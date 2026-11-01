# The factory

World is a factory for 3D models. A project sends an order, and the
factory builds the model from its parts and gives the files. The
projects (Phượt, DIY, Vũng Tàu) are on Cloudflare, so the factory is a
web service: <https://world.mkfifo.com>. A model has a URL. When World
corrects a part, each model that uses the part changes at the same URL,
and the projects do not deploy again.

## The words

| Word | What it is |
|---|---|
| **Warehouse** | The parts that World keeps: the standard parts (bolts, nuts, extrusions, strut channel, lumber, bricks, wheels and tires), the shapes (a box, a cylinder, a lathe, a loft, a sweep, a prism), and the materials (the roles of `priv/palette.json`). |
| **Blueprint** | A family of models with options: `van`, `person`, `house`, `power_station`. Each option has a name, a type, a default, a unit and a range or a list. The data of a blueprint (the sizes of each make, the traces of a body) is in `priv/data`, not in the code. |
| **Order** | A JSON document: a blueprint and its options, or a drawing, and the parts to fit into its slots. |
| **Drawing** | The design of a model that World has no blueprint for: its parts (shapes, standard parts, orders of blueprints, supplied parts) and its nodes (the JSON form of `World.Assembly`). |
| **Supplied part** | A mesh that the order gives (GLB, OBJ or `.wings`), with its ports. |
| **Slot** | A port of a blueprint where another order fits: the engine bay of a van, its roof, the seat of a scooter for a rider. |
| **Receipt** | What the factory gives with the files: the full order with each default, the version of World, the sources of each part, where each part comes from (blueprint, drawing, supplied), and the hash of the order. |

## The four kinds of work

| A real factory | World | When |
|---|---|---|
| Products of the catalog | An order of a blueprint | The common models, with sources and tests. |
| Build to print | An order with a drawing | A model that World has no blueprint for. No pull request is necessary. |
| Parts of the customer | Supplied parts in a drawing | A shape that the warehouse cannot make. |
| The engineering department | A pull request to World | A drawing that many orders use becomes a blueprint, with its sources and tests. |

An order is data, never code. World runs no code from an order.

## The URLs

| URL | What |
|---|---|
| `/` | The review page: each model of the catalog, its levels, its joints and its parts. |
| `/replay.html?order=HASH` | The replay of an order: the map of the yard with the truck on its road, what each person does, and the model that grows when each task ends (`docs/world.md`, step W3). |
| `/models/list.json` | The names of the models of the catalog. |
| `/models/NAME.glb`, `NAME.mid.glb`, `NAME.far.glb` | A model of the catalog at each level. |
| `/models/NAME.parts.json` | The list of its parts. |
| `/palette.json` | The default color of each material role. |
| `/version.json` | The commit of World that the site has. |
| `/blueprints` | Each blueprint with its options: the type, the default, the unit, the range or the values. |
| `POST /orders` | An order in JSON. The answer gives its hash, the full order (with each default), the URLs of its files, and the URL of its replay page; or 422 with the errors. |
| `/o/HASH.glb`, `.mid.glb`, `.far.glb`, `.parts.json`, `.receipt.json` | The files of an order of `POST /orders`. The people of the world build the GLB at each level (`World.Run`). |
| `/o/HASH.log.json`, `/o/HASH.replay.glb` | The log of the run of the world that built the near level (`World.Log`: one line for the clock and the yard, then one line for each event), and the model with each part in a node of its own, with the id of its task (extras `task`), for the replay. |
| `/m/BLUEPRINT.glb?OPTION=VALUE` (and the other files) | An order in the URL: `color.ROLE=%23rrggbb` gives a color, `joint.NAME=50` a joint, `target.LIMB=X,Y,Z` the end of a limb, `A,B` a list, and `OPTION.FIELD=VALUE` a field of an object (`origin.asian=1`: give each field, because a field that is not in the URL has its default). |
| `/v/VERSION/...` | A copy that never changes, for a release of a game (later). |

An order:

```json
{
  "blueprint": "catalog",
  "options": {"name": "ford_transit_148_camper"},
  "colors": {"paint": "#1d3b5a"},
  "joints": {"hood": 50}
}
```

An error tells the path of the wrong value and the rule:
`{"errors": [{"path": "options.length", "message": "must be from 0.05 to 6.1 m"}]}`.

The blueprints now: `catalog` (each model of the catalog, with colors
and joints), `drawing`, `person`, `traveler`, `exercise`, `animal`, `house`, `van`,
`extrusion`, `strut` and `l_track`.

The joints of a person are in the order too: `"joints": {"elbow_r":
120, "shoulder_r.spread": 80}` for a person, `"traveler/elbow_r"` for
the person of a traveler. `docs/format.md`, "The joints of a person in
an order", has the names and the limits.

The ends of the limbs are in the order too: `"targets": {"arm_r": [0.3,
0.4, 1.3]}` puts the wrist at that point (`docs/format.md`, "The
limbs"). In a URL: `target.arm_r=0.3,0.4,1.3`. An order with no target
has no key `"targets"`, so its hash stays the same as before. The
receipt lists the limbs of the model.

A `traveler` is a traveler of Phượt: a person (the options of `person`,
with the colors of the hair and of the clothes, and `head`, the size of
the head: 1 is the size of the body, up to 2 for the bigger head of a
game) and a vehicle of Phượt (`vehicle`: `car`, `camper`, `motorcycle`,
`motorbike`, `bicycle`, `foot`), in a `scene`:

- `ride` (the position of the traveler on a map): the person on the
  vehicle, in the pose of the vehicle. On two wheels the rider has a
  helmet (`helmet_color`, else a light gray). In the car and the van, the
  person sits in the seat of the driver (the left side), and the glass is
  clear. The driver of the van shows in the window of the door at the near
  level only: at mid and far, the window is a panel on the body.
- `parked` (the avatar of the traveler): the person stands next to the
  parked vehicle, on its right side, and looks to the right (+x). The
  person has no helmet. The model has two animations to play once (2.6
  s each): `wave` (the right hand waves to the viewer) and `point` (an excited
  point: the left arm goes up to the front of the vehicle, +y, with one
  finger out, and jabs three times; the body leans there and the head
  looks there).

A person on a moving vehicle is always in a safe pose: the eyes on the
road, the hands on the bars or on the wheel. The vehicle goes to the
front: seen from its right side, it goes to the right of the screen. At
the far level the file is about 300 KB.

A `drawing` is a model in the data of the order: its parts from
shapes, its nodes with their joints, the items of other blueprints (a
person, an animal, a model of the catalog), and the clips of its joints
(`docs/format.md`, "A drawing"). An app or another project can order a
thing that World has no blueprint for, and get the same files: the GLB
with its joints and clips, the list of the parts, the log. Each error
has its path.

An `animal` is an animal of a species, from its bones: `species`
(`street_dog`, `cat`, `wolf`, `fox`, `deer`, `goat`, `pig`, `horse`,
`donkey`, `cow`, `water_buffalo`, `sheep`, `alpaca`, `husky`,
`red_deer`, `hyena`, `macaque`, `rhesus_macaque`,
`pig_tailed_macaque`, `douc`, `gibbon`, `carp`, `tilapia`, `chicken`,
`duck`), `coat` (a
color; the color of the species by default), `size` (0.6 to 1.4: a
scale of the animal), `shape` (numbers of the
shape over the numbers of the species, as `{"leg_length": 1.2,
"ear_droop": 30}`), `markings` (a region of the
coat to its color, as `{"socks": "#ffffff"}`), `space` (the
coefficients of the shape space of the template, for the `wolf`: the
space lists the numbers and the coefficients of the horse, the cow, the
deer and more, so a wolf with the `shape` and the `space` of the horse
has the shape of a horse; `docs/format.md`, "The shape space") and `animations` (the
animations of its body plan: `walk`, `run`, `idle`, `idle_low`, `eat`,
`attack`, `kick` (only the animals with hooves), `jump`, `jump_stop`,
`hit_l`, `hit_r`, `death` and `wag` for four legs, `walk` (on four
limbs, or on two legs for the gibbon), `sit`, `climb`, `hang` and
`jump` for the primates, `swim` and `idle` for the fish, `walk`, `idle`, `peck` and `flap`
for the birds; the walk, the run and the jump are in
place, and the parts list gives their speeds, `walk_speed`, `run_speed`,
`jump_speed` and `swim_speed`, in m/s). Its joints and the ends of its limbs
are in the order too (`"joints": {"tail.spread": 20}`, `"targets":
{"front_r": [0.07, 0.3, 0.15]}`). A species is data of a body plan
(`docs/format.md`, "An animal"): an app can order a four-legged animal
that World has no species for, with numbers only.

An `exercise` is a group at a morning of exercise, as on the beach of
Vũng Tàu: `routine` (`tai_chi`, `yoga` or `aerobics`), `count` (1 to 12
people, 6 by default) and `seed`. A leader at the origin faces the group
(+y) and does the routine as in a mirror; the people stand in rows of
three in front of the leader and face the leader (-y). Each person is
different (the age of the routine: 55 to 75 for tai chi, 25 to 50 for
yoga, 35 to 65 for aerobics; the body, the hair, the clothes and the
color of the shirt), from the seed, and starts the routine up to 0.35 s
late. The routine is one animation of the model, in a loop (16 s, 24 s
and 8 s). A person (`person`) can also have a routine as its animation:
an app can place each person and start the loop at its own time. A group
of 7 people is about 1.5 MB at the far level and 4.8 MB at the mid level. With
`fans` (true), each person holds an open tai chi fan in the right hand,
and the leader in the left hand.

A `person` can hold a prop in each hand (`right_hand`, `left_hand`:
`fan` or `bottle`) and wear a hat (`hat`: `non_la`). The props follow
the hands in the pose and in the animations, and they are in the list of
the parts.
At the edge, a group of more than 3 people needs more memory than the
builder has (`AGENTS.md`, "Known problems"): order each person, or build
the group with `mix world.order`.

An order of a van:

```json
{
  "blueprint": "van",
  "options": {
    "model": "transit_148_medium",
    "windows": "passenger",
    "engine_bay": ["dc_charger"],
    "roof": [{"kind": "solar", "at": 3.8}, {"kind": "fan", "at": 5.2}],
    "size": {"height": 2.6}
  },
  "colors": {"paint": "#1d3b5a"}
}
```

The windows of a van are a list, or the name of a preset: `cargo` (no
window behind the cab, the default), `crew` (the window of the second
row at the left, the window of the sliding door and those of the rear
doors), `passenger` (the windows all around). Each window of a list has
its place (`at`: `left` or `right` in a side of the body, `slider` in
the sliding door, `rear_doors` in the rear doors; one window at a
place) and its numbers (`from` and `to` behind the front axle, `bottom`
and `top` over the ground, in meters); a number that the window does not
give is that of the model. The doors have numbers too (`doors`: `front`
`back` and `top`, `sliding` `from`, `to` and `top`, `rear` `height`),
and `rows` is the count of the rows of seats behind the front seats (by
default from the preset). A crew van with a longer window at the left
and a wider sliding door:

```json
{
  "blueprint": "van",
  "options": {
    "model": "transit_148",
    "windows": [{"at": "left", "to": 3.5}, {"at": "slider"}, {"at": "rear_doors"}],
    "doors": {"sliding": {"to": 2.9}},
    "rows": 1
  }
}
```

In the world, the doors factory makes each door to its numbers, with
the glass of its window, and its truck brings the doors to the line of
the van (`docs/world.md`, "The factories").

The sizes of a van (`size`: `length`, `width`, `height`, in meters) are
those of the US market by default: the sizes that the maker gives for
the US. An order for another market gives its sizes (the Sprinter of
Mercedes-Benz Australia: `"height": 2.331` with a standard roof, 2.62
with a high roof). The height goes up 0.3 m and down to the height of
the traces of the roof; the length and the width go 0.05 m each way.
The check of a van refuses a size, a door or a window out of the limits
of the model (a door stays in the body, a window in its side or its
door), two windows at one place, and more rows of seats than the body
has room for; it puts each item of the roof on the flat part of the
roof, and two items do not touch.

Each file has `Access-Control-Allow-Origin: *`, an `ETag`, and
`Cache-Control: public, max-age=300, stale-while-revalidate=86400`. So a
project gets a correction at most 5 minutes after the deploy of World,
and it can use a copy in its cache while it gets the new file.

## The line of a van

A van of the blueprint `van` is built as the maker builds it, station
after station (`World.Vehicles.Van`):

| Station | What it adds |
|---|---|
| The body shop | The body of sheets on the hull, 3 cm thick, with the openings cut: the windshield, the front doors, the sliding door, the rear doors, the windows of the body, the arches of the wheels. Inside: the floors, the wells of the wheels, the pillar behind the front door, and the mounting points of the seats (the ports `seat_driver`, `seat_passenger`, `row_2` and more, from the seats of the make in `priv/data/vans.json`). |
| The closures | The hood, the front doors with their windows and mirrors, the sliding door, the rear doors: each in its opening, on its hinges or its rail. |
| The paint | The role `paint` of the body and the doors. |
| The trim | The glass in the openings, the black plastic, the lamps, the grille, the small parts, the dash, and the seats (`World.Furniture.Seats`) on their mounting points: the two front seats on their tracks, with backs that recline, and the benches of the rows of the crew van and the passenger van. |
| The chassis | The engine bay and the wheels. |
| The upfit | The items of DIY on the roof and in the engine bay. |

Each part has its station in its `params` (the list of the parts is
the build sheet). The near level is the van of the line: the doors open
on the inside of the van. The mid level has a closed body with the doors
on it, and the far level the closed body only.

## The contract

The other projects use the names of the options, the slots, the joints,
the ports and the parts. A correction can change a shape, a size or a
color, but not these names. A test keeps a copy of the names of each
model of the catalog and compares them. A change of a name makes a new
version of the blueprint (`van@2`): the old version stays.

## Where the builds run

| Order | Where |
|---|---|
| A model of the catalog | CI builds it natively (`mix world.build --check`), and the files are in the repository. The Worker serves them as static files: no build at a request. |
| An order at a request | The VM of World (beam.com, WebAssembly) in a Durable Object of the Worker builds it (`worker.js`, `handler.js`, `World.Service`). The file goes into R2 with a key of the commit of the deploy and the hash of the order, so the next request reads it from R2, and a new deploy builds it again. |

The VM at the edge, measured with Node.js 25 and the runtime of
beam.com 0.1.0-rc.6 (the time of one build, and the peak of the memory
of the VM):

| Model | Level | Native | WebAssembly | Peak |
|---|---|---|---|---|
| `redarc_bcdc1250d` | near | 7 ms | 80 ms | 55 MB |
| `ford_transit_148_camper` | far | 86 ms | 234 ms | 68 MB |
| `ford_transit_148_camper` | mid | 133 ms | 332 ms | 92 MB |
| `ford_transit_148_camper` | near | 2.0 s | 3.3 s | 298 MB |
| `house_brick_vn` | mid | 147 ms | 404 ms | 88 MB |
| `house_brick_vn` | near | 4.3 s | 6.7 s | 847 MB |

At the edge (the deploy of 05ec8c6, 2026-10-28; the
time of the first request, with the check and the build):

| Order | Level | Time | File | Result |
|---|---|---|---|---|
| `strut`, 0.5 m | far | 2.2 s (0.3 s from R2) | 11 KB | Built |
| `ford_transit_148_camper` | far | 3.1 s | 169 KB | Built |
| `ford_transit_148_camper` | mid | 2.6 s | 301 KB | Built |
| `ford_transit_148_camper` | near | 5.7 s | 1.1 MB | Built |
| `person` (the defaults) | near | 6.9 s | | The VM stopped (error 1101). The next request started it again (2.8 s). |

The time is not a problem. The memory is: a Worker has 128 MB. The mid
and far levels and the small items fit; the near level of a large model
does not. In `wrangler dev`, the near level of a person (3 MB) took
0.9 s and 124 MB, and a small house took 0.2 s. Step F4 makes the build use less memory. If that is not
sufficient, a builder with more memory (a Cloudflare Container with
the native beam.com) builds the large orders.

F4, part 1 (2026-10-31). The peak of `:erlang.memory(:total)` over the
VM at rest, natively, in one process that builds the GLB of a person
(the data of MakeHuman already loaded; with it not loaded, add about
60 MB):

| Person | Before | After |
|---|---|---|
| The defaults, near | 132 MB | 90 MB |
| With `speech` and `expressions`, near | 431 MB (not loaded) | 131 MB |
| The defaults, mid | 64 MB | 35 MB |

- After a garbage collection only 5 to 17 MB of a build is live. The
  collector keeps the garbage in the old heap until a full sweep, and a
  full sweep copies the live data to a new heap: the peak was some
  times the live data. A full collection after each big step
  (`World.Detail.collect/1`: after each mesh of a person and each
  primitive of the GLB) keeps it low. A full sweep at each collection
  (`fullsweep_after: 0`) is worse: each one copies the whole heap.
- A morph target can be a map of the points that move
  (`World.Scene.Primitive`): a shape of the face moves few of the
  points of the body, and 45 dense targets were 75 MB of tuples.
- The GLB writer puts the points into the binary with no list of them
  in the axes of glTF, and takes their bounds from the binary.

F4, part 2 (2026-10-31). Two causes of the peak of a build, and the
load of the data. The files are the same, byte for byte.

- `World.Build` placed the corners of all the parts of a model before
  it made one primitive for each material, and it kept the triangles of
  each mesh in the dictionary of the process for all the later builds of
  that process (a worker, a foreman). Now it makes one material at a
  time, keeps the triangles of the meshes of that material only, and
  collects the garbage after each primitive.
- The data of MakeHuman: a short process parses each file and puts it
  in `:persistent_term`, so the garbage of the parse and a second copy
  of the data are not in the process of the build.

The peak of `:erlang.memory(:total)` over the VM at rest, natively, for
an order through the world (`World.Orders.build/3`, GLB at near):

| Order | Before | After |
|---|---|---|
| The camper van | +185 MB | +71 MB |
| A parked traveler on the motorbike, first order of the VM | +200 MB | +159 MB |
| A parked traveler on the motorbike, data loaded | +162 MB | +109 MB |
| A person (the defaults), first order of the VM | +159 MB | +115 MB |
| The scene of the motorbike alone (Honda Vision, near) | +82 MB | +33 MB |

The memory of the VM in `wrangler dev` (the host, all of the heap of
WebAssembly), one order alone:

| Order | Before | After |
|---|---|---|
| The camper van, near | 182 MB | 95 MB |
| A parked traveler on the motorbike, near | 230 MB | 172 MB |
| A person (the defaults), near | 149 MB | 157 MB (no change: the person is the next step) |

At the edge (the deploy of 8d59a75, the first request of each order),
the near level now builds: a parked traveler on the motorbike (GLB,
18.0 s), the log of a traveler on the motorbike (13.0 s, a run of
7.3 s), a person with the defaults (GLB, 10.8 s), and a traveler in
the car (GLB, 19.8 s). Before F4, part 2, the log of a traveler stopped
the VM (503).

The heap of the build of a person peaks near 38 MB, and the person (the
item) is 12 MB of terms: lists of tuples of floats for each point. Less
needs a packed format for the meshes (binaries of floats), a larger
change.

Still to do: a packed format for the meshes of a person; the data of
MakeHuman in the memory of the VM (the targets are a
binary of 14.6 MB, the base mesh 6 MB of terms, the assets 8 MB: a
format that reads only the targets of a person); and the peak at the
end of a build, where the person, the scene and the buffer of the GLB
are all live.

## Realism

Phượt and Vũng Tàu need models that look like the real things. So each
part, shape and model has two kinds of source, never a memory:

- **The sizes**: a standard, a data sheet, a drawing, or a trace of a
  drawing.
- **The photos**: photos of the real thing (from the maker, a dealer, a
  press kit, the owner). Before a commit, a render of the model and a
  photo from the same view are compared side by side.

The sources of a part give both, with the URL of each photo. The
repository keeps the URLs, not the photos.

## Other work: Cube of Roblox

"Cube: A Roblox View of 3D Intelligence" (arXiv 2503.15475, 2025; code
and weights at github.com/Roblox/cube) makes shapes with a neural
network:

- A shape tokenizer: points on the surface of a mesh become 512 to 1,024
  tokens; a decoder gives an occupancy field, and marching cubes gives
  the mesh. Text-to-shape writes the tokens from a text; shape-to-text
  writes a caption of a shape.
- Text-to-scene: a language model writes a scene as JSON (each object
  with its category, its caption, its place, its turn about the up axis
  and its box), then text-to-shape makes each object.
- For later, the paper names what World has now: shapes from parts,
  people with a skeleton and layers of clothes, and joints (a steering
  wheel that turns the wheels, a door that slides).

What it means for World:

| Topic | Cube | World |
|---|---|---|
| The source of a shape | Learned from about 1.5 million assets (Objaverse and Roblox). | Standards, data sheets, drawings and photos. |
| Sizes | A box from the scene; the shape inside it is learned. | The real sizes of each part. |
| Parts, joints, the list of the parts | Not yet ("future work"). | Yes. |
| Shapes that are not made from parts (a rock, a tree, a statue, a dog) | Yes. | No. |
| Where it runs | A GPU. | The VM at the edge. |

So the two agree in two ways:

1. **The order is the scene graph.** The JSON scene of Cube and an order
   of World have the same idea: a language model writes the layout, and
   a builder makes each object. An order of World gives more (options
   with ranges, slots, joints), and the check gives each error back to
   the model (step F7).
2. **Cube can supply parts.** A shape that the warehouse cannot make can
   come from Cube, made one time on a GPU, cleaned
   (`World.Mesh.clean/1`), and kept as a supplied part (step F6) with its
   text as its source. It is not a measured shape: the receipt says so.
   Read the license of the weights before a use.

## The steps

| Step | What |
|---|---|
| F1 | This file. The Worker at `world.mkfifo.com` serves the catalog and the review page. Done. |
| F2 | Blueprints, orders and the receipt (`World.Orders`), `mix world.order`, the builder in the VM, the cache in R2. People, houses and framing are the first blueprints: they have options already. Done. |
| F3 | The van blueprint, from the traces of DIY and from photos: the Ford Transit (high roof, medium roof, extended; cargo, crew and passenger windows), with the engine bay and the roof. Done. The Sprinter and the ProMaster come after their photos. |
| F4 | People in the release (the data of MakeHuman in `priv/`), and less memory for the near level. |
| F5 | Drawings. |
| F6 | Supplied parts (with the reader of `.wings` of step 5 of `README.md`). |
| F7 | Orders from text: a language model writes an order or a scene from `/blueprints`, and the errors of the check go back to it until the order is correct. |
| F8 | Scenes: a list of orders, each with its place and its turn, and joins at slots. |

## The setup on Cloudflare

The owner does this one time:

1. In the dashboard of Cloudflare, Workers and Pages, make a Worker from
   the repository `sntran/World` (Workers Builds). The build command is
   `npm run build`, the deploy command is `npx wrangler deploy`.
2. `wrangler.jsonc` has the custom domain `world.mkfifo.com`: the deploy
   makes its DNS record and its certificate in the zone `mkfifo.com`.
3. Make the R2 bucket of the orders before the first deploy:
   `npx wrangler r2 bucket create world`. It needs no public
   access: the Worker reads it.
4. The Worker needs the Workers Paid plan: `edge.com` is about 31 MB (with no files of the catalog: the site serves them), and
   a build takes more CPU time than the Free plan gives.

To try it on this computer: `npm install && npm run build && npx
wrangler dev` (Wrangler makes a local R2). `BEAM_COM=PATH` uses a
`beam.com` of the computer in place of `npx beam.com`.
