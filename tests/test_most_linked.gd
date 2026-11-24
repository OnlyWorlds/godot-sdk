extends RefCounted
## OWLanding.most_linked_of on the TypeScript SDK's and the Python package's shared fixture
## (tests/data/most-linked.fixture.json, the same bytes, held by its sha256): every case's whole answer, key order
## included, or the option it refuses; then what the fixture cannot hold: no options, a graph that is not one, purity,
## and a graph world_graph answers.

const FIXTURE := "res://tests/data/most-linked.fixture.json"
const FIXTURE_SHA256 := "9a7b27d849cd1c268d86b754bcdb7954cb23b3ede85178023332d61e497489c4"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _doc

## Godot's JSON reads every number as a float; the fixture's counts are whole numbers.
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

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["most-linked: " + c["name"], _case.bind(c)])
	return out

func test_the_fixture_is_the_shared_file(t) -> void:
	t.eq(FileAccess.get_sha256(FIXTURE), FIXTURE_SHA256, "the fixture's bytes are the TypeScript SDK's and the Python package's")
	t.eq(_fixture()["profile"], "most-linked", "the profile")
	t.eq(_fixture()["cases"].size(), 18, "18 cases")
	t.done()

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var got := OWLanding.most_linked_of(c["graph"], c["options"])
	if c["want"].has("refused"):
		t.eq(got.refused, c["want"]["refused"], "the option refused")
		t.ok(got.error.contains(c["want"]["refused"]), "the error names it: " + got.error)
		t.eq(got.to_dict(), {"refused": c["want"]["refused"]}, "the answer")
		t.done()
		return
	t.eq(got.error, "", "no caller's mistake")
	# Byte for byte, key order included.
	t.eq(OWJson.stringify(got.to_dict()), OWJson.stringify(_ints(c["want"])), "the whole answer")
	t.eq(typeof(got.per_type), TYPE_INT, "per_type an int")
	for type in got.by_type:
		for e in got.by_type[type]:
			t.eq(typeof(e["degree"]), TYPE_INT, "a degree an int")
	t.done()

func test_no_options_null_options_and_empty_options_are_the_default(t) -> void:
	var c: Dictionary = _fixture()["cases"][0]
	var want := OWJson.stringify(_ints(c["want"]))
	t.eq(OWJson.stringify(OWLanding.most_linked_of(c["graph"]).to_dict()), want, "no options")
	t.eq(OWJson.stringify(OWLanding.most_linked_of(c["graph"], null).to_dict()), want, "null options")
	t.eq(OWJson.stringify(OWLanding.most_linked_of(c["graph"], {}).to_dict()), want, "empty options")
	t.done()

func test_a_graph_that_is_not_one_and_options_that_are_not_a_dictionary_are_the_callers_mistake(t) -> void:
	for g in [null, {"nodes": []}, {"edges": []}, 3, "graph"]:
		var a := OWLanding.most_linked_of(g)
		t.ok(a.error != "" and a.refused == "", "%s: an error, no option refused" % var_to_str(g))
	var b := OWLanding.most_linked_of({"nodes": [], "edges": []}, 3)
	t.ok(b.error != "" and b.refused == "", "options 3: an error, no option refused")
	t.done()

## A whole number held as an int past 2^53 - 1 is refused as the TypeScript SDK refuses it (Number.isSafeInteger),
## and the largest safe one is taken and echoed.
func test_an_int_past_the_safe_range_is_refused_and_the_largest_safe_one_echoed(t) -> void:
	var g: Dictionary = _fixture()["cases"][0]["graph"]
	t.eq(OWLanding.most_linked_of(g, {"per_type": 9007199254740992}).refused, "per_type", "2^53 as an int")
	var a := OWLanding.most_linked_of(g, {"per_type": 9007199254740991})
	t.eq([a.refused, a.per_type], ["", 9007199254740991], "2^53 - 1 taken and echoed")
	t.eq(a.by_type["character"].size(), 4, "every character with an edge")
	t.done()

func test_it_reads_the_graph_it_is_given_and_changes_nothing_in_it(t) -> void:
	var g: Dictionary = _fixture()["cases"][6]["graph"]
	var before := OWJson.stringify(g)
	OWLanding.most_linked_of(g)
	t.eq(OWJson.stringify(g), before, "the graph unchanged")
	t.done()

## Through world_graph: a hidden element and map space are not counted for a reader who is not shown them; the control,
## a graph that brings the hidden element in, counts it.
func test_through_world_graph_a_hidden_element_and_map_space_are_not_counted(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["c2"]},
		{"id": "c2", "type": "character", "name": "Brin"},
		{"id": "sec", "type": "event", "name": "The Secret", "characters": ["c1", "c2"], "hidden": true},
		{"id": "m1", "type": "map", "name": "Chart"},
		{"id": "p1", "type": "pin", "name": "Pin", "map": "m1", "element_type": "character", "element_id": "c1"}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(g.error, "", "the graph read")
	t.eq(OWLanding.most_linked_of(g).to_dict(), {"per_type": 3, "by_type": {"character": [
		{"id": "c1", "name": "Ada", "degree": 1}, {"id": "c2", "name": "Brin", "degree": 1}]}}, "the owner's graph")
	var shown := OWLanding.most_linked_of(OWGraph.world_graph(world, {"rung": "owner"}, {"hidden": true}))
	t.eq(shown.by_type.get("event"), [{"id": "sec", "name": "The Secret", "degree": 2}], "the hidden event, brought in")
	t.eq(shown.by_type["character"][0]["degree"], 2, "and counted at Ada")
	t.done()
