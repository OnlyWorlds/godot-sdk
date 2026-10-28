extends RefCounted
## OWGraph on the lens fixture's graph kind (schema-dist profiles/lens.fixture.json at dist.82, the pinned copy): each
## of the 37 cases carries its own small world, reader and options, and the want (nodes in order with their marks,
## edges in order, edges_cut, the lens's cut and unreadable, or refused naming a flag). Then the profile's graph tables
## held to the fixture and the presentation defaults, degree_of and out_degree_of.

const P = preload("res://tests/paths.gd")

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(P.LENS))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		if c["kind"] == "graph":
			out.append(["graph:" + c["name"], _case.bind(c)])
	return out

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

func _case(t, c: Dictionary) -> void:
	var g := OWGraph.world_graph(c["world"], c["reader"], c.get("options", {}))
	var want: Dictionary = _ints(c["want"])
	var got: Dictionary = _ints(g.to_dict())
	if want.has("refused"):
		t.eq(g.refused, want["refused"], "the flag refused")
		t.eq(g.nodes, [], "nothing read")
	else:
		t.eq(g.error, "", "no caller's mistake")
		for k in ["nodes", "edges", "edges_cut", "cut", "unreadable"]:
			t.eq(got.get(k), want[k], k)
		t.eq(JSON.stringify(got["nodes"]), JSON.stringify(want["nodes"]), "the nodes' keys in the fixture's order")
	t.done()

func test_the_graph_tables_are_the_fixtures(t) -> void:
	var f := _fixture()
	t.eq(f["graph_links"], OWGraph.DECLARED_LINKS, "the declared links")
	t.eq(f["graph_flags"], OWGraph.FLAGS, "the flags")
	t.eq(f["owner_only_flags"], OWGraph.OWNER_ONLY_FLAGS, "the owner's flags")
	var reasons: Array = f["edges_cut_reasons"].duplicate()
	reasons.sort()
	var ours: Array = OWGraph.REASONS.duplicate()
	ours.sort()
	t.eq(ours, reasons, "the same fifteen reasons (counted in the packages' order)")
	for why in f["owner_only_edges_cut_reasons"]:
		t.ok(OWGraph.OWNER_ONLY_REASONS.has(why), "%s is the owner's alone" % why)
	var pres: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/presentation.json"))
	for type in OWTypes.slugs():
		t.eq([OWGraph.FAMILIES[type], OWGraph.ICONS[type]], [pres["types"][type]["family"], pres["types"][type]["icon"]], type)
	t.eq(OWGraph.FAMILIES.size(), 22, "every type a family")
	t.done()

## The npm SDK 4.95.0's degreeOf: a mirror pair counts 2 at each end, a link to itself once, a lone node 0, every node
## a key in the graph's node order, and only edges between nodes (what the reading left out is never counted).
func test_degree_of(t) -> void:
	var world := {"elements": [
		{"id": "e1", "type": "event", "name": "Siege", "relations": ["r1"]},
		{"id": "r1", "type": "relation", "name": "Truce", "events": ["e1"]},
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["c1", "c2", "h1"]},
		{"id": "c2", "type": "character", "name": "Bo"},
		{"id": "c3", "type": "character", "name": "Cy"},
		{"id": "h1", "type": "character", "name": "Hid", "hidden": true, "friends": ["c3"]}]}
	var d := OWGraph.degree_of(OWGraph.world_graph(world, {"rung": "owner"}))
	t.eq(d, {"c1": 2, "c2": 1, "c3": 0, "e1": 2, "r1": 2}, "the owner's degrees")
	t.eq(d.keys(), ["c1", "c2", "c3", "e1", "r1"], "in the node order")
	var with_hidden := OWGraph.degree_of(OWGraph.world_graph(world, {"rung": "owner"}, {"hidden": true}))
	t.eq(with_hidden["c3"], 1, "brought back, the hidden one's link counts")
	t.eq(with_hidden["h1"], 2, "and so does the link to it")
	t.done()

## The npm SDK 4.98.0's outDegreeOf: distinct targets of a node's own links, two fields to one target once, a link to
## itself none, a mirror pair 1 at each end, every node a key in the graph's node order.
func test_out_degree_of(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["c2", "c1"], "rivals": ["c2"]},
		{"id": "c2", "type": "character", "name": "Bo", "friends": ["c1"]},
		{"id": "r1", "type": "relation", "name": "Pact", "characters": ["c1", "c2", "c3"]},
		{"id": "c3", "type": "character", "name": "Cy"},
		{"id": "o1", "type": "object", "name": "Lamp"},
		{"id": "constructor", "type": "object", "name": "An id like an inherited key"},
		{"id": "__proto__", "type": "character", "name": "Another", "objects": ["constructor"]}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"})
	var d := OWGraph.out_degree_of(g)
	t.eq(d.keys(), g.nodes.map(func(n): return n["id"]), "in the node order")
	t.eq(d, {"__proto__": 1, "c1": 1, "c2": 1, "c3": 0, "constructor": 0, "o1": 0, "r1": 3}, "the out-degrees")
	t.done()

## out_degree_of on every fixture graph with nodes equals a direct count of distinct targets.
func test_out_degree_of_every_fixture_graph(t) -> void:
	var cases := 0
	for c in _fixture()["cases"]:
		if c["kind"] != "graph" or not c["want"].has("nodes"):
			continue
		cases += 1
		var g := OWGraph.Graph.new()
		g.nodes = c["want"]["nodes"]
		g.edges = c["want"]["edges"]
		var d := OWGraph.out_degree_of(g)
		for n in g.nodes:
			var direct := {}
			for e in g.edges:
				if e["source"] == n["id"] and e["target"] != n["id"]:
					direct[e["target"]] = true
			t.eq(d[n["id"]], direct.size(), "%s: %s" % [c["name"], n["id"]])
	t.ok(cases > 0, "a fixture graph case was read")
	t.done()

## A caller's mistake is named and nothing is read; a refused flag is named before anything is read.
func test_a_callers_mistake_and_a_refusal(t) -> void:
	var world := {"elements": []}
	t.ok(OWGraph.world_graph({"no": 1}, {"rung": "owner"}).error.contains("world"), "a world without elements")
	t.ok(OWGraph.world_graph(world, {"rung": "x"}).error.contains("rung"), "a rung outside the four")
	t.ok(OWGraph.world_graph(world, {"rung": "owner"}, {"mapSpace": true}).error.contains("mapSpace"), "an unknown option")
	t.ok(OWGraph.world_graph(world, {"rung": "owner"}, {"rooms": "yes"}).error.contains("rooms"), "a flag not a boolean")
	t.eq(OWGraph.world_graph(world, {"rung": "public"}, {"rooms": true, "map_space": true, "hidden": true}).refused, "hidden",
		"a public reader asking everything is refused as hidden")
	t.eq(OWGraph.world_graph(world, {"rung": "owner", "as": {"rung": "contributor"}}, {"proposed": true}).refused, "proposed",
		"the owner as a contributor is judged by the contributor's rung")
	t.eq(OWGraph.world_graph(world, {"rung": "owner"}, {"hidden": true, "proposed": true}).refused, "", "the owner may ask both")
	t.done()
