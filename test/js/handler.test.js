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

test('POST /orders keeps the full order and gives the URLs of its files', async () => {
  const env = { ORDERS: bucket() };
  const r = await handler(req('/orders', { method: 'POST', body: JSON.stringify({ blueprint: 'box' }) }), env, { vm: vm(), commit: 'c1' });
  assert.equal(r.status, 200);
  assert.equal(r.headers.get('access-control-allow-origin'), '*');
  const body = await r.json();
  assert.equal(body.hash, HASH);
  assert.equal(body.files['mid.glb'], `https://world.mkfifo.com/o/${HASH}.mid.glb`);
  assert.equal(body.files['log.json'], `https://world.mkfifo.com/o/${HASH}.log.json`);
  assert.equal(body.replay, `https://world.mkfifo.com/replay.html?order=${HASH}`);
  assert.ok(env.ORDERS.items.has(`orders/${HASH}.json`));
});

test('POST /orders gives the errors of a wrong order, and 400 for a body that is not JSON', async () => {
  const env = { ORDERS: bucket() };
  const wrong = await handler(req('/orders', { method: 'POST', body: '{"blueprint":"x"}' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(wrong.status, 422);
  assert.equal((await wrong.json()).errors[0].path, 'blueprint');
  const bad = await handler(req('/orders', { method: 'POST', body: 'nope' }), env, { vm: vm(), commit: 'c1' });
  assert.equal(bad.status, 400);
});

test('GET /o/ builds a file one time, then serves it from R2, with an ETag', async () => {
  const env = { ORDERS: bucket() };
  const v = vm();
  await env.ORDERS.put(`orders/${HASH}.json`, JSON.stringify({ blueprint: 'box' }));
  const first = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(first.status, 200);
  assert.equal(first.headers.get('content-type'), 'model/gltf-binary');
  assert.equal(first.headers.get('x-world-commit'), 'c1');
  assert.equal(await first.text(), 'mid glb');
  const etag = first.headers.get('etag');

  const second = await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c1' });
  assert.equal(await second.text(), 'mid glb');
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 1);

  const same = await handler(req(`/o/${HASH}.mid.glb`, { headers: { 'if-none-match': etag } }), env, { vm: v, commit: 'c1' });
  assert.equal(same.status, 304);

  // A new deploy builds the file again.
  await handler(req(`/o/${HASH}.mid.glb`), env, { vm: v, commit: 'c2' });
  assert.equal(v.calls.filter((c) => c.startsWith('/build')).length, 2);

  const receipt = await handler(req(`/o/${HASH}.receipt.json`), env, { vm: v, commit: 'c1' });
  assert.equal(await receipt.text(), 'near receipt');
});

test('GET /o/ of an order that is not in R2, or of a wrong name, is 404', async () => {
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
