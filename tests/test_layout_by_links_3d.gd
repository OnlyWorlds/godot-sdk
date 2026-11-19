extends RefCounted
## OWLayout's by-links-3d on its own fixture: the pinned dist's profiles/layout-by-links-3d.fixture.json (the default
## layouts page, profiles/layout.md, serial 137 on), read from the vendored folder, with the directions table beside it.
## Its unplaced suite (9 cases) is read whole here: one case each, the list equal exactly and in its order.

const FIXTURE := "res://codegen/schema-dist/profiles/layout-by-links-3d.fixture.json"
const FIXTURE_SHA256 := "acd6da7252493485cafc24356a84c53656d078872a28c695c0f7554009b6fb2a"
const TABLE := "res://codegen/schema-dist/profiles/layout-by-links-3d.directions.json"
const TABLE_SHA256 := "37dc2bbb4a1769e4ddafc2d0a27c9889229c3ef483e8f7cd6c9ba66a0d1afb87"

const BITS := "res://tests/data/layout-by-links-3d.bits.json"
## The page's tolerance for an element placed arm or link (held false) and every element of a ring piece; every other
## number is exact.
const WITHIN := 6e-8

var _doc: Dictionary
var _bits: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _doc

## The fixture's numbers as bits (codegen/generate_layout_3d.py): Godot's JSON reads some 17-digit decimals as a
## neighbouring double, so every input number that is not whole, and every wanted coordinate, comes from here.
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

func get_cases() -> Array:
	var out := []
	var cases: Array = _fixture()["cases"]
	for i in cases.size():
		out.append(["layout-by-links-3d:%03d %s" % [i, cases[i]["name"]], _case.bind(i)])
	for c in _fixture()["unplaced"]:
		out.append(["layout-by-links-3d-unplaced:" + c["name"], _unplaced.bind(c["name"])])
	return out

## The case's input, every number that is not whole set from its bits.
func _input(i: int) -> Dictionary:
	var c: Dictionary = _fixture()["cases"][i]
	var input: Dictionary = c["input"].duplicate(true)
	for f in _wants()["cases"][c["name"]]["floats"]:
		var path: Array = f[0]
		var at: Variant = input
		for s in range(path.size() - 1):
			at = at[int(path[s]) if at is Array else path[s]]
		var last: Variant = path[path.size() - 1]
		at[int(last) if at is Array else last] = _from_hex(f[1])
	return input

## The fixture's ring pieces (its compare.pieces): every piece other than the main one, of two nodes or more, none of
## them placed map in the want and none in the input's held.
static func _ring_nodes(input: Dictionary, want: Dictionary) -> Dictionary:
	var ids := []
	var at := {}
	for x in input["nodes"]:
		at[x["id"]] = ids.size()
		ids.append(x["id"])
	var parent := range(ids.size())
	var find := func(a: int) -> int:
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	for e in input["edges"]:
		var a: int = at.get(e.get("source"), -1)
		var b: int = at.get(e.get("target"), -1)
		if a < 0 or b < 0 or a == b:
			continue
		parent[find.call(a)] = find.call(b)
	var by_root := {}
	for i in ids.size():
		var r: int = find.call(i)
		if not by_root.has(r):
			by_root[r] = []
		by_root[r].append(ids[i])
	var pieces: Array = by_root.values()
	var least := []
	for p in pieces:
		var s: Array = p.duplicate()
		s.sort()
		least.append(s[0])
	var main := 0
	for p in range(1, pieces.size()):
		if pieces[p].size() > pieces[main].size() or (pieces[p].size() == pieces[main].size() and least[p] < least[main]):
			main = p
	var on_map := {}
	for i in want["ids"].size():
		if want["how"][i] == "map":
			on_map[want["ids"][i]] = true
	var held: Variant = input.get("held")
	var ring := {}
	for p in pieces.size():
		if p == main or pieces[p].size() < 2:
			continue
		var stands := false
		for id in pieces[p]:
			stands = stands or on_map.has(id) or (held is Dictionary and held.has(id))
		if stands:
			continue
		for id in pieces[p]:
			ring[id] = true
	return ring

func _case(t, i: int) -> void:
	var c: Dictionary = _fixture()["cases"][i]
	var name: String = c["name"]
	t.eq(int(c["steps"]), 300, name + ": STEPS is the method's own")
	var input := _input(i)
	var graph := {"nodes": input["nodes"], "edges": input["edges"]}
	var got := OWLayout.layout_by_links_3d(graph, input.get("rows"), input.get("held"), input.get("heldUnit"))
	var want: Dictionary = c["want"]
	if want.has("refused"):
		t.ok(got.has("error"), "%s: refused (%s)" % [name, str(got.get("error", "no error"))])
		t.eq(got.get("code", ""), want["refused"], name + ": the refusal's code")
		t.done()
		return
	t.eq(got.get("error", ""), "", name + ": an answer")
	if got.has("error"):
		t.done()
		return
	t.eq(got["method"], "by-links-3d", name + ": the method")
	var rows: Array = got["points"]
	var cols := {"ids": "id", "how": "how", "group": "group", "part": "part", "held": "held"}
	for key in cols:
		var have := []
		for r in rows:
			have.append(r[cols[key]])
		t.eq(have, want[key], "%s: %s" % [name, key])
	t.eq(got["centres"], want["centres"], name + ": centres")
	t.eq(got["unplaced"], want["unplaced"], name + ": unplaced")

	var ring := _ring_nodes(input, want)
	var wp: Array = _wants()["cases"][name]["points"]
	var off := []
	for k in mini(rows.size(), wp.size() / 3):
		var r: Dictionary = rows[k]
		var loose: bool = ring.has(r["id"]) or (not r["held"] and (r["how"] == "arm" or r["how"] == "link"))
		var have: Array = [r["x"], r["y"], r["z"]]
		for a in 3:
			var w := _from_hex(wp[3 * k + a])
			var h: float = have[a]
			var ok := absf(h - w) <= WITHIN if loose else h == w
			if not ok:
				var call := "step 11, the ring's asin, cos and sin" if ring.has(r["id"]) else ("step 9, the fan's cos and sin" if loose else "exact arithmetic, no math call")
				off.append("%s %s (%s%s; %s): %s against %s (%s against %s)" % [r["id"], "xyz"[a], r["how"], ", ring" if ring.has(r["id"]) else "",
					call, String.num_scientific(h), String.num_scientific(w), _hex(h), _hex(w)])
	t.eq(rows.size() * 3, wp.size(), name + ": three numbers a point")
	t.eq(off.size(), 0, "%s: %d coordinates differ from the fixture: %s" % [name, off.size(), "; ".join(off.slice(0, 6))])
	t.done()

func test_the_directions_table_is_the_vendored_table_bit_for_bit(t) -> void:
	var bits: Array = _wants()["directions"]
	t.eq(_wants()["table_sha256"], TABLE_SHA256, "the bits file was made from this table")
	t.eq(_wants()["fixture_sha256"], FIXTURE_SHA256, "the bits file was made from this fixture")
	t.eq(OWLayoutDirections.TABLE_SHA256, TABLE_SHA256, "the directions were generated from this table")
	t.eq(OWLayoutDirections.K_MAX, 37, "K up to 37")
	t.eq(OWLayoutDirections.BITS.size(), 3 * 37 * 38 / 2, "703 vectors")
	var floats := PackedInt64Array(OWLayoutDirections.BITS).to_byte_array().to_float64_array()
	var off := 0
	for i in mini(floats.size(), bits.size()):
		if _hex(floats[i]) != bits[i]:
			off += 1
	t.eq(off, 0, "directions that differ from the table's bits")
	t.done()

func test_the_golden_angle_is_the_pages_expression_and_the_packages_literal(t) -> void:
	t.eq(_hex(OWLayoutByLinks3d.gold()), "4003331febfa4bfb", "PI * (3 - sqrt(5)), 2.399963229728653 to the bit")
	t.done()

func _unplaced(t, name: String) -> void:
	var c := {}
	for u in _fixture()["unplaced"]:
		if u["name"] == name:
			c = u
	var got := OWLayout.unplaced_by_links_3d(c["graph"].duplicate(true), c["placed"].duplicate(true))
	t.eq(got.get("error", ""), "", name + ": an answer")
	t.eq(got.get("method", ""), "by-links-3d", name + ": the method")
	t.eq(got.get("unplaced", null), c["want"], name + ": the ids, in the one order")
	t.done()

func test_the_fixture_and_its_table_are_the_pinned_dists_bytes(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(FIXTURE), FIXTURE_SHA256, "the fixture's bytes are the ones this test pins")
	t.eq(manifest["profiles/layout-by-links-3d.fixture.json"], FIXTURE_SHA256, "the fixture's bytes are the pinned dist's")
	t.eq(FileAccess.get_sha256(TABLE), TABLE_SHA256, "the table's bytes are the ones this test pins")
	t.eq(manifest["profiles/layout-by-links-3d.directions.json"], TABLE_SHA256, "the table's bytes are the pinned dist's")
	t.eq(_fixture()["table_sha256"], TABLE_SHA256, "the fixture names the table by its sha256")
	t.eq(_fixture()["method"], "by-links-3d", "the method word")
	t.eq(_fixture()["cases"].size(), 116, "116 cases")
	t.eq(_fixture()["unplaced"].size(), 9, "nine unplaced cases")
	t.done()

func test_unplaced_by_links_3d_refuses_a_graph_it_cannot_count(t) -> void:
	t.ok(String(OWLayout.unplaced_by_links_3d(null, []).get("error", "")).contains("the graph is { nodes, edges }"), "no graph")
	t.ok(String(OWLayout.unplaced_by_links_3d({"nodes": [{"type": "pin"}], "edges": []}, []).get("error", "")).contains("node 0 has no id"), "no id")
	t.ok(String(OWLayout.unplaced_by_links_3d({"nodes": [{"id": "a"}, {"id": "a"}], "edges": []}, []).get("error", "")).contains("two nodes share the id a"), "an id twice")
	t.eq(OWLayout.unplaced_by_links_3d({"nodes": [{"id": "b", "type": "pin"}, {"id": "a", "type": "map"}], "edges": []}, ["b"]).get("unplaced"), ["a"], "any type counts")
	t.done()
