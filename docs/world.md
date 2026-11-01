# The world

The factory of World (`docs/factory.md`) takes an order and gives the
files of a model. In the world, people make the model, as in the real
world. A storekeeper picks the parts from a
warehouse. A driver brings them to the factory. The workers on the
line put them together. The places of the world are buildings, and
people build them too, from bricks, studs and the other materials of
World.

The world is not a picture on top of the factory. Each thing in it has
a real thing of the computer behind it. A warehouse is a store of
files. A factory is where the code builds one family of things. The
clock is the wall clock. A driver really drives the vehicle on the road
from one place to the other. The files travel with it, and the store at
the end of the road gets them when the vehicle arrives. The replay shows
what happened, with the real times.

The world has no scale of its own. It makes the models of each project
of the owner, and each project takes what it needs. DIY takes the items
of a house, Vũng Tàu a city, Phượt the roads of a trip, Humans Must Die
a planet.

This document is the plan. The owner reads it and changes it before the
work starts. The code is the source of truth after that (`AGENTS.md`).

## The words

| Word | What it is |
|---|---|
| **World** | The places, the roads, the people, the vehicles, the stock and the clock, in one assembly. |
| **Place** | A building with a position: a warehouse, a factory, a supplier, a yard, the site of a customer. A place is a model of World (`World.Buildings`): people build it. |
| **Warehouse** | A place that keeps stock. Its size is the limit of its store. |
| **Factory** | A place with lines and stations, where the workers build one family of things: vehicles, wheels, seats, slabs, houses, clothes. A sub-order goes to the factory of its family. |
| **Supplier** | A place outside the world that gives a part the world cannot make: the data of MakeHuman, the drawings of a maker, a supplied part of an order. |
| **Road** | The way from one place to another, with its length in meters. A vehicle drives on it at its speed, and a person walks on it. |
| **Stock** | The parts and the models that are in a warehouse now, each with its count. |
| **Person** | A figure (`World.Figure`) with a job, at a place, with one task at a time. |
| **Job** | What a person does: storekeeper, driver, worker of a station, foreman. Later: engineer, architect. |
| **Vehicle** | A model of World that moves parts: a van, a truck, a cart. A driver controls it, and it has a position on the yard at each time. |
| **Order** | A request for a model: the order of the factory (`docs/factory.md`), or an order of the world for a part, a delivery or a building. |
| **Plan** | The list of the tasks of an order, from the tree of its assembly, with the station of each task and what it waits for. |
| **Task** | One step of a plan for one person: pick a part, load, drive, unload, connect a part to its parent, store. |
| **Event** | One thing that happened, with its time, its place, its person or vehicle, and its order. |
| **Log** | The events in the order of their time. The log is the truth of the world: the replay and the statistics come from it. |
| **Replay** | The world in 3D from the log, at any speed: the vehicles drive, the people walk and carry, the model grows on the line. |
| **Clock** | The wall clock. The time of a task is the real time the code took. |

## What is real

Each thing of the world is one thing of the computer. The table gives
the rule. A new thing in the world comes with its real thing, or it
does not come.

| In the world | In the computer |
|---|---|
| A warehouse | A store of files: the R2 bucket of the orders (`world`), the catalog in the release (`priv/models`), the memory of the VM (the cache next to the line), the cache of a project (the R2 of Phượt). |
| The size of a warehouse | The limit of its store: the plan of R2 that the owner sets, the size of the release, the memory of the VM. The stock can not pass it. |
| The stock of a warehouse | The files in the store, by the hash of their order. A part in stock is built: nobody builds it again. |
| A factory | The processes that build one family of things, from the modules of that family: the vehicle factory from `World.Vehicles.Van` and the other vehicles, the wheel factory from `World.Vehicles.Wheels`, the seat factory from `World.Furniture.Seats`. In the first world, all the factories are in one VM; later, each factory can have its own VM (its own Durable Object). |
| A line and its stations | The stations of a model (`params.station` of each part): the body shop, the closures, the paint, the trim, the chassis, the upfit of a van. |
| A worker | A process of the BEAM that runs the tasks of one station. Two workers are two processes: they build two parts at one time. |
| A storekeeper | The process that reads and writes the store. |
| A driver and a vehicle | A person (a process) that drives a model of a vehicle on a road, at the speed of the vehicle, with the parts on board. The files of the parts travel with the vehicle: the store at the end of the road gets them when the vehicle arrives. That arrival is the transfer of the files (from R2 to the VM, from the VM to R2, from World to a project), and one event. |
| A road and its length | A line between two places on the yard, in meters. The time of a drive is the length of the road over the speed of the vehicle, on the wall clock: the world waits for the vehicle. The transfer of the bytes takes milliseconds; the drive is the time of the world. |
| A supplier | A source outside: a file of `priv/`, a URL, a supplied part in an order. |
| The clock | The wall clock of the VM. Each event has its real time. |
| The time of a task | The real time that the code of the task took: the build of a part, a transfer, a read of the store. |
| A person | A process (`GenServer`) with a mailbox. Its body is a figure of World, with the poses `walk`, `carry` and `work`. |
| The foreman | The process that makes the plan of an order from its assembly, and gives each task to a person. |

The replay shows the real log. A person that walks across the factory
in the replay is a process that walked there, at the speed of a person,
to its next task. A truck on the road carries the files of its parts,
and the store at the end gets them when it arrives. Nothing in the
replay is invented. The length of a road and the speed of a vehicle are
data of the world. The time of the drive is real time on the wall
clock.

## The places

A place is a building. The materials of World make it: bricks and
concrete blocks, lumber studs, OSB, siding, metal panels, doors and
windows (`World.Buildings`, `World.Materials.Construction`). A place is an
order too: the people of the world build it from its materials, and the
log has its build.

| Place | What it has | Its size |
|---|---|---|
| A warehouse | Racks (`World.Framing.Builds`: strut channel, shelves), a dock, a yard. | The limit of its store, in files and in bytes. The racks show the stock: a full rack is a full store. |
| A factory | Lines with stations, a dock for the parts, a yard for the finished things. One factory for each family of things (below). | The number of its workers (processes) and the memory of its VM. |
| A supplier | A gate: the parts come from outside. | None. |
| The site of a customer | Where a delivery ends: Phượt, DIY, Vũng Tàu, Humans Must Die. | None. |

Each place has a position in meters, in one flat frame: the yard of
World. Later, a place can have a latitude and a longitude, so the world
of Phượt puts the factory on its map.

### The factories

The world has many factories, as the real world does. Each factory makes
one family of things, from the modules of World of that family. An
order for a thing goes to the factory of its family. A part of it from
another family is a sub-order to that factory, and a vehicle brings
the part by road.

| Factory | What it makes | From |
|---|---|---|
| The materials | Bricks, concrete blocks, slabs, lintels, lumber, OSB, siding, metal panels. | `World.Materials.Construction`, `World.Materials.Stock` |
| The frames | T-slot frames, strut channel, racks, shelves. | `World.Framing`, `World.Framing.Builds` |
| The houses | Walls, roofs, doors, windows, houses, warehouses, factories. | `World.Buildings` |
| The wheels | Tires, rims, wheels. | `World.Vehicles.Wheels` |
| The seats | Seats and benches. | `World.Furniture.Seats` |
| The vehicles | Vans, cars, scooters, motorcycles, bicycles; their bodies, doors and engine bays. | `World.Vehicles.Van`, `World.Vehicles.Corners` and the other vehicles |
| The appliances and the power | Fridges, washers, ranges, power stations, the gear of a van. | `World.Appliances`, `World.Gear.PowerStations`, `World.Gear.Camper` |
| The clothes | The clothes and the hair of the people. | `World.People.Human` |
| The people | A person from the data of MakeHuman. | `World.People` |

A new family of things (an airplane, a ship) is a new factory, with its
modules. The people of the world build the factory first, from the
materials and the houses factories.

## The people

A person is a figure of World (`World.People`), with a name, a
job and a place. A person does one task at a time, and walks between
the tasks. The time of a walk is real: the person walks while the
process waits.

| Job | The tasks |
|---|---|
| Storekeeper | Check the stock. Pick a part from a rack. Put a model on a rack. Refuse a part when the warehouse is full. |
| Driver | Load a vehicle at a dock. Drive on a road. Unload at a dock. |
| Worker | The tasks of one station of a line: connect a part to its parent at its port, in the order of the plan. |
| Foreman | Make the plan of an order. Give each task to a free person. Ask a supplier or another factory for a part that is not in stock. |
| Engineer, architect (later) | Read the log. Propose a new process, a new part or a new model. |

A person is a process. Its mailbox holds its tasks. A person with no
task stands at its place. The world does not stop when a person waits:
the other people work.

## An order, from start to end

The example is a van of the blueprint `van`.

1. **The order comes in.** `POST /orders`, or an order from the world
   itself (a building, a part for another order). The log gets
   `order_received`.
2. **The foreman makes the plan.** The tree of the assembly gives the
   tasks. Each node after the root is one task: "connect this part to
   that node at that port", at the station of the part. A task waits for
   the task of its parent node. Two tasks that do not wait for each
   other can run at one time. The parts list of the assembly gives the
   parts to get.
3. **The storekeeper checks the stock.** A part with its hash in the
   store is in stock: the storekeeper picks it. A part that is not in
   stock becomes an order of its own, to the factory of its family, or
   to a supplier. The wheels of the van are an order of four wheels to
   the wheel factory; the seats are an order to the seat factory.
4. **The driver brings the parts.** The driver loads the parts on a
   vehicle at the dock of the warehouse or of the other factory. The
   driver drives on the road to the vehicle factory, at the speed of
   the vehicle, and unloads at its dock. The files of the parts arrive with the vehicle.
   The time is the time of the drive.
5. **The workers build.** Each station takes its tasks in the order of
   the plan. The body shop makes the body on the hull. The closures hang
   the doors. The trim puts the glass, the lamps and the seats. The
   chassis marries the engine bay and the wheels. The time of each task
   is the time the code took to make that part.
6. **The model goes to the warehouse.** The storekeeper puts the files in
   the store, under the hash of the order. The log gets `model_done` and
   `stored`.
7. **The delivery.** A driver brings the model to the site of the
   customer: the project reads the files. The log gets `delivered`.

A second order of the same van finds it in stock: step 3 picks it, and
the order ends at step 7. That is the cache of the factory today, seen
as a warehouse.

## The plan from an assembly

An assembly is a tree. The first node is the root. Each other node
connects to a node that comes before it. This order is the order of the
work, with no new data:

| In the assembly | In the plan |
|---|---|
| The root item | The first task: make the root part, or get it from stock. |
| A node with a `fixed` connection | A task: connect the part to its parent at the two ports. |
| A node with a joint (`turns`, `slides`) | The same task, and the joint goes into the log of the model. |
| A node that holds a smaller assembly | An order of its own, in the same factory or in another, then one task to connect it. |
| `params.station` of a part | The station of the task. |
| The parts list (`World.Build.parts/1`) | The parts to get from stock. |

The time of a task is not in the assembly. The world measures it when
a worker does the task, and the log keeps it. The second plan of the
same model knows the times of the first, and the foreman can give the
long tasks first.

## Time

Time is real. The clock of the world comes from the wall clock of the
VM, and the code takes real time to build a thing. But the code builds
much faster than people do. The camper van takes 0.46 s of code, and
about 30 hours of work in a real plant. So the world has a scale: one
second of the wall clock is one day of the world (86,400 world seconds).

### The scale from the measurements

The code times are the mean of three builds at the near level, with
`World.Build.scene/2`, on the computer of the development (BEAM.com
0.1.0-rc.6, native code).

| Thing | The time of the code | The time of the real work | Real ÷ code |
|---|---|---|---|
| The camper van (`ford_transit_148_camper`) | 0.46 s | About 30 hours of work for each vehicle in the plants of North America: stamping, engine and assembly (the Harbour Report of 2007: 30.37 hours). | About 240,000 |
| A wall of 164 bricks (`wall_brick_sample`) | 15 ms | 164 × 58 s: a bricklayer lays about 500 bricks in a day of 8 hours. | About 650,000 |
| A house of 7,108 bricks (`house_brick_vn`) | 1.9 s | About 114 hours of bricklaying. | About 215,000 |

At the edge, the VM runs in WebAssembly. The first guess was 10 times
slower than native code; step W7 measured 2 to 3 times (V8 compiles
the WebAssembly), so there the ratio is about 15,000 for the van.

One day for one second (86,400) is near the two. With this scale, a
worker of the world builds a van in 11 hours (native code) to about 28
hours (the edge, 2.5 times slower). A real plant takes about 30 hours: the same order of size. A faster computer is a faster factory, as a better tool is in the
real world. Step W7 measured the edge again ("The measures of a run"):
the code there is 2 to 3 times slower than native code, and the ratio
for the van is about 15,000. The owner
can change the scale: it is one number of the world, and each log keeps
it.

### The rules of the clock

- The time of the world: its start, plus 86,400 times the wall time
  since its start. The log keeps the world time and the wall time of
  each event, in milliseconds.
- The time of a task: the wall time of the code (the build of a part, a
  read of the store), times the scale.
- The speeds are real, in world time. A person walks at 1.4 m/s. A
  vehicle on the yard drives at 20 km/h; on a road between two places,
  at the limit of the road. The wall time of a drive is its world time
  over the scale: the world waits for the vehicle.
- A walk of 100 m takes 71 world seconds (0.8 ms of the wall clock). A
  van takes hours of the world. The world is as the real world: a
  walk across the yard is short, and a build is long.
- The calendar of the world runs fast: one hour of the wall clock is
  about 10 years of the world. The world gives its time as days since
  its start ("day 412, 14:05"), not as dates of the real calendar.

The replay runs the log at any speed: one world day in one second, or
slower to see a worker at a station. The statistics come from the log:
the time of an order from `order_received` to `delivered`, the time of
each station, the stock of each warehouse over time, the orders by
blueprint.

Sources of the real times: the Harbour Report of 2007
(<https://europe.autonews.com/article/20080605/COPY/569014825/harbour-report-chrysler-toyota-tie-for-2007-efficiency-title>),
and the output of a bricklayer
(<https://www.mybuilder.com/questions/v/24046/how-many-brick-layed-per-day>,
<https://uk.indeed.com/hire/job-description/bricklayer>).

## The events and the log

An event is one line of JSON. The log is the events in the order of
their time, in the SQLite of the VM, and in R2 as one file for each
order (`/o/HASH.log.json`).

| Event | Who and where | Data |
|---|---|---|
| `order_received` | The factory | The order and its hash. |
| `plan_made` | The foreman | The tasks and their stations. |
| `stock_checked` | The storekeeper, the warehouse | Each part: in stock or not. |
| `part_ordered` | The foreman | The order of the part, to which factory or supplier. |
| `picked`, `stored`, `refused` | The storekeeper, the warehouse | The part (`item` and `count`) or the files of a model (`model` and `bytes`), the reason of a refusal (`full`, `read_only`), and the bytes in the store after (`used`) with its limit. |
| `loaded`, `departed`, `arrived`, `unloaded` | The driver, the vehicle, the road | The parts on the vehicle, the time of the road. |
| `received` | The foreman, the factory | An item of an order of the factory arrives from another factory: the item, the count, the order of that factory. |
| `task_started`, `task_done` | The worker, the station | The task, its part, the time it took. |
| `model_done` | The factory | The hash, the size of the files. |
| `delivered` | The driver, the site of the customer | The project that reads the files. |
| `build_started`, `build_done` | A place | A new building of the world, from its own order. |
| `run_done` | The run (`World.Run.measure/3`) | The time of the run on the wall clock (`ms`), and the memory of the VM: the most (`memory_peak`) and at the end (`memory_end`), in bytes, with what they count (`memory`: `total`, or `processes` at the edge). |

Each event has: `at` (the time), `order` (the hash), `place`, `person`
or `vehicle`, `kind`, and the data of its kind. A test reads a log and
checks three things: the events are in order; the stock after each
event is never less than zero and never more than the size; each task
started after the task it waits for ended.

## The replay

The review page gets a page of the world. From a log, it shows:

- the places, as their building models;
- the stock on the racks of each warehouse;
- the vehicles on the roads, at the time of each event;
- the people, with the poses `walk`, `carry` and `work`, at their
  tasks;
- the model on the line, with one part more at each `task_done`.

The replay is a model of World too: an assembly of the world at a time,
with a pose for each person and each vehicle. So the files of the world
at a time are GLB files, and a project can show them.

## The projects

The world has no scale. It makes the models for each project of the
owner. Each project takes what it needs, at its own scale:

| Project | What it takes from the world |
|---|---|
| DIY | The items of a house, the vans, the builds of wood, as today. |
| Vũng Tàu | The buildings, the vehicles and the people of a city, in Godot. |
| Phượt | The vehicle of the traveler, the places along the road; later, the factory on its map. |
| Humans Must Die | A planet: its factories, its vehicles (emergency vehicles, airplanes, ships, aircraft carriers), its buildings. Each new family of things is a new factory of the world. |

The same parts, the same people and the same levels of detail serve all
four. A model of the world is one order; the project chooses its level.

## The engineers (later)

The first world does the work of a plan. The people do each task, in
the order the assembly gives. The plan comes from the assembly, not
from a person.

The second world makes plans. An engineer or an architect reads the
log: how many orders, of which blueprints, how the orders change, where
the time goes, which parts wait. From that, it proposes a change. A new process: a different order of
the tasks, or one more worker at a slow station. A new component: a
sub-assembly that many orders share. A new way to build, or a new
model. Erlang serves this well: a population of plans
that compete (genetic programming), flocks of people that move as one
(boids). That work comes after the first world, and it is research:
the owner decides each step of it.

## The order flow in TLA+

`specs/Order.tla` is the flow of one order: the supplier, the
warehouse and its storekeeper, the truck and its driver on the road,
the dock of the factory, the workers and the tasks of the plan, the
files of the model, and the delivery. Its invariants:

| Invariant | What it says |
|---|---|
| `InLimit` | The warehouse never holds more than its size. |
| `Conservation` | A part is at one place only: in the store, at a dock, on the truck, or in the model. |
| `InCapacity` | The truck never carries more than its capacity. |
| `OneWorkerOneTask` | Two workers never do one task. |
| `WaitsFirst` | A task starts only after each task that it waits for is done. |

Its liveness property, `Delivers`: each order is delivered in the end.
`docs/specs.md` tells each action, each invariant, the fault models and
the limits of the specification.

The checks, in the tests (`test/world/order_spec_test.exs`):

- `specs/MCOrder.tla` with `MCOrder.cfg`: a small model (a body, a
  door, a wheel of a rim and a tire, a seat from another factory, two
  workers): about 14,000 states.
  Each invariant holds, and each order is delivered.
- `MCOrderFault.cfg`: a task can start twice. The checker must find two
  workers on one task.
- `MCOrderSmall.cfg`: the files of the model do not fit in the
  warehouse. The checker must find the dead end.

The replay (`test/support/order_spec.ex`, `test/world/run_test.exs`):
the log of a real run of the van (343 events) is a behavior of the
specification, with the plan of the van as its constants. A log with an
event less, or with two workers on one task, is not.

## The measures of a run

Step W7. The run of an order through the world, with the measures of
its log (`run_done`). Native: BEAM.com 0.1.0-rc.6 on the computer of the
development, `mix run`. WebAssembly: the same `edge.com` in `wrangler
dev` (workerd on the same computer, with no limit of memory), the first
request of each order.

| Order | Level | Native run | Native memory (total) | WebAssembly run | WebAssembly memory (processes) | WebAssembly memory (host) |
|---|---|---|---|---|---|---|
| A traveler of Phượt on the motorbike | far | 1.9 s | 158 MB | about 8 s for the request | | 126 MB |
| A traveler of Phượt, parked | near | 4.0 s | 254 MB | 10.1 s | 55 MB | 216 MB |
| The camper van | near | 3.0 s | 277 MB | 7.3 s | 51 MB | 178 MB |

At the edge (the deploy of 3911c45 on <https://world.mkfifo.com>,
2026-10-31, the first request of each order, with the check of the
order and the start of the VM):

| Order | Level | Time of the request | Run (`run_done`) | Memory (processes) | Result |
|---|---|---|---|---|---|
| A strut of 0.5 m | near (log) | 6.3 s | 6 ms | 1 MB | Built |
| The camper van | far (GLB) | 9.4 s | | | Built |
| The camper van | near (log) | 16.1 s | 7.7 s | 56 MB | Built |
| A traveler of Phượt on the motorbike | far (GLB) | 12.5 s | | | Built |
| A traveler of Phượt on the motorbike | mid (GLB) | 7.4 s | | | Built |
| A traveler of Phượt on the motorbike | near (log) | 7.5 s | | | The VM stopped (503): not sufficient memory. After F4, part 2 (8d59a75): built, 13.0 s, a run of 7.3 s. |

What they tell:

- The code at the edge is 2 to 3 times slower than native code, not 10
  times (V8 compiles the WebAssembly): the run of the van takes 7.7 s
  at the edge and 3.0 s natively. So the ratio of the real time to the
  time of the code (section "Time") is about 15,000 for the van at the
  edge: 30 hours of work (108,000 s) over 7.7 s.
- The memory of the processes is small (about 50 MB); the host sees
  more (178 to 216 MB in `wrangler dev`), because the heap of
  WebAssembly only grows and keeps the garbage of the build. At the
  edge, the van at the near level fits; a person at the near level fits
  since F4, part 2 (`docs/factory.md`).
- The log of an order (`/o/HASH.log.json`) is a run at the near level;
  since F4, part 2 the log of a traveler is there at the edge too.

## The decisions

| Topic | Decision | Why |
|---|---|---|
| The name | The project is World: the module `World`, and a context of the world for each family of things (`World.People`, `World.Vehicles`, `World.Buildings`). The repository is `sntran/World`, the Worker `world` at <https://world.mkfifo.com>, and the bucket `world`. | The project builds things as the real world does. |
| Real, not invented | Each thing of the world is one thing of the computer, and each time is a measured time. | The replay is a record, and the statistics are true. |
| The log is the truth | The replay, the statistics and the engineers read the log only. | One source. A test reads a log. |
| A place is a model | A warehouse and a factory are orders, built by the people from the materials of World. | The world builds itself from the ground up. |
| People are processes | One `GenServer` for each person, one mailbox of tasks. | The BEAM is made for this. A person that waits does not stop the world. |
| The plan comes from the assembly | No new data for the plan: the tree, the stations and the parts list of the assembly. | Each model of World is buildable in the world with no change. |
| The driver drives | A driver is a person that drives a vehicle on a road from one place to the other, at the speed of the vehicle, with the parts on board. The files arrive with the vehicle. | This is how the world operates. The time of the drive is real time on the wall clock. |
| Many factories | One factory for each family of things. A sub-order goes to the factory of its family, and a vehicle brings the part. | The real world has a clothes factory, a slab factory and a car factory, not one factory. |
| No scale | The world has no scale of its own. Each project takes what it needs. | The world powers all the projects of the owner, at their own scales. |
| The clock | One second of the wall clock is one day of the world (86,400). The speeds are real speeds in world time: 1.4 m/s for a person, 20 km/h on the yard. | The code builds about 20,000 times (at the edge) to 650,000 times (native) faster than people. One day is between the two, and the real speeds keep a walk short and a build long, as in the real world. |
| The yard | The positions of the places are in meters, on one flat yard. A map comes later. | The simplest world first. |
| One bucket for each warehouse | A warehouse is one R2 bucket. A new warehouse is a new bucket. | In the game, a new warehouse is a collaboration with another city or country. |
| The flow in TLA+ | `specs/Order.tla` is the specification of the flow of an order. The native checker of Accord (`sntran/accord`, the branch `feat/native-tla-checker`, no Java) checks a small model of it in the tests: its invariants, and that each order is delivered in the end. Two fault models must fail: a task that starts twice, and a warehouse too small for the files of the model. The log of a real run replays as a behavior of the same specification (`Accord.TLA.Checker.Machine`). | The people are processes: the order of their acts changes from run to run. A model check finds the races and the dead ends that a test does not find, and the replay keeps the code and the specification the same. |
| The replay page | A static page (three.js and an SVG map) that reads the log and the replay GLB of an order from the site. No Phoenix LiveView. | The log is a file that does not change: a page that reads it needs no server and no socket. The Worker stays a plug (`World.Service`) in one VM of 128 MB. A live view of the world as it runs comes when the world runs for a long time (W4 and later); then a socket from the Durable Object can send the new lines of the log to the same page. |
| The crew van of the Transit | It comes with the Sprinter and the ProMaster, after the first world. | The owner wants the crew van in the line. Ford does not sell it for 2024 to 2027: its sizes come from the earlier years. |

## The steps

Each step is a small series of commits on `main`, with tests at 100%
and a picture of the replay where there is one.

| Step | Result | Check |
|---|---|---|
| W0. The plan | This document. | The owner agrees, or changes it. |
| W1. The data of the world | `World.Clock`, `World.Places`, `World.Yard` (the roads), `World.Stock`, `World.People.Person` (the jobs), `World.Vehicles.Vehicle`, `World.Log` (the events and the checks). The plan of an order from its assembly (`World.Plan`). Done. | A property test: the plan of each model of the catalog has one task for each node, and each task waits for the task of its parent. A log with a bad order of events is refused. |
| W2. One thin slice | One order of a van. One warehouse, one truck with its driver on a road of the yard, one vehicle factory with a foreman and two workers. The people are processes (`World.Run`, `World.People.Storekeeper`, `Driver`, `Foreman`, `Worker`). The log of the order, with real times. The flow in TLA+ (`specs/Order.tla`). Done. | A test runs the slice and reads its log: the van is delivered, the events are in order, the stock is never negative, the drive took the length of the road over the speed of the truck. The same order a second time comes from stock. |
| W3. The replay | The replay page (`review/replay.html`, `/replay.html?order=HASH`): the map of the yard with the truck on its road, what each person does, the events, and the model that grows when each task ends. The orders of the site go through the world (part of W7): `/o/HASH.log.json` and `/o/HASH.replay.glb` (`World.Build.scene/2` with `split: true`). No LiveView: the log is a file, and a static page reads it. Done. | A picture of the replay of the van at a time, on a phone and on a wide screen. A test: the replay GLB has one node for each task of the plan that takes a part. |
| W4. The factories | The wheel factory and the seat factory next to the vehicle factory, each with its foreman, its worker and the driver of its truck. The family of an item is the kind of its assembly (`World.Places.family_of/1`: `:wheel`, `:seat`). The plan of a factory (`World.Plan.flat/2` with its family) leaves a smaller assembly of another family to the factory of that family: the foreman orders it (`part_ordered`, the order `ORDER/wheels`), that factory makes it (`World.Plan.batch/2`) from the parts of the warehouse, and its truck brings it to the dock (`received`). A factory does one order at a time; the next order waits. `specs/Order.tla` has the action `Receive`. Done. | The log of a van: the wheels come from the wheel factory, the seats from the seat factory, each by a drive (`test/world/run_test.exs`). The log of the van replays in the specification. |
| W5. The buildings | The warehouse and the factories are orders: the people build them, and the log has the build. `World.Buildings.Plants`: a building is a house of World (walls of 2x4 studs, a metal roof, a door at the left end); a warehouse has one rack of strut channel for each 64 MiB of its store (a number of the world), in two rows; a factory has 3 m of length for each worker. `World.Run.build/3`: `build_started` (the model and its size), the order to the houses factory (a factory of the run now), the delivery to the place, and `build_done`. Each event of a storekeeper has the bytes in the store and its limit, and the replay draws the racks of a warehouse under it, dark when full. The materials are parts of the house, from the warehouse: no materials factory yet. Done. | The log of a build of a warehouse (`test/world/run_test.exs`): 200 MiB gives four racks. The size of a warehouse from the limit of its store (`test/world/plants_test.exs`). |
| W6. The stores | The stock is the files: each warehouse has a store (`World.Store`), and the stock keeps the files of each model in it (`World.Stock.put_files/3`). The kinds of a store: `:memory` (the memory of the VM, the store of the warehouses of a run by default), `:bucket` (an R2 bucket; on this computer a folder in its place, as the photos of Phượt), and `:release` (the catalog of the release, `priv/models`: read only and always full, `World.Places.catalog/3`). The yard of a run has an annex (a second warehouse, its storekeeper `tam`, a road to each factory) and, with the option `catalog`, the catalog. A model in the stock of a warehouse (the warehouse first, then the catalog, then the annex) goes to the customer with its files. A full warehouse refuses the files of a new model: the driver of the warehouse brings them from the factory to the annex, and its storekeeper stores them. With the annex full too, the order fails. The R2 bucket from the VM at the edge (a port to a binding, as `PHOTO_STORE` of Phượt) is not there yet: today the Worker puts the files of an order in R2 after the run. Done. | A test with a small limit: the storekeeper refuses, and the foreman sends the model to another warehouse. |
| W7. The site | The orders of the projects go through the world at <https://world.mkfifo.com> (done in W3). Each run of an order has its measures in its log (`run_done`, `World.Run.measure/3`): the time of the wall clock, and the memory of the VM, sampled each 25 ms. At the edge the emulator has no allocators of ERTS (`-Mea min`), so `:erlang.memory/1` is not there: the log then counts the memory of the processes and of their binaries (`memory: "processes"`), and the host logs the memory of all of the VM (`beam: memory N MB`). `POST /build` gives the time of the build in the header `server-timing`. The release has no `priv/models` now (the site serves them): `edge.com` goes from 87 MB to 31 MB. The deploys after 29 October 2026 did not reach the site (it served `af1ad01`); the first deploy with the smaller `edge.com` (3911c45) reached it, so the size of the Worker was the cause. The numbers are in "The measures of a run" below. Done. | An order of Phượt gives its files and its log. The times in the log agree with the times of the service. |
| W8. The other vans | The Sprinter, the ProMaster and the crew van of the Transit, built on the line of the vehicle factory. The ProMaster (2026-11-01): the make `ram_promaster` and the models `promaster_136_high`, `promaster_159_high` and `promaster_159_ext_high` in `priv/data/vans.json`. The side traces come from the render of Ram on the side of the 159 in, high roof (sent by the owner), with the length and the height of the brochure of Ram as the scales; the sizes from the brochure of Ram (2018) and the cargo page of Ram. The black band and the window of the front door are data of the make now (`trim.band`, `openings.door_window`). The Sprinter (2026-11-01): the make `mercedes_sprinter` and the models `sprinter_144_high`, `sprinter_170_high` and `sprinter_170_ext_high`. The side traces come from a drawing of the high roof van in the Body and Equipment Guideline of Mercedes-Benz (BM907, 2024-9, sent by the owner), which is to scale: with its wheelbase as the scale, its overhangs and its length are those of the guide to 6 mm; the lengths, the wheelbases and the front overhang from the tables of the guide. Still from the Transit, for both makes: the lamps, the grille, the wheels and the dash; the standard roofs and the super high roof of the ProMaster are not there yet. The crew van waits for photos (see "Open questions for the owner"). | As the Transit: a render next to the photo of the dealer. |
| W9. The engineers | Later, with the owner. | — |

## Open questions for the owner

- **The scale of the clock.** One second of the wall clock is one day of
  the world (86,400). Step W7 measured the edge again: the code there
  is 2 to 3 times slower than native code, so the scale stays.

- **The sources of the other vans (step W8).** A van of the line needs
  the traces of its side (the Transit has them from the drawings of
  Outlines and a photo of the owner), its sizes, and a side photo of a
  dealer for the check. Found on 2026-10-31:
  - The sizes. The Sprinter (VS30, 144 in and 170 in, high roof): the
    page of the cargo van of Mercedes-Benz Vans Canada (length 234 and
    274 in, height 107 in, overhangs 40 and 49 or 64 in, rear door 61 by
    73 in). The ProMaster (2014 to 2022, 136 in and 159 in, high roof):
    the Ram brochure of 2018, page 22 (length 213.1 and 236.1 in, width
    80.7 in, height 99.4 in). The crew van of the Transit (148 in): the
    columns of the cargo van in the Ford Technical Specifications of
    2025, page 4; Ford gives no sheet for the crew van itself.
  - Not found: the overhangs, the tracks and the tires of the ProMaster;
    the second row and the windows of the crew van; any scaled side view
    from a body builder guide (the guides of Mercedes-Benz, Ram and Ford
    refuse this computer: 403 or 503); any side photo of a dealer.
  - The drawings of Outlines (getoutlines.com) of each van exist, at
    24 USD each, and their previews show the side.

  The owner can give one of these: the PDF of each body builder guide,
  the drawings of Outlines (or permission to buy them), or side photos
  of the three vans. With them, W8 continues as F3 did for the Transit.
  On 2026-11-01 the owner sent the renders of the ProMaster from the
  page of Ram, and the ProMaster with a high roof is in the line. The
  Sprinter guide (28 MB) is with the owner: the side pages and the size
  tables, a folder shared to the session, or a link, let the Sprinter
  start. The crew van needs side photos of its windows and its second
  row. On 2026-11-01 the owner sent pages of the guide of the Sprinter:
  its drawing of the high roof van is to scale, and the Sprinter with a
  high roof is in the line. The height of the drawing (2.614 m) is lower
  than the US page (107 in, 2.718 m); the model has the height of the
  drawing.

