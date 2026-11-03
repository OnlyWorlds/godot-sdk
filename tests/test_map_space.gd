extends RefCounted
## OWMapSpace on the map space profile's conformance fixture (schema-dist profiles/map-space.fixture.json, the pinned
## copy at dist.107, its sha256 checked against the manifest): every case by name, the whole answer compared by value
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
	t.eq(JSON.stringify(got), JSON.stringify(want), "byte for byte, key order included")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(MAP_SPACE), manifest["profiles/map-space.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "map-space", "the profile")
	t.eq(f["profile_page"], "profiles/map-space.md", "its page")
	t.eq(f["cases"].size(), 34, "34 cases")
	var names := {}
	for c in f["cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 34, "each case named once")
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
