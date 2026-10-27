extends RefCounted
## OWLens on the lens profile's conformance fixture (schema-dist profiles/lens.fixture.json, the pinned copy at
## dist.81, its sha256 checked against the manifest): the pair and the template, the legal values of x_lens, where a
## seat's choice lives, every resolution over the fixture's five worlds and their readers, and the invariants. The
## graph kind is test_lens_graph.gd's. The profile's tables are held equal to the fixture's and to the generated models.

const P = preload("res://tests/paths.gd")

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(P.LENS))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		if c["kind"] in ["shape", "keys", "uses"]:
			out.append(["lens:" + c["name"], _case.bind(c)])
	return out

func _case(t, c: Dictionary) -> void:
	match c["kind"]:
		"shape":
			t.eq(OWLens.is_lens(c["element"]), c["is_lens"], "is_lens")
			t.eq(OWLens.is_template(c["element"]), c["is_template"], "is_template")
		"keys":
			var bad: Variant = OWLens.check_keys(c["x_lens"])
			t.eq(bad, c["bad"], "the key refused")
			t.eq(bad == null, c["legal"], "legal")
		"uses":
			t.eq(OWLens.lenses_in_use(c["membership"], c["x_lens_uses"]), PackedStringArray(c["lenses"]), "the lenses read")
		_:
			t.fail("a case of unknown kind %s" % c["kind"])
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(P.LENS), manifest["profiles/lens.fixture.json"], "the fixture's bytes are the dist's")
	var counts := {}
	for c in _fixture()["cases"]:
		counts[c["kind"]] = counts.get(c["kind"], 0) + 1
	t.eq(_fixture()["cases"].size(), 122, "122 cases")
	t.eq(counts, {"shape": 6, "keys": 23, "resolve": 51, "invariant": 4, "uses": 4, "graph": 34}, "by kind")
	t.done()

func test_the_tables_are_the_fixtures(t) -> void:
	var f := _fixture()
	t.eq(f["profile"], "lens", "the profile")
	t.eq([f["pair"]["type"], f["pair"]["supertype"]], [OWLens.PAIR_TYPE, OWLens.PAIR_SUPERTYPE], "the pair")
	t.eq(f["template_subtype"], OWLens.TEMPLATE_SUBTYPE, "the template's subtype")
	t.eq(f["field"], OWLens.FIELD, "the field")
	t.eq(f["uses_field"], OWLens.USES_FIELD, "the uses field")
	t.eq(f["anchor_fields"], OWLens.ANCHOR_FIELDS, "the anchor fields")
	t.eq(PackedStringArray(f["type_order"]), OWTypes.slugs(), "the budget's type order is the schema's")
	t.eq(f["room_pairs"], OWLens.ROOM_PAIRS, "the room pairs")
	t.eq(f["cut_reasons"], OWLens.CUT_REASONS, "the cut reasons")
	t.eq(f["owner_only_reasons"], OWLens.OWNER_ONLY, "the owner's two")
	var d: Dictionary = f["defaults"]
	t.eq([int(d["depth"]), int(d["budget"]), d["undated"], d["show"], d["mail"], int(d["mail_days"])],
		[OWLens.DEFAULT_DEPTH, OWLens.DEFAULT_BUDGET, OWLens.DEFAULT_UNDATED, OWLens.DEFAULT_SHOW, OWLens.DEFAULT_MAIL,
		OWLens.MAIL_DAYS], "the defaults")
	t.done()

## The room pairs as the room profile's own fixture spells them, folded: the same nine, in its order.
func test_the_room_pairs_are_the_room_profiles(t) -> void:
	var room: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/profiles/room.fixture.json"))
	var words := []
	for p in room.get("pairs", []):
		words.append(OWUnicode.profile_fold(p["type"]) + "/" + OWUnicode.profile_fold(p["supertype"]))
	t.eq(words, OWLens.ROOM_PAIRS, "the room fixture's pairs")
	t.done()

## The profiles' fold is trim then simple case folding, never NFC: a decomposed e and acute stays two code points.
func test_profile_fold_is_trim_and_simple_fold(t) -> void:
	t.eq(OWUnicode.profile_fold(" Lens　"), "lens", "White_Space trimmed, ASCII folded")
	t.eq(OWUnicode.profile_fold("﻿Lens"), "﻿lens", "a byte order mark is not white space")
	t.eq(OWUnicode.profile_fold("K"), "k", "the Kelvin sign folds to k (an S row)")
	t.eq(OWUnicode.profile_fold("É"), "é", "no NFC: the decomposed pair stays decomposed")
	t.eq(OWUnicode.profile_fold("ẞ"), "ß", "capital sharp s folds to sharp s (S row), never ss (F row)")
	t.done()

## A whole number: an int, or a float with no fraction inside 64 bits. Godot's JSON reads 7 as 7.0.
func test_whole(t) -> void:
	t.eq(OWLens.whole(7), 7, "an int")
	t.eq(OWLens.whole(7.0), 7, "7.0 is whole")
	t.eq(OWLens.whole(-40.0), -40, "-40.0 is whole")
	t.eq(OWLens.whole(-0.0), 0, "-0.0 is 0")
	t.eq(OWLens.whole(JSON.parse_string("[7]")[0]), 7, "a JSON 7 as Godot parses it")
	t.eq(OWLens.whole(JSON.parse_string("[7.0]")[0]), 7, "a JSON 7.0")
	for v in [1.5, NAN, INF, -INF, 9223372036854775808.0, -9223372036854775808.0 * 2.0, 1e300, true, false, "12", null, [3], {"year": 3}]:
		t.eq(OWLens.whole(v), null, "not whole: %s" % var_to_str(v))
	t.eq(OWLens.whole(-9223372036854775808.0), -9223372036854775807 - 1, "-2^63 is the last 64-bit whole number")
	t.done()
