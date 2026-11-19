class_name OWLayoutByLinks3d
extends RefCounted
## The [code]by-links-3d[/code] layout, behind [method OWLayout.layout_by_links_3d]: a whole world in three dimensions by
## its links, with the world's Maps and Pins as a plate its pinned elements stand on, and points an earlier answer gave
## held still. Written from the default layouts page (schema-dist [code]profiles/layout.md[/code], [code]by-links-3d[/code],
## serial 137 on), step by step in the page's order and numbering, and checked against its fixture
## ([code]profiles/layout-by-links-3d.fixture.json[/code]): [code]tests/test_layout_by_links_3d.gd[/code]. The npm SDK's
## [code]layoutByLinks3d[/code], the Python package's [code]layout_links_3d[/code] and the Unity SDK's
## [code]OWLayout.LayoutByLinks3d[/code] read the same page.
##
## Every number is a GDScript [float], a 64-bit double, held in [PackedFloat64Array]s, never a [Vector3] (32-bit in a
## standard build); every expression is worked as the page writes it, left to right, nothing regrouped (GDScript runs
## each operator on its own, so nothing is fused), and every [code]/[/code] divides doubles. Steps 1 to 8 use
## [code]+ - * /[/code], [method @GlobalScope.sqrt], [method @GlobalScope.floor], the lesser and the greater of two, and the
## generator's whole numbers (64-bit [int]s); step 9 [method @GlobalScope.cos] and [method @GlobalScope.sin], and step 11
## [method @GlobalScope.asin], cos and sin, all on doubles, which is why the points they place are held to 6e-8 and every
## other point to the last bit. The directions are generated data ([OWLayoutDirections]), never computed.

const REST := 60.0
const STEPS := 300
const MAX_CENTRES := 12
const MIN_GROUP := 3
const WAYS_CAP := 4503599627370496.0
const SPREAD := 2.0
const TILE := 0.4
const LOBE := 1.1
const GAP := 1.25
const CLEAR := 1.8
const PACK_STEPS := 600
const CROSS := 0.25
const PLATE := 0.02
const HOLD := 0.12
const CAP0 := 0.1
const CUTOFF := 3.0
const LINE := REST / 8.0
const SNAP := REST / 1000000000.0
const HELD_BOX := 768.0
const FRAME_AGREE := 3
const FIT := 0.000001
const OPPOSING := ["rivals", "adversaries", "rival", "antagonist"]

const HOW_CENTRE := 0
const HOW_WITH := 1
const HOW_ARM := 2
const HOW_LINK := 3
const HOW_OFF := 4
const HOW_MAP := 5
const HOW_WORDS := ["centre", "with", "arm", "link", "off", "map"]

## The version of the method's answers, the npm SDK's [code]BY_LINKS_3D_VERSION[/code]: raised whenever an answer to a
## case of the method's fixture moves.
const VERSION := 2

static var _gold := PI * (3.0 - sqrt(5.0))
static var _ring_gap := CLEAR * REST
static var _dirs := PackedFloat64Array()

## The golden angle, [code]PI * (3 - sqrt(5))[/code] as the page writes it.
static func gold() -> float:
	return _gold

## See [method OWLayout.layout_by_links_3d].
static func layout(graph: Variant, elements: Variant = null, held: Variant = null, held_unit: Variant = null) -> Dictionary:
	var given_nodes: Variant = null
	var given_edges: Variant = null
	if graph is OWGraph.Graph:
		given_nodes = graph.nodes
		given_edges = graph.edges
	elif graph is Dictionary:
		given_nodes = graph.get("nodes")
		given_edges = graph.get("edges")
	if not (given_nodes is Array) or not (given_edges is Array):
		return {"error": "layout_by_links_3d: the graph is { nodes, edges }, as world_graph answers it"}
	var h := _read_held(held)
	if h.has("error"):
		return h
	var u := _read_unit(held_unit)
	if u.has("error"):
		return u
	var handed := []
	for i in given_nodes.size():
		var node: Variant = given_nodes[i]
		var id: Variant = node.get("id") if node is Dictionary else null
		if typeof(id) != TYPE_STRING:
			return {"error": "layout_by_links_3d: node %d has no id" % i}
		handed.append(id)
	var edges := []
	for e in given_edges:
		if not (e is Dictionary):
			continue
		var s: Variant = e.get("source")
		var t: Variant = e.get("target")
		if typeof(s) != TYPE_STRING or typeof(t) != TYPE_STRING:
			continue
		var f: Variant = e.get("field")
		edges.append([s, t, f if typeof(f) == TYPE_STRING else null])
	var space: Variant = null
	if elements != null:
		if not (elements is Array):
			return {"error": "layout_by_links_3d: elements is an Array of the world's element Dictionaries, or null"}
		space = _space_of(elements)
	return _pieces(handed, edges, space, h["held"], u["unit"])

# ---- What is read besides the graph --------------------------------------------------------------------------------

static func _id_of(v: Variant) -> Variant:
	if (v is String or v is StringName) and String(v) != "":
		return String(v)
	return null

## The world's Maps and Pins as the map-space reading answers them, a layout map left out with its Pins (its rule 11):
## {maps: [{id, width, height, location}], pins: [{pin, map, element_id, x, y}]}.
static func _space_of(elements: Array) -> Dictionary:
	var ms := OWMapSpace.map_space(elements)
	var raw_maps := {}
	var raw_pins := {}
	for e in elements:
		if not (e is Dictionary and e.get("type") is String):
			continue
		var id: Variant = _id_of(e.get("id"))
		if id == null:
			continue
		if e["type"] == "map":
			raw_maps[id] = e
		elif e["type"] == "pin":
			raw_pins[id] = e
	var map_rows := raw_maps.values()
	var pin_rows := raw_pins.values()
	var maps := []
	for m in ms.maps:
		if OWMapSpace.layout_of(raw_maps[m["id"]], map_rows, pin_rows).layout != null:
			continue
		maps.append(m)
	return {"maps": maps, "pins": ms.pins}

# ---- Held points: the refusals before anything runs ---------------------------------------------------------------

static func _refuse(code: String, message: String) -> Dictionary:
	return {"error": "layout_by_links_3d: " + message, "code": code}

## {held: [[id, PackedFloat64Array(3)], ...] or null}, or a refusal.
static func _read_held(held: Variant) -> Dictionary:
	if held == null:
		return {"held": null}
	if not (held is Dictionary):
		return _refuse("held-not-object", "held is not a mapping of ids to points")
	for key in held:
		if not (key is String or key is StringName):
			return _refuse("held-not-object", "held is not a mapping of ids to points")
	var entries := []
	for key in held:
		var a: Variant = held[key]
		if a is PackedFloat64Array or a is PackedFloat32Array or a is PackedInt64Array or a is PackedInt32Array:
			a = Array(a)
		if not (a is Array) or a.size() != 3:
			return _refuse("held-not-point", "held[%s] is not three finite numbers" % key)
		var q := PackedFloat64Array()
		q.resize(3)
		for i in 3:
			var x: Variant = a[i]
			if typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT:
				return _refuse("held-not-point", "held[%s] is not three finite numbers" % key)
			q[i] = float(x)
			if not is_finite(q[i]):
				return _refuse("held-not-point", "held[%s] is not three finite numbers" % key)
		entries.append([String(key), q])
	return {"held": entries}

static func _read_unit(unit: Variant) -> Dictionary:
	if unit == null:
		return {"unit": 0.0}
	if typeof(unit) == TYPE_INT or typeof(unit) == TYPE_FLOAT:
		var u := float(unit)
		if is_finite(u) and u >= 0.0 and u <= LINE:
			return {"unit": u}
	return _refuse("held-unit", "heldUnit %s is not a finite number from 0 to %s" % [str(unit), str(LINE)])

## The box test of the held points one run holds (Held points, Refused): {} or a refusal.
static func _test_box(held: Variant) -> Dictionary:
	if held == null or held.is_empty():
		return {}
	for a in 3:
		var lo := INF
		var hi := -INF
		for p in held:
			var q: PackedFloat64Array = p[1]
			if q[a] < lo:
				lo = q[a]
			if q[a] > hi:
				hi = q[a]
		if hi - lo > HELD_BOX * REST:
			return _refuse("held-box", "the held points' box is %s rests on %s, wider than %s" % [str((hi - lo) / REST), "xyz"[a], str(HELD_BOX)])
	return {}

# ---- Steps 10 to 12: the pieces, the ring and the answer ----------------------------------------------------------

static func _xyz(points: PackedFloat64Array, i: int) -> PackedFloat64Array:
	return PackedFloat64Array([points[3 * i], points[3 * i + 1], points[3 * i + 2]])

static func _pieces(handed: Array, edges: Array, space: Variant, held: Variant, unit: float) -> Dictionary:
	var n := handed.size()
	if n == 0:
		return {"method": "by-links-3d", "version": VERSION, "points": [], "centres": [], "unplaced": []}
	var ids := handed.duplicate()
	ids.sort()
	for i in range(1, n):
		if ids[i] == ids[i - 1]:
			return {"error": "layout_by_links_3d: two nodes share the id %s" % ids[i]}
	var at := {}
	for i in n:
		at[ids[i]] = i

	# The pieces: a path of pairs joins two nodes of one piece; the main piece the largest, a tie to the lowest node.
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	for e in edges:
		var a: int = at.get(e[0], -1)
		var b: int = at.get(e[1], -1)
		if a < 0 or b < 0 or a == b:
			continue
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra != rb:
			if ra < rb:
				parent[rb] = ra
			else:
				parent[ra] = rb
	var piece_of := PackedInt32Array()
	piece_of.resize(n)
	var root_piece := PackedInt32Array()
	root_piece.resize(n)
	root_piece.fill(-1)
	var pieces := []
	for v in n:
		var r := _find(parent, v)
		if root_piece[r] == -1:
			root_piece[r] = pieces.size()
			pieces.append([])
		piece_of[v] = root_piece[r]
		pieces[piece_of[v]].append(v)
	var main_p := -1
	var main_size := 0
	for p in pieces.size():
		if pieces[p].size() <= main_size:
			continue
		main_size = pieces[p].size()
		main_p = p

	# The main run holds the held points of the main piece's nodes (when it holds a pair) and of every pinned node.
	var held_all := {}
	if held != null:
		for p in held:
			held_all[p[0]] = p[1]
	var on_map := {}
	if space != null:
		var pa: Variant = _plate_of(space, at, null)
		if pa != null:
			for id in pa["order"]:
				on_map[id] = true
	var main_held: Variant = null
	if held != null:
		main_held = []
		for p in held:
			var v: int = at.get(p[0], -1)
			if v >= 0 and ((main_size >= 2 and piece_of[v] == main_p) or on_map.has(p[0])):
				main_held.append(p)
	var main := _run(handed, edges, space, main_held, unit)
	if main.has("error"):
		return main
	var mpts: PackedFloat64Array = main["points"]
	var mrow: Dictionary = main["row"]

	var pinned := PackedByteArray()
	pinned.resize(n)
	var keep := PackedByteArray()
	keep.resize(n)
	for v in n:
		if main["how"][mrow[ids[v]]] == HOW_MAP:
			pinned[v] = 1
		if (main_size >= 2 and piece_of[v] == main_p) or pinned[v] == 1:
			keep[v] = 1

	# Step 11's order: every other piece that holds a pair, most nodes first, a tie to the lower least node.
	var others := []
	for p in pieces.size():
		if p != main_p and pieces[p].size() >= 2:
			others.append(p)
	others.sort_custom(func(p: int, q: int) -> bool:
		if pieces[p].size() != pieces[q].size():
			return pieces[p].size() > pieces[q].size()
		return pieces[p][0] < pieces[q][0])

	# A piece's run: its nodes and its edges in the order handed in, no Maps, its pinned nodes held at their main-run points.
	var runs := {}
	var moved := {}
	for p in others:
		var in_p := {}
		for v in pieces[p]:
			in_p[ids[v]] = true
		var pnodes := []
		for id in handed:
			if in_p.has(id):
				pnodes.append(id)
		var pedges := []
		for e in edges:
			if in_p.has(e[0]) and in_p.has(e[1]):
				pedges.append(e)
		var sub := []
		for v in pieces[p]:
			if pinned[v] == 1:
				sub.append([ids[v], _xyz(mpts, mrow[ids[v]])])
			elif held_all.has(ids[v]):
				sub.append([ids[v], held_all[ids[v]]])
		var r := _run(pnodes, pedges, null, sub if not sub.is_empty() else null, unit)
		if r.has("error"):
			return r
		runs[p] = r
		moved[p] = sub.is_empty()

	# Step 11. The main shape: M over the nodes taken from the main run, in the one order; Rmain over those and every
	# node of a piece that is not moved.
	var cnt := 0
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	for v in n:
		if keep[v] == 0:
			continue
		var m: int = mrow[ids[v]]
		sx += mpts[3 * m]
		sy += mpts[3 * m + 1]
		sz += mpts[3 * m + 2]
		cnt += 1
	var M := PackedFloat64Array([0.0, 0.0, 0.0])
	if cnt > 0:
		M = PackedFloat64Array([sx / cnt, sy / cnt, sz / cnt])
	var r_main := 0.0
	for v in n:
		if keep[v] == 0:
			continue
		var m: int = mrow[ids[v]]
		r_main = _farther(r_main, mpts[3 * m] - M[0], mpts[3 * m + 1] - M[1], mpts[3 * m + 2] - M[2])
	for p in others:
		if moved[p]:
			continue
		var u: Dictionary = runs[p]
		var up: PackedFloat64Array = u["points"]
		for v in pieces[p]:
			if pinned[v] == 1:
				continue
			var j: int = u["row"][ids[v]]
			r_main = _farther(r_main, up[3 * j] - M[0], up[3 * j + 1] - M[1], up[3 * j + 2] - M[2])

	var ring_list := []
	for p in others:
		if moved[p]:
			ring_list.append(p)
	var c := {}
	var rp := {}
	for p in ring_list:
		var u: Dictionary = runs[p]
		var up: PackedFloat64Array = u["points"]
		var qx := 0.0
		var qy := 0.0
		var qz := 0.0
		for v in pieces[p]:
			var i: int = u["row"][ids[v]]
			qx += up[3 * i]
			qy += up[3 * i + 1]
			qz += up[3 * i + 2]
		var k: int = pieces[p].size()
		var cp := PackedFloat64Array([qx / k, qy / k, qz / k])
		var r := 0.0
		for v in pieces[p]:
			var i: int = u["row"][ids[v]]
			r = _farther(r, up[3 * i] - cp[0], up[3 * i + 1] - cp[1], up[3 * i + 2] - cp[2])
		c[p] = cp
		rp[p] = r

	var rmax := 0.0
	for p in ring_list:
		if rp[p] > rmax:
			rmax = rp[p]
	var shift := {}
	var fit_edge := 2.0 * PI - FIT
	var ring_r := r_main + _ring_gap + rmax
	var on := []
	var sum := 0.0
	for p in ring_list:
		var th := 2.0 * asin((rp[p] + _ring_gap / 2.0) / ring_r)
		if on.size() > 0 and not (sum + th <= fit_edge):
			_close_ring(on, sum, ring_r, M, c, shift)
			ring_r = ring_r + 2.0 * rmax + _ring_gap
			on = []
			sum = 0.0
			th = 2.0 * asin((rp[p] + _ring_gap / 2.0) / ring_r)
		on.append([p, th])
		sum = sum + th
	if on.size() > 0:
		_close_ring(on, sum, ring_r, M, c, shift)

	# Step 12. The answer, in the order the nodes were handed in.
	var rows := []
	var unplaced := []
	var placed := {}
	for id in handed:
		var v: int = at[id]
		if keep[v] == 1:
			var m: int = mrow[id]
			var group: Variant = main["group"][m]
			var part: Variant = main["part"][m]
			if pinned[v] == 1 and piece_of[v] != main_p and runs.has(piece_of[v]) and runs[piece_of[v]]["centres"].has(id):
				group = id
				part = null
			rows.append({"id": id, "x": mpts[3 * m], "y": mpts[3 * m + 1], "z": mpts[3 * m + 2],
				"how": HOW_WORDS[main["how"][m]], "group": group, "part": part, "held": main["held"][m]})
			placed[id] = true
			continue
		var p := piece_of[v]
		if pieces[p].size() < 2:
			unplaced.append(v)
			continue
		var u: Dictionary = runs[p]
		var up: PackedFloat64Array = u["points"]
		var j: int = u["row"][id]
		var x := up[3 * j]
		var y := up[3 * j + 1]
		var z := up[3 * j + 2]
		if shift.has(p):
			var T: PackedFloat64Array = shift[p]
			x = x + T[0]
			y = y + T[1]
			z = z + T[2]
		rows.append({"id": id, "x": x, "y": y, "z": z, "how": HOW_WORDS[u["how"][j]], "group": u["group"][j],
			"part": u["part"][j], "held": u["held"][j]})
		placed[id] = true

	unplaced.sort()
	var centres := []
	for id in main["centres"]:
		if placed.has(id):
			centres.append(id)
	for p in others:
		centres.append_array(runs[p]["centres"])
	var unplaced_ids := []
	for v in unplaced:
		unplaced_ids.append(ids[v])
	return {"method": "by-links-3d", "version": VERSION, "points": rows, "centres": centres, "unplaced": unplaced_ids}

static func _find(parent: PackedInt32Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a

static func _len3(x: float, y: float, z: float) -> float:
	return sqrt(x * x + y * y + z * z)

static func _farther(r: float, dx: float, dy: float, dz: float) -> float:
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	return d if d > r else r

## One ring closed: each of its pieces' shift T, from the angle the ring leaves over shared one share after each piece.
static func _close_ring(on: Array, sum: float, ring_r: float, M: PackedFloat64Array, c: Dictionary, shift: Dictionary) -> void:
	var share := (2.0 * PI - sum) / on.size()
	var a := 0.0
	for q in on:
		var th: float = q[1]
		var phi := a + th / 2.0
		a = a + (th + share)
		var cp: PackedFloat64Array = c[q[0]]
		shift[q[0]] = PackedFloat64Array([M[0] + ring_r * cos(phi) - cp[0], M[1] + ring_r * sin(phi) - cp[1], M[2] - cp[2]])

# ---- Steps 1 to 9 and the held points' rules: one run -------------------------------------------------------------

static func _run(handed: Array, edges_in: Array, space: Variant, held_in: Variant, unit: float) -> Dictionary:
	var box := _test_box(held_in)
	if box.has("error"):
		return box
	var n := handed.size()

	# 1. The one order, and the pairs.
	var ids := handed.duplicate()
	ids.sort()
	var at := {}
	for i in n:
		at[ids[i]] = i
	var opp := []
	var seen := {}
	var pairs := []
	for e in edges_in:
		var a: int = at.get(e[0], -1)
		var b: int = at.get(e[1], -1)
		if a < 0 or b < 0:
			continue
		if e[2] != null and OPPOSING.has(e[2]):
			opp.append([a, b])
		if a == b:
			continue
		var lo := a if a < b else b
		var hi := b if a < b else a
		var key := lo * n + hi
		if not seen.has(key):
			seen[key] = true
			pairs.append([lo, hi])
	pairs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0] if p[0] != q[0] else p[1] < q[1])
	var adj := []
	adj.resize(n)
	for i in n:
		adj[i] = []
	for p in pairs:
		adj[p[0]].append(p[1])
		adj[p[1]].append(p[0])
	for i in n:
		adj[i].sort()
	var degree := PackedInt32Array()
	degree.resize(n)
	for i in n:
		degree[i] = adj[i].size()

	# 2. The body. 3. The centres and their groups.
	var bd := _body(n, adj)
	var body: PackedByteArray = bd["body"]
	var cg := _centres(n, adj, body)
	var taken: Array = cg["taken"]
	var group: PackedInt32Array = cg["group"]
	var k := taken.size()

	# The held points that are nodes (a held id that is no node is passed over).
	var hflag: Variant = null
	var hat := PackedFloat64Array()
	if held_in != null:
		for p in held_in:
			var v: int = at.get(p[0], -1)
			if v < 0:
				continue
			if hflag == null:
				hflag = PackedByteArray()
				hflag.resize(n)
				hat.resize(3 * n)
			hflag[v] = 1
			var q: PackedFloat64Array = p[1]
			hat[3 * v] = q[0]
			hat[3 * v + 1] = q[1]
			hat[3 * v + 2] = q[2]

	# 4. The plate; with held points, H1's frame, and the plate again at the frame's scale.
	var plate: Variant = null
	var frame_p: Variant = null
	if space != null:
		plate = _plate_of(space, at, null)
		if plate != null and hflag != null:
			var fr: Variant = _frame_of(plate, at, hflag, hat, unit)
			if fr != null:
				frame_p = fr["F"]
				plate = _plate_of(space, at, fr["s"])

	# H2: each group's case; H3's fixed parts and H4's snap for step 5; H5's kept nodes.
	var keep: Variant = null
	var free: Variant = null
	var gflag: Variant = null
	var gat := PackedFloat64Array()
	var extra := []
	if hflag != null:
		var pinned_v := PackedByteArray()
		pinned_v.resize(n)
		if plate != null:
			for id in plate["order"]:
				pinned_v[at[id]] = 1
		keep = PackedByteArray()
		keep.resize(n)
		for v in n:
			keep[v] = 1 if hflag[v] == 1 and pinned_v[v] == 0 else 0
		gflag = PackedByteArray()
		gflag.resize(k)
		gat.resize(3 * k)
		free = PackedByteArray()
		free.resize(k)
		var gs := PackedFloat64Array()
		gs.resize(3 * k)
		var gc := PackedInt32Array()
		gc.resize(k)
		for v in n:
			if body[v] == 0 or keep[v] == 0:
				continue
			var g := group[v]
			gs[3 * g] += hat[3 * v]
			gs[3 * g + 1] += hat[3 * v + 1]
			gs[3 * g + 2] += hat[3 * v + 2]
			gc[g] += 1
		for g in k:
			var t: int = taken[g]
			if pinned_v[t] == 1:
				continue
			if keep[t] == 1:
				gflag[g] = 1
				gat[3 * g] = hat[3 * t]
				gat[3 * g + 1] = hat[3 * t + 1]
				gat[3 * g + 2] = hat[3 * t + 2]
			elif gc[g] > 0:
				gflag[g] = 1
				free[g] = 1
				gat[3 * g] = gs[3 * g] / gc[g]
				gat[3 * g + 1] = gs[3 * g + 1] / gc[g]
				gat[3 * g + 2] = gs[3 * g + 2] / gc[g]
			else:
				free[g] = 1
		for v in n:
			if keep[v] == 1 and body[v] == 0:
				extra.append(v)

	# 5. Where each group's point stands.
	var pts := _group_points(n, body, taken, group, pairs, opp, plate, at, gflag, gat, frame_p, hflag, hat, 3.0 * unit + SNAP)

	# 6 to 8. The feed, the start, the steps.
	var relaxed := _force_steps(ids, body, pairs, taken, group, pts, keep, hat, free, extra)

	# 9. What is placed after the steps.
	var hung := _hang(n, body, bd["cut"], bd["depth"], bd["off"], taken, group, pts, degree, relaxed, keep, hat)
	var how: PackedInt32Array = hung["how"]
	var pos: PackedFloat64Array = hung["pos"]

	# The run's answer, in the order handed in.
	var points := PackedFloat64Array()
	points.resize(3 * n)
	var hows := PackedInt32Array()
	hows.resize(n)
	var groups := []
	var parts := []
	var helds := []
	var row := {}
	for i in n:
		var v: int = at[handed[i]]
		row[handed[i]] = i
		points[3 * i] = pos[3 * v]
		points[3 * i + 1] = pos[3 * v + 1]
		points[3 * i + 2] = pos[3 * v + 2]
		helds.append(keep != null and keep[v] == 1)
		var w := how[v]
		hows[i] = w
		var own: bool = body[v] == 1 and taken[group[v]] == v
		var g_word: Variant = null
		var p_word: Variant = null
		if w == HOW_CENTRE or w == HOW_WITH or (w == HOW_MAP and own):
			g_word = ids[taken[group[v]]]
		elif w == HOW_MAP:
			p_word = "map"
		elif w == HOW_ARM or w == HOW_LINK:
			p_word = "one-link"
		groups.append(g_word)
		parts.append(p_word)
	var centres := []
	for t in taken:
		centres.append(ids[t])
	return {"points": points, "how": hows, "group": groups, "part": parts, "held": helds, "centres": centres, "row": row}

# ---- Step 2: the body ---------------------------------------------------------------------------------------------

## {body, cut, depth, off}: the body's nodes, each hanging node's cut and depth (-1 for none), and the nodes off the
## main piece.
static func _body(n: int, adj: Array) -> Dictionary:
	# The pieces; the main piece the largest, a tie to the one that holds the lowest node.
	var piece := PackedInt32Array()
	piece.resize(n)
	piece.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n)
	var main := -1
	var main_size := 0
	var pieces := 0
	for s in n:
		if piece[s] != -1:
			continue
		var head := 0
		var tail := 0
		queue[tail] = s
		tail += 1
		piece[s] = pieces
		while head < tail:
			var v := queue[head]
			head += 1
			for w: int in adj[v]:
				if piece[w] != -1:
					continue
				piece[w] = pieces
				queue[tail] = w
				tail += 1
		if tail > main_size:
			main_size = tail
			main = pieces
		pieces += 1

	# The blocks (Hopcroft and Tarjan, without recursion); the body is the block with the most members, a tie to the one
	# whose members in rising order are the higher at the first place they differ.
	var body := PackedByteArray()
	body.resize(n)
	if main_size == 1:
		for i in n:
			if piece[i] == main:
				body[i] = 1
	elif main_size > 1:
		var disc := PackedInt32Array()
		disc.resize(n)
		disc.fill(-1)
		var low := PackedInt32Array()
		low.resize(n)
		var par := PackedInt32Array()
		par.resize(n)
		par.fill(-1)
		var nxt := PackedInt32Array()
		nxt.resize(n)
		var stamp := PackedInt32Array()
		stamp.resize(n)
		stamp.fill(-1)
		var stack_v := PackedInt32Array()
		stack_v.resize(n)
		var edge_a := []
		var edge_b := []
		var best := []
		var blocks := 0
		var clock := 0
		var top := 0
		var root := 0
		while piece[root] != main:
			root += 1
		disc[root] = clock
		low[root] = clock
		clock += 1
		stack_v[top] = root
		top += 1
		while top > 0:
			var v := stack_v[top - 1]
			var av: Array = adj[v]
			if nxt[v] < av.size():
				var w: int = av[nxt[v]]
				nxt[v] += 1
				if disc[w] == -1:
					par[w] = v
					disc[w] = clock
					low[w] = clock
					clock += 1
					edge_a.append(v)
					edge_b.append(w)
					stack_v[top] = w
					top += 1
				elif w != par[v] and disc[w] < disc[v]:
					edge_a.append(v)
					edge_b.append(w)
					if disc[w] < low[v]:
						low[v] = disc[w]
			else:
				top -= 1
				var u := par[v]
				if u == -1:
					continue
				if low[v] < low[u]:
					low[u] = low[v]
				if low[v] < disc[u]:
					continue
				var members := []
				while true:
					var a: int = edge_a.pop_back()
					var b: int = edge_b.pop_back()
					if stamp[a] != blocks:
						stamp[a] = blocks
						members.append(a)
					if stamp[b] != blocks:
						stamp[b] = blocks
						members.append(b)
					if a == u and b == v:
						break
				if members.size() >= best.size():
					members.sort()
					var wins := members.size() > best.size()
					if not wins:
						for i in members.size():
							if members[i] != best[i]:
								wins = members[i] > best[i]
								break
					if wins:
						best = members
				blocks += 1
		for v in best:
			body[v] = 1

	# What hangs: outward from the whole body at once, each node's cut and its depth from it.
	var cut := PackedInt32Array()
	cut.resize(n)
	cut.fill(-1)
	var depth := PackedInt32Array()
	depth.resize(n)
	var qh := 0
	var qt := 0
	for i in n:
		if body[i] == 1:
			queue[qt] = i
			qt += 1
	while qh < qt:
		var v := queue[qh]
		qh += 1
		for w: int in adj[v]:
			if body[w] == 1 or cut[w] != -1:
				continue
			cut[w] = v if body[v] == 1 else cut[v]
			depth[w] = depth[v] + 1
			queue[qt] = w
			qt += 1
	var off := PackedByteArray()
	off.resize(n)
	for i in n:
		off[i] = 1 if piece[i] != main else 0
	return {"body": body, "cut": cut, "depth": depth, "off": off}

# ---- Step 3: the centres and their groups -------------------------------------------------------------------------

## {taken, group}: the centres in rank order, and each body node's group (the rank of its centre).
static func _centres(n: int, adj: Array, body: PackedByteArray) -> Dictionary:
	var members := []
	for i in n:
		if body[i] == 1:
			members.append(i)
	var first := _pick(n, adj, members, body)
	var taken: Array = first["taken"]
	var group: PackedInt32Array = first["group"]
	for pass_n in 2:
		if taken.is_empty():
			break
		var sizes := PackedInt32Array()
		sizes.resize(taken.size())
		for v in members:
			sizes[group[v]] += 1
		var big := 0
		for r in range(1, taken.size()):
			if sizes[r] > sizes[big]:
				big = r
		if 2 * sizes[big] <= members.size():
			break
		var inside := []
		var in_set := PackedByteArray()
		in_set.resize(n)
		for v in members:
			if group[v] == big and v != taken[big]:
				inside.append(v)
				in_set[v] = 1
		var sub := _pick(n, adj, inside, in_set)
		var sub_taken: Array = sub["taken"]
		if sub_taken.size() < 2:
			break
		var bas := taken.size()
		taken.append_array(sub_taken)
		var sub_group: PackedInt32Array = sub["group"]
		var sub_dist: PackedInt32Array = sub["dist"]
		for v in inside:
			if sub_dist[v] != -1:
				group[v] = bas + sub_group[v]
	return {"taken": taken, "group": group}

## The page's pick on a set: {taken, group, dist}, the centres in rank order, and the last reach read.
static func _pick(n: int, adj: Array, members: Array, in_set: PackedByteArray) -> Dictionary:
	var size := members.size()
	var count := PackedInt32Array()
	count.resize(n)
	for v in members:
		var c := 0
		for w: int in adj[v]:
			if in_set[w] == 1:
				c += 1
		count[v] = c
	var ranked := members.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool: return count[a] > count[b] if count[a] != count[b] else a < b)
	var f := 0
	while f * f < size:
		f += 1
	var least := maxi(3, f)
	var mark := PackedInt64Array()
	mark.resize(n)
	var hit := PackedInt32Array()
	hit.resize(MAX_CENTRES)
	var taken := []
	for v in ranked:
		if count[v] < least or taken.size() == MAX_CENTRES:
			break
		hit.fill(0)
		for w: int in adj[v]:
			if in_set[w] == 0:
				continue
			for r in taken.size():
				hit[r] += (mark[w] >> r) & 1
		var ok := true
		for r in taken.size():
			if 2 * hit[r] >= count[v]:
				ok = false
				break
		if not ok:
			continue
		var rank := taken.size()
		taken.append(v)
		mark[v] |= 1 << rank
		for w: int in adj[v]:
			if in_set[w] == 1:
				mark[w] |= 1 << rank
	if taken.is_empty() and ranked.size() > 0:
		taken.append(ranked[0])
	while true:
		var rc := _reach_ways(n, adj, members, in_set, taken)
		var group: PackedInt32Array = rc["group"]
		var sizes := PackedInt32Array()
		sizes.resize(taken.size())
		for v in members:
			if group[v] != -1:
				sizes[group[v]] += 1
		var last := -1
		for r in taken.size():
			if sizes[r] < MIN_GROUP:
				last = r
		if last == -1 or taken.size() == 1:
			return {"taken": taken, "group": group, "dist": rc["dist"]}
		taken.remove_at(last)
	return {}

## The page's reach: levels from the centres, each node's count of shortest ways from each centre (capped at
## WAYS_CAP), and each node's group, the centre it has the most ways from (a tie to the lowest rank). {group, dist}.
static func _reach_ways(n: int, adj: Array, members: Array, in_set: PackedByteArray, taken: Array) -> Dictionary:
	var k := taken.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var group := PackedInt32Array()
	group.resize(n)
	group.fill(-1)
	var ways := PackedFloat64Array()
	ways.resize(n * k)
	var front := []
	for r in k:
		var t: int = taken[r]
		dist[t] = 0
		ways[t * k + r] = 1.0
		front.append(t)
	var d := 0
	while not front.is_empty():
		d += 1
		var next := []
		for v: int in front:
			for w: int in adj[v]:
				if in_set[w] == 0:
					continue
				if dist[w] == -1:
					dist[w] = d
					next.append(w)
				if dist[w] != d:
					continue
				for r in k:
					ways[w * k + r] = minf(WAYS_CAP, ways[w * k + r] + ways[v * k + r])
		front = next
	for r in k:
		group[taken[r]] = r
	for v: int in members:
		if dist[v] <= 0:
			continue
		var best := 0
		for r in range(1, k):
			if ways[v * k + r] > ways[v * k + best]:
				best = r
		group[v] = best
	return {"group": group, "dist": dist}

# ---- Step 4: the plate, and H1's frame ----------------------------------------------------------------------------

static func _sized(v: Variant) -> bool:
	return v != null and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v > 0

## The plate: {order, at, first}, the pinned elements in the order they were placed (the first map's, then each small
## plate's), each one's place (PackedFloat64Array(3)), and the first map's elements with their map places [id, mx, my];
## null for no plate. [param scale_held] is H1's frame's scale, or null for the page's own.
static func _plate_of(space: Dictionary, nodes: Dictionary, scale_held: Variant) -> Variant:
	var maps := {}
	for m in space["maps"]:
		maps[m["id"]] = m
	# By pin id in code point order (the map-space reading answers one Pin per id, already in that order).
	var pins: Array = space["pins"].duplicate()
	pins.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pin"] < b["pin"])
	var map_order := []
	var on := {}
	var on_has := {}
	for pin in pins:
		if pin["map"] == null or not maps.has(pin["map"]) or pin["element_id"] == null or not nodes.has(pin["element_id"]):
			continue
		if not on.has(pin["map"]):
			on[pin["map"]] = []
			on_has[pin["map"]] = {}
			map_order.append(pin["map"])
		if not on_has[pin["map"]].has(pin["element_id"]):
			on_has[pin["map"]][pin["element_id"]] = true
			on[pin["map"]].append([pin["element_id"], float(pin["x"]), float(pin["y"])])
	if map_order.is_empty():
		return null
	var first: Variant = null
	var best := -1
	for c in map_order:
		var size: int = on[c].size()
		if size > best or (size == best and c > first):
			first = c
			best = size
	var map: Dictionary = maps[first]
	var mine: Array = on[first]
	if mine.size() < 3 or not _sized(map["width"]) or not _sized(map["height"]):
		return null
	var W := float(map["width"])
	var H := float(map["height"])
	var many := float(mine.size())
	var scale: float = scale_held if scale_held != null else SPREAD * REST / sqrt(W * H / many)
	var order := []
	var at := {}
	var first_places := []
	for e in mine:
		var mx: float = e[1] - W / 2.0
		var my: float = e[2] - H / 2.0
		first_places.append([e[0], mx, my])
		order.append(e[0])
		at[e[0]] = PackedFloat64Array([mx * scale, my * scale, 0.0])
	var todo := []
	for x in map_order:
		if x != first:
			todo.append(x)
	todo.sort()
	var taken_any := true
	while taken_any:
		taken_any = false
		for c in todo.duplicate():
			var m: Dictionary = maps[c]
			var row: Array = on[c]
			var fresh := []
			for x in row:
				if not at.has(x[0]):
					fresh.append(x)
			if m["location"] == null or not at.has(m["location"]) or not _sized(m["width"]) or not _sized(m["height"]) or row.size() < 3 or fresh.is_empty():
				continue
			var l: PackedFloat64Array = at[m["location"]]
			var cw := float(m["width"])
			var ch := float(m["height"])
			var count := float(row.size())
			var sc := TILE * REST / sqrt(cw * ch / count)
			var rise := REST * 4.0 if row.size() >= 20 else REST * 2.0
			for e in fresh:
				order.append(e[0])
				at[e[0]] = PackedFloat64Array([l[0] + (e[1] - cw / 2.0) * sc, l[1] + (e[2] - ch / 2.0) * sc, l[2] + rise])
			todo.erase(c)
			taken_any = true
	return {"order": order, "at": at, "first": first_places}

## H1: the frame, where the plate stood when the held points were answered: {s, F}, or null when there is none.
static func _frame_of(plate: Dictionary, at: Dictionary, hflag: PackedByteArray, hat: PackedFloat64Array, unit: float) -> Variant:
	var cv := []
	var cx := PackedFloat64Array()
	var cy := PackedFloat64Array()
	for e in plate["first"]:
		var v: int = at[e[0]]
		if hflag[v] == 0:
			continue
		cv.append(v)
		cx.append(e[1])
		cy.append(e[2])
	var order := range(cv.size())
	order.sort_custom(func(p: int, q: int) -> bool: return cv[p] < cv[q])
	var m := order.size()
	var tol_z := unit + SNAP
	var band := 3.0 * unit + SNAP
	for ia in m:
		var a: int = order[ia]
		var va: int = cv[a]
		var ax := hat[3 * va]
		var ay := hat[3 * va + 1]
		var az := hat[3 * va + 2]
		var partners := []
		var bdist := PackedFloat64Array()
		for ib in m:
			var c: int = order[ib]
			if c == a:
				continue
			var dz := hat[3 * cv[c] + 2] - az
			if not (dz <= tol_z and -dz <= tol_z):
				continue
			if cx[c] == cx[a] and cy[c] == cy[a]:
				continue
			var mx := cx[c] - cx[a]
			var my := cy[c] - cy[a]
			partners.append(c)
			bdist.append(sqrt(mx * mx + my * my))
		var by_far := range(partners.size())
		by_far.sort_custom(func(p: int, q: int) -> bool: return bdist[p] > bdist[q] if bdist[p] != bdist[q] else p < q)
		for ib: int in by_far:
			var b: int = partners[ib]
			var vb: int = cv[b]
			var hx := hat[3 * vb] - ax
			var hy := hat[3 * vb + 1] - ay
			if hx == 0.0 and hy == 0.0:
				continue
			var sc := sqrt(hx * hx + hy * hy) / bdist[ib]
			var P := PackedFloat64Array([ax - sc * cx[a], ay - sc * cy[a], az])
			var agree := 0
			for ic in m:
				var c: int = order[ic]
				var vc: int = cv[c]
				var ex := hat[3 * vc] - (P[0] + sc * cx[c])
				var ey := hat[3 * vc + 1] - (P[1] + sc * cy[c])
				var ez := hat[3 * vc + 2] - P[2]
				if ex <= band and -ex <= band and ey <= band and -ey <= band and ez <= band and -ez <= band:
					agree += 1
			if agree < FRAME_AGREE:
				continue
			return {"s": sc, "F": P}
	return null

# ---- Step 5: where each group's point stands ----------------------------------------------------------------------

static func _dir(K: int, s: int, axis: int) -> float:
	if _dirs.is_empty():
		_dirs = PackedInt64Array(OWLayoutDirections.BITS).to_byte_array().to_float64_array()
	return _dirs[3 * K * (K - 1) / 2 + 3 * s + axis]

## The page's cube root: 0 for v not over 0; else from sqrt(v), or 1 when that is under 1, forty Newton steps.
static func _root(v: float) -> float:
	if not (v > 0.0):
		return 0.0
	var x := sqrt(v)
	if x < 1.0:
		x = 1.0
	for i in 40:
		x = (2.0 * x + v / (x * x)) / 3.0
	return x

## {size, link, opp}: each part's size, and link and opp for each pair of parts (at p * K + q, p < q).
static func _counts(n: int, K: int, part: PackedInt32Array, pairs: Array, opps: Array) -> Dictionary:
	var size := PackedInt32Array()
	size.resize(K)
	var link := PackedInt32Array()
	link.resize(K * K)
	var opp := PackedInt32Array()
	opp.resize(K * K)
	for v in n:
		if part[v] != -1:
			size[part[v]] += 1
	for pr in pairs:
		var p := part[pr[0]]
		var q := part[pr[1]]
		if p == -1 or q == -1 or p == q:
			continue
		if p < q:
			link[p * K + q] += 1
		else:
			link[q * K + p] += 1
	for e in opps:
		var p := part[e[0]]
		var q := part[e[1]]
		if p == -1 or q == -1 or p == q:
			continue
		if p < q:
			opp[p * K + q] += 1
		else:
			opp[q * K + p] += 1
	return {"size": size, "link": link, "opp": opp}

static func _by_size(K: int, size: PackedInt32Array) -> Array:
	var order := range(K)
	order.sort_custom(func(a: int, b: int) -> bool: return size[a] > size[b] if size[a] != size[b] else a < b)
	return order

## Each part's direction: the two ends, then the rest by size, each the free direction of least cost.
static func _directions(K: int, size: PackedInt32Array, link: PackedInt32Array, opp: PackedInt32Array) -> PackedFloat64Array:
	var dirs := PackedFloat64Array()
	dirs.resize(3 * K)
	if K == 1:
		return dirs
	assert(K <= OWLayoutDirections.K_MAX, "layout_by_links_3d: the directions table has no row of %d directions" % K)
	var any_opp := false
	for i in K:
		for j in range(i + 1, K):
			if opp[i * K + j] > 0:
				any_opp = true
	var b0 := -1
	var b1 := -1
	if any_opp:
		var bo := -1
		var bs := -1
		for i in K:
			for j in range(i + 1, K):
				var o := opp[i * K + j]
				var s := size[i] + size[j]
				if o > bo or (o == bo and s > bs):
					bo = o
					bs = s
					b0 = i
					b1 = j
	else:
		var by_size := _by_size(K, size)
		var big := by_size.slice(0, mini(K, 4))
		big.sort()
		for x in big.size():
			for y in range(x + 1, big.size()):
				var i: int = big[x]
				var j: int = big[y]
				if b0 == -1:
					b0 = i
					b1 = j
					continue
				var left := link[i * K + j] * size[b0] * size[b1]
				var right := link[b0 * K + b1] * size[i] * size[j]
				if left < right:
					b0 = i
					b1 = j
	var place := PackedInt32Array()
	place.resize(K)
	place.fill(-1)
	var used := PackedByteArray()
	used.resize(K)
	var placed := [b0, b1]
	place[b0] = 0
	used[0] = 1
	place[b1] = K - 1
	used[K - 1] = 1
	for g: int in _by_size(K, size):
		if place[g] != -1:
			continue
		var best_s := -1
		var best_c := 0.0
		for s in K:
			if used[s] == 1:
				continue
			var c := 0.0
			for h: int in placed:
				var t := place[h]
				var lo := g if g < h else h
				var hi := h if g < h else g
				var w := link[lo * K + hi] - 4 * opp[lo * K + hi]
				var dx := _dir(K, s, 0) - _dir(K, t, 0)
				var dy := _dir(K, s, 1) - _dir(K, t, 1)
				var dz := _dir(K, s, 2) - _dir(K, t, 2)
				c += w * sqrt(dx * dx + dy * dy + dz * dz)
			if best_s == -1 or c < best_c:
				best_s = s
				best_c = c
		place[g] = best_s
		used[best_s] = 1
		placed.append(g)
	for g in K:
		for a in 3:
			dirs[3 * g + a] = _dir(K, place[g], a)
	return dirs

## The packing (step 5), and H3's with fixed parts: [param fixed_flag] null when no part is fixed.
static func _pack(K: int, radius: PackedFloat64Array, link: PackedInt32Array, opp: PackedInt32Array, dirs: PackedFloat64Array,
		fixed_flag: Variant, fixed_at: PackedFloat64Array) -> PackedFloat64Array:
	var P := PackedFloat64Array()
	P.resize(3 * K)
	var nf := 0
	if fixed_flag != null:
		for i in K:
			if fixed_flag[i] == 1:
				nf += 1
	if nf == 0 and K == 1:
		return P
	var sum := 0.0
	for i in K:
		sum += radius[i]
	if nf == 0:
		for c in 3 * K:
			P[c] = dirs[c] * sum
	else:
		var ox := 0.0
		var oy := 0.0
		var oz := 0.0
		for i in K:
			if fixed_flag[i] == 0:
				continue
			P[3 * i] = fixed_at[3 * i]
			P[3 * i + 1] = fixed_at[3 * i + 1]
			P[3 * i + 2] = fixed_at[3 * i + 2]
			ox += fixed_at[3 * i]
			oy += fixed_at[3 * i + 1]
			oz += fixed_at[3 * i + 2]
		if nf == K:
			return P
		ox /= nf
		oy /= nf
		oz /= nf
		for i in K:
			if fixed_flag[i] == 1:
				continue
			P[3 * i] = ox + dirs[3 * i] * sum
			P[3 * i + 1] = oy + dirs[3 * i + 1] * sum
			P[3 * i + 2] = oz + dirs[3 * i + 2] * sum
	var total := 0.0
	for i in K:
		for j in range(i + 1, K):
			total += link[i * K + j]
	if total == 0.0:
		total = 1.0
	var D := PackedFloat64Array()
	D.resize(3 * K)
	for step in PACK_STEPS:
		D.fill(0.0)
		for i in K:
			for j in range(i + 1, K):
				var dx := P[3 * i] - P[3 * j]
				var dy := P[3 * i + 1] - P[3 * j + 1]
				var dz := P[3 * i + 2] - P[3 * j + 2]
				var dist := maxf(sqrt(dx * dx + dy * dy + dz * dz), 0.000001)
				var f := dist - GAP * (radius[i] + radius[j])
				if f > 0.0:
					f = f * ((0.02 + 0.5 * link[i * K + j] / total) * (0.25 if opp[i * K + j] > 0 else 1.0))
				var ux := dx / dist * f * 0.5
				var uy := dy / dist * f * 0.5
				var uz := dz / dist * f * 0.5
				D[3 * i] = D[3 * i] - ux
				D[3 * i + 1] = D[3 * i + 1] - uy
				D[3 * i + 2] = D[3 * i + 2] - uz
				D[3 * j] = D[3 * j] + ux
				D[3 * j + 1] = D[3 * j + 1] + uy
				D[3 * j + 2] = D[3 * j + 2] + uz
		for i in K:
			if nf > 0 and fixed_flag[i] == 1:
				continue
			for c in range(3 * i, 3 * i + 3):
				P[c] = P[c] + D[c] * 0.5
	if nf > 0:
		return P
	var mx := 0.0
	var my := 0.0
	var mz := 0.0
	for i in K:
		mx += P[3 * i]
		my += P[3 * i + 1]
		mz += P[3 * i + 2]
	mx /= K
	my /= K
	mz /= K
	for i in K:
		P[3 * i] -= mx
		P[3 * i + 1] -= my
		P[3 * i + 2] -= mz
	return P

## {cpt, lobe, pinned, plate_at}: each group's point and lobe, which nodes are pinned, and each pinned node's standing
## place (null without a plate).
static func _group_points(n: int, body: PackedByteArray, taken: Array, group: PackedInt32Array, pairs: Array, opps: Array,
		plate: Variant, at: Dictionary, gflag: Variant, gat: PackedFloat64Array, frame_p: Variant, hflag: Variant,
		hat: PackedFloat64Array, near: float) -> Dictionary:
	var k := taken.size()
	var part := PackedInt32Array()
	part.resize(n)
	for v in n:
		part[v] = group[v] if body[v] == 1 else -1
	var cnt := _counts(n, k, part, pairs, opps)
	var size: PackedInt32Array = cnt["size"]
	var lobe := PackedFloat64Array()
	lobe.resize(k)
	for g in k:
		lobe[g] = REST * LOBE * _root(float(size[g]))
	var pinned := PackedByteArray()
	pinned.resize(n)

	if plate == null:
		var dirs := _directions(k, size, cnt["link"], cnt["opp"])
		var cpt0 := _pack(k, lobe, cnt["link"], cnt["opp"], dirs, gflag, gat)
		return {"cpt": cpt0, "lobe": lobe, "pinned": pinned, "plate_at": null}

	var q := PackedFloat64Array()
	q.resize(3 * n)
	var outside := 0
	var half := 0.0
	for id in plate["order"]:
		var v: int = at[id]
		var xyz: PackedFloat64Array = plate["at"][id]
		pinned[v] = 1
		q[3 * v] = xyz[0]
		q[3 * v + 1] = xyz[1]
		q[3 * v + 2] = xyz[2]
		if body[v] == 0:
			outside += 1
		half = maxf(half, sqrt(xyz[0] * xyz[0] + xyz[1] * xyz[1]))
	var over := PackedByteArray()
	over.resize(k)
	var unit_of := PackedInt32Array()
	unit_of.resize(k)
	var pu := 0
	for g in k:
		unit_of[g] = -1
		if pinned[taken[g]] == 1:
			over[g] = 1
		else:
			unit_of[g] = pu
			pu += 1
	var K := pu + 1
	var upart := PackedInt32Array()
	upart.resize(n)
	for v in n:
		if body[v] == 0:
			upart[v] = -1
		elif pinned[v] == 1 or over[group[v]] == 1:
			upart[v] = pu
		else:
			upart[v] = unit_of[group[v]]
	var ucnt := _counts(n, K, upart, pairs, opps)
	var usize: PackedInt32Array = ucnt["size"]
	usize[pu] += outside
	var udirs := _directions(K, usize, ucnt["link"], ucnt["opp"])
	var radius := PackedFloat64Array()
	radius.resize(K)
	for p in pu:
		radius[p] = REST * LOBE * _root(float(usize[p]))
	radius[pu] = half * CLEAR
	var fflag: Variant = null
	var fat := PackedFloat64Array()
	if gflag != null:
		fflag = PackedByteArray()
		fflag.resize(K)
		fat.resize(3 * K)
		for g in k:
			if over[g] == 1 or gflag[g] == 0:
				continue
			var p := unit_of[g]
			fflag[p] = 1
			fat[3 * p] = gat[3 * g]
			fat[3 * p + 1] = gat[3 * g + 1]
			fat[3 * p + 2] = gat[3 * g + 2]
		if frame_p != null:
			fflag[pu] = 1
			fat[3 * pu] = frame_p[0]
			fat[3 * pu + 1] = frame_p[1]
			fat[3 * pu + 2] = frame_p[2]
	var upt := _pack(K, radius, ucnt["link"], ucnt["opp"], udirs, fflag, fat)
	var plate_at := PackedFloat64Array()
	plate_at.resize(3 * n)
	for v in n:
		if pinned[v] == 0:
			continue
		for c in 3:
			plate_at[3 * v + c] = upt[3 * pu + c] + q[3 * v + c]

	# H4: the snap, before any group reads its centre's standing place.
	if hflag != null:
		for v in n:
			if pinned[v] == 0 or hflag[v] == 0:
				continue
			var close := true
			for c in 3:
				var d := plate_at[3 * v + c] - hat[3 * v + c]
				if not (d <= near and -d <= near):
					close = false
			if close:
				for c in 3:
					plate_at[3 * v + c] = hat[3 * v + c]

	var cpt := PackedFloat64Array()
	cpt.resize(3 * k)
	for g in k:
		if over[g] == 1:
			var c: int = taken[g]
			cpt[3 * g] = plate_at[3 * c] + 0.0
			cpt[3 * g + 1] = plate_at[3 * c + 1] + 0.0
			cpt[3 * g + 2] = plate_at[3 * c + 2] + (lobe[g] + REST * 6.0)
		else:
			var p := unit_of[g]
			cpt[3 * g] = upt[3 * p]
			cpt[3 * g + 1] = upt[3 * p + 1]
			cpt[3 * g + 2] = upt[3 * p + 2]
	return {"cpt": cpt, "lobe": lobe, "pinned": pinned, "plate_at": plate_at}

# ---- Steps 6 to 8: the feed, the start, the steps -----------------------------------------------------------------

## FNV-1a, 32 bits, over the id's UTF-8 bytes; each product taken whole in 64 bits before the mod.
static func _fnv1a(id: String) -> int:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h

## Steps 6, 7 and 8: each body node's point after the force steps, row v at 3v (rows outside the body unread).
static func _force_steps(ids: Array, body: PackedByteArray, pairs: Array, taken: Array, group: PackedInt32Array, pts: Dictionary,
		keep: Variant, hat: PackedFloat64Array, free: Variant, extra: Array) -> PackedFloat64Array:
	var n := ids.size()
	var blist := []
	var bi := PackedInt32Array()
	bi.resize(n)
	for v in n:
		bi[v] = -1
		if body[v] == 0:
			continue
		bi[v] = blist.size()
		blist.append(v)
	var nb := blist.size()
	var centre := PackedByteArray()
	centre.resize(n)
	for t in taken:
		centre[t] = 1
	var has_plate: bool = pts["plate_at"] != null
	var pinned: PackedByteArray = pts["pinned"]
	var plate_at: PackedFloat64Array = pts["plate_at"] if has_plate else PackedFloat64Array()
	var cpt: PackedFloat64Array = pts["cpt"]

	# 6. The movers, their anchors, fixed or not, their links and weights.
	var la := PackedInt32Array()
	var lb := PackedInt32Array()
	var lw := PackedFloat64Array()
	for p in pairs:
		var i := bi[p[0]]
		var j := bi[p[1]]
		if i < 0 or j < 0:
			continue
		la.append(i)
		lb.append(j)
		var u: int = blist[i]
		var w: int = blist[j]
		var x := 1.0 if group[u] == group[w] else CROSS
		if has_plate and (pinned[u] == 1 or pinned[w] == 1):
			x = PLATE
		lw.append(x)
	var m := nb + extra.size()
	var anchor := PackedFloat64Array()
	anchor.resize(3 * m)
	var pull := PackedFloat64Array()
	pull.resize(m)
	var is_fixed := PackedByteArray()
	is_fixed.resize(m)
	var mgroup := PackedInt32Array()
	mgroup.resize(m)
	var mid := []
	mid.resize(m)
	for i in nb:
		var v: int = blist[i]
		var is_pinned := has_plate and pinned[v] == 1
		var is_kept: bool = keep != null and keep[v] == 1
		for c in 3:
			if is_pinned:
				anchor[3 * i + c] = plate_at[3 * v + c]
			elif is_kept:
				anchor[3 * i + c] = hat[3 * v + c]
			else:
				anchor[3 * i + c] = cpt[3 * group[v] + c]
		pull[i] = HOLD
		var freed: bool = free != null and free[group[v]] == 1
		is_fixed[i] = 1 if (centre[v] == 1 and not freed) or is_pinned or is_kept else 0
		mgroup[i] = group[v]
		mid[i] = ids[v]
	for e in extra.size():
		var i := nb + e
		var v: int = extra[e]
		for c in 3:
			anchor[3 * i + c] = hat[3 * v + c]
		pull[i] = 0.0
		is_fixed[i] = 1
		mgroup[i] = -1
		mid[i] = ids[v]

	# 7. The start: a fixed mover at its anchor; any other in its group's ball, by its own seeded generator.
	var p0 := PackedFloat64Array()
	p0.resize(3 * m)
	var free_count := {}
	for i in m:
		if is_fixed[i] == 1:
			continue
		free_count[mgroup[i]] = free_count.get(mgroup[i], 0) + 1
	for i in m:
		if is_fixed[i] == 1:
			for c in 3:
				p0[3 * i + c] = anchor[3 * i + c]
			continue
		var ball := REST * LOBE * _root(float(free_count[mgroup[i]]))
		var g := _fnv1a(mid[i])
		g = (g * 1664525 + 1013904223) & 0xFFFFFFFF
		g = (g * 1664525 + 1013904223) & 0xFFFFFFFF
		var x := 0.0
		var y := 0.0
		var z := 0.0
		for tries in 64:
			g = (g * 1664525 + 1013904223) & 0xFFFFFFFF
			var r1 := 2.0 * (float(g) / 4294967296.0) - 1.0
			g = (g * 1664525 + 1013904223) & 0xFFFFFFFF
			var r2 := 2.0 * (float(g) / 4294967296.0) - 1.0
			g = (g * 1664525 + 1013904223) & 0xFFFFFFFF
			var r3 := 2.0 * (float(g) / 4294967296.0) - 1.0
			if r1 * r1 + r2 * r2 + r3 * r3 <= 1.0:
				x = r1
				y = r2
				z = r3
				break
		p0[3 * i] = anchor[3 * i] + (0.0 + x * ball)
		p0[3 * i + 1] = anchor[3 * i + 1] + (0.0 + y * ball)
		p0[3 * i + 2] = anchor[3 * i + 2] + (0.0 + z * ball)

	# 8. The steps.
	var pos := _relax(m, p0, anchor, pull, is_fixed, la, lb, lw)
	var relaxed := PackedFloat64Array()
	relaxed.resize(3 * n)
	for i in nb:
		for c in 3:
			relaxed[3 * blist[i] + c] = pos[3 * i + c]
	return relaxed

static func _relax(m: int, p0: PackedFloat64Array, anchor: PackedFloat64Array, pull: PackedFloat64Array, is_fixed: PackedByteArray,
		la: PackedInt32Array, lb: PackedInt32Array, lw: PackedFloat64Array) -> PackedFloat64Array:
	var R := REST
	var cut := CUTOFF * R
	var cut2 := cut * cut
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var pz := PackedFloat64Array()
	px.resize(m)
	py.resize(m)
	pz.resize(m)
	for i in m:
		px[i] = p0[3 * i]
		py[i] = p0[3 * i + 1]
		pz[i] = p0[3 * i + 2]
	var scale := PackedFloat64Array()
	scale.resize(m)
	for e in la.size():
		scale[la[e]] += lw[e]
		scale[lb[e]] += lw[e]
	for i in m:
		scale[i] = 1.0 / maxf(1.0, scale[i] / 4.0)
	var free := 0
	for i in m:
		if is_fixed[i] == 0:
			free += 1
	var run := mini(STEPS, 1) if free == 0 else STEPS

	var dx := PackedFloat64Array()
	var dy := PackedFloat64Array()
	var dz := PackedFloat64Array()
	var lx := PackedFloat64Array()
	var ly := PackedFloat64Array()
	var lz := PackedFloat64Array()
	dx.resize(m)
	dy.resize(m)
	dz.resize(m)
	lx.resize(m)
	ly.resize(m)
	lz.resize(m)
	var key := PackedInt64Array()
	key.resize(m)
	var sorted := PackedInt64Array()
	sorted.resize(m)
	var order := PackedInt32Array()
	order.resize(m)
	for step in run:
		# The cells: each mover's cell, the cells in rising order, each listing its movers in rising order.
		var x0 := INF
		var y0 := INF
		var z0 := INF
		var x1 := -INF
		var y1 := -INF
		var z1 := -INF
		for i in m:
			if px[i] < x0:
				x0 = px[i]
			if px[i] > x1:
				x1 = px[i]
			if py[i] < y0:
				y0 = py[i]
			if py[i] > y1:
				y1 = py[i]
			if pz[i] < z0:
				z0 = pz[i]
			if pz[i] > z1:
				z1 = pz[i]
		var nx := floori((x1 - x0) / cut) + 1
		var ny := floori((y1 - y0) / cut) + 1
		var nz := floori((z1 - z0) / cut) + 1
		for i in m:
			var cx := floori((px[i] - x0) / cut)
			var cy := floori((py[i] - y0) / cut)
			var cz := floori((pz[i] - z0) / cut)
			key[i] = (cx * ny + cy) * nz + cz
			sorted[i] = key[i] * m + i
		sorted.sort()
		for u in m:
			order[u] = sorted[u] % m
		var cells := {}
		var cell_start := PackedInt32Array()
		var cell_key := PackedInt64Array()
		var cell_free := PackedByteArray()
		for u in m:
			var i := order[u]
			if cell_key.is_empty() or cell_key[cell_key.size() - 1] != key[i]:
				cells[key[i]] = cell_key.size()
				cell_key.append(key[i])
				cell_start.append(u)
				cell_free.append(0)
			if is_fixed[i] == 0:
				cell_free[cell_free.size() - 1] = 1
		cell_start.append(m)

		# The push.
		dx.fill(0.0)
		dy.fill(0.0)
		dz.fill(0.0)
		var nyz := ny * nz
		for ci in cell_key.size():
			var ck := cell_key[ci]
			var cx := ck / nyz
			var cy := ck / nz % ny
			var cz := ck % nz
			var s0 := cell_start[ci]
			var s1 := cell_start[ci + 1]
			for ox in 2:
				for oy in range(-1 if ox == 1 else 0, 2):
					for oz in range(-1 if ox == 1 or oy == 1 else 0, 2):
						var qx := cx + ox
						var qy := cy + oy
						var qz := cz + oz
						if qx >= nx or qy < 0 or qy >= ny or qz < 0 or qz >= nz:
							continue
						var qi: int = cells.get((qx * ny + qy) * nz + qz, -1)
						if qi < 0:
							continue
						if cell_free[ci] == 0 and cell_free[qi] == 0:
							continue
						var same := qi == ci
						var t0 := cell_start[qi]
						var t1 := cell_start[qi + 1]
						for u in range(s0, s1):
							var i := order[u]
							for w in range(u + 1 if same else t0, t1):
								var j := order[w]
								if is_fixed[i] == 1 and is_fixed[j] == 1:
									continue
								var ux := px[i] - px[j]
								var uy := py[i] - py[j]
								var uz := pz[i] - pz[j]
								var d2 := ux * ux + uy * uy + uz * uz
								if d2 > cut2:
									continue
								var d := maxf(sqrt(d2), 0.000001)
								var f := ((R * R) / d - R / 3.0) / d
								dx[i] = dx[i] + ux * f
								dy[i] = dy[i] + uy * f
								dz[i] = dz[i] + uz * f
								dx[j] = dx[j] - ux * f
								dy[j] = dy[j] - uy * f
								dz[j] = dz[j] - uz * f

		# The links.
		lx.fill(0.0)
		ly.fill(0.0)
		lz.fill(0.0)
		for e in la.size():
			var a := la[e]
			var b := lb[e]
			var ux := px[a] - px[b]
			var uy := py[a] - py[b]
			var uz := pz[a] - pz[b]
			var d := maxf(sqrt(ux * ux + uy * uy + uz * uz), 0.000001)
			var f := ((d - R) * 0.5 * lw[e]) / d
			lx[b] = lx[b] + ux * f
			ly[b] = ly[b] + uy * f
			lz[b] = lz[b] + uz * f
			lx[a] = lx[a] - ux * f
			ly[a] = ly[a] - uy * f
			lz[a] = lz[a] - uz * f

		# The move.
		var cap := CAP0 * R * (1.0 - float(step) / STEPS) + R / 20.0
		for i in m:
			if is_fixed[i] == 1:
				px[i] = anchor[3 * i]
				py[i] = anchor[3 * i + 1]
				pz[i] = anchor[3 * i + 2]
				continue
			var vx := dx[i] + lx[i] * scale[i] + (anchor[3 * i] - px[i]) * pull[i]
			var vy := dy[i] + ly[i] * scale[i] + (anchor[3 * i + 1] - py[i]) * pull[i]
			var vz := dz[i] + lz[i] * scale[i] + (anchor[3 * i + 2] - pz[i]) * pull[i]
			var vlen := maxf(sqrt(vx * vx + vy * vy + vz * vz), 0.000000001)
			var shrink := minf(1.0, cap / vlen)
			px[i] = px[i] + vx * shrink
			py[i] = py[i] + vy * shrink
			pz[i] = pz[i] + vz * shrink

	var pos := PackedFloat64Array()
	pos.resize(3 * m)
	for i in m:
		pos[3 * i] = px[i]
		pos[3 * i + 1] = py[i]
		pos[3 * i + 2] = pz[i]
	return pos

# ---- Step 9: what is placed after the steps, with H6 ---------------------------------------------------------------

static func _skin(a: Array) -> float:
	var m := a.size()
	if m == 0:
		return 0.0
	a.sort()
	var vi := (m - 1) * 0.9
	var lo: int
	var hi: int
	if vi >= m - 1:
		lo = m - 1
		hi = m - 1
	else:
		lo = floori(vi)
		hi = lo + 1
	var t := vi - lo
	var d: float = a[hi] - a[lo]
	return a[hi] - d * (1.0 - t) if t >= 0.5 else a[lo] + d * t

## The fan's place j at depth d round cut c ([param f]: the cut's frame, see [method _hang]).
static func _fan_point(f: Dictionary, j: int, d: int) -> PackedFloat64Array:
	var ang := _gold * j
	var fan := REST * 0.5 * sqrt(float(j))
	var ca := cos(ang)
	var sa := sin(ang)
	if f["over"]:
		var pa: PackedFloat64Array = f["plate"]
		return PackedFloat64Array([pa[0] + ca * fan * 0.5, pa[1] + sa * fan * 0.5, pa[2] + REST * d])
	var cp: PackedFloat64Array = f["cpt"]
	var u: PackedFloat64Array = f["u"]
	var t: PackedFloat64Array = f["t"]
	var w: PackedFloat64Array = f["w"]
	var reach: float = f["skin"] + REST * d
	return PackedFloat64Array([cp[0] + u[0] * reach + (t[0] * ca + w[0] * sa) * fan,
		cp[1] + u[1] * reach + (t[1] * ca + w[1] * sa) * fan,
		cp[2] + u[2] * reach + (t[2] * ca + w[2] * sa) * fan])

## {how, pos}: each node's how and its point.
static func _hang(n: int, body: PackedByteArray, hang_cut: PackedInt32Array, hang_depth: PackedInt32Array, off: PackedByteArray,
		taken: Array, group: PackedInt32Array, pts: Dictionary, degree: PackedInt32Array, relaxed: PackedFloat64Array,
		keep: Variant, hat: PackedFloat64Array) -> Dictionary:
	var k := taken.size()
	var cpt: PackedFloat64Array = pts["cpt"]
	var pinned: PackedByteArray = pts["pinned"]
	var plate_at: PackedFloat64Array = pts["plate_at"] if pts["plate_at"] != null else PackedFloat64Array()
	var pos := PackedFloat64Array()
	pos.resize(3 * n)
	var how := PackedInt32Array()
	how.resize(n)
	how.fill(-1)

	# The kept nodes (held, not pinned), and the near test against every one of them.
	var kept := []
	if keep != null:
		for v in n:
			if keep[v] == 1 and pinned[v] == 0:
				kept.append(v)

	# The body.
	var nbody := 0
	for v in n:
		if body[v] == 0:
			continue
		for c in 3:
			pos[3 * v + c] = relaxed[3 * v + c]
		how[v] = HOW_CENTRE if taken[group[v]] == v else HOW_WITH
		nbody += 1

	# The middle.
	var mid_x := 0.0
	var mid_y := 0.0
	var mid_z := 0.0
	for v in n:
		if body[v] == 0:
			continue
		mid_x += relaxed[3 * v]
		mid_y += relaxed[3 * v + 1]
		mid_z += relaxed[3 * v + 2]
	mid_x /= nbody
	mid_y /= nbody
	mid_z /= nbody

	# The skin of each group.
	var skin := PackedFloat64Array()
	skin.resize(k)
	for g in k:
		var vals := []
		for v in n:
			if body[v] == 0 or group[v] != g or pinned[v] == 1:
				continue
			vals.append(_len3(relaxed[3 * v] - cpt[3 * g], relaxed[3 * v + 1] - cpt[3 * g + 1], relaxed[3 * v + 2] - cpt[3 * g + 2]))
		skin[g] = _skin(vals)

	# What hangs: each cut in the one order, its nodes by depth, then the one order.
	var lists := {}
	for v in n:
		if hang_cut[v] == -1:
			continue
		if not lists.has(hang_cut[v]):
			lists[hang_cut[v]] = []
		lists[hang_cut[v]].append(v)
	for c in n:
		if not lists.has(c):
			continue
		var row: Array = lists[c]
		row.sort_custom(func(x: int, y: int) -> bool: return hang_depth[x] < hang_depth[y] if hang_depth[x] != hang_depth[y] else x < y)
		var g := group[c]

		# Outward.
		var ux := pos[3 * c] - cpt[3 * g]
		var uy := pos[3 * c + 1] - cpt[3 * g + 1]
		var uz := pos[3 * c + 2] - cpt[3 * g + 2]
		var lu := _len3(ux, uy, uz)
		if lu > 0.000001:
			ux = ux / lu
			uy = uy / lu
			uz = uz / lu
		else:
			ux = 0.0
			uy = 0.0
			uz = 0.0
		var ox := cpt[3 * g] - mid_x
		var oy := cpt[3 * g + 1] - mid_y
		var oz := cpt[3 * g + 2] - mid_z
		var lo := _len3(ox, oy, oz)
		if lo > 0.000001:
			ox = ox / lo
			oy = oy / lo
			oz = oz / lo
		else:
			ox = 0.0
			oy = 0.0
			oz = 1.0
		ux = ux + 0.75 * ox
		uy = uy + 0.75 * oy
		uz = uz + 0.75 * oz
		var l := _len3(ux, uy, uz)
		ux = ux / l
		uy = uy / l
		uz = uz / l

		# t = u x (0, 0, 1), else u x (1, 0, 0); w = u x t.
		var tx := uy * 1.0 - uz * 0.0
		var ty := uz * 0.0 - ux * 1.0
		var tz := ux * 0.0 - uy * 0.0
		if _len3(tx, ty, tz) < 0.001:
			tx = uy * 0.0 - uz * 0.0
			ty = uz * 1.0 - ux * 0.0
			tz = ux * 0.0 - uy * 1.0
		var lt := _len3(tx, ty, tz)
		tx = tx / lt
		ty = ty / lt
		tz = tz / lt
		var wx := uy * tz - uz * ty
		var wy := uz * tx - ux * tz
		var wz := ux * ty - uy * tx
		var over_place := pinned[c] == 1
		var frame := {"over": over_place, "cpt": PackedFloat64Array([cpt[3 * g], cpt[3 * g + 1], cpt[3 * g + 2]]),
			"u": PackedFloat64Array([ux, uy, uz]), "t": PackedFloat64Array([tx, ty, tz]), "w": PackedFloat64Array([wx, wy, wz]),
			"skin": skin[g], "plate": PackedFloat64Array()}
		if over_place:
			frame["plate"] = PackedFloat64Array([plate_at[3 * c], plate_at[3 * c + 1], plate_at[3 * c + 2]])

		var used: Variant = null
		if keep != null:
			# H6: first the claims of the kept nodes of the list.
			used = {}
			for v: int in row:
				if keep[v] == 0 or pinned[v] == 1:
					continue
				var d := hang_depth[v]
				var hx := hat[3 * v]
				var hy := hat[3 * v + 1]
				var hz := hat[3 * v + 2]
				var axx: float
				var axy: float
				var axz: float
				if over_place:
					axx = plate_at[3 * c]
					axy = plate_at[3 * c + 1]
					axz = plate_at[3 * c + 2] + REST * d
				else:
					var reach := skin[g] + REST * d
					axx = cpt[3 * g] + ux * reach
					axy = cpt[3 * g + 1] + uy * reach
					axz = cpt[3 * g + 2] + uz * reach
				var bound := _len3(hx - axx, hy - axy, hz - axz) + LINE + REST
				var j := 0
				while true:
					var fan := REST * 0.5 * sqrt(float(j))
					if not ((fan * 0.5 if over_place else fan) < bound):
						break
					var fp := _fan_point(frame, j, d)
					if _len3(fp[0] - hx, fp[1] - hy, fp[2] - hz) < LINE:
						used[j] = true
					j += 1

		for r in row.size():
			var v: int = row[r]
			var d := hang_depth[v]
			how[v] = HOW_LINK if degree[v] == 1 and d == 1 else HOW_ARM
			var j := r
			if used != null:
				if keep[v] == 1 and pinned[v] == 0:
					continue
				j = 0
				while true:
					if used.has(j):
						j += 1
						continue
					var fp := _fan_point(frame, j, d)
					if not _near(kept, hat, fp):
						break
					j += 1
				used[j] = true
			var at := _fan_point(frame, j, d)
			pos[3 * v] = at[0]
			pos[3 * v + 1] = at[1]
			pos[3 * v + 2] = at[2]

	# Off the main piece: placed by no rule of a run.
	for v in n:
		if off[v] == 1 and pinned[v] == 0:
			how[v] = HOW_OFF

	# Kept: every kept node at its held point.
	for v: int in kept:
		for c in 3:
			pos[3 * v + c] = hat[3 * v + c]

	# The map, last: every pinned node at its standing place.
	for v in n:
		if pinned[v] == 0:
			continue
		for c in 3:
			pos[3 * v + c] = plate_at[3 * v + c]
		how[v] = HOW_MAP

	for v in n:
		assert(how[v] != -1, "layout_by_links_3d: a node was placed by no rule")
	return {"how": how, "pos": pos}

static func _near(kept: Array, hat: PackedFloat64Array, p: PackedFloat64Array) -> bool:
	for u: int in kept:
		if _len3(p[0] - hat[3 * u], p[1] - hat[3 * u + 1], p[2] - hat[3 * u + 2]) < LINE:
			return true
	return false
