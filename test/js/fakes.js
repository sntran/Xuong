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

// A VM that checks an order with a blueprint "box", and counts the builds.
export function vm() {
  const calls = [];
  const fn = async (request, hash) => {
    const url = new URL(request.url);
    calls.push(url.pathname + url.search);
    if (url.pathname === '/build') assert.equal(hash, HASH);
    if (url.pathname === '/blueprints') return Response.json(BLUEPRINTS);
    const order = await request.json();
    if (order.blueprint !== 'box') return Response.json({ errors: [{ path: 'blueprint', message: 'no' }] }, { status: 422 });
    if (url.pathname === '/check') return Response.json({ hash: HASH, order: { ...order, full: true } });
    if (order.joints?.bad) return Response.json({ errors: [{ path: 'joints.bad', message: 'no' }] }, { status: 422 });
    return new Response(`${url.searchParams.get('level')} ${url.searchParams.get('file')}`);
  };
  fn.calls = calls;
  return fn;
}
