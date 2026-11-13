extends RefCounted
## OWLens on the lens profile's conformance fixture (schema-dist profiles/lens.fixture.json, the pinned copy at
## dist.123, its sha256 checked against the manifest): the pair and the template, the legal values of x_lens, where a
## seat's choice lives, every resolution over the fixture's ten worlds and their readers, and the invariants. The
## graph kind is test_lens_graph.gd's. The profile's tables are held equal to the fixture's and to the generated models.

const P = preload("res://tests/paths.gd")
## The npm SDK's and the Python package's shared edge cases (npm 4.98.0's test/fixtures/lens-edges.json, byte for byte;
## both suites hold this sha256), answers written by hand.
const EDGES := "res://tests/data/lens-edges.json"
const EDGES_SHA256 := "4cb440cde85da877e2b5ba7129dd34be90a1e0bb109eefb56f0cae040a19b080"
## The two packages' shared row cases: a row is the body as keel serves that reader (keel elements/serialize.py and
## elements/visibility.py redact). The Python package's tests/fixtures/row-trim-cases.json at its commit 28b8ed5, byte
## for byte (the npm SDK's test/fixtures/row-trim-cases.json is the same file; both suites hold this sha256), answers
## written by hand.
const ROW_TRIM := "res://tests/data/row-trim-cases.json"
const ROW_TRIM_SHA256 := "8365cf7c1364e8d04f2143824ba4cb19f275935d3a602178fb2ed497bf6fe140"

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
	for c in _row_trims():
		out.append(["row-trim:" + c["name"], _row_trim.bind(c)])
	for c in _room()["cases"]:
		out.append(["room:" + c["name"], _in_room.bind(c)])
	return out

## The room profile's own fixture (profiles/room.fixture.json): each case's element is a room element exactly when
## in_room says, the pair AND the mark.
func _room() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/profiles/room.fixture.json"))

func _in_room(t, c: Dictionary) -> void:
	t.eq(OWLens._is_room_element(c["element"]), c["in_room"], "in_room")
	t.done()

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
	t.eq(_fixture()["cases"].size(), 233, "233 cases")
	t.eq(counts, {"shape": 6, "keys": 25, "resolve": 133, "invariant": 4, "uses": 5, "graph": 55, "degree": 5}, "by kind")
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

## The room pairs as the room profile's own fixture spells them, folded: the same ten, in its order.
func test_the_room_pairs_are_the_room_profiles(t) -> void:
	var room: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/profiles/room.fixture.json"))
	var words := []
	for p in room.get("pairs", []):
		words.append(OWUnicode.profile_fold(p["type"]) + "/" + OWUnicode.profile_fold(p["supertype"]))
	t.eq(words, OWLens.ROOM_PAIRS, "the room fixture's pairs")
	t.eq(room["mark"]["field"], OWLens.ROOM_MARK, "the room fixture's mark")
	t.eq(room["cases"].size(), 35, "35 room cases")
	t.done()

## The profiles' fold is trim then simple case folding, never NFC: a decomposed e and acute stays two code points.
func test_profile_fold_is_trim_and_simple_fold(t) -> void:
	t.eq(OWUnicode.profile_fold(" Lens　"), "lens", "White_Space trimmed, ASCII folded")
	t.eq(OWUnicode.profile_fold("﻿Lens"), "﻿lens", "a byte order mark is not white space")
	t.eq(OWUnicode.profile_fold("K"), "k", "the Kelvin sign folds to k (an S row)")
	t.eq(OWUnicode.profile_fold("É"), "é", "no NFC: the decomposed pair stays decomposed")
	t.eq(OWUnicode.profile_fold("ẞ"), "ß", "capital sharp s folds to sharp s (S row), never ss (F row)")
	t.done()

## A whole number: an int, or a float with no fraction that a double holds exactly (within 2^53 - 1, JavaScript's
## isSafeInteger). Godot's JSON reads every number as a float, so past 2^53 a parse may have rounded it.
func test_whole(t) -> void:
	t.eq(OWLens.whole(7), 7, "an int")
	t.eq(OWLens.whole(7.0), 7, "7.0 is whole")
	t.eq(OWLens.whole(-40.0), -40, "-40.0 is whole")
	t.eq(OWLens.whole(-0.0), 0, "-0.0 is 0")
	t.eq(OWLens.whole(JSON.parse_string("[7]")[0]), 7, "a JSON 7 as Godot parses it")
	t.eq(OWLens.whole(JSON.parse_string("[7.0]")[0]), 7, "a JSON 7.0")
	for v in [1.5, NAN, INF, -INF, 9223372036854775808.0, -9223372036854775808.0 * 2.0, 1e300, true, false, "12", null, [3], {"year": 3}]:
		t.eq(OWLens.whole(v), null, "not whole: %s" % var_to_str(v))
	# float(int), not a float literal: GDScript's parser reads the literal 9007199254740991.0 as ...990 (Godot 4.7.2).
	t.eq(OWLens.whole(float(9007199254740991)), 9007199254740991, "2^53 - 1 is the last float a double holds exactly")
	t.eq(OWLens.whole(float(-9007199254740991)), -9007199254740991, "and its negative")
	for v in [float(9007199254740992), float(-9007199254740992), -9223372036854775808.0]:
		t.eq(OWLens.whole(v), null, "past 2^53 - 1 a float is not whole: %s" % var_to_str(v))
	for s in ["-9223372036854775809", "9223372036854775807", "9007199254740993"]:
		t.eq(OWLens.whole(JSON.parse_string("[" + s + "]")[0]), null, "a JSON %s, rounded by the parse, is not whole" % s)
	t.eq(OWLens.whole(9223372036854775807), 9223372036854775807, "an int is exact at any 64-bit value")
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

func _row_trims() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(ROW_TRIM))

## One row case: the rows alone, as the reader is served them, compared whole.
func _row_trim(t, c: Dictionary) -> void:
	var got := OWLens.resolve(c["world"], c["lens"], c["reader"])
	t.eq(got.error, "", "no caller's mistake")
	t.eq(_ints(got.rows), _ints(c["want_rows"]), "rows")
	t.done()

func test_the_row_trim_file_is_the_packages(t) -> void:
	t.eq(FileAccess.get_sha256(ROW_TRIM), ROW_TRIM_SHA256, "the Python package's 28b8ed5 bytes, the npm SDK's too")
	t.eq(_row_trims().size(), 28, "28 cases")
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

## A doubt (any value present in x_review_proposed, not only a mark) is in no reader's view, the owner's included.
## The owner's row is still the body as stored (keel serves the owner with no viewer, so nothing is redacted): its link
## to the doubt stays.
func test_a_proposed_doubt_is_in_no_view(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "location": "p1"},
		{"id": "p1", "type": "location", "name": "Doubtful Keep", "x_review_proposed": "unsure"}]}
	var lens := {"id": "L", "type": "construct", "supertype": "Lens", "characters": ["c1"]}
	var got := OWLens.resolve(world, lens, {"rung": "owner"})
	t.eq(got.kept, PackedStringArray(["c1"]), "a doubt is not there to hop to")
	t.eq(got.cut, {"not_visible": 1}, "the owner counts it")
	t.eq(got.rows, [world["elements"][0]], "the owner's row keeps its link to the doubt")
	t.done()

## The review profile's rule 1 (serial 87): the mark is read by presence, and an empty one ("", White_Space only, [] or
## {}) is settled, never a doubt; keel's proposals/marked.py `empty` and `doubt_or_mark`. U+FEFF is not White_Space, so
## a string of it is a doubt; so are a number, false and a list with an entry.
func test_an_empty_review_mark_is_settled(t) -> void:
	var marks := {"e_obj": {}, "e_list": [], "e_str": "", "e_ws": " \t　\u0085", "d_str": "unsure",
		"d_bom": "﻿", "d_zero": 0, "d_false": false, "d_list": ["x"], "d_mark": {"by": "m1"}}
	var friends := []
	var els := []
	for id in marks:
		friends.append(id)
		els.append({"id": id, "type": "character", "name": id, "x_review_proposed": marks[id]})
	els.push_front({"id": "c1", "type": "character", "name": "Ada", "friends": friends})
	var lens := {"id": "L", "type": "construct", "supertype": "Lens", "characters": ["c1"], "x_lens": {"depth": 1}}
	for rung in ["owner", "contributor"]:
		var got := OWLens.resolve({"elements": els}, lens, {"rung": rung})
		t.eq(got.kept, PackedStringArray(["c1", "e_list", "e_obj", "e_str", "e_ws"]), rung + ": an empty mark is in view")
		t.eq(got.cut, {"not_visible": 6} if rung == "owner" else {}, rung + ": the doubts are not, counted for the owner")
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
	# In an unlensed graph the aids are out whatever other flag is asked, and reading_aids brings them back, marked
	# (serial 104); a lens naming the pair keeps them as nodes, marked too.
	var g := OWGraph.world_graph(_aids(), OWNER, {"rooms": true, "hidden": true, "proposed": true, "map_space": true})
	t.eq(g.nodes.map(func(n): return n["id"]), ["charter", "desk", "ledger"], "the graph's nodes")
	t.eq(g.cut, {"reading_aid": 3}, "the graph's cut")
	t.eq(g.edges_cut, {"reading_aid": 2}, "the Desk's links to the Domain and the Guide")
	t.eq(g.edges, [{"source": "charter", "field": "author", "target": "desk", "index": 0}], "the one edge")
	var back := OWGraph.world_graph(_aids(), OWNER, {"reading_aids": true})
	t.eq(back.nodes.map(func(n): return [n["id"], n.get("marks")]),
		[["charter", null], ["desk", null], ["domain", ["reading_aid"]], ["guide", ["reading_aid"]], ["ledger", null],
		["rules", ["reading_aid"]]], "reading_aids: the three aids back, each marked, the lore Charter unmarked")
	t.eq(back.cut, {}, "nothing cut")
	t.eq(back.edges_cut, {}, "no edge cut")
	var lensed := OWGraph.world_graph(_aids(), OWNER, {"lens": _lens_on({"institutions": ["desk"]}, {"types": ["construct/domain", "institution"]})})
	t.eq(lensed.nodes.map(func(n): return [n["id"], n.get("marks")]), [["desk", null], ["domain", ["reading_aid"]]],
		"a lens naming the pair keeps the Domain, marked")
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
	t.eq(kept.call({"updated_at": "2026-10-26T00:00:00Z", "local_updated_at": "2026-09-02T00:00:00Z"}), true, "updated_at newer than the folder stamp")
	t.eq(kept.call({"updated_at": "2026-09-02T00:00:00Z", "local_updated_at": "2026-10-26T00:00:00Z"}), true, "the folder stamp newer than updated_at")
	t.eq(kept.call({"updated_at": "2026-10-26T00:00:00Z", "local_updated_at": "soon"}), true, "an unreadable stamp is none")
	t.done()

## One clock per lens (the lens page, serial 123): rule 5's order reads the clock changed_within reads, the element's
## clock, the newest of its readable updated_at, server_updated_at and local_updated_at. A filter over objects with
## budget 1 keeps the one sorted first; e2 is stamped 10-20 on the wire, e1 by the stamps given; no changed_within, so
## nothing is cut stale and the order alone decides.
func test_rule_5_orders_by_the_clock_changed_within_reads(t) -> void:
	var lens := _lens_on({}, {"types": ["object"], "budget": 1})
	var first := func(stamps: Dictionary) -> String:
		var e1 := {"id": "e1", "type": "object", "name": "Folder copy"}
		e1.merge(stamps)
		var world := {"elements": [e1, {"id": "e2", "type": "object", "name": "Wire copy",
			"updated_at": "2026-10-20T12:00:00Z"}]}
		var kept := OWLens.resolve(world, lens, OWNER, {"clock": CLOCK}).kept
		return kept[0] if kept.size() == 1 else "kept " + str(kept)
	t.eq(first.call({"updated_at": "2026-10-25T12:00:00Z"}), "e1", "the wire: updated_at")
	t.eq(first.call({"updated_at": "2026-10-15T12:00:00Z"}), "e2", "the wire: an older updated_at")
	t.eq(first.call({"server_updated_at": "2026-10-25T12:00:00Z"}), "e1", "only server, newer")
	t.eq(first.call({"local_updated_at": "2026-10-25T12:00:00Z"}), "e1", "only local, newer")
	t.eq(first.call({"server_updated_at": "2026-10-15T12:00:00Z", "local_updated_at": "2026-10-25T12:00:00Z"}), "e1",
		"the newer of the two")
	t.eq(first.call({"updated_at": "2026-10-15T12:00:00Z", "server_updated_at": "2026-10-25T12:00:00Z"}), "e1",
		"a folder stamp over an older updated_at")
	t.eq(first.call({"updated_at": "2026-10-25T12:00:00Z", "server_updated_at": "2026-10-15T12:00:00Z"}), "e1",
		"a newer updated_at over an older folder stamp")
	t.eq(first.call({"updated_at": "2026-10-25T12:00:00Z", "local_updated_at": "2026-10-15T12:00:00Z"}), "e1",
		"a newer updated_at over an older local stamp")
	t.eq(first.call({"updated_at": "2026-10-25T12:00:00Z", "server_updated_at": "garbage"}), "e1",
		"an unreadable folder stamp is none: updated_at read")
	t.eq(first.call({"server_updated_at": "garbage"}), "e2", "no readable clock sorts last")
	t.done()

## The element's clock is the newest of its three readable stamps, decided element by element (serial 123, the second
## outside read's two cases, built here on their own strings). First: a family's budget of 2 over its two languages;
## Peatspeech's updated_at (11-05) is newer than both its folder stamps (10-01, 10-02), so its clock is 11-05 and it
## is kept over Turfcant (11-01). A folder-first clock reads Peatspeech at 10-02 and keeps Turfcant.
## Second: changed_within 7 at 2026-11-20T12:00Z (the line at 11-13); Mossspeech's local edit (11-18) and Lichencant's
## wire stamp (11-18) are each newer than the element's other stamp (10-01), so both are kept. updated_at alone cuts
## Mossspeech stale; a folder-first clock cuts Lichencant stale.
## Third: an element with no readable clock comes last of its type, not of the budget: the ability (whose type comes
## before language in the schema's order) is kept over the language with a clock.
func test_the_clock_is_the_newest_of_the_three_readable_stamps(t) -> void:
	var peat := {"elements": [
		{"id": "k00", "type": "family", "name": "The Peat Kin", "languages": ["k01", "k02"], "updated_at": "2026-11-01T12:00:00Z"},
		{"id": "k01", "type": "language", "name": "Peatspeech", "server_updated_at": "2026-10-01T12:00:00Z",
			"local_updated_at": "2026-10-02T12:00:00Z", "updated_at": "2026-11-05T12:00:00Z"},
		{"id": "k02", "type": "language", "name": "Turfcant", "updated_at": "2026-11-01T12:00:00Z"}]}
	var a := OWLens.resolve(peat, _lens_on({"families": ["k00"]}, {"budget": 2}), OWNER, {"clock": CLOCK})
	t.eq([a.kept, a.cut], [PackedStringArray(["k00", "k01"]), {"budget": 1}], "an updated_at newer than both folder stamps")
	var moss := {"elements": [
		{"id": "k10", "type": "family", "name": "The Moss Kin", "languages": ["k11", "k12"], "updated_at": "2026-11-01T12:00:00Z"},
		{"id": "k11", "type": "language", "name": "Mossspeech", "updated_at": "2026-10-01T12:00:00Z",
			"local_updated_at": "2026-11-18T12:00:00Z"},
		{"id": "k12", "type": "language", "name": "Lichencant", "server_updated_at": "2026-10-01T12:00:00Z",
			"updated_at": "2026-11-18T12:00:00Z"}]}
	var b := OWLens.resolve(moss, _lens_on({"families": ["k10"]}, {"changed_within": 7}), OWNER,
		{"clock": "2026-11-20T12:00:00Z"})
	var kept_b := Array(b.kept)
	kept_b.sort()
	t.eq([kept_b, b.cut], [["k10", "k11", "k12"], {}], "a local edit and a wire stamp, each newer, both kept")
	var rush := {"elements": [
		{"id": "k20", "type": "family", "name": "The Rush Kin", "abilities": ["k21"], "languages": ["k22"], "updated_at": "2026-11-01T12:00:00Z"},
		{"id": "k21", "type": "ability", "name": "Rushweaving", "local_updated_at": "soon"},
		{"id": "k22", "type": "language", "name": "Rushcant", "updated_at": "2026-11-01T12:00:00Z"}]}
	var c := OWLens.resolve(rush, _lens_on({"families": ["k20"]}, {"budget": 2}), OWNER, {"clock": CLOCK})
	t.eq([c.kept, c.cut], [PackedStringArray(["k20", "k21"]), {"budget": 1}], "no readable clock: last of its type, not of the budget")
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

## A mark (x_room_of, x_charter_of) counts by presence: any value but null; a string only when something is left after
## trimming Unicode's White_Space (25 code points, so a lone U+001F is a mark); the value is never compared.
func test_a_mark_counts_by_presence(t) -> void:
	var message := func(mark: Variant, has: bool = true) -> Dictionary:
		var el := {"id": "m", "type": "narrative", "name": "Memo", "supertype": "Message"}
		if has:
			el["x_room_of"] = mark
		return el
	for mark in ["w1", 7, 0, false, true, {"a": 1}, [], "\u001f", "​", "﻿", " w1 "]:
		t.eq(OWLens._is_room_element(message.call(mark)), true, "x_room_of %s is a mark" % var_to_str(mark))
	for mark in ["", "  ", " 　\u0085 \t\n", null]:
		t.eq(OWLens._is_room_element(message.call(mark)), false, "x_room_of %s is no mark" % var_to_str(mark))
	t.eq(OWLens._is_room_element(message.call(null, false)), false, "no x_room_of is no mark")
	var charter := func(mark: Variant) -> Dictionary:
		return {"id": "k", "type": "law", "name": "Rules", "supertype": "Charter", "x_charter_of": mark}
	for mark in ["w1", 7, 0, false, {"a": 1}, "\u001f", "﻿"]:
		t.eq(OWLens.is_charter_element(charter.call(mark)), true, "x_charter_of %s is a mark" % var_to_str(mark))
	for mark in ["", "  ", " 　", null]:
		t.eq(OWLens.is_charter_element(charter.call(mark)), false, "x_charter_of %s is no mark" % var_to_str(mark))
	# Through a reader: a room element is out of a public reader's view and out of an unlensed graph.
	var world := {"elements": [
		{"id": "a", "type": "narrative", "name": "Seven", "supertype": "Message", "x_room_of": 7},
		{"id": "b", "type": "narrative", "name": "Blank", "supertype": "Message", "x_room_of": "  "},
		{"id": "c", "type": "narrative", "name": "Unit separator", "supertype": "Message", "x_room_of": "\u001f"}]}
	t.eq(OWLens.resolve(world, _lens_on({}), {"rung": "public"}).kept, PackedStringArray(["b"]), "the public reader sees only the lore")
	t.eq(OWGraph.world_graph(world, OWNER).cut, {"room": 2}, "an unlensed graph leaves two room elements out")
	t.done()

## A whole float in an x_lens key reads whole, as an element's date reads 7.0 as 7 (the profile's ruling 13); what is
## refused is a fraction, NaN, infinity, a number past 64 bits. Godot's JSON reads a 7 and a 7.0 alike (both a float),
## as the TypeScript SDK's does.
func test_x_lens_numbers_as_godot_can_see_them(t) -> void:
	t.eq(typeof(JSON.parse_string("[7.0]")[0]), typeof(JSON.parse_string("[7]")[0]), "Godot's JSON: 7 and 7.0 are one type")
	t.eq(OWLens.check_keys(JSON.parse_string("{\"depth\": 2.0, \"changed_within\": 7.0}")), null, "a JSON 2.0 reads as 2")
	for key in ["depth", "window", "from", "budget", "changed_within"]:
		for v in [1.5, NAN, INF, 1e300]:
			t.eq(OWLens.check_keys({key: v}), key, "%s %s is refused" % [key, var_to_str(v)])
	t.eq(OWLens.check_keys({"from": 1, "to": 2.5}), "to", "to 2.5 is refused")
	t.eq(OWLens.date_of({"type": "event", "start_date": 7.0}), 7, "an element's date reads 7.0 as 7")
	t.done()

# -- the umbrella's children, each by its own recipe (keel's reading) --------------------------------------------------

## An umbrella U over one child K: U's x_lens and K's x_lens and anchors as given, three Characters to point at.
func _umbrella(u: Dictionary, k: Dictionary) -> Dictionary:
	var umbrella := {"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "constructs": ["K"]}
	umbrella.merge(u)
	var child := {"id": "K", "type": "construct", "name": "K", "supertype": "Lens"}
	child.merge(k)
	return {"elements": [umbrella, child,
		{"id": "a", "type": "character", "name": "Ada", "description": "First line.\nSecond line."},
		{"id": "b", "type": "character", "name": "Brin"},
		{"id": "c", "type": "character", "name": "Cass"}]}

## A child keeps at most its own budget, the rest counted budget, before the union; the umbrella's budget caps on top.
func test_an_umbrella_child_keeps_at_most_its_own_budget(t) -> void:
	var k := {"characters": ["a", "b", "c"], "x_lens": {"depth": 0, "budget": 2}}
	var r := OWLens.resolve(_umbrella({"x_lens": {"depth": 0}}, k), "U", OWNER)
	t.eq(r.kept, PackedStringArray(["a", "b"]), "the child's capped set")
	t.eq(r.cut, {"budget": 1}, "Cass, past the child's budget")
	# The child's budget counts what the umbrella already holds: K keeps Ada and Brin, and Ada is the umbrella's own.
	var own := OWLens.resolve(_umbrella({"characters": ["a"], "x_lens": {"depth": 0}}, k), "U", OWNER)
	t.eq(own.kept, PackedStringArray(["a", "b"]), "Ada once, then Brin")
	t.eq(own.cut, {"budget": 1}, "Cass still cut by the child")
	var both := OWLens.resolve(_umbrella({"x_lens": {"depth": 0, "budget": 1}}, k), "U", OWNER)
	t.eq(both.kept, PackedStringArray(["a"]), "the umbrella's budget on top")
	t.eq(both.cut, {"budget": 2}, "Brin by the umbrella, Cass by the child")
	t.done()

## show is the umbrella's alone: a row kept through a child is built by the umbrella's recipe.
func test_an_umbrella_child_row_shows_by_the_umbrellas_recipe(t) -> void:
	var world := _umbrella({"x_lens": {"depth": 0, "show": "full"}}, {"characters": ["a"], "x_lens": {"depth": 0, "show": "name"}})
	t.eq(OWLens.resolve(world, "U", OWNER).rows, [world["elements"][2]], "full under a full umbrella")
	world = _umbrella({"x_lens": {"depth": 0, "show": "name"}}, {"characters": ["a"], "x_lens": {"depth": 0, "show": "full"}})
	t.eq(OWLens.resolve(world, "U", OWNER).rows, [{"id": "a", "type": "character", "name": "Ada"}], "name under a name umbrella")
	t.done()

## A child's note is the child's recipe too: a row kept through a child carries none (the umbrella builds the rows).
func test_an_umbrella_child_note_does_not_ride(t) -> void:
	var world := _umbrella({"x_lens": {"depth": 0}}, {"characters": ["a"], "x_lens": {"depth": 0, "notes": {"a": "Why Ada."}}})
	var r := OWLens.resolve(world, "U", OWNER)
	t.eq(r.rows, [world["elements"][2]], "no note on Ada's row")
	t.eq(r.notes_ignored, 0, "the child's note is not the umbrella's to count")
	t.done()

## A child's own mail rule takes its mail out of the child's kept before the union, though the umbrella names no mail
## rule: the messages go nowhere (the child's mail part is not served), and nothing is counted.
func test_an_umbrella_child_mail_rule_takes_its_messages_out(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["post"].duplicate(true)
	world["elements"].append({"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "constructs": ["M"], "x_lens": {"depth": 0}})
	world["elements"].append({"id": "M", "type": "construct", "name": "M", "supertype": "Lens",
		"x_lens": {"types": ["narrative"], "mail": "unread_full_read_titles"}})
	var r := OWLens.resolve(world, "U", world["readers"]["seat"], {"clock": CLOCK})
	# M alone: the filter selects the five Narratives the seat sees; its mail part takes the three of the last thirty
	# days addressed to Ada, leaving her own reply and the summer letter.
	t.eq(r.kept, PackedStringArray(["019a7f00-0000-7000-8000-000000000037", "019a7f00-0000-7000-8000-000000000036"]),
		"kept [%s]" % _names(world, r.kept))
	t.eq(r.mail, null, "the umbrella names no mail rule")
	t.eq(r.cut, {}, "nothing counted")
	t.done()

# -- the profile owner's rulings on readings no fixture case decided yet (each a case in the fixture's next serial) ----

## Ruling 1: a link reaches only an element of its field's target type. Ada's species names a Location and an Event's
## locations names Ada: neither is a hop, either way. Her location is.
func test_ruling_1_a_link_reaches_only_its_fields_target_type(t) -> void:
	var world := {"elements": [_lens_on({"characters": ["a"]}),
		{"id": "a", "type": "character", "name": "Ada", "species": ["port"], "location": "home"},
		{"id": "port", "type": "location", "name": "Port"},
		{"id": "home", "type": "location", "name": "Home"},
		{"id": "fair", "type": "event", "name": "Fair", "locations": ["a"]}]}
	var r := OWLens.resolve(world, "L", OWNER)
	t.eq(r.kept, PackedStringArray(["a", "home"]), "Ada and her location only")
	t.eq(r.cut, {}, "a wrongly typed id is no hop, so nothing to count")
	t.done()

## Ruling 2: a generic pair links only when its type key names one of the 22, and then only to an element of that type.
func test_ruling_2_a_generic_pair_links_only_by_one_of_the_22(t) -> void:
	var world := {"elements": [_lens_on({"characters": ["a"]}),
		{"id": "a", "type": "character", "name": "Ada"},
		{"id": "p1", "type": "pin", "name": "Dragon pin", "element_type": "dragon", "element_id": "a"},
		{"id": "p2", "type": "pin", "name": "Ada's pin", "element_type": "character", "element_id": "a"},
		{"id": "p3", "type": "pin", "name": "Wrong pin", "element_type": "location", "element_id": "a"},
		{"id": "p4", "type": "pin", "name": "Bare pin", "element_id": "a"}]}
	var r := OWLens.resolve(world, "L", OWNER)
	t.eq(r.kept, PackedStringArray(["a", "p2"]), "only the pin whose pair names a Character")
	t.done()

## The generic pair's type key compares exact against the 22 slugs, as stored, nothing folded: a stored "Character" or
## " character " links nothing, and a reader below the owner is served that pair unset.
func test_ruling_a_a_generic_pairs_type_key_compares_exact(t) -> void:
	var world := {"elements": [_lens_on({"characters": ["a"]}),
		{"id": "a", "type": "character", "name": "Ada"},
		{"id": "p1", "type": "pin", "name": "Capital pin", "element_type": "Character", "element_id": "a"},
		{"id": "p2", "type": "pin", "name": "Ada's pin", "element_type": "character", "element_id": "a"},
		{"id": "p3", "type": "pin", "name": "Spaced pin", "element_type": " character ", "element_id": "a"}]}
	t.eq(OWLens.resolve(world, "L", OWNER).kept, PackedStringArray(["a", "p2"]), "only the pin whose type key is the slug as written")
	var served := OWLens.View.new(world, {"rung": "contributor"}, null)
	for pin in ["p1", "p3"]:
		var b: Dictionary = served.body(pin)
		t.eq([b.get("element_type"), b.get("element_id")], ["", null], pin + ": served an unset pair")
	t.eq(served.body("p2").get("element_id"), "a", "the slug as written is served whole")
	t.done()

## Ruling 3: an anchor id no element holds is counted for the owner as anchor_not_visible, never skipped; so is one of
## another type than its field's. Below the owner nothing is counted.
func test_ruling_3_a_dangling_anchor_is_counted_for_the_owner(t) -> void:
	var world := {"elements": [_lens_on({"characters": ["a", "ghost", "port"]}, {"depth": 0}),
		{"id": "a", "type": "character", "name": "Ada"},
		{"id": "port", "type": "location", "name": "Port"}]}
	var r := OWLens.resolve(world, "L", OWNER)
	t.eq(r.kept, PackedStringArray(["a"]), "Ada")
	t.eq(r.cut, {"anchor_not_visible": 2}, "the missing id and the Location under characters")
	t.eq(OWLens.resolve(world, "L", {"rung": "contributor"}).cut, {}, "a contributor is not told")
	# The lens's own id under characters is no lens of the reading (keel keys an anchor by its field's type): counted too.
	world["elements"][0]["characters"] = ["L", "a"]
	r = OWLens.resolve(world, "L", OWNER)
	t.eq(r.kept, PackedStringArray(["a"]), "never in its own result")
	t.eq(r.cut, {"anchor_not_visible": 1}, "the lens's id under characters")
	t.done()

## Ruling 4: an umbrella's children are not in its hop's known set: a child its anchors reach by a hop is kept as an
## element before it is entered.
func test_ruling_4_a_child_the_umbrellas_hop_reaches_is_kept(t) -> void:
	var world := _umbrella({"characters": ["a"]}, {"characters": ["a"], "x_lens": {"depth": 0}})
	var r := OWLens.resolve(world, "U", OWNER)
	t.eq(r.kept, PackedStringArray(["a", "K"]), "Ada, then K by the hop (Ada is K's anchor), then K's own Ada once")
	t.eq(r.cut, {}, "nothing cut")
	t.done()

## Ruling 5: a lens id a child cut before it was entered stays counted in the cut; a later visit never erases a count.
func test_ruling_5_a_cut_lens_id_stays_cut_once_entered(t) -> void:
	var world := {"elements": [
		{"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "constructs": ["K1", "K2"], "x_lens": {"depth": 0}},
		{"id": "K1", "type": "construct", "name": "K1", "supertype": "Lens", "characters": ["a"], "x_lens": {"types": ["location"]}},
		{"id": "K2", "type": "construct", "name": "K2", "supertype": "Lens", "characters": ["a"], "x_lens": {"depth": 0}},
		{"id": "a", "type": "character", "name": "Ada"}]}
	var r := OWLens.resolve(world, "U", OWNER)
	t.eq(r.kept, PackedStringArray(["a"]), "Ada, through both children")
	t.eq(r.cut, {"types": 1}, "K2, cut by K1's types before U entered it")
	t.done()

## Ruling 7: a known-of stub is shaped as keel serves it: the base and public fields kept (a public link redacted to
## what the reader sees), every other field at its unset value, extension keys dropped, known_of true.
func test_ruling_7_a_stub_keeps_base_and_public_and_unsets_the_rest(t) -> void:
	var world := {"elements": [_lens_on({"characters": ["s"]}, {"depth": 0}),
		{"id": "s", "type": "character", "name": "Sable", "description": "Quiet.", "supertype": "Smith", "change_seq": 5,
			"physicality": "Tall", "height": 180, "species": ["sp1", "sp2"], "mentality": "Calm", "background": "Secret.",
			"birth_date": 12, "birthplace": "loc", "friends": ["sp1"], "x_custom": "kept nowhere", "created_by": "m1"},
		{"id": "sp1", "type": "species", "name": "Elves"},
		{"id": "sp2", "type": "species", "name": "Hidden kin"},
		{"id": "loc", "type": "location", "name": "Forge"}]}
	var r := OWLens.resolve(world, "L", {"rung": "guest", "whole": ["L", "sp1"], "known_of": ["s"]})
	t.eq(r.rows, [{"id": "s", "type": "character", "name": "Sable", "description": "Quiet.", "supertype": "Smith",
		"change_seq": 5, "physicality": "Tall", "height": 180, "species": ["sp1"], "mentality": "", "background": "",
		"birth_date": null, "birthplace": null, "friends": [], "created_by": null, "known_of": true}], "keel's stub")
	t.done()

## A single link stored as "" is served as stored to every reader below the owner: "", never null, and never named in
## x_served_trimmed, since no id was left out (keel's redact strips only an id the reader cannot see). A Message whose
## narrator is "" claims no hidden sender.
func test_an_empty_single_link_is_served_as_stored_and_never_marked_trimmed(t) -> void:
	var world := {"elements": [
		{"id": "o1", "type": "object", "name": "Cup", "language": ""},
		{"id": "c1", "type": "character", "name": "Ada"},
		{"id": "m1", "type": "narrative", "supertype": "Message", "name": "Hi", "narrator": "", "characters": ["c1"]},
		_lens_on({"objects": ["o1"], "narratives": ["m1"]}, {"depth": 0})]}
	for reader in [{"rung": "contributor"}, {"rung": "guest", "whole": ["o1", "c1", "m1", "L"]}, {"rung": "public"}]:
		var view := OWLens.View.new(world, reader, null)
		for pair in [["m1", "narrator"], ["o1", "language"]]:
			var b: Dictionary = view.body(pair[0])
			t.eq(b.get(pair[1]), "", "%s: %s.%s served as \"\"" % [reader["rung"], pair[0], pair[1]])
			t.ok(not b.has(OWLens.SERVED_TRIMMED), "%s: %s carries no trimmed mark" % [reader["rung"], pair[0]])
		var rows: Array = OWLens.resolve(world, "L", reader).rows.filter(func(r): return r["id"] == "m1")
		t.eq(rows.size(), 1, "%s: the message is kept" % reader["rung"])
		t.eq(rows[0].get("narrator"), "", "%s: the kept message's narrator" % reader["rung"])
		t.ok(not rows[0].has(OWLens.SERVED_TRIMMED), "%s: the kept message claims no hidden sender" % reader["rung"])
	t.done()

## Ruling 11, as the profile's owner reversed it: two messages with one created_at keep the order of the list they came
## in, as the message profile rules, never by id. A tie listed in reverse id order stays as listed.
func test_ruling_11_a_mail_tie_keeps_the_lists_order(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["post"].duplicate(true)
	var els: Array = world["elements"]
	var i34 := els.find(els.filter(func(e): return e["id"].ends_with("0034"))[0])
	var i35 := els.find(els.filter(func(e): return e["id"].ends_with("0035"))[0])
	var night: Dictionary = els[i35]
	night["created_at"] = els[i34]["created_at"]
	night["updated_at"] = els[i34]["updated_at"]
	els.remove_at(i35)
	els.insert(i34, night)
	var lens := {"id": "M", "type": "construct", "name": "M", "supertype": "Lens", "x_lens": {"types": ["narrative/message"], "mail": "all"}}
	var r := OWLens.resolve(world, lens, world["readers"]["seat"], {"clock": CLOCK})
	t.eq(r.mail["unread"], ["019a7f00-0000-7000-8000-000000000035", "019a7f00-0000-7000-8000-000000000034"],
		"Night shift, then Notes to self: as the world lists them, never by id")
	t.done()

## An empty string is no id, so a lens whose anchor fields hold only empty strings names no anchor and is a filter, as
## rule 7 reads a lens with empty lists. One real id beside them anchors it, and a served lens whose x_served_trimmed
## names an anchor field stays anchored. Guards what this reader already does. Kills: [""] read as naming an anchor.
func test_a_lens_whose_anchor_fields_hold_only_empty_strings_names_no_anchor_and_is_a_filter(t) -> void:
	var world := {"elements": [{"id": "e03", "type": "law", "name": "Law"}, {"id": "a", "type": "character", "name": "Ada"}]}
	t.eq(OWLens.resolve(world, _lens_on({"narratives": [""]}, {}), OWNER).kept, PackedStringArray(["a", "e03"]), "a filter")
	t.eq(OWLens.resolve(world, _lens_on({"characters": ["", ""], "laws": [""]}, {}), {"rung": "public"}).kept,
		PackedStringArray(["a", "e03"]), "a filter, for any reader")
	t.eq(OWLens.resolve(world, _lens_on({"characters": ["", "a"]}, {}), OWNER).kept, PackedStringArray(["a"]), "one id anchors it")
	t.eq(OWLens.resolve(world, _lens_on({"narratives": [""], "x_served_trimmed": ["narratives"]}, {}), OWNER).kept,
		PackedStringArray(), "an anchor field the server trimmed still names an anchor")
	t.done()

## A row is the body as the wire serves it to that reader, and a served body of an element under the hidden mark
## carries hidden: true: the owner's full row of a hidden element, by the world's list or by its own key; below the
## owner only a guest's row of its own hidden creation. A name row never carries it. The world stays as it was. Kills:
## the row as stored.
func test_an_owners_full_row_of_a_hidden_element_carries_hidden_true_as_served(t) -> void:
	var world := {"hidden": ["e05"], "elements": [
		{"id": "e05", "type": "collective", "name": "Guild"},
		{"id": "e06", "type": "collective", "name": "Choir", "hidden": true},
		_lens_on({}, {})]}
	var before := JSON.stringify(world)
	t.eq(OWLens.resolve(world, "L", OWNER).rows, [
		{"id": "e05", "type": "collective", "name": "Guild", "hidden": true},
		{"id": "e06", "type": "collective", "name": "Choir", "hidden": true}], "the world's list and the element's own key, one mark")
	t.eq(OWLens.resolve(world, "L", {"rung": "guest", "whole": ["L", "e05"]}).rows,
		[{"id": "e05", "type": "collective", "name": "Guild", "hidden": true}], "a guest's own hidden creation")
	world["elements"][2]["x_lens"] = {"show": "name"}
	t.ok(not OWLens.resolve(world, "L", OWNER).rows[0].has("hidden"), "a name row")
	world["elements"][2]["x_lens"] = {}
	t.eq(JSON.stringify(world), before, "the world is not changed")
	t.done()

## The lens profile's first-line rule (schema-dist serial 115): trimming White_Space decides which line is the first
## that holds something; the line itself is carried as stored, its leading spaces kept; a description with no such line
## gives no description key. The npm package's eight cases ([code]test/lens.test.mjs[/code], 4.153.0) and the Python
## package's ([code]tests/test_lens.py[/code], 0.116.0), the same inputs and answers ([code]null[/code]: no key).
func test_a_first_line_row_carries_the_first_line_holding_something_as_stored(t) -> void:
	var cases := [
		["plain", "One.\nTwo.", "One."],
		["a leading break, then spaces", "\n  Rung for every crossing.\nMore.", "  Rung for every crossing."],
		["blank lines first, CRLF", "\r\n \t\r\n" + String.chr(0xA0) + "\r\nThird.\r\nFourth.", "Third."],
		["a carriage return alone", "\rAfter the return.", "After the return."],
		["one line with spaces", "  Only line  ", "  Only line  "],
		["blank lines only", "\n \n\t\r\n", null],
		["White_Space alone", " " + String.chr(0x3000) + " ", null],
		["empty", "", null],
	]
	for c in cases:
		var world := {"elements": [
			{"id": "a", "type": "institution", "name": "Anchor", "objects": ["o"]},
			{"id": "o", "type": "object", "name": "Ledger", "description": c[1]}]}
		var rows: Array = OWLens.resolve(world, _lens_on({"institutions": ["a"]}, {"show": "first_line"}), OWNER).rows
		var row: Dictionary = {}
		for r in rows:
			if r["id"] == "o":
				row = r
		t.ok(not row.is_empty(), "%s: the row" % c[0])
		t.eq(row.has("description"), c[2] != null, "%s: the key" % c[0])
		t.eq(row.get("description"), c[2], c[0])
	t.done()

## keel serves no hidden key on a body no mark hides, so a stored hidden: false is dropped from the row, for the owner
## and every reader below it. Kills: the stored key carried onto the row.
func test_a_stored_hidden_false_is_dropped_from_the_row(t) -> void:
	var world := {"elements": [{"id": "e05", "type": "collective", "name": "Guild", "hidden": false}, _lens_on({}, {})]}
	for reader in [OWNER, {"rung": "contributor"}, {"rung": "guest", "whole": ["L", "e05"]}, {"rung": "public"}]:
		t.eq(OWLens.resolve(world, "L", reader).rows, [{"id": "e05", "type": "collective", "name": "Guild"}], reader["rung"])
	t.done()

## The cut counts each element once under its first reason, and a kept element is never also counted as cut; an anchor
## resolves by its field's type and the id. One id an umbrella and its child anchor under two wrong types (a Location
## under characters, then objects) is one element, counted once; one the umbrella anchors under the wrong type and the
## child under its own is kept and not counted, and so the other way round. Guards what this reader already does (it
## keys the cut by id). Kills: the cut keyed by (type, id).
func test_the_cut_counts_each_element_once_and_a_kept_element_is_never_also_cut(t) -> void:
	var harbour := {"id": "x", "type": "location", "name": "Harbour"}
	var read := func(u: Dictionary, k: Dictionary) -> OWLens.Reading:
		var umbrella := {"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "constructs": ["C"], "x_lens": {"depth": 0}}
		umbrella.merge(u)
		var child := {"id": "C", "type": "construct", "name": "C", "supertype": "Lens", "x_lens": {"depth": 0}}
		child.merge(k)
		return OWLens.resolve({"elements": [child, harbour]}, umbrella, OWNER)
	var r: OWLens.Reading = read.call({"characters": ["x"]}, {"objects": ["x"]})
	t.eq([r.kept, r.cut], [PackedStringArray(), {"anchor_not_visible": 1}], "one element, once")
	r = read.call({"characters": ["x"]}, {"locations": ["x"]})
	t.eq([r.kept, r.cut], [PackedStringArray(["x"]), {}], "kept by the child, so never also cut")
	r = read.call({"locations": ["x"]}, {"characters": ["x"]})
	t.eq([r.kept, r.cut], [PackedStringArray(["x"]), {}], "kept by the umbrella, the child's wrong type not counted")
	t.done()

## Counts are per reader: below the owner an element whose owner-side reason was anchor_not_visible (a Location the
## umbrella names under characters) and which a child cuts by types is counted under the child's reason; for the owner
## anchor_not_visible comes first and it is counted once there. Kills: the unseen anchor recorded for every reader and
## dropped at the count.
func test_below_the_owner_an_unseen_anchor_a_cut_child_reaches_is_counted_under_the_childs_reason(t) -> void:
	var world := {"elements": [
		{"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "characters": ["x"], "constructs": ["C"], "x_lens": {"depth": 0}},
		{"id": "C", "type": "construct", "name": "C", "supertype": "Lens", "characters": ["y"], "x_lens": {"types": ["character"]}},
		{"id": "y", "type": "character", "name": "Ysolde", "birthplace": "x"},
		{"id": "x", "type": "location", "name": "Harbour"}]}
	var contributor := OWLens.resolve(world, "U", {"rung": "contributor"})
	t.eq(contributor.kept, PackedStringArray(["y"]), "Ysolde")
	t.eq(contributor.cut, {"types": 1}, "the child's reason")
	t.eq(OWLens.resolve(world, "U", {"rung": "public"}).cut, {"types": 1}, "the public reader's too")
	t.eq(OWLens.resolve(world, "U", OWNER).cut, {"anchor_not_visible": 1}, "the owner's first reason, once")
	t.done()

## A note goes with its anchor: an anchor that reaches nothing (a Language named under constructs) carries its note onto
## no row, even where another path (a child filter) keeps the element, for the owner and below it; and the note is not
## counted ignored. Kills: an unseen id among the anchors whose notes ride.
func test_a_note_goes_with_its_anchor_an_anchor_that_reaches_nothing_carries_it_onto_no_row(t) -> void:
	var world := {"elements": [
		{"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "constructs": ["e08", "L1"], "x_lens": {"notes": {"e08": "the old tongue"}}},
		{"id": "L1", "type": "construct", "name": "L1", "supertype": "Lens", "x_lens": {}},
		{"id": "e08", "type": "language", "name": "Old"}]}
	for reader in [OWNER, {"rung": "contributor"}]:
		var r := OWLens.resolve(world, "U", reader)
		t.eq(r.kept, PackedStringArray(["e08"]), "%s: kept by the child" % reader["rung"])
		t.ok(r.rows.size() == 1 and not r.rows[0].has("note"), "%s: no note rides" % reader["rung"])
		t.eq(r.notes_ignored, 0, "%s: a note on an anchor is never counted ignored" % reader["rung"])
	t.done()

## Visited never comes before visibility, for any anchor: a hidden lens in its own constructs, read as a body through a
## contributor's view, counts itself for the owner as anchor_not_visible; so does a child lens pointing back at its
## hidden umbrella, its own objects kept. Guards what this reader already does. Kills: an anchor already visited skipped
## before it is counted.
func test_an_unseen_anchor_is_counted_before_the_visited_check_the_lens_itself_included(t) -> void:
	var as_contributor := {"rung": "owner", "as": {"rung": "contributor"}}
	var self_lens := {"id": "L0", "type": "construct", "name": "L0", "supertype": "Lens", "hidden": true, "constructs": ["L0"], "x_lens": {}}
	t.eq(OWLens.resolve({"elements": [self_lens]}, self_lens, as_contributor).cut, {"anchor_not_visible": 1}, "the lens's own id")
	var umbrella := {"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "hidden": true, "constructs": ["C"], "x_lens": {"depth": 0}}
	var world := {"elements": [umbrella,
		{"id": "C", "type": "construct", "name": "C", "supertype": "Lens", "constructs": ["U"], "objects": ["o1"], "x_lens": {"depth": 0}},
		{"id": "o1", "type": "object", "name": "Cup"}]}
	var r := OWLens.resolve(world, umbrella, as_contributor)
	t.eq(r.kept, PackedStringArray(["o1"]), "the child's own objects")
	t.eq(r.cut, {"anchor_not_visible": 1}, "the hidden umbrella, once")
	t.done()

## Hidden beats known_of: a hidden element named in a guest's known_of that is not its own creation is not in that
## guest's view, so no stub, no row, no count and no mark; a hidden id in whole stays its own creation. A filter keeps
## nothing of it; an anchor on it is one the guest cannot see, counted only for the owner reading as that guest; a link
## to it is left out of the guest's served list (no gap). Kills: the hidden element kept as a stub.
func test_a_hidden_element_in_a_guests_known_of_is_not_in_its_view_no_stub_no_row_no_count_no_mark(t) -> void:
	var world := {"elements": [
		{"id": "e05", "type": "character", "name": "Heir", "hidden": true},
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["e05", "e06"]},
		{"id": "e06", "type": "character", "name": "Brin"},
		{"id": "F", "type": "construct", "name": "F", "supertype": "Lens", "x_lens": {"types": ["character"]}},
		{"id": "A", "type": "construct", "name": "A", "supertype": "Lens", "characters": ["e05"], "x_lens": {"depth": 0}}]}
	var guest := {"rung": "guest", "whole": ["F", "A", "c1", "e06"], "known_of": ["e05"]}
	var filter := OWLens.resolve(world, "F", guest)
	t.eq(filter.kept, PackedStringArray(["c1", "e06"]), "a filter keeps no stub of it")
	t.eq(filter.cut, {}, "nothing counted")
	var anchored := OWLens.resolve(world, "A", guest)
	t.eq([anchored.kept, anchored.cut], [PackedStringArray(), {}], "no stub row, nothing counted for the guest")
	t.eq(OWLens.resolve(world, "A", {"rung": "owner", "as": guest}).cut, {"anchor_not_visible": 1},
		"the owner reading as the guest counts the anchor")
	var view := OWLens.View.new(world, guest, null)
	t.ok(not view.view.has("e05"), "not in the guest's view")
	t.eq(view.body("c1")["friends"], ["e06"], "left out of the guest's served list")
	var own := OWLens.resolve(world, "F", {"rung": "guest", "whole": ["F", "e05"]}).rows
	t.eq(own.size() == 1 and own[0].get("hidden") == true, true, "a hidden id in whole stays its own creation, marked")
	t.done()
