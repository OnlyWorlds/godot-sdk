# Changelog

Notable changes to the OnlyWorlds SDK for Godot. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Nothing is released yet; the history before this file is in
the git log.

## [Unreleased]

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
