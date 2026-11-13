extends RefCounted
## OWGraph on the lens fixture's graph kind (schema-dist profiles/lens.fixture.json at dist.123, the pinned copy): each
## of its cases carries its own small world, reader and options, and the want (nodes in order with their marks,
## edges in order, edges_cut, the lens's cut and unreadable, or refused naming a flag). Then the profile's graph tables
## held to the fixture and the presentation defaults, degree_of and out_degree_of, and the degree kind's cases.

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
		elif c["kind"] == "degree":
			out.append(["degree:" + c["name"], _degree.bind(c)])
	return out

## The degree kind (serial 103): a small graph as world_graph gives it, and both counts, every node a key in the
## graph's node order.
func _degree(t, c: Dictionary) -> void:
	var g := OWGraph.Graph.new()
	g.nodes = c["graph"]["nodes"]
	g.edges = c["graph"]["edges"]
	var want: Dictionary = _ints(c["want"])
	var d := OWGraph.degree_of(g)
	var out := OWGraph.out_degree_of(g)
	t.eq(d, want["degree"], "degree")
	t.eq(out, want["out_degree"], "out_degree")
	t.eq(d.keys(), want["degree"].keys(), "degree's keys in the node order")
	t.eq(out.keys(), want["out_degree"].keys(), "out_degree's keys in the node order")
	t.done()

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
	t.eq(pres["types"].size(), 22, "every type in the sidecar")
	var world := {"elements": []}
	for type in OWTypes.slugs():
		world["elements"].append({"id": "n_" + type, "type": type, "name": type})
	var nodes: Array = OWGraph.world_graph(world, {"rung": "owner"}, {"map_space": true}).nodes
	t.eq(nodes.size(), 22, "a node for every type")
	for n in nodes:
		var type: String = n["type"]
		t.eq([n["family"], n["icon"]], [pres["types"][type]["family"], pres["types"][type]["icon"]], type)
	t.done()

## The node's family and icon follow the presentation: with one type's family changed in memory to another of the four
## words the node follows, and back on the defaults it returns.
func test_the_node_follows_the_presentation(t) -> void:
	var world := {"elements": [{"id": "c1", "type": "character", "name": "Ada"}, {"id": "l1", "type": "location", "name": "Keep"}]}
	var before: Array = OWGraph.world_graph(world, {"rung": "owner"}).nodes
	var pres: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/presentation.json"))
	var table: Dictionary = pres["types"].duplicate(true)
	table["character"]["family"] = "amber"
	table["character"]["icon"] = "star"
	OWPresentation.use(table)
	var after: Array = OWGraph.world_graph(world, {"rung": "owner"}).nodes
	OWPresentation.reset()
	var back: Array = OWGraph.world_graph(world, {"rung": "owner"}).nodes
	t.eq(before[0]["family"], pres["types"]["character"]["family"], "the default family")
	t.eq([after[0]["family"], after[0]["icon"]], ["amber", "star"], "the changed type follows")
	t.eq([after[1]["family"], after[1]["icon"]], [before[1]["family"], before[1]["icon"]], "another type is untouched")
	t.eq(back, before, "back on the defaults")
	t.done()

## The lens profile's nodes and presentation.json's _meta.groups (serial 87): a word not in colors.order fails loudly,
## naming the word, and never draws a default. A table that brings one is refused whole, the table before it kept; a
## table changed in place after it was taken makes the graph a caller's mistake that names the word, with no node.
func test_a_family_word_not_in_the_order_fails_loudly(t) -> void:
	var world := {"elements": [{"id": "c1", "type": "character", "name": "Ada"}]}
	var before: Array = OWGraph.world_graph(world, {"rung": "owner"}).nodes
	var pres: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/presentation.json"))
	var table: Dictionary = pres["types"].duplicate(true)
	t.eq(OWPresentation.ORDER, pres["colors"]["order"], "the four words are colors.order's, in order")
	table["character"]["family"] = "temporal"
	var said := OWPresentation.use(table)
	t.ok(said.contains("character") and said.contains("\"temporal\""), "use names the type and the word: " + said)
	var after := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(after.nodes, before, "the table with an unknown word is not taken")
	var partial := {"character": pres["types"]["character"]}
	t.ok(OWPresentation.use(partial) != "", "a table short of a type is refused too")
	t.eq(OWPresentation.use(pres["types"].duplicate(true)), "", "the dist's own table is taken")
	var good: Dictionary = pres["types"].duplicate(true)
	OWPresentation.use(good)
	good["character"]["family"] = "temporal"
	var changed := OWGraph.world_graph(world, {"rung": "owner"})
	OWPresentation.reset()
	t.eq(changed.nodes, [], "no node is drawn")
	t.ok(changed.error.contains("\"temporal\""), "the graph's mistake names the word: " + changed.error)
	t.eq(OWGraph.world_graph(world, {"rung": "owner"}).nodes, before, "back on the defaults")
	t.done()

## The review profile's rule 1 (serial 87): an empty review mark ("", White_Space only, [] or {}) is settled, so its
## element is a node like any other, unmarked, and no flag is needed for it; a doubt is out as proposed.
func test_an_empty_review_mark_is_no_proposed_node(t) -> void:
	var marks := {"e_obj": {}, "e_list": [], "e_str": "", "e_ws": " \t　", "d_str": "unsure", "d_list": ["x"],
		"d_mark": {"by": "m1"}}
	var world := {"elements": []}
	for id in marks:
		world["elements"].append({"id": id, "type": "location", "name": id, "x_review_proposed": marks[id]})
	var plain := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(plain.nodes.map(func(n): return n["id"]), ["e_list", "e_obj", "e_str", "e_ws"], "the empty marks are nodes")
	t.eq(plain.nodes.filter(func(n): return n.has("marks")), [], "and carry no mark")
	t.eq(plain.cut, {"proposed": 3}, "only the doubts and the mark are out as proposed")
	var asked := OWGraph.world_graph(world, {"rung": "owner"}, {"proposed": true})
	var marked := asked.nodes.filter(func(n): return n.has("marks")).map(func(n): return n["id"])
	t.eq(marked, ["d_list", "d_mark", "d_str"], "the flag brings back three, marked")
	var public := OWGraph.world_graph(world, {"rung": "public"})
	t.eq(public.nodes.size(), 4, "a public reader sees the four settled")
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

## reading_aids (serial 104) where the fixture's five cases leave it unpinned: last in the refusal order (no fixture case
## asks map_space and reading_aids together below hidden), a boolean like the other flags, any signed rung's, and a
## node's marks in the packages' order (room, hidden, proposed, reading_aid), an aid the owner hid carrying both.
func test_reading_aids_order_kind_and_marks(t) -> void:
	var world := {"elements": []}
	t.eq(OWGraph.world_graph(world, {"rung": "public"}, {"reading_aids": true, "map_space": true}).refused, "map_space",
		"map_space before reading_aids")
	t.eq(OWGraph.world_graph(world, {"rung": "public"}, {"reading_aids": true, "rooms": true}).refused, "rooms",
		"rooms before reading_aids")
	t.ok(OWGraph.world_graph(world, {"rung": "owner"}, {"reading_aids": 1}).error.contains("reading_aids"), "a boolean")
	t.eq(OWGraph.world_graph(world, {"rung": "owner"}, {"reading_aids": null}).error, "", "null is the default")
	for rung in ["owner", "contributor", "guest"]:
		t.eq(OWGraph.world_graph(world, {"rung": rung}, {"reading_aids": true}).refused, "", "%s may ask it" % rung)
	t.eq(OWGraph.world_graph(world, {"rung": "owner", "as": {"rung": "public"}}, {"reading_aids": true}).refused,
		"reading_aids", "the owner as a public reader is judged by the public rung")
	var hid := {"elements": [{"id": "ch", "type": "law", "name": "House Rules", "supertype": "Charter",
		"x_charter_of": "w1", "hidden": true}]}
	var both := OWGraph.world_graph(hid, {"rung": "owner"}, {"hidden": true, "reading_aids": true})
	t.eq(both.nodes.map(func(n): return n.get("marks")), [["hidden", "reading_aid"]], "hidden, then reading_aid")
	t.eq(OWGraph.world_graph(hid, {"rung": "owner"}, {"reading_aids": true}).cut, {"hidden": 1},
		"a hidden aid needs both flags: hidden, its first reason, counts it")
	t.eq(OWGraph.world_graph(hid, {"rung": "owner"}, {"hidden": true}).cut, {"reading_aid": 1},
		"and with hidden alone it is out as a reading aid")
	t.done()

# -- the profile owner's rulings on the graph section's silences (each a case in the fixture's next serial) -----------

## G1: an edge to an anchor the reader cannot see carries the lens's own reason, anchor_not_visible, not not_visible.
## The owner reading as a contributor is told both, so the two can differ.
func test_ruling_g1_an_edge_to_an_unseen_anchor_carries_the_lens_reason(t) -> void:
	var world := {"elements": [
		{"id": "L", "type": "construct", "name": "L", "supertype": "Lens", "characters": ["a", "h"], "x_lens": {"depth": 0}},
		{"id": "a", "type": "character", "name": "Ada", "friends": ["h"]},
		{"id": "h", "type": "character", "name": "Hal", "hidden": true}]}
	var g := OWGraph.world_graph(world, {"rung": "owner", "as": {"rung": "contributor"}}, {"lens": "L"})
	t.eq(g.nodes.map(func(n): return n["id"]), ["a"], "Ada")
	t.eq(g.edges_cut, {"anchor_not_visible": 1}, "Ada's link to Hal, the lens's unseen anchor")
	t.done()

## G2: a Pin's generic pair is placement, never an edge; its map link is.
func test_ruling_g2_a_pins_pair_is_no_edge(t) -> void:
	var world := {"elements": [
		{"id": "m", "type": "map", "name": "Map"},
		{"id": "p", "type": "pin", "name": "Pin", "map": "m", "element_type": "character", "element_id": "a"},
		{"id": "a", "type": "character", "name": "Ada"}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"}, {"map_space": true})
	t.eq(g.edges, [{"source": "p", "field": "map", "target": "m", "index": 0}], "the map link only")
	t.done()

## G3: a node's name is the stored value, null when absent, nothing invented.
func test_ruling_g3_a_nodes_name_is_as_stored(t) -> void:
	var world := {"elements": [{"id": "a", "type": "character", "name": 7}, {"id": "b", "type": "character"},
		{"id": "c", "type": "character", "name": ""}]}
	t.eq(OWGraph.world_graph(world, {"rung": "owner"}).nodes.map(func(n): return n["name"]), [7, null, ""], "7, null, \"\"")
	t.done()

## G4: a node's type is as stored, never folded (a non-slug type is a data fault for the lint, not the reader's to fold).
func test_ruling_g4_a_nodes_type_is_as_stored(t) -> void:
	var world := {"elements": [{"id": "a", "type": "Character", "name": "Ada"}]}
	var node: Dictionary = OWGraph.world_graph(world, {"rung": "owner"}).nodes[0]
	t.eq(node["type"], "Character", "as stored")
	t.eq(node["family"], OWPresentation.family_of("character"), "the family read by the folded slug")
	var padded := {"elements": [{"id": "a", "type": " character ", "name": "Ada"}]}
	t.eq(OWGraph.world_graph(padded, {"rung": "public"}).nodes[0]["type"], " character ", "a public reader's node, padding kept")
	t.done()

## G5: an edge's index is the target's place in the link list as served to that reader; a contributor is served the link
## to a proposed element (keel's scoped), so the index counts it. A hidden id is not served and not counted.
func test_ruling_g5_a_contributors_index_counts_a_served_proposed_link(t) -> void:
	var world := {"elements": [
		{"id": "a", "type": "character", "name": "Ada", "friends": ["h", "px", "b"]},
		{"id": "h", "type": "character", "name": "Hal", "hidden": true},
		{"id": "px", "type": "character", "name": "Pax", "x_review_proposed": {"by": "m1"}},
		{"id": "b", "type": "character", "name": "Brin"}]}
	var g := OWGraph.world_graph(world, {"rung": "contributor"})
	t.eq(g.edges, [{"source": "a", "field": "friends", "target": "b", "index": 1}], "served [Pax, Brin]: Brin at 1")
	t.eq(OWGraph.world_graph(world, {"rung": "public"}).edges, [{"source": "a", "field": "friends", "target": "b", "index": 0}],
		"the public rung is served no proposed link: Brin at 0")
	t.done()

## A public reader's served link lists leave a proposed id out, as keel's wire serves the public rung, so the index has no
## gap: a visible target after a proposed one is at 0.
func test_a_public_readers_served_list_leaves_a_proposed_id_out_and_its_index_has_no_gap(t) -> void:
	var world := {"elements": [
		{"id": "a", "type": "character", "name": "Ada", "friends": ["px", "b"]},
		{"id": "px", "type": "character", "name": "Pax", "x_review_proposed": {"by": "m1"}},
		{"id": "b", "type": "character", "name": "Brin"}]}
	t.eq(OWLens.View.new(world, {"rung": "public"}, null).body("a")["friends"], ["b"], "the public rung is served [Brin]")
	t.eq(OWGraph.world_graph(world, {"rung": "public"}).edges, [{"source": "a", "field": "friends", "target": "b", "index": 0}],
		"Brin at 0")
	t.done()

## Ruling 1 reaches the edge list: a link reaches only an element of its field's target type, so a Character's friends
## naming a Location names nothing, a dangling link, neither an edge nor counted. The owner's index is still the place in
## the list as stored.
func test_ruling_b_a_wrongly_typed_id_draws_no_edge_and_is_not_counted(t) -> void:
	var world := {"elements": [
		{"id": "c", "type": "character", "name": "C", "friends": ["p", "h", "d"], "location": "p"},
		{"id": "p", "type": "location", "name": "P"},
		{"id": "h", "type": "location", "name": "H", "hidden": true},
		{"id": "d", "type": "character", "name": "D"}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(g.edges, [{"source": "c", "field": "friends", "target": "d", "index": 2},
		{"source": "c", "field": "location", "target": "p", "index": 0}], "the friend D and the location, never P as a friend")
	t.eq(g.edges_cut, {}, "the hidden Location under friends is no link, so not counted hidden")
	t.eq(OWGraph.world_graph(world, {"rung": "contributor"}).edges, [{"source": "c", "field": "friends", "target": "d", "index": 0},
		{"source": "c", "field": "location", "target": "p", "index": 0}], "a contributor is served friends [D]")
	t.done()

## The cut counts each element once, so an edge to an element the lens cut only as a wrongly typed anchor (a Location
## named under characters) reads the lens's reason, never outside_lens. Guards what this reader already does. Kills: the
## edge's target looked up by its own type and id.
func test_an_edge_to_an_element_the_lens_cut_as_a_wrongly_typed_anchor_reads_the_lenss_reason(t) -> void:
	var world := {"elements": [
		{"id": "o", "type": "object", "name": "Ledger", "location": "x"},
		{"id": "x", "type": "location", "name": "Harbour"}]}
	var lens := {"id": "L", "type": "construct", "name": "L", "supertype": "Lens", "characters": ["x"], "objects": ["o"]}
	var g := OWGraph.world_graph(world, {"rung": "owner"}, {"lens": lens})
	t.eq([g.nodes.map(func(n): return n["id"]), g.cut, g.edges_cut], [["o"], {"anchor_not_visible": 1}, {"anchor_not_visible": 1}])
	t.done()

## Counts are per reader, and an edge with them: below the owner an element whose owner-side reason was
## anchor_not_visible and which a child cuts by types is cut by the child's reason, so the edge to it is cut by that
## reason, never left uncounted. Kills: the unseen anchor recorded for every reader and dropped at the count.
func test_below_the_owner_an_edge_to_an_unseen_anchor_a_cut_child_reaches_is_cut_by_the_childs_reason(t) -> void:
	var world := {"elements": [
		{"id": "U", "type": "construct", "name": "U", "supertype": "Lens", "characters": ["x"], "constructs": ["C"], "x_lens": {"depth": 0}},
		{"id": "C", "type": "construct", "name": "C", "supertype": "Lens", "characters": ["y"], "x_lens": {"types": ["character"]}},
		{"id": "y", "type": "character", "name": "Ysolde", "birthplace": "x"},
		{"id": "x", "type": "location", "name": "Harbour"}]}
	var g := OWGraph.world_graph(world, {"rung": "contributor"}, {"lens": "U"})
	t.eq([g.nodes.map(func(n): return n["id"]), g.cut, g.edges_cut], [["y"], {"types": 1}, {"types": 1}])
	t.done()

## Hidden beats known_of: a hidden element named in a guest's known_of is no node, and a link to it is left out of the
## guest's served list, so the next edge's index has no gap; for the guest it is not counted, and for the owner reading
## as the guest it is not_visible, a target the reader does not see. Kills: the hidden element drawn as a known-of node.
func test_a_hidden_element_in_a_guests_known_of_is_no_node_and_a_link_to_it_is_not_visible(t) -> void:
	var world := {"elements": [
		{"id": "c1", "type": "character", "name": "Ada", "friends": ["h", "b"]},
		{"id": "h", "type": "character", "name": "Hal", "hidden": true},
		{"id": "b", "type": "character", "name": "Brin"}]}
	var guest := {"rung": "guest", "whole": ["c1", "b"], "known_of": ["h"]}
	var g := OWGraph.world_graph(world, guest)
	t.eq([g.nodes.map(func(n): return n["id"]), g.edges, g.edges_cut],
		[["b", "c1"], [{"source": "c1", "field": "friends", "target": "b", "index": 0}], {}])
	var as_guest := OWGraph.world_graph(world, {"rung": "owner", "as": guest})
	t.eq([as_guest.nodes.map(func(n): return n["id"]), as_guest.edges_cut], [["b", "c1"], {"not_visible": 1}])
	t.done()
