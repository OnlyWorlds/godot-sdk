extends RefCounted
## OWViews on views.json's conformance fixture (schema-dist views.fixture.json at the dist's root since serial 113,
## version 2 since serial 114; the pinned copies, their sha256 checked against the manifest): the baked table is the
## file, every case gives its row, its sentence, its banners and, where it names one, its order (a case that names a
## table of the fixture's own reads against that table, through OWViews._view_in), and the fixture's cites name fields
## their rows name and their types have, each quote at its line of the vendored page. Beside the fixture, the
## TypeScript SDK's own tests (test/views.test.mjs, 4.152.0) and the Unity SDK's vectors for what version 2 states
## (OWViewsTests, 628418d).

const VIEWS := "res://codegen/schema-dist/views.json"
const FIXTURE := "res://codegen/schema-dist/views.fixture.json"
const DIST := "res://codegen/schema-dist/"
const WORLD := "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e0f"

var _fx: Dictionary
var _doc: Dictionary

func _fixture() -> Dictionary:
	if _fx.is_empty():
		_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _fx

func _the_file() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["views:" + c["name"], _case.bind(c)])
	return out

## The answer as a case writes it: [code]order[/code] only where the case gives one (the fixture's first note).
func _answer(v: OWViews.View, with_order: bool) -> Dictionary:
	var a := {"row": v.row["id"] if v.row != null else null, "sentence": v.sentence, "banners": Array(v.banners)}
	if with_order:
		a["order"] = Array(v.order)
	return a

func _case(t, c: Dictionary) -> void:
	var want: Dictionary = c["expect"]
	var v: OWViews.View
	if c.has("table"):
		var table: Variant = _fixture().get("tables", {}).get(c["table"])
		if not (table is Dictionary):
			t.fail("%s names the table %s, which the fixture does not hold" % [c["name"], c["table"]])
			t.done()
			return
		v = OWViews._view_in(table, c["element"])
	else:
		v = OWViews.view_of(c["element"])
		if v.row != null:
			t.ok(is_same(v.row, _table_row(v.row["id"])), "the row is the table's own row")
	t.eq(_answer(v, want.has("order")), want, c["name"])
	t.done()

func _table_row(id: String) -> Variant:
	for r in OWViews.ROWS:
		if r["id"] == id:
			return r
	return null

func test_the_files_are_the_pinned_ones(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIST + "MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(FIXTURE), manifest["views.fixture.json"], "the fixture's bytes are the dist's")
	t.eq(FileAccess.get_sha256(VIEWS), manifest["views.json"], "views.json's bytes are the dist's")
	t.eq(OWViews.SHA256, manifest["views.json"], "the baked table is the pinned views.json's: regenerate with codegen/generate.py")
	t.done()

func test_the_table_is_the_file_the_banners_the_layouts_and_every_row(t) -> void:
	var doc := _the_file()
	t.eq(doc["_meta"]["version"], 2.0, "the vendored file is version 2")
	t.eq(OWViews.VERSION, 2, "the baked table is version 2")
	t.eq(OWViews.BANNERS, doc["banners"], "the banners, in the file's order")
	t.eq(OWViews.LAYOUTS, doc["layouts"], "the layouts")
	t.eq(OWViews.ROWS, doc["rows"], "every row, as the file writes it")
	t.ok(OWViews.ROWS.size() > 0, "a table with no rows would pass every case that wants no row")
	t.ok(OWViews.ROWS.is_read_only() and OWViews.BANNERS.is_read_only(), "the table is read-only")
	for r in OWViews.ROWS:
		t.ok(r.is_read_only(), "row %s is read-only" % r["id"])
		for k in r:
			t.ok(k in ["id", "kind", "from", "sentence", "lead", "fold", "layout", "banner"], "row %s carries a column OWViews does not read: %s" % [r["id"], k])
	t.done()

func test_the_fixture_holds_dist114s_cases_and_every_row_is_reached(t) -> void:
	var f := _fixture()
	t.eq(f["views"], "views.json", "the fixture's table")
	var cases: Array = f["cases"]
	t.eq(cases.size(), 41, "dist.114's fixture holds 41 cases")
	var own := cases.filter(func(c): return not c.has("table"))
	t.eq(cases.size() - own.size(), 2, "two cases read a table of the fixture's own")
	t.eq(own.filter(func(c): return c["expect"].has("order")).size(), 5, "five of the file's own cases name an order")
	var seen := {}
	for c in own:
		var v := OWViews.view_of(c["element"])
		if v.row != null:
			seen[v.row["id"]] = true
	for r in OWViews.ROWS:
		t.ok(seen.has(r["id"]), "no case reaches the row " + r["id"])
	t.done()

## The fixture's third note: each cite names a field its row names, each field a row names has a cite, each is a field
## of the row's type in the standard (a base field included), and each quote is at its line of the vendored page (the
## page split at LF, the line 1-based), as codegen/generate.py checks them before it bakes the table.
func test_the_cites_name_fields_their_rows_name_and_their_types_have_each_quote_at_its_line(t) -> void:
	var cites: Array = _fixture()["cites"]
	t.eq(cites.size(), 10, "dist.114's fixture holds 10 cites")
	var named := {}
	var type_of := {}
	for r in OWViews.ROWS:
		var kind: Dictionary = r["kind"]
		type_of[r["id"]] = kind["pair"].split("/")[0] if kind.has("pair") else kind["type"]
		for f in r.get("sentence", []) + r.get("lead", []):
			named[r["id"] + "." + f] = true
		for f in r.get("fold", []):
			named[r["id"] + "." + f["field"]] = true
		if r["layout"].has("by"):
			named[r["id"] + "." + r["layout"]["by"]] = true
	var cited := {}
	for c in cites:
		var key: String = c["row"] + "." + c["field"]
		t.ok(named.has(key), "the cite of %s names a field its row does not name" % key)
		var slug: String = type_of.get(c["row"], "")
		var fields := []
		if OWTypes.SCRIPTS.has(slug):
			fields = OWTypes.SCRIPTS[slug].get_script_constant_map()["FIELDS"].keys() + OWElement.BASE_FIELDS.keys()
		t.ok(fields.has(c["field"]), "%s: not a field of %s" % [key, slug])
		var page := FileAccess.get_file_as_string(DIST + c["page"])
		var lines := page.split("\n")
		var line := int(c["line"])
		t.ok(page != "" and line >= 1 and line <= lines.size() and lines[line - 1].contains(c["quote"]),
			"%s: the quote is not at %s:%d" % [key, c["page"], line])
		cited[key] = true
	for k in named:
		t.ok(cited.has(k), "a field a row names has no cite: " + k)
	t.done()

# -- beside the fixture (the TypeScript SDK's own tests) ---------------------------------------------------------------

func test_anything_that_is_not_an_element_has_no_row_no_sentence_no_banners_and_no_fields(t) -> void:
	var none := {"row": null, "sentence": null, "banners": [], "order": []}
	for bad in [null, 1, "narrative", [], true, {}]:
		t.eq(OWViews.view_of(bad).to_dict(), none, var_to_str(bad))
	t.done()

## The fixture's carriage-return case is CRLF, which a cut at the line feed alone also passes (the trim takes the CR
## left behind); a lone CR tells the two apart.
func test_the_sentence_is_cut_at_a_lone_carriage_return_as_at_a_line_feed(t) -> void:
	for story in ["One.\rTwo.", "One.\nTwo.", "  \r\n One. \rTwo."]:
		t.eq(OWViews.view_of({"type": "narrative", "supertype": "Message", "story": story}).sentence, "One.", story.c_escape())
	t.done()

func test_each_answer_is_its_own_and_the_row_cannot_be_changed(t) -> void:
	var el := {"type": "narrative", "supertype": "Message", "story": "Hello.", "hidden": true}
	var first := OWViews.view_of(el)
	t.eq(first.banners, PackedStringArray(["hidden"]), "the banners")
	first.banners.append("changed")
	first.order.append("changed")
	t.eq(OWViews.view_of(el).banners, PackedStringArray(["hidden"]), "a caller changing one answer changes no later one")
	t.eq(OWViews.view_of(el).order, PackedStringArray(["story"]), "nor its order")
	t.ok(first.row is Dictionary and first.row.is_read_only(), "the row is the table's own, read-only")
	t.eq(OWViews.view_of(el).to_dict(), {"row": "message", "sentence": "Hello.", "banners": ["hidden"], "order": ["story"]}, "to_dict")
	t.done()

# -- the Unity SDK's vectors for what version 2 states -----------------------------------------------------------------

func _row(id: String, kind: Dictionary, banner: Array = []) -> Dictionary:
	var r := {"id": id, "kind": kind, "from": "a test", "sentence": ["story"], "lead": [], "layout": {"name": "document"}}
	if not banner.is_empty():
		r["banner"] = banner
	return r

func _table(rows: Array) -> Dictionary:
	return {"banners": OWViews.BANNERS, "rows": rows}

## The file's words (version 2's [code]banners[/code] sentence): a row's own [code]banner[/code] marks are "each read by
## presence as the room profile reads a mark: not null, a string only when something is left after trimming, any other
## value counts".
func test_a_rows_own_banner_mark_is_read_by_presence_the_files_words(t) -> void:
	var table := _table([_row("noted", {"type": "character"}, ["x_note"])])
	var vectors := [["\"" + WORLD + "\"", true], ["\"  \"", false], ["\"\"", false], ["7", true], ["false", true],
		["{}", true], ["null", false]]
	for vec in vectors:
		var el := {"type": "character", "x_note": JSON.parse_string(vec[0])}
		var v := OWViews._view_in(table, el)
		t.eq(v.to_dict()["row"], "noted", vec[0])
		t.eq(v.banners, PackedStringArray(["x_note"]) if vec[1] else PackedStringArray(), vec[0])
	t.eq(OWViews._view_in(table, {"type": "character"}).banners, PackedStringArray(), "an absent mark is no banner")
	t.done()

## The file's words (version 2's [code]match[/code] sentence): two rows on one kind are a fault "refused where it is
## built", and "a reader drawing a page never refuses over the table: where two rows match on one rung, the first in the
## file wins". The fixture's faulty-table-first-row-wins holds the same with its own table.
func test_a_tie_on_one_rung_the_first_row_wins_the_files_words(t) -> void:
	var el := {"type": "narrative", "supertype": "Message", "story": "Hi."}
	var a := _row("first", {"type": "narrative", "supertype": "Message"})
	var b := _row("second", {"type": "Narrative", "supertype": " message "})
	t.eq(OWViews._view_in(_table([a, b]), el).to_dict()["row"], "first", "a, b")
	t.eq(OWViews._view_in(_table([b, a]), el).to_dict()["row"], "second", "b, a")
	var plain := _row("plain", {"type": "narrative"})
	t.eq(OWViews._view_in(_table([plain, a]), el).to_dict()["row"], "first", "a higher rung still wins from later in the table")
	t.done()

## The file's words (version 2's [code]banners[/code] sentence): [code]x_served_trimmed[/code] shows "only when it names a
## field (its list holds at least one string with something left after trimming: a list of blanks shows no banner)".
func test_served_trimmed_is_a_banner_only_when_it_names_a_field_the_files_words(t) -> void:
	var vectors := [["[\"characters\"]", true], ["[\"narrator\", \"characters\"]", true], ["[\" \", \"characters\"]", true],
		["[]", false], ["[\"\"]", false], ["[\" \\t\", \"\\u3000\"]", false], ["[42]", false], ["[null]", false],
		["\"characters\"", false]]
	for vec in vectors:
		var el := {"type": "narrative", "supertype": "Message", "story": "Hi.", "x_served_trimmed": JSON.parse_string(vec[0])}
		t.eq(OWViews.view_of(el).banners, PackedStringArray(["x_served_trimmed"]) if vec[1] else PackedStringArray(), vec[0])
	t.done()

## The order's section fields are the walk's: for every type they are the generated model's FIELDS (the same walk) in the
## same order, but for the Pin, whose generic link the schema lists once as [code]element[/code] and a body carries as
## [code]element_type[/code] and [code]element_id[/code].
func test_the_section_fields_are_the_walks_in_its_order_the_pins_generic_link_as_the_schema_lists_it(t) -> void:
	t.eq(Array(OWViews.SECTION_FIELDS.keys()), Array(OWTypes.slugs()), "the 22 slugs, in the schema's order")
	for slug in OWTypes.slugs():
		var want := []
		for f in OWTypes.SCRIPTS[slug].get_script_constant_map()["FIELDS"]:
			if slug == "pin" and f == "element_id":
				continue
			want.append("element" if slug == "pin" and f == "element_type" else f)
		t.eq(OWViews.SECTION_FIELDS[slug], want, slug)
	t.done()

## The file names the schema's fields as listed, and a Pin's is [code]element[/code], which no served body holds: it
## carries [code]element_type[/code] and [code]element_id[/code]. So a Pin's page draws no element, as the TypeScript
## SDK (ELEMENT_SECTIONS.pin names element) and the Unity SDK read it today. A known open point: when the file says the
## generic link is drawn at element's place as its two keys, this test and SECTION_FIELDS follow.
func test_a_pins_generic_link_is_no_field_its_body_holds_so_its_page_draws_no_element(t) -> void:
	var pin := {"type": "pin", "name": "The ferry", "map": "m1", "element_type": "location", "element_id": "l1", "x": 0, "y": 12}
	t.eq(OWViews.view_of(pin).order, PackedStringArray(["map", "x", "y"]), "the order")
	t.done()

## What holds something, field by field, beside the fixture's cases: a number (zero too) and a boolean (false too) hold
## it; a list of blank strings holds something here, whatever a banner reads of one; White_Space alone (U+3000 too) and
## an object with no keys hold nothing. The type is folded as the room profile folds it.
func test_a_field_holds_something_by_the_files_test(t) -> void:
	var el := {"type": " Character ", "physicality": "\u3000 ", "mentality": [" "], "height": 0, "weight": false,
		"species": [], "background": {}, "motivations": {"a": 1}, "birthplace": null,
		"x_note": "an extension key is in no order", "name": "Sol", "description": "a base field is the page's head"}
	t.eq(OWViews.view_of(el).order, PackedStringArray(["mentality", "height", "weight", "motivations"]), "the order")
	t.done()
