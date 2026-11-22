extends RefCounted
## OWMapSpace.carry_of on the map space profile's frame cases (schema-dist profiles/map-space.fixture.json, the pinned
## copy, its frame_cases: rules 13 and 14). Each case is read as the page says: map is the last Map row served with the
## case's id (or each row map_index lists), maps every row of the case, of which the reader keeps the Maps itself, and
## point the case's. A number in parent_frame and in points compares as a 64-bit float, exactly and with no tolerance
## (0 and -0 are one number, as == has it); every other part as written, key order included. The npm SDK's
## test/carry-of.test.mjs (4.183.0), ported, and beside it what the fixture leaves open in Godot: ints and floats, a
## bool that is no number, and a reading that never moves its input.
##
## Godot's JSON reads some 17-digit decimals as a neighbouring double, so every number of a case written with a
## fraction or an exponent, in its input and in its want, comes from tests/data/map-space-frames.bits.json
## (codegen/generate_frame_bits.py, which names the fixture's sha256), never from the parse.

const MAP_SPACE := "res://codegen/schema-dist/profiles/map-space.fixture.json"
const BITS := "res://tests/data/map-space-frames.bits.json"

var _doc: Dictionary
var _bits: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(MAP_SPACE))
	return _doc

func _floats() -> Dictionary:
	if _bits.is_empty():
		_bits = JSON.parse_string(FileAccess.get_file_as_string(BITS))
	return _bits

static func _from_hex(h: String) -> float:
	var be := h.hex_decode()
	be.reverse()
	return be.decode_double(0)

func get_cases() -> Array:
	var out := []
	for c in _fixture().get("frame_cases", []):
		out.append(["carry_of:" + c["name"], _case.bind(c["name"])])
	return out

## The case by name, a copy whose every number written with a fraction is set from its bits; [param parsed_off]
## gathers the paths where Godot's parse gave another double.
func _read_case(name: String, parsed_off: Array = []) -> Dictionary:
	var found: Array = _fixture()["frame_cases"].filter(func(x): return x["name"] == name)
	var c: Dictionary = found[0].duplicate(true)
	for f in _floats()["cases"][name]:
		var path: Array = f[0]
		var at: Variant = c
		for s in range(path.size() - 1):
			at = at[int(path[s]) if at is Array else path[s]]
		var last: Variant = path[path.size() - 1]
		var k: Variant = int(last) if at is Array else last
		var exact := _from_hex(f[1])
		if typeof(at[k]) != TYPE_FLOAT or at[k] != exact:
			parsed_off.append("%s %s" % [name, path])
		at[k] = exact
	return c

## The rows a case reads: each map_index lists, or the last Map row served with its id.
static func _rows_read(c: Dictionary) -> Array:
	if c.has("map_index"):
		return c["map_index"].map(func(i): return c["elements"][int(i)])
	var last: Variant = null
	for e in c["elements"]:
		if e is Dictionary and e.get("type") is String and e["type"] == "map" and e.get("id") is String and e["id"] == c["map"]:
			last = e
	return [] if last == null else [last]

## Exactly equal: a number as a 64-bit float (both floats, ==), a list and a Dictionary by their parts, a
## Dictionary's keys in order, anything else as written.
static func _same(t, got: Variant, want: Variant, path: String) -> void:
	match typeof(want):
		TYPE_FLOAT:
			t.ok(typeof(got) == TYPE_FLOAT and got == want, "%s: %s is not %s" % [path, var_to_str(got), var_to_str(want)])
		TYPE_ARRAY:
			if typeof(got) != TYPE_ARRAY or got.size() != want.size():
				t.fail("%s: %s is not a list of %d" % [path, var_to_str(got), want.size()])
				return
			for i in want.size():
				_same(t, got[i], want[i], "%s[%d]" % [path, i])
		TYPE_DICTIONARY:
			if typeof(got) != TYPE_DICTIONARY:
				t.fail("%s: %s is not an object" % [path, var_to_str(got)])
				return
			t.eq(got.keys(), want.keys(), path + ": keys in order")
			for k in want:
				_same(t, got.get(k), want[k], "%s.%s" % [path, k])
		_:
			t.eq(got, want, path)

func _case(t, name: String) -> void:
	var c := _read_case(name)
	var rows := _rows_read(c)
	t.ok(not rows.is_empty(), name + ": a row to read")
	for row in rows:
		var a := OWMapSpace.carry_of(row, c["point"], c["elements"])
		t.eq(a.error, "", "no caller's mistake")
		_same(t, a.to_dict(), c["want"], "answer")
	t.done()

func test_the_fixture_holds_the_frame_readings_cases_each_named_once(t) -> void:
	var cases: Array = _fixture().get("frame_cases", [])
	t.ok(not cases.is_empty(), "the pinned fixture holds frame cases")
	t.eq(FileAccess.get_sha256(MAP_SPACE), _floats()["fixture_sha256"], "the bits file is the pinned fixture's")
	t.eq(cases.size(), int(_floats()["frame_cases"]), "the bits file counts the fixture's frame cases")
	t.eq(get_cases().size(), cases.size(), "one test per frame case")
	var names := {}
	for c in cases:
		names[c["name"]] = true
	t.eq(names.size(), cases.size(), "each frame case named once")
	t.eq(names.keys(), _floats()["cases"].keys(), "the bits file holds every case, in the fixture's order")
	var off := []
	for c in cases:
		_read_case(c["name"], off)
	print("       carry_of: of %d numbers written with a fraction, Godot's JSON read %d as another double: %s" % [
		_floats()["cases"].values().reduce(func(n, v): return n + v.size(), 0), off.size(), ", ".join(off)])
	t.done()

func test_every_answer_holds_its_four_keys_in_order_and_the_other_readings_carry_no_frame_key(t) -> void:
	for c0 in _fixture()["frame_cases"]:
		var c := _read_case(c0["name"])
		for row in _rows_read(c):
			t.eq(OWMapSpace.carry_of(row, c["point"], c["elements"]).to_dict().keys(),
				["parent_frame", "lint", "points", "stop"], c["name"] + ": the keys")
		for m in OWMapSpace.map_space(c["elements"]).maps:
			t.ok(not m.has("parent_frame") and not m.has("x_parent_frame"), c["name"] + ": a map-space entry carries no frame key")
	t.done()

func test_carry_of_names_a_point_that_is_not_two_finite_numbers_and_a_map_that_is_not_one_element(t) -> void:
	var m := {"type": "map", "id": "a", "width": 10, "height": 10}
	var empty := {"parent_frame": null, "lint": null, "points": [], "stop": null}
	for bad in [[1], [1, 2, 3], ["1", 2], [1, NAN], [1, INF], [true, 2], null, {}, Vector2(1, 2)]:
		var a := OWMapSpace.carry_of(m, bad, [m])
		t.ok(a.error.begins_with("carry_of: point"), "a mistake: " + var_to_str(bad))
		t.eq(a.to_dict(), empty, "nothing read: " + var_to_str(bad))
	t.ok(OWMapSpace.carry_of(null, [1, 2], []).error.begins_with("carry_of: map"), "a map that is no Dictionary")
	t.ok(OWMapSpace.carry_of(m, [1, 2], null).error.begins_with("carry_of: maps"), "maps that is no Array")
	t.eq(OWMapSpace.carry_of(m, [1, 2], [m]).error, "", "and a good call is no mistake")
	t.done()

## Godot holds an int and a float apart where JSON does not: the same rows as ints carry to the same floats, every
## carried coordinate is a float, and parent_frame is the key as written.
func test_ints_and_floats_carry_alike(t) -> void:
	var land := {"type": "map", "id": "land", "width": 1000, "height": 800}
	var town := {"type": "map", "id": "town", "width": 100, "height": 50, "parent_map": "land",
		"x_parent_frame": [100, 200, 300, 300]}
	var a := OWMapSpace.carry_of(town, [20, 10], [land, town]).to_dict()
	t.eq(a, {"parent_frame": [100, 200, 300, 300], "lint": null,
		"points": [{"map": "town", "x": 20.0, "y": 10.0}, {"map": "land", "x": 140.0, "y": 220.0}], "stop": "top"}, "ints")
	var town_f := {"type": "map", "id": "town", "width": 100.0, "height": 50.0, "parent_map": "land",
		"x_parent_frame": [100.0, 200.0, 300.0, 300.0]}
	var b := OWMapSpace.carry_of(town_f, [20.0, 10.0], [land, town_f]).to_dict()
	t.eq(b["points"], a["points"], "floats give the same points")
	t.eq(b["parent_frame"], [100.0, 200.0, 300.0, 300.0], "the key as written")
	t.done()

## A bool is no number, in the frame and as a size: Godot's bool is its own type, never 1.
func test_a_bool_is_no_number(t) -> void:
	var land := {"type": "map", "id": "land", "width": 10, "height": 10}
	var framed := {"type": "map", "id": "t", "width": 10, "height": 10, "parent_map": "land", "x_parent_frame": [0, 0, true, 5]}
	t.eq(OWMapSpace.carry_of(framed, [1, 1], [land, framed]).lint, "not_four_numbers", "a bool in the frame")
	var sized := {"type": "map", "id": "t", "width": true, "height": 10, "parent_map": "land", "x_parent_frame": [0, 0, 5, 5]}
	t.eq(OWMapSpace.carry_of(sized, [1, 1], [land, sized]).stop, "no_carry", "a bool as a width")
	t.done()

## A reading never moves its input, and every part of the answer is the caller's own.
func test_a_reading_never_moves_its_input(t) -> void:
	var c := _read_case("nesting-three-levels")
	var before := var_to_str(c)
	var a := OWMapSpace.carry_of(_rows_read(c)[0], c["point"], c["elements"])
	t.eq(a.stop, "top", "the chain is walked")
	a.parent_frame[0] = -1
	a.points[0]["x"] = -1
	t.eq(var_to_str(c), before, "the case unchanged")
	t.done()
