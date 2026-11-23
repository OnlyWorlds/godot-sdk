# OnlyWorlds SDK for Godot

[OnlyWorlds](https://www.onlyworlds.com) is an open standard for world data: a world's characters, places, events
and lore as elements of 22 types, linked by id, that any tool can read. This addon brings such a world into your Godot
game: written outside the engine, then read at run time over the onlyworlds.com API, or shipped with the game as a
folder.

A GDScript addon, with a class for each of the 22 element types. It reads and writes worlds through the API, and on
disk as world folders and `.owworld` files. It runs on the standard Godot build; no .NET is needed.

## Install

Godot 4.7, the standard build. Earlier 4.x versions are untested, and so are exports other than Windows desktop (the
web and mobile among them).

- **The release zip**: `onlyworlds-godot-0.1.0.zip`, from this repository's
  [Releases](https://github.com/OnlyWorlds/godot-sdk/releases) page. Unpack it into your project folder: it holds
  `addons/onlyworlds/`, which joins your project's `addons/` folder.
- **A clone** of this repository: copy its `addons/onlyworlds/` folder into your project's `addons/` folder.

Then open the project in the editor once (or run `godot --headless --path . --import`), so Godot registers the `OW…`
classes. Enabling the plugin under **Project Settings → Plugins** is optional: the classes work without it.

**Versions.** 0.1.0 is the first numbered release. Before 1.0, a minor version may change a call's name, and the
[CHANGELOG](CHANGELOG.md) says so when it does.

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
- **`ow_w_`** reads and writes. Writes also send your PIN, as `api_pin`.

```gdscript
var client := OWClient.new({"api_key": world_key, "api_pin": pin})   # ow_w_…, your PIN
var made := await client.create("character", {"name": "The Brine Cartographer"})
await client.patch("character", made.value.id, {"description": "Maps the tide lines."})
```

`patch` sends only the fields you pass; `delete("character", id)` removes one. Every call answers a reply with
`value` on success, else `error` (an `OWApiError` that says why). Keep write keys out of games you ship: a key written
in a script, a scene or an exported variable is packed into the export, where anyone with the build can read it, so
read write credentials at runtime.

An AI agent that writes to your world takes a seat of its own instead, an
[agent seat](https://onlyworlds.github.io/docs/development/agents): its own key and secret (`ow_s_…`), for one world,
which the world's owner can remove at any time.

**A world on disk**, with no server at all. `OWWorld.read_folder(path)` reads a world folder,
`OWWorldArchive.read_file(path)` an `.owworld` file (one zip that holds a folder), and both give the same typed
elements. A world you never edited is written back byte for byte. A pack (`OWWorldArchive.pack`, `OWWorld.pack`)
is a copy: it carries every element, hidden ones included (the addon has no share yet). This repository carries a
small example world, Hyperion, at `codegen/schema-dist/example/hyperion`; `demo/world_map.tscn`, the project's main
scene, draws its Map with its Pin.

**A player link** (`https://www.onlyworlds.com/join#ow_j_…`, made by a world's owner for one Character) needs no
account. Redeem it once for that player's read key; the server then shows the key only what that Character may see.

```gdscript
var code := OWJoin.parse_link(pasted)           # "" when the text holds no code
var joined := await OWJoin.redeem(code)         # the code is spent: keep joined.value.key
var client := OWClient.new({"api_key": joined.value.key})
```

`OWJoin.preview(code)` says who invites, to which world, without spending the code.

## What's in it

| Part | Classes | What it does |
|---|---|---|
| **Client** | `OWClient`, `OWJoin` | The API: read a world, list and page through its elements, the change feed, writes (create, upsert, patch, delete, link edits, bulk), joining by invite link. |
| **Models** | `OWCharacter`, `OWLocation`, … (all 22), `OWElement` | One class per element type, generated from the schema; `OWTypes.make(type, body)` builds the right one. |
| **On disk** | `OWWorld`, `OWWorldArchive`, `OWJson` | World folders and `.owworld` files, read and written in the folder format's own bytes. |
| **Readers** | `OWLens`, `OWGraph`, `OWLanding`, `OWMapSpace`, `OWCharter`, `OWStrand`, `OWRecord`, `OWReport`, `OWMessage`, `OWNames`, `OWViews` | Answers worked out from elements you already hold, with no request of their own: what one reader may see of a world, the world as nodes and edges, its most-linked Characters, its maps as points and outlines, the rules and the story a world shows first, a Character's record of game runs, in-world messages and reports, how an element is shown. |
| **Helpers** | `OWCalendar`, `OWAddress`, `OWOpeners`, `OWTools`, `OWId`, `OWUnicode` | A world's own calendar, `ow://` links, an "Open with" menu of OnlyWorlds tools, ids, name comparison. |

Every call, with what it answers and what it refuses: [docs/reference.md](docs/reference.md).

## How it follows the standard

The 22 classes are generated from one pinned release of the
[schema distribution](https://github.com/OnlyWorlds/schema-dist), the standard's published form (`codegen/PIN`;
`OWSchemaPin` names it at run time), vendored unchanged in `codegen/schema-dist/`. Each reader gives the same answers
as the TypeScript, Python and Unity SDKs on a shared set of test cases, and every request the client makes is checked
against the API's own description of itself (`tests/data/keel-wire.json`). The reference opens with the few words of
the standard it uses.

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
judged by the fixture set's reference checker, which is not part of this repository: `--run-py DIR`),
`release_zip.py` and `prove_zip.py` (the release zip made from a tag or a commit into `dist/`, then unpacked into an
empty project that reads a world through it: `python tools/release_zip.py v0.1.0`, then
`python tools/prove_zip.py dist/onlyworlds-godot-0.1.0.zip --godot <binary>`), and two probes.

## OnlyWorlds

The schema lives at [OnlyWorlds/OnlyWorlds](https://github.com/OnlyWorlds/OnlyWorlds). Other clients: the
[TypeScript SDK](https://github.com/OnlyWorlds/sdk), the [Python SDK](https://github.com/OnlyWorlds/python-sdk), the
[Unity SDK](https://github.com/OnlyWorlds/unity-sdk) and the [Unreal SDK](https://github.com/OnlyWorlds/unreal-sdk).

## Licence and contributions

The code is MIT ([LICENSE](LICENSE)). Issues are welcome: a bug, a wrong word, a thing you could not do in Godot. Pull
requests are read; a small fix is usually taken as is, and a change to what the addon does is better opened as an
issue first, since it may already be built or ruled out. A pull request runs two checks by itself: the words of its
commit messages, and the test suite on Linux. A reply can take a few days. A security problem goes through
[private vulnerability reporting](https://github.com/OnlyWorlds/godot-sdk/security/advisories/new), not an issue
([SECURITY.md](SECURITY.md)). What we ask at the door, and what you can expect:
[the code of conduct](https://github.com/OnlyWorlds/OnlyWorlds/blob/main/CODE_OF_CONDUCT.md).

Maintained by Quillon, an AI agent working for Titus. Issues and pull requests are read and answered here.
