extends RefCounted
## OWLens on the lens profile's conformance fixture (schema-dist profiles/lens.fixture.json, the pinned copy at
## dist.82, its sha256 checked against the manifest): the pair and the template, the legal values of x_lens, where a
## seat's choice lives, every resolution over the fixture's five worlds and their readers, and the invariants. The
## graph kind is test_lens_graph.gd's. The profile's tables are held equal to the fixture's and to the generated models.

const P = preload("res://tests/paths.gd")
## The npm SDK's and the Python package's shared edge cases (npm 4.98.0's test/fixtures/lens-edges.json, byte for byte;
## both suites hold this sha256), answers written by hand.
const EDGES := "res://tests/data/lens-edges.json"
const EDGES_SHA256 := "4cb440cde85da877e2b5ba7129dd34be90a1e0bb109eefb56f0cae040a19b080"

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
		elif c["kind"] == "resolve":
			out.append(["lens:" + c["name"], _resolves.bind(c)])
		elif c["kind"] == "invariant":
			out.append(["lens:" + c["name"], _holds.bind(c)])
	for e in _edges():
		out.append(["lens-edges:" + e["name"], _edge.bind(e)])
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
	t.eq(_fixture()["cases"].size(), 132, "132 cases")
	t.eq(counts, {"shape": 6, "keys": 23, "resolve": 58, "invariant": 4, "uses": 4, "graph": 37}, "by kind")
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
	t.eq(f["reading_aid_pairs"], OWLens.READING_AID_PAIRS, "the reading aids' pairs")
	t.eq(f["reading_aid_mark"]["field"], OWLens.READING_AID_MARK, "the reading aid's mark")
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

# -- the date table and date_of (the npm SDK 4.96.0's DATE_FIELD and dateOf, the Python package 0.79.0's date_of) ----

## The table is the fixture's date_table; every type of the standard is dated (12) or timeless (10); each date field is
## an integer field of its type in the generated models; the table cannot be written to.
func test_the_date_table_is_the_fixtures(t) -> void:
	t.eq(_ints(_fixture()["date_table"]), OWLens.DATE_FIELD, "the fixture's date_table")
	t.eq(OWLens.DATE_FIELD.size(), 12, "twelve dated types")
	var timeless := 0
	for slug in OWTypes.slugs():
		if not OWLens.DATE_FIELD.has(slug):
			timeless += 1
	t.eq(timeless, 10, "the ten timeless types")
	for type in OWLens.DATE_FIELD:
		var fields: Dictionary = OWTypes.SCRIPTS[type].get_script_constant_map()["FIELDS"]
		var field: String = OWLens.DATE_FIELD[type]
		t.ok(fields.has(field) and fields[field][0] == "scalar_int", "%s.%s is an integer field" % [type, field])
	t.ok(OWLens.DATE_FIELD.is_read_only(), "the table cannot be written to")
	t.done()

## The whole number in the type's date field, 0 and a date before 0 included, the type trimmed and folded; a number
## with no fraction is whole (7.0, as JavaScript and the Python package read it).
func test_date_of_reads_the_whole_number(t) -> void:
	for type in OWLens.DATE_FIELD:
		var field: String = OWLens.DATE_FIELD[type]
		t.eq(OWLens.date_of({"type": type, field: 1204}), 1204, type)
		t.eq(OWLens.date_of({"type": type, field: 0}), 0, type + " at 0")
		t.eq(OWLens.date_of({"type": type, field: -40}), -40, type + " before 0")
	t.eq(OWLens.date_of({"type": " Event ", "start_date": 7}), 7, "the type is trimmed and folded")
	t.eq(OWLens.date_of({"type": "EVENT", "start_date": 7}), 7, "folded")
	t.eq(OWLens.date_of(JSON.parse_string("{\"type\":\"event\",\"start_date\":7}")), 7, "a JSON 7, which Godot reads as 7.0")
	t.eq(OWLens.date_of(JSON.parse_string("{\"type\":\"event\",\"start_date\":7.0}")), 7, "7.0 is whole")
	t.eq(OWLens.date_of({"type": "event", "start_date": -40.0}), -40, "-40.0 is whole")
	t.done()

## Null for a timeless type, another type's field, a value that is not a whole number, an absent field, no type, a type
## that is no type, a known-of stub (it serves no date), and anything that is not an element body.
func test_date_of_is_null_for_what_is_not_a_date(t) -> void:
	for type in OWTypes.slugs():
		if not OWLens.DATE_FIELD.has(type):
			t.eq(OWLens.date_of({"type": type, "start_date": 5, "birth_date": 5, "date": 5}), null, type)
	t.eq(OWLens.date_of({"type": "event", "birth_date": 5}), null, "another type's field")
	for v in [null, "12", 1.5, true, NAN, INF, 1e20, [3], {"year": 3}]:
		t.eq(OWLens.date_of({"type": "event", "start_date": v}), null, var_to_str(v))
	t.eq(OWLens.date_of({"type": "event"}), null, "absent")
	t.eq(OWLens.date_of({"start_date": 5}), null, "no type")
	t.eq(OWLens.date_of({"type": 3, "start_date": 5}), null, "a type that is not text")
	t.eq(OWLens.date_of({"type": "constructor", "constructor": 5}), null, "a word that is no type")
	t.eq(OWLens.date_of({"type": "event", "known_of": true, "name": "A stub"}), null, "a stub serves no date")
	for v in [null, "event", 3, [{"type": "event", "start_date": 1}]]:
		t.eq(OWLens.date_of(v), null, var_to_str(v))
	t.done()

# -- the replay ---------------------------------------------------------------------------------------------------------

func _edges() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(EDGES))

## A fixture reader by name: its rung, its character, a guest's lists; [code]as[/code] (a reader's name in the
## fixture) is the owner reading as that reader.
func _reader(world: Dictionary, name: String) -> Dictionary:
	var r: Dictionary = world["readers"][name].duplicate(true)
	if r.has("as"):
		r["as"] = _reader(world, r["as"])
	return r

func _options(c: Dictionary) -> Dictionary:
	var o := {}
	if c.get("as_of") != null:
		o["as_of"] = c["as_of"]
	if c.get("clock") != null:
		o["clock"] = c["clock"]
	return o

func _resolve(world: Dictionary, c: Dictionary, reader: Dictionary) -> OWLens.Reading:
	return OWLens.resolve(world, c["lens"], reader, _options(c))

## A fixture value with every whole float as an int, so a count of 2.0 and a reading's 2 compare equal.
static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if OWLens.whole(v) != null else v
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out := []
			for x in v:
				out.append(_ints(x))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[k] = _ints(v[k])
			return out
	return v

func _names(world: Dictionary, ids: PackedStringArray) -> String:
	var by := {}
	for e in world["elements"]:
		by[e["id"]] = e.get("name")
	var out := PackedStringArray()
	for i in ids:
		out.append(str(by.get(i, i)))
	return ", ".join(out)

## The reading's keys the case names, compared as the fixture spells them (mail: only its keys the case names).
func _check(t, got: OWLens.Reading, want: Dictionary, world: Dictionary) -> void:
	t.eq(got.error, "", "no caller's mistake")
	var all: Dictionary = _ints(got.to_dict())
	for k in want:
		if k == "kept":
			t.eq(got.kept, PackedStringArray(want["kept"]), "kept [%s], want [%s]" % [_names(world, got.kept), _names(world, PackedStringArray(want["kept"]))])
		elif k == "mail" and want["mail"] != null and all["mail"] != null:
			for m in want["mail"]:
				t.eq(all["mail"].get(m), _ints(want["mail"][m]), "mail." + m)
		else:
			t.eq(all.get(k), _ints(want[k]), k)

func _resolves(t, c: Dictionary) -> void:
	var world: Dictionary = _fixture()["worlds"][c["world"]]
	var got := _resolve(world, c, _reader(world, c["reader"]))
	var want := {}
	for k in ["kept", "cut", "rows", "notes_ignored", "mail"]:
		if c.has(k):
			want[k] = c[k]
	t.eq(got.unreadable, null, "readable")
	_check(t, got, want, world)
	t.done()

func _edge(t, e: Dictionary) -> void:
	_check(t, _resolve(e["world"], e, e["reader"]), e["want"], e["world"])
	t.done()

func _holds(t, c: Dictionary) -> void:
	var world: Dictionary = _fixture()["worlds"][c["world"]]
	match c["claim"]:
		"subset":
			var owner := _resolve(world, c, _reader(world, "owner"))
			var secrets := PackedStringArray(c["secrets"])
			for e in world["elements"]:
				if PackedStringArray(c["secrets"]).has(e["id"]):
					secrets.append(e["name"])
			for r in c["readers"]:
				var reader := _reader(world, r)
				var got := _resolve(world, c, reader)
				for i in got.kept:
					t.ok(owner.kept.has(i), "%s keeps %s, which the owner does not" % [r, i])
				if world["readers"][r]["rung"] == "owner":
					continue
				var text := JSON.stringify(got.to_dict())
				for s in secrets:
					t.ok(not text.contains(s), "%s's reading names the secret %s" % [r, s])
				t.ok(owner.cut.is_empty() or owner.cut != got.cut, "%s's counts are the owner's" % r)
		"same_without":
			var without := PackedStringArray(c["without"])
			var less := world.duplicate(true)
			less["elements"] = world["elements"].filter(func(e): return not without.has(e["id"]))
			for r in c["readers"]:
				var a := JSON.stringify(_resolve(world, c, _reader(world, r)).to_dict())
				var b := JSON.stringify(_resolve(less, c, _reader(less, r)).to_dict())
				t.eq(b, a, "%s reads the same without %s" % [r, without])
		"unchanged":
			var before := JSON.stringify(world, "", false, true)
			for r in c["readers"]:
				_resolve(world, c, _reader(world, r))
			t.eq(JSON.stringify(world, "", false, true), before, "no reading moved the world")
		_:
			t.fail("a claim of unknown kind %s" % c["claim"])
	t.done()

func test_the_edge_file_is_the_packages(t) -> void:
	t.eq(FileAccess.get_sha256(EDGES), EDGES_SHA256, "npm 4.98.0's and the Python package 0.80.0's bytes")
	t.eq(_edges().size(), 15, "15 cases")
	t.done()

# -- beyond the fixture -------------------------------------------------------------------------------------------------

## The links a hop reads come from the generated models: single links and lists, never a scalar; the pin's generic
## link by its id key. The anchor fields are the Construct's link lists in the schema's order, less titles.
func test_the_link_fields_are_the_generated_models(t) -> void:
	var character := OWLens.link_fields_of("character")
	t.eq(character.filter(func(l): return not l[1]).map(func(l): return l[0]), ["birthplace", "location"], "the Character's single links")
	t.ok(character.has(["family", true]), "family is a list")
	t.ok(OWLens.link_fields_of("location").map(func(l): return l[0]).has("primary_power"), "a Location's primary_power")
	t.ok(not OWLens.link_fields_of("location").map(func(l): return l[0]).has("founding_date"), "a date is no link")
	t.ok(not OWLens.link_fields_of("zone").map(func(l): return l[0]).has("shape"), "a shape is no link")
	t.eq(OWLens.link_fields_of("pin"), [["map", false], ["element_id", false]], "the pin: map, and the generic link's id")
	t.eq(OWLens.link_fields_of("relation")[0], ["actor", false], "the Relation's actor first")
	t.eq(OWLens.link_fields_of("not-a-type"), [], "no type, no links")
	var lists := OWLens.link_fields_of("construct").filter(func(l): return l[1] and l[0] != "titles").map(func(l): return l[0])
	t.eq(lists, OWLens.ANCHOR_FIELDS, "the anchor fields are the Construct's link lists less titles")
	t.done()

## A stub's public fields are presentation.json's types.<type>.public, every type.
func test_the_stub_fields_are_the_presentations(t) -> void:
	var pres: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/presentation.json"))
	var want := {}
	for type in pres["types"]:
		var pub: Variant = pres["types"][type].get("public")
		if pub is Array and not pub.is_empty():
			want[type] = pub
	t.eq(want, OWLens.PUBLIC_FIELDS, "presentation.json's public fields")
	t.done()

func test_an_unreadable_lens_names_its_key_and_resolves_nothing(t) -> void:
	var vale: Dictionary = _fixture()["worlds"]["vale"]
	var lens := {"id": "L", "type": "construct", "supertype": "Lens", "characters": ["019a7f00-0000-7000-8000-000000000001"],
		"x_lens": {"depth": 3}}
	var got := OWLens.resolve(vale, lens, {"rung": "owner"})
	t.eq(got.unreadable, "depth", "the key refused")
	t.eq(got.kept, PackedStringArray(), "nothing kept")
	t.eq(got.cut, {}, "nothing cut")
	t.done()

## A doubt (any value but null in x_review_proposed) is in no reader's view, the owner's included.
func test_a_proposed_doubt_is_in_no_view(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "location": "p1"},
		{"id": "p1", "type": "location", "name": "Doubtful Keep", "x_review_proposed": "unsure"}]}
	var lens := {"id": "L", "type": "construct", "supertype": "Lens", "characters": ["c1"]}
	var got := OWLens.resolve(world, lens, {"rung": "owner"})
	t.eq(got.kept, PackedStringArray(["c1"]), "a doubt is not there to hop to")
	t.eq(got.cut, {"not_visible": 1}, "the owner counts it")
	t.done()

func test_an_element_of_no_standard_type_is_not_in_the_world(t) -> void:
	var world := {"elements": [{"id": "c1", "type": "character", "name": "Ada"}, {"id": "w1", "type": "widget"},
		{"id": "n1", "name": "No type"}, "not a body", {"id": 3, "type": "character"}]}
	var got := OWLens.resolve(world, {"id": "L", "type": "construct", "supertype": "Lens"}, {"rung": "owner"})
	t.eq(got.kept, PackedStringArray(["c1"]), "a filter keeps only the standard's types")
	t.done()

func test_an_element_that_is_not_a_lens_resolves_to_nothing(t) -> void:
	var world := {"elements": [{"id": "c1", "type": "character", "name": "Ada"}]}
	var got := OWLens.resolve(world, {"id": "k1", "type": "construct", "supertype": "Charter", "characters": ["c1"],
		"x_lens": {"depth": 9}}, {"rung": "owner"})
	t.eq(got.unreadable, null, "its x_lens is never read")
	t.eq(got.kept, PackedStringArray(), "nothing kept")
	t.done()

## The npm SDK 4.93.1's vector: a lens a guest knows only as a stub, named by its id, reads as nothing; whole, it reads.
func test_a_lens_a_guest_knows_only_as_a_stub_reads_as_nothing(t) -> void:
	var world := {"elements": [
		{"id": "L", "type": "construct", "name": "Ada and hers", "supertype": "Lens", "characters": ["c1"], "x_lens": {"depth": 1}},
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["c2"]},
		{"id": "c2", "type": "character", "name": "Bo"}]}
	var stub := OWLens.resolve(world, "L", {"rung": "guest", "whole": ["c1", "c2"], "known_of": ["L"]})
	t.eq(stub.kept, PackedStringArray(), "a stub lens keeps nothing")
	t.eq(stub.cut, {}, "and cuts nothing")
	t.eq(stub.unreadable, null, "a stub lens is not an unreadable one")
	t.eq(OWLens.resolve(world, "L", {"rung": "guest", "whole": ["L", "c1", "c2"]}).kept, PackedStringArray(["c1", "c2"]), "whole, it reads")
	t.done()

## A caller's mistake is no reading: the message names it, and nothing is resolved.
func test_a_callers_mistake_is_named(t) -> void:
	var world := {"elements": []}
	var lens := {"id": "L", "type": "construct", "supertype": "Lens"}
	t.ok(OWLens.resolve({"no": "elements"}, lens, {"rung": "owner"}).error.contains("world"), "a world without elements")
	t.ok(OWLens.resolve(world, lens, {"rung": "king"}).error.contains("rung"), "a rung outside the four")
	t.ok(OWLens.resolve(world, lens, {"rung": "owner", "as": {"rung": "x"}}).error.contains("rung"), "an as outside the four")
	t.ok(OWLens.resolve(world, 3, {"rung": "owner"}).error.contains("lens"), "a lens neither a body nor an id")
	t.ok(OWLens.resolve(world, lens, {"rung": "owner"}, {"as_of": 1.5}).error.contains("as_of"), "an as_of not whole")
	t.ok(OWLens.resolve(world, lens, {"rung": "owner"}, {"clock": "yesterday"}).error.contains("clock"), "a clock not a time")
	t.ok(OWLens.resolve(world, lens, {"rung": "owner"}, {"asOf": 3}).error.contains("asOf"), "an option it does not know")
	t.done()

# -- the reading aids and changed_within (the npm SDK 4.98.0's vectors; the Python package 0.80.0 holds the same) ------

const OWNER := {"rung": "owner"}
const CLOCK := "2026-10-27T12:00:00Z"

func _aids() -> Dictionary:
	return {"elements": [
		{"id": "desk", "type": "institution", "name": "The Desk", "constructs": ["domain", "guide"]},
		{"id": "rules", "type": "law", "name": "House Rules", "supertype": "Charter", "author": "desk", "x_charter_of": "w1"},
		{"id": "charter", "type": "law", "name": "Harbour Charter", "supertype": " charter ", "author": "desk"},
		{"id": "domain", "type": "construct", "name": "Reporting", "supertype": "Domain", "x_charter_of": "w1"},
		{"id": "guide", "type": "construct", "name": "How we work", "supertype": "GUIDE", "x_charter_of": "w1", "objects": ["ledger"]},
		{"id": "ledger", "type": "object", "name": "Ledger"}]}

func _lens_on(anchors: Dictionary, x_lens: Variant = null) -> Dictionary:
	var lens := {"id": "L", "type": "construct", "name": "L", "supertype": "Lens"}
	lens.merge(anchors)
	if x_lens != null:
		lens["x_lens"] = x_lens
	return lens

## Each pair word is a legal types word in any case and padding, and an element of the pair is an aid only with the mark.
func test_the_reading_aid_pairs_are_types_words_and_need_the_mark(t) -> void:
	for pair in OWLens.READING_AID_PAIRS:
		var lens := _lens_on({}, {"types": [" " + pair.to_upper() + " "]})
		t.eq(OWLens.resolve({"elements": []}, lens, OWNER).unreadable, null, pair)
		var words: PackedStringArray = pair.split("/")
		var el := {"id": "x", "type": words[0], "name": pair, "supertype": words[1].to_upper()}
		t.eq(OWLens.is_charter_element(el), false, "%s without the mark" % pair)
		var marked := el.duplicate()
		marked[OWLens.READING_AID_MARK] = "w1"
		t.eq(OWLens.is_charter_element(marked), true, "%s with the mark" % pair)
	t.done()

func test_is_charter_element_is_the_pair_and_the_mark(t) -> void:
	var els: Array = _aids()["elements"]
	t.eq(OWLens.is_charter_element(els[1]), true, "a marked Charter")
	t.eq(OWLens.is_charter_element(els[2]), false, "the pair without the mark: lore")
	t.eq(OWLens.is_charter_element(els[3]), true, "a marked Domain")
	t.eq(OWLens.is_charter_element(els[4]), true, "GUIDE, folded")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charters", "x_charter_of": "w1"}), false, "the whole word")
	t.eq(OWLens.is_charter_element({"type": "object", "supertype": "Charter", "x_charter_of": "w1"}), false, "not the pair")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charter", "x_charter_of": ""}), false, "an empty mark")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charter", "x_charter_of": " 　"}), false, "a blank mark")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charter", "x_charter_of": null}), false, "a null mark")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charter", "x_charter_of": 7}), true, "a number is a mark")
	t.eq(OWLens.is_charter_element({"type": "law", "supertype": "Charter", "x_room_of": "w1"}), false, "the room's mark is not this one")
	t.eq(OWLens.is_charter_element(null), false, "null")
	t.done()

func test_an_unmarked_charter_is_lore(t) -> void:
	var plain := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}), OWNER)
	t.eq(plain.kept, PackedStringArray(["desk", "charter"]), "a hop keeps it like any Law")
	t.eq(plain.cut, {"types": 3}, "the three aids cut")
	var laws := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}, {"types": ["law"]}), OWNER)
	t.eq(laws.kept, PackedStringArray(["desk", "charter"]), "types law keeps it")
	t.eq(laws.cut, {"types": 3}, "and cuts the aids")
	t.done()

func test_a_marked_domain_a_hop_reaches_is_cut_unless_its_pair_is_named(t) -> void:
	var none := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}, {"types": ["construct"]}), OWNER)
	t.eq(none.kept, PackedStringArray(["desk"]), "construct keeps no aid")
	t.eq(none.cut, {"types": 4}, "the three aids, and the lore Charter, a Law")
	var named := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}, {"types": [" Construct/Domain "]}), OWNER)
	t.eq(named.kept, PackedStringArray(["desk", "domain"]), "the pair named keeps the Domain")
	t.eq(named.cut, {"types": 3}, "the rest cut")
	# A hop does not continue out of an aid whose pair is not named: the Ledger, behind the Guide, is never reached.
	var deep := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}, {"depth": 2}), OWNER)
	t.eq(deep.cut, {"types": 3}, "no second hop out of an unnamed aid")
	var through := OWLens.resolve(_aids(), _lens_on({"institutions": ["desk"]}, {"depth": 2, "types": ["construct/guide", "institution"]}), OWNER)
	t.eq(through.cut, {"types": 3, "hops_not_served": 1}, "a named Guide is hopped out of")
	# In an unlensed graph the aids are out, whatever flag is asked; a lens naming the pair keeps them as nodes.
	var g := OWGraph.world_graph(_aids(), OWNER, {"rooms": true, "hidden": true, "proposed": true, "map_space": true})
	t.eq(g.nodes.map(func(n): return n["id"]), ["charter", "desk", "ledger"], "the graph's nodes")
	t.eq(g.cut, {"reading_aid": 3}, "the graph's cut")
	t.eq(g.edges_cut, {"reading_aid": 2}, "the Desk's links to the Domain and the Guide")
	t.eq(g.edges, [{"source": "charter", "field": "author", "target": "desk", "index": 0}], "the one edge")
	var lensed := OWGraph.world_graph(_aids(), OWNER, {"lens": _lens_on({"institutions": ["desk"]}, {"types": ["construct/domain", "institution"]})})
	t.eq(lensed.nodes.map(func(n): return [n["id"], n.get("marks")]), [["desk", null], ["domain", null]], "a lens naming the pair")
	t.done()

func test_an_anchor_that_is_a_marked_guide_is_kept_and_followed(t) -> void:
	var r := OWLens.resolve(_aids(), _lens_on({"constructs": ["guide"]}, {"types": ["object", "institution"]}), OWNER)
	t.eq(r.kept, PackedStringArray(["guide", "desk", "ledger"]), "whatever types says")
	t.eq(r.cut, {}, "nothing cut")
	var pub := OWLens.resolve(_aids(), _lens_on({"constructs": ["guide"]}), {"rung": "public"})
	t.eq(pub.kept, PackedStringArray(["guide", "desk", "ledger"]), "an aid is no room element: a public reader sees it")
	t.done()

func test_changed_within_keeps_the_exact_edge_and_never_cuts_an_anchor(t) -> void:
	var world := {"elements": [
		{"id": "a", "type": "institution", "name": "Anchor", "updated_at": "2020-01-01T00:00:00Z", "objects": ["edge", "past", "none", "bad"]},
		{"id": "edge", "type": "object", "name": "Seven days", "updated_at": "2026-10-20T12:00:00Z"},
		{"id": "past", "type": "object", "name": "Seven days and a second", "updated_at": "2026-10-20T11:59:59Z"},
		{"id": "none", "type": "object", "name": "No time"},
		{"id": "bad", "type": "object", "name": "Unreadable", "updated_at": "yesterday"}]}
	var lens := _lens_on({"institutions": ["a"]}, {"changed_within": 7})
	var r := OWLens.resolve(world, lens, OWNER, {"clock": CLOCK})
	t.eq(r.kept, PackedStringArray(["a", "edge", "bad", "none"]), "no readable time: never cut, sorted last")
	t.eq(r.cut, {"stale": 1}, "a second older is stale")
	world["elements"][2]["updated_at"] = "2026-10-20T13:00:00+01:00"
	t.eq(OWLens.resolve(world, lens, OWNER, {"clock": CLOCK}).cut, {}, "an offset is read: the same instant as the edge")
	var f := OWLens.resolve(world, _lens_on({}, {"types": ["object"], "changed_within": 1}), OWNER, {"clock": CLOCK})
	t.eq([f.kept, f.cut], [PackedStringArray(["bad", "none"]), {"stale": 2}], "a filter is cut too")
	for bad in [0, -1, 1.5, "7", true, [7]]:
		t.eq(OWLens.resolve(world, _lens_on({"institutions": ["a"]}, {"changed_within": bad}), OWNER).unreadable, "changed_within", var_to_str(bad))
	t.eq(OWLens.resolve(world, _lens_on({"institutions": ["a"]}, {"changed_within": null}), OWNER, {"clock": CLOCK}).unreadable, null, "null is absent")
	t.done()

func test_changed_within_reads_a_folder_element_by_the_newer_sync_stamp(t) -> void:
	var lens := _lens_on({"institutions": ["a"]}, {"changed_within": 7})
	var kept := func(stamps: Dictionary) -> bool:
		var o := {"id": "o", "type": "object", "name": "Folder copy"}
		o.merge(stamps)
		var world := {"elements": [{"id": "a", "type": "institution", "name": "Anchor", "objects": ["o"]}, o]}
		return OWLens.resolve(world, lens, OWNER, {"clock": CLOCK}).kept.has("o")
	t.eq(kept.call({"server_updated_at": "2026-09-01T00:00:00Z", "local_updated_at": "2026-10-26T00:00:00Z"}), true, "local newer")
	t.eq(kept.call({"server_updated_at": "2026-10-26T00:00:00Z", "local_updated_at": "2026-09-01T00:00:00Z"}), true, "server newer")
	t.eq(kept.call({"server_updated_at": "2026-09-01T00:00:00Z", "local_updated_at": "2026-09-02T00:00:00Z"}), false, "both old")
	t.eq(kept.call({"updated_at": "2026-10-26T00:00:00Z", "local_updated_at": "2026-09-02T00:00:00Z"}), false, "a folder stamp wins over updated_at")
	t.eq(kept.call({"updated_at": "2026-10-26T00:00:00Z", "local_updated_at": "soon"}), true, "an unreadable stamp is none")
	t.done()

# -- keel's reader, where the packages read otherwise (ruled keel's way; serial 83's fixture is to carry them) ---------

## Nothing past the reading's date leads anywhere: no hop goes out of an element cut after_as_of, an anchor or one a hop
## reached, and the owner's not_visible count does not look past it either (keel builds its frontier without it).
func test_no_hop_goes_out_of_an_element_cut_after_as_of(t) -> void:
	var world := {"elements": [
		{"id": "L", "type": "construct", "name": "L", "supertype": "Lens", "x_lens": {}, "events": ["e"]},
		{"id": "e", "type": "event", "name": "e", "start_date": 1300, "characters": ["c"]},
		{"id": "c", "type": "character", "name": "c"}]}
	var r := OWLens.resolve(world, "L", OWNER, {"as_of": 1200})
	t.eq(r.kept, PackedStringArray(), "the anchor after as_of links c, and c is not reached")
	t.eq(r.cut, {"after_as_of": 1}, "only the anchor is cut")
	world = {"elements": [
		{"id": "L", "type": "construct", "name": "L", "supertype": "Lens", "x_lens": {"depth": 2}, "characters": ["a"]},
		{"id": "a", "type": "character", "name": "a"},
		{"id": "e", "type": "event", "name": "e", "start_date": 1300, "characters": ["a", "c"]},
		{"id": "c", "type": "character", "name": "c"}]}
	r = OWLens.resolve(world, "L", OWNER, {"as_of": 1200})
	t.eq(r.kept, PackedStringArray(["a"]), "a reached element after as_of is cut")
	t.eq(r.cut, {"after_as_of": 1}, "and not hopped out of: c is not a second hop")
	world = {"elements": [
		{"id": "L", "type": "construct", "name": "L", "supertype": "Lens", "x_lens": {}, "events": ["e"]},
		{"id": "e", "type": "event", "name": "e", "start_date": 1300, "characters": ["h"]},
		{"id": "h", "type": "character", "name": "h", "hidden": true}]}
	r = OWLens.resolve(world, "L", {"rung": "owner", "as": {"rung": "contributor"}}, {"as_of": 1200})
	t.eq(r.cut, {"after_as_of": 1}, "the owner reading as a contributor: no not_visible behind the fenced anchor")
	t.done()

## hops_not_served never counts a room element or a reading aid that types would not keep; a lens that names the pair
## counts it.
func test_hops_not_served_counts_a_room_element_or_aid_only_when_types_would_keep_it(t) -> void:
	var world := {"elements": [
		{"id": "A", "type": "institution", "name": "The Desk", "allies": ["B"]},
		{"id": "B", "type": "institution", "name": "The Bindery"},
		{"id": "ch", "type": "law", "name": "House Rules", "supertype": "Charter", "author": "B", "x_charter_of": "w1"},
		{"id": "m", "type": "narrative", "name": "Memo", "supertype": "Message", "institutions": ["B"], "x_room_of": "w1"}]}
	var lens := _lens_on({"institutions": ["A"]}, {"depth": 2})
	var r := OWLens.resolve(world, lens, OWNER)
	t.eq(r.kept, PackedStringArray(["A", "B"]), "kept")
	t.eq(r.cut, {}, "the charter and the message at the second hop, which types would not keep, are not counted")
	lens = _lens_on({"institutions": ["A"]}, {"depth": 2, "types": ["institution", "law/charter"]})
	t.eq(OWLens.resolve(world, lens, OWNER).cut, {"hops_not_served": 1}, "a lens that names the aid's pair counts it")
	lens = _lens_on({"institutions": ["A"]}, {"depth": 2, "types": ["institution", "narrative/message"]})
	t.eq(OWLens.resolve(world, lens, OWNER).cut, {"hops_not_served": 1}, "a lens that names the room pair counts it")
	lens = _lens_on({"institutions": ["A"]}, {"depth": 2, "types": ["institution"]})
	world["elements"].append({"id": "o", "type": "event", "name": "Audit", "institutions": ["B"]})
	t.eq(OWLens.resolve(world, lens, OWNER).cut, {"hops_not_served": 1}, "lore of a type types would cut is still counted")
	t.done()
