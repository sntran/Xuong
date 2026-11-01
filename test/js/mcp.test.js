// The tests of the MCP server (mcp.js), through handler.js, with a fake
// VM and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handler } from '../../handler.js';
import { TOOLS, VERSIONS, mcp } from '../../mcp.js';
import { BLUEPRINTS, HASH, bucket, vm } from './fakes.js';

const post = (body, headers = {}) =>
  new Request('https://world.mkfifo.com/mcp', {
    method: 'POST',
    headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

// One JSON-RPC request to the server: the HTTP answer and its body.
async function rpc(method, params, { env = { ORDERS: bucket() }, v = vm(), headers } = {}) {
  const r = await handler(post({ jsonrpc: '2.0', id: 7, method, ...(params ? { params } : {}) }, headers), env, { vm: v, commit: 'c1' });
  return { r, body: await r.json() };
}

const call = (name, args, options) => rpc('tools/call', { name, arguments: args }, options);

test('initialize gives the version of the client when the server knows it, else the newest', async () => {
  const { r, body } = await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 't', version: '1' } });
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('content-type'), 'application/json');
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.equal(r.headers.get('mcp-session-id'), null);
  assert.equal(body.jsonrpc, '2.0');
  assert.equal(body.id, 7);
  assert.equal(body.result.protocolVersion, '2025-06-18');
  assert.deepEqual(body.result.capabilities, { tools: { listChanged: false } });
  assert.equal(body.result.serverInfo.name, 'world');
  assert.equal(body.result.serverInfo.version, 'c1');
  assert.match(body.result.instructions, /place_order/);

  const newer = await rpc('initialize', { protocolVersion: '2099-01-01' });
  assert.equal(newer.body.result.protocolVersion, VERSIONS[0]);
  const none = await rpc('initialize');
  assert.equal(none.body.result.protocolVersion, VERSIONS[0]);
});

test('ping, and the list of the tools', async () => {
  assert.deepEqual((await rpc('ping')).body.result, {});
  const { body } = await rpc('tools/list', {});
  assert.deepEqual(body.result.tools.map((t) => t.name), ['list_blueprints', 'get_blueprint', 'check_order', 'place_order']);
  for (const tool of body.result.tools) {
    assert.equal(tool.inputSchema.type, 'object');
    assert.equal(typeof tool.description, 'string');
  }
  assert.equal(TOOLS.find((t) => t.name === 'place_order').annotations.readOnlyHint, false);
});

test('list_blueprints gives the name and the description of each blueprint', async () => {
  const { body } = await call('list_blueprints', {});
  assert.equal(body.result.isError, undefined);
  assert.deepEqual(body.result.structuredContent, { blueprints: [{ name: 'box', doc: 'A box.' }] });
  assert.deepEqual(JSON.parse(body.result.content[0].text), body.result.structuredContent);
  // A call with no arguments.
  const bare = await rpc('tools/call', { name: 'list_blueprints' });
  assert.equal(bare.body.result.structuredContent.blueprints.length, 1);
});

test('get_blueprint gives the options of one blueprint, or the names of the blueprints', async () => {
  const { body } = await call('get_blueprint', { name: 'box' });
  assert.deepEqual(body.result.structuredContent, BLUEPRINTS[0]);
  const wrong = await call('get_blueprint', { name: 'ball' });
  assert.equal(wrong.body.result.isError, true);
  assert.match(wrong.body.result.structuredContent.errors[0].message, /no blueprint ball; the blueprints are box/);
});

test('check_order gives the full order and keeps nothing; a wrong order gives its errors', async () => {
  const env = { ORDERS: bucket() };
  const { body } = await call('check_order', { order: { blueprint: 'box' } }, { env });
  assert.deepEqual(body.result.structuredContent, { hash: HASH, order: { blueprint: 'box', full: true } });
  assert.equal(env.ORDERS.items.size, 0);

  const wrong = await call('check_order', { order: { blueprint: 'ball' } }, { env });
  assert.equal(wrong.r.status, 200);
  assert.equal(wrong.body.result.isError, true);
  assert.deepEqual(wrong.body.result.structuredContent.errors, [{ path: 'blueprint', message: 'no' }]);
});

test('place_order keeps the order and gives the URLs of its files, as POST /orders', async () => {
  const env = { ORDERS: bucket() };
  const { body } = await call('place_order', { order: { blueprint: 'box' } }, { env });
  const placed = body.result.structuredContent;
  assert.equal(placed.hash, HASH);
  assert.equal(placed.files['glb'], `https://world.mkfifo.com/o/${HASH}.glb`);
  assert.equal(placed.files['far.glb'], `https://world.mkfifo.com/o/${HASH}.far.glb`);
  assert.equal(placed.replay, `https://world.mkfifo.com/replay.html?order=${HASH}`);
  assert.ok(env.ORDERS.items.has(`orders/${HASH}.json`));

  const rest = await handler(new Request('https://world.mkfifo.com/orders', { method: 'POST', body: '{"blueprint":"box"}' }), { ORDERS: bucket() }, { vm: vm(), commit: 'c1' });
  assert.deepEqual(await rest.json(), placed);

  // The file of the order builds at its first GET.
  const glb = await handler(new Request(placed.files['mid.glb']), env, { vm: vm(), commit: 'c1' });
  assert.equal(await glb.text(), 'mid glb');

  const wrong = await call('place_order', { order: { blueprint: 'ball' } }, { env });
  assert.equal(wrong.body.result.isError, true);
  assert.equal(env.ORDERS.items.size, 2);
});

test('an order that is not a JSON object is a tool error', async () => {
  for (const order of [undefined, null, 'box', [1], 3]) {
    const { body } = await call('place_order', order === undefined ? {} : { order });
    assert.equal(body.result.isError, true);
    assert.match(body.result.content[0].text, /must be a JSON object/);
  }
});

test('a VM that stops gives a tool error, not an HTTP error', async () => {
  const stops = async () => {
    throw new Error('the object stopped');
  };
  const { r, body } = await call('place_order', { order: { blueprint: 'box' } }, { v: stops });
  assert.equal(r.status, 200);
  assert.equal(body.result.isError, true);
  assert.match(body.result.structuredContent.errors[0].message, /the builder stopped/);
});

test('the errors of the protocol', async () => {
  const unknown = await rpc('resources/list');
  assert.deepEqual(unknown.body.error, { code: -32601, message: 'no method resources/list' });
  assert.equal(unknown.body.id, 7);

  const tool = await call('build_house', {});
  assert.equal(tool.body.error.code, -32602);
  assert.match(tool.body.error.message, /the tools are list_blueprints, get_blueprint, check_order, place_order/);

  const env = { ORDERS: bucket() };
  const opts = { vm: vm(), commit: 'c1' };
  const notJson = await handler(post('nope'), env, opts);
  assert.equal(notJson.status, 400);
  assert.equal((await notJson.json()).error.code, -32700);

  for (const body of [[{ jsonrpc: '2.0', id: 1, method: 'ping' }], { id: 1, method: 'ping' }, 'null']) {
    const r = await handler(post(body), env, opts);
    assert.equal(r.status, 400);
    assert.equal((await r.json()).error.code, -32600);
  }

  const version = await rpc('ping', undefined, { headers: { 'mcp-protocol-version': '1999-01-01' } });
  assert.equal(version.r.status, 400);
  assert.match(version.body.error.message, /1999-01-01 is not known/);
  const known = await rpc('ping', undefined, { headers: { 'mcp-protocol-version': '2025-06-18' } });
  assert.equal(known.r.status, 200);
});

test('a notification or a response of the client gives 202 with no body', async () => {
  const env = { ORDERS: bucket() };
  const opts = { vm: vm(), commit: 'c1' };
  for (const body of [{ jsonrpc: '2.0', method: 'notifications/initialized' }, { jsonrpc: '2.0', id: 3, result: {} }]) {
    const r = await handler(post(body), env, opts);
    assert.equal(r.status, 202);
    assert.equal(await r.text(), '');
  }
});

test('GET and DELETE give 405; OPTIONS gives the CORS headers of MCP', async () => {
  const env = { ORDERS: bucket() };
  const opts = { vm: vm(), commit: 'c1' };
  for (const method of ['GET', 'DELETE']) {
    const r = await handler(new Request('https://world.mkfifo.com/mcp', { method }), env, opts);
    assert.equal(r.status, 405);
    assert.equal(r.headers.get('allow'), 'POST, OPTIONS');
  }
  const options = await mcp(new Request('https://world.mkfifo.com/mcp', { method: 'OPTIONS' }), {});
  assert.equal(options.status, 204);
  assert.match(options.headers.get('access-control-allow-headers'), /mcp-protocol-version/);
});
