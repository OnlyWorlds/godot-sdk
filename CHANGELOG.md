# Changelog

Notable changes to the OnlyWorlds SDK for Godot. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing is released yet; the history before this file is in
the git log.

## [Unreleased]

### Added

- `OWClient.bulk(items, {"create_only": true})`, sent as `create_only`: every item with an id is created as `create`
  creates it, never replaced. An id the world already holds answers that item's slot 409 `id_conflict`, and the element
  stays as it was; the rest of the batch goes on as before, and the slot reads as any failed slot does
  (`BulkResult.failed()`, its error's `is_id_conflict()`). Left out, false or null, the body is the one earlier
  versions sent. A value that is not a bool is refused before anything is sent ("bulk: create_only is a bool"). Parity
  with the TypeScript SDK 4.185.0, its test vector ported; null reads as left out, as every option here does and as
  keel reads it, where the TypeScript SDK refuses it.
- A third layout method, `by-links-3d` (the default layouts page, serial 137 on):
  `OWLayout.layout_by_links_3d(graph, elements = null, held = null, held_unit = null)` lays a whole world out in three
  dimensions by its links. The largest part of the graph that no single element's removal parts is cut into groups
  round its most linked elements, packed apart in directions read from a table (`OWLayoutDirections`, generated from the
  pinned dist's own table by `codegen/generate_layout_3d.py`, never computed), and settled by 300 seeded force steps;
  what hangs off it fans out. Where the world's Maps hold three or more of its elements by a Pin, the fullest Map is a
  flat plate with each pinned element at its Pin (a layout map is never the plate), and a Map over a place on it a
  small plate above. Every other piece of linked elements is laid out on its own: one with a pinned or held element
  stands where those points put it, the rest on a ring beside the main shape. `held` hands back points an earlier
  answer gave, so those elements stand where they stood; `held_unit` is the step they were rounded to. An element
  linked to no other and pinned on no map is listed in `unplaced`. Answers `{method, version, points, centres,
  unplaced}`, each point `{id, x, y, z, how, group, part, held}` in 64-bit floats; a refusal the page names answers
  `{error, code}` (`held-not-object`, `held-not-point`, `held-unit`, `held-box`). Every one of the method fixture's 116
  cases passes: each list exactly, every point to the last bit where the page promises it and within 6e-8 where it
  allows the runtime's cosine, sine and arcsine (an `arm` or `link` element, a piece on the ring).
- The `unplaced` reading for every layout method: `OWLayout.unplaced_by_kind(graph, placed)`,
  `unplaced_around(graph, focus, placed, steps = 1)` and `unplaced_by_links_3d(graph, placed)` answer
  `{method, unplaced}`, the ids of the nodes the method counts that are not in `placed` (the elements a saved layout
  Map's Pins stand for), in code point order. A member of `placed` that is not a non-empty String names no element;
  `placed` is an Array, a `PackedStringArray` or a Dictionary used as a set. Every `unplaced` case of both layout
  fixtures passes (17 and 9), and a saved `by-links-3d` Map read back through `OWMapSpace` gives its answer's own
  `unplaced`.
- A co-builder, and a contributor's own hidden creations (the lens profile, serial 138): the hidden mark keeps an
  element from every reader but a keeper (the owner or a co-builder) and the one who made it. `OWLens.RUNGS` gains
  `co-builder`, which reads the whole world as the owner does, hidden elements included and bodies as stored, with none
  of the owner's two counts. A contributor reader's `whole` lists the hidden elements it made: each is in its view and
  its body carries `hidden: true`. The lens readers, `OWCharter.charter_of` and `design_parts_of`, the strand reader
  and the graph read both through the view. Serial 138's three lens cases and one charter case on the two rules pass.
- A talk on an Object or a Construct (the room and report profiles, serial 135): `OWLens.talks_of(element)` answers
  each `{type, id}` a line in the room (the pair `narrative` + `Message` and the mark) names in its `objects`
  (`object`) or `constructs` (`construct`), read from the line alone, and `OWReport.talks_of(element)` the same of a
  report (the pair `narrative` + `Report` and the mark), the talks a reader shows it with, never which one it closed.
  An entry that is not a String or is empty once trimmed of White_Space names nothing, a field that is not an Array
  names none, and every other entry is an id read as written; anything that is no line, or no report, answers `[]`.
  `OWLens.TALK_FIELDS` names the two fields. Every case of the room fixture's `talk_cases` (13, in
  `tests/test_lens.gd`) and the report fixture's (6) passes, each list's count held.
- The design state (the charter profile, serial 135): `OWCharter.design_parts_of(world, reader)` answers each Object
  or Construct the reader is served whole whose subtype, trimmed and folded, is `in design` or `locked`
  (`OWCharter.DESIGN_STATES`), as `{type, id, state}`, only in a world where `charter_of` finds a Charter for that
  reader: a known-of stub has none, and a reader the hidden mark keeps the Charter from reads none. Every case of the
  charter fixture's `design_cases` (13) passes, the count held.
- A line of a report's `consequences`, read as every reader reads it (the report profile's rule 10, schema-dist serial
  129): `OWReport.read_line(line, world = null)` and `OWReport.read_lines(text, world = null)`, the npm package's
  `readReportLine` and `readReportLines` (4.169.0) and the Python package's twins. `read_lines` splits a text at every
  carriage return and line feed, trims each piece of White_Space and drops the empty ones. `read_line` answers an
  `OWReport.Line`: `line`, `address` (the element it names, `ow://<type>/<id>` with the id in lowercase, or null),
  `reading`, `start` and `end` (the address as written, code points) and `words` (what a reader shows). The line's
  address is the last one `OWAddress.find_links` finds that names an element of this world; an address of another
  world, a slug, a world alone or a lens with no element stays prose. The address leaves the words only when it is
  canonical, has no moment and no lens, and stands apart, alone or in a matched pair, and a colon before it goes too;
  otherwise the whole line is shown, still naming its element. The page's lines fixture (101 cases and 16 texts) runs
  whole in `tests/test_report_lines.gd`, read from the vendored folder.
- The default layout method: `OWLayout.layout_by_kind(graph)` and `OWLayout.layout_around(graph, focus, steps = 1)`,
  a world's default picture and one element's, the npm package's `layoutByKind` and `layoutAround` (4.167.0) and the
  Python package's `layout_by_kind` and `layout_around` (0.127.0). By kind: each kind of element gets a point on a
  circle, links act as springs and neighbours push apart for a fixed number of seeded steps, and the answer is fitted
  into a frame of -1 to 1. Around: the focus at 0, 0, its neighbours on rings round it, and with `steps` 2 their
  neighbours fanned out beyond. Each takes an `OWGraph.Graph` or a `{nodes, edges}` Dictionary, puts it in one order
  first, and answers `{method, version: 1, points}` (points in the order the nodes were handed in, 64-bit floats, never
  a `Vector2`) or `{error}` naming what it cannot read. By kind gives the npm package's points to the last bit, around
  within 1e-12. The kinds' anchors are a table of bit patterns (`ow_layout_anchors.gd`, written by the new
  `codegen/generate_layout.py` from the shared fixture), never a decimal: Godot 4.7.2's JSON reads 56 of the fixture's
  506 anchors and 871 of its 6,464 wanted coordinates as a neighbouring double, so the same script writes the wants as
  bits too (`tests/data/by-kind.bits.json`, naming the fixture's sha256). The fixture (`tests/data/by-kind.json`, the
  npm package's bytes) runs whole in `tests/test_layout.gd`: 12 by-kind cases bit for bit, 7 around cases.
  `tools/twin_run.gd` answers the layout twin's two kinds as well, and takes a `from to` range of cases: on 1,500
  random graphs against npm, 159,081 by-kind points equal to the bit and 705 around runs within 1e-12.

- An address found in prose (the address page's "An address in prose", schema-dist serial 123):
  `OWAddress.read_link_at(text, index = 0)` answers a `Found` (`reading`, `end`): the address that starts exactly at
  `index` in a text and the index just past it, or null when the text there is not an address. The npm package's
  `readOwLinkAt` and the Python package's `read_ow_link_at`. Both forms, the prefix as written. Where the address ends
  is the grammar's, never the next space's: after the path it continues only with `@` and a moment and then `?lens=`
  and a lens; any other query key, a fragment and a full stop are prose. In the site's form the run after `/w/` is read
  whole: exactly an id's form is the id, any other legal slug the slug, else no address, and a run followed by a
  letter of any script, a combining mark or an underscore is cut inside a word and is no address. `index` and `end`
  count code points, as a Godot String does (npm counts UTF-16 units, Python code points). An index below 0 or past
  the end reads nothing. `parse_link` is unchanged. The address fixture's 61 prose cases, skipped by kind until now,
  run against it and pass. `OWUnicode.is_letter_or_mark(c)` reads general category L or M from a table `generate.py`
  now emits into `ow_unicode_data.gd` (`LETTER_OR_MARK`, 725 ranges of UnicodeData 15.1.0 as schema-dist vendors it,
  checked equal to Python's `unicodedata`).
- `OWAddress.read_link_at` answers null when the address would begin inside a word (schema-dist serial 127): after a
  letter of any script, a combining mark or an underscore (`elbow://object/<id>` and `_ow://…` are prose), the same
  set that cuts a run after it; a hyphen, a digit, white space, punctuation or the start of the text before the prefix
  does not glue. One index back is a whole code point here, so a letter above U+FFFF glues as any letter does. Two
  addresses written back to back read as two after an id that ends in a digit and as one after an id that ends in a
  hex letter. The address fixture's fifteen new prose cases run and pass.
- Every address in a text (the address page's find-all, schema-dist serial 128): `OWAddress.find_links(text)` answers
  an `Array[Found]`, each what `read_link_at` reads at a place where either prefix starts, in order. The npm package's
  `findOwLinks` and the Python package's `find_ow_links`. The search goes on from the end of each address found, so no
  two overlap and a prefix inside an address is no start, and two addresses written back to back are found as two
  where `read_link_at` ends the first. `Found` gains `start`, the index the address begins at (what `read_link_at`
  was given). Indexes count code points, as a Godot String does. The address fixture's two `prose-all` cases run and
  pass.
- `OWTools` repinned at the tools list's `aa00969` (tools.json sha256 `2140d2b9…`): the OnlyWorlds mapper is listed,
  a world's maps and layouts in the browser, read only. Its `element_types` is null, so its element door is offered
  on every type's menu; it skips map space (a Map, Pin or Marker as served), needs an account and opens a public
  world with none. Seven rows (from six); no other row's reading changed.
- `OWTools` repinned at the tools list's `53a05e4` (tools.json sha256 `198f62a2…`), the list the TypeScript SDK
  4.160.0 bakes: Windrose is listed, a map of one world in the browser that only reads, with no `open`, so the Open
  with menu offers it nowhere. Six rows (from five); no other row's reading changed.
- `OWTools` repinned at the tools list's `0a7539c` (tools.json sha256 `f1fac743…`), the list the TypeScript SDK
  4.159.0 and the Python package 0.120.0 bake: Subs is listed, a game that opens a Character (`needs` account, no
  world link).
- Report threads (the report profile's rule 9, schema-dist serial 120): `OWReport.threads_of(narratives)` answers a
  `Threads` (`to_dict()` is the fixture's shape): `parents`, each report's parent as `none`, `report`, `board`,
  `missing`, `other` or `self`; `groups`, one `{parent, kind, reports}` per report or board entry some report names,
  the reports in `created_at` order as `OWMessage` orders messages (through `OWLens.time_key`; equal times keep the
  order given, an unreadable time last); `lints`, `chain` and `self`. Only reports are grouped; a parent is read as
  written (absent, null, no String or White_Space only is none; content is never trimmed); a report that names itself
  names no parent and still heads its thread; nothing is walked further up. Of two elements with one id the first is
  read and the later one ignored. `OWReport.is_report` and `is_board_entry` are the room profile's pairs with the mark,
  read by `OWLens`'s room reader. Every case of `profiles/report.fixture.json` (20), with tests of its own for a time
  with no offset, one id given twice, a parent that is no String or an object, and a parent with padding. Parity with
  the TypeScript SDK 4.159.0 (`reportThreadsOf`) and the Python package 0.120.0 (`report_threads_of`).
- How an element is shown by its kind: `OWViews.view_of(element)` reads the distribution's `views.json` (version 3,
  serial 115; presentation, not the standard) and answers a `View`: `row`, the matching row (the table's own,
  read-only) or null when the element draws as its type; `sentence`, the first field the row names whose value is a
  String with something left after trimming White_Space, cut at its first U+000A or U+000D and trimmed again, else
  null; `banners`, the marks at its page's head in the file's order (`known_of` and `hidden` only when true, the two
  review marks only as an object with at least one key, `x_served_trimmed` only when its list holds a String with
  something after trimming), then the row's own marks by presence; `order`, the fields its page draws (lead, then the
  type's section fields in the schema's order, then fold, each once, only a field that holds something; a field in
  both lead and fold is drawn in the lead). `to_dict()` is the fixture's shape. A row's kind is a type, a type with a
  supertype, or a profile's pair, which matches only with that profile's mark by `OWLens`'s room and charter readers;
  types and supertypes are trimmed and folded as the room profile folds them; the most specific row wins, and on a
  tie the first. A generic link, a Pin's `element`, is one field of the order at its place, holding something only
  when both its keys (`element_type`, `element_id`) are Strings with something left after trimming.
  `codegen/generate.py` bakes the table into the generated `ow_views_table.gd` (`OWViews.ROWS`, `BANNERS`, `LAYOUTS`,
  `SECTION_FIELDS`, `GENERIC_LINKS`, `VERSION`, `SHA256`) and refuses a file of another version,
  a column the reader does not read, a pair its profile's reader does not match, two rows of one kind, a field its type
  lacks, an undefined layout, or a cite whose quote is not at its line (`codegen/test_generate_views.py`). Every one of
  the fixture's 46 cases, two of them against tables of the fixture's own, and its 10 cites; the TypeScript SDK's and
  the Unity SDK's vectors beside them. Parity with the TypeScript SDK 4.152.0's `viewOf` and the Unity SDK's
  `OWViews.ViewOf` for version 2; version 3's generic link built to the file's words and its fixture.
- The map space profile's layout reading (rules 8 to 10, serial 110): `OWMapSpace.layout_of(map, maps, pins)` answers
  a `MapLayout` whose `to_dict()` is `{layout, ground, hand}`. `layout` is the Map's `x_layout.method` when
  `x_layout` is a Dictionary whose `method` is a non-empty String (`"hand"` a board; a method no page names answers
  itself), else null. `ground`, only on a layout map, is the id in `x_layout.settings.ground.map` when it names a Map
  in `maps` other than this one, else null; its size is not returned. `hand` is the ids, by code point, of this Map's
  Pins a new lay-out keeps: every Pin on a board, the Pins whose `x_hand` is the bool `true` on any other layout map
  (`1`, `1.0` and `"true"` are not), none on a plain Map. `pins` may hold every Pin the caller has: the reader keeps
  those whose `map` names this Map, reads rows as `map_space` does (a row without a non-empty String id is no element,
  a Map row without one no layout map; the last row served for an id) and counts a Pin whose element it cannot see.
  A caller's mistake (a `map` that is not a Dictionary, `maps` or `pins` not an Array) is named in `error` and reads
  nothing. Every one of the fixture's 21 `layout_cases`, whole answers in key order, and the TypeScript SDK 4.142.0's
  and the Python package 0.110.0's vectors beyond the fixture. `map_space` is unchanged.
- The calendar's labels, durations and typed dates: the last of the TypeScript SDK's calendar functions, on
  `OWCalendar`. `format_year_label(calendar, step)` is the compact axis label (the era's year and abbrev, or its
  name; a falsy word, `""` or 0, prints the year alone) and `format_mid_label` the dense one (day, month and year, no
  era word; an intercalary day's name and year; with no months the year label). `format_duration(calendar, steps)`
  speaks a span: years from the base year length (one decimal under 10, whole from 10, half up as JavaScript's
  `Math.round`), else the step word (`step_name`, else the grain, trimmed as JavaScript trims; `""` reads `step`),
  to two decimals, a fraction of a step included. `approx_year_length` and `month_start_steps(calendar, year)`
  (`{month, name, step}` each, by arithmetic). `parse_date(calendar, text, {"now": step})` reads a typed date to
  `{"step"}` or `{"error"}` in the TypeScript SDK's words, and `is_parse_error` tells them apart: a bare number is
  the raw step; era, intercalary and month words match without regard to case (U+0130 lowered as JavaScript does),
  the longest first by UTF-16 length; a missing year reads in the now's year and is an error with no now; the default
  era is the one holding the now, else the latest-started open era, a tie to the first listed. An unknown option, a
  `now` that is not a whole number or options that are not a Dictionary answer `{"error", "refused"}` and push the
  error. `abs_year_for_era_year` is its inverse of an era's year. `validate_config(value)` is the builder's
  check, `validateCalendarConfig`'s messages in its order on any JSON value, read as JavaScript reads it (an absent
  key prints `undefined`, a string's `length` is read, mixed values compare as `<` does, eras ordered by V8's sort);
  where the TypeScript SDK throws (eras or intercalary days that are an object, a number or true; a null value or
  entry) it answers `eras must be a list`, `intercalary must be a list`, or reads the null as an object with no keys.
  `resolve_calendar(elements, id, {"fallback_to_only": true})` is `resolveCalendar`: the id left out
  (`OWCalendar.NOT_CHOSEN`, the default) falls back to a world's only calendar, null stays none, ids compare as
  `===`, an unknown option is refused (pushed, null). Where Godot answers differently: a number past a 64-bit int is
  unrecognized (JavaScript reads a rounded double) and one past 2^53 is exact; an era abbrev or `step_name` that is
  not a string is passed over (the TypeScript SDK throws); a final capital sigma lowers to σ, not ς. Held to
  parity vectors generated from the TypeScript SDK 4.133.2's built code (`codegen/generate_calendar_parity.mjs`,
  `tests/data/calendar_parity.json`, `--check` to see they still hold): the fixture's 34 calendars and 16 written for
  the traps, about 15,000 parses, 148 validations and 784 resolutions.
- `OWTools` repinned at the tools list's `9452529` (tools.json sha256 `8905defb…`), the list the TypeScript SDK
  4.133.1 bakes: Atlas's row carries `opens_public: true` (its `needs` stays `account`), so a world's public page
  offers Atlas live.
- A tools-list row can say it opens a public world with no account. `OWOpeners.openers_for` reads the row's
  `open.opens_public`: on a world's public page a row with `needs: account` and `opens_public: true` is live instead
  of "Needs an account"; anywhere else it reads as its `needs` says. Absent reads as false. A value that is not true or
  false, or true beside a `needs` other than `account`, is refused by name, as a row that is not one. The same rule as
  the TypeScript SDK 4.133.0; the shared openers fixture at 110 cases.
- A tool that opens one kind of element is offered only on that kind. `OWOpeners.openers_for` reads the tools
  list's `open.element_types`, the element types a tool's element door opens (type words such as `character`), or
  null (or the key absent, as in a list older than it) for every type. On an element's menu a row whose
  `element_types` does not hold the address's type word is not there, whether or not the row has a world door: the
  tool opens other kinds, so its world is not offered from this element either. The type is read from the address,
  so no element body is needed; a world's menu reads no element types. Refused by name, as a row that is not one: a
  word outside the 22 (in another case included), an empty list, a repeat, and `element_types` on a row with no
  element door. Parity with the TypeScript SDK 4.132.0 and the Python package 0.106.0; the shared openers fixture
  re-vendored at 100 cases (from 92), the same bytes as theirs, every case by name green.
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
  `delete` (with `if_match`), `edit_links` (`POST /{type}/{id}/links/{field}` with `{add, remove}`, keel's merge of
  one link array) and `bulk` (`POST /bulk/`, `atomic`, a typed
  `OWClient.BulkResult` whose slots carry their own status, error and proposal, and `was_replay` from keel's replay
  header). The body is cleaned as the Unity SDK cleans it (the read-only keys left out, a null string field sent as
  `""`, extension keys untouched) and written compact with JavaScript's number form. Every write sends the PIN and
  `X-OW-Client` (the new `client` config key, `godot-sdk` by default), and `X-OW-Agent` on a client the new `agent`
  config key declares an AI agent. A 202 is an `OWApiError` of kind `api` and status 202, its row in `proposal`; new
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
  vendored from the Unity SDK), every key the models read to what keel serves. The vendored document follows keel's
  (at `cf4be12d237e`: the Pin list takes `element`, the Pins that place that element of any type, `""` for the Pins
  placing nothing; a read-only sign-in's token answers carry `scope`; the AI lens answer carries `charged`; the member
  rows carry `follows_sponsor` and `may_change_character_note`, and two 422 codes, `seat_above_sponsor` and
  `seat_follows_sponsor`, are listed; the agent seat rows carry `may_change_character`, its note and `follows_sponsor`; the front door on `GET /me`, `POST /join` and two `PUT /me/...` answers serves
  `front_door.charter_element` and `front_door.charter_skill_elements`; a member's PATCH body and answer carry
  `may_change_character`; the draught's answer carries `work[].by_role`; the request body of `POST /account/worlds/{world_id}/messages` takes
  `constructs`, `objects` and `relations` beside `characters`; `POST /bulk` takes `create_only`, and every proposal
  answer declares `house`; both invite link bodies take `note`, and `POST /join/preview` answers it);
  `list` already sends any field-named filter as given, so `{"filter": {"element": id}}` needs no change here, and no
  path, method, parameter or request key moved: the document's words, not the client's, are what moved.

### Fixed

- The Moppetopia demo never draws a layout map as its root Map: among the Maps with no `parent_map` it skips any whose
  `x_layout` is a Dictionary with a non-empty String `method` (the map space profile's rule 8, read through
  `OWMapSpace.layout_of`), so a layout map with the world's image or a name that sorts first is no longer drawn as the
  ground. The choice is `root_map_of(world)`, a static function `tests/test_demo_root_map.gd` holds.
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

- `OWGraph.world_graph`: a co-builder reads the graph as a keeper (the lens page, serial 140). The flags `hidden` and
  `proposed`, and the `hidden` and `proposed` counts in `cut` and `edges_cut`, are a keeper's (the owner or a
  co-builder), where they were the owner's alone, so a co-builder's unlensed graph is answered as the owner's is on the
  same inputs; `not_visible` and `anchor_not_visible` stay the owner's. `OWGraph.OWNER_ONLY_REASONS` now holds those
  two, the new `OWGraph.KEEPER_ONLY_REASONS` holds `hidden` and `proposed`, and `OWNER_ONLY_FLAGS` keeps its name (the
  fixture's key) for the two flags a keeper may ask. A refused flag's message says "a keeper's alone (the owner or a
  co-builder)". Every case of the lens fixture's `graph` kind passes.
- The reading aids and the strand say what type each of their elements is (the charter and strand profiles, serial
  133): `OWCharter.charter_of` writes the Charter `{id, type, name, rules, skill}` (`law`), the Guide `{id, type, name}`
  and each Domain `{id, type, name, sentence, hubs}` (`construct`), and `OWStrand.strand_of` each filled slot
  `{id, type, name}` (the kind the slot holds, `now` a `location`), each type the element's own as the lens folds it.
  A reader handed the packet alone fetches an id by its type. `OWCharter.served` and `OWStrand.served` keep a served
  `type`, and give an entry served without one (a keel from before serial 133) its fixed type beside `id`. The charter
  test compares each case's packet whole, so a key added later cannot pass unseen. Every case of serial 133's two
  fixtures passes.
- `OWCharter.served` hands over each served entry as its kind's named keys, in the charter page's order: the Charter
  `{id, type, name, rules, skill}`, the Guide `{id, type, name}`, each Domain `{id, type, name, sentence, hubs}` and
  each hub `{type, id}`, each value as served. A key the page does not give (a host's `description`, say) is dropped,
  where before it was passed on: the page's packet carries none of the text an AI reader follows, which it reads from
  the element whole. Unity and Unreal already read the packet this way.
- Schema pin to `v0.34.1-dist.145` (`f73146c`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 145). Only the
  charter and checks pages, the charter fixture and the views fixture moved; the generated files moved in their stamp
  only. The charter page's rule 4 names the field an AI reader follows: the `description` of the Charter and of each
  Object in its skill, whole as the world holds it, a part or a shortened copy of it being data. A leading Charter
  whose `description` holds nothing gives that reader no house rules, and its text is taken from no other field and no
  older Charter. The checks page says its rule list is checked, never followed. The charter fixture gains four cases
  (61 in all), each a newer Charter whose `description` holds nothing leading with an empty skill; `charter_of`
  answers all four as the page says with no change, and every existing case passes. The views fixture's one quote of
  the charter page follows its new wording.
- Schema pin to `v0.34.1-dist.144` (`35a12a0`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 144). Two serials:
  only the charter and map-space pages, the map-space fixture and the dist's README moved; the generated files moved
  in their stamp only. Serial 143: the charter page's rule 4 says an AI reader follows the Charter's text and the text
  of the Objects in the Charter's skill, as `charter_of` answers it for that reader, and every other element's text
  stays data; who may change that text is the host's to rule; the charter fixture is unchanged. Serial 144: the
  map-space page gains rule 15, a point on a Map brought down into the pixels of a Map below it, and a fourth reading,
  `downOf`; the map-space fixture gains its own list of 28 `down_cases`, which this SDK does not read yet. The 46
  cases and 32 layout cases are unchanged and every one passes with no reader change; the 66 frame cases, not read
  here either, are unchanged.
- Schema pin to `v0.34.1-dist.142` (`5d5a8be`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 142). Only the
  map-space page and its fixture moved; the generated files moved in their stamp only. Serial 142: a Zone outlined on a
  child Map and on its parent keeps two outlines, never joined and with no point added on the edge of the child's
  rectangle or its parent frame, and what a tool draws there is the tool's; rule 4 says one outline per Map the Zone
  has placed Markers on. The map-space fixture gains three cases (46 in all); every one passes with no reader change.
- Schema pin to `v0.34.1-dist.141` (`f87f9ab`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 141). Only the
  charter and lens pages and their fixtures moved; the generated files moved in their stamp only. Serial 141: the
  charter page says folded Domain names compare by code point, as written, never by UTF-16 unit, a collation or a
  locale, with nothing normalized, and a name is trimmed and folded as the room page defines both. The charter fixture
  gains ten Domain order cases (57 in all) and three design cases (19), the lens fixture four graph cases on a
  co-builder's lens anchors (66 graph cases, 256 in all); every one passes with no reader change.
- Schema pin to `v0.34.1-dist.140` (`5195351`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 140). Only the
  lens page and its fixture moved; the generated files moved in their stamp only. Serial 140: in the graph, the flags
  `hidden` and `proposed` and the hidden and proposed counts are a keeper's (the owner or a co-builder), where they
  were the owner's alone, so a co-builder's unlensed graph is answered as the owner's is on the same inputs;
  `not_visible` and `anchor_not_visible` stay the owner's. The lens fixture gains six graph cases (252 in all); no
  answer on an existing case moved.
- Schema pin to `v0.34.1-dist.139` (`fc46657`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 139). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only, and the layout anchor
  table and its bits file in the fixture sha256 they name (no anchor moved). Serial 137: a third default layout,
  `by-links-3d`, with its own fixture, which this SDK does not lay out yet; a member of a layout map's `placed` that is
  no non-empty string names no element (two `unplaced` cases, not read here); map-space reads a whole-number width,
  height or depth as written (four new `cases`, three new `layout_cases`, each passing with no change to a reader).
  Serial 138: the hidden mark keeps an element from every reader but a keeper (the owner or a co-builder) and the one
  who made it; the lens fixture gains four cases, the report fixture three talk cases and the charter fixture three
  design cases. Serial 139: where a child Map lies on its parent, `x_parent_frame`, with the map-space fixture's
  `frame_cases`, which this SDK does not read yet. No answer on an existing case moved.
- Schema pin to `v0.34.1-dist.136` (`56f5c02`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 136). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. Serial 135: the room page
  names a talk on an Object or a Construct (a line in the room that names one in its `objects` or `constructs`), the
  report page shows a report with the talk on each Object or Construct it links, and the charter page gives an Object
  or a Construct a design state, `in design` or `locked`, in a world where `charter_of` finds a Charter for the
  reader; a Charter the hidden mark keeps from a reader is not that reader's. The room fixture gains `talk_cases`
  (13), the report fixture `talk_cases` (6) and the charter fixture `design_cases` (13); no existing case or answer
  moved, and every existing case passes with no change to a reader. Serial 136: the packet page's fourth work-item
  state, `standing`, its optional `x_packet_from` (who asked) and its first fixture, `packet.fixture.json`; this SDK
  reads no work item's state, so nothing here moves with it.
- Schema pin to `v0.34.1-dist.134` (`700f04b`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 134). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The strand page says no
  reader trims a member: one of white space alone is a string that names no element, so its slot is empty, and the
  empty string in any of the three members, `narrative` too, is no mark. The strand fixture holds 42 cases on 39
  worlds (thirteen more); `tests/test_strand.gd` reads it from the vendored folder, checked against the manifest, and
  every case passes with no change to `OWStrand`. The checks page's specimen is one world's own house rules, a
  specimen of the form and not a set to adopt (no rule or case moved), and the lens page says a lens is read for its
  reader, never for the Character whose draught it is read beside.
- Schema pin to `v0.34.1-dist.133` (`6c28fc1`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 133). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The charter and strand
  pages say what type each element of their packets is, a hub is an element of the kind its link field links to (an id
  of another kind, or of no element, names no hub), and every type compared to a kind is trimmed and folded as the
  room profile defines it. The charter fixture holds 47 cases (six more), the strand fixture 29 on 26 worlds (two
  more). `tests/test_charter.gd` and `tests/test_strand.gd` read them from the vendored folder, each checked against
  the manifest; every case passes.
- Schema pin to `v0.34.1-dist.132` (`c2a4652`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 132). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The distribution now
  carries the default layouts page, `profiles/layout.md`, and its fixture, `layout.fixture.json`: the `by-kind` and
  `around` methods `OWLayout` implements, written out step by step, with 17 `by-kind` cases and 10 `around` (five and
  three more than before), and `unplaced`, the reading of which elements a saved layout map does not place (15 cases;
  not implemented here). `tests/test_layout.gd` now reads the distribution's fixture from the vendored folder in place
  of the npm SDK's `by-kind.json`, and its wants from `tests/data/layout.bits.json`, which `codegen/generate_layout.py`
  makes from it; every case passes and no method changes. The map-space page's rule 8 names the layouts page as the
  page of the method words, reads a method word whole, and says reading or drawing a layout map writes nothing.
- Schema pin to `v0.34.1-dist.131` (`0dc4ab7`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 131). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The room page defines its
  fold exactly (simple case folding by the C and S rows of CaseFolding.txt 15.1, never lower-casing or full folding),
  which `OWUnicode.profile_fold` already does, and the room and message pages say a value that is not an object is no
  element: every reader answers for it as for a body that is not a message, and none fails. The fixtures gain cases:
  room 10 (48), message 17 (120), lens 7 (242), calendar 1 (78, 35 calendars, 229 steps). The calendar parity vectors
  were regenerated from the TypeScript SDK 4.133.2 at the same commit, for the fixture's new calendar (35 named, 149
  validate rows). The import-map page reads the room page's fold instead of copying it.
- Schema pin to `v0.34.1-dist.130` (`f8c5ce8`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 130). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The message page says the
  order a reader asks in: whether a body is a message first, then whether it was served without a credential, so a
  body that is not a message answers false from `OWMessage.has_unseen_recipients` whatever the key. Its fixture gains
  that case, `keyless-non-message-is-not-unseen` (103 in all), which `OWMessage` already answered; no reader changes.
  The report page names its readers of lines.
- Schema pin to `v0.34.1-dist.129` (`8796c07`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 129). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. The report page gains rule
  10, a line of a report's `consequences` read the same in every reader, and its second fixture,
  `profiles/report-lines.fixture.json` (101 cases and 16 texts), read from the vendored folder (the `### Added` entry
  for `read_line` builds it here).
- Schema pin to `v0.34.1-dist.128` (`7ffb61c`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 128). No schema
  file, `schema.json` or `views.json` moved; the generated files moved in their stamp only. A multi-link names each
  element once: a reader served a list that names one element twice reads it once, in its first place, on the lens,
  landing and message pages (the entries below build it here). The address page adds a find-all with a new kind of
  case, `prose-all`. The folder spec is at 0.3.24 (the vendored folder check's `FORMAT_VERSION`); this SDK stamps no
  `format_version`. The spine fixture's new case has no reader here. The fixtures' counts follow: address 218 (two
  `prose-all`), lens 235 (resolve 134, graph 56), message 102 (two `recipients`); landing's doubled-target case now
  wants one edge.
- `OWGraph.world_graph` reads each element of a list once (serial 128): a schema multi-link, `x_lens_leads_to` or
  `x_spine_depends_on` that names one target twice is one edge, in its first place, and a repeat to a target that is
  not a node is counted once in `edges_cut`. An edge's `index` is still its place in the list as served. Ids are
  compared as written. `OWLanding.landing_of` reads the graph it is given, so a doubled target is one edge there too.
  The lens fixture's case 143 and the new graph case pass.
- `OWMessage.recipients_of` answers each recipient once, and only for a message (serial 128): a `characters` list
  that names one Character twice gives that Character once, in its first place, ids compared as written; a body that
  is not a message (`OWMessage.is_message`: a Story, a Narrative with no supertype, a body with no pair) now has none,
  where before any body but a Note gave its list. The message fixture's two `recipients` cases run and pass.
- `OWMessage.is_addressed_to`, `is_to_everyone` and `has_unseen_recipients` answer only for a message (serial 128,
  the message page's own reader gating all four on the pair): a body that is not a message is addressed to nobody, is
  never to everyone, and has no unseen recipients, `false` keyless or not; before, any body but a Note was read as a
  message, so `unread_for` never counts one unread now either. A Note reads as before.
- Schema pin to `v0.34.1-dist.127` (`f50c526`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 127). No schema
  file or `schema.json` moved; the generated files moved in their stamp only, and `OWViewsTable` in its `views.json`
  sha256: the file's `banners` sentence now defers to the room page's presence rule with no paraphrase of its own, the
  reading this SDK already followed, and the views fixture's ten new cases of a row's own banner, on a table of the
  fixture's own, pass unchanged. The address page adds a start rule for an address found in prose (the entry below
  builds it here); its two cases with a letter above U+FFFF before the address carry `index_utf16` beside `index`,
  and this SDK reads `index`, since a Godot String counts code points. The map space page says what the layout mark
  means (a Map that is a drawing of its elements) and who writes it (rule 12): this SDK writes no `x_layout`, and the
  three new layout cases pass unchanged. The checks fixture's three presence cases and the spine fixture's one have no
  reader here. The fixtures' counts follow: address 216 (76 prose), views 56 (12 on a table of the fixture's own),
  map space 29 layout cases.
- Schema pin to `v0.34.1-dist.126` (`86e2ff4`); canonical 00.34.01 unchanged (`OWSchemaPin.SERIAL` 126). No schema
  file, `schema.json` or `views.json` moved, and the generated files moved in their stamp only. The room, charter,
  review and checks pages read a mark by one presence: null, a blank string, an empty list and an empty object are
  absent (the entry below builds it here). The map space page reads a link whose value is an empty string as no
  link, as an empty id is no id: this SDK already read every link and id so, and the fixture's seven new cases pass
  unchanged. The address page gains four prose cases, skipped here by kind as serial 123's are (no finder of an
  address in prose). The fixtures' counts follow: address 201 (61 prose), charter 41, map space 39 cases and 26
  layout cases (a second case names its Map by `map_index`), room 38.
- A room or charter mark that is an empty Array or an empty Dictionary is no mark (serial 126). `OWLens._has_mark`
  reads `x_room_of` and `x_charter_of` as the review mark was already read: null, a blank String, `[]` and `{}` are
  absent, since a compact reader leaves an empty list or object out and the same element must read the same in either
  served form. Everything that reads the two marks follows: `OWLens._is_room_element`, `OWLens.is_charter_element` and
  `OWCharter`, the lens and the graph, the openers' marks, `OWReport`, the views' row match and a row's own banner
  (`{}` is no banner, as the TypeScript SDK's `carries` reads it through `hasMark`). `OWLens.is_proposed` reads the
  review mark through the same `_has_mark`, its own empty check folded into it (no reading moves there). A list or object with something in it,
  a number and `false` are still marks. The room fixture's `mark-empty-list` and `mark-empty-object` and the charter
  fixture's two empty-mark cases pass.
- Schema pin to `v0.34.1-dist.124` (`094107b`); the standard moves to canonical 00.34.01 (`OWSchemaPin.CANONICAL`
  is now `"00.34.01"`, `SERIAL` 124), the first canonical move since serial 103. One description moved and no field:
  Map's `hierarchy` orders the maps that stand side by side (floors, decks, layers), the maps with the same
  `parent_map`, without one the maps of the same `location`, without either the maps of the world itself; lower is
  deeper or earlier, and nesting is said by `parent_map` and `location`, not by the number (`OWMap.hierarchy`'s doc
  comment follows). No fixture, `views.json` or walk reader moved, and the other generated files moved in their stamp
  only. No reader in this SDK changes.
- An element held in upper case answers no rows, not a refusal. `OWOpeners.openers_for` with an options `element`
  whose own `id` is the address's id in upper case (the address's id is read in either case and taken in lowercase,
  the element's is read as written) now answers ok with no rows, the site's own row included: no address can name
  such an element, so no door opens it, and it is no caller's mistake. The empty answer comes only after every other
  check has run, so a tools row that is not one is still refused beside it. An id that differs by more than case is
  still refused ("its id differs"). The shared openers fixture is re-vendored at 111 cases (sha256 `8af6f6da…`, the
  TypeScript SDK 4.161.0 and the Python package 0.122.0): its case `skips-id-case-held-upper` wants no rows.
- One time grammar: a record's `played_at` is now read by the message page's grammar, `OWLens.time_key`, the one the
  message and lens readers already call, where `OWRecord` had a grammar of its own. `OWRecord.record_mark_of` and
  `records_of` therefore now read a lowercase `t` and `z` (`2026-11-01t00:30:00z`) and an offset
  (`2026-11-01T00:30:00+01:00`, ordered as its instant) as a mark, and no longer read a time without seconds
  (`2026-11-01T00:30Z`) as one. The message grammar's other two readings come with it: a time with no zone is read as
  UTC, and the year 0000 is a year. `played_at` is still kept as written, and the order is still to the millisecond
  (a fraction truncated past three digits, before 1970 as after it), a tie by the Event's id. A writer that stamped
  `played_at` without seconds writes them now, or its records stop showing. This is the record page's reading at
  schema-dist serial 123.
- The lens clock is the newest of an element's three readable stamps: `updated_at`, `server_updated_at` and
  `local_updated_at`, whichever read as a time, decided element by element. `changed_within` and the order past the
  anchors (the entry below) both read it. Before, a folder element was read by the newer of its two folder stamps
  alone, and `updated_at` only when neither read. So a wire `updated_at` newer than both folder stamps now wins: such
  an element is no longer cut `stale` by `changed_within`, and is no longer sorted as old. An element with no readable
  clock is still never cut, and still sorts last of its type. This is the lens page's reading at schema-dist serial
  123.
- One clock per lens: `OWLens.resolve`'s order past the anchors (the lens page's rule 5, which the budget keeps the
  first of) now reads the same clock as `changed_within`, the element's clock (the entry above), where it read
  `updated_at` only. On the wire that is still `updated_at`. So an element edited locally yesterday sorts before one
  the server stamped last week, and an element `changed_within` keeps as fresh is never sorted as old in the same
  lens. An element with no readable clock still sorts last of its type, and a tie is still broken by id by code
  point. This is the lens page's reading at schema-dist serial 123.
- The message read mark's ties go to the higher id. `OWMessage.read_mark_of` now reads the message page's sentence:
  a lone mark is the mark; among several, the newest readable `updated_at` wins; one that cannot be read never beats
  one that can; among equal instants, or when none can be read, the higher id (code point, as written) is the mark.
  Two marks at the same instant (an instant written two ways, as `10:00:00Z` and `11:00:00+01:00`, included), and
  marks none of whose `updated_at` can be read (garbage, absent, null, a date alone), were decided by the first in
  list order. So the mark no longer depends on the order the Relations are listed in, and `OWLens`'s mail reader,
  which reads it, follows. This is the message page's reading at schema-dist serial 123, and the order `OWCharter`'s
  newest Charter already breaks its ties in.
- Schema pin to `v0.34.0-dist.123` (`6092c39`); the standard stays at 00.34.00, no schema file, `schema.json`,
  `views.json` or walk reader moved, and the generated files moved in their stamp only. The serial's readings are the
  four entries above. Cases gained: `record.fixture.json` five (46: lowercase `t` and `z` with seconds, an offset of
  one hour, half past without seconds, no zone, the leap day of the year 0000), and four of its cases rewritten to the
  one grammar (an offset written without its colon, `+0100`, is no mark; the leap day of 2028 and the half past of the
  instant-order case written with seconds; `fluffington-two-games` unchanged in its want, its offset Event now
  `+0100`): the four cases the record grammar entry above turned red against dist.122 read green here;
  `message.fixture.json` seven read-mark cases (100); `lens.fixture.json` twelve (233: the clock of three stamps, a
  clock that cannot be read, the mail window, a note keyed in upper case); `strand.fixture.json` one (27: a mark naming
  its story in upper case is no strand); `address.fixture.json` fifty-seven of a new kind, `prose`, an address found
  inside other text at an index (197); `checks.fixture.json` two rules and two cases, a `one_of` over a list (no
  reader here). Against this branch's readers every case of the five fixtures but the address page's `prose` kind
  reads as it stands; the `prose` kind asks for a finder this SDK does not have (the whole-string `OWAddress.parse_link`
  is unchanged, and still refuses `ow://<type>/<id>.` as a bad id). Each `prose` case that finds an address checks
  that the text holds it at the index and that `parse_link` reads it whole as the case's reading, then is skipped by
  name, counted in the suite's skips; the finder is not ported yet.
- A Charter's skill ids match an Object's own id as written. `OWCharter.charter_of` still finds an id in the Charter's
  text in either case and takes it in lowercase, but now matches it against the ids of the Objects the reader sees as
  they are written, where it lowercased those too. So an Object whose own id is held in upper case is not the Object a
  lowercase id in the text names, and is no longer kept; an id named in upper case in the text still names the Object
  held in lowercase, and a kept skill is always the Object's own id. This follows the address profile's rule for the
  same id: an id is read in either case only at an address and in a text, and what it is then matched against is read
  as written, as every other reader of this SDK already reads ids.
- The openers' check reads the given element's own id as written. `OWOpeners.openers_for` with an options `element`
  still reads the address's id in either case and takes it in lowercase, but now compares the element's own `id` to it
  as written, where it lowercased that too. An element held in upper case is not the element the address names,
  whatever the address's case, and is refused ("its id differs"); an element held in lowercase is the element of an
  address in either case. The same rule for the same id as the Charter's skill ids above. The shared openers fixture
  is re-vendored at 111 cases (sha256 `ac14435b…`): its old id-case case is now two, an element held in upper case
  under a lowercase address (refused) and a lowercase element under an upper-case address (the rows).
- `OWClient`'s writes follow the Unity and TypeScript SDKs on two rules. A write that became a proposal (a 202 with
  `{proposal}` to an upsert, a patch or a link edit) is now an `OWApiError` of kind `api`, `status` 202, its row in
  `proposal`, `is_proposed()` true, as the Unity SDK's `OWProposedError` is; the kind `proposed` and
  `OWApiError.PROPOSED` are gone, so the kinds are four. A caller that matched `OWApiError.PROPOSED` (or
  `"proposed"`) calls `error.is_proposed()` instead, before any branch on kind `api`, since a proposal is not a failure
  to retry; `error.proposal` is the same row. A 202 without a proposal row is still kind `answer`. And `patch` now
  sends a link array as given, where it refused one with nothing sent: the PATCH replaces the whole array, so a
  writer adding one id still uses `edit_links`, keel's merge. A caller that relied on the refusal to catch a link
  array in a partial now sees it written.
- `OWOpeners.openers_for` with `audience: "public"` (the signed-out reader) now gives a row for a tool whose
  `open.needs` is `account` (Atlas and Lantern today), its word the new `OWOpeners.NEEDS_AN_ACCOUNT`, "Needs an
  account", whatever `signed_in` says; the href stays in the row, and a menu draws it as one that opens nothing
  (disabled, still reachable). Before, the public saw no such row. A tool that needs the device is still not there for
  the public. The word comes after "You are here" and "Needs a connection", and before the sign-in, browser and phone
  words. Parity with the TypeScript SDK 4.130.0 and the Python package 0.105.0; the shared openers fixture
  re-vendored at 92 cases (from 90), every case by name green.
- Tests only: the shared openers fixture's 24 type refusals each name their kind beside the key: `unknown_key` (a key
  the object does not take, refused by name) or `bad_value` (a key it takes whose value it refuses, a missing one
  included). `test_openers.gd` tells the two apart by this package's own words ("unknown key 'k'"), so a reader that
  refuses a known key as unknown, or the other way round, now fails the case where before the name alone passed it.
  Still 92 cases, the same bytes as the TypeScript SDK's (`85ef7dd`) and the Python package's (`b1a4a45`); nothing
  shipped changes.
- `OWTools` repinned at the tools list's `60a590e` (tools.json sha256 `e9e8ad9d…`), the list the TypeScript SDK 4.132.1
  and the Python package 0.106.1 bake: Tactical Tangle opens a world or a Character. Its row gains a world door and an
  element door (`needs: "account"`, `element_types: ["character"]`, skipping room, hidden and proposed elements), so
  the Open with menu offers it on a world and on a Character, and on no other type. Atlas, Lantern and Little Lens
  each gain `element_types: null`, so nothing they offer changes.
- `OWTools` repinned at the tools list's `f10afdc` (tools.json sha256 `ff5e7c67…`), the list the TypeScript SDK 4.131.0
  bakes and the Python package pins: one new row, Tactical Tangle (`tangle`, listed, the API door only), with no
  `open`, so the Open with menu offers it nowhere. No other row changed.
- `OWMapSpace.map_space` reads serial 106's map space page: two rows of one type with one id read as the last one
  served, Markers and Pins as Maps and Zones already were, even when the last row reads less (an unplaced Marker, a
  Pin on a Map not served); a whole value past the 64-bit int reads as not whole, as the page's platform sentence
  says (before, a whole float past it was kept as written). The other new readings (a frame measured from placed
  points only, a non-whole `z` as 0, `no_markers` for a Zone with no placed Marker, a dangling Marker or a Pin with no
  served map counted once, `type` and `shape` read as written) were read so already. Parity with the TypeScript SDK
  4.129.1 and the Python package 0.104.1, which read serial 106 the same way.
- Folder format 0.3.22 (a draft world, one no host holds yet, conforms as any other folder; a writer adds no `world`
  to an element file and a reader gives one no meaning). **`OWWorld.write_folder` and `OWWorld.pack` now refuse a
  world they would write with no id**: a `world.json` whose `id` is not a non-empty String, or a new or edited
  element with no id. `write_folder` answers `ERR_INVALID_DATA` and writes nothing, `pack` answers a `Packed` that is
  not ok, and the new `OWWorld.write_refusal()` says why. Before, both wrote such a world (a 0-byte `world.json`, an
  element file named `…--.json`). A writer mints no id: the caller sets `info.id` (a draft world's id is the tool's
  own until a host gives one) and each element's. A file read with no id and not edited is carried back as read.
  **`OWElement.world` is read only**: setting it is refused with an error and changes nothing, so no model adds a
  `world` key to an element file (`codegen/generate.py`'s `READ_ONLY`). This SDK's writers stamp no
  `format_version`, so there is no version to move.
- **`OWClient.BulkSlot.id` is `Variant`: a String, or null when the slot answers none** (a failure before the item was
  identified), as the API document types it and the TypeScript and Unity SDKs read it; it read `""` before. A caller
  that typed it `String` reads it as a `Variant` now.
- Schema pin to `v0.34.0-dist.122` (`2888214`); the standard stays at 00.34.00, no schema file, `schema.json` or
  walk reader moved. The address page's new section, the same id: inside a world two ids are the same id when they
  are written the same, and an order by id is of the ids as written; an id is read in either case, and taken in
  lowercase, only at an address and in a text a page says is searched for ids (a Charter's `description`), and what
  it is then matched against is read as written. The Charter's skills and the openers' check now read a held id so
  (the two Changed entries above); the lens page's notes, the record page's seats and the report page's parents
  name it too, and this SDK's readers read those as written already. Cases gained: `address.fixture.json` three (140:
  an upper-case lens id is read, the key `Lens` is refused, a key with a space before it is another key),
  `charter.fixture.json` seven (38), `lens.fixture.json` one (221: an `updated_at` read as the message profile reads a
  `created_at`, an unreadable one last), `record.fixture.json` one (41), `report.fixture.json` two (29),
  `checks.fixture.json` two (no reader here). Against the code before the two Changed entries, one case's answer
  moves, `a-skill-object-whose-own-id-is-in-upper-case-is-not-kept`; every other case read as it stood. The baked
  views table moved in the conversation layout's sentence ("read and ordered as profiles/message.md orders
  messages") and the report row's `from`; the generated headers moved in their stamp only.
- Schema pin to `v0.34.0-dist.121` (`f890974`); the standard stays at 00.34.00, no schema file, `schema.json` or
  walk reader moved, and no answer of a reader moves. The message page gives the one form a `created_at` is read in
  (a time with no offset is UTC, every part in its range, a year any four digits, a fraction counted to its sixth
  digit) and `message.fixture.json` gains five `unread` cases (93). The report page's rule 9 says a parent that is no
  string is no parent, a padded one is read as written, one id given twice keeps the first, and reports that name each
  other in a ring are each grouped and linted; `report.fixture.json` gains seven thread cases (27). `OWMessage` and
  `OWReport.threads_of` answer every new case as they stood; the generated headers moved in their stamp only.
- Schema pin to `v0.34.0-dist.120` (`39d5163`); the standard stays at 00.34.00, no schema file, `schema.json` or
  walk reader moved, and no answer of a reader moves. The report page gains a `parent_narrative` row (the first
  report of the work a report continues, or the board entry a closed talk hangs on), a section on a report that
  continues earlier work, rule 9 (threads: a reader that groups reports groups them by `parent_narrative` as written,
  ordered by `created_at` as the message profile orders messages) and its first fixture, `report.fixture.json`. The
  views fixture's two cites of the report page move down one line with the new row (`description` 22, `consequences`
  24), as `test_views.gd` checks each quote at its line. The generated headers moved in their stamp only.
- Schema pin to `v0.34.0-dist.119` (`00369ea`); the standard stays at 00.34.00, no schema file, `schema.json` or
  walk reader moved, and no answer of a reader moves. The map-space page gains rule 11 (a layout map is no candidate
  when a tool picks the Map that stands for the world's space, and a Pin or a Marker on one is a place in that
  drawing, never in the world) and its reading H says a row's id is a non-empty string, as `OWMapSpace` already read
  it. The fixture gains one map-space case (a layout map read as any Map, 35 in all) and two layout cases (a layout
  Map and its ground, neither with a `parent_map`, 23 in all), each answered by `map_space` and `layout_of` as before;
  the test asserts both counts and names the new cases, and a new test holds a Map row whose `id` is `""` as no layout
  map. The distribution's folder lint knows folder format 0.3.22 and gains no check. The generated headers moved in
  their stamp only.
- Schema pin to `v0.34.0-dist.118` (`cf708c8`); the standard stays at 00.34.00, no schema file or walk moved,
  `views.json` is still version 3, and no answer of a reader moves. The views table's sentence rule ends by saying a
  tool that shows names only need show no sentence, and its `conversation` layout by saying a tool that shows one
  element and no thread draws it as a document and asks nothing of the layout; the layout is the one string
  `OWViews` bakes of the two (`_meta` is not baked), so the views table moved in that string, its stamp and its
  sha256, by `codegen/generate.py`. The checks fixture gains two room-mark rules (an extension key as the field) with
  eight cases, and the checks page names the White_Space set `present` trims; this SDK has no checks reader. The
  room page says a sitting's own mark holds the world's id and a sitting's winning spec is named in its `x_star`;
  the room fixture's pairs and cases are the same, so `OWLens` is unchanged. The other generated headers moved in
  their stamp only.
- Schema pin to `v0.34.0-dist.117` (`8f16a18`); the standard stays at 00.34.00, no schema file or walk moved, and
  `views.json` is still version 3. The views table's description says a tool's own words for a heading or a fold are
  its drawing, and a fold's label the word a tool uses where it has none of its own; `OWViews`' header quotes it.
  `_meta` is not baked, so the views table moved in its stamp and sha256 only. The views fixture gains a 46th case, a
  Pin whose generic link has one key holding and the other White_Space alone, which holds nothing: `OWViews.view_of`
  already read it so, and the fixture's count test now holds 46. Only the generated headers and the views table's
  stamp moved.
- Schema pin to `v0.34.0-dist.116` (`51a2496`); the standard stays at 00.34.00, no schema file, fixture or walk moved.
  The review page says who a mark's `by` names: the writer's own word, a claim, read as stored and never trimmed
  (White_Space alone, or a value that is not a String, names nobody), shown as the mark's word and in a name's place
  only where the platform resolves it. This SDK reads the review marks by presence and reads no mark's `by`, so no
  reader moved. The review cases follow the TypeScript SDK 4.155.0 (one row renamed, two added, 31 in all; every
  answer here is presence and unchanged). Only the generated headers and the views table's stamp moved.
- Schema pin to `v0.34.0-dist.115` (`9652e1b`); the standard stays at 00.34.00, no schema file moved. A lens's
  `first_line` row now carries as `description` the first line, the description split at every carriage return and
  every line feed (no other character breaks a line), that holds something after trimming White_Space, as stored with
  its own spaces; a description with no such line, or one that is not a String, gives no `description`. Before, the
  row carried everything up to the first line break, so a description opening with a line break gave `""` and one of
  White_Space alone was carried. The lens fixture's ten new cases pass (220 in all). `views.json` is version 3 (a
  generic link, a Pin's `element`, is one field of the drawing order, read by its two keys) with a fixture of 45
  cases, read by `OWViews` (Added). The charter page's empty mark (settled) and a Domain's sentence (trimmed, cut at
  the first line break, trimmed again) are how `OWCharter` already read them; the charter fixture's four new cases
  pass (31 in all). The report page's keeper report in one write and its reporter by `created_by`, the packet page's
  optional producer `version`, and the folder lint's review warnings bind readers this SDK has none of. No package
  had published a reader of the lens or views rule at this serial: both are built to the profiles' words and the
  fixtures. Only the generated headers and the views table moved beside the code.
- Schema pin to `v0.34.0-dist.114` (`428227a`); the standard stays at 00.34.00, no schema file moved. A lens's short
  rows (`show` `first_line` or `name`) now carry `supertype` and `subtype`, each only where the body the reader is
  served holds it as a String with something left after trimming White_Space, as stored (never trimmed): `OWLens`'s
  rows do, and the lens fixture's nine new cases pass (210 in all). Parity with the TypeScript SDK 4.151.0. The review
  page's new rule 5 (an object holding a key is a mark, whatever its keys) is how `OWLens.is_proposed` already read
  it; npm's two vectors join the review cases. The report page's rule 8 (a `consequences` line may stand for a change
  made to many, with no address) binds a reader of report lines, which this SDK has none of. `views.json` is version
  2 (the order a page draws its fields in) with a fixture of 41 cases; both vendored, and read by `OWViews` (Added). The
  lens page's `lenses_from` gains `none`, which the client's roster and `/me` answers hand on as served. Only the
  generated headers moved.
- Schema pin to `v0.34.0-dist.113` (`e3e2499`); the standard stays at 00.34.00, no schema file moved. The serial adds
  two presentation files at the distribution's root, `views.json` (how a report, a charter, a message and a line in a
  room are shown: the one sentence, what leads, what folds, the layout, the marks at a page's head) and its fixture,
  `views.fixture.json`. This SDK vendors both; `OWViews` reads them since version 2 (Added). The room
  page now says the order of its pairs carries no meaning (no pair or case moved; the tests still hold the fixture's
  order, which is stricter than the page), and two texts changed in words only (the report page's example, one
  checks fixture case's description). Only the generated headers moved.
- Schema pin to `v0.34.0-dist.112` (`04ce83d`); the standard stays at 00.34.00, no schema file moved. A report is a
  room element: `OWLens.ROOM_PAIRS` holds the room profile's tenth pair, `narrative/report`, third in the fixture's
  order, so the lens's room rule leaves a Narrative with supertype `Report` and `x_room_of` out of a lore view and a
  lens's `types` may name it; without the mark it stays lore. The room fixture's three new cases pass (35 in all) and
  the lens fixture's `room_pairs` is held to the pairs in the new order. The new report profile's key
  `x_report_answers` and the packet profile's new optional `x_packet_for` have no reader here (none in the TypeScript
  SDK or the Python package either); `lenses_in_use`'s `membership` is null only for a folder world, as the lens page
  now says, its behaviour unchanged. Only the generated headers moved.
- Schema pin to `v0.34.0-dist.111` (`bfc90b4`); the standard stays at 00.34.00, no schema file moved. Four more
  `layout_cases` (twenty-one: code point order, a repeated Pin id, a Pin row and a Map row without a string id), the
  page's sentence that a Map row without a string id is no Map, and a case that names the Map it reads by `map_index`
  (positions in its elements) when the row has no id; the replay reads every row a case names. `layout_of` needed no
  change. Only the generated headers moved.
- Schema pin to `v0.34.0-dist.110` (`533a581`); the standard stays at 00.34.00, no schema file moved. The map space
  profile gains its layout keys, rules 8 to 10 (`x_layout` on a Map, its ground, `x_hand` on a Pin), and a second,
  small reading of one Map, with seventeen `layout_cases` beside the fixture's `cases`, which keep their 34 entries
  unchanged. Only the generated headers moved.
- Schema pin to `v0.34.0-dist.109` (`bc30626`); the standard stays at 00.34.00. The calendar profile's refusal list now
  says an era's `year_base` is refused when it is "present and not 0 or 1", as its field table always did, and its
  fixture gains `refuse-year-base-five` (77 cases, 43 refusals). `OWCalendar.read_value` refused it already; no reader
  change. The generated headers moved and the calendar parity vectors were regenerated from the TypeScript SDK
  4.133.2, which reads the new case the same way.
- Schema pin to `v0.34.0-dist.108` (`c618b9d`); the standard stays at 00.34.00, descriptions only (canonical PR 20): no
  field, type, link, fixture or reader change. Seventeen time-field descriptions on thirteen types say one thing, "in
  the world's time unit (World `time_basic_unit`)"; `Event.constructs` reads "concepts, systems or built entities";
  `Map.hierarchy` reads "an integer to order or group the maps that share a parent; how a tool reads it is the tool's
  own". The generated models' doc comments for those 19 fields and the generated headers moved; nothing else did.
- Schema pin to `v0.34.0-dist.107` (`1d774b9`); the standard stays at 00.34.00, no model, fixture or reader change. The
  serial changes two profile pages' prose: the charter page names a reader's `open` as the World's `public_read`, the
  standard's field on world.yaml, and the map space page dates its exact-range sentence. Only the generated headers
  and `OWSchemaPin` moved. `OWCharter.charter_of` and `domains_of` now say in their doc comments that the world's
  `open` key is `OWWorldInfo.public_read`, read from a folder's `world.json` or the world GET.
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
