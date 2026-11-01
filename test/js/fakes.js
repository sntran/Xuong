// A fake VM and a fake R2 bucket for the tests of handler.js and mcp.js.
import assert from 'node:assert/strict';

export const HASH = '0123456789abcdef0123456789abcdef';

// The blueprints of the fake VM.
export const BLUEPRINTS = [{ name: 'box', doc: 'A box.', options: [{ name: 'size', type: 'float', default: 1, unit: 'm' }] }];

// A bucket in memory, with the API of R2 that handler.js uses.
export function bucket() {
  const items = new Map();
  return {
    items,
    async get(key) {
      if (!items.has(key)) return null;
      const bytes = items.get(key);
      return {
        httpEtag: `"${key.length}-${bytes.byteLength}"`,
        body: bytes,
        async json() { return JSON.parse(new TextDecoder().decode(bytes)); },
      };
    },
    async put(key, value) {
      items.set(key, typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value));
    },
  };
}

// A VM that checks an order with a blueprint "box", keeps the orders of
// /orders (by their hash), answers /mcp, and counts the builds.
export function vm() {
  const calls = [];
  const orders = new Map();
  const fn = async (request, hash) => {
    const url = new URL(request.url);
    calls.push(url.pathname + url.search);
    fn.last = request;
    if (url.pathname === '/build') assert.equal(hash, HASH);
    if (url.pathname === '/blueprints') return Response.json(BLUEPRINTS);
    if (url.pathname === '/mcp') {
      if (request.method !== 'POST') return Response.json({ jsonrpc: '2.0', id: null, error: { code: -32000 } }, { status: 405, headers: { allow: 'POST' } });
      const message = await request.json();
      if (!('id' in message)) return new Response('', { status: 202 });
      return Response.json({ jsonrpc: '2.0', id: message.id, result: { version: request.headers.get('mcp-protocol-version') } });
    }
    if (url.searchParams.has('hash')) {
      if (!orders.has(url.searchParams.get('hash'))) return Response.json({ errors: [{ path: '', message: 'no such order' }] }, { status: 404 });
      return new Response(`${url.searchParams.get('level')} ${url.searchParams.get('file')}`);
    }
    let order;
    try {
      order = await request.json();
    } catch {
      return Response.json({ errors: [{ path: '', message: 'the body is not JSON' }] }, { status: 400 });
    }
    if (order.blueprint !== 'box') return Response.json({ errors: [{ path: 'blueprint', message: 'no' }] }, { status: 422 });
    if (url.pathname === '/check') return Response.json({ hash: HASH, order: { ...order, full: true } });
    if (url.pathname === '/orders') {
      orders.set(HASH, order);
      const origin = request.headers.get('x-world-origin');
      return Response.json({ hash: HASH, order, files: { glb: `${origin}/o/${HASH}.glb` }, replay: `${origin}/replay.html?order=${HASH}` });
    }
    if (order.joints?.bad) return Response.json({ errors: [{ path: 'joints.bad', message: 'no' }] }, { status: 422 });
    return new Response(`${url.searchParams.get('level')} ${url.searchParams.get('file')}`);
  };
  fn.calls = calls;
  fn.orders = orders;
  return fn;
}
