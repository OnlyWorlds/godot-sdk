class_name OWLayout
extends RefCounted
## Two layout methods for a world nobody laid out, read from its graph as [method OWGraph.world_graph] answers it (the
## npm SDK's [code]layoutByKind[/code] and [code]layoutAround[/code], 4.167.0, and the Python package's
## [code]layout_by_kind[/code] and [code]layout_around[/code], 0.127.0).
##
## [b]by-kind[/b]: each kind of element gets a point on a circle, links act as springs, neighbours push apart, for a fixed
## number of seeded steps; the answer is fitted into a square. [b]around[/b]: one element at the centre, its neighbours on
## rings round it, and at two steps their neighbours further out, near the element that reached them.
##
## Both are exact: the same graph gives the same points as the npm SDK and the Python package, by-kind to the last bit,
## around within about 1e-12 (its cosines and sines are the engine's own). The kinds' points on the circle are a table of
## bit patterns ([OWLayoutAnchors], generated from the shared fixture), never computed and never parsed from a decimal;
## everything else is addition, subtraction, multiplication, division, square root and floor, in the npm SDK's order
## (GDScript runs each operator on its own, so nothing is fused), with JavaScript's [code]Math.min[/code] and
## [code]Math.max[/code], so even the sign of a zero matches. Points are 64-bit floats, never [Vector2] (32-bit in a
## standard build).
##
## A graph is an [OWGraph.Graph] or a Dictionary [code]{nodes, edges}[/code] in the npm SDK's words: each node
## [code]{id, type, name?}[/code] (the type a slug), each edge [code]{source, target, field?, index?}[/code]. The graph is
## first put in one order (nodes by id; links by source, field, index, then target; every word by code point), so the
## order the nodes and links are handed in moves nothing. A graph it cannot read answers [code]{error}[/code], naming
## what (the npm SDK's TypeError): no nodes or edges list, a node that is not a Dictionary or has no id, a type that is
## not one of the 22, a name neither a String nor null, an id twice, an edge without String [code]source[/code] and
## [code]target[/code], a [code]field[/code] there and not a String (null too), an [code]index[/code] there and not a
## finite number (null too). The kinds' colour groups are the first-party defaults ([constant OWPresentation.TYPES] and
## [constant OWPresentation.ORDER]), never a tool's [method OWPresentation.use].

const _STEPS := 320
const _CELL_MAX := 12
const _RING_ONE := 60

static var _anchors := PackedFloat64Array()

## Lay out a whole graph by kind. Each kind present gets an anchor on a circle, in colour group order and then by type
## word; every element starts near its kind's anchor, at a seeded jitter. Then, for 320 steps (160 past 2,000 elements):
## elements closer than a few rest lengths push each other apart (a cell holding more than 12 pushes with a rotating
## sample of 12, scaled up), every link pulls its two ends towards a rest length, every element is drawn back towards its
## kind's anchor, and no element moves further in one step than a cap that shrinks as the steps run out. Last, the points
## are fitted into a frame of -1 to 1 on the longer axis, centred, proportions kept.
##
## Answers [code]{method: "by-kind", version: 1, points}[/code], one [code]{id, x, y}[/code] per node in the order
## handed; an empty graph answers no points, one element answers 0, 0. Self-links pull nothing; a link to an id that is
## not a node is passed over. [code]{error}[/code] on a graph it cannot read.
static func layout_by_kind(graph: Variant) -> Dictionary:
	var g := _read_graph("layout_by_kind", graph)
	if g.has("error"):
		return g
	var nodes: Array = g["nodes"]
	var handed: Array = g["handed"]
	var place: Dictionary = g["index"]
	var n := nodes.size()
	if n <= 1:
		var zero := []
		for x in handed:
			zero.append({"id": x["id"], "x": 0.0, "y": 0.0})
		return {"method": "by-kind", "version": 1, "points": zero}

	var ea := PackedInt32Array()
	var eb := PackedInt32Array()
	for e in g["edges"]:
		var a: int = place.get(e["source"], -1)
		var b: int = place.get(e["target"], -1)
		if a >= 0 and b >= 0 and a != b:
			ea.append(a)
			eb.append(b)
	var seen := {}
	var types := []
	for x in nodes:
		if not seen.has(x["type"]):
			seen[x["type"]] = true
			types.append(x["type"])
	types.sort_custom(func(a: String, b: String) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb if ra != rb else a < b)
	var k := types.size()
	var anchor_x := {}
	var anchor_y := {}
	for i in k:
		anchor_x[types[i]] = _anchor(k * (k - 1) + 2 * i)
		anchor_y[types[i]] = _anchor(k * (k - 1) + 2 * i + 1)

	var seed := 7
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var tx := PackedFloat64Array()
	var ty := PackedFloat64Array()
	px.resize(n)
	py.resize(n)
	tx.resize(n)
	ty.resize(n)
	for i in n:
		var ax: float = anchor_x[nodes[i]["type"]]
		var ay: float = anchor_y[nodes[i]["type"]]
		seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
		px[i] = ax * 0.8 + (float(seed) / 4294967296.0 - 0.5) * 0.5
		seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
		py[i] = ay * 0.8 + (float(seed) / 4294967296.0 - 0.5) * 0.5
		tx[i] = ax * 0.85
		ty[i] = ay * 0.85
	var rest := _max_js(0.002, 0.9 / sqrt(float(n)))
	var push := rest * rest * 1.4
	var cell := rest * 2.2
	var cell2 := cell * cell
	var fx := PackedFloat64Array()
	var fy := PackedFloat64Array()
	fx.resize(n)
	fy.resize(n)
	var cxs := PackedInt64Array()
	var cys := PackedInt64Array()
	cxs.resize(n)
	cys.resize(n)
	var steps := _STEPS / 2 if n > 2000 else _STEPS
	var ne := ea.size()

	for it in steps:
		var t := 1.0 - float(it) / steps
		fx.fill(0.0)
		fy.fill(0.0)
		var grid := {}
		for i in n:
			var gx := floori(px[i] / cell)
			var gy := floori(py[i] / cell)
			cxs[i] = gx
			cys[i] = gy
			var key := (gx + 1048576) * 2097152 + (gy + 1048576)
			var c: Variant = grid.get(key)
			if c == null:
				grid[key] = [i]
			else:
				c.append(i)
		for i in n:
			var cx: int = cxs[i]
			var cy: int = cys[i]
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var cell_of: Variant = grid.get((cx + dx + 1048576) * 2097152 + (cy + dy + 1048576))
					if cell_of == null:
						continue
					var members: Array = cell_of
					var len_ := members.size()
					if len_ > _CELL_MAX:
						# A crowded cell: a sample of 12 that turns with the element and the step, each push scaled up to the whole.
						var off := (i * 7 + it * 13) % len_
						var scale := float(len_) / _CELL_MAX
						for s in _CELL_MAX:
							var j: int = members[(off + s) % len_]
							if j == i:
								continue
							var ux := px[i] - px[j]
							var uy := py[i] - py[j]
							var d2 := ux * ux + uy * uy + 1e-6
							if d2 > cell2:
								continue
							var d := sqrt(d2)
							var f := (push * scale) / d2
							fx[i] += (ux / d) * f
							fy[i] += (uy / d) * f
						continue
					for j: int in members:
						if j <= i:
							continue
						var ux := px[i] - px[j]
						var uy := py[i] - py[j]
						var d2 := ux * ux + uy * uy + 1e-6
						if d2 > cell2:
							continue
						var d := sqrt(d2)
						var f := push / d2
						fx[i] += (ux / d) * f
						fy[i] += (uy / d) * f
						fx[j] -= (ux / d) * f
						fy[j] -= (uy / d) * f
		for q in ne:
			var a: int = ea[q]
			var b: int = eb[q]
			var ux := px[b] - px[a]
			var uy := py[b] - py[a]
			var d := sqrt(ux * ux + uy * uy) + 1e-6
			var f := (d - rest) * 0.06
			fx[a] += (ux / d) * f
			fy[a] += (uy / d) * f
			fx[b] -= (ux / d) * f
			fy[b] -= (uy / d) * f
		for i in n:
			fx[i] += (tx[i] - px[i]) * 0.06
			fy[i] += (ty[i] - py[i]) * 0.06
			var m := sqrt(fx[i] * fx[i] + fy[i] * fy[i])
			var cap := 0.03 * t + 0.002
			var s := cap / m if m > cap else 1.0
			px[i] += fx[i] * s
			py[i] += fy[i] * s

	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	for i in n:
		x0 = _min_js(x0, px[i])
		x1 = _max_js(x1, px[i])
		y0 = _min_js(y0, py[i])
		y1 = _max_js(y1, py[i])
	var span := _max_js(x1 - x0, y1 - y0)
	var sc := 2.0 / span if span > 1e-9 else 1.0
	var mx := (x0 + x1) / 2.0
	var my := (y0 + y1) / 2.0
	var points := []
	for x in handed:
		var i: int = place[x["id"]]
		points.append({"id": x["id"], "x": (px[i] - mx) * sc, "y": (py[i] - my) * sc})
	return {"method": "by-kind", "version": 1, "points": points}

## Lay out one element and what is linked to it. The focus stands at 0, 0. Its neighbours (one link away, either
## direction) stand on a ring round it, in colour group order, then by type word, then by name (code point order, the
## same in every language and locale), up to 60 on the first ring and further rings beyond it. With [param steps] 2, each
## neighbour's own neighbours stand on an outer ring, fanned out near the neighbour that reached them.
##
## Answers [code]{method: "around", version: 1, points}[/code]: the focus and every element within the steps, in the
## order the nodes were handed in, each [code]{id, depth, x, y}[/code] (depth 0, 1 or 2). [code]{error}[/code] on a
## [param steps] that is not the integer 1 or 2 (checked first), a graph it cannot read, or a focus that is not one of the
## graph's nodes.
static func layout_around(graph: Variant, focus: Variant, steps: Variant = 1) -> Dictionary:
	if typeof(steps) != TYPE_INT or (steps != 1 and steps != 2):
		return {"error": "layout_around: steps is 1 or 2, not %s" % str(steps)}
	var g := _read_graph("layout_around", graph)
	if g.has("error"):
		return g
	var nodes: Array = g["nodes"]
	var handed: Array = g["handed"]
	var place: Dictionary = g["index"]
	if typeof(focus) != TYPE_STRING or not place.has(focus):
		return {"error": "layout_around: the focus %s is not a node of the graph" % str(focus)}
	var centre: int = place[focus]
	var n := nodes.size()
	var walk := _reach(g, centre, steps)
	var depth: PackedInt32Array = walk["depth"]
	var via: PackedInt32Array = walk["via"]
	var reached: Array = walk["reached"]
	var ring1: Array = reached[1].duplicate()
	ring1.sort_custom(func(a: int, b: int) -> bool:
		var ta: String = nodes[a]["type"]
		var tb: String = nodes[b]["type"]
		var ra := _rank(ta)
		var rb := _rank(tb)
		if ra != rb:
			return ra < rb
		if ta != tb:
			return ta < tb
		var na: String = nodes[a]["name"] if nodes[a]["name"] != null else ""
		var nb: String = nodes[b]["name"] if nodes[b]["name"] != null else ""
		if na != nb:
			return na < nb
		return a < b)

	var placed_at := PackedByteArray()
	placed_at.resize(n)
	var at_x := PackedFloat64Array()
	var at_y := PackedFloat64Array()
	var angle := PackedFloat64Array()
	at_x.resize(n)
	at_y.resize(n)
	angle.resize(n)
	placed_at[centre] = 1
	if not ring1.is_empty():
		var first := mini(ring1.size(), _RING_ONE)
		var r1 := _max_js(0.34, first * 0.017)
		var gap := (2.0 * PI * r1) / first
		var placed := 0
		var r := r1
		while placed < ring1.size():
			var room := int(_max_js(1.0, floor((2.0 * PI * r) / gap)))
			var count := mini(room, ring1.size() - placed)
			for k in count:
				var j: int = ring1[placed + k]
				var a := -PI / 2.0 + (2.0 * PI * (k + 0.5)) / count
				angle[j] = a
				at_x[j] = cos(a) * r
				at_y[j] = sin(a) * r
				placed_at[j] = 1
			placed += count
			r += gap * 1.2
		var outer := r - gap * 1.2
		if steps == 2:
			var kids := {}
			for j: int in reached[2]:
				var p: int = via[j]
				if kids.has(p):
					kids[p].append(j)
				else:
					kids[p] = [j]
			var spread := _min_js(0.5, ((2.0 * PI) / maxi(1, ring1.size())) * 0.9)
			for p: int in kids:
				var a0 := angle[p]
				var ks: Array = kids[p]
				for k in ks.size():
					var j: int = ks[k]
					var a := a0 + (0.0 if ks.size() == 1 else (float(k) / (ks.size() - 1) - 0.5) * spread)
					at_x[j] = cos(a) * outer * 1.8
					at_y[j] = sin(a) * outer * 1.8
					placed_at[j] = 1
	var points := []
	for x in handed:
		var j: int = place[x["id"]]
		if placed_at[j] == 1:
			points.append({"id": x["id"], "depth": depth[j], "x": at_x[j], "y": at_y[j]})
	return {"method": "around", "version": 1, "points": points}

## What a saved [code]by-kind[/code] layout map does not place (the default layouts' page, [code]unplaced[/code]): the
## ids of the graph's nodes that are not in [param placed], by id in code point order. [code]by-kind[/code] places
## every node, so every node counts.
##
## [param placed] is the ids of the elements the Map's Pins stand for ([method OWMapSpace.map_space]'s
## [code]element_id[/code] of each Pin on this Map): an Array, a [PackedStringArray], or a Dictionary used as a set (its
## keys). A member that is not a non-empty String names no element and is passed over (the number 7 is not the id
## "7"; Godot's JSON reads 7 as 7.0, no String either), and an id that is no node is no part of the answer. The
## answer's length is the count a tool shows; it does not say why an element has no Pin.
##
## Answers [code]{method: "by-kind", unplaced}[/code], or [code]{error}[/code] on a graph it cannot read (as
## [method layout_by_kind]) or a [param placed] that is null, a String or not a list or a set.
static func unplaced_by_kind(graph: Variant, placed: Variant) -> Dictionary:
	var ids := _placed_ids("unplaced_by_kind", placed)
	if ids.has("error"):
		return ids
	var g := _read_graph("unplaced_by_kind", graph)
	if g.has("error"):
		return g
	var answer := []
	for x in g["nodes"]:
		if not ids["set"].has(x["id"]):
			answer.append(x["id"])
	return {"method": "by-kind", "unplaced": answer}

## What a saved [code]around[/code] layout map does not place: the ids of the focus and every node within
## [param steps] of it that are not in [param placed], by id in code point order. [param placed] is read as
## [method unplaced_by_kind] reads it; an id that [code]around[/code] would not place (no node, or a node further out
## than the steps) is no part of the answer. Only a tool that holds the Map's focus and steps can make this reading.
##
## Answers [code]{method: "around", unplaced}[/code], or [code]{error}[/code] as [method layout_around] (steps, graph,
## focus, in that order) and on a [param placed] that is no list or set.
static func unplaced_around(graph: Variant, focus: Variant, placed: Variant, steps: Variant = 1) -> Dictionary:
	if typeof(steps) != TYPE_INT or (steps != 1 and steps != 2):
		return {"error": "unplaced_around: steps is 1 or 2, not %s" % str(steps)}
	var g := _read_graph("unplaced_around", graph)
	if g.has("error"):
		return g
	var place: Dictionary = g["index"]
	if typeof(focus) != TYPE_STRING or not place.has(focus):
		return {"error": "unplaced_around: the focus %s is not a node of the graph" % str(focus)}
	var ids := _placed_ids("unplaced_around", placed)
	if ids.has("error"):
		return ids
	var depth: PackedInt32Array = _reach(g, place[focus], steps)["depth"]
	var nodes: Array = g["nodes"]
	var answer := []
	for j in nodes.size():
		if depth[j] >= 0 and not ids["set"].has(nodes[j]["id"]):
			answer.append(nodes[j]["id"])
	return {"method": "around", "unplaced": answer}

## What a saved [code]by-links-3d[/code] layout map does not place: the ids of the graph's nodes that are not in
## [param placed], by id in code point order. Every node counts, of any type, also one the method would not place
## (linked to no other and pinned on no map), so for the Map an answer makes this is that answer's own
## [code]unplaced[/code]. The method's Maps, Pins and held points are not read. [param placed] is read as
## [method unplaced_by_kind] reads it.
##
## Answers [code]{method: "by-links-3d", unplaced}[/code], or [code]{error}[/code] when the graph is not
## [code]{nodes, edges}[/code], a node has no String id, two nodes share an id, or [param placed] is no list or set.
static func unplaced_by_links_3d(graph: Variant, placed: Variant) -> Dictionary:
	var given_nodes: Variant = null
	var given_edges: Variant = null
	if graph is OWGraph.Graph:
		given_nodes = graph.nodes
		given_edges = graph.edges
	elif graph is Dictionary:
		given_nodes = graph.get("nodes")
		given_edges = graph.get("edges")
	if not (given_nodes is Array) or not (given_edges is Array):
		return {"error": "unplaced_by_links_3d: the graph is { nodes, edges }, as world_graph answers it"}
	var taken := _placed_ids("unplaced_by_links_3d", placed)
	if taken.has("error"):
		return taken
	var ids := []
	for i in given_nodes.size():
		var node: Variant = given_nodes[i]
		var id: Variant = node.get("id") if node is Dictionary else null
		if typeof(id) != TYPE_STRING:
			return {"error": "unplaced_by_links_3d: node %d has no id" % i}
		ids.append(id)
	ids.sort()
	for i in range(1, ids.size()):
		if ids[i] == ids[i - 1]:
			return {"error": "unplaced_by_links_3d: two nodes share the id %s" % ids[i]}
	var answer := []
	for id in ids:
		if not taken["set"].has(id):
			answer.append(id)
	return {"method": "by-links-3d", "unplaced": answer}

## [param placed] as a set of ids ({set}: id -> true), or {error}: a member that is not a non-empty String is passed
## over; null, a String, or anything that is not an Array, a PackedStringArray or a Dictionary (its keys) is refused.
static func _placed_ids(fn: String, placed: Variant) -> Dictionary:
	var members: Array
	if placed is Array:
		members = placed
	elif placed is PackedStringArray:
		members = Array(placed)
	elif placed is Dictionary:
		members = placed.keys()
	else:
		return {"error": "%s: placed is a list or a set of element ids" % fn}
	var out := {}
	for v in members:
		if typeof(v) == TYPE_STRING and v != "":
			out[v] = true
	return {"set": out}

## [code]around[/code]'s reach (its steps 1 and 2) on a read graph: {depth, via, reached}, each node's depth from the
## focus (-1 past the steps), the node whose list each was met in, and each depth's nodes in the order they were found
## (the order the npm SDK's depth map holds them in, which orders each neighbour's fan).
static func _reach(g: Dictionary, centre: int, steps: int) -> Dictionary:
	var place: Dictionary = g["index"]
	var n: int = g["nodes"].size()
	var adj := []
	adj.resize(n)
	for i in n:
		adj[i] = []
	for e in g["edges"]:
		var a: int = place.get(e["source"], -1)
		var b: int = place.get(e["target"], -1)
		if a < 0 or b < 0:
			continue
		adj[a].append(b)
		if a != b:
			adj[b].append(a)
	var depth := PackedInt32Array()
	depth.resize(n)
	depth.fill(-1)
	depth[centre] = 0
	var via := PackedInt32Array()
	via.resize(n)
	var reached := [[]]
	var frontier := [centre]
	for s in range(1, steps + 1):
		var next := []
		for a: int in frontier:
			for to: int in adj[a]:
				if depth[to] >= 0:
					continue
				depth[to] = s
				via[to] = a
				next.append(to)
		reached.append(next)
		frontier = next
	return {"depth": depth, "via": via, "reached": reached}

## Check the graph, then put it in the method's one order, whatever order the caller handed: the nodes by id, the edges
## by source, then field (none as ""), then index (none as 0), then target, every word in code point order. Answers
## {handed, nodes, edges, index} (index: id -> place in the ordered nodes), or {error}.
static func _read_graph(fn: String, graph: Variant) -> Dictionary:
	var given_nodes: Variant = null
	var given_edges: Variant = null
	if graph is OWGraph.Graph:
		given_nodes = graph.nodes
		given_edges = graph.edges
	elif graph is Dictionary:
		given_nodes = graph.get("nodes")
		given_edges = graph.get("edges")
	if not (given_nodes is Array) or not (given_edges is Array):
		return {"error": "%s: the graph is { nodes, edges }, as world_graph answers it" % fn}
	var handed := []
	var seen := {}
	for i in given_nodes.size():
		var node: Variant = given_nodes[i]
		if node is Array:   # an array is an object to JavaScript's typeof, one with no id
			return {"error": "%s: node %d has no id" % [fn, i]}
		if not (node is Dictionary):
			return {"error": "%s: node %d is not an object" % [fn, i]}
		var id: Variant = node.get("id")
		if typeof(id) != TYPE_STRING or id == "":
			return {"error": "%s: node %d has no id" % [fn, i]}
		var type: Variant = node.get("type")
		if typeof(type) != TYPE_STRING or not OWPresentation.TYPES.has(type):
			return {"error": "%s: node %s: '%s' is not one of the 22 element types" % [fn, id, "undefined" if not node.has("type") else str(type)]}
		var name: Variant = node.get("name")
		if name != null and typeof(name) != TYPE_STRING:
			return {"error": "%s: node %s: name is a string or null" % [fn, id]}
		if seen.has(id):
			return {"error": "%s: the id %s is a node twice" % [fn, id]}
		seen[id] = true
		handed.append({"id": id, "type": type, "name": name})
	var edges := []
	for k in given_edges.size():
		var e: Variant = given_edges[k]
		if not (e is Dictionary) or typeof(e.get("source")) != TYPE_STRING or typeof(e.get("target")) != TYPE_STRING:
			return {"error": "%s: edge %d is not { source, target }" % [fn, k]}
		if e.has("field") and typeof(e["field"]) != TYPE_STRING:
			return {"error": "%s: edge %d: field is a string" % [fn, k]}
		var at := 0.0
		if e.has("index"):
			var v: Variant = e["index"]
			if (typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT) or not is_finite(float(v)):
				return {"error": "%s: edge %d: index is a number" % [fn, k]}
			at = float(v)
		edges.append({"source": e["source"], "target": e["target"], "field": e.get("field", ""), "index": at})
	var nodes := handed.duplicate()
	nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["source"] != b["source"]:
			return a["source"] < b["source"]
		if a["field"] != b["field"]:
			return a["field"] < b["field"]
		if a["index"] != b["index"]:
			return a["index"] < b["index"]
		return a["target"] < b["target"])
	var index := {}
	for i in nodes.size():
		index[nodes[i]["id"]] = i
	return {"handed": handed, "nodes": nodes, "edges": edges, "index": index}

static func _rank(type: String) -> int:
	return OWPresentation.ORDER.find(OWPresentation.TYPES[type]["family"])

static func _anchor(i: int) -> float:
	if _anchors.is_empty():
		_anchors = PackedInt64Array(OWLayoutAnchors.BITS).to_byte_array().to_float64_array()
	return _anchors[i]

## JavaScript's [code]Math.min[/code] of two: NaN if either is, and -0 below +0.
static func _min_js(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
	if a < b:
		return a
	if b < a:
		return b
	return a if a == 0.0 and 1.0 / a < 0.0 else b

## JavaScript's [code]Math.max[/code] of two: NaN if either is, and +0 above -0.
static func _max_js(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
	if a > b:
		return a
	if b > a:
		return b
	return a if a == 0.0 and 1.0 / a > 0.0 else b
