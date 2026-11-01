// The MCP server of the factory at /mcp (docs/factory.md, "The MCP
// server"): an MCP client of another project finds the blueprints,
// checks an order and places it, with the tools of the Model Context
// Protocol.
//
// The transport is the Streamable HTTP of MCP, with no state: each POST
// is one JSON-RPC message, and the answer is one JSON message (no event
// stream and no session). GET and DELETE give 405. A notification or a
// response from the client gives 202 with no body.
//
// mcp() takes the request and the factory:
//
// - blueprints(): the blueprints, as GET /blueprints gives them;
// - check(order): {status, body} of the check of the VM (POST /check);
// - place(order): {status, body} of POST /orders: the order goes into R2,
//   and the body has the URLs of its files;
// - commit: the commit of the deploy, the version of the server.

// The versions of the protocol that this server knows, the newest first.
export const VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];

const INSTRUCTIONS = `World is a factory of 3D models (GLB). An order is JSON data: a blueprint and its options, colors and joints.
1. Call list_blueprints, then get_blueprint for the options of one blueprint.
2. Call check_order with the order until it has no errors. Each error has the path of the wrong value and the rule.
3. Call place_order. The answer has the hash of the order and the URLs of its files: the GLB at the near, mid and far levels, the list of the parts, the receipt, and the log of the people of the world that built it.
The factory builds each file at its first GET (this can take some seconds; 503 means that the order needs more memory than the edge has), and keeps it. The same order always gives the same hash and the same URLs.`;

// The schema of an order (docs/factory.md, "The URLs").
const ORDER = {
  type: 'object',
  description: 'An order: {"blueprint": NAME, "options": {...}, "colors": {ROLE: "#rrggbb"}, "joints": {NAME: DEGREES}, "targets": {LIMB: [X, Y, Z]}}. Only "blueprint" is necessary: each option that the order does not give has its default.',
  properties: {
    blueprint: { type: 'string', description: 'The name of a blueprint (list_blueprints).' },
    options: { type: 'object', description: 'The options of the blueprint (get_blueprint), by their names.' },
    colors: { type: 'object', description: 'A color for each material role, as "#rrggbb".' },
    joints: { type: 'object', description: 'The angle of each joint, in degrees.' },
    targets: { type: 'object', description: 'The end of each limb, as a point [x, y, z] in meters.' },
  },
  required: ['blueprint'],
};

const READ = { readOnlyHint: true, openWorldHint: false };

export const TOOLS = [
  {
    name: 'list_blueprints',
    title: 'List the blueprints',
    description: 'Gives the name and the description of each blueprint of the factory. A blueprint is a family of models with options (van, person, house, animal, catalog, drawing, and more).',
    inputSchema: { type: 'object', properties: {} },
    annotations: READ,
  },
  {
    name: 'get_blueprint',
    title: 'Get a blueprint',
    description: 'Gives the options of one blueprint: for each option, its type, default, unit, range, values or presets, and its description.',
    inputSchema: {
      type: 'object',
      properties: { name: { type: 'string', description: 'The name of the blueprint.' } },
      required: ['name'],
    },
    annotations: READ,
  },
  {
    name: 'check_order',
    title: 'Check an order',
    description: 'Checks an order and does not keep it. Gives the hash and the full order (with each default), or the errors: each error has the path of the wrong value and the rule.',
    inputSchema: { type: 'object', properties: { order: ORDER }, required: ['order'] },
    annotations: READ,
  },
  {
    name: 'place_order',
    title: 'Place an order',
    description: 'Checks an order and keeps it. Gives the hash, the full order, the URLs of its files (GLB at the near, mid and far levels, parts, receipt, log, replay GLB) and the URL of its replay page; or the errors. The factory builds each file at its first GET. The same order gives the same hash.',
    inputSchema: { type: 'object', properties: { order: ORDER }, required: ['order'] },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
];

const HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id',
};

const reply = (status, body) =>
  new Response(body === undefined ? null : JSON.stringify(body), {
    status,
    headers: body === undefined ? HEADERS : { ...HEADERS, 'content-type': 'application/json' },
  });

const failure = (id, code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });

// A tool result: the data as JSON text, and as structured content.
const result = (data, isError = false) => ({
  content: [{ type: 'text', text: JSON.stringify(data) }],
  structuredContent: data,
  ...(isError ? { isError: true } : {}),
});

const wrong = (message) => result({ errors: [{ path: '', message }] }, true);

export async function mcp(request, factory) {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...HEADERS, 'access-control-max-age': '86400' } });
  if (request.method !== 'POST') {
    return new Response(JSON.stringify(failure(null, -32000, 'use POST: this server sends no event stream')), {
      status: 405,
      headers: { ...HEADERS, allow: 'POST, OPTIONS', 'content-type': 'application/json' },
    });
  }

  const version = request.headers.get('mcp-protocol-version');
  if (version && !VERSIONS.includes(version)) return reply(400, failure(null, -32600, `the protocol version ${version} is not known; use one of ${VERSIONS.join(', ')}`));

  let message;
  try {
    message = await request.json();
  } catch {
    return reply(400, failure(null, -32700, 'the body is not JSON'));
  }

  if (message === null || typeof message !== 'object' || Array.isArray(message) || message.jsonrpc !== '2.0') {
    return reply(400, failure(null, -32600, 'the body is not one JSON-RPC 2.0 message'));
  }
  // A notification, or a response of the client: nothing to answer.
  if (!('id' in message) || typeof message.method !== 'string') return reply(202);

  const answer = await answerOf(message, factory);
  return reply(200, { jsonrpc: '2.0', id: message.id, ...answer });
}

async function answerOf({ id, method, params = {} }, factory) {
  switch (method) {
    case 'initialize':
      return {
        result: {
          protocolVersion: VERSIONS.includes(params.protocolVersion) ? params.protocolVersion : VERSIONS[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: 'world', title: 'World, the factory of 3D models', version: factory.commit },
          instructions: INSTRUCTIONS,
        },
      };
    case 'ping':
      return { result: {} };
    case 'tools/list':
      return { result: { tools: TOOLS } };
    case 'tools/call': {
      const tool = TOOLS.find((t) => t.name === params.name);
      if (!tool) return failure(id, -32602, `no tool ${params.name}; the tools are ${TOOLS.map((t) => t.name).join(', ')}`);
      try {
        return { result: await call(tool.name, params.arguments ?? {}, factory) };
      } catch {
        return { result: wrong('the builder stopped: the VM failed, or the order needs more memory than the edge has; try again later') };
      }
    }
    default:
      return failure(id, -32601, `no method ${method}`);
  }
}

async function call(name, args, factory) {
  if (name === 'list_blueprints') {
    const all = await factory.blueprints();
    return result({ blueprints: all.map(({ name, doc }) => ({ name, doc })) });
  }

  if (name === 'get_blueprint') {
    const all = await factory.blueprints();
    const blueprint = all.find((b) => b.name === args.name);
    if (!blueprint) return wrong(`no blueprint ${args.name}; the blueprints are ${all.map((b) => b.name).join(', ')}`);
    return result(blueprint);
  }

  const order = args.order;
  if (order === null || typeof order !== 'object' || Array.isArray(order)) return wrong('the argument "order" must be a JSON object');
  const { status, body } = await (name === 'check_order' ? factory.check(order) : factory.place(order));
  return result(body, status !== 200);
}
