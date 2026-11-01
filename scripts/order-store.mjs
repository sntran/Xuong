#!/usr/bin/env node
// The store of the orders on this computer: the port program of
// World.Orders.Store in development and in the tests. It runs the code
// of the Worker (order_store.js) with a folder in place of the R2
// bucket: WORLD_ORDER_DIR.
//
//   WORLD_ORDER_DIR=tmp/orders scripts/order-store.mjs get orders/HASH.json
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { orderStore } from '../order_store.js';

const write = (part) => new Promise((resolve) => process.stdout.write(part, resolve));

const dir = process.env.WORLD_ORDER_DIR;

const folder = {
  async get(key) {
    const bytes = await readFile(join(dir, key)).catch(() => null);
    return bytes && { body: new Response(bytes).body };
  },
  async put(key, bytes) {
    await mkdir(dirname(join(dir, key)), { recursive: true });
    await writeFile(join(dir, key), bytes);
  },
};

// An error ends the port with the exit status 1, as at the edge.
process.stdout.on('error', () => process.exit(1));
try {
  if (!dir) throw new Error('no WORLD_ORDER_DIR');
  const result = await orderStore(folder).port(Readable.toWeb(process.stdin), { argv: process.argv.slice(2) });
  for await (const part of result) await write(part);
  process.exit(0);
} catch {
  process.exit(1);
}
