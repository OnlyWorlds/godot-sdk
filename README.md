# OnlyWorlds SDK for Godot

[OnlyWorlds](https://www.onlyworlds.com) is an open standard for world data: a world's characters, places, events
and lore as elements of 22 types, linked by id, that any tool can read. This addon brings such a world into your Godot
game: written outside the engine, then read at run time over the onlyworlds.com API, or shipped with the game as a
folder.

A GDScript addon, with a class for each of the 22 element types. It reads and writes worlds through the API, and on
disk as world folders and `.owworld` files. It runs on the standard Godot build; no .NET is needed.

![A Godot window showing a space map with a planet, a station, ships and an asteroid field, and eleven named pins on it](https://media.onlyworlds.com/onlyworlds/readme/godot-map-demo-moppetopia.webp)

*The map demo of this repository (`demo/world_map.tscn`) on a folder of Moppetopia, a public sample world: the
world's Map image, each of its Pins where the world places it, and each Pin's name. The folder itself is not in this
repository; the demo opens on a smaller example world that is.*

## Install

Godot 4.7, the standard build. Earlier 4.x versions are untested, and so are exports other than Windows desktop (the
web and mobile among them).

- **Godot's Asset Library**: [OnlyWorlds SDK](https://godotengine.org/asset-library/asset/5621), also found from the
  editor's **AssetLib** tab by searching for OnlyWorlds. Download it and install with the installer's defaults ("Ignore
  Asset Root" stays ticked), and it lands at `addons/onlyworlds/`. The Library carries a release, so it can be a step
  behind this repository.
- **The release zip**: `onlyworlds-godot-0.6.0.zip`, from this repository's
  [Releases](https://github.com/OnlyWorlds/godot-sdk/releases) page. Unpack it into your project folder: it holds
  `addons/onlyworlds/`, which joins your project's `addons/` folder.
- **A clone** of this repository: copy its `addons/onlyworlds/` folder into your project's `addons/` folder.

Then open the project in the editor once (or run `godot --headless --path . --import`), so Godot registers the `OW…`
classes. Enabling the plugin under **Project Settings → Plugins** is optional: the classes work without it.

**Versions.** A patch release fixes and a minor release adds; neither removes nor renames a public name, and the
addon keeps to this while it is 0.x. A name that will go is marked deprecated first, saying since which release,
what to use instead and the release it leaves in; it stays at least six months after that release and goes only in
1.0. It is the same promise as on the docs'
[Stability page](https://onlyworlds.github.io/docs/development/api/stability#the-standard-the-packages-and-this-site), and a check in CI
holds the public names to it on every change; it reads names, not a call's parameters or what it does. The [CHANGELOG](CHANGELOG.md) lists what each version changed.

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

**Without the editor.** `godot --headless --script` runs only a script that extends `SceneTree` (a `Node` script is
refused: "doesn't inherit from SceneTree or MainLoop"). The same first run as one:

```gdscript
extends SceneTree

func _init() -> void:
	await process_frame   # TLS starts with the first frame: an https request before it gets no answer
	var client := OWClient.new({"api_key": "0000000001"})   # demo key: Moppetopia, read-only
	var world := await client.get_world()
	if not world.ok:
		print(world.error)
		quit(1)
		return
	print(world.value["name"])
	var found := await client.list("character", {"name_contains": "fluffington"})
	print(found.value.data[0].name)
	quit()
```

From your project's folder, after the import: `godot --headless --script res://first_run_headless.gd`. It prints
`Moppetopia`, then `Admiral Fluffington`. In this repository it is `demo/first_run_headless.gd`.

## Your own world

Create a world at [onlyworlds.com](https://www.onlyworlds.com); its keys are on the world's page. A new key is shown
once, so copy it then.

- **`ow_r_`** reads, with no PIN. This is the key to ship in a game.
- **`ow_w_`** reads and writes. Writes also send your PIN, as `api_pin`.

```gdscript
var client := OWClient.new({"api_key": world_key, "api_pin": pin})   # ow_w_…, your PIN
var made := await client.create("character", {"name": "The Brine Cartographer", "location": harbour_id})
await client.patch("character", made.value.id, {"description": "Maps the tide lines."})
await client.edit_links("character", made.value.id, "friends", {"add": [friend_id]})
```

A link field takes the linked element's id (`"location": harbour_id`); a list of links (`friends`) is changed with
`edit_links`, which adds or removes ids without touching the others. `patch` sends only the fields you pass; `delete("character", id)` removes one. Every call answers a reply with
`value` on success, else `error` (an `OWApiError` that says why). Keep write keys out of games you ship: a key written
in a script, a scene or an exported variable is packed into the export, where anyone with the build can read it, so
read write credentials at runtime.

An AI agent that writes to your world takes a seat of its own instead, an
[agent seat](https://onlyworlds.github.io/docs/development/agents): its own key and secret (`ow_s_…`), for one world,
which the world's owner can remove at any time.

**A world on disk**, with no server at all. `OWWorld.read_folder(path)` reads a world folder,
`OWWorldArchive.read_file(path)` an `.owworld` file (one zip that holds a folder), and both give the same typed
elements. A world you never edited is written back byte for byte. A pack (`OWWorldArchive.pack`, `OWWorld.pack`) is
a copy by default: every element file travels whole, hidden ones included, as you would back up or move your own
world. With `include_hidden` false it is a share, a file to hand to someone else: an element marked `hidden` is left
out, and so is every file under `elements/` the reader could not read as one element; the result names each, hidden
apart from unread (`hidden_left_out`, `unread_left_out`). Either way a pack leaves out who wrote each one: the five
author fields (`created_by`, `changed_by`, `changed_via`, `changed_client`, `doors`) are left out of every element
file that is one JSON object, since a `.owworld` is a file handed on. Pass `include_author_fields` for a byte copy of
your own folder. This repository carries a
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
| **Readers** | `OWLens`, `OWGraph`, `OWLanding`, `OWMapSpace`, `OWCharter`, `OWStrand`, `OWRecord`, `OWReport`, `OWMessage`, `OWNames`, `OWViews`, `OWNameFinder` | Answers worked out from elements you already hold, with no request of their own: what one reader may see of a world, the world as nodes and edges, its most-linked Characters and the most linked of each type, its maps as points and outlines and which of their Pins one reader knows, the rules and the story a world shows first, a Character's record of game runs, in-world messages and reports, how an element is shown, which element names a text mentions. |
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
python tools/verify_promise.py --godot godot                     # the written promise: no public name gone, each one listed
python tools/mutants_promise.py --godot godot                    # the promise check, watched failing once per rule
godot --path . res://demo/world_map.tscn -- --world=<folder | file.owworld>   # the map demo on another world
```

The tests need no network and no key: the client's tests run against a fake transport. A few tests read two large
real worlds when their folders are named by `OW_SIKELIA` and `OW_MOPPETOPIA`; without them those tests are skipped,
never passed. The `.owworld` conformance set is the vendored copy, or a draft copy when `OW_OWWORLD_FIXTURES` names
a folder holding its `verdicts.json`. A stale class cache shows as `Could not find type "OW…"` parse errors, and a test file that fails to
parse drops out of the total rather than counting as failed: import again and rerun.

`tools/` holds `pack.gd` and `extract.gd` (shell tools for `.owworld` files), `check_writer.py` (an `.owworld` file
judged by the fixture set's reference checker, which is not part of this repository: `--run-py DIR`),
`verify_promise.py` and `mutants_promise.py` (below), `release_zip.py` and `prove_zip.py` (the release zip made from a tag or a commit into `dist/`, then unpacked into an
empty project that reads a world through it: `python tools/release_zip.py v0.6.0`, then
`python tools/prove_zip.py dist/onlyworlds-godot-0.6.0.zip --godot <binary>`), and two probes.

**Deprecating a name.** Write `## @deprecated: Since X.Y.Z. Leaves in 1.0. Use Y.` in its doc comment, with X.Y.Z the
release that first carries the mark; a deprecated function also calls `push_warning()` with the same words, since
GDScript does not warn at a call by itself. Then run `python tools/verify_promise.py --godot <binary> --write` and
commit `tools/public-names.json`, which lists every public name and its mark as Godot's doctool reads them. CI runs
`verify_promise.py` on every push and pull request, and `python tools/mutants_promise.py --godot <binary>` watches the
check fail once for each rule.

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
