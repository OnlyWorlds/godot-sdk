#!/usr/bin/env python3
"""The GDScript emitter: the pinned schema-dist into typed models, the pin, and the Unicode tables.

    python codegen/generate.py            # verify the vendored dist against the pin, then write every output
    python codegen/generate.py --check    # verify, then exit 1 if any output would change (the drift guard)

Standard library only. What it reads and writes:

  codegen/PIN                      the pin: the dist's tag and the sha256 of its MANIFEST.json (a tag can move; a
                                   manifest hash recorded on our side makes a moved tag visible)
  codegen/schema-dist/             the dist at that tag, verbatim (`git archive <tag>`); never edited
  -> addons/onlyworlds/ow_element.gd              the base fields every element has (schema.json `base`)
  -> addons/onlyworlds/models/ow_<type>.gd        one class_name OW<Type> per element type (schema.json `types`)
  -> addons/onlyworlds/ow_world_info.gd           world.json's fields (schema.json `world`)
  -> addons/onlyworlds/ow_types.gd                the registry: type slug -> model script
  -> addons/onlyworlds/ow_schema_pin.gd           the pin, for the runtime's own check
  -> addons/onlyworlds/ow_presentation.gd         each type's default family and icon (presentation.json `types`);
                                                  codegen/ is not exported with a game, so the runtime reads this
  -> addons/onlyworlds/ow_views_table.gd          views.json's banners, layouts and rows, and each type's section
                                                  fields in the walk's order, for OWViews; the file is checked first
                                                  (check_views) and refused whole when it fails
  -> addons/onlyworlds/unicode/ow_unicode_data.gd NFC data and the C+S case folds (OW-18), and the letters and
                                                  combining marks an address in prose is cut by, as GDScript constants
  -> tests/data/unicode_vectors.txt               what Python says NFC and the fold give, for the tests

The schema source is `schema.json`, the walk's own output (schema-dist README: "plain JSON, so any language or engine
reads it without Python or a YAML parser"), so this emitter decodes nothing itself: the walk stays the one decoder.

The NFC tables come from Python's `unicodedata`, asserted to be Unicode 15.1.0, the version of the CaseFolding file
the fixture set pins. The source is one function (`nfc_tables_from_unicodedata`); if schema-dist publishes NFC data,
a second function reading that file replaces it and the emitted file keeps its shape.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
import unicodedata
from pathlib import Path

CODEGEN = Path(__file__).resolve().parent
ROOT = CODEGEN.parent
DIST = CODEGEN / "schema-dist"
PIN = CODEGEN / "PIN"
ADDON = ROOT / "addons" / "onlyworlds"
UNICODE_VERSION = "15.1.0"
CASEFOLDING = DIST / "fixtures" / "owworld" / f"CaseFolding-{UNICODE_VERSION}.txt"

KIND_VIEW = {  # kind -> (GDScript type, getter, setter)
    "scalar_str": ("String", "_str", "_set_str"),
    "scalar_int": ("Variant", "_int", "_set_int"),   # int or null: GDScript has no nullable int
    "scalar_bool": ("bool", "_bool", "_set_bool"),
    "single": ("String", "_id", "_set_id"),
    "multi": ("PackedStringArray", "_ids", "_set_ids"),
}

GD_RESERVED = {  # GDScript keywords a field name may not take as a property name
    "if", "elif", "else", "for", "while", "match", "break", "continue", "pass", "return", "class", "class_name",
    "extends", "is", "in", "as", "self", "signal", "func", "static", "const", "enum", "var", "breakpoint",
    "preload", "await", "yield", "assert", "void", "PI", "TAU", "INF", "NAN", "and", "or", "not", "super",
    "when", "trait", "namespace",
}


# -- the pin --------------------------------------------------------------------------------------------------------

def read_pin() -> dict:
    pin = {}
    for line in PIN.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            k, v = line.split(":", 1)
            pin[k.strip()] = v.strip()
    return pin


def verify_dist(pin: dict) -> list[str]:
    """The vendored tree is what the pin says: its manifest hashes to the pinned sha256, every file it lists hashes to
    its entry, and nothing else is in the tree. Returns the problems found."""
    problems = []
    manifest_bytes = (DIST / "MANIFEST.json").read_bytes()
    got = hashlib.sha256(manifest_bytes).hexdigest()
    if got != pin["manifest_sha256"]:
        problems.append(f"MANIFEST.json hashes to {got}, the pin says {pin['manifest_sha256']}")
    files = json.loads(manifest_bytes.decode("utf-8"))["files"]
    for rel, sha in files.items():
        p = DIST / rel
        if not p.is_file():
            problems.append(f"the manifest lists {rel}, which is not vendored")
        elif hashlib.sha256(p.read_bytes()).hexdigest() != sha:
            problems.append(f"{rel} does not match its manifest entry")
    for p in DIST.rglob("*"):
        rel = p.relative_to(DIST).as_posix()
        if p.is_file() and rel != "MANIFEST.json" and rel not in files:
            problems.append(f"untracked file inside the vendored dist: {rel}")
    version = dict(l.split(": ", 1) for l in (DIST / "VERSION").read_text(encoding="utf-8").splitlines() if ": " in l)
    if f"dist.{int(version['serial'])}" not in pin["tag"]:
        problems.append(f"VERSION says serial {version['serial']}, the pin's tag is {pin['tag']}")
    return problems


# -- models ---------------------------------------------------------------------------------------------------------

def pascal(slug: str) -> str:
    return "".join(p.capitalize() for p in slug.split("_"))


def prop_name(field: str) -> str:
    return field + "_" if field in GD_RESERVED else field


def doc(desc: str | None) -> str:
    d = " ".join((desc or "").split())
    return d + "." if d and not d.endswith((".", "?", "!", ")")) else d


# Fields a model reads and never writes, and why. world: the folder format 0.3.22 rules that a writer adds no `world` to
# an element file and a reader gives one no meaning; the site serves none in an element's body, and a write strips it.
READ_ONLY = {"world": "a writer adds no world to an element (folder format 0.3.22)"}


def emit_fields(fields: list[dict]) -> list[str]:
    out, section = [], None
    for f in fields:
        if f.get("section") != section:
            section = f.get("section")
            if section:
                out += [f"# -- {section} " + "-" * max(4, 100 - len(section)), ""]
        d = doc(f.get("desc"))
        if f["kind"] == "generic":
            out.append(f"## {d} The type's slug, with [member {f['id_key']}].")
            out += [f"var {f['type_key']}: String:", f'\tget: return _str("{f["type_key"]}")',
                    f'\tset(v): _set_id("{f["type_key"]}", v)']
            out.append(f"## {d} The element's id, with [member {f['type_key']}].")
            out += [f"var {f['id_key']}: String:", f'\tget: return _id("{f["id_key"]}")',
                    f'\tset(v): _set_id("{f["id_key"]}", v)', ""]
            continue
        if f["kind"] == "list":
            gd_type, get, set_ = ("Array", "_list", "_set_list")
        else:
            gd_type, get, set_ = KIND_VIEW[f["kind"]]
        target = f" Links to [code]{f['target']}[/code]." if f.get("target") else ""
        out.append(f"## {d}{target}" if d or target else f"## [code]{f['name']}[/code].")
        if f["name"] in READ_ONLY:
            out += [f"## Read only: {READ_ONLY[f['name']]}; setting it is refused and changes nothing.",
                    f"var {prop_name(f['name'])}: {gd_type}:", f'\tget: return {get}("{f["name"]}")',
                    f'\tset(_v): push_error("OnlyWorlds: {f["name"]} is read only: {READ_ONLY[f["name"]]}")', ""]
            continue
        out += [f"var {prop_name(f['name'])}: {gd_type}:", f'\tget: return {get}("{f["name"]}")',
                f'\tset(v): {set_}("{f["name"]}", v)', ""]
    return out


def field_table(fields: list[dict], const: str = "FIELDS") -> list[str]:
    out = ["## Field name -> [kind, link target] in the schema's order (a generic link's two keys: kind \"generic\").",
           f"const {const} := {{"]
    for f in fields:
        if f["kind"] == "generic":
            out.append(f'\t"{f["type_key"]}": ["generic", ""],')
            out.append(f'\t"{f["id_key"]}": ["generic", ""],')
        else:
            out.append(f'\t"{f["name"]}": ["{f["kind"]}", "{f.get("target", f.get("items", ""))}"],')
    return out + ["}", ""]


def header(head: str) -> list[str]:
    return [f"# GENERATED by codegen/generate.py from schema-dist {head}. Do not edit: regenerate."]


def emit_base(schema: dict, head: str) -> str:
    out = header(head) + [
        "class_name OWElement",
        "extends OWElementCore",
        "## The fields every element has (schema-dist [code]base[/code]); each type's model extends this.",
        "",
    ] + field_table(schema["base"], "BASE_FIELDS") + emit_fields(schema["base"])
    return "\n".join(out).rstrip("\n") + "\n"


def emit_model(slug: str, fields: list[dict], head: str) -> str:
    cls = "OW" + pascal(slug)
    out = header(head) + [
        f"class_name {cls}",
        "extends OWElement",
        f"## The [code]{slug}[/code] element type: its own fields, beside [OWElement]'s base fields.",
        "",
        f'const TYPE := &"{slug}"',
        "",
    ] + field_table(fields) + [
        "func get_type() -> StringName:",
        "\treturn TYPE",
        "",
    ] + emit_fields(fields)
    return "\n".join(out).rstrip("\n") + "\n"


def emit_world_info(schema: dict, head: str) -> str:
    out = header(head) + [
        "class_name OWWorldInfo",
        "extends OWElementCore",
        "## world.json's fields (schema-dist [code]world[/code]), typed views onto the parsed file.",
        "",
    ] + field_table(schema["world"]) + emit_fields(schema["world"])
    return "\n".join(out).rstrip("\n") + "\n"


def emit_registry(schema: dict, head: str) -> str:
    out = header(head) + [
        "class_name OWTypes",
        "extends RefCounted",
        "## The registry: each element type's slug -> its model script, in the schema's order.",
        "",
        "const SCRIPTS := {",
    ]
    for slug in schema["types"]:
        out.append(f'\t"{slug}": preload("res://addons/onlyworlds/models/ow_{slug}.gd"),')
    out += [
        "}",
        "",
        "## The 22 slugs, in the schema's order.",
        "static func slugs() -> PackedStringArray:",
        "\treturn PackedStringArray(SCRIPTS.keys())",
        "",
        "## A model for [param data]: the type's own class, or a plain [OWElement] for a type that is not one of the 22",
        "## (its data still kept whole and written back as read).",
        "static func make(type: String, data: Dictionary) -> OWElement:",
        "\tvar script = SCRIPTS.get(type)",
        "\tif script != null:",
        "\t\treturn script.new(data)",
        "\tvar e := OWElement.new(data)",
        "\te._type = StringName(type)",
        "\treturn e",
    ]
    return "\n".join(out) + "\n"


def emit_pin(pin: dict, version: dict) -> str:
    return "\n".join([
        "# GENERATED by codegen/generate.py from codegen/PIN. Do not edit: regenerate.",
        "class_name OWSchemaPin",
        "extends RefCounted",
        "## The schema-dist this SDK's models were generated from: the tag, and the sha256 of its MANIFEST.json (a tag",
        "## can move; the manifest hash recorded here makes a moved tag visible).",
        "",
        f'const TAG := "{pin["tag"]}"',
        f'const MANIFEST_SHA256 := "{pin["manifest_sha256"]}"',
        f'const CANONICAL := "{version["canonical"]}"',
        f'const SERIAL := {int(version["serial"])}',
        f'const PUBLISHED := "{version["published"]}"',
        "",
    ])


def emit_presentation(presentation: dict, head: str) -> str:
    # serial 87 (lens.md nodes, presentation.json _meta.groups): a word not in colors.order fails loudly, naming the
    # word; a sidecar that brings one is refused here, before anything is written.
    order = presentation["colors"]["order"]
    for slug, t in presentation["types"].items():
        if t["family"] not in order:
            sys.exit(f"presentation.json: {slug}'s family {t['family']!r} is not in colors.order {order}")
    out = header(head) + [
        "class_name OWPresentation",
        "extends RefCounted",
        "## Each type's default family and icon: schema-dist presentation.json's [code]types[/code], the first-party",
        "## defaults (a tool may override them: [method use]). Colour is the tool's, so it is not here.",
        "",
        "## The colour words in their order (presentation.json [code]colors.order[/code]): a family is one of these.",
        "const ORDER := [" + ", ".join(f'"{w}"' for w in order) + "]",
        "",
        "## Type slug -> {family, icon}, in the sidecar's order.",
        "const TYPES := {",
    ]
    for slug, t in presentation["types"].items():
        out.append(f'\t"{slug}": {{"family": "{t["family"]}", "icon": "{t["icon"]}"}},')
    out += [
        "}",
        "",
        "static var _table: Dictionary = TYPES",
        "",
        "## The family of [param type] (the lens profile's graph node key).",
        "static func family_of(type: String) -> String:",
        '\treturn _table[type]["family"]',
        "",
        "## The icon of [param type] (a Material Symbols name).",
        "static func icon_of(type: String) -> String:",
        '\treturn _table[type]["icon"]',
        "",
        "## Read [param table] (the shape of [constant TYPES]) in place of the defaults, for a tool that overrides them.",
        "## A table whose family for some type is not one of [constant ORDER] is refused whole, naming the word, and the",
        "## table in use stays: returns that refusal (also pushed as an error), or \"\" when the table is taken.",
        "static func use(table: Dictionary) -> String:",
        "\tvar bad := refusal_of(table)",
        '\tif bad != "":',
        "\t\tpush_error(\"OnlyWorlds: \" + bad)",
        "\t\treturn bad",
        "\t_table = table",
        '\treturn ""',
        "",
        "## Back to the defaults.",
        "static func reset() -> void:",
        "\t_table = TYPES",
        "",
        "## Why [param table] cannot be read: the first type in the standard's order with no entry, or whose family is",
        "## not one of [constant ORDER], named with its word; \"\" when every type's family is one of them. Without a",
        "## table, the one in use (a table changed in place after [method use] took it).",
        "static func refusal_of(table: Variant = null) -> String:",
        "\tvar t: Dictionary = _table if table == null else table",
        "\tfor type in OWTypes.slugs():",
        "\t\tvar entry: Variant = t.get(type)",
        "\t\tif not (entry is Dictionary):",
        '\t\t\treturn "presentation: %s has no entry" % type',
        '\t\tif not ORDER.has(entry.get("family")):',
        '\t\t\treturn "presentation: %s\'s family %s is not one of %s" % [type, JSON.stringify(entry.get("family")),'
        ' ", ".join(ORDER)]',
        '\treturn ""',
        "",
    ]
    return "\n".join(out)


# -- views ----------------------------------------------------------------------------------------------------------

VIEWS_ROW_KEYS = {"id", "kind", "from", "sentence", "lead", "fold", "layout", "banner"}
VIEWS_PROFILES = ("room", "charter")


def views_refuse(msg: str) -> None:
    sys.exit(f"views.json: {msg}")


def check_views(doc, schema: dict, fixture: dict, dist: Path) -> None:
    """views.json is checked as the Unity SDK's codegen/generate_views.py checks it (628418d; itself the TypeScript
    SDK's load_views, 4.151.0), and nothing is written when it fails: version 3 only (serial 115: a generic link is one
    field of the drawing order, which changes a Pin's order for every reader of version 2; version 2, serial 114, stated
    the order, version 1 never did); each row's keys ones OWViews reads (a new column is a
    new meaning); a kind that is a type, a type with a supertype, or a profile's pair that profile's own reader matches
    (the room fixture's pairs for room, the lens fixture's reading aid pairs for charter); no two rows holding one kind
    (the file's `match`: "a file where two do is at fault, and is refused where it is built"); every field a row names
    a field of its type by the walk (schema.json, the base fields included); every layout one the file defines;
    distinct row ids; and views.fixture.json's cites (check_view_cites)."""
    meta = doc.get("_meta") if isinstance(doc, dict) else None
    if not isinstance(meta, dict) or meta.get("version") != 3:
        views_refuse(f"`_meta.version` is {meta.get('version') if isinstance(meta, dict) else meta!r}, expected 3")
    if set(doc) != {"_meta", "banners", "layouts", "rows"}:
        views_refuse(f"the top-level keys are {sorted(doc)}, expected _meta, banners, layouts, rows")
    banners, layouts, rows = doc["banners"], doc["layouts"], doc["rows"]
    if (not isinstance(banners, list)
            or not all(isinstance(b, dict) and set(b) == {"mark", "defined_by"}
                       and isinstance(b["mark"], str) and isinstance(b["defined_by"], str) for b in banners)
            or len({b["mark"] for b in banners}) != len(banners)):
        views_refuse("`banners` must be a list of distinct {mark, defined_by}")
    if not isinstance(layouts, dict) or not layouts or not all(isinstance(v, str) for v in layouts.values()):
        views_refuse("`layouts` must be an object of layout names to their sentences")
    if not isinstance(rows, list) or not rows:
        views_refuse("`rows` must be a non-empty list")

    base = {f["name"] for f in schema["base"]} - {"id", "world"}
    fields = {slug: {f["name"] for f in fs} | base for slug, fs in schema["types"].items()}

    def fold(s: str) -> str:
        return s.strip().lower()  # the pairs are ASCII, checked against the profiles' own lists

    room = {(fold(p["type"]), fold(p["supertype"]))
            for p in json.loads((dist / "profiles" / "room.fixture.json").read_text(encoding="utf-8"))["pairs"]}
    charter = {tuple(fold(x) for x in w.split("/")) for w in json.loads(
        (dist / "profiles" / "lens.fixture.json").read_text(encoding="utf-8"))["reading_aid_pairs"]}

    ids: set[str] = set()
    kinds: set[tuple] = set()
    for row in rows:
        rid = row.get("id") if isinstance(row, dict) else None
        if not isinstance(rid, str) or not rid or rid in ids:
            views_refuse(f"a row's id is {rid!r}: each row needs its own non-empty id")
        ids.add(rid)
        stray = sorted(set(row) - VIEWS_ROW_KEYS)
        if stray:
            views_refuse(f"row {rid} carries {stray}, which OWViews does not read: a new column is a new meaning, "
                         "read it in OWViews first, then here")
        kind = row.get("kind")
        if isinstance(kind, dict) and set(kind) == {"profile", "pair"}:
            prof, pair = kind["profile"], kind["pair"]
            parts = pair.split("/") if isinstance(pair, str) else []
            if prof not in VIEWS_PROFILES or len(parts) != 2:
                views_refuse(f"row {rid}'s kind {kind!r} names a profile outside {VIEWS_PROFILES} or a pair not "
                             "`type/Supertype`")
            if (fold(parts[0]), fold(parts[1])) not in (room if prof == "room" else charter):
                views_refuse(f"row {rid}'s pair {pair!r} is not one the {prof} profile's reader matches")
            slug = parts[0]
            key = ("profile", prof, fold(pair))
        elif (isinstance(kind, dict) and set(kind) in ({"type"}, {"type", "supertype"})
              and all(isinstance(v, str) for v in kind.values())):
            slug = kind["type"]
            key = ("type", fold(kind["type"]), fold(kind.get("supertype", "\0")))
        else:
            views_refuse(f"row {rid}'s kind {kind!r} is neither a type, a type with a supertype, nor a profile's pair")
        if slug not in fields:
            views_refuse(f"row {rid} names the type {slug!r}, not one of the 22 slugs as written")
        if key in kinds:
            views_refuse(f"row {rid} holds a kind another row holds; the file's `match` says no two rows do")
        kinds.add(key)

        def names(k: str) -> list[str]:
            v = row.get(k, [])
            if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
                views_refuse(f"row {rid}'s `{k}` is {v!r}, expected a list of field names")
            return v

        named = names("sentence") + names("lead")
        folds = row.get("fold", [])
        if not isinstance(folds, list) or not all(isinstance(f, dict) and set(f) == {"field", "label"}
                                                 and isinstance(f["field"], str) and isinstance(f["label"], str)
                                                 for f in folds):
            views_refuse(f"row {rid}'s `fold` is {folds!r}, expected a list of {{field, label}}")
        named += [f["field"] for f in folds]
        layout = row.get("layout")
        if not isinstance(layout, dict) or layout.get("name") not in layouts or not set(layout) <= {"name", "by"}:
            views_refuse(f"row {rid}'s layout {layout!r} is not {{name, by?}} with a name the file defines")
        if "by" in layout:
            if not isinstance(layout["by"], str):
                views_refuse(f"row {rid}'s layout.by is {layout['by']!r}, expected a field name")
            named.append(layout["by"])
        unknown = sorted({n for n in named if n not in fields[slug]})
        if unknown:
            views_refuse(f"row {rid} names {unknown}, which {slug} does not have by the walk")
        banner = row.get("banner", [])
        if not isinstance(banner, list) or not all(isinstance(b, str) and b for b in banner):
            views_refuse(f"row {rid}'s `banner` is {banner!r}, expected a list of mark names")
        if not isinstance(row.get("from"), str):
            views_refuse(f"row {rid}'s `from` is {row.get('from')!r}, expected the page that defines the kind")
    check_view_cites(rows, fixture, dist)


def check_view_cites(rows: list, fixture: dict, dist: Path) -> None:
    """views.fixture.json's cites (its third note): every field a row names (sentence, lead, fold, layout.by) is
    quoted from the page that defines the kind, at its line. Each quote is checked at its line of the vendored page
    (the page split at LF, the line 1-based), each cite names a field its row names, and each field a row names has a
    cite. As the Unity SDK's generate_views.py check_cites."""
    named: set[tuple[str, str]] = set()
    for row in rows:
        for f in row.get("sentence", []) + row.get("lead", []) + [x["field"] for x in row.get("fold", [])]:
            named.add((row["id"], f))
        if "by" in row["layout"]:
            named.add((row["id"], row["layout"]["by"]))
    cited: set[tuple[str, str]] = set()
    for c in fixture.get("cites", []):
        where = f"the cite of {c.get('row')}.{c.get('field')} ({c.get('page')}:{c.get('line')})"
        if (c.get("row"), c.get("field")) not in named:
            views_refuse(f"{where} names a field its row does not name")
        page = dist / c["page"]
        if not page.is_file():
            views_refuse(f"{where}: the page is not in the vendored dist")
        lines = page.read_bytes().decode("utf-8").split("\n")
        if not (isinstance(c["line"], int) and 1 <= c["line"] <= len(lines) and c["quote"] in lines[c["line"] - 1]):
            views_refuse(f"{where}: the quote is not at that line of the page")
        cited.add((c["row"], c["field"]))
    if named - cited:
        views_refuse(f"fields a row names with no cite in views.fixture.json: {sorted(named - cited)}")


def gd_literal(value) -> str:
    """A JSON value as a GDScript constant expression: JSON's own text is one, for objects, arrays, strings, null and
    booleans (no number appears in views.json); ASCII only, so every escape is one GDScript reads (\\uXXXX)."""
    if any(ord(c) > 0xFFFF for c in json.dumps(value, ensure_ascii=False)):
        views_refuse("a character outside the Basic Multilingual Plane, which this emitter does not write")
    return json.dumps(value, ensure_ascii=True)


def emit_views(doc: dict, sha: str, schema: dict, head: str) -> str:
    """The table OWViews reads: views.json's banners, layouts and rows as the file writes them (`_meta` is not baked:
    its sentences are the file's rules, which OWViews reads in code), and each type's section fields in the walk's
    order, as the Unity SDK bakes OWViews.SectionFields and the TypeScript SDK its ELEMENT_SECTIONS."""
    out = header(head) + [
        "extends RefCounted",
        "## views.json as baked at this pin, read by [OWViews] (which names these as its own constants). Data, not code.",
        "",
        "## views.json's format, [code]_meta.version[/code].",
        f"const VERSION := {int(doc['_meta']['version'])}",
        "## sha256 of the views.json these rows were baked from, as the pinned MANIFEST.json lists it.",
        f'const SHA256 := "{sha}"',
        "",
        "## The marks every page shows at its head, in the file's order, each {mark, defined_by}.",
        "const BANNERS := [",
    ]
    out += [f"\t{gd_literal(b)}," for b in doc["banners"]]
    out += ["]", "", "## The layouts the file defines, by name, each with its sentence.", "const LAYOUTS := {"]
    out += [f"\t{gd_literal(name)}: {gd_literal(sentence)}," for name, sentence in doc["layouts"].items()]
    out += ["}", "", "## The rows, in the file's order, each as the file writes it.", "const ROWS := ["]
    out += [f"\t{gd_literal(r)}," for r in doc["rows"]]
    out += [
        "]",
        "",
        "## Each type's section fields in the schema's own order (schema/<type>.yaml: its sections as listed, each",
        "## section's fields as listed), as the walk lists them; the base fields are in no section. A generic link is",
        "## its one name ([code]element[/code] on a Pin), as the walk lists it.",
        "const SECTION_FIELDS := {",
    ]
    out += [f"\t{gd_literal(slug)}: {gd_literal([f['name'] for f in fs])}," for slug, fs in schema["types"].items()]
    out += [
        "}",
        "",
        "## Each type's generic links and the two keys a served body carries for each, [code][type_key, id_key][/code],",
        "## from the walk. The document layout draws a generic link as one field at its place, holding something only",
        "## when both keys do (views.json version 3).",
        "const GENERIC_LINKS := {",
    ]
    for slug, fs in schema["types"].items():
        links = {f["name"]: [f["type_key"], f["id_key"]] for f in fs if f["kind"] == "generic"}
        if any(not (isinstance(k, str) and k) for pair in links.values() for k in pair):
            views_refuse(f"{slug} has a generic link without both its keys in the walk")
        if links:
            out.append(f"\t{gd_literal(slug)}: {gd_literal(links)},")
    out += ["}", ""]
    return "\n".join(out)


def views_output(schema: dict, head: str) -> str:
    data = (DIST / "views.json").read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    doc = json.loads(data.decode("utf-8"))
    fixture = json.loads((DIST / "views.fixture.json").read_text(encoding="utf-8"))
    check_views(doc, schema, fixture, DIST)
    return emit_views(doc, sha, schema, head)


# -- Unicode --------------------------------------------------------------------------------------------------------

def simple_folds() -> dict[int, int]:
    """The C and S rows of the vendored CaseFolding file (OW-18: the file, never a runtime's casefold)."""
    folds = {}
    for line in CASEFOLDING.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        code, status, mapping = [p.strip() for p in line.split(";")[:3]]
        if status in ("C", "S"):
            folds[int(code, 16)] = int(mapping, 16)
    return folds


HANGUL_S0, HANGUL_COUNT = 0xAC00, 11172


UNICODE_DATA = DIST / "fixtures" / "owworld" / f"UnicodeData-{UNICODE_VERSION}.txt"
COMPOSITION_EXCLUSIONS = DIST / "fixtures" / "owworld" / f"CompositionExclusions-{UNICODE_VERSION}.txt"


def nfc_tables_from_files() -> dict:
    """NFC's data from the two Unicode files schema-dist vendors beside the case folds (serial 57, folder spec 4.7:
    every reader builds OW-18's NFC from them, never from a runtime). UnicodeData's field 3 is the combining class and
    field 5 the decomposition (one in angle brackets is compatibility, skipped). The primary composites are the
    two-part canonical decompositions minus Full_Composition_Exclusion: the file's listed code points plus what its
    comments derive from UnicodeData, singletons and non-starter decompositions. The reference checker's `load_nfc`,
    in the same shape this file emits."""
    raw, ccc = {}, {}
    for line in UNICODE_DATA.read_text(encoding="utf-8").splitlines():
        fields = line.split(";")
        cp = int(fields[0], 16)
        if fields[3] != "0":
            ccc[cp] = int(fields[3])
        if fields[5] and not fields[5].startswith("<"):
            raw[cp] = [int(x, 16) for x in fields[5].split()]
    excluded = set()
    for line in COMPOSITION_EXCLUSIONS.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            lo, _, hi = line.partition("..")
            excluded.update(range(int(lo, 16), int(hi or lo, 16) + 1))
    for cp, d in raw.items():
        if len(d) == 1 or ccc.get(cp, 0) or ccc.get(d[0], 0):
            excluded.add(cp)

    def full(cp):
        return [c for d in raw[cp] for c in full(d)] if cp in raw else [cp]

    def ordered(cps):
        # Canonical ordering: a stable sort of each run of non-starters by class, as NFD gives it.
        out, run = [], []
        for c in cps + [None]:
            if c is not None and ccc.get(c, 0):
                run.append(c)
                continue
            out += sorted(run, key=lambda x: ccc[x])
            run = []
            if c is not None:
                out.append(c)
        return out

    decomp = {cp: ordered(full(cp)) for cp in raw}
    compose = {(d[0], d[1]): cp for cp, d in raw.items() if len(d) == 2 and cp not in excluded}
    return {"decomp": decomp, "ccc": ccc, "compose": compose}


def nfc_tables_from_unicodedata() -> dict:
    """NFC's data from Python's unicodedata: each code point's full canonical decomposition (Hangul left to the
    algorithm), every non-zero canonical combining class, and the primary composites as pairs. A composite is primary
    when NFC of its decomposition gives it back, which excludes singletons, non-starter decompositions and the
    composition exclusions without a separate list."""
    if unicodedata.unidata_version != UNICODE_VERSION:
        sys.exit(f"Python's unicodedata is Unicode {unicodedata.unidata_version}; the pin is {UNICODE_VERSION}. "
                 "Use a Python whose unicodedata matches, or a published NFC file.")
    decomp, ccc, compose = {}, {}, {}
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF or HANGUL_S0 <= cp < HANGUL_S0 + HANGUL_COUNT:
            continue
        c = chr(cp)
        k = unicodedata.combining(c)
        if k:
            ccc[cp] = k
        raw = unicodedata.decomposition(c)
        if not raw or raw.startswith("<"):
            continue
        full = unicodedata.normalize("NFD", c)
        decomp[cp] = [ord(x) for x in full]
        parts = [int(x, 16) for x in raw.split()]
        if len(parts) == 2 and unicodedata.normalize("NFC", chr(parts[0]) + chr(parts[1])) == c:
            compose[(parts[0], parts[1])] = cp
    return {"decomp": decomp, "ccc": ccc, "compose": compose}


def white_space() -> list[int]:
    """What Python's str.strip() strips (str.isspace), so a world id is trimmed as the reference checker trims it."""
    return [cp for cp in range(0x110000) if not (0xD800 <= cp <= 0xDFFF) and chr(cp).isspace()]


def word_ranges() -> list[list[int]]:
    """The code points that glue an address found in prose into a word (the address page's "An address in prose",
    serial 123): general category L or M, any letter or combining mark, from the vendored UnicodeData file (a
    `<..., First>` and `<..., Last>` pair is a range), checked equal to Python's unicodedata. As ranges, first and last
    inclusive. The underscore, the set's third member, is Pc and the reader's own."""
    cps, first = set(), None
    for line in UNICODE_DATA.read_text(encoding="utf-8").splitlines():
        fields = line.split(";")
        cp = int(fields[0], 16)
        if fields[1].endswith(", First>"):
            first = cp
            continue
        lo = first if fields[1].endswith(", Last>") else cp
        first = None
        if fields[2][0] in "LM":
            cps.update(range(lo, cp + 1))
    oracle = {cp for cp in range(0x110000) if unicodedata.category(chr(cp))[0] in "LM"}
    if cps != oracle:
        sys.exit("The letters and marks from the vendored UnicodeData and from Python's unicodedata disagree.")
    ranges: list[list[int]] = []
    for cp in sorted(cps):
        if ranges and ranges[-1][1] == cp - 1:
            ranges[-1][1] = cp
        else:
            ranges.append([cp, cp])
    return ranges


def emit_unicode(nfc: dict, folds: dict, spaces: list[int], words: list[list[int]]) -> str:
    def h(cp):
        return "0x%X" % cp

    out = [
        "# GENERATED by codegen/generate.py. Do not edit: regenerate.",
        "#",
        f"# Data, not code: Unicode {UNICODE_VERSION}.",
        f"# - FOLD: the C and S rows of CaseFolding-{UNICODE_VERSION}.txt as vendored in schema-dist",
        "#   (fixtures/owworld/), OW-18's simple case folding.",
        f"# - DECOMP, CCC, COMPOSE: NFC's data from UnicodeData-{UNICODE_VERSION}.txt and",
        f"#   CompositionExclusions-{UNICODE_VERSION}.txt as vendored in schema-dist (fixtures/owworld/), checked",
        f"#   equal to Python {sys.version.split()[0]}'s unicodedata (unidata_version {unicodedata.unidata_version}).",
        "# - WHITE_SPACE: what Python's str.strip() strips, for trimming a world id as the reference checker does.",
        f"# - LETTER_OR_MARK: general category L or M from UnicodeData-{UNICODE_VERSION}.txt, what glues an address",
        "#   found in prose into a word.",
        "extends RefCounted",
        "",
        f'const UNICODE_VERSION := "{UNICODE_VERSION}"',
        "",
        "## Simple case folding (status C and S): code point -> code point.",
        "const FOLD := {",
    ]
    out += ["\t%s: %s," % (h(k), h(v)) for k, v in sorted(folds.items())]
    out += ["}", "", "## Full canonical decomposition (Hangul syllables are left to the algorithm).", "const DECOMP := {"]
    out += ["\t%s: [%s]," % (h(k), ", ".join(h(x) for x in v)) for k, v in sorted(nfc["decomp"].items())]
    out += ["}", "", "## Canonical combining class, where it is not 0.", "const CCC := {"]
    out += ["\t%s: %d," % (h(k), v) for k, v in sorted(nfc["ccc"].items())]
    out += ["}", "", "## Primary composites: (first << 21 | second) -> composite.", "const COMPOSE := {"]
    out += ["\t%s: %s," % (h(a << 21 | b), h(c)) for (a, b), c in sorted(nfc["compose"].items())]
    out += ["}", "", "## White space as Python's str.isspace() has it.", "const WHITE_SPACE := ["]
    out += ["\t" + ", ".join(h(cp) for cp in spaces) + ","]
    out += ["]", "", "## Letters and combining marks (general category L or M): ranges as first, last, first, last, ...",
            "## ascending, each inclusive.", "const LETTER_OR_MARK := ["]
    out += ["\t%s, %s," % (h(lo), h(hi)) for lo, hi in words]
    out += ["]", ""]
    return "\n".join(out)


def unicode_vectors(nfc: dict, folds: dict) -> str:
    """Test vectors: an input, Python's NFC of it, and run_py's fold (NFC then the C+S rows), as hex code points."""
    def fold(s):
        return "".join(chr(folds.get(ord(c), ord(c))) for c in unicodedata.normalize("NFC", s))

    inputs = []
    for cp in sorted(nfc["decomp"]):
        inputs.append(chr(cp))
        inputs.append(unicodedata.normalize("NFD", chr(cp)))
    for cp in range(HANGUL_S0, HANGUL_S0 + HANGUL_COUNT, 97):
        inputs.append(unicodedata.normalize("NFD", chr(cp)))
        inputs.append(chr(cp))
    rng = random.Random(15_1_0)
    marks = sorted(nfc["ccc"])
    bases = [0x41, 0x61, 0x45, 0x65, 0x4F, 0x55, 0x3B1, 0x3C9, 0x1100, 0x1161, 0x11A8, 0x938, 0x5D0, 0x627]
    for _ in range(3000):
        s = [rng.choice(bases)]
        for _ in range(rng.randint(1, 4)):
            s.append(rng.choice(marks) if rng.random() < 0.7 else rng.choice(bases))
        inputs.append("".join(map(chr, s)))
    for cp in sorted(folds):
        inputs.append(chr(cp))
    inputs += ["Café", "café", "Café", "σ", "ς", "ﬅ", "ﬆ", "ΐ", "ΐ",
               "straße", "strasse", "K", "İ", "ı", "\U0001F600", "Ａ", "abbey/Elements/x.json"]
    lines = ["# GENERATED by codegen/generate.py: input ; NFC (Python unicodedata) ; NFC then C+S fold, as hex",
             f"# unidata_version {unicodedata.unidata_version}, {len(inputs)} vectors"]
    for s in inputs:
        hx = lambda t: " ".join("%X" % ord(c) for c in t)
        lines.append("%s;%s;%s" % (hx(s), hx(unicodedata.normalize("NFC", s)), hx(fold(s))))
    return "\n".join(lines) + "\n"


# -- main -----------------------------------------------------------------------------------------------------------

def outputs() -> dict[Path, str]:
    pin = read_pin()
    problems = verify_dist(pin)
    if problems:
        for p in problems:
            print("FAIL:", p)
        sys.exit("The vendored dist is not what the pin says. Re-vendor from the pinned tag; never edit a hash.")
    version = dict(l.split(": ", 1) for l in (DIST / "VERSION").read_text(encoding="utf-8").splitlines() if ": " in l)
    head = f"{pin['tag']} (canonical {version['canonical']}, serial {int(version['serial'])})"
    schema = json.loads((DIST / "schema.json").read_text(encoding="utf-8"))
    kinds = set(KIND_VIEW) | {"generic", "list"}
    for where, fields in [("base", schema["base"]), ("world", schema["world"])] + list(schema["types"].items()):
        for f in fields:
            if f["kind"] not in kinds:
                sys.exit(f"{where}.{f['name']}: kind {f['kind']!r} is new to this emitter; refusing to drop it.")
    out = {
        ADDON / "ow_element.gd": emit_base(schema, head),
        ADDON / "ow_world_info.gd": emit_world_info(schema, head),
        ADDON / "ow_types.gd": emit_registry(schema, head),
        ADDON / "ow_schema_pin.gd": emit_pin(pin, version),
    }
    presentation = json.loads((DIST / "presentation.json").read_text(encoding="utf-8"))
    out[ADDON / "ow_presentation.gd"] = emit_presentation(presentation, head)
    out[ADDON / "ow_views_table.gd"] = views_output(schema, head)
    for slug, fields in schema["types"].items():
        out[ADDON / "models" / f"ow_{slug}.gd"] = emit_model(slug, fields, head)
    nfc = nfc_tables_from_files()
    # The oracle the tables were first built from, now a cross-check: a Python of the same Unicode must agree whole.
    if nfc != nfc_tables_from_unicodedata():
        sys.exit("NFC from the vendored files and from Python's unicodedata disagree; read both before trusting either.")
    folds = simple_folds()
    out[ADDON / "unicode" / "ow_unicode_data.gd"] = emit_unicode(nfc, folds, white_space(), word_ranges())
    out[ROOT / "tests" / "data" / "unicode_vectors.txt"] = unicode_vectors(nfc, folds)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="exit 1 if any output would change")
    a = ap.parse_args()
    pin = read_pin()
    print(f"dist OK: {pin['tag']}, MANIFEST.json sha256 {pin['manifest_sha256'][:12]}... matches the pin")
    drift = 0
    for path, text in outputs().items():
        data = text.encode("utf-8")
        if a.check:
            if not path.is_file() or path.read_bytes() != data:
                print("DRIFT:", path.relative_to(ROOT).as_posix())
                drift += 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.is_file() or path.read_bytes() != data:
                path.write_bytes(data)
                print("wrote", path.relative_to(ROOT).as_posix())
    if a.check:
        print("no drift" if not drift else f"{drift} file(s) drifted: run codegen/generate.py")
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
