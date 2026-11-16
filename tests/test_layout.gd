extends RefCounted
## OWLayout.layout_by_kind and layout_around on the shared fixture: the pinned dist's profiles/layout.fixture.json (the
## default layouts page, profiles/layout.md, serial 132), read from the vendored folder. by-kind compares exactly, every
## x and y bit for bit: the method is chaotic, so two runtimes agree bit for bit or not at all. around compares within
## 1e-12: each of its points is one cosine and one sine, and runtimes' cosines may differ in the last place. The
## fixture's third suite, unplaced, is not read: the package has no unplaced reader.
##
## Godot's JSON reads some of the fixture's 17-digit decimals as a neighbouring double, so the graphs (whose numbers are
## small integers) are read from the fixture, and the wants from tests/data/layout.bits.json, which
## codegen/generate_layout.py writes from the same fixture with an exact reader and which names the fixture's sha256.
## When the pin moves the fixture: run codegen/generate_layout.py and update the hash.

const FIXTURE := "res://codegen/schema-dist/profiles/layout.fixture.json"
const FIXTURE_SHA256 := "6860a7654f1a92e31269cbbdd2a08049035bd19caebc2f9083b320be4872000e"
const BITS := "res://tests/data/layout.bits.json"
const AROUND_TOLERANCE := 1e-12

var _doc: Dictionary
var _bits: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _doc

func _wants() -> Dictionary:
	if _bits.is_empty():
		_bits = JSON.parse_string(FileAccess.get_file_as_string(BITS))
	return _bits

static func _from_hex(h: String) -> float:
	var be := h.hex_decode()
	be.reverse()
	return be.decode_double(0)

static func _hex(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	b.reverse()
	return b.hex_encode()

func _case(name: String) -> Dictionary:
	for c in _fixture()["cases"]:
		if c["name"] == name:
			return c
	return {}

func _around(name: String) -> Dictionary:
	for c in _fixture()["around"]:
		if c["name"] == name:
			return c
	return {}

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["layout-by-kind:" + c["name"], _by_kind.bind(c["name"])])
	for c in _fixture()["around"]:
		out.append(["layout-around:" + c["name"], _ring.bind(c["name"])])
	return out

func _by_kind(t, name: String) -> void:
	var c := _case(name)
	var got := OWLayout.layout_by_kind(c["graph"].duplicate(true))
	t.eq(got.get("error", ""), "", name + ": an answer")
	if got.has("error"):
		t.done()
		return
	t.eq(got["method"], "by-kind", "the method")
	t.eq(got["version"], 1, "the version")
	var want: Array = _wants()["cases"][name]
	var points: Array = got["points"]
	t.eq(points.size(), want.size(), name + ": one point per node")
	var off := 0
	var first := ""
	for k in mini(points.size(), want.size()):
		t.eq(points[k]["id"], c["graph"]["nodes"][k]["id"], name + ": in the order handed")
		if _hex(points[k]["x"]) != want[k][0] or _hex(points[k]["y"]) != want[k][1]:
			off += 1
			if first == "":
				first = "%s: (%s, %s) against (%s, %s)" % [points[k]["id"], _hex(points[k]["x"]), _hex(points[k]["y"]), want[k][0], want[k][1]]
	t.eq(off, 0, "%s: %d of %d points differ from the fixture (bit for bit); first %s" % [name, off, want.size(), first])
	t.done()

func _ring(t, name: String) -> void:
	var c := _around(name)
	var got := OWLayout.layout_around(c["graph"].duplicate(true), c["focus"], int(c["steps"]))
	t.eq(got.get("error", ""), "", name + ": an answer")
	if got.has("error"):
		t.done()
		return
	t.eq(got["method"], "around", "the method")
	t.eq(got["version"], 1, "the version")
	var want_bits: Array = _wants()["around"][name]
	var ids := []
	var want_ids := []
	for p in got["points"]:
		ids.append("%s:%d" % [p["id"], p["depth"]])
	for w in c["want"]:
		want_ids.append("%s:%d" % [w[0], int(w[1])])
	t.eq(ids, want_ids, name + ": the ids and depths, in the order handed")
	if ids == want_ids:
		for k in want_bits.size():
			var p: Dictionary = got["points"][k]
			var wx := _from_hex(want_bits[k][0])
			var wy := _from_hex(want_bits[k][1])
			t.ok(absf(p["x"] - wx) <= AROUND_TOLERANCE and absf(p["y"] - wy) <= AROUND_TOLERANCE,
				"%s: %s (%s, %s) against (%s, %s)" % [name, p["id"], String.num_scientific(p["x"]), String.num_scientific(p["y"]), String.num_scientific(wx), String.num_scientific(wy)])
	t.done()

func test_the_fixture_is_the_pinned_dists_bytes_with_seventeen_exact_cases_and_ten_rings(t) -> void:
	# The fixture also holds unplaced (15 cases), which no test here reads: the package has no unplaced reader.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(FIXTURE), FIXTURE_SHA256, "the fixture's bytes are the ones this test pins")
	t.eq(manifest["profiles/layout.fixture.json"], FIXTURE_SHA256, "the fixture's bytes are the pinned dist's")
	t.eq(_wants()["fixture_sha256"], FIXTURE_SHA256, "the bits file was made from this fixture")
	t.eq(OWLayoutAnchors.FIXTURE_SHA256, FIXTURE_SHA256, "the anchor table was made from this fixture")
	t.eq(_fixture()["compare"].keys(), ["cases", "around", "unplaced"], "the compare block")
	t.eq(_fixture()["cases"].size(), 17, "seventeen exact cases")
	t.eq(_fixture()["around"].size(), 10, "ten rings")
	t.eq(_wants()["cases"].size(), 17, "the bits file's exact cases")
	t.eq(_wants()["around"].size(), 10, "the bits file's rings")
	t.done()

func test_the_anchor_table_is_the_fixtures_anchors_bit_for_bit(t) -> void:
	var bits: Array = _wants()["anchors"]
	t.eq(OWLayoutAnchors.BITS.size(), 506, "253 points")
	t.eq(bits.size(), 506, "the bits file's 253 points")
	var floats := PackedInt64Array(OWLayoutAnchors.BITS).to_byte_array().to_float64_array()
	var off := 0
	for i in mini(floats.size(), bits.size()):
		if _hex(floats[i]) != bits[i]:
			off += 1
	t.eq(off, 0, "anchors that differ from the fixture's")
	t.done()

func test_the_groups_are_the_fixtures_and_the_presentation_defaults(t) -> void:
	t.eq(_fixture()["group_order"], OWPresentation.ORDER, "the group order")
	var groups: Dictionary = _fixture()["groups"]
	t.eq(groups.size(), 22, "22 types")
	for type in groups:
		t.eq(OWPresentation.TYPES[type]["family"], groups[type], type)
	t.done()

## The npm test's seeded shuffle (its generator, seed 99), so a failure reruns the same.
class _Shuffler:
	var s := 99
	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0
	func shuffle(xs: Array) -> Array:
		var a := xs.duplicate()
		for i in range(a.size() - 1, 0, -1):
			var j := int(floor(next() * (i + 1)))
			var tmp = a[i]
			a[i] = a[j]
			a[j] = tmp
		return a

static func _keys(points: Array) -> Dictionary:
	var out := {}
	for p in points:
		out[p["id"]] = "%s:%s:%s" % [str(p.get("depth", "")), _hex(p["x"]), _hex(p["y"])]
	return out

func test_the_order_nodes_and_links_are_handed_in_moves_no_point(t) -> void:
	var sh := _Shuffler.new()
	for name in ["hyperion", "past-324", "a-self-link-pulls-nothing"]:
		var g: Dictionary = _case(name)["graph"].duplicate(true)
		var mixed := {"nodes": sh.shuffle(g["nodes"]), "edges": sh.shuffle(g["edges"])}
		var got := OWLayout.layout_by_kind(mixed)
		var ids := []
		for p in got.get("points", []):
			ids.append(p["id"])
		var handed := []
		for x in mixed["nodes"]:
			handed.append(x["id"])
		t.eq(ids, handed, name + ": in the order handed")
		t.eq(_keys(got.get("points", [])), _keys(OWLayout.layout_by_kind(g).get("points", [])), name + ": the same points")
	var c := _around("two-steps")
	var g2: Dictionary = c["graph"].duplicate(true)
	var mixed2 := {"nodes": sh.shuffle(g2["nodes"]), "edges": sh.shuffle(g2["edges"])}
	var got2 := OWLayout.layout_around(mixed2, c["focus"], 2)
	var order := {}
	for k in mixed2["nodes"].size():
		order[mixed2["nodes"][k]["id"]] = k
	var pts: Array = got2.get("points", [])
	var in_order := true
	for k in range(1, pts.size()):
		in_order = in_order and order[pts[k - 1]["id"]] < order[pts[k]["id"]]
	t.ok(in_order and pts.size() > 0, "around: in the order handed")
	t.eq(_keys(pts), _keys(OWLayout.layout_around(g2, c["focus"], 2).get("points", [])), "around: the same points")
	t.done()

func _same_as_want(got: Dictionary, name: String) -> bool:
	var want: Array = _wants()["cases"][name]
	var points: Array = got.get("points", [])
	if points.size() != want.size():
		return false
	for k in want.size():
		if _hex(points[k]["x"]) != want[k][0] or _hex(points[k]["y"]) != want[k][1]:
			return false
	return true

func test_a_link_pulls_both_ends_alike(t) -> void:
	var g: Dictionary = _case("two-elements-linked")["graph"].duplicate(true)
	var e: Dictionary = g["edges"][0]
	var flipped := {"nodes": g["nodes"], "edges": [{"source": e["target"], "target": e["source"], "field": "x", "index": 0}]}
	t.ok(_same_as_want(OWLayout.layout_by_kind(flipped), "two-elements-linked"), "its direction moves nothing")
	t.done()

func test_a_frame_of_minus_one_to_one_on_the_longer_axis_centred(t) -> void:
	for name in ["hyperion", "moppetopia", "past-324"]:
		var xs := PackedFloat64Array()
		var ys := PackedFloat64Array()
		for p in OWLayout.layout_by_kind(_case(name)["graph"].duplicate(true)).get("points", []):
			xs.append(p["x"])
			ys.append(p["y"])
		if xs.is_empty():
			t.fail(name + ": no points")
			continue
		var x0: float = Array(xs).min()
		var x1: float = Array(xs).max()
		var y0: float = Array(ys).min()
		var y1: float = Array(ys).max()
		t.ok(absf(maxf(x1 - x0, y1 - y0) - 2.0) < 1e-12, name + ": the span")
		t.ok(absf(x1 + x0) < 1e-12 and absf(y1 + y0) < 1e-12, name + ": centred")
	t.done()

func test_the_empty_graph_answers_no_points_and_one_element_zero(t) -> void:
	t.eq(OWLayout.layout_by_kind({"nodes": [], "edges": []}), {"method": "by-kind", "version": 1, "points": []}, "empty")
	t.eq(OWLayout.layout_by_kind({"nodes": [{"id": "a", "type": "zone"}], "edges": []}).get("points"), [{"id": "a", "x": 0.0, "y": 0.0}], "one")
	t.done()

func test_a_link_to_an_id_that_is_not_a_node_is_passed_over(t) -> void:
	var g: Dictionary = _case("two-elements-linked")["graph"].duplicate(true)
	g["edges"].append({"source": g["nodes"][0]["id"], "target": "not-a-node", "field": "friends", "index": 0})
	t.ok(_same_as_want(OWLayout.layout_by_kind(g), "two-elements-linked"), "the same points")
	t.done()

func test_by_kind_runs_on_world_graphs_answer_as_it_comes(t) -> void:
	var world := {"elements": [
		{"id": "01a1d4ef-0000-7000-8000-000000000002", "type": "location", "name": "Harbour"},
		{"id": "01a1d4ef-0000-7000-8000-000000000001", "type": "character", "name": "Mara", "birthplace": "01a1d4ef-0000-7000-8000-000000000002"},
		{"id": "01a1d4ef-0000-7000-8000-000000000003", "type": "creature", "name": "Gull", "location": "01a1d4ef-0000-7000-8000-000000000002"}]}
	var g := OWGraph.world_graph(world, {"rung": "owner"})
	t.eq(g.error, "", "the graph read")
	var got := OWLayout.layout_by_kind(g)
	var ids := []
	var finite := true
	for p in got.get("points", []):
		ids.append(p["id"])
		finite = finite and is_finite(p["x"]) and is_finite(p["y"])
	var want_ids := []
	for n in g.nodes:
		want_ids.append(n["id"])
	t.eq(ids, want_ids, "one point per node, in the graph's order")
	t.ok(finite, "finite")
	var depths := []
	for p in OWLayout.layout_around(g, "01a1d4ef-0000-7000-8000-000000000002").get("points", []):
		depths.append(p["depth"])
	t.eq(depths, [1, 0, 1], "around the harbour")
	t.done()

func test_a_graph_it_cannot_read_is_refused_by_name(t) -> void:
	var bad := func(graph: Variant, words: String) -> void:
		var a: String = OWLayout.layout_by_kind(graph).get("error", "")
		t.ok(a.begins_with("layout_by_kind: ") and a.contains(words), "layout_by_kind refuses (%s): %s" % [words, a])
		var b: String = OWLayout.layout_around(graph, "a").get("error", "")
		t.ok(b.begins_with("layout_around: ") and b.contains(words), "layout_around refuses (%s): %s" % [words, b])
	bad.call(null, "the graph is { nodes, edges }")
	bad.call({"nodes": []}, "the graph is { nodes, edges }")
	bad.call({"nodes": [null], "edges": []}, "node 0 is not an object")
	bad.call({"nodes": [{"type": "character"}], "edges": []}, "node 0 has no id")
	bad.call({"nodes": [{"id": "a", "type": "starship"}], "edges": []}, "'starship' is not one of the 22 element types")
	bad.call({"nodes": [{"id": "a", "type": "toString"}], "edges": []}, "'toString' is not one of the 22 element types")
	bad.call({"nodes": [{"id": "a", "type": "character", "name": 7}], "edges": []}, "name is a string or null")
	bad.call({"nodes": [{"id": "a", "type": "character"}, {"id": "a", "type": "location"}], "edges": []}, "the id a is a node twice")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a"}]}, "edge 0 is not { source, target }")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a", "target": "a", "field": 3}]}, "edge 0: field is a string")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a", "target": "a", "field": null}]}, "edge 0: field is a string")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a", "target": "a", "index": NAN}]}, "edge 0: index is a number")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a", "target": "a", "index": "0"}]}, "edge 0: index is a number")
	bad.call({"nodes": [{"id": "a", "type": "character"}], "edges": [{"source": "a", "target": "a", "index": null}]}, "edge 0: index is a number")
	t.done()

func test_around_steps_is_one_or_two_and_the_focus_is_a_node(t) -> void:
	var g := {"nodes": [{"id": "a", "type": "character"}], "edges": []}
	for steps in [0, 3, "2", 1.5]:
		t.ok(String(OWLayout.layout_around(g, "a", steps).get("error", "")).contains("layout_around: steps is 1 or 2"), "steps %s" % str(steps))
	t.ok(String(OWLayout.layout_around({"nodes": [], "edges": []}, "a").get("error", "")).contains("the focus a is not a node of the graph"), "no node a")
	t.ok(OWLayout.layout_around(g, "b").has("error"), "no node b")
	t.ok(OWLayout.layout_around(g, null).has("error"), "a null focus")
	t.eq(OWLayout.layout_around(g, "a").get("points", []).size(), 1, "the focus alone")
	t.done()

func test_around_one_step_answers_the_neighbours_only_two_add_theirs(t) -> void:
	var one := _around("one-step-of-the-same")
	var two := _around("two-steps")
	var d1: Array = OWLayout.layout_around(one["graph"].duplicate(true), one["focus"]).get("points", [])
	var d2: Array = OWLayout.layout_around(two["graph"].duplicate(true), two["focus"], 2).get("points", [])
	var focus := 0
	var shallow := true
	for p in d1:
		shallow = shallow and p["depth"] <= 1
		focus += 1 if p["depth"] == 0 else 0
	t.ok(shallow and focus == 1 and d1.size() > 1, "one step")
	var deep := false
	var ring2 := []
	for p in d2:
		deep = deep or p["depth"] == 2
		if p["depth"] < 2:
			ring2.append(p)
	t.ok(deep, "two steps reach further")
	t.eq(_keys(ring2), _keys(d1), "the first ring is the same either way")
	t.done()

static func _ring_by_angle(points: Array, names: Dictionary) -> Array:
	var ring := []
	for p in points:
		if p["depth"] == 1:
			ring.append([fmod(atan2(p["y"], p["x"]) + PI / 2 + 4 * PI, 2 * PI), names[p["id"]]])
	ring.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var out := []
	for r in ring:
		out.append(r[1])
	return out

func test_around_names_order_by_code_point_never_by_locale(t) -> void:
	var c := _around("names-by-code-point-not-locale")
	var names := {}
	for x in c["graph"]["nodes"]:
		names[x["id"]] = x.get("name")
	var ring := _ring_by_angle(OWLayout.layout_around(c["graph"].duplicate(true), c["focus"]).get("points", []), names)
	t.eq(ring, ["Bea", "Zed", "adam", "bea", "Émile", "Øyvind", "𝐀lpha"], "by code point")
	t.done()

## -0 is made from its bits, never written as a literal: GDScript keeps one constant per value that compares equal, so a
## -0.0 and a 0.0 in one script are the same constant, whichever comes first (measured with Godot 4.7.2).
func test_min_and_max_are_javascripts(t) -> void:
	var nz := _from_hex("8000000000000000")
	var pz := _from_hex("0000000000000000")
	t.eq(_hex(nz), "8000000000000000", "-0 made")
	t.ok(1.0 / OWLayout._min_js(pz, nz) < 0.0 and 1.0 / OWLayout._min_js(nz, pz) < 0.0, "min(+0, -0) is -0, either way round")
	t.ok(1.0 / OWLayout._max_js(pz, nz) > 0.0 and 1.0 / OWLayout._max_js(nz, pz) > 0.0, "max(+0, -0) is +0, either way round")
	t.ok(is_nan(OWLayout._min_js(NAN, 1.0)) and is_nan(OWLayout._max_js(1.0, NAN)), "NaN if either is")
	t.eq(OWLayout._min_js(1.0, 2.0), 1.0, "min")
	t.eq(OWLayout._max_js(1.0, 2.0), 2.0, "max")
	t.done()

## U+FF5A (one UTF-16 code unit, 0xFF5A) sorts before U+1D400 (a surrogate pair, 0xD835 0xDC00) by code point, after it by
## UTF-16 code unit. The fixture's names-by-code-point-not-utf-16 case sets the two orders apart as well (serial 132);
## this pair is the smallest that does.
func test_around_names_order_by_code_point_not_by_utf16_code_unit(t) -> void:
	var astral := char(0x1D400)
	var wide := char(0xFF5A)
	var g := {"nodes": [{"id": "f", "type": "character"}, {"id": "p", "type": "character", "name": astral},
		{"id": "q", "type": "character", "name": wide}],
		"edges": [{"source": "f", "target": "p", "field": "friends", "index": 0}, {"source": "f", "target": "q", "field": "friends", "index": 1}]}
	var ring := _ring_by_angle(OWLayout.layout_around(g, "f").get("points", []), {"p": astral, "q": wide})
	t.eq(ring, [wide, astral], "U+FF5A first")
	t.done()
