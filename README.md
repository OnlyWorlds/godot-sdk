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
var land := OWLanding.landing_of(g, {"heads": 5})                         # mode, size, clusters, unclustered, gaps
var space := OWMapSpace.map_space(bodies)                                  # maps, zones, pins, out: in the Map's pixels
var lay := OWMapSpace.layout_of(map_row, map_rows, pin_rows)               # layout, ground, hand: one Map's layout keys
var view := OWViews.view_of(body)                                          # row, sentence, banners, order: how it is shown

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
  an account token and a keyless client write nothing. Refused before sending: a known-of stub, an `if_match` that is
  not a whole number. A link array in a patch is sent as given and replaces the whole array, as in the Unity and
  TypeScript SDKs: to add or remove one id, use `edit_links` (keel's merge).
- **Errors**: one type, `OWApiError`, with a `kind`: `api` (keel's envelope: `status`, `code`, `message`, `param`,
  `doc_url`, `retry_after`), `transport` (no answer), `refused` (a caller's mistake, nothing sent: an unknown option, a
  value of the wrong type, `world` beside a world key) and `answer` (a 2xx that is not what the route answers). A write
  that became a proposal is kind `api` with `status` 202 and `error.proposal` the row (`is_proposed()`), as the Unity
  SDK's `OWProposedError` is: the element did not change.
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
| `addons/onlyworlds/models/` | one `class_name OW<Type>` per element type, **generated**; `ow_element.gd`, `ow_world_info.gd`, `ow_types.gd`, `ow_schema_pin.gd`, `ow_presentation.gd`, `ow_views_table.gd` and `unicode/ow_unicode_data.gd` are generated too |
| `codegen/generate.py` | the emitter (Python standard library); `--check` is the drift guard; `test_generate_views.py` holds each of its refusals of `views.json` red |
| `codegen/PIN`, `codegen/schema-dist/` | the pinned schema-dist (tag and manifest sha256), vendored verbatim; never edit it |
| `codegen/generate_tools.py`, `codegen/tools-pin.json`, `codegen/tools/` | the OnlyWorlds tools list at its own pin (commit and sha256, the npm and Python packages' pin), vendored byte for byte, and its emitter into the **generated** `addons/onlyworlds/ow_tools.gd`; `--check` is its drift guard, `test_generate_tools.py` holds it red on a one-byte change |
| `codegen/generate_layout.py`, `codegen/generate_layout_3d.py` | the layout methods' shared tables (the by-kind anchors, the by-links-3d directions) from the pinned dist's fixtures into the **generated** `addons/onlyworlds/ow_layout_anchors.gd` and `ow_layout_directions.gd` as bit patterns, and the fixtures' numbers as bits for the tests (`tests/data/layout.bits.json`, `layout-by-links-3d.bits.json`); `--check` is each one's drift guard |
| `tests/` | the headless suite; `tests/data/unicode_vectors.txt` is generated; `tests/data/keel-wire.json` is keel's wire document, vendored from the Unity SDK (`test_client_wire.gd` names its commit and checks its sha256) |
| `tools/` | `pack.gd`, `extract.gd` (shell tools), `check_writer.py` (the reference checker's verdict on a file), `probe_numbers.gd`, `twin_run.gd` (the lens and graph readers over a file of random worlds, one answer per line in the npm runner's shape, for a side-by-side compare) |
| `demo/moppetopia_map.tscn` | a world in a scene: the root Map's image with its Pins |

## Running

```sh
python codegen/generate.py --check                               # the pin holds, the generated files are current
python codegen/generate_tools.py --check                         # the tools list's pin holds, ow_tools.gd is current
python codegen/generate_layout.py --check                        # the by-kind anchors and the layout bits are current
python codegen/generate_layout_3d.py --check                     # the by-links-3d directions and bits are current
python codegen/test_generate_views.py                            # generate.py refuses a views.json that breaks a rule
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
  and Python packages do: every case of the profile's fixture (201, the graph kind's 54 and the degree kind's 5
  included), the room profile's 32, their shared edge file (15) and their shared row cases (20: a row is the body as
  keel serves that reader, a link only to an element it sees of the field's type, a lens's notes never keyed to what
  it cannot see, the owner's as stored). Where the platform's own reader reads otherwise, this reads as it does:
  nothing hops out of an element dated after `as_of`, `hops_not_served` never counts a room element or reading aid `types`
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
  with no fraction is whole (`7.0` reads as 7), in `x_lens` too (the owner's ruling 13); a float past 2^53 - 1 is not. The
  one case that needs the text (`text_only`) is skipped, as the fixture allows; the ruling retires it. The graph's
  flags, each a boolean, false by default: `rooms`, `hidden`, `proposed`, `map_space` and `reading_aids` (serial 104:
  the charter, its guide and its domains back into an unlensed graph, each marked `reading_aid`; any signed reader's,
  refused for a public one, last in the refusal order). A flag never widens a lens; a reading aid a lens keeps is
  marked `reading_aid` too, as a room element a lens keeps is marked `room`.
- **The landing** (the landing profile, serial 103): `OWLanding.landing_of(graph, options)` is a world's first picture
  at a door, read from the graph `OWGraph.world_graph` answers (a `Graph` or its `to_dict()`), so it sees only what
  that reader sees: `{mode, size, clusters, unclustered, gaps}`. The most-linked Characters are the heads (never a
  known-of node), each node within `hops` joins its nearest head (a tie to the higher-ranked), and the gaps are the
  orphans, near-orphans, a Character with no place and a Location nobody's in. `heads`, `hops` and `size` are whole
  numbers of 1 or more (`2.0` is 2), an unknown key or a bad value refused by name; counts are ints and ids compare
  by code point. `orphan` and `near_orphan` go by the page's own degree (`OWGraph.degree_of`: a link to itself once,
  each place in a list once), and a whole number too large to hold reads as the largest. Every case of the profile's
  fixture (33).
- **Map space** (the map space profile, serial 106): `OWMapSpace.map_space(elements)` reads a world's Maps, Zones,
  Markers and Pins, as the reader is served them, into `{maps, zones, pins, out}`, whole numbers in the Map's pixels:
  each Map's frame (`width` and `height` its own, or measured from its points with `extent: "points"`; `depth`,
  `z_max` beside it, `scale` from `x_metres_per_pixel`), each Zone's outline per Map from its Markers (by `order`, a
  Marker without a whole order after the ordered ones, then by id; `shape` `polygon` or `line`), each Pin's point and
  its element as both keys or neither, and what was left out by reason (`no_point`, `no_markers`, `dangling`,
  `no_map`). `z` is an elevation, never a height, and a `z` past `depth` is kept; `2.0` is 2, a boolean is no number,
  a float past 2^53 - 1 (a value the parse may have rounded) is not whole; two rows of one type with one id read as the last one served;
  `type` and `shape` are read as written; ids compare by code point. Every case of the profile's fixture (34).
  Since serial 110, `OWMapSpace.layout_of(map, maps, pins)` reads one Map's layout keys (rules 8 to 10) into
  `{layout, ground, hand}`: the `x_layout` method when it is a non-empty string (`hand` a board), the ground Map's id
  when `settings.ground.map` names a served Map other than this one, and the ids of this Map's Pins a new lay-out
  keeps (every Pin on a board, those whose `x_hand` is the bool `true` on any other layout map, none on a plain Map),
  by code point. The Pins are filtered by `map` inside, so a caller passes every Pin it holds. Every layout case of the
  fixture (21 since serial 111).
- **Reading aids** (the charter profile, serial 83): `OWCharter.charter_of(world, reader)` is the packet every front
  door shows first (`{charter, guide, domains}` as that reader sees the world), `domains_of` the list alone, as keel's
  `reading_aids` reads it: the newest marked Charter and Guide, the Domains in the Guide's order then by folded name,
  each with its sentence and hubs, the Charter's skill Objects as keel's `charter_skill` finds them. Every case of the
  profile's fixture (22). `OWCharter.design_parts_of(world, reader)` (serial 135) is every Object or Construct that
  reader is served whole whose subtype, trimmed and folded, is `in design` or `locked`, each `{type, id, state}`, only
  in a world where `charter_of` finds a Charter for that reader; every case of the fixture's `design_cases`.
- **The strand** (the strand profile, serial 98): `OWStrand.strand_of(world, reader)` is the world's one story in
  miniature as that reader sees it, `{narrative, event, location, character, now, same}`: the story the World's
  `x_strand` names, one of its events and that event's place, the story's protagonist and where the hero is now, and
  whether then and now are one place. Only the story is required; an empty slot is null, never filled from another
  slot; a story the reader only knows of fills its own slot alone. Every case of the profile's fixture.
- **Records** (the record profile, serials 102 and 103): `OWRecord.records_of(character_id, elements)` is a Character's
  record of game runs, read from the world: every Event marked `x_record` whose `characters` names them, newest
  first, each `{event, tool, played_at, version, seed, outcome, seat, stories}` with the Narratives that tell it
  about them or by them. `OWRecord.record_mark_of(element)` reads one mark; a broken mark is no record, a proposed
  run or story (as the review profile reads it: an empty mark is settled) is not read. Every case of the profile's
  fixture (40).
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
- **Report threads** (the report profile's rule 9, serial 120): `OWReport.threads_of(narratives)` groups the reports
  among a world's Narratives by `parent_narrative`, read as written: `parents` (each report's parent: `none`,
  `report`, `board`, `missing`, `other` or `self`), `groups` (a report's thread, or the reports of the talks under a
  board entry, each in `created_at` order as `OWMessage` orders messages) and `lints` (`chain`, `self`); never walked
  further up, never guessed from names or days. A report and a board entry are the room profile's pairs with the
  mark, read by `OWLens`'s room reader (`OWReport.is_report`, `is_board_entry`). Every case of the profile's fixture
  (20). Parity with the TypeScript SDK 4.159.0 and the Python package 0.120.0. A talk on an Object or a Construct
  (serial 135): `OWLens.talks_of(element)` is each `{type, id}` a line in the room names in its `objects` (`object`)
  or `constructs` (`construct`), and `OWReport.talks_of(element)` the same of a report, the talks a reader shows it
  with; ids read as written, an entry that is no String or only White_Space naming nothing. Every case of the room and
  report fixtures' `talk_cases`.
- **Views** (the distribution's `views.json`, version 3, serial 115: presentation, not the standard):
  `OWViews.view_of(element)` is how an element is shown by its kind, a `View` with the matching `row` (the table's
  own, read-only; null when the element draws as its type), its one `sentence`, the `banners` at its page's head and
  the `order` its page draws its fields in. A row is a report, a charter, a message or a line in a room; a profile's
  pair matches only with its mark, by `OWLens`'s room and charter readers, and the most specific row wins (on a tie,
  the first). The sentence is the first named field holding text after trimming, cut at its first line break (U+000A
  or U+000D). The banners: `known_of` and `hidden` only when true, the review marks only as an object with a key,
  `x_served_trimmed` only when it names a field, then the row's own marks by presence. The order: lead, then the
  type's section fields in the schema's order (`OWViews.SECTION_FIELDS`), then fold, each once, only a field that
  holds something; a Pin's generic link is one field, `element`, at its place, holding something only when both its
  keys (`element_type`, `element_id`) do (`OWViews.GENERIC_LINKS`). The table is baked by `codegen/generate.py`, which
  refuses a file the fixture's rules break (another version, two rows of one kind, a field its type lacks, a cite whose
  quote is not at its line); every case of its fixture (46) and the 10 cites. Parity with the TypeScript SDK 4.152.0
  and the Unity SDK.
- **Calendars** (the calendar profile, `atlas_calendar`, version 1 and 2): `OWCalendar.read_value` reads the field
  (an object, or the same as strict JSON text: Godot's parser takes a trailing comma, a leading zero, `5.` and a raw
  control character, so the text is checked against JSON's grammar first) and refuses what the profile refuses;
  `breakdown_step` and `format_step` read a step as npm's `breakdownStep` and `formatStep` do (Euclidean floor, the
  leap rule with `except` and `offset`, eras with an open end skipping down eras, free and nested weeks, the template's
  close-up on JavaScript's white space); `world_calendars` finds them by the field. Every case of the profile's fixture
  (77: 34 calendars, 209 steps, 43 refusals). A whole number is a safe integer (2^53 - 1), `1.0` is 1, a boolean is
  never a number; a month's days are found by arithmetic, never listed. The axis labels `format_year_label` ("22 FT")
  and `format_mid_label` ("11 Greening 454"), `format_duration` ("19 years", "12 days", "1.5 years"),
  `approx_year_length` and `month_start_steps` read as npm's `formatYearLabel`, `formatMidLabel`, `formatDuration`,
  `approxYearLength` and `monthStartSteps` do; `parse_date(calendar, text, {"now": step})` reads a typed date as
  npm's `parseDate` (a bare number is the raw step; the calendar's words without regard to case; `{"step"}` or
  `{"error"}` in npm's words, an unknown option refused by name), with `abs_year_for_era_year` its inverse of an era's
  year; `validate_config` is npm's `validateCalendarConfig`, a builder's messages word for word on any JSON value
  (where npm throws, on eras or intercalary days that are no list, it says so);
  `resolve_calendar(elements, id, {"fallback_to_only": true})` is npm's `resolveCalendar`, the id left out
  (`OWCalendar.NOT_CHOSEN`) apart from null. Each held to npm's own answers: parity vectors generated from the npm
  package's built code (`codegen/generate_calendar_parity.mjs`, `--check` to see they still hold) over every
  calendar of the fixture and calendars written for the traps.
- **Open with** (the tools list's README, "Open with"): `OWOpeners.openers_for(tools, kind, address, surface)` gives
  the rows of an Open with menu for a world or one element, as the npm SDK's `openersFor` and the Python package's
  `openers_for` do: the site's page first, then each listed tool with a door for that kind in the list's order, each
  `{id, name, href, state}` with its word in sentence case or null. `OWTools.ALL` is the OnlyWorlds tools list as
  of this release (a tool listed after it is offered from the next). The surface says what the game knows and
  nothing is guessed: `audience` (`member` or `public`, the signed-out reader: a tool that needs an account is a row
  that says "Needs an account" and opens nothing, so draw it disabled; a tool that needs the device is not there),
  `signed_in` (null when unknown: no word), `browser` (false
  in a game: an account tool says "Opens in your browser"), `phone`, `online` (false with no connection: every row
  whose link is a web address says "Needs a connection" and keeps its href), `tool` (your client name: "You are
  here"). On an element's menu, pass the element as you were served it (`{"element": body}`, a fifth argument): a
  tool whose element link cannot open it (a room element, a hidden or proposed one, a Map, Pin or Marker, a reading
  aid: the tools list's `element_skips`) is left out, each mark read as `OWGraph` reads it. A tool that opens only
  some kinds of element (the list's `element_types`, read from the address's type) is not on another kind's menu at
  all, its world door included. A refused address answers
  `reason` as the address profile names it; any other mistake answers `reason` "" and a `message` naming the key.
  Every case of the packages' shared fixture (100).
- **Names** (the names profile, `x_names`, serial 92): `OWNames.type_word(world, type, supertype, many)` is the
  world's own word for a type (Character shown as *Employee*), or null for the standard's name, as the npm SDK's
  `typeWord` and the Python package's `type_word` read it: the supertype's entry, trimmed and folded as the room
  profile reads, then the type's, printed as written. A display lookup only: the folder, the ids and every other
  reader keep the standard's names. Version `1` read as `1.0` is the number 1; a `types` or `supertypes` key present
  and null refuses the map. Every case of the profile's fixture (23).
- **Writing an archive**: its own zip bytes: the marker stored first, UTF-8 byte order, fixed 1980 stamps, methods 0
  and 8, zip64 from 65,535 entries.
