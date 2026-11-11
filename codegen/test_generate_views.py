#!/usr/bin/env python3
"""generate.py's check of views.json (check_views): green on the vendored file, and each refusal the Unity SDK's
codegen/generate_views.py makes (628418d) red on a copy changed in one place: a file of another version, a column
OWViews does not read, a field its type lacks, a pair its profile's reader does not match, an undefined layout, two
rows of one kind, a field a row names with no cite, and a cite whose quote is not at its line.

Each case changes a deep copy of the parsed file (or of the fixture) and calls check_views on it, so the vendored dist
is never touched; the pin's own check (verify_dist) refuses a changed byte before check_views is reached, which is why
the refusals are tested here on the parsed copy.

    python codegen/test_generate_views.py
"""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

CODEGEN = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("ow_generate", CODEGEN / "generate.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

DIST = gen.DIST


def _read(name: str):
    return json.loads((DIST / name).read_text(encoding="utf-8"))


class CheckViewsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.doc = _read("views.json")
        self.schema = _read("schema.json")
        self.fixture = _read("views.fixture.json")

    def refused(self, doc=None, fixture=None) -> str:
        with self.assertRaises(SystemExit) as cm:
            gen.check_views(self.doc if doc is None else doc, self.schema,
                            self.fixture if fixture is None else fixture, DIST)
        return str(cm.exception.code)

    def row(self, doc, rid: str) -> dict:
        return next(r for r in doc["rows"] if r["id"] == rid)

    def test_the_vendored_file_passes(self) -> None:
        gen.check_views(self.doc, self.schema, self.fixture, DIST)

    def test_the_emitted_table_is_the_committed_one(self) -> None:
        sha = gen.hashlib.sha256((DIST / "views.json").read_bytes()).hexdigest()
        want = gen.emit_views(self.doc, sha, self.schema, "HEAD")
        have = (gen.ADDON / "ow_views_table.gd").read_text(encoding="utf-8")
        self.assertEqual(want.split("\n", 1)[1], have.split("\n", 1)[1], "only the generated header may differ")

    def test_version_2_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        doc["_meta"]["version"] = 2
        self.assertIn("`_meta.version` is 2, expected 3", self.refused(doc))

    def test_a_column_owviews_does_not_read_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "charter")["tone"] = "formal"
        self.assertIn("which OWViews does not read", self.refused(doc))

    def test_a_field_its_type_lacks_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "charter")["lead"].append("story")  # a Narrative's field, not a Law's
        self.assertIn("which law does not have by the walk", self.refused(doc))

    def test_a_pair_its_profiles_reader_does_not_match_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "report")["kind"]["pair"] = "narrative/Chronicle"
        self.assertIn("is not one the room profile's reader matches", self.refused(doc))
        doc = copy.deepcopy(self.doc)
        self.row(doc, "charter")["kind"]["pair"] = "narrative/Message"  # a room pair, not a reading aid's
        self.assertIn("is not one the charter profile's reader matches", self.refused(doc))

    def test_an_undefined_layout_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "charter")["layout"]["name"] = "gallery"
        self.assertIn("with a name the file defines", self.refused(doc))

    def test_two_rows_of_one_kind_are_refused_folded(self) -> None:
        doc = copy.deepcopy(self.doc)
        twin = copy.deepcopy(self.row(doc, "message"))
        twin["id"] = "message-again"
        twin["kind"] = {"type": "narrative", "supertype": " message "}  # the type a slug as written, the supertype folded
        doc["rows"].append(twin)
        self.assertIn("holds a kind another row holds", self.refused(doc))

    def test_two_rows_of_one_id_are_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "charter")["id"] = "report"
        self.assertIn("each row needs its own non-empty id", self.refused(doc))

    def test_a_named_field_with_no_cite_is_refused(self) -> None:
        doc = copy.deepcopy(self.doc)
        self.row(doc, "message")["lead"].append("consequences")  # a Narrative's field, cited nowhere
        self.assertIn("with no cite in views.fixture.json: [('message', 'consequences')]", self.refused(doc))

    def test_a_cite_whose_quote_is_not_at_its_line_is_refused(self) -> None:
        fixture = copy.deepcopy(self.fixture)
        fixture["cites"][0]["line"] += 1
        self.assertIn("the quote is not at that line of the page", self.refused(fixture=fixture))

    def test_a_cite_of_a_field_its_row_does_not_name_is_refused(self) -> None:
        fixture = copy.deepcopy(self.fixture)
        fixture["cites"][3]["field"] = "story"  # the charter row names description only
        self.assertIn("names a field its row does not name", self.refused(fixture=fixture))


if __name__ == "__main__":
    unittest.main()
