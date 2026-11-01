// The tests of handler.js, with a fake VM and a fake R2 bucket.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handler, orderOf, split } from '../../handler.js';
import { BLUEPRINTS, HASH, bucket, vm } from './fakes.js';

const req = (path, init) => new Request(`https://world.mkfifo.com${path}`, init);

test('the name and the file of a path', () => {
  assert.deepEqual(split('van.mid.glb')[0], 'van');
  assert.equal(split('van.mid.glb')[1][1], 'mid');
  assert.equal(split('van.glb')[1][1], 'near');
  assert.equal(split('van.receipt.json')[1][2], 'receipt');
  assert.equal(split('van.log.json')[1][2], 'log');
  assert.deepEqual(split('van.replay.glb').map((x, i) => (i ? x[2] : x)), ['van', 'replay']);
  assert.equal(split('.glb'), null);
  assert.equal(split('van.txt'), null);
});

test('an order from a URL', () => {
  const order = orderOf('van', new URLSearchParams('make=ford&color.paint=%23ff0000&joint.hood=50&gear=a,b'));
  assert.deepEqual(order, { blueprint: 'van', options: { make: 'ford', gear: 'a,b' }, colors: { paint: '#ff0000' }, joints: { hood: 50 } });
  const person = orderOf('traveler', new URLSearchParams('origin.asian=0.5&origin.african=0.5&vehicle=car'));
  assert.deepEqual(person.options, { origin: { asian: '0.5', african: '0.5' }, vehicle: 'car' });
  const reach = orderOf('person', new URLSearchParams('target.arm_r=0.3,0.4,1.3&joint.elbow_l=90'));
  assert.deepEqual(reach.targets, { arm_r: [0.3, 0.4, 1.3] });
  assert.deepEqual(reach.joints, { elbow_l: 90 });
});

test('POST /orders goes to the VM, with the origin of the URLs', async () => {
  const v = vm();
  const r = await handler(req('/orders', { method: 'POST', headers: { 'content-type': 'application/json', 'x-world-origin': 'https://evil.example' }, body: JSON.stringify({ blueprint: 'box' }) }), { ORDERS: bucket() }, { vm: v, commit: 'c1' });
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.equal(r.headers.get('content-type'), 'application/json');
  const body = await r.json();
  assert.equal(body.hash, HASH);
  // The Worker gives the origin, not the client.
  assert.equal(body.files.glb, `https://world.mkfifo.com/o/${HASH}.glb`);
  assert.equal(body.replay, `https://world.mkfifo.com/replay.html?order=${HASH}`);
  assert.equal(v.last.headers.get('content-type'), 'application/json');
  assert.ok(v.orders.has(HASH));
});

test('POST /orders gives the errors of the VM: 422 for a wrong order, 400 for a body that is not JSON', async () => {
  const env = { ORDERS: bucket() };
  const wrong = await handler(req('/orders', { method: 'POST', body: '{"blueprint":"x"}' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  assert.equal((await wrong.json()).errors[0].path, 'blueprint');
  const bad = await handler(req('/orders', { method: 'POST', body: 'nope' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(bad.status, 400);
});

test('/mcp goes to the VM: the body, the version of the protocol, 202 with no body, and 405', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  const call = (body, headers = {}) => handler(req('/mcp', { method: 'POST', headers, body: JSON.stringify(body) }), env, { vm: v, commit: 'c1' });

  const ping = await call({ jsonrpc: '2.0', id: 1, method: 'ping' }, { 'mcp-protocol-version': '2025-06-18', cookie: 'a=b' });
  assert.equal(ping.status, 200);
  assert.equal(ping.headers.get('access-control-allow-origin'), '*');
  assert.deepEqual(await ping.json(), { jsonrpc: '2.0', id: 1, result: { version: '2025-06-18' } });
  assert.equal(v.last.headers.get('x-world-origin'), 'https://world.mkfifo.com');
  assert.equal(v.last.headers.get('cookie'), null);

  const note = await call({ jsonrpc: '2.0', method: 'notifications/initialized' });
  assert.equal(note.status, 202);
  assert.equal(await note.text(), '');

  for (const method of ['GET', 'DELETE']) {
    const r = await handler(req('/mcp', { method }), env, { vm: v, commit: 'c1' });
    assert.equal(r.status, 405);
    assert.equal(r.headers.get('allow'), 'POST');
  }

  const options = await handler(req('/mcp', { method: 'OPTIONS' }), env, { vm: v, commit: 'c1' });
  assert.equal(options.status, 204);
  assert.match(options.headers.get('access-control-allow-headers'), /mcp-protocol-version/);
});

test('GET /o/ builds a file one time, then serves it from R2, with an ETag', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  v.orders.set(HASH, { blueprint: 'box' });
  const first = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('content-type'), 'model/gltf-binary');
  assert.equal(first.headers.get('x-world-commit'), 'c1');
  assert.equal(await first.text(), 'mid glb');
  const etag = first.headers.get('etag');

  const second = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(await second.text(), 'mid glb');
  assert.deepEqual(v.calls.filter((c) => c.startsWith('/build')), [`/build?level=mid&file=glb&hash=${HASH}`]);

  const same = await handler(req(`/o/${HASH}.mid.glb`, { headers: { 'if-none-match': etag } }), env, { vm: v, commit: 'c1' });
  assert.equal(same.status, 304);

  // A new deploy builds the file again.
  await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c2' });
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 2);

  const receipt = await handler(req(`/o/${HASH}.receipt.json`), env, { vm: v, commit: 'c1' });
  assert.equal(await receipt.text(), 'near receipt');
});

test('GET /o/ of an order that the VM does not have, or of a wrong name, is 404', async () => {
  const env = { ORDERS: bucket() };
  assert.equal((await handler(req(`/o/${HASH}.glb`), env, { vm: vm(), commit: 'c1' })).status, 404);
  assert.equal((await handler(req('/o/xyz.glb'), env, { vm: vm(), commit: 'c1' })).status, 404);
  assert.equal((await handler(req(`/o/${HASH}.txt`), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('GET /m/ checks the order of the URL, then builds it', async () => {
  const env = { ORDERS: bucket() };
  const ok = await handler(req('/m/box.far.glb?size=2'), env, { vm: vm(), commit: 'c1' });
  assert.equal(await ok.text(), 'far glb');
  const wrong = await handler(req('/m/ball.glb'), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  const joint = await handler(req('/m/box.glb?joint.bad=1'), env, { vm: vm(), commit: 'c1' });
  assert.equal(joint.status, 422);
  assert.equal((await handler(req('/m/box'), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('the other routes', async () => {
  const env = { ORDERS: bucket() };
  const blueprints = await handler(req('/blueprints'), env, { vm: vm(), commit: 'c1' });
  assert.deepEqual(await blueprints.json(), BLUEPRINTS);
  const options = await handler(req('/orders', { method: 'OPTIONS' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(options.status, 204);
  assert.equal(options.headers.get('access-control-allow-methods'), 'GET, POST, OPTIONS');
  assert.equal((await handler(req('/o/x', { method: 'DELETE' }), env, { vm: vm(), commit: 'c1' })).status, 405);
  assert.equal((await handler(req('/nope'), env, { vm: vm(), commit: 'c1' })).status, 404);
});

test('a VM that stops gives 503 with the errors', async () => {
  const stops = async () => {
    throw new Error('the object stopped');
  };
  const r = await handler(req('/m/box.glb'), { ORDERS: bucket() }, { vm: stops, commit: 'c1' });
  assert.equal(r.status, 503);
  assert.equal(r.headers.get('retry-after'), '10');
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  assert.match((await r.json()).errors[0].message, /the builder stopped/);
});
