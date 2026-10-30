# Changelog

Notable changes to the OnlyWorlds SDK for Godot. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing is released yet; the history before this file is in
the git log.

## [Unreleased]

### Changed

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

- `OWStrand.strand_of(world, reader)`: the strand profile's reader (schema-dist `profiles/strand.md`, serial 98), a
  world's strand as one reader sees it through the lens reader's own view (`OWLens.View`): the story the World's
  `x_strand` names, one of its events, that event's place, the story's `protagonist`, where the hero is now, and
  whether then and now are one place by id (`{narrative, event, location, character, now, same}`, each slot
  `{id, name}` or null). A slot holds only its own kind, no slot is filled from another, a list's order is never read,
  and a story the reader knows only as a stub fills its own slot alone. A mark that is not a Dictionary of three
  Strings is no mark; a member that is an empty string is an empty slot (the page's words; the npm and Python readers
  read it as no mark). Every case of the profile's fixture (17), held by its sha256.
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
