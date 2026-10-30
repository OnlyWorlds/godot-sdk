# Changelog

Notable changes to the OnlyWorlds SDK for Godot. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing is released yet; the history before this file is in
the git log.

## [Unreleased]

### Changed

- `OWLens.resolve` (and `OWGraph.world_graph` with a lens) follows the lens profile owner's rulings on readings no
  fixture case decided yet, ahead of the fixture's next serial, which carries a case for each: a link reaches only an
  element of its field's target type, and a generic pair (a Pin's `element_type`/`element_id`) only when its type key
  names one of the 22 (rulings 1, 2); an anchor id no element of its field's type holds is counted for the owner as
  `anchor_not_visible`, never skipped (3); an umbrella's hop keeps a child lens it reaches as an element before it is
  entered (4); a lens id a child cut before it was entered stays counted in the cut (5); a known-of stub keeps the base
  fields (`change_seq` too) and its type's public fields, a public link as the reader is served it, every other field
  at its unset value and no extension key (7); the mail part orders two messages with one `created_at` by id (11). A
  whole float in an `x_lens` key already read whole, as ruling 13 now says for every reader. Each change is held by a
  test named for its ruling.

### Added

- `OWOpeners.openers_for(tools, kind, address, surface)`: the rows of an "Open with" menu for a world (`"world"`) or
  one of its elements (`"element"`), a port of the npm SDK's `openersFor` and the Python package's `openers_for`. The
  site's page comes first, then each listed tool with a link for that kind, in the list's order, each a Dictionary
  `{id, name, href, state}` (the row's word in sentence case, or null). The address is a Dictionary of the parts or an
  `OWAddress.Reading`; the surface a Dictionary (`audience` required, `signed_in`, `browser`, `phone`, `tool`). The
  answer is an `OWOpeners.Result`: `rows` when `ok`; else `reason`, the address profile's refusal, or `reason` "" and
  a `message` naming the key. The whole address is checked by the writer, so a malformed form, lens or moment refuses
  (`bad_form`, `bad_lens`, `bad_moment`), as the npm SDK 4.110.0 and the Python package 0.91.0 do. Tested by the
  packages' shared fixture (45 cases, held by its sha256).
- `OWTools.ALL`: the OnlyWorlds tools list (github.com/OnlyWorlds/tools, `tools.json` format 1) baked in at commit
  `86208c8`, the keys `openers_for` reads. The list is vendored at `codegen/tools/tools.json` and pinned in
  `codegen/tools-pin.json`; `codegen/generate_tools.py` writes `addons/onlyworlds/ow_tools.gd` and `--check` fails
  when the two disagree. A tool listed after a release is offered from the next one.
