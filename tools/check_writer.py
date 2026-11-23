#!/usr/bin/env python3
"""Judge .owworld files with the reference checker's own reader and check_writer (folder spec 4.7).

    python tools/check_writer.py FILE [FILE ...] [--source private] [--run-py DIR]

The checker (`run_py.py`, the reference reader and writer check the fixture set was made with) is not part of this
repository; this imports it from DIR (--run-py, or the folder OW_RUN_PY names), and takes `source` (the files a conforming writer must carry byte-exact) from the pinned set's
verdicts.json. Prints one line per file; exits 1 unless every file is accepted by the reader and by check_writer.
"""

import argparse
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VERDICTS = os.path.join(HERE, "..", "codegen", "schema-dist", "fixtures", "owworld", "verdicts.json")
DEFAULT_RUN_PY = os.environ.get("OW_RUN_PY", "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("--source", help="one of verdicts.json's `sources` (default: the base world's `source`)")
    ap.add_argument("--run-py", default=DEFAULT_RUN_PY, help="the folder holding run_py.py")
    a = ap.parse_args()
    if not a.run_py:
        ap.error("no checker: pass --run-py DIR or set OW_RUN_PY to the folder holding run_py.py")
    sys.dont_write_bytecode = True  # read the checker, never write beside it
    spec =importlib.util.spec_from_file_location("run_py", os.path.join(a.run_py, "run_py.py"))
    run_py = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(run_py)
    doc = json.load(open(VERDICTS, encoding="utf-8"))
    source = doc["sources"][a.source] if a.source else doc["source"]
    marker = doc["marker"].encode("ascii")
    bad = 0
    for path in a.files:
        raw = open(path, "rb").read()
        try:
            read = run_py.read_archive(raw, marker)
        except run_py.Refused as r:
            print("%s: reader REFUSES (%s: %s)" % (path, r.reason, r))
            bad += 1
            continue
        fault = run_py.check_writer(raw, read, source)
        print("%s: reader accepts (world %s, %d files); check_writer %s" % (
            path, read[0], len(read[3]), "ACCEPTS" if fault is None else "REFUSES: " + fault))
        bad += fault is not None
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
