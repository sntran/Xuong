// The store of the orders: a port program of the VM (BEAM.com, "Ports to
// bindings"). worker.js gives it to the object of the VM as the binding
// ORDER_STORE, with the R2 bucket ORDERS, and scripts/order-store.mjs
// runs it on this computer with a folder. World.Orders.Store is the
// other side. The arguments:
//
// - get KEY: the result is the full order, or nothing when the store has
//   no order of the key (an order is never empty).
// - put KEY LENGTH: the order comes on the input, with this length. The
//   result is "ok".
//
// An error ends the port with the exit status 1.

// The keys of World.Orders.Store: orders/HASH.json.
const KEY = /^orders\/[0-9a-f]{32}\.json$/;

const key = (value) => {
  if (!KEY.test(value ?? '')) throw new Error(`not a key of an order: ${value}`);
  return value;
};

const text = (value) => new Response(value).body;

// The first `total` bytes of the input. The VM does not end the input
// of a port, so the length comes in the arguments.
async function read(stdin, total) {
  const bytes = new Uint8Array(total);
  const reader = stdin.getReader();
  let n = 0;
  while (n < total) {
    const { value, done } = await reader.read();
    if (done) throw new Error(`the input ended after ${n} of ${total} bytes`);
    const part = value.subarray(0, total - n);
    bytes.set(part, n);
    n += part.byteLength;
  }
  reader.releaseLock();
  return bytes;
}

// bucket: an R2 bucket, or an object with the same get and put.
export const orderStore = (bucket) => ({
  async port(stdin, { argv: [op, ...args] }) {
    if (op === 'get' && args.length === 1) {
      const object = await bucket.get(key(args[0]));
      return object ? object.body : text('');
    }
    if (op === 'put' && args.length === 2) {
      const length = Number(args[1]);
      if (!Number.isSafeInteger(length) || length <= 0) throw new Error(`not a length: ${args[1]}`);
      await bucket.put(key(args[0]), await read(stdin, length), { httpMetadata: { contentType: 'application/json' } });
      return text('ok\n');
    }
    throw new Error(`not an operation of the store: ${[op, ...args].join(' ')}`);
  },
});
