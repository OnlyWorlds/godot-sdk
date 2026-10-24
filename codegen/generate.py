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
  -> addons/onlyworlds/unicode/ow_unicode_data.gd NFC data and the C+S case folds (OW-18), as GDScript constants
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


def emit_unicode(nfc: dict, folds: dict, spaces: list[int]) -> str:
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
    for slug, fields in schema["types"].items():
        out[ADDON / "models" / f"ow_{slug}.gd"] = emit_model(slug, fields, head)
    nfc = nfc_tables_from_files()
    # The oracle the tables were first built from, now a cross-check: a Python of the same Unicode must agree whole.
    if nfc != nfc_tables_from_unicodedata():
        sys.exit("NFC from the vendored files and from Python's unicodedata disagree; read both before trusting either.")
    folds = simple_folds()
    out[ADDON / "unicode" / "ow_unicode_data.gd"] = emit_unicode(nfc, folds, white_space())
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
