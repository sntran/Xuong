# How to work on World

Read `README.md` first: it tells what World is, and the state of each
step. `docs/format.md` tells the format of a model. This file tells how
to work on the project, and the facts that are not in the code.

## The sources of truth

1. The code. When the code and a doc do not agree, the code is correct:
   change the doc in the same branch.
2. `docs/format.md`: the format of a part, an assembly, a voxel model,
   and of each file.
3. `README.md`: the product, and the state of each step ("Progress").
4. `specs/` and `docs/specs.md`: the flow of an order in TLA+. A change
   of the people of the world (`World.People`, `World.Run`) changes the
   specification in the same commit, and the replay test must pass.

An idea that is not a decision goes into `TODO.md`. The owner decides
about it.

## The rules of the owner

- Write all text in ASD-STE100 Simplified Technical English: docs, code
  comments, names, log text, error messages and commit messages. See
  `CONTRIBUTING.md`.
- Give each size of a part its source (`sources`): a standard, a data
  sheet, or a measurement. A size that is a guess says so.
- Each change has tests of its behavior, also for errors and limits.
  Write property tests (StreamData) where you can.
- Keep the coverage of the tests at 100%. Remove code that no feature
  uses.
- Keep each commit small, with one purpose. Write the message in the
  format of [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): description`. The types are `feat`, `fix`, `docs`,
  `test`, `refactor`, `perf`, `build`, `ci` and `chore`.
- Do the work on `main`, and push to `main` (the owner chose this for
  the start of the project). Open a pull request only when the owner
  asks.
- Commit with the identity of the owner, with no trailer:

  ```sh
  git -c user.name="Sơn Trần-Nguyễn" -c user.email=github@sntran.com \
    -c commit.gpgsign=false commit
  ```

- Look at each new or changed model on the review page
  (`scripts/shot.mjs`) before a commit, from the front, the side and
  three quarters. `FOCUS=x,y,z ZOOM=4` gives a close view of a point
  (an engine bay, the inside of a cabinet).

## The tools

- [BEAM.com](https://github.com/sntran/BEAM.com) 0.1.0-rc.6: Erlang/OTP
  29.1.1 and Elixir 1.20.4 in one file (`CONTRIBUTING.md`).
- The core of Wings 3D in `wings/`: the modules of the mesh, with no
  window (below).
- The Khronos glTF validator (`gltf-validator` on npm) for each GLB.
- [Accord](https://github.com/sntran/accord), the branch
  `feat/native-tla-checker` (dev and test only): the native TLA+ checker,
  with no Java, for `specs/` (`docs/specs.md`).
- The review page (`review/index.html`): three.js from a CDN, each model
  of `priv/models` from 12 cameras, with a slider for each joint.
  Playwright makes the pictures in CI. The replay page
  (`review/replay.html`) reads the log and the replay GLB of an order:
  `?log=URL&model=URL` for a local test.

## The contexts

`World` is the project. Each module under it is a part of the world.

| Module | What it holds |
|---|---|
| `World.Vec`, `World.Frame`, `World.Mesh`, `World.Shape` | Points, frames, meshes and the shapes of parts: the matter of the world. |
| `World.Part`, `World.Port`, `World.Assembly`, `World.Joint`, `World.Limb`, `World.Figure` | A part, its ports, an assembly of parts, a joint (hinge, slide or ball, with its limits), a limb (a chain of bones and its solver), a figure with a skeleton, its joints, its limbs and its props. |
| `World.Detail`, `World.Build`, `World.Scene`, `World.GLB`, `World.PNG` | The levels of detail (and `collect/1`: a full garbage collection after a big step of a build, for the 128 MB of the edge), the build of a model into a scene, the GLB writer, and the PNG writer for the textures that World makes. |
| `World.Kit` | Small helpers for the shapes of items (inches, round boxes, handles, feet). |
| `World.Materials` | `Stock` (tubes, lumber, sheets, extrusions), `Fasteners` (bolts, nuts, screws), `Construction` (bricks, blocks, lintels, tiles, panels). |
| `World.Framing` | T-slot extrusions, strut channel, L-track, and `Builds` from them. |
| `World.Buildings` | Walls, roofs, doors, windows and houses, from the materials. |
| `World.Furniture` | `Seats` (seats and benches), `VanBuilds` (a bed platform, a galley). |
| `World.Appliances` | The appliances of a house, and `Systems` (the water heater, the AC, the fans, the TV). |
| `World.Gear` | `PowerStations`, and `Camper` (the gear of a camper van). |
| `World.Vehicles` | `Wheels`, `Corners`, `Body`, `Hull`, the `Van` line and its stations, and each vehicle (`FordTransit`, `ChevyBolt`, `HondaVision`, `RoyalEnfieldHimalayan`, `TouringBicycle`). |
| `World.People` | The people of the catalog, `Human` (a person from the data of MakeHuman), `Face` (the 15 visemes for speech, from the units of the expressions of MakeHuman), `Skin` (the skin that is not like plastic: the sheen, the pores, the creases), `Data`, `Skeleton` (the joints: flex, spread, twist, limits, aim, look, the hips, the spine, the hands and the feet to points), `Joints` (the joints and the limbs of a person, for an order), `Props` (the props on the ports of the bones: a fan, a bottle, a nón lá), `Pose` (the poses, the shapes of a hand, the animations, the routines of exercise). `World.People.exercise/2` is a group at a morning of exercise. |
| `World.Rig`, `World.Blob`, `World.Subdivision` | A figure from bones, with a skin: a base mesh with its weights, a material for each face and a color for each point, smooth by subdivision (Catmull and Clark), or a smooth skin around the bones (a field of distances, surface nets); parts on bones (horns). |
| `World.Animals`, `World.Animals.Quadruped`, `World.Animals.Primate`, `World.Animals.Fish`, `World.Animals.Bird`, `World.Animals.Shape`, `World.Animals.UV`, `World.Animals.Space`, `World.Animals.Coat` | The animals: a species is numbers on a template mesh (`priv/animals/templates/`, `World.Animals.Shape`: the shape, the coat and the length of the fur by region; `World.Animals.UV`: the UVs, box charts for each bone; `World.Animals.Coat`: the texture of hair of a mammal, a PNG that World makes for each kind of hair (short, long, curly, wool); `World.Animals.Space`: a shape space learned from the templates, `scripts/shape_space.exs`) of a body plan in code. Four legs: the eleven animals of the Ultimate pack of Quaternius on one rig, from `scripts/gltf_figure.exs`, and the pig and the sheep of its Farm Animals Pack (`scripts/fbx_gltf.exs` reads the FBX files; they take the clips of the cow and the deer), with their clips (walk, run, idle, idle_low, eat, attack, kick, jump, jump_stop, hit_l, hit_r, death) from `scripts/gltf_clips.exs` in `priv/animals/clips/`. Primates: the mesh of a rhesus macaque of BigMaQ (`scripts/primate_template.exs`, MIT), on the bones of a person with the fingers, on four limbs or upright (the gibbon), with hands that grip, and the walk, the run and the sit of real macaques (`scripts/bigmaq_clips.exs`, CC BY). Fish (`World.Animals.Fish`) and birds (`World.Animals.Bird`): templates that World makes from their bones (`scripts/fish_template.exs`, `scripts/bird_template.exs`), with a swim, and a walk, a peck and a flap. Now: `street_dog`, `cat`, `wolf`, `fox`, `deer`, `goat`, `pig`, `horse`, `donkey`, `cow`, `water_buffalo`, `sheep`, `alpaca`, `husky`, `red_deer`, `hyena`, `macaque`, `rhesus_macaque`, `pig_tailed_macaque`, `douc`, `gibbon`, `carp`, `tilapia`, `chicken`, `duck`. |
| `World.Drawing` | A model in the data of an order: its check (each error with its path) and its build into an assembly. |
| `World.Orders` | An order in, the files out: `Blueprint`, `Blueprints`. |
| `World.Catalog` | Each model of the library by its name. |
| `World.Service`, `World.Application` | The HTTP service of the VM, and the application. |

The world of `docs/world.md`:

| Module | What it holds |
|---|---|
| `World.Clock` | The clock of the world: one second of the wall clock is one day of the world. |
| `World.Places`, `World.Yard` | The places (warehouses, factories by family, suppliers, sites) on the yard, the roads between them, the people and the vehicles. |
| `World.Stock` | The stock of a warehouse, with the limit of its store in bytes, and the files of its models in its store. |
| `World.Store` | The store of the files of a warehouse: the memory of the VM, a bucket (a folder on this computer), or the catalog of the release (read only). |
| `World.People.Person`, `World.Vehicles.Vehicle` | A person with a job (storekeeper, driver, worker, foreman), and a vehicle with its speed and its load. |
| `World.Plan` | The tasks of an order, from the tree of its assembly. |
| `World.Log` | The events of the world in the order of their time, in JSON, and their checks. `World.Log.Server` keeps the log of a run. |
| `World.Run` | A run of the world: the people of a yard as processes, a warehouse and four factories (the vehicles, the wheels, the seats, the houses), and one order at a time for each factory; the build of a place (`build/3`). |
| `World.Buildings.Plants` | The buildings of the places of the world: a warehouse with a rack for each 64 MiB of its store, a factory with room for its workers. |
| `World.People.Storekeeper`, `Driver`, `Foreman`, `Worker` | The jobs of the people as processes: the stock, the haul on the road, the plan and the tasks (and the orders to the other factories), the work of a task. |

## The core of Wings

`wings/` has a copy of the modules of Wings 3D that build, change and
read a mesh, from [dgud/wings](https://github.com/dgud/wings) at a fixed
commit (`wings/VERSION`). `scripts/wings.sh` copies them again from a
new commit. The copy changes only these things:

- `wings.hrl` has no lines that include the headers of wx and SDL.
  `-include_lib("wings/e3d/e3d.hrl")` becomes `-include("e3d.hrl")`.
- Three small modules take the place of modules of the window:
  - `wings_pb` (the progress bar): each call does nothing.
  - `wings_lang` (the texts): `str/2` gives the default text.
  - `wings_plugin`: `check_plugins/2` gives `[]` (no plugin state to
    keep in a merge).
- No image codecs of `e3d` (`e3d__png`, `e3d__tif`, and more).

`intl_tools` (the parse transform of the texts) compiles first.

## The decisions

| Topic | Decision | Why |
|---|---|---|
| The name | World: the OTP app `:world`, the module `World`, and a context of the world for each family of things (`World.People`, `World.Vehicles`, `World.Buildings`, `World.Materials`). The repository is `sntran/World`, the Worker is `world` at <https://world.mkfifo.com>, and the R2 bucket is `world`. | The project builds things as the real world does: people, materials, warehouses and factories. Each context is one part of the world, not a kind of file. |
| The levels of a model | Standard parts, shaped parts, assemblies. | A model is made as a real thing is made. The joints and the list of the parts come from the connections. |
| The language | Elixir, on BEAM.com. | DIY and Phượt are Elixir. The core of Wings is Erlang, and runs in the same VM with no window. |
| The source of a shape | Code for a standard part. A `.wings` file for a shaped part. | Wings 3D is free, small, and in Erlang. A person can open each part, change it, and save it. |
| The one format | GLB (glTF 2.0) for the screens. STL only for a printer. | Godot, three.js, Android and MapLibre read GLB. GLB has nodes for the joints, materials, and levels of detail. STL has none of them. |
| The joints | From the connections of an assembly. Rigid joints first (each part follows one joint). | They cover vehicles, furniture, machines and the figures of Tre. A person has a skin (a mesh that bends) from the skeleton of MakeHuman. |
| The people | The data of MakeHuman (CC0) in `priv/makehuman/`: a body from its numbers, the skeleton `game_engine`, skins, hair and clothes. A low-poly body of MakeHuman at mid and far. | Real shapes and real weights, free to use. A person is a `World.Figure`, and an assembly holds it at its port `hips` or `ground`. |
| The animation | Data in the format (poses), not a timeline in Wings. | The apps move the models in code: the wheels turn with the speed, the legs of Tre swing in a walk. |
| Voxels | A separate kind of model in `.vox`, and a voxel maker from any model. | The mesh of Wings cannot hold blocks that touch at an edge or a corner. Tre needs blocks at its own sizes. |
| The axes | Right hand: x to the right side, y to the front, z up, in meters. The origin of a model on the ground at the center of its box. | One rule for each model. The GLB writer turns the axes with no mirror. |
| The colors | A role of material. The palette of the package, and a palette of each app. | One model, the colors of each app. |
| The files of the build in Git | Yes, with a check in CI. | An app reads the files with no build. |
| The way the projects use World | A web service, the factory at <https://world.mkfifo.com> (`docs/factory.md`), not a library in each app. | Phượt, DIY and Vũng Tàu are on Cloudflare. A model has a URL, and a correction of World reaches them with no new deploy. |
| Orders | Data in JSON, never code: a blueprint, its options, colors and joints. The hash of the full order names its files. | An order can come from any project and any language. The same order gives the same files. |
| Realism | The sizes from a standard, a data sheet or a drawing, and the shape from photos of the real thing, never from a memory. A render and a photo side by side before a commit. | Phượt and Vũng Tàu need models that look real. |
| The world | The next step of World (`docs/world.md`): people, warehouses, factories and vehicles build the models, and each thing of the world is one real thing of the computer, with real times. The owner decided to rename the project "World" after the foundation of the world is in place, not before. | A model is made as a real thing is made; the world makes it as the real world does. One rename, at one time. |
| The license | AGPL-3.0. The core of Wings keeps its own terms in `wings/LICENSE`. | The models stay free, and nobody can close them. |

## Known problems

These come from the tests before the repository, with the core of Wings
on BEAM.com, on the 77 models of DIY, the shape kinds of Tre, and 42
trees from Blender:

- **Floats only.** The core of Wings fails on a box or a prism with
  integer points. `World.Mesh` changes each point to floats.
- **A flat face has two faces.** One polygon alone fails in
  `wings_we_build`. A flat part (a label, a window) has its front and its
  back.
- **One order of corners.** A mesh with faces in two orders fails in
  `wings_we_build:combine_half_edges`. A function that makes a mesh gives
  each face the same order, then turns the whole mesh when its volume is
  less than 0.
- **The name of a material is an atom.** A face with a string as its
  material fails in `wings_we_build:mat_face`.
- **`wings_we:build/2` can give `error`** with no exception. The code
  checks the result, not only the exceptions.
- **Hidden faces.** The core of Wings closes each open edge loop with a
  hidden face (a hole, a negative face number). The GLB writer takes
  only the visible faces (`wings_we:visible/1`), and the triangulation
  too.
- **Blocks and bad meshes become many objects.** Blocks that touch at an
  edge, points where two fans of faces meet, and pieces with faces in two
  orders go through the last steps of the import of Wings: one object for
  each piece or each face. `World.Mesh.clean/1` (`docs/format.md`) does
  the repair first.
- **Speed.** In the interpreter of BEAM.com, most models build in less
  than 2 seconds. A tree with 19,000 triangles in many small objects
  takes 20 to 26 seconds. A model has a time limit in its test.
- **The `.wings` file of a person is not safe data.** `binary_to_term`
  with no `:safe` can make new atoms. The reader is strict
  (`docs/format.md`, "Wings files").
- **Each part is one task of the world.** A house of bricks has 5,206
  tasks: its order runs in about 2 seconds here, and its log has 3 MB at
  the far level. An order of the site runs the world for each file of
  the GLB and the log, so the edge does the work two times for a new
  order. Step W7 measures it at the edge.
- **A group of people is heavy.** An `exercise` group of 7 people builds
  in about 17 s on this computer at the mid level (5 s at far), and its
  file has 4.8 MB (1.5 MB at far): each person is a full person with its
  own animation. In the interpreter of the VM it is about 10 times
  slower. Use the far level for a group, or a `person` with a routine
  for each place. At the edge (128 MB) a group of 2 or 3 people builds
  at the far level (about 650 KB, 12 to 15 s), and a group of 4 or more
  stops the builder: build it on a computer (`mix world.order`) until F4.
- **One build at a time in a VM.** Two cold builds at one time in one
  builder (4 builders, by the first digit of the hash) stopped the VM
  (128 MB). `World.Service` builds one file at a time (`:global.trans`);
  the next request waits. A near level of the car or the van, alone,
  still stops the VM (F4). F4 part 1 took the peak of a near person
  from 132 to 90 MB natively (`docs/factory.md`); it is not measured
  at the edge yet.

## The steps

Each step is one branch and one pull request in `sntran/World`, or in the
app that uses the models.

| Step | Result | Check |
|---|---|---|
| 0. The plan | `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `docs/format.md`, `LICENSE`. | The owner agrees, or changes them. |
| 1. The project and the core of Wings | Mix project, `wings/` with `scripts/wings.sh`, `World.Mesh` (build, smooth, triangulate, clean), `World.GLB`, the review page, CI on BEAM.com with the validator. | A box, a cylinder, a lathe and a loft give GLB files with no error and no warning. `scripts/wings.sh` twice gives the same files. Coverage 100%. |
| 2. Standard parts | `World.Parts`: bolt, nut, washer, bearing, tube, sheet, lumber, extrusion, rim, tire, wheel. Each with its ports and its sources. | Property tests: each size agrees with the table of its standard. Each part on the review page. |
| 3. Assemblies and joints | `World.Assembly`, `World.Connection`, joints, poses, the list of the parts, the three levels, `mix world.build` and `--check`. The Honda Vision 110 from parts. | The wheels and the bars turn on the review page. The list of the parts of the scooter. The triangles of each level are in their limits. The build gives the same bytes twice. |
| 4. Phượt uses World | The vehicle next to the avatar of Phượt is the far level of its model. It moves a little in a drive (the wheels turn, the body bobs), and stops when the vehicle stops. | On a phone of 390 px, in Phượt. With `prefers-reduced-motion`, nothing moves. |
| 5. Wings files | `World.Wings.read/1` (strict) and `write/2`. Shaped parts from `.wings` files. The body panels of the scooter as shaped parts. | A file that `write/2` makes opens in Wings 3D on the desk of the owner, and `read/1` reads its change. A file with an unknown atom is refused. |
| 6. The Wings plugin | `wpc_world`: ports and joints in the plugin state of the file, a command to try a pose, the axes in the view. | The data and its export: tests here. The window: the owner tries it in Wings 3D. |
| 7. DIY uses World | The models of DIY as assemblies of World. DIY draws its SVG from them, and depends on `:world`. | The pictures of DIY do not change: its tests compare the frames before and after. |
| 8. Voxel models | `World.Voxel`: `.vox` read and write, the voxel maker. In Tre: the stamp of a `.vox` model into the fine grid. | A stool and a cart of World in the world of Tre, with the colors of Tre. A `.vox` file opens in Goxel. |
| 9. STL for a printer | `World.STL`, a file for each material, the checks of a print (closed, outside, thick enough, the size). | A slicer (PrusaSlicer) slices the scooter at 1:43 with no error. |
