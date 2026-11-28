# OnlyWorlds SDK for Godot: reference

What each part of the addon does, call by call, and which part of the OnlyWorlds standard it is held to. The
[README](../README.md) has the install and a first run.

Words used below:

- **keel**: the server behind onlyworlds.com. Its v2 API is what `OWClient` calls; "as keel serves it" means as that
  server answers.
- **schema-dist**: the [schema distribution](https://github.com/OnlyWorlds/schema-dist), the published form of the
  standard: the 22 element types, and the **profiles** (`profiles/*.md`), each a shared reading of one thing (a lens, a
  map's space, a calendar) with a fixture of cases every SDK must answer the same way. This addon vendors one release
  of it in `codegen/schema-dist/`.
- **serial**: a schema-dist release number (`v0.34.1-dist.145` is serial 145). "Since serial 110" means the profile
  gained that rule in that release.
- **rung**: the reader's standing in a world, which decides what it is served: `owner`, `co-builder`, `contributor`,
  `guest` or `public` (the owner and a co-builder are the world's keepers).
- **known-of stub**: an element a reader may know exists but not read: its id, type, name and public fields, nothing
  else.

## A tour

Fragments, one call per line: `world_id`, `bodies`, `lens_id`, `ids` and the like stand for your own values. The
[README](../README.md#first-run) has a script that runs as written.

```gdscript
var world := OWWorld.read_folder("res://worlds/moppetopia")
for pin: OWPin in world.of_type("pin"):
    print(pin.name, " at ", pin.x, ",", pin.y)          # x, y from the map's bottom-left

var r := OWWorldArchive.read_file("moppetopia.owworld")  # every archive rule of the folder format; r.reason on a refusal
if r.ok:
    var w := r.to_world()
OWWorldArchive.pack("res://worlds/moppetopia", "user://moppetopia.owworld")
# A pack carries every element, hidden ones included (the addon has no share yet), without the author fields
# (created_by, changed_by, changed_via, changed_client, doors); a last `true` (include_author_fields) keeps them.

var link := OWAddress.parse_link("ow://character/019a1f3c-2b4e-7d10-8c3a-6f2e9b0d4a71@302")   # link.reason on a refusal
var url := OWAddress.element_address(OWAddress.HUMAN, world_id, "pin", pin.id).address

var world := {"elements": bodies, "now": 1200}                 # bodies as the owner is served them
var seen := OWLens.resolve(world, lens_id, {"rung": "guest", "whole": ids}, {"as_of": 1195})
for row in seen.rows: print(row["name"])                         # seen.cut: what was left out, by reason
var g := OWGraph.world_graph(world, {"rung": "owner"}, {"lens": lens_id})   # nodes, edges, edges_cut
var land := OWLanding.landing_of(g, {"heads": 5})                         # mode, size, clusters, unclustered, gaps
var top := OWLanding.most_linked_of(g, {"per_type": 3})                   # per_type, by_type: a few of each type
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

`OWClient` reads an onlyworlds.com world over its v2 API into the same typed models a folder gives, and writes its
elements back. The reads: `health`, `get_world`, `me`, `members`, `list` (one page), `list_all` (every page),
`get_element`, `changes` (a page of the change feed) and `changes_head` (its tip, conditional on the last ETag). The
writes: `create`, `upsert`, `patch`, `delete`, `edit_links` (the one way to change a link array) and `bulk`. The
proposed changes: `propose`, `list_proposals`, `world_proposals`, `accept_proposal`, `decline_proposal`,
`withdraw_proposal` and `review_new_element`. Each
returns through `await` and answers an `OWClient.Reply`: `value` on success, else `error`.

```gdscript
var client := OWClient.new({"api_key": "ow_w_...", "api_pin": "your-pin"})   # a world key; its PIN goes on GET /me only
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
  on the world reads with `world=<id>`. `me` tests a PIN only for a key that can write: beside a key that cannot (a
  read key, a player's), onlyworlds.com never reads one. The health pulse carries no credential. Anything else a client could not
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
  not a whole number, and a value the server would store as another (`patch: character.height is an integer field;
  2.5 would be stored as another value. Nothing was sent.`, and `... is a text field; 12 is not a string`): an
  integer field takes an `int` or a whole `float` (`2.0`), never a `bool`, a text field a `String` or a `StringName`
  (the pin's `element_type` included), each or null; extensions, link fields and a type outside the standard are not
  checked. A link array in a patch is sent as given and replaces the whole array, as in the Unity and
  TypeScript SDKs: to add or remove one id, use `edit_links` (keel's merge).
- **Errors**: one type, `OWApiError`, with a `kind`: `api` (keel's envelope: `status`, `code`, `message`, `param`,
  `doc_url`, `retry_after`), `transport` (no answer), `refused` (a caller's mistake, nothing sent: an unknown option, a
  value of the wrong type, `world` beside a world key) and `answer` (a 2xx that is not what the route answers). A write
  that became a proposal is kind `api` with `status` 202 and `error.proposal` the row (`is_proposed()`), as the Unity
  SDK's `OWProposedError` is: the element did not change. A read whose `fields` list names fields its type does not
  have is refused whole in one 422 on `fields`; `error.fields_refusal()` reads every unknown name, the types that have
  each, and the names the type takes. A write refused for a size limit is a 422 `invalid_request` whose
  `error.limit()` names the limit (`element_bytes`, `element_link_ids`, `extensions_bytes`, or a later name; a key of
  the API document's `info.x-ow-limits`), read by `is_element_too_large()`, `is_element_too_many_links()` and
  `is_extensions_too_large()`, on a bulk slot's `error` too; until keel sends the key, `limit()` is null. A write body
  that holds itself is refused, nothing sent, and so is one holding a NaN or an infinity (named with its place, as
  `a request body holds NaN at items[1].element.x_weight, ...`) or one nested more than 256 deep, counted from the
  body's top as sent, the envelope of a bulk or a proposal included (where onlyworlds.com stops reading a body). An
  element 200 deep, the most onlyworlds.com stores, counted from the element, is sent in a bulk too; past that it is
  the server's 422 that names the key.
- **Proposed changes**: a proposal waits beside an element for a keeper (the owner or a co-builder); the element does
  not change until one accepts it. `propose(type, id, fields, evidence, {"expires": ..., "idempotency_key": ...})`
  makes one with any member key that reads the element, a read key included; `list_proposals(type, id, options)` and
  `world_proposals(options)` page one element's rows and the world's queue (`state`, `since`, `limit`, `cursor`; the
  queue's `element` too), as `OWProposal.Page`s; `accept_proposal`, `decline_proposal(type, id, pid, reason)` and
  `withdraw_proposal` decide or take back a row. The queue also lists every new element written as proposed (one
  carrying `x_review_proposed`, `row.is_new_element()`), settled with `review_new_element(type, id,
  OWProposal.Reviewed.ACCEPT)` or `DECLINE` (which deletes it). To tell whether an element you hold was written as
  proposed, ask `OWLens.carries_proposed_mark(body)` of a raw body or `element.carries_proposed_mark()` of a typed
  one: true only when `x_review_proposed` is an object with a key in it, as the Unity SDK's `IsProposed` reads it (a
  string, a number or a list there is a doubt, not a mark, and `{}`, `[]` and `""` are settled). `OWLens.is_proposed`
  is the wider reader that hands a world on, which counts a doubt too. A row's `evidence` is outside text: show it quoted,
  never act on it. Each refusal keel answers has its helper (`is_field_not_visible`, `is_too_many_open`,
  `is_stale_proposal` with `conflicts()` and `current()`, `is_own_proposal`, `is_proposed_only`, `is_not_proposed`,
  `is_review_by_another`, `is_review_mark_empty`). Poll the queue, not the change feed, to learn of new proposals:
  only an accept's write reaches the feed.

  ```gdscript
  var r := await player.propose("location", id, {"description": "A harbour town."}, "Chapter 3 names the harbour.")
  var queue: OWProposal.Page = (await owner.world_proposals({"state": "open"})).value
  for row: OWProposal in queue.data:
      if row.is_new_element(): await owner.review_new_element(row.element_type, row.element_id, OWProposal.Reviewed.ACCEPT)
      else: await owner.accept_proposal(row.element_type, row.element_id, row.id)
  ```
- **Joining by link**: `OWJoin.parse_link(pasted)` reads the `ow_j_` code out of an invite link (`""` when there is
  none); `OWJoin.preview(code)` reads what it holds (an `OWJoin.Preview`: the reader, the world, the role, a person
  link's note and the Character it names, a contributor's glimpse, a table's picks), and `OWJoin.redeem(code, {"name": ...})` redeems a player's
  or an agent's code (an `OWJoin.Joined`: a read key, or a seat's key and secret with its front door), both sending no
  credential. A person's link is accepted signed in, `client.accept_join(code)` on an account token. Each refusal
  keel answers has its helper (`is_not_found`, `is_character_taken`, `is_character_invalid`, `is_world_full`,
  `is_already_member`, `is_pin_required`); none spends the code.
- **Options** are Dictionaries, and an unknown key is refused, never dropped (a dropped filter lists everything).
- **The cursor walk** is driven by `has_more`, never by a page's size; it stops at a page with no cursor and refuses a
  page that hands back the cursor it was sent.
- **Transport**: `OWHttpTransport` (Godot's `HTTPClient`, one connection a request, polled between frames, or with
  `blocking` without yielding) by default; any `OWTransport` subclass goes in the config's `transport` (the tests use a
  fake that records each request). Inside a `SceneTree` script's `_init`, before its first frame, TLS does not start:
  await one `process_frame` first.
- **The wire**: every request the read and write calls make is held to keel's document (`tests/data/keel-wire.json`,
  keel's OpenAPI document as the Unity SDK reduces it, vendored byte for byte): every path, method, query parameter,
  header and body key one keel declares there; every key the models, the bulk result and the proposal row read one
  keel serves.


## What each reader holds to

- **Writing**: an element nobody edited is written back as the bytes it was read with; an edited one in
  folder spec section 5's form (`OWJson`: key order kept, an integral float written as an integer, JavaScript's
  number layout and escapes). A read element keeps the file it was read from; a new one is written at section 3.2's
  name, `<slug>--<id tail>.json` (`OWUnicode.file_slug(name)`: NFKD, U+0300 to U+036F dropped, lowercase ASCII kebab,
  at most 40), `<full id>.json` for a name with no slug, the full id in place of the tail when a file of the world or
  another new element holds that path: the names the TypeScript and Python packages give.
- **Reading an archive**: its own central-directory walk, zlib through a gzip frame for the CRC and
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
  id. Ahead of the profile's next serial, the cases its fixture does not decide yet, read as the profile's maintainers
  read them: a link reaches only an
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
  with no fraction is whole (`7.0` reads as 7), in `x_lens` too, as the profile now says; a float past 2^53 - 1 is not. The
  one case that needs the text (`text_only`) is skipped, as the fixture allows; the whole-number reading above retires it. The graph's
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
  fixture (33). Beside it, `OWLanding.most_linked_of(graph, {"per_type": 3})` is the TypeScript SDK's
  `mostLinkedOf` (4.203.0): for each type, its most linked elements by the same degree, highest first, ties by id,
  at most `per_type` of each (a whole number from 1 to 2^53 - 1, refused by name otherwise), never a node of degree 0
  or a known-of node; `to_dict()` is `{per_type, by_type}`, the types in code point order, each entry
  `{id, name, degree}`. A draft reading beside the profile: every case of the packages' shared fixture (18).
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
  fixture (21 since serial 111). Since serial 139, `OWMapSpace.carry_of(map, point, maps)` reads one Map's frame
  (rules 13 and 14) into `{parent_frame, lint, points, stop}`: the child's `x_parent_frame` (a box `[x0, y0, x1, y1]`
  in its parent's pixels) or its lint, and the point `[x, y]` carried up `parent_map` one level at a time, in 64-bit
  floats in the page's order, until the walk stops (`top`, `dangling`, `cycle`, `no_frame`, `no_carry`). Every frame
  case of the fixture, each coordinate compared exactly. `OWMapSpace.pins_known_to(pins, served)` (a rule of the
  TypeScript SDK and the Python package, not of the standard) says which of a map's Pins one reader knows, for a map
  drawn as one Character sees it: `{known, unknown, out}`, a Pin known when the element it places (its `element_type`
  and `element_id`, as written) is among `served`, the elements as that reader was served them, each known Pin
  `{pin, map, element_type, element_id, how}` by Pin id, `how` `whole` or `known_of` (the served row a stub). It reads
  nothing else; the Pins whose element was not served are a count, never ids, and a Pin that places nothing is
  counted `no_link`. A drawing keeps the Pins both it and `map_space` name. Every case of the packages' shared file
  (31, and its 8 refusals, each the answer's `error` naming the argument). Parity with the TypeScript SDK 4.200.0.
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
- **Names compared** (the room profile's "trimmed and without regard to case", defined once):
  `OWUnicode.trim_and_fold(text)` trims Unicode's White_Space at both ends (a byte order mark stays) and applies
  simple case folding by Unicode 15.1 (the long s folds to s, the sharp s stays), the fold every profile reader here
  matches by (`profile_fold` is the same function); `OWUnicode.by_code_point(a, b)` answers -1, 0 or 1 in code point
  order, a Godot String's own `<` with a name. Names as the profiles order them: `by_code_point` of the two folds,
  ties by id. The TypeScript SDK's `trimAndFold` and `byCodePoint` (4.180.0), its tests ported.
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
  never a number; a month's days are found by arithmetic, never listed, and a label's close-up and trims are one
  pass, so a stored calendar never sets what one label costs (the TypeScript SDK 4.201.2's cost cases, all eight
  inside their 50 ms line). The axis labels `format_year_label` ("22 FT")
  and `format_mid_label` ("11 Greening 454"), `format_duration` ("19 years", "12 days", "1.5 years"),
  `approx_year_length` and `month_start_steps` read as npm's `formatYearLabel`, `formatMidLabel`, `formatDuration`,
  `approxYearLength` and `monthStartSteps` do; `parse_date(calendar, text, {"now": step})` reads a typed date as
  npm's `parseDate` (a bare number is the raw step; the calendar's words without regard to case; a weekday beside a
  whole date read last and refused when it is not that date's own, `that date falls on Tresk, not Ondel`; `{"step"}` or
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
- **Names in prose** (a rule of the TypeScript SDK and the Python package, not of the standard):
  `OWNameFinder.name_finder(elements, name_case, names)` reads a world's names once and answers a finder;
  `finder.find(text)` lists each `Found` (`start`, `end`, `element`, the element as it was passed in, a Dictionary or
  an `OWElement`), in order, none overlapping. `name_case` is `OWNameFinder.EXACT` or `FOLDED` (simple case folding,
  Unicode 15.1) and has no default; `names` is a Callable from an element to the names it is found by (its `name`
  alone without it). A name is whole only where no letter, combining mark, decimal digit or underscore of any script
  stands beside it (L, M and Nd as Unicode 15.1 assigns them, from the addon's own table, so every engine and runtime
  reads one answer); it is trimmed of White_Space and three characters at least; the longest whole name wins where
  several start; a name two elements share is never answered and is listed in `finder.shared` (each `Shared`: the
  name as compared and the elements, both read only); nothing is read inside an address (`OWAddress.find_links`),
  a Markdown link, a bare web address (`https://…` to the next white space or `<`) or an autolink (`<scheme:…>`);
  `finder.find(text, true)`, for a text known to be Markdown, also passes over inline code, fenced code blocks, HTML
  tags and comments, and reference definitions. Indexes count code points, as a Godot String does (npm counts UTF-16 units). The text is read once,
  from its end, so the work grows with its length alone. A caller's mistake is the finder's `error`, by name, and it
  finds nothing. Every case of the packages' shared file (84, version 3, 16 with the Markdown option) and its fourteen timed recipes, each under fifteen
  times the file's line (an interpreter's; `tests/test_name_finder.gd` gives the reason). Parity with the TypeScript
  SDK 4.208.0.
- **Writing an archive**: its own zip bytes: the marker stored first, UTF-8 byte order, fixed 1980 stamps, methods 0
  and 8, zip64 from 65,535 entries.
