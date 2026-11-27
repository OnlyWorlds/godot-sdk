#!/usr/bin/env python3
"""Hold the addon to its written promise (the docs' Stability page, "The standard, the packages and this site").

A patch release fixes and a minor release adds; neither removes nor renames a public name. A name that will go is
marked first, as `## @deprecated: Since X.Y.Z, leaves in 1.0, use Y.` in its doc comment (and a function also calls
push_warning with those words); the mark says since which release and the release it leaves in; the name stays at
least six months after that release and goes only in a major (1.0 for this 0.x addon). Three rules, against the names
file `tools/public-names.json`:

1. Marks. Every `@deprecated` on a public name says `Since X.Y.Z` (a release at or before this one, or the next one
   while the CHANGELOG has an Unreleased section) and `leaves in N.0`, N a major above this one.
2. Names. Within the major the file was written at, every name it lists is still public (declared, or reachable
   through an in-tree base class), every public name is listed, and the file records each name's mark as the source
   has it. A release that adds names or marks runs `--write`.
3. Six months. When the major has moved, a listed name gone from the source was marked in the file, and the release
   its mark names is dated (the CHANGELOG's `## [x.y.z] - YYYY-MM-DD`) at least six months before this release.

A public name: a `class_name` class of addons/onlyworlds (and its inner classes), with its members, methods, constants
and signals, none of whose parts starts with an underscore. Godot reads them itself: `--doctool --gdscript-docs`
writes the addon's reference as XML, and its `@deprecated` tags as `deprecated` attributes. A script without a
`class_name` is not public. The keys of an answer given as a Dictionary are not names, and are not checked.
Not checked: whether a mark's words are true, whether a marked function warns when called, a call's parameters, a
change of behaviour under an unchanged name. Watched failing: tools/mutants_promise.py.

Usage:
  python tools/verify_promise.py --godot <binary>           check the addon against the names file
  python tools/verify_promise.py --godot <binary> --write   add new names and update the marks; a name leaves the
                                                            file only when the major moved and rule 3 lets it go
The project must have been imported once (`godot --headless --path . --import`). The binary is --godot, else the
GODOT environment variable, else `godot` on the PATH. `--docs DIR` reads XML a doctool run already wrote.
Exit 0 PASS, 1 FAIL (one line per break), 2 BLIND (Godot, the version, the CHANGELOG or the names file could not be
read): never a pass.
"""

from __future__ import annotations

import argparse
import calendar
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("OW_PROMISE_ROOT") or HERE.parent)
NAMES_FILE = Path(os.environ.get("OW_PROMISE_NAMES") or ROOT / "tools" / "public-names.json")
ADDON = "res://addons/onlyworlds"
CHANGELOG = ROOT / "CHANGELOG.md"
SINCE = re.compile(r"\bsince (\d+\.\d+\.\d+)\b", re.IGNORECASE)
LEAVES = re.compile(r"\bleaves? in (\d+)\.(\d+)\b", re.IGNORECASE)
HEADING = re.compile(r"^## \[(\d+\.\d+\.\d+)\]\s*[-—]\s*(\d{4}-\d{2}-\d{2})", re.MULTILINE)
UNRELEASED = re.compile(r"^## \[Unreleased\]", re.MULTILINE | re.IGNORECASE)
ABOUT = (
    "Every public name of the OnlyWorlds SDK for Godot and its deprecation: written by tools/verify_promise.py --write, "
    "read by it in CI. A name leaves this file only in a major."
)
MARK_WORDS = "## @deprecated: Since X.Y.Z, leaves in 1.0, use ..."
OPTIONS = argparse.Namespace(godot=None, docs=None)


class Blind(Exception):
    """Something the check needs could not be read: exit 2, never a pass."""


# ---- this engine: the version and the public names -------------------------------------------------------------


def read_version() -> str:
    try:
        text = (ROOT / "addons" / "onlyworlds" / "plugin.cfg").read_text(encoding="utf-8")
    except OSError as exc:
        raise Blind(f"plugin.cfg: {exc}") from exc
    m = re.search(r'^version="(\d+\.\d+\.\d+)"', text, re.MULTILINE)
    if not m:
        raise Blind('plugin.cfg: no version="X.Y.Z"')
    return m.group(1)


def doctool(out: Path) -> None:
    godot = OPTIONS.godot or os.environ.get("GODOT") or "godot"
    try:
        r = subprocess.run([godot, "--headless", "--path", str(ROOT), "--doctool", str(out), "--gdscript-docs", ADDON],
                           capture_output=True, text=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Blind(f"Godot ({godot}) did not run: {exc}") from exc
    if r.returncode != 0:
        raise Blind(f"Godot's doctool exited {r.returncode}: {(r.stdout + r.stderr)[-800:]}")


CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")  # Godot writes a private constant's control character raw


def read_xml(folder: Path) -> tuple[list[tuple[str, str | None]], set[str]]:
    decls: list[tuple[str, str | None]] = []
    members: dict[str, list[str]] = {}
    inherits: dict[str, str] = {}
    files = sorted(folder.glob("*.xml"))
    if not files:
        raise Blind(f"{folder}: no XML: the doctool wrote nothing (import the project first?)")
    public = lambda n: not any(p.startswith("_") for p in n.split("."))
    for f in files:
        try:
            root = ET.fromstring(CONTROL.sub("?", f.read_text(encoding="utf-8")))
        except (OSError, ET.ParseError) as exc:
            raise Blind(f"{f.name}: {exc}") from exc
        cls = root.get("name") or ""
        if cls.startswith('"') or not public(cls):
            continue  # a script without a class_name, or a private inner class
        decls.append((cls, root.get("deprecated")))
        if root.get("inherits"):
            inherits[cls] = root.get("inherits")
        if "." in cls:
            members.setdefault(cls.rsplit(".", 1)[0], []).append(cls.rsplit(".", 1)[1])
        for section in ("members", "methods", "constants", "signals"):
            node = root.find(section)
            for e in [] if node is None else node:
                n = e.get("name")
                if n and public(n):
                    decls.append((f"{cls}.{n}", e.get("deprecated")))
                    members.setdefault(cls, []).append(n)
    if not any("." not in n for n, _ in decls):
        raise Blind(f"{folder}: no public class read")
    reach: set[str] = set()
    for cls in inherits:
        seen, base = {cls}, inherits.get(cls)
        while base in members or base in inherits:
            if base in seen:
                break
            seen.add(base)
            reach.update(f"{cls}.{m}" for m in members.get(base, []))
            base = inherits.get(base)
    return decls, reach


def read_names() -> tuple[list[tuple[str, str | None]], set[str]]:
    if OPTIONS.docs:
        return read_xml(Path(OPTIONS.docs))
    with tempfile.TemporaryDirectory(prefix="ow-promise-doc-") as out:
        doctool(Path(out))
        return read_xml(Path(out))


def engine_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--godot", help="the Godot binary (else GODOT, else godot on the PATH)")
    parser.add_argument("--docs", help="read the XML a doctool run wrote into DIR, instead of running Godot")


# ---- the rules (the same in the three engine packages) -----------------------------------------------------------


def parse_version(v: str) -> tuple[int, int, int]:
    a, b, c = (int(x) for x in v.split("."))
    return a, b, c


def six_months_after(day: datetime.date) -> datetime.date:
    month = day.month + 6
    year, month = day.year + (month - 1) // 12, (month - 1) % 12 + 1
    return datetime.date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


def changelog() -> tuple[dict[str, datetime.date], bool]:
    try:
        text = CHANGELOG.read_text(encoding="utf-8")
    except OSError as exc:
        raise Blind(f"{CHANGELOG.name}: {exc}") from exc
    return {v: datetime.date.fromisoformat(d) for v, d in HEADING.findall(text)}, bool(UNRELEASED.search(text))


def judge_mark(text: str | None, version: str, unreleased: bool) -> tuple[str | None, str | None, list[str]]:
    """Rule 1 for one mark: (since, leaves, failures)."""
    fails: list[str] = []
    if text is None:
        return None, None, []
    if text.startswith("\u0000"):
        return None, None, [f"its message is not a string this check can read ({text[1:][:80]}): write it as a literal or a const string"]
    major = parse_version(version)[0]
    since = None
    sinces = SINCE.findall(text)
    if not sinces:
        fails.append(f'its message says no "Since X.Y.Z" ({text[:90]!r}); the words are {MARK_WORDS}')
    elif len(set(sinces)) > 1:
        fails.append(f"its message names more than one release it was marked in ({', '.join(sorted(set(sinces)))})")
    else:
        since = sinces[0]
        s, v = parse_version(since), parse_version(version)
        nexts = {(v[0], v[1], v[2] + 1), (v[0], v[1] + 1, 0)}
        if s > v and not (unreleased and s in nexts):
            fails.append(f"marked since {since}, after this release {version} and not the next one")
    leaves = None
    found = [(int(a), int(b)) for a, b in LEAVES.findall(text)]
    above = sorted(f for f in found if f[0] > major and f[1] == 0)
    if not found:
        fails.append(f'its message says no "Leaves in N.0" ({text[:90]!r}); the words are {MARK_WORDS}')
    elif not above:
        fails.append(f"it leaves in {found[0][0]}.{found[0][1]}, not in a major above {major} (N.0)")
    else:
        leaves = f"{above[0][0]}.0"
    return since, leaves, fails


def run(writing: bool) -> int:
    version = read_version()
    major = parse_version(version)[0]
    decls, reach = read_names()
    dates, unreleased = changelog()
    today = datetime.date.fromisoformat(os.environ["OW_PROMISE_TODAY"]) if os.environ.get("OW_PROMISE_TODAY") else datetime.date.today()

    fails: list[str] = []
    by_name: dict[str, list[str | None]] = {}
    for name, mark in decls:
        by_name.setdefault(name, []).append(mark)
    source: dict[str, dict] = {}
    for name, marks in sorted(by_name.items()):
        record: dict = {}
        judged = []
        for mark in marks:
            since, leaves, bad = judge_mark(mark, version, unreleased)
            fails += [f"(1) {name}: {b}" for b in bad]
            judged.append((mark, since, leaves))
        if all(m is not None for m, _, _ in judged):
            since, leaves = judged[0][1], judged[0][2]
            record = {"deprecated": {"since": since, "leaves": leaves}}
        source[name] = record
    present = set(source) | reach

    file = None
    if NAMES_FILE.exists():
        try:
            file = json.loads(NAMES_FILE.read_text(encoding="utf-8"))
        except ValueError as exc:
            raise Blind(f"{NAMES_FILE.name} is not JSON: {exc}") from exc
        if not (isinstance(file, dict) and isinstance(file.get("major"), int) and isinstance(file.get("names"), dict)
                and isinstance(file.get("version"), str)):
            raise Blind(f"{NAMES_FILE.name} has no version, major or names")
        if file["major"] > major:
            raise Blind(f"{NAMES_FILE.name} was written at {file['version']}, a later major than {version}")
    elif not writing:
        raise Blind(f"{NAMES_FILE} does not exist: run with --write once")

    released: set[str] = set()  # names a moved major may drop
    held_back = False
    if file:
        moved = file["major"] != major
        this_day = dates.get(version, today)
        for name, info in sorted(file["names"].items()):
            if name in present:
                continue
            if not moved:
                fails.append(f"(2) {name}: listed at {file['version']}, gone from {version}, and the major is still {major}")
                continue
            since = (info.get("deprecated") or {}).get("since")
            if not since:
                fails.append(f"(3) {name}: gone in major {major} without a mark first")
            elif since not in dates:
                fails.append(f"(3) {name}: marked since {since}, a release {CHANGELOG.name} does not date")
            elif six_months_after(dates[since]) > this_day:
                fails.append(f"(3) {name}: marked since {since} ({dates[since]}), gone {this_day}, before {six_months_after(dates[since])}")
            else:
                released.add(name)
                continue
            held_back = True
        if not writing:
            for name, record in source.items():
                if name not in file["names"]:
                    fails.append(f"(2) {name}: public in {version} and not in {NAMES_FILE.name}: run --write")
                elif file["names"][name] != record and not moved:  # a major rewrites the marks: --write
                    fails.append(f"(2) {name}: the source marks it {record or 'not at all'}, the names file {file['names'][name] or 'not at all'}: run --write")

    count, marked = len(source), sum(1 for r in source.values() if r)
    if writing:
        keep = {} if not file else {n: r for n, r in file["names"].items() if n not in released and n not in source}
        names = {**keep, **source}
        back = held_back and file is not None and file["major"] != major
        out = {"about": ABOUT, "version": file["version"] if back else version, "major": file["major"] if back else major,
               "names": dict(sorted(names.items()))}
        with NAMES_FILE.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(json.dumps(out, indent=1, ensure_ascii=True) + "\n")
        print(f"wrote {NAMES_FILE.name}: {len(names)} names, {marked} marked")
    for f in fails:
        print(f"  FAIL {f}")
    if fails:
        print(f"FAIL: {len(fails)} break(s) of the promise in {version}.")
        return 1
    print(f"PASS: {count} public names in {version}, {marked} marked deprecated, each with its since and the release it "
          f"leaves in; none gone within major {major}. Not checked: a mark's other words, a call's parameters, "
          f"behaviour under an unchanged name.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument("--write", action="store_true", help="add new names and update the marks in the names file")
    engine_options(parser)
    args = parser.parse_args()
    vars(OPTIONS).update(vars(args))
    try:
        return run(args.write)
    except Blind as exc:
        print(f"BLIND: {exc}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
