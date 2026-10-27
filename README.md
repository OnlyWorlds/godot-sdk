# OnlyWorlds SDK for Godot (spike)

A GDScript addon that reads OnlyWorlds world folders and `.owworld` files into typed elements, and writes them back
in the format's own bytes. Godot 4.7, the standard build (no C#). Not released; private at `OnlyWorlds/godot-sdk`.

```gdscript
var world := OWWorld.read_folder("C:/worlds/moppetopia")
for pin: OWPin in world.of_type("pin"):
    print(pin.name, " at ", pin.x, ",", pin.y)          # x, y from the map's bottom-left

var r := OWWorldArchive.read_file("moppetopia.owworld")  # every section 4.7 rule; r.reason on a refusal
if r.ok:
    var w := r.to_world()
OWWorldArchive.pack("C:/worlds/moppetopia", "C:/out/moppetopia.owworld")

var link := OWAddress.parse_link("ow://character/019a1f3c-2b4e-7d10-8c3a-6f2e9b0d4a71@302")   # link.reason on a refusal
var url := OWAddress.element_address(OWAddress.HUMAN, world_id, "pin", pin.id).address

var world := {"elements": bodies, "now": 1200}                 # bodies as the owner is served them
var seen := OWLens.resolve(world, lens_id, {"rung": "guest", "whole": ids}, {"as_of": 1195})
for row in seen.rows: print(row["name"])                         # seen.cut: what was left out, by reason
var g := OWGraph.world_graph(world, {"rung": "owner"}, {"lens": lens_id})   # nodes, edges, edges_cut
```

## Layout

| Path | What it is |
|---|---|
| `addons/onlyworlds/` | the library: copy this folder into a project (the classes work without enabling the plugin) |
| `addons/onlyworlds/models/` | one `class_name OW<Type>` per element type, **generated**; `ow_element.gd`, `ow_world_info.gd`, `ow_types.gd`, `ow_schema_pin.gd` and `unicode/ow_unicode_data.gd` are generated too |
| `codegen/generate.py` | the emitter (Python standard library); `--check` is the drift guard |
| `codegen/PIN`, `codegen/schema-dist/` | the pinned schema-dist (tag and manifest sha256), vendored verbatim; never edit it |
| `tests/` | the headless suite; `tests/data/unicode_vectors.txt` is generated |
| `tools/` | `pack.gd`, `extract.gd` (shell tools), `check_writer.py` (the reference checker's verdict on a file), `probe_numbers.gd` |
| `demo/moppetopia_map.tscn` | a world in a scene: the root Map's image with its Pins |

## Running

```sh
python codegen/generate.py --check                               # the pin holds, the generated files are current
godot --headless --path . --import                               # once per clone: registers the class_name scripts
godot --headless --path . --script res://tests/run.gd            # exits 0 only when every test passes
python tools/check_writer.py out.owworld                         # run_py.py's reader and check_writer on a file
godot --path . --write-movie frames/map.png --quit-after 4 res://demo/moppetopia_map.tscn
godot --headless --path . --export-release "Windows Desktop" build/windows/ow-godot-demo.exe   # needs 4.7.2's templates
build/windows/ow-godot-demo.exe -- --world=<folder | file.owworld> --capture=frame.png
```

The exported demo (Windows x86_64, 2026-10-24) reads Moppetopia from a folder and from an `.owworld`, and both
frames are byte-identical to the editor's.

The tests read Sikelia and Moppetopia from their places on this machine (`OW_SIKELIA`, `OW_MOPPETOPIA` override); a
test whose world is missing is skipped, never passed.

## What it holds to

- **Writing** (DECISIONS #2): an element nobody edited is written back as the bytes it was read with; an edited one in
  folder spec section 5's form (`OWJson`: key order kept, an integral float written as an integer, JavaScript's
  number layout and escapes).
- **Reading an archive** (DECISIONS #4): its own central-directory walk, zlib through a gzip frame for the CRC and
  size, a GDScript CRC-32 for stored entries, NFC and CaseFolding 15.1 tables for collisions.
- **Addresses** (the address profile, serial 77): `ow://` links and the site's URL, read and written as the npm and
  Python packages do: every case of the profile's fixture, the reader's refusals in its order, the writer's
  `bad_form`, `segments`, `no_world` before them, a moment of `3.0` the step 3, an empty string present.
- **Lenses** (the lens profile, serial 78; its graph section, serial 81): `OWLens` reads a saved way of reading a world
  (`is_lens`, `is_template`, `check_keys`, `lenses_in_use`, `resolve`, `date_of`) and `OWGraph` the world as nodes and
  edges (`world_graph`, `degree_of`), as the npm and Python packages do: every case of the profile's fixture (122,
  the graph kind's 34 included), their shared edge file, and 6,000 random readings answered alike by the Python
  package. A JSON number with no fraction is whole (`7.0` reads as 7); past 64 bits it is not.
- **Writing an archive**: its own zip bytes: the marker stored first, UTF-8 byte order, fixed 1980 stamps, methods 0
  and 8, zip64 from 65,535 entries.
