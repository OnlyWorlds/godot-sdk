#!/usr/bin/env python3
"""The release zip proven as a stranger would use it: an empty Godot project, the zip unpacked into it, the plugin
enabled, and a first run on a world on disk, headless and with no network.

    python tools/prove_zip.py dist/onlyworlds-godot-0.1.0.zip --godot <path to the Godot 4.7 binary>

The world is this repository's example, Hyperion (codegen/schema-dist/example/hyperion), copied into the new
project's worlds/ folder. The first run is a scene whose one Node reads it with OWWorld.read_folder and prints the
world's name, its element count and its first Character's name; the expected three lines are read from the world's
own files. Exits 0 only when both Godot runs exit 0, print no error, and the scene prints those three lines.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "codegen", "schema-dist", "example", "hyperion")

PROJECT = """\
config_version=5

[application]

config/name="A new game"
run/main_scene="res://first_run.tscn"

[editor_plugins]

enabled=PackedStringArray("res://addons/onlyworlds/plugin.cfg")
"""

SCENE = """\
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://first_run.gd" id="1"]

[node name="FirstRun" type="Node"]
script = ExtResource("1")
"""

SCRIPT = """\
extends Node

func _ready() -> void:
\tvar world := OWWorld.read_folder("res://worlds/hyperion")
\tif world == null:
\t\tget_tree().quit(1)
\t\treturn
\tprint(world.info.name)
\tprint("%d elements" % world.elements.size())
\tprint(world.of_type("character")[0].name)
\tget_tree().quit(0 if world.errors.is_empty() else 1)
"""

ERROR_MARKS = ("SCRIPT ERROR", "Parse Error", "ERROR:", "Failed to load", "Could not find type")


def expected() -> list:
    def name(path: str) -> str:
        with open(path, encoding="utf-8") as f:
            return json.load(f)["name"]
    count = 0
    for top in ("elements", "spatial"):
        base = os.path.join(WORLD, top)
        if os.path.isdir(base):
            for t in os.listdir(base):
                count += sum(1 for n in os.listdir(os.path.join(base, t)) if n.endswith(".json"))
    chars = os.path.join(WORLD, "elements", "character")
    first = sorted(n for n in os.listdir(chars) if n.endswith(".json"))[0]
    return [name(os.path.join(WORLD, "world.json")), "%d elements" % count, name(os.path.join(chars, first))]


def run(godot: str, project: str, *args: str) -> tuple:
    try:
        r = subprocess.run([godot, "--headless", "--path", project, *args], capture_output=True, timeout=180)
    except subprocess.TimeoutExpired as e:   # run() has killed Godot by now
        out = ((e.stdout or b"") + (e.stderr or b"")).decode("utf-8", "replace").replace("\r\n", "\n")
        return "timed out", out
    out = (r.stdout + r.stderr).decode("utf-8", "replace").replace("\r\n", "\n")
    return r.returncode, out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("zip")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--work", default=None, help="the folder the throwaway project is made in (default: the system's temp)")
    ap.add_argument("--keep", action="store_true", help="leave the project folder in place and print its path")
    a = ap.parse_args()

    work = tempfile.mkdtemp(prefix="ow-zip-proof-", dir=a.work)
    project = os.path.join(work, "game")
    os.makedirs(project)
    try:
        with open(os.path.join(project, "project.godot"), "w", encoding="utf-8", newline="\n") as f:
            f.write(PROJECT)
        with open(os.path.join(project, "first_run.tscn"), "w", encoding="utf-8", newline="\n") as f:
            f.write(SCENE)
        with open(os.path.join(project, "first_run.gd"), "w", encoding="utf-8", newline="\n") as f:
            f.write(SCRIPT)
        with zipfile.ZipFile(a.zip) as z:
            z.extractall(project)
        shutil.copytree(WORLD, os.path.join(project, "worlds", "hyperion"))

        failures = []
        code, out = run(a.godot, project, "--import")
        noisy = code != 0 or any(m in out for m in ERROR_MARKS)
        print("--- import (exit %s)%s" % (code, "\n" + out.rstrip() if noisy else ", its output shown only on an error"))
        if code != 0:
            failures.append("the import exited %s" % code)
        # --quit-after ends the scene when its script never loads (and so never quits it); the scene quits itself
        # within its first frame when it does.
        code2, out2 = run(a.godot, project, "--quit-after", "120")
        print("--- first run (exit %s)\n%s" % (code2, out2.rstrip()))
        if code2 != 0:
            failures.append("the first run exited %s" % code2)
        for label, text in (("import", out), ("first run", out2)):
            for line in text.splitlines():
                if any(m in line for m in ERROR_MARKS):
                    failures.append("%s printed: %s" % (label, line.strip()))
        lines = [l.strip() for l in out2.splitlines()]
        want = expected()
        if not any(lines[i:i + 3] == want for i in range(len(lines))):
            failures.append("the first run did not print %s" % " / ".join(want))

        print("---")
        if failures:
            for f in dict.fromkeys(failures):   # each once, in the order met
                print("FAIL: " + f)
            return 1
        print("OK: the zip installs in an empty project and reads a world: %s" % " / ".join(want))
        return 0
    finally:
        if a.keep:
            print("project kept at %s" % project)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
