extends RefCounted
## OWLanding on the landing profile's conformance fixture (schema-dist profiles/landing.fixture.json, the pinned copy at
## dist.104, its sha256 checked against the manifest): every case by name, the keys its want holds compared value and
## key order, a whole case the entire answer, a refusal naming its option. Beside it, what the fixture leaves open: the
## five keys always there in order, every node in one place, the graph world_graph answers read as its Dictionary is,
## Godot's float options, a caller's mistake, and a reading that never moves the graph.

const LANDING := "res://codegen/schema-dist/profiles/landing.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(LANDING))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["landing:" + c["name"], _case.bind(c)])
	return out

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

func _case(t, c: Dictionary) -> void:
	var want: Dictionary = _ints(c["want"])
	var l := OWLanding.landing_of(c["graph"], c.get("options"))
	if want.has("refused"):
		t.eq(l.refused, want["refused"], "the option refused")
		t.ok(l.error.contains(want["refused"]), "the message names it: " + l.error)
		t.eq(l.to_dict(), {"refused": want["refused"]}, "nothing read")
		t.done()
		return
	t.eq(l.refused, "", "nothing refused")
	t.eq(l.error, "", "no caller's mistake")
	var all := l.to_dict()
	var got := all if c.get("whole", false) else {}
	if not c.get("whole", false):
		for k in want:
			got[k] = all.get(k)
	for k in want:
		t.eq(got.get(k), want[k], k)
	t.eq(JSON.stringify(got), JSON.stringify(want), "byte for byte, key order included")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(LANDING), manifest["profiles/landing.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "landing", "the profile")
	t.eq(f["profile_page"], "profiles/landing.md", "its page")
	t.eq(f["cases"].size(), 33, "33 cases")
	t.eq(f["cases"].filter(func(c): return c["want"].has("refused")).size(), 7, "7 refusals")
	t.done()

## Every answer holds the five keys in order, its counts are ints, and the same graph and options give the same bytes.
func test_five_keys_in_order_ints_and_the_same_bytes(t) -> void:
	for c in _fixture()["cases"]:
		if c["want"].has("refused"):
			continue
		var a := OWLanding.landing_of(c["graph"], c.get("options")).to_dict()
		t.eq(a.keys(), ["mode", "size", "clusters", "unclustered", "gaps"], c["name"] + ": the keys")
		t.eq(typeof(a["size"]), TYPE_INT, c["name"] + ": size an int")
		for k in a["clusters"]:
			for m in k["members"]:
				t.ok(typeof(m["hops"]) == TYPE_INT and typeof(m["degree"]) == TYPE_INT, c["name"] + ": a member's counts")
		for u in a["unclustered"]:
			t.eq(typeof(u["degree"]), TYPE_INT, c["name"] + ": an unclustered degree")
		t.eq(JSON.stringify(OWLanding.landing_of(c["graph"], c.get("options")).to_dict()), JSON.stringify(a), c["name"] + ": stable")
	t.done()

## Every node is in exactly one cluster or unclustered, and each cluster starts with its head at 0 hops.
func test_every_node_in_one_place(t) -> void:
	for c in _fixture()["cases"]:
		if c["want"].has("refused"):
			continue
		var a := OWLanding.landing_of(c["graph"], c.get("options"))
		var ids := []
		for k in a.clusters:
			for m in k["members"]:
				ids.append(m["id"])
			t.eq([k["members"][0]["id"], k["members"][0]["hops"]], [k["head"], 0], c["name"] + ": the head first")
		for u in a.unclustered:
			ids.append(u["id"])
		var nodes: Array = c["graph"]["nodes"].map(func(n): return n["id"])
		ids.sort()
		nodes.sort()
		t.eq(ids, nodes, c["name"] + ": every node once")
	t.done()

## The graph world_graph answers is read as its Dictionary is: a small world, the owner's graph, the same landing.
func test_a_world_graph_is_read_as_its_dictionary(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "location": "l1", "friends": ["c2"]},
		{"id": "c2", "type": "character", "name": "Bo", "friends": ["c1"]},
		{"id": "l1", "type": "location", "name": "Harbour"},
		{"id": "l2", "type": "location", "name": "Shoal"},
		{"id": "o1", "type": "object", "name": "Lamp", "location": "l2"}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(g.error, "", "the graph read")
	var a := OWLanding.landing_of(g)
	t.eq(a.error, "", "no caller's mistake")
	t.eq(a.to_dict(), OWLanding.landing_of(g.to_dict()).to_dict(), "the Graph and its Dictionary land the same")
	t.eq(a.clusters.map(func(k): return k["head"]), ["c1", "c2"], "the heads: c1 (3 edges) before c2 (2)")
	t.eq(a.gaps, [{"kind": "near_orphan", "id": "l1"}, {"kind": "near_orphan", "id": "l2"},
		{"kind": "near_orphan", "id": "o1"}, {"kind": "no_place", "id": "c2"}, {"kind": "nobody_here", "id": "l2"}],
		"an Object's location is an edge, and fills no Location")
	t.done()

## Godot's JSON reads 2 as 2.0: a whole float is that number. A bool, a fraction, a string, 0 and below are refused by
## name; an unknown key is refused before any value is read; null is the default.
func test_options_as_godot_holds_them(t) -> void:
	var g := {"nodes": [{"id": "a", "type": "character"}, {"id": "b", "type": "character"}, {"id": "c", "type": "event"}],
		"edges": [{"source": "c", "field": "characters", "target": "a", "index": 0},
			{"source": "c", "field": "characters", "target": "b", "index": 1}]}
	t.eq(OWLanding.landing_of(g, {"heads": 1.0}).clusters.size(), 1, "1.0 is 1")
	t.eq(OWLanding.landing_of(g, {"size": 3.0}).mode, "graph", "3.0 is 3")
	t.eq(OWLanding.landing_of(g, {"size": 3.0}).size, 3, "and is answered as the int")
	t.eq(OWLanding.landing_of(g, {"heads": 1e30}).clusters.size(), 2, "a whole number too large to hold is the largest")
	t.eq(OWLanding.landing_of(g, {"size": 1e30}).size, OWLanding.I64_MAX, "and is answered as the largest int")
	t.eq(OWLanding.landing_of(g, {"size": 1e30}).refused, "", "and is no refusal")
	for v in [true, false, 1.5, "2", -1, 0, -0.0, [2], {"n": 2}, INF, NAN]:
		t.eq(OWLanding.landing_of(g, {"hops": v}).refused, "hops", "hops " + var_to_str(v))
	t.eq(OWLanding.landing_of(g, {"heads": 0, "lens": "x"}).refused, "lens", "an unknown key before a bad value")
	t.eq(OWLanding.landing_of(g, {"heads": 0, "hops": 0}).refused, "heads", "heads, then hops, then size")
	t.eq(OWLanding.landing_of(g, {"heads": null}).clusters.size(), 2, "null is the default")
	t.eq(OWLanding.landing_of(g, {}).to_dict(), OWLanding.landing_of(g).to_dict(), "no options is the defaults")
	t.done()

## A caller's mistake is named and nothing is read: no graph, nodes or edges not a list, options not a Dictionary.
func test_a_callers_mistake(t) -> void:
	for g in [null, {}, {"nodes": []}, {"edges": []}, {"nodes": {}, "edges": []}, [], "graph"]:
		var a := OWLanding.landing_of(g)
		t.ok(a.error != "" and a.refused == "", "a mistake, no refusal: " + var_to_str(g))
	var a := OWLanding.landing_of({"nodes": [], "edges": []}, 5)
	t.ok(a.error.contains("options"), "options not a Dictionary: " + a.error)
	t.eq(a.refused, "", "a mistake is no refusal")
	t.done()

## A reading never moves the graph or the options.
func test_a_reading_never_moves_the_graph(t) -> void:
	var c: Dictionary = _fixture()["cases"].filter(func(c): return c.get("whole", false))[0]
	var before := JSON.stringify(c["graph"]) + JSON.stringify(c["options"])
	var a := OWLanding.landing_of(c["graph"], c["options"])
	a.clusters[0]["members"].clear()
	t.eq(JSON.stringify(c["graph"]) + JSON.stringify(c["options"]), before, "the graph and the options unchanged")
	t.ok(not OWLanding.landing_of(c["graph"], c["options"]).clusters[0]["members"].is_empty(), "an answer is the caller's own")
	t.done()
