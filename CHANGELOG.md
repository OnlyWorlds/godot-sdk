# Changelog

Notable changes to the OnlyWorlds SDK for Godot. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing is released yet; the history before this file is in
the git log.

## [Unreleased]

### Added

- `OWMapSpace.map_space(elements)`: the map space profile's reader (schema-dist `profiles/map-space.md`, serial 105),
  how a world's Maps, Zones, Markers and Pins, as the reader is served them, are read as geometry. The answer,
  `OWMapSpace.MapSpace`, always holds its four parts (`to_dict()` in the profile's order): `maps` (each Map's
  `{id, width, height, depth, z_max, scale, location, parent_map}`, a missing or non-whole `width` or `height`
  measured from the Map's own outline and Pin points with `extent: "points"`, `scale` the Map's
  `x_metres_per_pixel` when a positive number), `zones` (one `{zone, map, shape, points}` per Zone and Map, the
  Markers by `order`, a Marker without a whole order after every ordered one, then by id; `shape` `polygon` or
  `line`, anything else `polygon`), `pins` (`{pin, map, element_type, element_id, x, y, z}`, the element both keys or
  neither) and `out` (what was left out, counted `no_point`, `no_markers`, `dangling`, `no_map`; a Marker both
  dangling and without a point is dangling). `z` is an elevation, 0 when absent or not whole, kept past `depth`. A
  whole number is read by value (`2.0` is 2), a boolean is no number; a row without a non-empty String id is no
  element. Ids compare by code point. Parity with the TypeScript SDK 4.129.1's `mapSpace` and the Python package
  0.104.1's `map_space`; the profile's 34 cases pass by name (serial 106's readings below, under Changed).
- `OWGraph.world_graph` takes `reading_aids` (the lens profile's fifth graph flag, schema-dist serial 104), a boolean,
  false by default: the reading aids (the charter, its guide and its domains, by the pair and the mark
  `x_charter_of`) come back into an unlensed graph, each node marked `reading_aid`. Any signed reader may ask it; a
  public reader is refused by name, last in the refusal order (`hidden`, `proposed`, `rooms`, `map_space`,
  `reading_aids`). A flag never widens a lens. A reading aid a lens keeps now carries the `reading_aid` mark too, as
  a room element a lens keeps carries `room`; marks come in the order `room`, `hidden`, `proposed`, `reading_aid`.
  Parity with the TypeScript SDK's `readingAids` and the Python package's `reading_aids`; the fixture's five new
  graph cases pass by name.
- `OWLanding.landing_of(graph, options)`: the landing profile's reader (schema-dist `profiles/landing.md`, serial
  103), a world's first picture at a door, read from the graph `OWGraph.world_graph` answers (a `Graph`, or its
  `to_dict()` shape), so it sees only what that reader sees. The answer, `OWLanding.Landing`, always holds its five
  parts (`to_dict()` in the profile's order): `mode` (`gaps` under `size` nodes, `graph` at it and above), `size`,
  `clusters` (the most-linked Characters as heads, never a known-of node, each with the nodes within `hops` steps that
  are nearest to it, a tie to the higher-ranked head, as `{id, hops, degree}`), `unclustered` (the rest, by degree)
  and `gaps` (orphans, near-orphans, a Character whose `location` reaches no Location, a Location no Character's
  `location` names). Degree is `OWGraph.degree_of`'s. Options `heads` (5), `hops` (1) and `size` (24) are whole
  numbers of 1 or more, null their default; an unknown key or any other value is refused by name, nothing read. A
  whole number too large for a 64-bit int (`1e30`) reads as the largest, since a count past the nodes means all.
  Counts are ints, ids compare by code point. Parity with the TypeScript SDK's `landingOf` and the Python package's
  `landing_of`; the profile's 30 cases pass by name.
- `OWOpeners.openers_for(tools, kind, address, surface, {"element": body})`: no row for a tool that cannot open the
  element. The tools list's `open.element_skips` says what a tool's element door does not open, in the lens profile's
  graph section's words (`OWOpeners.ELEMENT_MARKS`: `room`, `hidden`, `proposed`, `map_space`, a Map, Pin or Marker,
  a Zone being content, and `reading_aid`). Given the element as served, a row whose door skips a mark it carries is
  left out, each mark read by the reader `OWGraph.world_graph` uses (`OWLens._is_room_element`, `OWLens.is_hidden`,
  new and now the lens view's own reader, `OWLens.is_proposed`, the type folded among `OWGraph.MAP_SPACE`,
  `OWLens.is_charter_element`; `OWOpeners.marks_of`); a test holds the menu and the graph equal on every element of
  the lens fixture's worlds. Without the element every row is there, as before. Refused by name: an unknown options
  key, an element for a world's menu or naming another id than the address, a skip word outside the list's, and skips
  on a row with no element door. Parity with the TypeScript SDK 4.126.0 and the Python package 0.101.0, their test
  vector ported: the shared openers fixture at 90 cases, the same bytes. `OWTools` repinned at the tools list's
  `6da4d55` (Little Lens skips room, hidden, proposed and map space; Atlas and Lantern none); `generate_tools.py`
  bakes a list of words.

- `OWRecord`: the record profile's reader (schema-dist `profiles/record.md`, serial 102), parity with the TypeScript
  SDK 4.124.0 and the Python package 0.100.0. `record_mark_of(element)` reads an Event's `x_record` mark
  (`{tool, played_at, version, seed, outcome, seats}`, unset members null, or null for any other shape and on any
  element but an Event); `records_of(character_id, elements)` reads a Character's records, newest first by
  `played_at` as an instant to the millisecond, a tie by the Event's id in code point order, each with the stories
  that name the Character as `protagonist`, `narrator` or `both`. Who took part is the Event's `characters` alone;
  a run or a story still proposed is not read. `played_at` is checked by its parts (ASCII digits, the calendar's
  month lengths and Gregorian leap years, hour, minute and second), never by a date parser. `OWRecord.MARK` is the
  field's name. Every case of the profile's fixture (32), held by its sha256.
- `OWClient`'s element writes: `create` (`POST /{type}/`), `upsert` (`PUT`), `patch` (`PATCH`, with `if_match`),
  `delete` (with `if_match`), `edit_links` (`POST /{type}/{id}/links/{field}` with `{add, remove}`, the one way to
  change a link array: a patch carrying one is refused) and `bulk` (`POST /bulk/`, `atomic`, a typed
  `OWClient.BulkResult` whose slots carry their own status, error and proposal, and `was_replay` from keel's replay
  header). The body is cleaned as the Unity SDK cleans it (the read-only keys left out, a null string field sent as
  `""`, extension keys untouched) and written compact with JavaScript's number form. Every write sends the PIN and
  `X-OW-Client` (the new `client` config key, `godot-sdk` by default), and `X-OW-Agent` on a client the new `agent`
  config key declares an AI agent. A 202 is an `OWApiError` of the new kind `proposed`, its row in `proposal`; new
  helpers `is_proposed`, `is_precondition_failed` with `current()` (the element as it is now on a 412),
  `is_id_conflict`, `is_idempotency_conflict`, `is_known_of_not_writable`. The wire checks cover the writes: every
  body key one keel declares on that operation (a bulk item's element as its type's create declares it).
- `OWId`: element ids as the standard mints them, a UUIDv7 (`new_id`), and under an `Idempotency-Key` the UUIDv5 of
  the key and the position in the shared keyed namespace (`keyed`), the id the Unity, TypeScript and Python clients
  derive, so a keyed retry sends the same body and keel replays it.
- `OWClient`, the first API client: an onlyworlds.com world read over keel's v2 API into the SDK's own element
  models. The read calls: `health`, `get_world`, `me` (its `reading_aids` read by `OWCharter.served`), `members`,
  `list` (with its typed options and single-link filters), `list_all` (the cursor walk, by `has_more`),
  `get_element`, `changes` and `changes_head` (the tip, conditional on its ETag, a 304 handing back the last tip).
  The credential rules are the Unity SDK's `OWClient`: which header carries which credential, the PIN only on
  `GET /me` among the reads (and on every request of a legacy key), `world=` for an account token or no key, and
  what such a client may not send refused before sending. Every call answers an `OWClient.Reply` through `await`.
- `OWApiError`: keel's error envelope typed (status, code, message, param, doc URL, `Retry-After`), and the client's
  own word when no answer came, a call was refused before sending, or a 2xx was not the answer.
- `OWTransport`, the seam the client sends through, and `OWHttpTransport`, its default on Godot's `HTTPClient`
  (polled between frames, or blocking): no scene tree needed, unlike `HTTPRequest`.
- The wire checks: every request the read calls make is held to keel's OpenAPI document (`tests/data/keel-wire.json`,
  vendored from the Unity SDK), every key the models read to what keel serves.

### Fixed

- `OWLens.whole` (every profile reader's whole number) reads a float as whole only within 2^53 - 1, the range a double
  holds exactly, as the TypeScript SDK's `Number.isSafeInteger`: Godot's JSON reads every number as a float, so past
  2^53 a parse may have rounded it (`-9223372036854775809` arrived as exactly -2^63 and read as whole). An int is whole
  at any 64-bit value. Outside every fixture's range, which stays within 2^53. The TypeScript SDK 4.129.2's map space
  vector, read from JSON text, holds it in `OWMapSpace.map_space`: 2^53 - 1 is whole, -9223372036854775809 and
  2^53 + 1 (rounded by the parse) and 2^53 are not.
- The Open with menu's own site row says "You are here" when the surface's `tool` is `onlyworlds` (the site itself),
  where before it said "Needs a connection" offline or nothing. Parity with the TypeScript SDK 4.123.0, the shared
  openers fixture re-vendored at 57 cases.
- Parity with the TypeScript SDK 4.122.1: every value a call puts in a request path is sent as one escaped segment, the element type and the link field included (`list`, `get_element`, `create`, `upsert`, `patch`, `delete`, `edit_links`). The id and the link field were escaped already; the type went in as given, so a type carrying a slash asked a different route. On a real type name nothing changes on the wire. A test reads the client's source and fails on any request path built from an unescaped value or in a way it cannot read.

### Changed

- `OWMapSpace.map_space` reads serial 106's map space page: two rows of one type with one id read as the last one
  served, Markers and Pins as Maps and Zones already were, even when the last row reads less (an unplaced Marker, a
  Pin on a Map not served); a whole value past the 64-bit int reads as not whole, as the page's platform sentence
  says (before, a whole float past it was kept as written). The other new readings (a frame measured from placed
  points only, a non-whole `z` as 0, `no_markers` for a Zone with no placed Marker, a dangling Marker or a Pin with no
  served map counted once, `type` and `shape` read as written) were read so already. Parity with the TypeScript SDK
  4.129.1 and the Python package 0.104.1, which read serial 106 the same way.
- Schema pin to `v0.34.0-dist.106`; the standard stays at 00.34.00, no model change. The serial adds the map space
  page's readings I to K and four rulings from the first engine ports (the fixture at 34 cases, the 24 of 105
  unchanged).
- Schema pin to `v0.34.0-dist.105`; the standard stays at 00.34.00, no model change. The serial adds the map space
  profile (`profiles/map-space.md`, 24 cases): how a world's Maps, Zones, Pins and what is left out are read. The
  landing page's door sentence changes words only: the landing fixture is unchanged and passes as before.
- Schema pin to `v0.34.0-dist.104`; the standard stays at 00.34.00, no model change. The serial adds the lens
  profile's `reading_aids` graph flag (five cases; the lens fixture at 201) and two landing rulings, `orphan` and
  `near_orphan` by the page's own degree and a `heads` past the reader's range read as the largest (three cases, the
  landing fixture at 33). `OWLanding` already read both: the three cases pass with no reader change.
- Schema pin to `v0.34.0-dist.103`, the standard at 00.34.00: `OWLocation` gains `vehicle`, a single link to the
  Object a place is the inside of (a ship, a train, a walking city), generated. The serial adds the landing profile
  (`profiles/landing.md`, 30 cases), cases degree and out-degree on the lens profile's graph section (the lens
  fixture at 196 cases), and seven readings on the record profile (its fixture at 40 cases).
- `OWRecord.records_of` reads a run or a story as proposed exactly when the review profile's reader does (the record
  profile's reader rule 1 at serial 103): `x_review_proposed` a Dictionary with a key. An empty mark (`{}`, `""` or
  White_Space only, `[]`) and a value that is not a Dictionary are settled, so the run and its stories are read;
  before, any value but null hid them. Parity with the TypeScript SDK's and the Python package's readers. The serial's
  other readings (`played_at` upper-case `T` and `Z`, ASCII digits, seconds and a fraction optional; ties and stories
  by code point; an Event or a Narrative whose `id` is not a string never read; a name that is not a string read as
  `""`) were this reader's already; the 40 cases pass.
- `OWGraph.world_graph` without a lens takes about a second less on a large world: the lens view builds its reverse
  link index (who links to each element) on the first lens reading that asks for it, not in its constructor. Over a
  world of 20,570 elements (8,896 nodes, 32,215 edges), one read went from 2.6 to 3.6 s to 1.0 to 2.4 s (headless
  Godot 4.7.2, two alternating rounds of five). No answer changes: the index is built in the same order as before,
  and the suite is unchanged (1,184 passed, 4 skipped). The same change as the Unity SDK's 0.31.0.
- Schema pin to `v0.33.0-dist.102`: the record profile, new (`profiles/record.md` and its 32-case fixture): a game's
  run kept in the world its Characters live in, an Event marked `x_record`. The strand profile's ruled line moved;
  no schema field moved, and the generated headers move with the serial.
- Parity with the TypeScript SDK 4.123.2: `OWOpeners.openers_for` refuses a tools row whose `open.world` or
  `open.element` template does not begin with its scheme, or whose scheme (in any case) is `javascript`, `data`,
  `vbscript`, `file`, `blob` or `about`, which open no app. The refusal is a mistake with a message naming the tool
  and the key, as the reader's other malformed rows are; a null template is still null. The shared openers fixture is
  re-vendored at 61 cases.
- Parity with the TypeScript SDK 4.123.3: a value that is not one path segment is refused before anything is sent.
  The element type must be a lower-case word (letters, digits and underscores, starting with a letter); the id and
  the link field letters, digits and `_ . -`, not starting with a dot or a dash. `list`, `list_all`, `get_element`,
  `create`, `upsert`, `patch`, `delete` and `edit_links` answer an `OWApiError` of kind `refused` naming the value
  (`id "..." is not one path segment. Nothing was sent.`). The server decodes an escaped slash before it routes, so
  the escape the client already applied could not hold one; what passes is still escaped.
- The shared openers fixture is re-vendored at 65 cases, in parity with the TypeScript SDK: one refused case for each
  scheme that opens no app (`vbscript:`, `file:`, `blob:`, `about:` beside `javascript:` and `data:`), so a reader that
  forgot one of the six no longer passes. No reader changed; the six were already refused.
- `OWTools.ALL` carries Little Lens, in parity with the TypeScript SDK 4.123.5. The tools list is repinned at `a1573ac`
  (from `86208c8`): Little Lens, a world as a web of its elements and links, read only, is a listed row, so
  `OWOpeners.openers_for` offers it in the Open with menu for a world and for an element, to anyone (it needs no account).
  No type or function changed.
- Schema pin to `v0.33.0-dist.101`: the strand profile's Where it shows says what a reader draws. An empty slot as
  the next thing to make is a writer's rule; a surface that only reads may draw the filled slots alone, and still
  shows a half-built strand as the strand. No fixture, schema or reader rule moved; the generated headers move
  with the serial.
- The test runner awaits each test, and hands it the tree (`t.tree`), so a test can wait a frame.
- Schema pin to `v0.33.0-dist.100`: the strand on the front door. The strand profile's rule 2 says the server's front
  door (`GET /me` and an agent's join reply) serves `reading_aids.strand`, the six slots of the strand as that key
  reads the world, six null slots when the world has none or its story is out of the key's view; the charter
  profile's rule 2 orders the aids the Charter, the Guide, the Domains, then the strand. No fixture or schema file
  moved; the generated headers move with the serial.
- Schema pin to `v0.33.0-dist.99`: the strand profile's mark relaxed (only the story's id required; the event and
  the place null or absent read as unset, any other value there no mark) and its readings for a non-list multi-link,
  a nameless slot and the public rung, nine new cases (26). `OWStrand.strand_of` already answered them so.
- Schema pin to `v0.33.0-dist.98`: the strand profile, new (`profiles/strand.md` and its fixture, 17 cases): one
  story in a world in miniature, named on the World by `x_strand`'s three ids and read through four existing links.
  No schema file moved; the generated headers move with the serial.
- Schema pin to `v0.33.0-dist.97`: the address profile's four format cases on an empty string, one per part (an
  empty world, type, id or lens refuses by that part's own reason; only null or a missing key is absent), which
  `OWAddress` already answered so.
- Schema pin to `v0.33.0-dist.96`: two graph cases on a guest's own hidden creation (out of an unlensed graph with no
  count and no counted cut edge; a node of a lensed graph that keeps it, marked hidden, its edge to an element the
  lens never reached `outside_lens`), which `OWGraph.world_graph` already answered so.
- Schema pin to `v0.33.0-dist.95`: five new cases across the charter, lens and message fixtures, and `pairs.json`
  beside `presentation.json` (vendored with the rest; no reader for it here yet). `OWMessage.read_mark_of` takes
  `keyless`, as `is_to_everyone` does: a mark served without a credential is ignored, since the keyless public reader
  is served no `created_by` or `changed_by` on any body.
- Hidden beats `known_of`: a hidden element named in a guest's `known_of` that is not its own creation is not in that
  guest's view (`OWLens.resolve`, `OWGraph.world_graph`, and the owner reading as that guest): no stub, no row, no
  node, no count and no mark; a link to it is left out of the guest's served lists, and the owner reading as the guest
  counts an edge to it `not_visible` and an anchor on it `anchor_not_visible`. A hidden id in a guest's `whole` stays
  its own creation, served whole and marked.
- Schema pin to `v0.33.0-dist.94`: the charter, lens and names fixtures' twenty-four new cases. `OWLens.resolve` reads
  an anchor list's empty or White_Space-only string as no id, so a lens holding only such strings is a filter; a
  served body carries `hidden: true` where the hidden mark keeps the element (the owner's body, and below the owner a
  guest's own creation, never a stub), and no `hidden` key otherwise, a stored `false` dropped; below the owner an
  unseen anchor is recorded under no reason, so a child's cut of the element counts; a note goes with its anchor.
  `OWCharter`'s Domain hubs leave out an element the reader does not see as the field's type, so a proposed Object
  is no hub, the owner's view included.
- `OWLens.resolve` (and `OWGraph.world_graph` with a lens) follows the lens profile owner's rulings on readings no
  fixture case decided yet, ahead of the fixture's next serial, which carries a case for each: a link reaches only an
  element of its field's target type, and a generic pair (a Pin's `element_type`/`element_id`) only when its type key
  is one of the 22 slugs exactly as stored, nothing trimmed or folded, so a stored `"Character"` links nothing and is
  served to a reader below the owner as an unset pair (rulings 1, 2); an anchor id no element of its field's type
  holds is counted for the owner as `anchor_not_visible`, never skipped (3); an umbrella's hop keeps a child lens it
  reaches as an element before it is entered (4); a lens id a child cut before it was entered stays counted in the cut
  (5); a known-of stub keeps the base fields (`change_seq` too) and its type's public fields, a public link as the
  reader is served it, every other field at its unset value and no extension key (7); the mail part keeps two messages
  with one `created_at` in the order of the world's list, as the message profile rules, never by id (11, as the owner
  reversed it). A whole float in an `x_lens` key already read whole, as ruling 13 now says for every reader. Each
  change is held by a test named for its ruling.
- `OWGraph.world_graph` follows the owner's rulings on the graph section's silences, ahead of the same serial: a
  Pin's generic pair is placement, never an edge (G2); a node's `name` is the stored value, null when absent (G3); a
  node's `type` is as stored, never folded (G4); an edge's `index` is the target's place in the link list as served to
  that reader, so a contributor's counts a link to a proposed element (G5). An edge to an anchor the reader cannot see
  already carried the lens's `anchor_not_visible` (G1). Ruling 1 reaches the edge list too: a schema link to an
  element of another type than its field's target (a Character's `friends` naming a Location) names nothing, a
  dangling link, neither an edge nor counted in `edges_cut`.
- Pinned to schema-dist `v0.33.0-dist.92`: a Zone leaves map space in the lens profile's graph. Zones are nodes by
  default, for a public reader too; Map, Pin and Marker stay out until `map_space` (`OWGraph.MAP_SPACE`). The
  fixture's graph cases that changed with it were red on the old table and pass now.
- Pinned to schema-dist `v0.33.0-dist.93`: the lens fixture carries a case for each of the rulings above, nineteen
  new cases over a ninth world (171 in all: 86 resolve, 45 graph, 5 uses), and `profiles/lens.md` states each
  reading. The `text_only` keys case this SDK skipped is retired for `keys-an-integral-float-reads-whole`, which runs
  and passes, so the lens replay skips nothing now. Every case passes.

### Added

- `OWCharter.served(answer)`: the front door's packet as the server serves it, `reading_aids` in a `GET /me` answer
  or an agent's join answer, read as served for that key and never recomputed: the Charter, the Guide and the Domains
  as served, then the world's strand (serial 100) as `strand`, an `OWStrand.Strand` read by `OWStrand.served` (each
  slot `{id, name}` or null, `same` as served). Six null slots read as an empty strand, the world having none or its
  story being out of the key's view; a packet with no `strand` (a server from before serial 100) reads `strand`
  null; an answer with no packet (a player's join answer) reads null. `to_dict` writes the packet in the charter
  profile's order, the strand fourth, and only when it was served. `charter_of` still reads the three aids alone.
- `OWStrand.strand_of(world, reader)`: the strand profile's reader (schema-dist `profiles/strand.md`, serial 98), a
  world's strand as one reader sees it through the lens reader's own view (`OWLens.View`): the story the World's
  `x_strand` names, one of its events, that event's place, the story's `protagonist`, where the hero is now, and
  whether then and now are one place by id (`{narrative, event, location, character, now, same}`, each slot
  `{id, name}` or null). A slot holds only its own kind, no slot is filled from another, a list's order is never read,
  and a story the reader knows only as a stub fills its own slot alone. Only the story's id is required (serial 99):
  the event and the place null or absent read as unset, a place with no event is an empty place, and any other value
  there (an empty string, a number, a Dictionary) is no mark, as is a story that is not a String. A multi-link that is
  not a list lists nothing; a nameless slot reads an empty string; the public rung reads only a world open to anyone.
  Every case of the profile's fixture, held by its sha256.
- `OWNames.type_word(world, type, supertype, many)`: a world's own word for a type, the names profile's `x_names` on
  the World (schema-dist `profiles/names.md`), a port of the npm SDK's `typeWord` and the Python package's
  `type_word`. The supertype's entry first, its key trimmed and folded as the room profile reads, then the type's,
  else null for the standard's name; a value that is not a names map is null everywhere. Godot's JSON reads
  `version` 1 as 1.0, which is the number 1; `true` and `"1"` are not. Tested by the profile's fixture (23 cases,
  held by its sha256).
- `OWOpeners.openers_for(tools, kind, address, surface)`: the rows of an "Open with" menu for a world (`"world"`) or
  one of its elements (`"element"`), a port of the npm SDK's `openersFor` and the Python package's `openers_for`. The
  site's page comes first, then each listed tool with a link for that kind, in the list's order, each a Dictionary
  `{id, name, href, state}` (the row's word in sentence case, or null). The address is a Dictionary of the parts or an
  `OWAddress.Reading`; the surface a Dictionary (`audience` required, `signed_in`, `browser`, `phone`, `online`,
  `tool`). The answer is an `OWOpeners.Result`: `rows` when `ok`; else `reason`, the address profile's refusal, or
  `reason` "" and a `message` naming the key. The whole address is checked by the writer, so a malformed form, lens
  or moment refuses (`bad_form`, `bad_lens`, `bad_moment`), as the npm SDK 4.110.0 and the Python package 0.91.0 do.
  Tested by the packages' shared fixture (54 cases, held by its sha256).
- `online` on the `openers_for` surface (default true; anything but a bool is a mistake naming it), as the npm SDK
  4.118.0 and the Python package 0.96.0 take it. With `online` false, every row whose href is a web address (`http:`
  or `https:`, in any case, read from the row's own filled href) says `OWOpeners.NEEDS_A_CONNECTION`, "Needs a
  connection", the site's own row included. The words in order, the first that holds: "You are here", then "Needs a
  connection", then the account, browser and phone words, then "Opens the world". A row whose link opens an app on
  the device keeps its own word, and every row keeps its href. The shared fixture moves from 45 to 54 cases (sha256
  `5a9ebbc8…`, the same bytes as both packages').
- `OWTools.ALL`: the OnlyWorlds tools list (github.com/OnlyWorlds/tools, `tools.json` format 1) baked in at commit
  `86208c8`, the keys `openers_for` reads. The list is vendored at `codegen/tools/tools.json` and pinned in
  `codegen/tools-pin.json`; `codegen/generate_tools.py` writes `addons/onlyworlds/ow_tools.gd` and `--check` fails
  when the two disagree. A tool listed after a release is offered from the next one.
