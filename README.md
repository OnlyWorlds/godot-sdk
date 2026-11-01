# OnlyWorlds SDK for Godot (spike)

A GDScript addon that reads OnlyWorlds world folders and `.owworld` files into typed elements, and writes them back
in the format's own bytes; it reads and writes an onlyworlds.com world over the API too. Godot 4.7, the standard
build (no C#). Not released; private at `OnlyWorlds/godot-sdk`.

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

var cal := OWCalendar.read_value(element.get(OWCalendar.FIELD))   # null: not a calendar, show bare numbers
print(OWCalendar.format_step(cal, 1200))                           # the step in the world's words, or "1200"

var word = OWNames.type_word(world_json, "character", "Agent", true)   # "AI agents", or null: print "Characters"

var where := {"world": world_id, "type": "pin", "id": pin.id}         # or a Reading that names its world
var menu := OWOpeners.openers_for(OWTools.ALL, "element", where, {"audience": "member", "browser": false})
for row in menu.rows: print(row["name"], " ", row["href"], " ", row["state"])   # state: null or "Opens in your browser"

var client := OWClient.new({"api_key": "ow_r_..."})            # client.error: "" when built
var r := await client.list_all("character")                    # r.value, or r.error (an OWApiError)
```

## The API client

`OWClient` reads an onlyworlds.com world over keel's v2 API into the same typed models a folder gives, and writes its
elements back. The reads: `health`, `get_world`, `me`, `members`, `list` (one page), `list_all` (every page),
`get_element`, `changes` (a page of the change feed) and `changes_head` (its tip, conditional on the last ETag). The
writes: `create`, `upsert`, `patch`, `delete`, `edit_links` (the one way to change a link array) and `bulk`. Each
returns through `await` and answers an `OWClient.Reply`: `value` on success, else `error`.

```gdscript
var client := OWClient.new({"api_key": "ow_w_...", "api_pin": "1234"})   # a world key; its PIN goes on GET /me only
var page: OWClient.Page = (await client.list("location", {"supertype": "City", "filter": {"parent_location": id}})).value
var r := await client.get_element("character", id, {"expand": ["friends"]})
if r.error and r.error.is_not_found(): print("gone")
var me := (await client.me()).value
var aids := OWCharter.served(me)                                  # the Charter, the Guide, the Domains, the strand
var tip: OWClient.ChangesPage = (await client.changes_head()).value   # tip.unchanged: keel answered 304
var public := OWClient.new({"world": world_id})                  # no key: a public world, as the public reads it
var mine := OWClient.new({"api_key": "ow_a_...", "world": world_id})  # an account token reads the world it names

var made := await client.create("character", {"name": "Ana"}, {"idempotency_key": key})  # the id minted from the key
var r2 := await client.patch("character", made.value.id, {"level": 4}, {"if_match": seq})  # seq: its change_seq
if r2.error and r2.error.is_precondition_failed(): print(r2.error.current())               # someone wrote first
await client.edit_links("character", made.value.id, "friends", {"add": [bo_id]})
var done: OWClient.BulkResult = (await client.bulk([ana, bo], {"atomic": true})).value     # done.failed(): the slots
```

- **Credentials**, as the Unity and TypeScript SDKs send them: a world key (`ow_w_`, `ow_r_`, a 10-digit legacy key)
  as `API-Key`, its PIN as `API-Pin` only on `GET /me` among the reads, and on every request of a legacy key; an
  account token as a Bearer, never with the PIN, with `world=<id>` on the world reads and the roster; no key at all
  on the world reads with `world=<id>`. The health pulse carries no credential. Anything else a client could not
  send (`me` on an account token, the roster with no key, a world read on an account token without `world`) is
  refused before sending, and nothing is sent.
- **Writes**: an element is an `OWElement` (its data is sent) or a Dictionary, and is never changed: the body is a
  copy cleaned as the Unity SDK cleans it (`world`, `type`, `created_at`, `updated_at`, `change_seq` and `known_of`
  left out; a null string field sent as `""`, the wire's one unset; `x_*` keys untouched), compact, its numbers as
  JavaScript writes them (Godot reads every JSON number as a float; `3.0` goes as `3`). A create or a bulk item
  without an id gets a UUIDv7 (`OWId`), or under an `idempotency_key` the id derived from the key and the position
  (the id the Unity, TypeScript and Python clients derive), so a retry replays. Every write sends the PIN and
  `X-OW-Client` (the config's `client`, `godot-sdk` by default), and `X-OW-Agent` when the config says `agent: true`;
  an account token and a keyless client write nothing. Refused before sending: a known-of stub, a link array in a
  patch (a PATCH replaces it whole: use `edit_links`), an `if_match` that is not a whole number.
- **Errors**: one type, `OWApiError`, with a `kind`: `api` (keel's envelope: `status`, `code`, `message`, `param`,
  `doc_url`, `retry_after`), `transport` (no answer), `refused` (a caller's mistake, nothing sent: an unknown option, a
  value of the wrong type, `world` beside a world key), `answer` (a 2xx that is not what the route answers) and
  `proposed` (a 202: the write became a proposal, `error.proposal` is the row, the element did not change).
- **Options** are Dictionaries, and an unknown key is refused, never dropped (a dropped filter lists everything).
- **The cursor walk** is driven by `has_more`, never by a page's size; it stops at a page with no cursor and refuses a
  page that hands back the cursor it was sent.
- **Transport**: `OWHttpTransport` (Godot's `HTTPClient`, one connection a request, polled between frames, or with
  `blocking` without yielding) by default; any `OWTransport` subclass goes in the config's `transport` (the tests use a
  fake that records each request). Inside a `SceneTree` script's `_init`, before its first frame, TLS does not start:
  await one `process_frame` first.
- **The wire**: every request the read and write calls make is held to keel's document (`tests/data/keel-wire.json`,
  keel's OpenAPI document as the Unity SDK reduces it, vendored byte for byte): every path, method, query parameter,
  header and body key one keel declares there; every key the models and the bulk result read one keel serves.

## Layout

| Path | What it is |
|---|---|
| `addons/onlyworlds/` | the library: copy this folder into a project (the classes work without enabling the plugin) |
| `addons/onlyworlds/models/` | one `class_name OW<Type>` per element type, **generated**; `ow_element.gd`, `ow_world_info.gd`, `ow_types.gd`, `ow_schema_pin.gd` and `unicode/ow_unicode_data.gd` are generated too |
| `codegen/generate.py` | the emitter (Python standard library); `--check` is the drift guard |
| `codegen/PIN`, `codegen/schema-dist/` | the pinned schema-dist (tag and manifest sha256), vendored verbatim; never edit it |
| `codegen/generate_tools.py`, `codegen/tools-pin.json`, `codegen/tools/` | the OnlyWorlds tools list at its own pin (commit and sha256, the npm and Python packages' pin), vendored byte for byte, and its emitter into the **generated** `addons/onlyworlds/ow_tools.gd`; `--check` is its drift guard, `test_generate_tools.py` holds it red on a one-byte change |
| `tests/` | the headless suite; `tests/data/unicode_vectors.txt` is generated; `tests/data/keel-wire.json` is keel's wire document, vendored from the Unity SDK (`test_client_wire.gd` names its commit and checks its sha256) |
| `tools/` | `pack.gd`, `extract.gd` (shell tools), `check_writer.py` (the reference checker's verdict on a file), `probe_numbers.gd`, `twin_run.gd` (the lens and graph readers over a file of random worlds, one answer per line in the npm runner's shape, for a side-by-side compare) |
| `demo/moppetopia_map.tscn` | a world in a scene: the root Map's image with its Pins |

## Running

```sh
python codegen/generate.py --check                               # the pin holds, the generated files are current
python codegen/generate_tools.py --check                         # the tools list's pin holds, ow_tools.gd is current
godot --headless --path . --import                               # per clone, and after any pull that adds a class_name
godot --headless --path . --script res://tests/run.gd            # exits 0 only when every test passes
python tools/check_writer.py out.owworld                         # run_py.py's reader and check_writer on a file
godot --path . --write-movie frames/map.png --quit-after 4 res://demo/moppetopia_map.tscn
godot --headless --path . --export-release "Windows Desktop" build/windows/ow-godot-demo.exe   # needs 4.7.2's templates
build/windows/ow-godot-demo.exe -- --world=<folder | file.owworld> --capture=frame.png
```

A stale class cache shows as `Could not find type "OW…"` parse errors, and a test file that fails to parse drops
out of the total instead of counting as failed: a run whose total is short of the last one is that, so import and
run again.

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
- **Lenses** (the lens profile, serial 83, with its graph section): `OWLens` reads a saved way of reading a world
  (`is_lens`, `is_template`, `check_keys`, `lenses_in_use`, `resolve`, `date_of`, `is_charter_element` for the
  reading aids) and `OWGraph` the world as nodes and edges (`world_graph`, `degree_of`, `out_degree_of`), as the npm
  and Python packages do: every case of the profile's fixture (152, the graph kind's 38 included), the room profile's
  32, their shared edge file (15) and their shared row cases (20: a row is the body as keel serves that reader, a link
  only to an element it sees of the field's type, a lens's notes never keyed to what it cannot see, the owner's as
  stored). Where the platform's own reader reads otherwise, this reads as it does: nothing
  hops out of an element dated after `as_of`, `hops_not_served` never counts a room element or reading aid `types`
  would cut, a mark (`x_room_of`, `x_charter_of`) counts by presence, and an umbrella's union drops an element only by
  id. Ahead of the profile's next serial, its owner's rulings on readings no case decided yet: a link reaches only an
  element of its field's type (a generic pair only when its type key is one of the 22 slugs exactly as stored), an anchor id no such
  element holds is counted `anchor_not_visible` for the owner, an umbrella's hop keeps a child it reaches before
  entering it, a count is never erased by a later visit, a known-of stub is keel's (the base and public fields, every
  other field unset, no extension key), and two messages with one `created_at` keep the world's list order, never by
  id; in the graph, a link to an element of another type than its field's names nothing (no edge, no count), an edge
  to an anchor the reader cannot see carries the lens's `anchor_not_visible`, a Pin's generic pair is placement and never
  an edge, a node's type and name are as stored, and an edge's index is its place in the list as that reader is
  served it (a contributor is served a link to a proposed element). The review mark (`x_review_proposed`, `OWLens.is_proposed`) counts by presence too, and an empty one (`""`,
  White_Space only, `[]`, `{}`) is settled, never a doubt (the review profile's rule 1, serial 87). A node's family
  is one of `colors.order`'s four words (`OWPresentation.ORDER`); a word not among them fails loudly, naming it:
  `OWPresentation.use` refuses the table and keeps the one in use, `world_graph` answers it as a caller's mistake
  with no node, and `codegen/generate.py` refuses a sidecar that carries one (serial 87). A JSON number
  with no fraction is whole (`7.0` reads as 7), in `x_lens` too (the owner's ruling 13); past 64 bits it is not. The
  one case that needs the text (`text_only`) is skipped, as the fixture allows; the ruling retires it.
- **Reading aids** (the charter profile, serial 83): `OWCharter.charter_of(world, reader)` is the packet every front
  door shows first (`{charter, guide, domains}` as that reader sees the world), `domains_of` the list alone, as keel's
  `reading_aids` reads it: the newest marked Charter and Guide, the Domains in the Guide's order then by folded name,
  each with its sentence and hubs, the Charter's skill Objects as keel's `charter_skill` finds them. Every case of the
  profile's fixture (22).
- **The strand** (the strand profile, serial 98): `OWStrand.strand_of(world, reader)` is the world's one story in
  miniature as that reader sees it, `{narrative, event, location, character, now, same}`: the story the World's
  `x_strand` names, one of its events and that event's place, the story's protagonist and where the hero is now, and
  whether then and now are one place. Only the story is required; an empty slot is null, never filled from another
  slot; a story the reader only knows of fills its own slot alone. Every case of the profile's fixture.
- **Records** (the record profile, serial 102): `OWRecord.records_of(character_id, elements)` is a Character's
  record of game runs, read from the world: every Event marked `x_record` whose `characters` names them, newest
  first, each `{event, tool, played_at, version, seed, outcome, seat, stories}` with the Narratives that tell it
  about them or by them. `OWRecord.record_mark_of(element)` reads one mark; a broken mark is no record, a proposed
  run or story is not read. Every case of the profile's fixture (32).
- **The front door's packet** (serial 100): `OWCharter.served(answer)` reads `reading_aids` from a `GET /me` answer
  or an agent's join answer as the server serves it for that key: the Charter, the Guide, the Domains, then the
  strand (`strand`, an `OWStrand.Strand`, six null slots when the key sees none; null from a server that sends none).
- **Messages** (the message profile, serial 79): `OWMessage` reads a message between a world's members and the
  Note beside it, as the npm and Python packages do: `is_message`, `is_note`, `recipients_of`, `is_addressed_to`,
  `is_to_everyone` and `has_unseen_recipients` (keel's `x_served_trimmed`, `keyless` for a body read with no
  credential), `is_sent_by` (the claim), `sender_status` (verified, mismatch, unverifiable or unseen, by the members
  list), `edited_by`, `read_mark_of` (the reader's own-hand Read mark, the newest by `updated_at`), `unread_for`,
  `thread_of` and `note_of` (a Character's line). Every case of the profile's fixture (87). A Note's line is proposed
  only by an object mark, as the profile's text and the packages read it (a doubt leaves it shown, unlike
  `OWLens.is_proposed`, the rule of a reader that hands a world on). `OWLens`'s mail rule reads through it.
- **Calendars** (the calendar profile, `atlas_calendar`, version 1 and 2): `OWCalendar.read_value` reads the field
  (an object, or the same as strict JSON text: Godot's parser takes a trailing comma, a leading zero, `5.` and a raw
  control character, so the text is checked against JSON's grammar first) and refuses what the profile refuses;
  `breakdown_step` and `format_step` read a step as npm's `breakdownStep` and `formatStep` do (Euclidean floor, the
  leap rule with `except` and `offset`, eras with an open end skipping down eras, free and nested weeks, the template's
  close-up on JavaScript's white space); `world_calendars` finds them by the field. Every case of the profile's fixture
  (76: 34 calendars, 209 steps, 42 refusals). A whole number is a safe integer (2^53 - 1), `1.0` is 1, a boolean is
  never a number; a month's days are found by arithmetic, never listed. Not ported: `parseDate`, the axis labels
  (`formatYearLabel`, `formatMidLabel`), `formatDuration`, `monthStartSteps`, `validateCalendarConfig`,
  `resolveCalendar`.
- **Open with** (the tools list's README, "Open with"): `OWOpeners.openers_for(tools, kind, address, surface)` gives
  the rows of an Open with menu for a world or one element, as the npm SDK's `openersFor` and the Python package's
  `openers_for` do: the site's page first, then each listed tool with a door for that kind in the list's order, each
  `{id, name, href, state}` with its word in sentence case or null. `OWTools.ALL` is the OnlyWorlds tools list as
  of this release (a tool listed after it is offered from the next). The surface says what the game knows and
  nothing is guessed: `audience` (`member` or `public`), `signed_in` (null when unknown: no word), `browser` (false
  in a game: an account tool says "Opens in your browser"), `phone`, `online` (false with no connection: every row
  whose link is a web address says "Needs a connection" and keeps its href), `tool` (your client name: "You are
  here"). A refused address answers `reason` as the address profile names it; any other mistake answers `reason` ""
  and a `message` naming the key. Every case of the packages' shared fixture (54).
- **Names** (the names profile, `x_names`, serial 92): `OWNames.type_word(world, type, supertype, many)` is the
  world's own word for a type (Character shown as *Employee*), or null for the standard's name, as the npm SDK's
  `typeWord` and the Python package's `type_word` read it: the supertype's entry, trimmed and folded as the room
  profile reads, then the type's, printed as written. A display lookup only: the folder, the ids and every other
  reader keep the standard's names. Version `1` read as `1.0` is the number 1; a `types` or `supertypes` key present
  and null refuses the map. Every case of the profile's fixture (23).
- **Writing an archive**: its own zip bytes: the marker stored first, UTF-8 byte order, fixed 1980 stamps, methods 0
  and 8, zip64 from 65,535 entries.
