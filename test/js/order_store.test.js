// The tests of the store of the orders (order_store.js), with a fake R2
// bucket, and of its program on this computer (scripts/order-store.mjs).
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { orderStore } from '../../order_store.js';
import { bucket } from './fakes.js';

const KEY = 'orders/0123456789abcdef0123456789abcdef.json';

// An input of parts that stays open, as the input of a port of the VM;
// ended() is an input that ends after its parts.
const input = (...parts) => new ReadableStream({
  start(c) {
    for (const p of parts) c.enqueue(new TextEncoder().encode(p));
  },
});
const ended = (...parts) => new ReadableStream({
  start(c) {
    for (const p of parts) c.enqueue(new TextEncoder().encode(p));
    c.close();
  },
});

const text = (body) => new Response(body).text();

test('put keeps the order with its length, and get gives it back', async () => {
  const b = bucket();
  const store = orderStore(b);
  // The order comes in parts, and the VM does not end the input: the
  // store reads its length only.
  assert.equal(await text(await store.port(input('{"blue', 'print":"box"}', 'more'), { argv: ['put', KEY, '19'] })), 'ok\n');
  assert.equal(new TextDecoder().decode(b.items.get(KEY)), '{"blueprint":"box"}');
  assert.equal(await text(await store.port(input(), { argv: ['get', KEY] })), '{"blueprint":"box"}');
});

test('get of an order that the store does not have gives nothing', async () => {
  const store = orderStore(bucket());
  assert.equal(await text(await store.port(input(), { argv: ['get', KEY] })), '');
});

test('a wrong key, length, operation or input is an error', async () => {
  const store = orderStore(bucket());
  const fails = (argv, stdin = input()) => assert.rejects(store.port(stdin, { argv }));
  await fails(['get', '../x']);
  await fails(['get']);
  await fails(['put', KEY, '0']);
  await fails(['put', KEY, 'x']);
  await fails(['put', 'orders/x.json', '2']);
  await fails(['put', KEY, '9'], ended('{}'));
  await fails(['delete', KEY]);
});

test('the program on this computer keeps the orders in a folder', () => {
  const dir = mkdtempSync(join(tmpdir(), 'world-orders-'));
  const env = { ...process.env, WORLD_ORDER_DIR: dir };
  const program = new URL('../../scripts/order-store.mjs', import.meta.url).pathname;
  assert.equal(execFileSync(program, ['put', KEY, '2'], { env, input: '{}' }).toString(), 'ok\n');
  assert.equal(execFileSync(program, ['get', KEY], { env }).toString(), '{}');
  assert.equal(execFileSync(program, ['get', KEY.replace('0123', 'ffff')], { env }).toString(), '');
  assert.equal(spawnSync(program, ['get', '../x'], { env }).status, 1);
  assert.equal(spawnSync(program, ['get', KEY], { env: { PATH: process.env.PATH } }).status, 1);
  rmSync(dir, { recursive: true });
});
