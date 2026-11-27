#!/usr/bin/env python3
"""Watch tools/verify_promise.py fail, once for each thing it holds, and pass on its controls.

Godot's doctool writes the addon's reference once, from this checkout. Each plant then runs the check (with --docs)
on a copy of what it reads (that XML, plugin.cfg, CHANGELOG.md and tools/public-names.json), never on the real files,
with one change made to the copy. One more plant goes through Godot itself: a copy of the addon in an empty project,
an `@deprecated` without its since written in a doc comment, imported and read by the doctool, so the path from a doc
comment to the check is watched too.

Usage: python tools/mutants_promise.py --godot <binary>   (else GODOT, else godot on the PATH; the project imported)
Exit 0 when every plant failed as named and every control passed, 1 otherwise, 2 when Godot does not run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CHECK = HERE / "verify_promise.py"
MARKED = "OWPresentation.family_of"
GOOD = "Since 0.6.0. Leaves in 1.0. Use [method OWPresentation.icon_of]."


def godot_docs(godot: str, project: Path, out: Path) -> None:
    r = subprocess.run([godot, "--headless", "--path", str(project), "--doctool", str(out), "--gdscript-docs",
                        "res://addons/onlyworlds"], capture_output=True, text=True, timeout=600)
    if r.returncode != 0 or not list(out.glob("*.xml")):
        print(f"mutants-promise: Godot's doctool did not run (exit {r.returncode}):\n{(r.stdout + r.stderr)[-800:]}")
        sys.exit(2)


def copy(docs: Path) -> Path:
    d = Path(tempfile.mkdtemp(prefix="ow-promise-"))
    shutil.copytree(docs, d / "docs")
    (d / "addons" / "onlyworlds").mkdir(parents=True)
    shutil.copy2(ROOT / "addons" / "onlyworlds" / "plugin.cfg", d / "addons" / "onlyworlds" / "plugin.cfg")
    shutil.copy2(ROOT / "CHANGELOG.md", d / "CHANGELOG.md")
    (d / "tools").mkdir()
    shutil.copy2(HERE / "public-names.json", d / "tools" / "public-names.json")
    return d


def edit(path: Path, fn) -> None:
    path.write_text(fn(path.read_text(encoding="utf-8")), encoding="utf-8", newline="")


def once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise RuntimeError(f"plant anchor not found: {old}")
    return text.replace(old, new, 1)


def mark(words: str):
    """family_of marked deprecated with `words`, as the doctool writes a `## @deprecated: words` tag."""
    return lambda d: edit(d / "docs" / "OWPresentation.xml", lambda t: once(
        t, '<method name="family_of" qualifiers="static">', f'<method name="family_of" qualifiers="static" deprecated="{words}">'))


def names(fn):
    return lambda d: edit(d / "tools" / "public-names.json", lambda t: json.dumps(fn(json.loads(t)), indent=1) + "\n")


def ghost(since: str | None):
    def put(f):
        f["names"]["GhostName"] = {"deprecated": {"since": since, "leaves": "1.0"}} if since else {}
        return f
    return names(put)


def major1(date: str):
    def plant(d: Path) -> None:
        edit(d / "addons" / "onlyworlds" / "plugin.cfg", lambda t: re.sub(r'^version="[^"]+"', 'version="1.0.0"', t, count=1, flags=re.M))
        edit(d / "CHANGELOG.md", lambda t: once(t, "## [Unreleased]", f"## [Unreleased]\n\n## [1.0.0] - {date}"))
    return plant


def both(*plants):
    return lambda d: [p(d) for p in plants]


def unlist(f):
    del f["names"]["OWClient"]
    return f


def recorded(f):
    f["names"][MARKED] = {"deprecated": {"since": "0.6.0", "leaves": "1.0"}}
    return f


def inherited(f):
    f["names"]["OWFamily.name"] = {}  # declared on OWElement, its base: still reachable
    return f


PLANTS = [
    ("a listed name gone within the major", ghost(None), 1, r"\(2\) GhostName: listed at"),
    ("a public name the file does not list", names(unlist), 1, r"\(2\) OWClient: public in .* not in public-names\.json"),
    ("a mark the file does not record", mark(GOOD), 1, r"\(2\) OWPresentation\.family_of: the source marks it"),
    ("a mark without its since", mark("Leaves in 1.0, use [method OWPresentation.icon_of]."), 1,
     r'\(1\) OWPresentation\.family_of: its message says no "Since X\.Y\.Z"'),
    ("a mark that leaves in a minor", mark("Since 0.6.0, leaves in 0.9, use [method OWPresentation.icon_of]."), 1,
     r"\(1\) OWPresentation\.family_of: it leaves in 0\.9, not in a major above 0"),
    ("a mark since a release after the next one", mark("Since 9.9.9, leaves in 1.0."), 1,
     r"\(1\) OWPresentation\.family_of: marked since 9\.9\.9, after this release"),
    ("a mark with no words", mark(""), 1, r'\(1\) OWPresentation\.family_of: its message says no "Since X\.Y\.Z"'),
    ("a major that drops an unmarked name", both(major1("2027-12-01"), ghost(None)), 1, r"\(3\) GhostName: gone in major 1 without a mark first"),
    ("a major that drops a name under six months after its mark", both(major1("2027-05-22"), ghost("0.1.0")), 1,
     r"\(3\) GhostName: marked since 0\.1\.0 \(2026-11-23\), gone 2027-05-22, before 2027-05-23"),
    ("control: a major that drops a name six months after its mark", both(major1("2027-05-23"), ghost("0.1.0")), 0, r"^PASS"),
    ("control: a well-formed mark the file records", both(mark(GOOD), names(recorded)), 0, r"^PASS: \d+ public names in [\d.]+, 1 marked"),
    ("control: a listed member reached through its base class", names(inherited), 0, r"^PASS"),
    ("control: the copy unchanged", lambda d: None, 0, r"^PASS"),
]


def through_godot(godot: str) -> tuple[bool, str]:
    """An `@deprecated` without its since in the addon's source, read by Godot's doctool and failed by the check."""
    d = Path(tempfile.mkdtemp(prefix="ow-promise-src-"))
    try:
        shutil.copytree(ROOT / "addons", d / "addons")
        (d / "project.godot").write_text('config_version=5\n\n[application]\n\nconfig/name="promise plant"\n', encoding="utf-8")
        script = d / "addons" / "onlyworlds" / "ow_presentation.gd"
        edit(script, lambda t: once(t, "static func family_of(", "## @deprecated: Leaves in 1.0, use [method icon_of].\nstatic func family_of("))
        subprocess.run([godot, "--headless", "--path", str(d), "--import"], capture_output=True, timeout=600)
        (d / "tools").mkdir()
        shutil.copy2(HERE / "public-names.json", d / "tools" / "public-names.json")
        shutil.copy2(ROOT / "CHANGELOG.md", d / "CHANGELOG.md")
        env = {**os.environ, "OW_PROMISE_ROOT": str(d), "OW_PROMISE_NAMES": str(d / "tools" / "public-names.json")}
        r = subprocess.run([sys.executable, str(CHECK), "--godot", godot], env=env, capture_output=True, text=True, timeout=600)
        out = r.stdout + r.stderr
        ok = r.returncode == 1 and re.search(r'\(1\) OWPresentation\.family_of: its message says no "Since', out) is not None
        return ok, out
    finally:
        shutil.rmtree(d, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Watch tools/verify_promise.py fail once per rule.")
    parser.add_argument("--godot", default=os.environ.get("GODOT") or "godot")
    godot = parser.parse_args().godot
    base = Path(tempfile.mkdtemp(prefix="ow-promise-doc-"))
    bad = 0
    try:
        godot_docs(godot, ROOT, base)
        for what, plant, want, line in PLANTS:
            d = copy(base)
            try:
                plant(d)
                env = {**os.environ, "OW_PROMISE_ROOT": str(d), "OW_PROMISE_NAMES": str(d / "tools" / "public-names.json")}
                r = subprocess.run([sys.executable, str(CHECK), "--docs", str(d / "docs")], env=env, capture_output=True, text=True, timeout=600)
                out = r.stdout + r.stderr
                ok = r.returncode == want and re.search(line, out, re.MULTILINE) is not None
                bad += not ok
                print(f"{'as named' if ok else 'NOT AS NAMED'}: {what} (exit {r.returncode}, wanted {want})" + ("" if ok else f"\n{out[:1500]}"))
            finally:
                shutil.rmtree(d, ignore_errors=True)
    finally:
        shutil.rmtree(base, ignore_errors=True)
    ok, out = through_godot(godot)
    bad += not ok
    print(f"{'as named' if ok else 'NOT AS NAMED'}: a doc comment's @deprecated without its since, read by Godot" + ("" if ok else f"\n{out[:1500]}"))
    plants = sum(1 for p in PLANTS if not p[0].startswith("control")) + 1
    controls = len(PLANTS) + 1 - plants
    print(f"mutants-promise: FAIL: {bad} of {len(PLANTS) + 1} not as named" if bad
          else f"mutants-promise: PASS: {plants} plants each failed as named; {controls} controls passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
