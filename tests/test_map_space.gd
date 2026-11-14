extends RefCounted
## OWMapSpace on the map space profile's conformance fixture (schema-dist profiles/map-space.fixture.json, the pinned
## copy at dist.127, its sha256 checked against the manifest): every case by name, the whole answer compared by value
## and as bytes, key order included. Beside it, what the fixture leaves open in Godot: the same rows given as ints,
## a boolean that is no number, a whole value past the reader's int range, the page's reading A, a caller's mistake,
## rows that are no element, and a reading that never moves the elements.

const MAP_SPACE := "res://codegen/schema-dist/profiles/map-space.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(MAP_SPACE))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["map_space:" + c["name"], _case.bind(c)])
	for c in _fixture().get("layout_cases", []):
		out.append(["layout_of:" + c["name"], _layout_case.bind(c)])
	return out

## Godot's JSON reads every number as a float; the fixture's coordinates and counts are whole numbers, its scales not.
static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if OWLens.whole(v) != null else v
		TYPE_ARRAY:
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

func _case(t, c: Dictionary) -> void:
	var want: Dictionary = _ints(c["want"])
	var a := OWMapSpace.map_space(c["elements"])
	t.eq(a.error, "", "no caller's mistake")
	var got := a.to_dict()
	for k in want:
		t.eq(got.get(k), want[k], k)
	# sort_keys false: JSON.stringify sorts a Dictionary's keys by default, which would hide the order.
	t.eq(JSON.stringify(got, "", false), JSON.stringify(want, "", false), "byte for byte, key order included")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(MAP_SPACE), manifest["profiles/map-space.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "map-space", "the profile")
	t.eq(f["profile_page"], "profiles/map-space.md", "its page")
	t.eq(f["cases"].size(), 39, "39 cases (34 at dist.106, 35 at dist.119)")
	var names := {}
	for c in f["cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 39, "each case named once")
	t.ok(names.has("layout-map-read-as-before"), "dist.119's case: a layout map read as any Map (rule 11)")
	t.done()

## Every answer holds its four keys in order, a Map row its eight (and extent only when measured), every coordinate
## and count is an int, and the same elements give the same bytes.
func test_four_keys_in_order_ints_and_the_same_bytes(t) -> void:
	for c in _fixture()["cases"]:
		var a := OWMapSpace.map_space(c["elements"]).to_dict()
		t.eq(a.keys(), ["maps", "zones", "pins", "out"], c["name"] + ": the keys")
		for m in a["maps"]:
			var keys: Array = ["id", "width", "height", "depth", "z_max", "scale", "location", "parent_map"]
			if m.has("extent"):
				keys.append("extent")
			t.eq(m.keys(), keys, c["name"] + ": a Map's keys")
			for k in ["width", "height", "depth", "z_max"]:
				t.ok(m[k] == null or typeof(m[k]) == TYPE_INT, c["name"] + ": a Map's " + k)
		for o in a["zones"]:
			t.eq(o.keys(), ["zone", "map", "shape", "points"], c["name"] + ": an outline's keys")
			for p in o["points"]:
				t.ok(p.size() == 3 and p.all(func(n): return typeof(n) == TYPE_INT), c["name"] + ": a point of three ints")
		for p in a["pins"]:
			t.eq(p.keys(), ["pin", "map", "element_type", "element_id", "x", "y", "z"], c["name"] + ": a Pin's keys")
			t.ok([p["x"], p["y"], p["z"]].all(func(n): return typeof(n) == TYPE_INT), c["name"] + ": a Pin's ints")
		for k in a["out"]:
			t.eq(typeof(a["out"][k]), TYPE_INT, c["name"] + ": a count")
		t.eq(JSON.stringify(OWMapSpace.map_space(c["elements"]).to_dict()), JSON.stringify(a), c["name"] + ": stable")
	t.done()

## The same rows with their whole numbers given as ints, as a caller's own code builds them, read the same.
func test_ints_read_as_the_floats_json_gives(t) -> void:
	for c in _fixture()["cases"]:
		t.eq(JSON.stringify(OWMapSpace.map_space(_ints(c["elements"])).to_dict()),
			JSON.stringify(OWMapSpace.map_space(c["elements"]).to_dict()), c["name"])
	t.done()

## A boolean is no number anywhere (Godot keeps true apart from 1): an x leaves the row out, a z reads 0, an order
## reads missing, a width is measured.
func test_a_boolean_is_no_number(t) -> void:
	var els := [
		{"type": "map", "id": "m", "width": true, "height": 10},
		{"type": "zone", "id": "z"},
		{"type": "marker", "id": "a", "zone": "z", "map": "m", "x": 2, "y": 3, "z": true, "order": true},
		{"type": "marker", "id": "b", "zone": "z", "map": "m", "x": 4, "y": 5, "order": 0},
		{"type": "marker", "id": "c", "zone": "z", "map": "m", "x": true, "y": 3},
		{"type": "pin", "id": "p", "map": "m", "x": 7, "y": 1}]
	var a := OWMapSpace.map_space(els).to_dict()
	t.eq(a["zones"], [{"zone": "z", "map": "m", "shape": "polygon", "points": [[4, 5, 0], [2, 3, 0]]}],
		"z true reads 0, order true after the ordered one")
	t.eq(a["out"], {"no_point": 1}, "x true is no point")
	t.eq(a["maps"][0]["width"], 7, "width true is measured from the points")
	t.eq(a["maps"][0]["extent"], "points", "and says so")
	t.done()

## A whole value past this reader's integer range, the range a double holds exactly (2^53 - 1), reads as not whole
## (the page's platform sentence, serial 106; the fixture keeps every number within 2^53, so no case holds it): as x it
## leaves the row out, as z it reads 0, as order it reads missing, as width the width is measured.
func test_a_whole_value_past_the_int_range_is_not_whole(t) -> void:
	var els := [
		{"type": "map", "id": "m", "width": 1e30, "height": 10},
		{"type": "zone", "id": "z"},
		{"type": "marker", "id": "a", "zone": "z", "map": "m", "x": -1e30, "y": 1},
		{"type": "marker", "id": "b", "zone": "z", "map": "m", "x": 2, "y": 3, "z": 1e30, "order": 5},
		{"type": "marker", "id": "c", "zone": "z", "map": "m", "x": 4, "y": 5, "order": 1e30},
		{"type": "marker", "id": "d", "zone": "z", "map": "m", "x": 6, "y": 6, "order": 9},
		{"type": "pin", "id": "p", "map": "m", "x": 7, "y": 1}]
	var a := OWMapSpace.map_space(els).to_dict()
	t.eq(a["zones"], [{"zone": "z", "map": "m", "shape": "polygon", "points": [[2, 3, 0], [6, 6, 0], [4, 5, 0]]}],
		"z 1e30 reads 0, order 1e30 after the ordered ones")
	t.eq(a["out"], {"no_point": 1}, "x -1e30 is no point")
	t.eq(a["maps"][0]["width"], 7, "width 1e30 is measured from the points")
	t.eq(a["maps"][0]["extent"], "points", "and says so")
	t.eq(a["maps"][0]["z_max"], 0, "no z past the range is kept")
	t.done()

## The TypeScript SDK 4.129.2's vector (test/map-space.test.mjs), read from JSON text, as a reader is served it: a
## number the parse had to round is not whole; a reader holds whole numbers only where a double holds them exactly.
## -9223372036854775809 parses to exactly -2^63, 2^53 + 1 to 2^53; 2^53 - 1 is the largest a double holds exactly.
func test_a_number_the_parse_had_to_round_is_not_whole(t) -> void:
	var elements: Variant = JSON.parse_string("""[
		{"type": "map", "id": "m", "width": 10, "height": 10},
		{"type": "zone", "id": "z"},
		{"type": "marker", "id": "k1", "map": "m", "zone": "z", "x": 1, "y": 1, "z": 9007199254740991},
		{"type": "marker", "id": "k2", "map": "m", "zone": "z", "x": -9223372036854775809, "y": 2},
		{"type": "marker", "id": "k3", "map": "m", "zone": "z", "x": 3, "y": 3, "z": 9007199254740993},
		{"type": "pin", "id": "p1", "map": "m", "x": 9007199254740992, "y": 1}
	]""")
	t.ok(elements is Array and elements.size() == 6, "the text parses")
	var a := OWMapSpace.map_space(elements).to_dict()
	# k2's x and p1's x are past 2^53 - 1: no point. k3's z is past it: read as 0, as any z that is not a whole
	# number, and the point stays placed.
	t.eq(a["zones"], [{"zone": "z", "map": "m", "shape": "polygon", "points": [[1, 1, 9007199254740991], [3, 3, 0]]}], "the zone")
	t.eq(a["pins"], [], "no pin")
	t.eq(a["out"], {"no_point": 2}, "two without a point")
	t.eq(a["maps"][0]["z_max"], 9007199254740991, "2^53 - 1 is whole")
	t.done()

## The page's reading A (the fixture's marker-dangling-before-no-point since serial 106): a Marker both dangling and
## without a point counts once, as dangling (served-ness before shape), whichever of its zone or map is not served.
func test_reading_a_a_dangling_marker_without_a_point_is_dangling(t) -> void:
	var els := [
		{"type": "map", "id": "m", "width": 10, "height": 10},
		{"type": "zone", "id": "z"},
		{"type": "marker", "id": "a", "zone": "gone", "map": "m", "y": 1},
		{"type": "marker", "id": "b", "zone": "z", "map": "gone", "x": 1.5, "y": 1},
		{"type": "marker", "id": "c", "zone": "z", "map": "m", "x": 2, "y": 2}]
	t.eq(OWMapSpace.map_space(els).out, {"dangling": 2}, "two dangling, no no_point")
	t.done()

## A caller's mistake is named and nothing is read; a row that is no element (not a Dictionary, no string type, no
## non-empty string id) is passed over and never counted.
func test_a_callers_mistake_and_rows_that_are_no_element(t) -> void:
	var empty := {"maps": [], "zones": [], "pins": [], "out": {}}
	for e in [null, {}, {"elements": []}, "x", 3]:
		var a := OWMapSpace.map_space(e)
		t.ok(a.error != "", "a mistake: " + var_to_str(e))
		t.eq(a.to_dict(), empty, "nothing read: " + var_to_str(e))
	t.eq(OWMapSpace.map_space([]).to_dict(), empty, "no elements, the empty answer")
	t.eq(OWMapSpace.map_space([]).error, "", "and no mistake")
	t.eq(OWMapSpace.map_space([null, 3, "x", {"id": "a"}, {"type": 7, "id": "b"}, {"type": "pin", "id": 5, "map": "m", "x": 1, "y": 1},
		{"type": "map", "id": ""}]).to_dict(), empty, "rows that are no element")
	t.done()

## A reading never moves the elements, and every part of the answer is the caller's own.
func test_a_reading_never_moves_the_elements(t) -> void:
	var c: Dictionary = _fixture()["cases"].filter(func(c): return c["name"] == "plan-of-record-whole")[0]
	var before := JSON.stringify(c["elements"])
	var a := OWMapSpace.map_space(c["elements"])
	t.ok(not a.zones.is_empty() and not a.maps.is_empty(), "the ship has outlines")
	a.maps[0]["id"] = "planted"
	a.zones[0]["points"][0][0] = -1
	t.eq(JSON.stringify(c["elements"]), before, "the elements unchanged")
	var b := OWMapSpace.map_space(c["elements"])
	t.ok(b.maps[0]["id"] != "planted" and b.zones[0]["points"][0][0] != -1, "an answer is the caller's own")
	t.done()

# -- The layout reading (rules 8 to 10, serials 110 and 111): the fixture's layout_cases and the two packages' vectors ---------

## A layout case read as the page says, once per Map row it names: by [code]map[/code], the one Map row with that
## String id; by [code]map_index[/code] (since dist.111, for rows with no id to name them by), each row at those
## positions in its elements, every one a Map row. [code]maps[/code] are the case's Map rows, [code]pins[/code] its Pin
## rows. A case names its Map one way, never both and never neither. [param errors] gathers what is wrong with the case
## itself (read with [code]get[/code], so a row without an id never stops the replay).
static func _read_layouts(c: Dictionary, errors: Array) -> Array:
	var elements: Array = c["elements"]
	var maps: Array = elements.filter(func(e): return e.get("type") == "map")
	var pins: Array = elements.filter(func(e): return e.get("type") == "pin")
	var rows := []
	if c.has("map") == c.has("map_index"):
		errors.append("a case names its Map by map or by map_index, one of the two")
		return []
	if c.has("map"):
		var named: Array = maps.filter(func(e): return e.get("id") is String and c["map"] is String and e["id"] == c["map"])
		if named.size() != 1:
			errors.append("no one Map row with the case's id")
			return []
		rows.append(named[0])
	else:
		var index: Variant = c["map_index"]
		if not (index is Array and not index.is_empty()):
			errors.append("map_index is a list of positions")
			return []
		for i in index:
			var at: Variant = OWLens.whole(i)
			if at == null or at < 0 or at >= elements.size() or elements[at].get("type") != "map":
				errors.append("position %s is no Map row of the elements" % var_to_str(i))
				return []
			rows.append(elements[at])
	return rows.map(func(m): return OWMapSpace.layout_of(m, maps, pins))

## A case that names one Map row (by its id): its one answer.
static func _read_layout(c: Dictionary) -> OWMapSpace.MapLayout:
	var errors := []
	var all := _read_layouts(c, errors)
	return all[0] if all.size() == 1 and errors.is_empty() else OWMapSpace.layout_of(null, [], [])

func _layout_case(t, c: Dictionary) -> void:
	var errors := []
	var answers := _read_layouts(c, errors)
	t.eq(errors, [], "the case names its Map rows")
	t.ok(not answers.is_empty(), "a Map row read")
	var n := 0
	for a in answers:
		n += 1
		var row := "row %d" % n
		t.eq(a.error, "", row + ": no caller's mistake")
		var got: Dictionary = a.to_dict()
		t.eq(got.keys(), ["layout", "ground", "hand"], row + ": the three keys, in order")
		for k in c["want"]:
			t.eq(got.get(k), c["want"][k], row + ": " + k)
		t.eq(JSON.stringify(got), JSON.stringify(c["want"]), row + ": byte for byte, key order included")
	t.done()

## The replay reads every row a case names: one per map case, each of a map_index case's positions (dist.111's
## map-without-a-string-id names two, a row with no id and one whose id is 7).
func test_the_replay_reads_every_row_a_case_names(t) -> void:
	var by_index: Array = _fixture()["layout_cases"].filter(func(c): return c.has("map_index"))
	t.eq(by_index.map(func(c): return c["name"]), ["map-without-a-string-id", "layout-map-empty-id-is-no-map"],
		"dist.111 names one case's Maps by map_index, dist.126 a second (a Map whose id is an empty string)")
	var errors := []
	t.eq(_read_layouts(by_index[0], errors).size(), 2, "its two rows, each read")
	t.eq(_read_layouts(by_index[1], errors).size(), 1, "its one row, read")
	var rows := 0
	for c in _fixture()["layout_cases"]:
		rows += _read_layouts(c, errors).size()
	t.eq(rows, 29 - 2 + 2 + 1, "every row a case names, read once (29 cases, one of them naming two rows)")
	t.eq(errors, [], "every case names its Map rows")
	t.done()

## Godot's JSON joins an escaped surrogate pair into one code point, which sorts after U+FFFF (measured, as the
## fixture's hand-in-code-point-order holds its ids raw, not escaped).
func test_an_escaped_surrogate_pair_is_one_code_point_in_code_point_order(t) -> void:
	var bs := String.chr(92)
	var text := "[{\"type\": \"pin\", \"id\": \"p" + bs + "ud83d" + bs + "udea2\", \"map\": \"m\"}, {\"type\": \"pin\", \"id\": \"p" + bs + "uffff\", \"map\": \"m\"}]"
	var pins: Variant = JSON.parse_string(text)
	t.ok(pins is Array and pins.size() == 2, "the text parses")
	t.eq(pins[0]["id"], "p" + String.chr(0x1F6A2), "the pair is one code point")
	var board := {"type": "map", "id": "m", "x_layout": {"method": "hand"}}
	t.eq(OWMapSpace.layout_of(board, [board], pins).hand, ["p" + String.chr(0xFFFF), "p" + String.chr(0x1F6A2)], "U+FFFF first")
	t.done()

func test_the_fixture_holds_twenty_nine_layout_cases_beside_its_cases(t) -> void:
	var f := _fixture()
	t.ok(f.get("layout_cases") is Array, "layout_cases beside cases")
	t.eq(f["layout_cases"].size(), 29, "29 layout cases (17 at dist.110, 21 at dist.111, 23 at dist.119, 26 at dist.126)")
	var names := {}
	for c in f["layout_cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 29, "each layout case named once")
	t.ok(names.has("parentless-layout-beside-ground") and names.has("ground-beside-parentless-layout"),
		"dist.119's two cases: a layout Map and its ground, neither with a parent_map, each read in turn")
	t.eq(f["cases"].size(), 39, "the map space reading's 39 cases beside them")
	t.done()

## The map space reading is unchanged by rules 8 to 10: on every layout case its answer carries no layout key.
func test_the_map_space_reading_carries_no_layout_key(t) -> void:
	for c in _fixture()["layout_cases"]:
		var a := OWMapSpace.map_space(c["elements"]).to_dict()
		t.eq(a.keys(), ["maps", "zones", "pins", "out"], c["name"] + ": the keys")
		for row in a["maps"] + a["pins"]:
			for k in row:
				t.ok(not (k.begins_with("x_") or k == "layout" or k == "hand"), c["name"] + ": " + k)
	t.done()

## The reading never moves the rows, the same case gives the same bytes, and the answer is the caller's own.
func test_the_layout_reading_never_moves_the_rows(t) -> void:
	for c in _fixture()["layout_cases"]:
		var before := JSON.stringify(c["elements"])
		var once := JSON.stringify(_read_layouts(c, []).map(func(a): return a.to_dict()))
		t.eq(JSON.stringify(_read_layouts(c, []).map(func(a): return a.to_dict())), once, c["name"] + ": stable")
		t.eq(JSON.stringify(c["elements"]), before, c["name"] + ": the rows unchanged")
	var board: Dictionary = _fixture()["layout_cases"].filter(func(c): return c["name"] == "board-every-pin-is-hand")[0]
	var got := _read_layout(board)
	got.hand.append("planted")
	t.eq(_read_layout(board).to_dict(), board["want"], "an answer is the caller's own")
	t.done()

## Godot's JSON reads 1 as 1.0 and a caller's own code may write 1: neither is the mark, only the bool true.
func test_only_the_bool_true_is_the_mark_as_ints_and_floats(t) -> void:
	var trail := {"type": "map", "id": "m", "x_layout": {"method": "trail-by-place"}}
	var pins := [{"type": "pin", "id": "a", "map": "m", "x_hand": 1}, {"type": "pin", "id": "b", "map": "m", "x_hand": 1.0},
		{"type": "pin", "id": "c", "map": "m", "x_hand": true}, {"type": "pin", "id": "d", "map": "m", "x_hand": "true"}]
	t.eq(OWMapSpace.layout_of(trail, [trail], pins).hand, ["c"], "1, 1.0 and \"true\" are not true")
	t.done()

## A caller's mistake is named and nothing is read.
func test_a_callers_mistake_in_the_layout_reading(t) -> void:
	var none := {"layout": null, "ground": null, "hand": []}
	var trail := {"type": "map", "id": "m", "x_layout": {"method": "hand"}}
	for args in [[null, [], []], [[trail], [], []], ["m", [], []], [trail, null, []], [trail, [], {"pins": []}]]:
		var a := OWMapSpace.layout_of(args[0], args[1], args[2])
		t.ok(a.error != "", "a mistake: " + var_to_str(args))
		t.eq(a.to_dict(), none, "nothing read: " + var_to_str(args))
	t.eq(OWMapSpace.layout_of(trail, [], []).error, "", "a board with no Pins is no mistake")
	t.done()

# The TypeScript SDK 4.142.0's vectors beyond the fixture (test/layout-of.test.mjs).

## U+FF5E sorts before U+1F600 by code point; as UTF-16 units the surrogate D83D sorts first.
func test_npm_hand_is_in_code_point_order_never_utf16_order(t) -> void:
	var trail := {"type": "map", "id": "m1", "x_layout": {"method": "trail-by-place"}}
	var low := String.chr(0xFF5E)
	var high := String.chr(0x1F600)
	var pins := [{"type": "pin", "id": high, "map": "m1", "x_hand": true}, {"type": "pin", "id": low, "map": "m1", "x_hand": true}]
	t.eq(OWMapSpace.layout_of(trail, [trail], pins).hand, [low, high], "a trail")
	t.eq(OWMapSpace.layout_of({"type": "map", "id": "m1", "x_layout": {"method": "hand"}}, [], pins).hand, [low, high], "a board")
	t.done()

func test_npm_a_row_without_an_id_is_no_pin_and_the_last_row_served_is_read(t) -> void:
	var trail := {"type": "map", "id": "m1", "x_layout": {"method": "trail-by-place"}}
	var pins := [
		{"type": "pin", "map": "m1", "x_hand": true},
		{"type": "pin", "id": "", "map": "m1", "x_hand": true},
		{"type": "pin", "id": 7, "map": "m1", "x_hand": true},
		null,
		"p",
		{"type": "pin", "id": "p1", "map": "m1", "x_hand": true},
		{"type": "pin", "id": "p1", "map": "other", "x_hand": true},
		{"type": "pin", "id": "p2", "map": "m1"},
		{"type": "pin", "id": "p2", "map": "m1", "x_hand": true}]
	t.eq(OWMapSpace.layout_of(trail, [trail], pins).to_dict(), {"layout": "trail-by-place", "ground": null, "hand": ["p2"]})
	t.done()

func test_npm_a_map_row_without_an_id_is_no_map_and_a_list_x_layout_is_no_layout(t) -> void:
	var pins := [{"type": "pin", "id": "p1", "map": "m1", "x_hand": true}]
	var none := {"layout": null, "ground": null, "hand": []}
	t.eq(OWMapSpace.layout_of({"type": "map", "x_layout": {"method": "hand"}}, [], pins).to_dict(), none, "no id")
	t.eq(OWMapSpace.layout_of({"type": "map", "id": "m1", "x_layout": [{"method": "hand"}]}, [], pins).to_dict(), none, "a list")
	t.done()

## Reading H says a non-empty string id (dist.119's words): a Map row whose id is "" is no Map, so no layout map, even
## with a method and a Pin naming "" as its map. No fixture case holds this row yet.
func test_a_map_row_whose_id_is_the_empty_string_is_no_layout_map(t) -> void:
	var map := {"type": "map", "id": "", "x_layout": {"method": "hand"}}
	var pins := [{"type": "pin", "id": "p1", "map": ""}]
	t.eq(OWMapSpace.layout_of(map, [map], pins).to_dict(), {"layout": null, "ground": null, "hand": []})
	t.done()

func test_npm_a_ground_named_by_a_row_that_is_no_map_is_no_ground(t) -> void:
	var grounded := {"type": "map", "id": "m1", "x_layout": {"method": "trail-by-place", "settings": {"ground": {"map": "g"}}}}
	t.eq(OWMapSpace.layout_of(grounded, [grounded, {"type": "map", "id": "g"}], []).ground, "g", "served")
	t.eq(OWMapSpace.layout_of(grounded, [grounded, {"type": "map", "name": "g"}], []).ground, null, "a row without an id")
	var flat := {"type": "map", "id": "m1", "x_layout": {"method": "trail-by-place", "settings": {"ground": "g"}}}
	t.eq(OWMapSpace.layout_of(flat, [{"type": "map", "id": "g"}], []).ground, null, "a ground that is a string")
	t.done()

# The Python package 0.110.0's vectors beyond the fixture (tests/test_layout_of.py).

func test_py_rows_are_read_as_the_map_space_reading_reads_them(t) -> void:
	var board := {"type": "map", "id": "m", "x_layout": {"method": "hand"}}
	var pins := [
		{"type": "pin", "id": "b", "map": "m"},
		{"type": "pin", "id": "", "map": "m"},
		{"type": "pin", "id": 7, "map": "m"},
		{"type": "pin", "map": "m"},
		"not a row",
		{"type": "pin", "id": "a", "map": "m"},
		{"type": "pin", "id": "a", "map": "elsewhere"}]
	t.eq(OWMapSpace.layout_of(board, [board], pins).to_dict(), {"layout": "hand", "ground": null, "hand": ["b"]})
	t.done()

func test_py_a_method_that_is_no_non_empty_string_is_no_layout(t) -> void:
	for method in [true, false, 1, 1.0, null, ["hand"], {"method": "hand"}, ""]:
		var map := {"type": "map", "id": "m", "x_layout": {"method": method}}
		var pin := {"type": "pin", "id": "p", "map": "m", "x_hand": true}
		t.eq(OWMapSpace.layout_of(map, [map], [pin]).to_dict(), {"layout": null, "ground": null, "hand": []}, var_to_str(method))
	t.done()

## U+FFFF sorts before U+10000 by code point, after it by UTF-16 unit.
func test_py_hand_is_in_code_point_order_above_u_ffff(t) -> void:
	var board := {"type": "map", "id": "m", "x_layout": {"method": "hand"}}
	var pins := [{"type": "pin", "id": String.chr(0x10000), "map": "m"}, {"type": "pin", "id": String.chr(0xFFFF), "map": "m"}]
	t.eq(OWMapSpace.layout_of(board, [board], pins).hand, [String.chr(0xFFFF), String.chr(0x10000)])
	t.done()

func test_py_settings_are_never_returned(t) -> void:
	var ground := {"type": "map", "id": "g", "width": 30, "height": 20}
	var map := {"type": "map", "id": "m", "x_layout": {"method": "trail-by-place", "settings": {"ground": {"map": "g", "width": 3, "height": 2}}}}
	t.eq(OWMapSpace.layout_of(map, [map, ground], []).to_dict(), {"layout": "trail-by-place", "ground": "g", "hand": []})
	t.done()

func test_py_a_ground_map_that_is_no_id_is_no_ground(t) -> void:
	var ground := {"type": "map", "id": "g"}
	for named in ["", 5, true, null, ["g"], {"id": "g"}]:
		var map := {"type": "map", "id": "m", "x_layout": {"method": "trail-by-place", "settings": {"ground": {"map": named}}}}
		t.eq(OWMapSpace.layout_of(map, [map, ground], []).ground, null, var_to_str(named))
	t.done()
