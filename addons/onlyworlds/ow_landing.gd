class_name OWLanding
extends RefCounted
## The landing profile (schema-dist [code]profiles/landing.md[/code], serial 103): a world's first picture at a door,
## read from the graph [method OWGraph.world_graph] answers for the visitor, so it sees exactly what that graph holds.
## A real world shows its most-linked Characters, each with what it links; a small one shows its gaps. It adds nothing
## to the world and holds structure only, never coordinates: a layout is the drawing tool's, keyed by id. The npm
## SDK's [code]landingOf[/code] and the Python package's [code]landing_of[/code], ported; the fixture beside the
## profile is this file's test.

## The options, each a whole number of 1 or more, null its default.
const OPTIONS := {"heads": 5, "hops": 1, "size": 24}
## What a whole number too large for a 64-bit int reads as (1e30 is whole, as the packages take it).
const I64_MAX := 9223372036854775807
## The gap kinds, in the order the answer lists them.
const GAP_KINDS := ["orphan", "near_orphan", "no_place", "nobody_here"]

## What [method landing_of] answers: the five parts, always all there. [member refused] names an option refused
## (nothing read); [member error] says why, and names a caller's mistake on its own; both "" otherwise.
class Landing:
	## [code]gaps[/code] when the graph has fewer nodes than [member size], [code]graph[/code] otherwise: which part a
	## door draws first. Both parts are always read.
	var mode := ""
	## The size the mode was read at.
	var size := 0
	## One [code]{head, members}[/code] per head, in the heads' order; a member is [code]{id, hops, degree}[/code], the
	## head first at 0, then by hops, then by degree (highest first), then by id in code point order.
	var clusters := []
	## Every node no head reaches, [code]{id, degree}[/code], by degree (highest first), then by id.
	var unclustered := []
	## [code]{kind, id}[/code], in [constant GAP_KINDS]'s order, then by id; a node can carry several.
	var gaps := []
	var refused := ""
	var error := ""

	## The answer in the fixture's shape: the five keys in order, or [code]{refused}[/code].
	func to_dict() -> Dictionary:
		if refused != "":
			return {"refused": refused}
		return {"mode": mode, "size": size, "clusters": clusters, "unclustered": unclustered, "gaps": gaps}

## The landing of [param graph] (an [OWGraph.Graph], or its [method OWGraph.Graph.to_dict] shape: [code]nodes[/code]
## and [code]edges[/code] Arrays), the profile's [code]landingOf[/code]. Pure: the graph is never changed and every
## part of the answer is the caller's own.
##
## [param options]: [code]heads[/code] (how many clusters at most, 5), [code]hops[/code] (how far a head reaches, 1),
## [code]size[/code] (the node count at which the mode turns from gaps to graph, 24); null takes the default. An unknown
## key, then [code]heads[/code], [code]hops[/code] and [code]size[/code] in that order, is refused by name before
## anything is read when it is not a whole number of 1 or more ([method OWLens.whole]: a float with no fraction is its
## number, as Godot's JSON reads every number; a bool is refused).
##
## Degree is [method OWGraph.degree_of]'s: every edge, in or out, once at each node it touches (a mirror pair is two
## edges, a link to itself counts once). Heads: the Characters with an edge, never a known-of node, most linked first,
## ties by id in code point order, the first [code]heads[/code]. A node within [code]hops[/code] steps of a head (a step
## follows an edge either way; a mirror pair is one step) joins the head it is fewest steps from, a tie going to the
## higher-ranked head. Gaps, never on a known-of node: [code]orphan[/code] (degree 0) and [code]near_orphan[/code]
## (degree 1), the links report's own; [code]no_place[/code], a Character whose [code]location[/code] edge reaches no
## Location node; [code]nobody_here[/code], a Location no Character's [code]location[/code] edge reaches. Every count
## is an int and ids compare by code point (Godot's String order), so the same graph and options give the same answer.
static func landing_of(graph: Variant, options: Variant = null) -> Landing:
	var l := Landing.new()
	var g := _graph_of(graph)
	if g == null:
		l.error = "landing_of: graph is what OWGraph.world_graph answers, a Graph or a Dictionary with nodes and edges Arrays"
		return l
	if options == null:
		options = {}
	if not options is Dictionary:
		l.error = "landing_of: options is a Dictionary, such as {\"heads\": 5}; got %s" % var_to_str(options)
		return l
	for k in options:
		if not OPTIONS.has(k):
			l.refused = str(k)
			l.error = "landing_of: options holds %s; got %s" % [", ".join(OPTIONS.keys()), str(k)]
			return l
	var opt := {}
	for k in OPTIONS:
		var v: Variant = options.get(k)
		if v == null:
			opt[k] = OPTIONS[k]
			continue
		var n: Variant = OWLens.whole(v)
		if n == null and v is float and not is_inf(v) and not is_nan(v) and floor(v) == v and v >= 1.0:
			n = I64_MAX   # a whole number too large to hold reads as the largest: a count past the nodes means all of them
		if n == null or n < 1:
			l.refused = k
			l.error = "landing_of: %s is a whole number, 1 or more; got %s" % [k, var_to_str(v)]
			return l
		opt[k] = n
	var nodes: Array = g.nodes
	var degree := OWGraph.degree_of(g)
	var near := {}
	var type_of := {}
	for n in nodes:
		near[n["id"]] = {}
		type_of[n["id"]] = n.get("type")
	var placed := {}
	var inhabited := {}
	for e in g.edges:
		var s: Variant = e["source"]
		var t: Variant = e["target"]
		if s != t and near.has(s) and near.has(t):
			near[s][t] = true
			near[t][s] = true
		if e.get("field") == "location" and type_of.get(s) == "character" and type_of.get(t) == "location":
			placed[s] = true
			inhabited[t] = true

	var heads := []
	for n in nodes:
		if n.get("type") == "character" and not _known_of(n) and degree[n["id"]] > 0:
			heads.append(n["id"])
	heads.sort_custom(func(a, b) -> bool: return degree[a] > degree[b] if degree[a] != degree[b] else a < b)
	heads = heads.slice(0, mini(opt["heads"], heads.size()))   # slice's end is 32-bit: a larger count wraps negative

	# Each node's least [hops, rank] over every head's own walk, so no visiting order ever decides a tie.
	var best := {}
	for rank in heads.size():
		var seen := {heads[rank]: 0}
		var frontier := [heads[rank]]
		var step := 0
		while step < opt["hops"] and not frontier.is_empty():
			var next := []
			for id in frontier:
				for nb in near[id]:
					if not seen.has(nb):
						seen[nb] = step + 1
						next.append(nb)
			frontier = next
			step += 1
		for id in seen:
			var b: Variant = best.get(id)
			if b == null or seen[id] < b[0] or (seen[id] == b[0] and rank < b[1]):
				best[id] = [seen[id], rank]

	for h in heads:
		l.clusters.append({"head": h, "members": []})
	for n in nodes:
		var id: String = n["id"]
		var b: Variant = best.get(id)
		if b != null:
			l.clusters[b[1]]["members"].append({"id": id, "hops": b[0], "degree": degree[id]})
		else:
			l.unclustered.append({"id": id, "degree": degree[id]})
	for k in l.clusters:
		k["members"].sort_custom(func(a, b) -> bool:
			if a["hops"] != b["hops"]:
				return a["hops"] < b["hops"]
			if a["degree"] != b["degree"]:
				return a["degree"] > b["degree"]
			return a["id"] < b["id"])
	l.unclustered.sort_custom(func(a, b) -> bool:
		return a["degree"] > b["degree"] if a["degree"] != b["degree"] else a["id"] < b["id"])

	for n in nodes:
		if _known_of(n):
			continue
		var id: String = n["id"]
		if degree[id] == 0:
			l.gaps.append({"kind": "orphan", "id": id})
		if degree[id] == 1:
			l.gaps.append({"kind": "near_orphan", "id": id})
		if n.get("type") == "character" and not placed.has(id):
			l.gaps.append({"kind": "no_place", "id": id})
		if n.get("type") == "location" and not inhabited.has(id):
			l.gaps.append({"kind": "nobody_here", "id": id})
	l.gaps.sort_custom(func(a, b) -> bool:
		var ka := GAP_KINDS.find(a["kind"])
		var kb := GAP_KINDS.find(b["kind"])
		return ka < kb if ka != kb else a["id"] < b["id"])

	l.mode = "gaps" if nodes.size() < opt["size"] else "graph"
	l.size = opt["size"]
	return l

## The graph as an [OWGraph.Graph] over the caller's own nodes and edges (read, never changed), or null when it is
## neither a Graph nor a Dictionary with nodes and edges Arrays.
static func _graph_of(graph: Variant) -> Variant:
	if graph is OWGraph.Graph:
		return graph
	if graph is Dictionary and graph.get("nodes") is Array and graph.get("edges") is Array:
		var g := OWGraph.Graph.new()
		g.nodes = graph["nodes"]
		g.edges = graph["edges"]
		return g
	return null

## A guest's stub: [code]known_of[/code] true exactly, as world_graph marks it.
static func _known_of(n: Dictionary) -> bool:
	var v: Variant = n.get("known_of")
	return v is bool and v
