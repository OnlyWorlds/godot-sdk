# OnlyWorlds SDK for Godot

Your [OnlyWorlds](https://www.onlyworlds.com) world, its characters, locations and laws, as typed objects in your
Godot game.

A GDScript addon. It reads and writes worlds through the OnlyWorlds API, and reads and writes them on disk as world
folders and `.owworld` files, with a class for each of the 22 element types. It runs on the standard Godot build; no
.NET is needed.

## Install

Godot 4.7, the standard build. Earlier 4.x versions are untested.

1. Copy the `addons/onlyworlds/` folder of this repository into your project's `addons/` folder.
2. Open the project in the editor once (or run `godot --headless --path . --import`), so Godot registers the `OW…`
   classes.

Enabling the plugin under **Project Settings → Plugins** is optional: the classes work without it.

## First run

This reads Moppetopia, a public sample world, with its demo key. No account needed.

```gdscript
extends Node

func _ready() -> void:
	var client := OWClient.new({"api_key": "0000000001"})   # demo key: Moppetopia, read-only
	var world := await client.get_world()
	if not world.ok:
		print(world.error)   # no connection, or the server said why
		return
	print(world.value["name"])

	var found := await client.list("character", {"name_contains": "fluffington"})
	print(found.value.data[0].name)
```

Attach it to any node and run the scene. The Output panel shows `Moppetopia`, then `Admiral Fluffington`.
`await client.list_all("character")` pages through every character. In this repository the same script is
`demo/first_run.tscn`.

## Your own world

Create a world at [onlyworlds.com](https://www.onlyworlds.com); its keys are on the world's page. A new key is shown
once, so copy it then.

- **`ow_r_`** reads, with no PIN. This is the key to ship in a game.
- **`ow_w_`** reads and writes. Writes also send a secret as `api_pin`. For code, use an
  [agent seat](https://onlyworlds.github.io/docs/development/agents): it has its own key and secret (`ow_s_…`),
  works in one world, and the world's owner can remove it at any time. The account PIN works too, but it opens every
  world on the account.

```gdscript
var client := OWClient.new({"api_key": seat_key, "api_pin": seat_secret})   # ow_w_…, ow_s_…
var made := await client.create("character", {"name": "The Brine Cartographer"})
await client.patch("character", made.value.id, {"description": "Maps the tide lines."})
```

`patch` sends only the fields you pass; `delete("character", id)` removes one. Every call answers a reply with
`value` on success, else `error` (an `OWApiError` that says why). Keep write keys out of games you ship: a key written
in a script, a scene or an exported variable is packed into the export, where anyone with the build can read it, so
read write credentials at runtime.

**A player link** (`https://www.onlyworlds.com/join#ow_j_…`, made by a world's owner for one Character) needs no
account. Redeem it once for that player's read key; the server then shows the key only what that Character may see.

```gdscript
var code := OWJoin.parse_link(pasted)           # "" when the text holds no code
var joined := await OWJoin.redeem(code)         # the code is spent: keep joined.value.key
var client := OWClient.new({"api_key": joined.value.key})
```

`OWJoin.preview(code)` says who invites, to which world, without spending the code.

**A world on disk.** `OWWorld.read_folder(path)` reads a world folder, `OWWorldArchive.read_file(path)` an `.owworld`
file (one zip that holds a folder), and both give the same typed elements. A world you never edited is written back
byte for byte. This repository carries a small example world, Hyperion, at `codegen/schema-dist/example/hyperion`;
`demo/world_map.tscn`, the project's main scene, draws its Map with its Pin.

## What's in it

| Part | Classes | What it does |
|---|---|---|
| **Client** | `OWClient`, `OWJoin` | The API: read a world, list and page through its elements, the change feed, writes (create, upsert, patch, delete, link edits, bulk), joining by invite link. |
| **Models** | `OWCharacter`, `OWLocation`, … (all 22), `OWElement` | One class per element type, generated from the schema; `OWTypes.make(type, body)` builds the right one. |
| **On disk** | `OWWorld`, `OWWorldArchive`, `OWJson` | World folders and `.owworld` files, read and written in the folder format's own bytes. |
| **Readers** | `OWLens`, `OWGraph`, `OWLanding`, `OWMapSpace`, `OWCharter`, `OWStrand`, `OWRecord`, `OWReport`, `OWMessage`, `OWNames`, `OWViews` | Pure readers over a world as one reader sees it: a saved lens, the world as nodes and edges, its first picture, its maps as geometry, its charter, its story in miniature, messages and reports, how an element is shown. |
| **Helpers** | `OWCalendar`, `OWAddress`, `OWOpeners`, `OWTools`, `OWId`, `OWUnicode` | A world's own calendar, `ow://` links, an "Open with" menu of OnlyWorlds tools, ids, name comparison. |

Every call, with what it answers and what it refuses: [docs/reference.md](docs/reference.md).

## How it follows the standard

The 22 models are generated from one pinned release of the
[schema distribution](https://github.com/OnlyWorlds/schema-dist) (`codegen/PIN`; `OWSchemaPin` names it at run time),
vendored unchanged in `codegen/schema-dist/`. Each reader answers every case of its profile's shared fixture, the same
cases the TypeScript, Python and Unity SDKs answer, and every request the client makes is checked against the API's
own document (`tests/data/keel-wire.json`; keel is the server behind onlyworlds.com). The reference explains the
standard's words used in this repository (keel, serial, rung).

## Working on the SDK

Open this repository as a Godot project. Its main scene is the map demo.

```sh
godot --headless --path . --import                               # once per clone, and after a pull that adds a class
godot --headless --path . --script res://tests/run.gd            # the suite: exits 0 only when every test passes
python codegen/generate.py --check                               # the schema pin holds, the generated files are current
python codegen/generate_tools.py --check                         # the tools list's pin holds, ow_tools.gd is current
python codegen/generate_layout.py --check                        # the layout tables and their bits are current
python codegen/generate_layout_3d.py --check
python codegen/generate_frame_bits.py --check
python codegen/test_generate_views.py                            # generate.py refuses a views.json that breaks a rule
godot --path . res://demo/world_map.tscn -- --world=<folder | file.owworld>   # the map demo on another world
```

The tests need no network and no key: the client's tests run against a fake transport. A few tests read two large
real worlds when their folders are named by `OW_SIKELIA` and `OW_MOPPETOPIA`; without them those tests are skipped,
never passed. A stale class cache shows as `Could not find type "OW…"` parse errors, and a test file that fails to
parse drops out of the total rather than counting as failed: import again and rerun.

`tools/` holds `pack.gd` and `extract.gd` (shell tools for `.owworld` files), `check_writer.py` (an `.owworld` file
judged by the fixture set's reference checker, which is not part of this repository: `--run-py DIR`), and two probes.

## OnlyWorlds

An open standard for world data: 22 element types, linked by id, usable by any tool. The schema lives at
[OnlyWorlds/OnlyWorlds](https://github.com/OnlyWorlds/OnlyWorlds). Other clients: the
[TypeScript SDK](https://github.com/OnlyWorlds/sdk), the [Python SDK](https://github.com/OnlyWorlds/python-sdk) and
the [Unity SDK](https://github.com/OnlyWorlds/unity-sdk).

## Licence and contributions

The code is MIT ([LICENSE](LICENSE)). Issues are welcome: a bug, a wrong word, a thing you could not do in Godot. Pull
requests are read; a small fix is usually taken as is, and a change to what the addon does is better opened as an
issue first, since it may already be built or ruled out. A pull request runs two checks by itself: the words of its
commit messages, and the test suite on Linux. A reply can take a few days. A security problem goes through
[private vulnerability reporting](https://github.com/OnlyWorlds/godot-sdk/security/advisories/new), not an issue
([SECURITY.md](SECURITY.md)). What we ask at the door, and what you can expect:
[the code of conduct](https://github.com/OnlyWorlds/OnlyWorlds/blob/main/CODE_OF_CONDUCT.md).

Maintained by Quillon, an AI agent working for Titus. Issues and pull requests are read and answered here.
