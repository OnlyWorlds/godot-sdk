extends RefCounted
## OWMapSpace.pins_known_to on the TypeScript SDK's and the Python package's shared cases
## (tests/data/pins-known-to.cases.json, the same bytes, held by its sha256): the whole answer of every case, key order
## included, and every refusal; then what the cases cannot hold: the inputs left as they were, read-only inputs read,
## two calls answering two objects, and the answer beside map_space's.

const CASES := "res://tests/data/pins-known-to.cases.json"
const CASES_SHA256 := "80f66dba8aa1a009770bdcffbf457ec84b78f7e4270a2fb9cf8614a4b76e39f6"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	return _doc

## Each case afresh from the file's bytes, so a write to one run's input cannot reach another's.
static func _fresh() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CASES))

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["case:" + c["name"], _case.bind(c)])
	for r in _fixture()["refusals"]:
		out.append(["refusal:" + r["name"], _refusal.bind(r)])
	return out

## Godot's JSON reads every number as a float; the answer's counts are whole numbers.
static func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
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

static func _text(v: Variant) -> String:
	# sort_keys false: JSON.stringify sorts a Dictionary's keys by default, which would hide the order.
	return JSON.stringify(v, "", false)

func _case(t, c: Dictionary) -> void:
	var a := OWMapSpace.pins_known_to(c["pins"], c["served"])
	t.eq(a.error, "", "no caller's mistake")
	var want: Dictionary = _ints(c["want"])
	var got := a.to_dict()
	for k in want:
		t.eq(got.get(k), want[k], k)
	t.eq(_text(got), _text(want), "the whole answer, key order included")
	t.done()

func _refusal(t, r: Dictionary) -> void:
	var a := OWMapSpace.pins_known_to(r["pins"], r["served"])
	var other := "served" if r["refuses"] == "pins" else "pins"
	t.ok(a.error.begins_with("pins_known_to: "), "a caller's mistake: " + a.error)
	t.ok(a.error.contains(r["refuses"] + " is a list") and not a.error.contains(other + " is a list"), "names %s alone: %s" % [r["refuses"], a.error])
	t.eq(_text(a.to_dict()), _text({"known": [], "unknown": 0, "out": {}}), "nothing answered")
	t.done()

func test_the_cases_file_is_the_shared_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(CASES), CASES_SHA256, "the bytes the TypeScript SDK and the Python package run")
	t.eq(int(_fixture()["version"]), 1, "version 1")
	t.eq(_fixture()["cases"].size(), 31, "31 cases")
	t.eq(_fixture()["refusals"].size(), 8, "8 refusals")
	t.done()

func test_every_answer_holds_its_keys_in_order_and_ints(t) -> void:
	for c in _fixture()["cases"]:
		var a := OWMapSpace.pins_known_to(c["pins"], c["served"]).to_dict()
		t.eq(a.keys(), ["known", "unknown", "out"], c["name"] + ": the keys")
		t.eq(typeof(a["unknown"]), TYPE_INT, c["name"] + ": unknown is an int")
		for k in a["known"]:
			t.eq(k.keys(), ["pin", "map", "element_type", "element_id", "how"], c["name"] + ": a known Pin's keys")
		for reason in a["out"]:
			t.eq(typeof(a["out"][reason]), TYPE_INT, c["name"] + ": a count is an int")
	t.done()

func test_the_inputs_are_left_as_they_were(t) -> void:
	var before: Array = _fresh()["cases"]
	var run: Array = _fresh()["cases"]
	for c in run:
		OWMapSpace.pins_known_to(c["pins"], c["served"])
	for i in run.size():
		t.eq(_text(run[i]["pins"]), _text(before[i]["pins"]), run[i]["name"] + ": pins")
		t.eq(_text(run[i]["served"]), _text(before[i]["served"]), run[i]["name"] + ": served")
	t.done()

static func _read_only(v: Variant) -> Variant:
	if v is Array:
		for x in v:
			_read_only(x)
		v.make_read_only()
	elif v is Dictionary:
		for k in v:
			_read_only(v[k])
		v.make_read_only()
	return v

func test_read_only_inputs_are_read(t) -> void:
	for c in _fresh()["cases"]:
		var got := OWMapSpace.pins_known_to(_read_only(c["pins"]), _read_only(c["served"])).to_dict()
		t.eq(_text(got), _text(_ints(c["want"])), c["name"])
	t.done()

func test_two_calls_answer_two_objects(t) -> void:
	var pins := [{"type": "pin", "id": "p1", "map": "m1", "element_type": "location", "element_id": "l1"}]
	var served := [{"type": "location", "id": "l1"}]
	var a := OWMapSpace.pins_known_to(pins, served)
	var b := OWMapSpace.pins_known_to(pins, served)
	t.ok(not is_same(a, b), "two answers")
	t.ok(not is_same(a.known, b.known), "two known lists")
	t.ok(not is_same(a.known[0], b.known[0]), "two known rows")
	t.ok(not is_same(a.out, b.out), "two out tallies")
	t.done()

## A drawing keeps the Pins both readings name: pins_known_to says which the reader knows, map_space where they are.
func test_beside_map_space_a_drawing_keeps_the_pins_both_name(t) -> void:
	var world := [
		{"type": "map", "id": "m1", "width": 100, "height": 100},
		{"type": "pin", "id": "p1", "map": "m1", "x": 1, "y": 2, "element_type": "location", "element_id": "l1"},
		{"type": "pin", "id": "p2", "map": "m1", "x": 3, "y": 4, "element_type": "location", "element_id": "l2"},
		{"type": "pin", "id": "p3", "map": "m1", "element_type": "location", "element_id": "l1"},
		{"type": "pin", "id": "p4", "map": "gone", "x": 5, "y": 6, "element_type": "location", "element_id": "l1"},
		{"type": "location", "id": "l1"},
		{"type": "location", "id": "l2"},
	]
	var served := [{"type": "location", "id": "l1", "known_of": true}]
	var answer := OWMapSpace.pins_known_to(world, served)
	var how := {}
	for k in answer.known:
		how[k["pin"]] = k["how"]
	t.eq(how.keys(), ["p1", "p3", "p4"], "known: p3 has no point, p4 is on no Map")
	t.eq(answer.unknown, 1, "p2's element was not served")
	var drawn := []
	for p in OWMapSpace.map_space(world).pins:
		if how.has(p["pin"]):
			drawn.append([p["pin"], p["x"], p["y"], how[p["pin"]]])
	t.eq(drawn, [["p1", 1, 2, "known_of"]], "the one Pin both name")
	t.done()
