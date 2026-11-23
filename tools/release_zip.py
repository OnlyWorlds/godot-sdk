#!/usr/bin/env python3
"""The zip a person downloads: onlyworlds-godot-<version>.zip, made from a commit or a tag, never the working folder.

    python tools/release_zip.py v0.1.0              # the tag: refused unless plugin.cfg there says 0.1.0
    python tools/release_zip.py HEAD --out dist     # any commit (what CI proves on every push)

The zip holds addons/onlyworlds/ as the named commit has it (every tracked file under it, its copy of the LICENSE
among them, refused when that copy is not the root LICENSE byte for byte), the layout Godot's "Installing plugins"
page expects ("Extract the ZIP archive and move the addons/ folder it contains into your project folder"). A commit
from before the folder held a copy gets the root's. Nothing outside addons/onlyworlds/ is
carried: the tests, the codegen and its vendored schema, the demos and the tools are for working on the addon, and the
addon loads nothing from them (every preload in it names res://addons/onlyworlds/).

The version is plugin.cfg's, read at that commit. A tag must be vX.Y.Z and say the same version, or nothing is
written. The file is the same bytes for the same commit: entries in path order, each dated with the commit's time.
Prints the zip's path, its file count, its size and its sha256. Python's standard library and git, nothing else.
"""

import argparse
import datetime
import hashlib
import io
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = "addons/onlyworlds"


def git(*args: str) -> bytes:
    r = subprocess.run(["git", "-C", ROOT, *args], capture_output=True)
    if r.returncode != 0:
        raise SystemExit("git %s: %s" % (" ".join(args), r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout


def blob(sha: str, path: str) -> bytes:
    return git("cat-file", "blob", "%s:%s" % (sha, path))


def plugin_version(cfg: bytes) -> str:
    m = re.search(rb'^version="([^"]*)"\s*$', cfg, re.M)
    if m is None:
        raise SystemExit("%s/plugin.cfg has no version line" % ADDON)
    return m.group(1).decode("utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ref", help="a tag vX.Y.Z, or a commit")
    ap.add_argument("--out", default="dist", help="the folder the zip is written to (default: dist)")
    a = ap.parse_args()

    tag = None
    if subprocess.run(["git", "-C", ROOT, "rev-parse", "-q", "--verify", "refs/tags/" + a.ref],
                      capture_output=True).returncode == 0:
        tag = a.ref
    r = subprocess.run(["git", "-C", ROOT, "rev-parse", "-q", "--verify", a.ref + "^{commit}"], capture_output=True)
    if r.returncode != 0:
        raise SystemExit("refused: no tag or commit is named %s" % a.ref)
    sha = r.stdout.decode().strip()

    version = plugin_version(blob(sha, ADDON + "/plugin.cfg"))
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("plugin.cfg's version %r is not X.Y.Z" % version)
    if tag is not None:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            raise SystemExit("refused: the tag %s is not vX.Y.Z" % tag)
        if tag[1:] != version:
            raise SystemExit("refused: the tag says %s, plugin.cfg at %s says %s" % (tag[1:], sha[:7], version))

    paths = [p for p in git("ls-tree", "-r", "--name-only", "-z", sha, "--", ADDON + "/").decode("utf-8").split("\0") if p]
    if not paths:
        raise SystemExit("%s holds no files at %s" % (ADDON, sha[:7]))
    files = {p: blob(sha, p) for p in paths}
    if ADDON + "/LICENSE" not in files:
        # Before 0.1.1 the folder held no copy, and the zip carried the root's.
        files[ADDON + "/LICENSE"] = blob(sha, "LICENSE")
    elif files[ADDON + "/LICENSE"] != blob(sha, "LICENSE"):
        raise SystemExit("refused: %s/LICENSE at %s is not the root LICENSE byte for byte" % (ADDON, sha[:7]))

    when = datetime.datetime.fromtimestamp(int(git("log", "-1", "--format=%ct", sha).decode().strip()),
                                           datetime.timezone.utc)
    stamp = (when.year, when.month, when.day, when.hour, when.minute, when.second)

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for p in sorted(files):
            info = zipfile.ZipInfo(p, stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            info.create_system = 3   # unix, so the mode above is read on unpack
            z.writestr(info, files[p], compresslevel=9)
    data = buf.getvalue()

    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, "onlyworlds-godot-%s.zip" % version)
    with open(out, "wb") as f:
        f.write(data)

    print("zip:     %s" % out)
    print("from:    %s%s" % (sha, " (tag %s)" % tag if tag else " (a commit, not a tag)"))
    print("version: %s" % version)
    print("files:   %d" % len(files))
    print("size:    %d bytes" % len(data))
    print("sha256:  %s" % hashlib.sha256(data).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
