// The Worker of https://world.mkfifo.com (docs/factory.md). The static files
// of site/ (the review page and the catalog) go out before the Worker
// runs. The other requests go to handler.js: the orders, with their
// files in R2, and the VM of World for each file that R2 does not have.
//
// The VM is edge.com (scripts/edge.sh): the release of World for the
// WebAssembly runtime of the npm package beam.com, with WORLD_SERVER=true
// (wrangler.jsonc), so World.Service answers on port 4000. The VM runs
// in the Durable Object Beam: the builds of one order go to one object,
// so the object builds it one time and the next request finds it in R2.
import app from './edge.com' with { type: 'bytes' };
import { Beam as BeamObject, serve } from 'beam.com';
import version from './site/version.json';
import { handler } from './handler.js';
import { orderStore } from './order_store.js';

// The VM gets one port, a plain object with port(), so it needs no other
// Worker: /env/ORDER_STORE, the store of the orders with the R2 bucket
// ORDERS (order_store.js, World.Orders.Store).
export class Beam extends BeamObject {
  constructor(ctx, env) {
    super(ctx, { ...env, ORDER_STORE: orderStore(env.ORDERS) });
  }
}

// The object of a request: one of 4 builders, from the first digit of
// the hash of the order, so the builds of one order go to one builder.
// A request with no order (/blueprints, /check) goes to any builder.
const builders = serve(app, {
  name: (request) => `builder-${parseInt(request.headers.get('x-world-builder') ?? '0', 16) % 4}`,
});

export default {
  fetch(request, env, ctx) {
    const vm = (r, hash) => {
      r.headers.set('x-world-builder', hash?.[0] ?? Math.floor(Math.random() * 16).toString(16));
      return builders.fetch(r, env, ctx);
    };
    return handler(request, env, { vm, commit: version.commit });
  },
};
