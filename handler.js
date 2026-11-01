// The routes of the factory that are not static files (docs/factory.md,
// "The URLs"). The static files of site/ (the catalog, the review page)
// go out before the Worker runs. The VM of World (World.Service) has the
// orders, their store and the MCP server; this file keeps the files that
// the VM built, so that a file goes out of R2 with no VM. handler() takes:
//
// - vm(request, hash): the VM of World. The hash of the order, when there
//   is one, chooses the builder;
// - env.ORDERS: the R2 bucket. builds/COMMIT/FILE is a file that the VM
//   built at the commit COMMIT. The VM keeps the full orders in the same
//   bucket (orders/HASH.json, World.Orders.Store);
// - commit: the commit of the deploy (site/version.json). A new deploy
//   builds each file again at its first request, so a correction of
//   World reaches each order.
//
// The routes:
//
// - GET /blueprints: the blueprints and their options (the VM).
// - POST /orders: an order in JSON (the VM). 200 with the hash, the full
//   order, the URLs of its files and the URL of its replay page; 422
//   with the errors.
// - /mcp: the MCP server (the VM, World.MCP).
// - GET /o/HASH.glb, .mid.glb, .far.glb, .parts.json, .receipt.json,
//   .log.json, .replay.glb: the files of an order of POST /orders. The
//   people of the world build the model (World.Run): the log tells what
//   each one did, and the replay GLB has a node for each part.
// - GET /m/BLUEPRINT.glb (and the other files) ?OPTION=VALUE&color.ROLE=
//   %23rrggbb&joint.NAME=DEGREES&target.LIMB=X,Y,Z: an order in the URL. A list is
//   VALUE,VALUE, and OPTION.FIELD=VALUE is a field of an object.
//
// The Worker gives the VM the header x-world-origin (the start of the
// URLs of an order). When the VM stops (an order that needs more memory
// than the edge has), the answer is 503 with the errors in JSON, and the
// next request starts the VM again.

const CACHE = 'public, max-age=300, stale-while-revalidate=86400';

// The suffix of each file: the level and the file of /build.
const FILES = [
  ['.mid.glb', 'mid', 'glb', 'model/gltf-binary'],
  ['.far.glb', 'far', 'glb', 'model/gltf-binary'],
  ['.parts.json', 'near', 'parts', 'application/json'],
  ['.receipt.json', 'near', 'receipt', 'application/json'],
  ['.log.json', 'near', 'log', 'application/json'],
  ['.replay.glb', 'near', 'replay', 'model/gltf-binary'],
  ['.glb', 'near', 'glb', 'model/gltf-binary'],
];

const HASH = /^[0-9a-f]{32}$/;

const headers = (extra = {}) => ({
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id',
  ...extra,
});

const json = (status, body, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: headers({ 'content-type': 'application/json', ...extra }) });

const errors = (status, message) => json(status, { errors: [{ path: '', message }] });

// The name and the file of a path: "ford.mid.glb" is ["ford", FILES[0]].
export function split(name) {
  for (const file of FILES) {
    if (name.endsWith(file[0]) && name.length > file[0].length) return [name.slice(0, -file[0].length), file];
  }
  return null;
}

// The order of a URL /m/BLUEPRINT.EXT?...: color.ROLE, joint.NAME and
// target.LIMB (a point X,Y,Z: the order has targets only with one), and
// the options. OPTION.FIELD is a field of an option that is an object
// (origin.asian=1).
export function orderOf(blueprint, params) {
  const order = { blueprint, options: {}, colors: {}, joints: {} };
  for (const [key, value] of params) {
    if (key.startsWith('color.')) order.colors[key.slice(6)] = value;
    else if (key.startsWith('joint.')) order.joints[key.slice(6)] = Number(value);
    else if (key.startsWith('target.')) (order.targets ??= {})[key.slice(7)] = value.split(',').map(Number);
    else if (key.includes('.')) {
      const [option, field] = key.split('.', 2);
      const object = typeof order.options[option] === 'object' ? order.options[option] : {};
      order.options[option] = { ...object, [field]: value };
    } else order.options[key] = value;
  }
  return order;
}

async function check(vm, order) {
  const r = await vm(new Request('http://vm/check', { method: 'POST', body: JSON.stringify(order) }));
  return { status: r.status, body: await r.json() };
}

// A request of the client to the VM, with its method, its body, the
// headers that the VM reads, and the origin of the URLs.
async function forward(request, vm, origin, path) {
  const keep = ['content-type', 'mcp-protocol-version'].filter((name) => request.headers.has(name));
  const ask = new Headers(keep.map((name) => [name, request.headers.get(name)]));
  ask.set('x-world-origin', origin);
  const body = request.method === 'GET' || request.method === 'HEAD' ? undefined : await request.arrayBuffer();
  const r = await vm(new Request(`http://vm${path}`, { method: request.method, headers: ask, body }));
  const extra = Object.fromEntries(['content-type', 'allow'].filter((name) => r.headers.has(name)).map((name) => [name, r.headers.get(name)]));
  return new Response(r.status === 202 ? null : r.body, { status: r.status, headers: headers(extra) });
}

// A file of an order: from R2, else from the VM (then into R2). order is
// the full order, or null for an order of POST /orders, which the VM
// reads from its store by the hash.
async function file(request, env, vm, commit, hash, order, [, level, kind, type]) {
  const key = `builds/${commit}/${hash}.${level}.${kind}`;
  let object = await env.ORDERS.get(key);
  if (!object) {
    const url = `http://vm/build?level=${level}&file=${kind}${order ? '' : `&hash=${hash}`}`;
    const r = await vm(new Request(url, { method: 'POST', body: order ? JSON.stringify(order) : undefined }), hash);
    if (r.status !== 200) return new Response(r.body, { status: r.status, headers: headers({ 'content-type': 'application/json' }) });
    await env.ORDERS.put(key, await r.arrayBuffer(), { httpMetadata: { contentType: type } });
    object = await env.ORDERS.get(key);
  }
  const etag = object.httpEtag;
  const extra = { etag, 'cache-control': CACHE, 'x-world-commit': commit, 'x-world-order': hash };
  if (request.headers.get('if-none-match') === etag) return new Response(null, { status: 304, headers: headers(extra) });
  return new Response(object.body, { headers: headers({ 'content-type': type, ...extra }) });
}

export async function handler(request, env, options) {
  try {
    return await route(request, env, options);
  } catch {
    return json(503, { errors: [{ path: '', message: 'the builder stopped: the order needs more memory than the edge has, or the VM failed' }] }, { 'retry-after': '10' });
  }
}

async function route(request, env, { vm, commit }) {
  const url = new URL(request.url);
  const path = url.pathname;

  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: headers({ 'access-control-max-age': '86400' }) });

  if (path === '/blueprints' && request.method === 'GET') {
    const r = await vm(new Request('http://vm/blueprints'));
    return new Response(r.body, { status: r.status, headers: headers({ 'content-type': 'application/json', 'cache-control': CACHE }) });
  }

  if (path === '/orders' && request.method === 'POST') return forward(request, vm, url.origin, '/orders');

  if (path === '/mcp') return forward(request, vm, url.origin, '/mcp');

  if (request.method !== 'GET' && request.method !== 'HEAD') return errors(405, 'the method is not allowed');

  if (path.startsWith('/o/')) {
    const parts = split(path.slice(3));
    if (!parts || !HASH.test(parts[0])) return errors(404, 'no such file');
    return file(request, env, vm, commit, parts[0], null, parts[1]);
  }

  if (path.startsWith('/m/')) {
    const parts = split(path.slice(3));
    if (!parts) return errors(404, 'no such file');
    const { status, body } = await check(vm, orderOf(parts[0], url.searchParams));
    if (status !== 200) return json(status, body);
    return file(request, env, vm, commit, body.hash, body.order, parts[1]);
  }

  return errors(404, 'no such page');
}
