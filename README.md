# World

World makes things as the real world makes them. People, materials,
warehouses, factories and vehicles build each thing from the ground up:
a bolt, a seat, a van, a house. World makes the 3D models of the
projects of the owner: [Phượt](https://github.com/sntran/phuot),
[DIY](https://github.com/sntran/DIY), [Tre](https://github.com/sntran/Tre),
[Vung_Tau](https://github.com/sntran/Vung_Tau) and
[Humans_Must_Die](https://github.com/sntran/Humans_Must_Die).

A model in World is made as a real thing is made: from real parts.
A bolt, a bearing, a wheel and a panel are parts. A scooter is an
assembly of parts and of smaller assemblies. Each part has its real size,
from a standard or from a measurement, in meters.

The library writes each model as GLB (glTF 2.0, binary): one format for
the screens of each project. It also writes STL for a 3D printer, and a
list of the parts (a bill of materials).

World is also a factory: a web service at <https://world.mkfifo.com>. Each
model has a URL, and a correction of World reaches each project with no
new deploy of the project. `docs/factory.md` tells how it works.

The world (`docs/world.md`) builds each order: people, warehouses,
factories and vehicles build the models as in the real world, from the
ground up, with real times in a log. The replay page shows the log of
an order. The flow of an order is a TLA+ specification, and the log of
each run of the code replays as one of its behaviors
(`docs/specs.md`).

## Why

Four projects draw 3D things, and none shares its models with another:

| Project | Language | Its models | How it draws |
|---|---|---|---|
| DIY | Elixir | Parts in code (box, cylinder, prism, face): about 60 kinds of items of a house, 9 camper vans, an electric car, power stations | SVG on the server |
| Tre | JavaScript | A world of blocks (voxels), figures of parts on pivots, smooth meshes for the living things | three.js |
| Vung_Tau | GDScript (Godot) | Boxes and cylinders in code, trees from Blender (not final) | Godot |
| Phượt | Elixir, Kotlin | None yet: the vehicle next to the avatar is a line icon | MapLibre, Android |

The projects use four languages, so one library of code cannot serve
them all. A file can: each project reads GLB. World is a library in
Elixir that makes the files, and the files are in the repository and in
each release.

## The three levels of a model

1. **Standard parts.** A function makes the part from its numbers and its
   standard: a bolt from its thread and its length (ISO 4014), a nut
   (ISO 4032), a washer (ISO 7089), a bearing (the 6000 series), a tube,
   a sheet, a piece of lumber, an aluminum extrusion, a wheel from the
   size of its rim and the code of its tire (ETRTO: 100/90-14).
2. **Shaped parts.** A part with a free shape: the body panel of a
   scooter, a seat, the door of a fridge. A person makes it in
   [Wings 3D](https://www.wings3d.com/), and the repository keeps its
   `.wings` file.
3. **Assemblies.** A tree of parts and smaller assemblies. Each child
   connects to its parent at two ports: for example, the axle bolt goes
   through the hub of the wheel and through the fork. The kind of the
   connection (fixed, hinge, slide) gives the joints of the model.

Tre also needs **voxel models** (models of blocks). They are a separate
kind, in the MagicaVoxel format (`.vox`). A tool of World makes the voxel
version of any model, at the size of a block (`docs/format.md`, "Voxel
models").

## The ideas

- **Real parts, real sizes.** The size of each part comes from a
  standard, a data sheet or a measurement, and the model says which
  (`sources`). A wheel of the scooter and a wheel of the food cart are
  the same function with other numbers.
- **The joints come from the parts.** The axle bolt of a wheel is the
  axis of the joint of the wheel. The bearing of the steering stem is the
  axis of the steering. A hinge is the axis of a door. Nobody draws a
  joint by hand.
- **A model knows its parts.** The build writes the list of the parts of
  each model, with their counts: a van of DIY gives the screws, the
  lumber and the batteries that its build needs.
- **Detail for the size on the screen.** A scooter has hundreds of bolts.
  The build writes three levels of detail (near, mid, far), and drops the
  parts that are too small for a level, or that a body hides.
- **The core of Wings in Elixir.** The library uses the mesh core of
  Wings 3D (Erlang) with no window: the same mesh, the same smooth
  (Catmull-Clark) and the same file format as the program on the desk.
  A person can open each part in Wings 3D, change it, and save it.
- **Code is the source.** A standard part and an assembly are code. A
  shaped part is a `.wings` file. The GLB, STL and list files are the
  output: the build makes them again, byte by byte, and CI compares them.

## Progress

| Step | Result | State |
|---|---|---|
| 0. The plan | This file, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `docs/format.md`. | Done |
| 1. The project and the core of Wings | A Mix project on [BEAM.com](https://github.com/sntran/BEAM.com). The core of Wings 3D in `wings/`. `World.Mesh`, `World.GLB`, the check of the Khronos validator, the review page. CI. | Done |
| 2. Standard parts | Bolts, nuts, washers, bearings, tubes, sheets, lumber, extrusions, wheels and tires, each from its standard, with its ports. | Done |
| 3. Assemblies and joints | Connections, joints, the list of the parts, three levels of detail, GLB with a node for each joint. The vehicles of Phượt: the Honda Vision 110, the Chevrolet Bolt EV, the Ford Transit 148 camper, the Royal Enfield Himalayan, a touring bicycle. | Done |
| 3b. People | People from the data of MakeHuman (CC0): the shape of the body from its numbers, a skeleton of 53 bones with a skin, 18 skins, 10 hairs, 22 items of clothes, 9 colors of the eyes, 12 eyebrows, a color for the hair and for each item of the clothes, poses ("stand", "sit", "ride", "drive"), a skeleton with the joints of a body (flex, spread and twist, limits, the aim of an arm, the look of the face, the hips, the spine, the hands and the feet to points, the shapes of a hand, the mirror of a side), the routines of a morning of exercise in a loop (tai chi, yoga, aerobics) and a group that does them, the animations "walk", "wave" and "point", the size of the head, a helmet on two wheels, the joints of a body in an order (`elbow_r`, `shoulder_r.spread`), ports on the bones (the grips, the crown, the back, the soles) with props that follow the bones (a tai chi fan, a bottle of water, a nón lá), and the three levels. A traveler, a man and a woman of Việt Nam, and a rider on the Honda Vision 110. The traveler of Phượt on each vehicle, riding or parked. With `speech`, the teeth (with the gums), the tongue and the 15 visemes of Meta as morph targets, for lip sync; with `expressions`, 30 face shapes of ARKit (a blink, a smile, the brows), with the eyelashes and the eyebrows. | Done |
| 3c. Animals | Figures from bones (`World.Rig`): the data of a rig in, a figure with a skin out. A species is data of a body plan. The four-legged animals are numbers on thirteen template meshes (eleven on one rig from the Ultimate Animated Animal Pack of Quaternius, and the pig and the sheep of its Farm Animals Pack; the shape and the coat by region, as SMAL for animals and MakeHuman for people): a street dog of Việt Nam (chó cỏ), a cat (mèo ta), a wolf, a fox, a deer, a goat (dê cỏ), a pig (lợn Móng Cái), a horse, a donkey, a cow (bò vàng), a water buffalo (trâu), a Suffolk sheep, an alpaca, a Siberian husky, a red deer stag and a spotted hyena (from the shape space), and any other from the numbers of an order. The primates are numbers on the mesh of a rhesus macaque of BigMaQ (MIT), on the bones of a person: a long-tailed macaque (khỉ đuôi dài), a rhesus macaque (khỉ vàng), a northern pig-tailed macaque (khỉ đuôi lợn) and a red-shanked douc (voọc chà vá chân nâu) on four limbs, and a northern white-cheeked gibbon (vượn đen má trắng) on two legs. The fish are numbers on a template that World makes from its bones (a smooth skin, fins and eyes): a common carp (cá chép) and a Nile tilapia (cá rô phi), that swim. The birds are numbers on a template that World makes in the same way: a hen of Việt Nam (gà ta) and a white duck (vịt), that walk, peck and flap their wings. Each with its joints, limbs, ports and animations: the four-legged animals walk, run, rest and eat with the clips of their template on the bones of their shape; the primates walk, run and sit (the moves of real rhesus macaques, from the motion data of BigMaQ), climb a trunk, hang from a branch and jump, with hands that grip. Each animal has UVs for a texture that repeats and the length of its fur at each point (`_FUR`), so an app can draw its fur; the review page draws it. A mammal has a texture of hair that World makes (short, long, curly or wool), and bare skin with no hair (the face, the ears and the hands of a macaque); the eyes of a primate have an iris and a pupil, and its face has morph targets for its expressions (an open mouth with teeth, a grimace, a lip-smack, the brows up) that move the points and the normals. A shape space learned from the eleven templates on the Ultimate rig (as SMAL) gives the wolf the shape of any of them, or a shape between them. | Done |
| 3d. Drawings | A model in the data of an order (`World.Drawing`): parts from shapes (box, cylinder, sphere, prism, lathe, tube) and ports, nodes with joints, items of other blueprints (a person, an animal, a model of the catalog), clips of the joints, each error with its path. A cart of bánh mì with its seller and a dog. | Done |
| 4. Phượt uses World | The vehicle next to the avatar of Phượt is the model of World, and it moves with the trip. | To do |
| 5. Wings files | A strict reader and a writer of `.wings`. Shaped parts from `.wings` files. The clean-up of a mesh before Wings takes it. | To do |
| 6. The Wings plugin | `wpc_world` for Wings 3D: ports and joints in the file, a pose to try, the axes in the view. | To do |
| 7a. The items of DIY | The appliances (a fridge, a washer and a dryer, a dishwasher, a range, a microwave, a freezer, a water heater, the AC, a mini split, a ceiling fan, a TV), the seven power stations, the gear of a van (a LiFePO4 battery, the Victron MultiPlus-II, SmartShunt, Lynx Distributor and Orion XS, a battery switch, a 12 V fridge, a roof fan, a diesel heater, a water tank, a solar panel), and builds of wood (a bed platform, a galley) with their lumber and screws. Doors, lids, drawers, fans and knobs are joints. | Done |
| 7b. Houses | The materials (bricks of Việt Nam and of the US, concrete blocks, lintels, lumber, OSB, siding, clay tiles, metal panels, hinges), walls of masonry and of wood studs with openings, gable roofs, doors and windows that open, and houses from them: a house of bricks of Việt Nam with a roof of tiles, a cabin of wood with a metal roof. The list of the parts counts each brick, stud, tile and panel. | Done |
| 7c. Framing systems | T-slot extrusions (80/20 10 and 15 series, metric 20, 30 and 40 mm) with T-nuts, corner brackets and button head screws; strut channel (Unistrut P1000 and P1000T) with spring nuts, fittings and threaded rod; L-track with fittings that slide. Inch threads for the fasteners. Builds: a shelf of 80/20, a rack and a trapeze of strut channel, a floor with L-track. | Done |
| 7d. The engine bay | The hood of the Ford Transit opens on its engine bay: the 3.5 L V6 with its belt and pulleys, the radiator and its fan, the air box, the reservoirs and the fuse box. In the bay, the two items of DIY for the engine bay: the REDARC BCDC1250D (a DC-DC charger of 50 A) and a second alternator of 250 A with a pulley that turns. The parts in the bay are only in the near level. | Done |
| F1. The factory: the site | `docs/factory.md`. The Worker at <https://world.mkfifo.com>: the review page, and each file of the catalog at `/models/NAME.glb`, with CORS, an ETag and a cache of 5 minutes. | Done |
| F2. The factory: orders | Blueprints with options (`catalog`, `person`, `traveler`, `house`, `extrusion`, `strut`, `l_track`), orders in JSON with colors and joints, the receipt, `mix world.order`, the VM of World in the Worker (`World.Service`), and the files of each order in R2. | Done |
| F3. The factory: vans | The blueprint `van` (`World.Vehicles.Van`) from the traces of DIY and the photos of dealers: the Ford Transit 148 in with a high roof, a medium roof, or extended. The options: the windows (cargo, crew, passenger), the items of DIY in the engine bay, and the items on the roof (a roof fan, a solar panel; the camper of Phượt has none). The seats are parts of their own (`World.Furniture.Seats`: a base, a cushion on its track, a back that reclines, the headrests), on the mounting points of the floor of each make; the catalog has a seat and a bench of a van. The doors open, the wheels turn and steer. The Sprinter and the ProMaster come after their photos (`TODO.md`). | Done |
| F4. The factory: memory | Less memory for the near level at the edge. (The data of people is in `priv/` now, so the release has it.) Part 1: a full collection after each big step and sparse morph targets (the near person 132 to 90 MB natively; `docs/factory.md`). | In progress |
| W0. The world: the plan | `docs/world.md`: the places, the factories by family, the people and their jobs, the vehicles that drive on the roads of the yard, the stock, the clock, the log and the replay; what each thing is in the computer; the steps W1 to W9. | Done |
| W1. The world: its data | `World.Clock`, `World.Places`, `World.Yard`, `World.Stock`, `World.People.Person`, `World.Vehicles.Vehicle`, `World.Log`, and `World.Plan`: the tasks of an order from the tree of its assembly. | Done |
| W2. The world: one thin slice | One order of the van through a warehouse, a truck with its driver on a road, and a factory with a foreman and two workers. The people are processes, and each act is an event of the log at its real time. The flow is a TLA+ specification (`specs/Order.tla`): the native checker of Accord checks it, and the log of a run replays as one of its behaviors. | Done |
| W3. The world: the replay | The orders of the site go through the world: the log of each order (`/o/HASH.log.json`), the model with a node for each task (`/o/HASH.replay.glb`), and the replay page (`/replay.html?order=HASH`). `docs/specs.md` tells the specifications and their checks. | Done |
| W4. The world: the factories | The wheel factory and the seat factory next to the vehicle factory. A smaller assembly of another family is an order to the factory of its family, and its truck brings it by road. | Done |
| W5. The world: the buildings | The people build the warehouse and the factories as orders to the houses factory. A warehouse has a rack for each 64 MiB of its store, and the replay shows how full they are. | Done |
| W6. The world: the stores | The stock is the files: each warehouse has a store (the memory of the VM, a bucket, or the catalog of the release). A full warehouse refuses the model, and the driver brings it to the annex. A second order gets the same files from the stock. | Done |
| W7. The world: the measures | Each run has its time and its memory in its log. An order of Phượt gives its files and its log, and the times agree with the service. The release is 31 MB (no catalog files in it), so the site can deploy again. | Done |
| W8. The world: the other vans | The ProMaster with a high roof (136 in, 159 in, 159 in extended), from the render and the sizes of Ram; the Sprinter with a high roof (144 in, 170 in, 170 in extended), from the drawing and the tables of the guide of Mercedes-Benz. The crew van waits for photos. | In progress |
| W9. The world: the engineers | Later, with the owner. | To do |
| 7. DIY uses World | DIY draws its SVG from the models, and keeps its pictures. | To do |
| 8. Voxel models | The `.vox` reader and writer, the voxel maker, and the stamp of a model into the grid of Tre. | To do |
| 9. STL for a printer | STL at a scale, for each material too, and the checks of a print. | To do |

`AGENTS.md`, "The steps", gives the check of each step. `TODO.md` has
the ideas for later.

## Use the models

A project reads the files from the site, for example in three.js:

```js
const gltf = await new GLTFLoader().loadAsync('https://world.mkfifo.com/models/ford_transit_148_camper.mid.glb');
```

| URL | What |
|---|---|
| `/models/list.json` | The names of the models. |
| `/models/NAME.glb`, `NAME.mid.glb`, `NAME.far.glb` | A model at each level. |
| `/models/NAME.parts.json` | The list of its parts. |
| `/palette.json` | The default color of each material role. |
| `/version.json` | The commit of World that the site has. |
| `/blueprints` | The blueprints and their options. |
| `POST /orders`, `/o/HASH.glb` | An order in JSON, and the files of the order. |
| `/o/HASH.log.json`, `/replay.html?order=HASH` | The log of the people that built the order, and its replay. |
| `/m/BLUEPRINT.glb?OPTION=VALUE` | An order in the URL, for example `/m/strut.glb?length=0.6&kind=solid`. |

`docs/factory.md` tells the details. An Elixir app can also add the package and call its functions:

```elixir
{:world, github: "sntran/World", ref: "COMMIT"}
```

To try the site on this computer: `npm install && npm run build && npx
wrangler dev`.

## The license

The code, the models, and the files that the build makes are under the
**GNU Affero General Public License 3.0** (`LICENSE`):

- Each person can use, change, share and print the models.
- A person who changes them and gives them to others, or runs them in a
  service on the web, must give the changes under the same license.
- The models come with no warranty (sections 15 and 16 of the license).
  A print of a model is a model. Do not use it as a part of a vehicle or
  to hold a load.

The owner has the copyright, so the other projects of the owner use the
models with no change to their own licenses. A model from another person
comes in only when that person agrees to the AGPL-3.0
(`CONTRIBUTING.md`).

The core of Wings 3D in `wings/` keeps its own license (`wings/LICENSE`,
the terms of Wings 3D: free use, copy and change, with its copyright
notice kept). An asset from outside keeps its own license in its own
folder, with a line in `CREDITS.md`.
