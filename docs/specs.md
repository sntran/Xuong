# The specifications of World

World builds each model as the real world does: people in a yard take
parts from a warehouse, drive them on a road to a factory, and build the
model task by task (`docs/world.md`). The people are processes. They act
at the same time, and the order of their acts changes from run to run.
A test sees one order of the acts. A specification sees all of them.

This document tells what World specifies, what the checks prove, what
they do not prove, and how to run them.

## The chain of the checks

Each order of the site goes through four checks. Each check covers a
gap that the one before it does not cover.

| Check | What it reads | What it proves | Where |
|---|---|---|---|
| 1. The model check | `specs/Order.tla`, a small model | In each possible order of the acts, the invariants hold, and each order is delivered in the end. | `test/world/order_spec_test.exs` |
| 2. The fault models | The same specification, with one rule removed or one size too small | The checker finds the fault. A check that cannot fail proves nothing. | the same test |
| 3. The replay | The log of a real run of the code | The code does only what the specification allows: each event of the log is one step of the specification, and the invariants hold after each step. | `test/support/order_spec.ex`, `test/world/run_test.exs` |
| 4. The log check | Each log, at each read | The events are in the order of their time, and each task starts once, after the tasks that it waits for. | `World.Log.check/1` |

The checks 1 and 2 prove the design. The check 3 ties the code to the
design. The check 4 runs on each log that the site gives, so a log that
breaks a rule never reaches a replay page.

## The specification: `specs/Order.tla`

One order: the supplier, the warehouse and its storekeeper, the truck
and its driver on the road, the dock of the factory, the workers and the
tasks of the plan, the files of the model, and the delivery.

### The constants

| Constant | What it is | From the code |
|---|---|---|
| `Items` | The names of the parts of the order. | `World.Plan.flat/1`, the parts |
| `Size[i]` | The bytes of one part `i`. | The size of the part in the external format of the BEAM |
| `Need[i]` | The count of the part `i` that the order needs from the warehouse. | The plan |
| `Ordered[i]` | The count of the item `i` that comes from other factories (a wheel, a seat). | The plan (`ordered`) |
| `Limit` | The size of the warehouse, in bytes. | `World.Stock`, the limit |
| `Capacity` | The count of parts on the truck. | `World.Vehicles.Vehicle`, the capacity |
| `Tasks`, `Waits[t]`, `Uses[t]` | The tasks of the plan, the tasks that each one waits for, and the part that each one takes from the dock. | The plan: the tree of the assembly |
| `Workers` | The names of the workers. | The yard |
| `ModelSize` | The bytes of the files of the model. | The GLB that the foreman makes |
| `Guard` | `FALSE` gives the fault model: a task can start twice. | — |

### The actions

Each action is one act of one person. The log of the code has one event
for each act, with the same name.

| Action | The person | When it can occur | Event of the log |
|---|---|---|---|
| `Supply(i, n)` | The storekeeper | The order needs `n` more of the part `i`, and they fit in the warehouse. | `stored` |
| `Pick(i, n)` | The storekeeper | `n` parts are in the store. | `picked` |
| `Load(i, n)` | The driver | The truck is at the warehouse, the parts are at its dock, and the load stays in the capacity. | `loaded` |
| `Depart(p)` | The driver | The truck leaves the warehouse with a load, or the factory empty. | `departed` |
| `Arrive(p)` | The driver | The truck is on the road to `p`. | `arrived` |
| `Unload(i, n)` | The driver | The truck is at the factory with the parts. | `unloaded` |
| `Receive(i, n)` | The driver of another factory | The order asked that factory for `n` more of the item `i`. | `received` |
| `Start(w, t)` | A worker | The worker is free, each task that `t` waits for is done, and the part of `t` is at the dock. | `task_started` |
| `Finish(w, t)` | A worker | The worker does `t`. | `task_done` |
| `ModelDone` | The foreman | Each task is done and each worker is free. | `model_done` |
| `StoreModel` | The storekeeper | The files fit in the warehouse. | `stored` (the model) |
| `Deliver` | The foreman | The files are in the warehouse. | `delivered` |

### The invariants

An invariant is true in each state that the system can reach.

| Invariant | What it says | The fault that it stops |
|---|---|---|
| `InLimit` | The warehouse never holds more than its size. | A full warehouse that takes one more part, or the files of a model. |
| `Conservation` | Each part is at one place only: in the store, at a dock, on the truck, or in the model. The count from the supplier and from the other factories is the sum. | A part that is lost, or a part that comes from nowhere. |
| `InCapacity` | The truck never carries more than its capacity. | A truck with too much load. |
| `OneWorkerOneTask` | Two workers never do one task. | Two workers that build the same part, so the model has it two times. |
| `WaitsFirst` | A task starts only after each task that it waits for is done. | A door on a body that is not there. |

### The liveness property

`Delivers`: each order is delivered in the end. The specification has
weak fairness on its next step: a step that can occur stays possible
until it occurs. The property stops a dead end: an order that waits
forever for a part, a worker or a place in the warehouse.

## The model check

`specs/MCOrder.tla` is a small model: a body, a door, a wheel of a rim
and a tire (a smaller assembly, so the plan has a sub-order), and a seat
from another factory, two workers, a truck of two parts, and a warehouse
of 6 bytes. It is small, but it has each shape of the real plans: a task
with no wait, tasks that wait for one task, a sub-order that waits for
its tasks, an item that another factory sends (`Receive`), more parts
than the truck carries, and a warehouse that is almost full. Two parts
of one name are not in the model (with a second door, the check takes
more than 40 s); the replay of the van, with its four wheels, has them.

| Configuration | Result | Numbers |
|---|---|---|
| `MCOrder.cfg` | Each invariant holds, and `Delivers` holds. | 13,836 distinct states, depth 43 |
| `MCOrderFault.cfg` (`Guard = FALSE`) | The checker finds `OneWorkerOneTask` violated. | A trace of 17 states |
| `MCOrderSmall.cfg` (`Limit = 3`) | The checker finds the dead end: the files of the model (4 bytes) never fit. | A trace of 41 states |

The checker is the native TLA+ checker of Accord
(<https://github.com/sntran/accord>, the branch `feat/native-tla-checker`).
It is Elixir: no Java, and it runs in `mix test` with the other tests.

## The replay: the code against the specification

A model check proves the design. It does not prove that the code does
what the design says. The replay closes that gap.

`World.OrderSpec.replay/5` (`test/support/order_spec.ex`) takes the log
of a real run of `World.Run` and:

1. writes a module `Run.tla` that extends `Order` with the constants of
   the run: its parts, their sizes, the tasks of its plan, the workers,
   the size of the warehouse and of the truck, the bytes of the model;
2. loads it in the machine of the checker
   (`Accord.TLA.Checker.Machine`);
3. takes each event of the log as one action of the specification, with
   its arguments (the person, the task, the part, the count);
4. checks each invariant after each step.

The result is `:ok`, `{:error, {:diverged, event}}` when the
specification has no step for an event (the code did a thing that the
design does not allow), or `{:error, {:violated, invariant, event}}`.

`test/world/run_test.exs` replays the order of the Ford Transit 148 at
the near level: 343 events, two workers. The test also proves
that the replay can fail: the same log with one `unloaded` event less
diverges, because a worker then takes a part that is not at the dock.

## The log check

`World.Log.check/1` runs each time a log is read from JSON
(`World.Log.from_json/1`). It is not a model check: it reads one log.
It refuses an event of an unknown kind, an event with a world time that
does not agree with its wall time and the clock, an event before the
last one, a task that starts two times, a task that starts before the
tasks that it waits for, and a task that ends before its start.

## What the specifications do not cover yet

A specification is as useful as it is honest about its limits.

- **One factory, one truck, one order at a time.** The other factories
  (step W4) are one action, `Receive`: an item arrives at the dock. Their
  plans, their trucks and their queue of orders are not in the
  specification.
- **The annex.** A full warehouse refuses the files of the model, and
  the truck brings them to the annex (step W6). The specification stops
  at the refusal: the replay of such an order diverges at the haul to
  the annex. The order from the stock (with the files from the store)
  is not an action either.
- **The time.** The specification has no clock. The log has the times,
  and `World.Log.check/1` checks them. The drive of the truck takes the
  length of the road over its speed: a test checks it, not the
  specification.
- **The files.** The specification counts the bytes of the files of a
  model. It does not check the GLB: the Khronos glTF validator does that
  for each file of the catalog (`npm test`).
- **The Worker at the edge.** The cache of the files in R2 and the
  restart of the VM are not specified.

## Run the checks

```sh
mix.com test test/world/order_spec_test.exs     # the model check and the fault models
mix.com test test/world/run_test.exs            # the run of the van and its replay
mix.com accord.check --extra specs/MCOrder.tla  # the model check alone, with its numbers
mix.com precommit                               # all the checks, with the coverage at 100%
```

The replay page (`/replay.html?order=HASH` on <https://world.mkfifo.com>)
shows the log of an order: the truck on the road, what each person
does, and the model that grows when each task ends. It reads the same
log as the replay of the tests.
