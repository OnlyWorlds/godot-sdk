class_name OWGraph
extends RefCounted
## The lens profile's graph section (schema-dist [code]profiles/lens.md[/code], serial 82): a reading of a world as
## nodes and edges. The elements a reader sees are the nodes, the links between them the edges. It adds nothing to the
## world and stores nothing. Who sees what is [OWLens]'s own reading, never a second copy; with a lens the nodes are
## exactly what the lens kept. The npm SDK's [code]worldGraph[/code], [code]degreeOf[/code] and
## [code]outDegreeOf[/code] (4.98.0) and the Python package's [code]world_graph[/code], ported; the fixture's graph kind
## is this file's test.

## The extension fields a published profile declares a link, each a list of ids: the lens profile's and the spine's.
const DECLARED_LINKS := ["x_lens_leads_to", "x_spine_depends_on"]
## The flags, each bringing back one kind of element that is out by default.
const FLAGS := ["rooms", "hidden", "proposed", "map_space"]
## The flags only the owner may ask (judged by the rung it reads as).
const OWNER_ONLY_FLAGS := ["hidden", "proposed"]
## Map space: out by default for size, not for standing (a node it brings back carries no mark).
const MAP_SPACE := ["map", "pin", "marker", "zone"]
## Every reason an element is not a node or an edge was cut, in the order the npm and Python packages count them:
## the lens's nine, then the graph's own.
const REASONS := ["budget", "types", "window", "stale", "undated", "after_as_of", "anchor_not_visible", "not_visible",
	"hops_not_served", "room", "hidden", "proposed", "map_space", "reading_aid", "outside_lens"]
## The reasons a reader that is not the owner never carries, not even as zero.
const OWNER_ONLY_REASONS := ["anchor_not_visible", "not_visible", "hidden", "proposed"]
## The type's family and icon: schema-dist presentation.json's first-party defaults (held equal to it by the tests).
## Colour stays the tool's.
const FAMILIES := {
	"ability": "abstract", "collective": "agents", "character": "agents", "construct": "world", "creature": "agents",
	"event": "temporal", "family": "agents", "institution": "agents", "language": "abstract", "law": "abstract",
	"location": "world", "map": "world", "marker": "world", "narrative": "temporal", "object": "world",
	"phenomenon": "temporal", "pin": "world", "relation": "temporal", "species": "agents", "title": "abstract",
	"trait": "abstract", "zone": "world",
}
const ICONS := {
	"ability": "auto_fix_normal", "collective": "groups_3", "character": "person", "construct": "api",
	"creature": "bug_report", "event": "saved_search", "family": "supervisor_account", "institution": "account_balance",
	"language": "edit_road", "law": "gpp_bad", "location": "castle", "map": "map", "marker": "polyline",
	"narrative": "menu_book", "object": "webhook", "phenomenon": "thunderstorm", "pin": "push_pin", "relation": "link",
	"species": "crib", "title": "military_tech", "trait": "flaky", "zone": "pentagon",
}

const _OPTION_KEYS := ["lens", "as_of", "clock", "rooms", "hidden", "proposed", "map_space"]

## What [method world_graph] answers. [member refused] names a flag asked from the wrong rung (nothing read);
## [member error] names a caller's mistake (nothing read); both "" otherwise.
class Graph:
	## The nodes, by id in code point order: {id, type, name, family, icon}, with marks (room, hidden, proposed) when
	## any applies and known_of true on a guest's stub.
	var nodes := []
	## The edges, by source id, then field name (both by code point), then index: {source, field, target, index}.
	var edges := []
	## The links left out because their target is not a node, by the target's reason.
	var edges_cut := {}
	## With a lens, the lens's own cut, unchanged; without one, the elements out by default, by reason.
	var cut := {}
	## With a lens the lens reader cannot read, the key it names, and the graph is empty; null otherwise.
	var unreadable: Variant = null
	var refused := ""
	var error := ""

	## The graph in the fixture's shape.
	func to_dict() -> Dictionary:
		if refused != "":
			return {"refused": refused}
		return {"nodes": nodes, "edges": edges, "edges_cut": edges_cut, "cut": cut, "unreadable": unreadable}

## Read [param world] as a graph for one [param reader] (the profile's [code]worldGraph[/code]): the elements the reader
## sees as nodes, the links between them as edges, and what was left out, counted by reason. Pure: it never writes.
##
## [param world] and [param reader] are what [method OWLens.resolve] takes. [param options]: [code]lens[/code] (a lens
## body or id: the nodes are exactly what it kept, its cut rides along, and no flag adds to them), [code]as_of[/code]
## and [code]clock[/code] (the lens's reading), and the flags [code]rooms[/code], [code]hidden[/code],
## [code]proposed[/code], [code]map_space[/code] (booleans, false by default). Without a lens, room, hidden, proposed
## and map-space elements are out unless their flag brings them back, marked, and so are the reading aids
## ([method OWLens.is_charter_element]), counted [code]reading_aid[/code], which no flag brings back. [code]hidden[/code] or
## [code]proposed[/code] from any rung but the owner's, or any flag from a public reader, is refused by name before
## anything is read (the first in the order hidden, proposed, rooms, map_space).
static func world_graph(world: Variant, reader: Variant, options: Variant = null) -> Graph:
	var g := Graph.new()
	if options == null:
		options = {}
	if not (options is Dictionary):
		return _mistake(g, "world_graph: options is a Dictionary, such as {\"rooms\": true}")
	for k in options:
		if not _OPTION_KEYS.has(k):
			return _mistake(g, "world_graph: options holds %s; got %s" % [", ".join(_OPTION_KEYS), k])
	if not (world is Dictionary and world.get("elements") is Array):
		return _mistake(g, "world_graph: world is a Dictionary with an elements Array")
	var bad := OWLens._check_reader(reader, "world_graph: reader")
	if bad != "":
		return _mistake(g, bad)
	var flags := {}
	for f in FLAGS:
		var v: Variant = options.get(f)
		if v != null and not (v is bool):
			return _mistake(g, "world_graph: %s is a boolean; got %s" % [f, var_to_str(v)])
		flags[f] = v == true
	var seen_rung: String = reader["as"]["rung"] if reader["rung"] == "owner" and reader.get("as") != null else reader["rung"]
	for f in OWNER_ONLY_FLAGS:
		if flags[f] and seen_rung != "owner":
			g.refused = f
			return _mistake(g, "world_graph: %s is the owner's alone; a %s reader may not ask it" % [f, seen_rung])
	if seen_rung == "public":
		for f in ["rooms", "map_space"]:
			if flags[f]:
				g.refused = f
				return _mistake(g, "world_graph: a public reader takes no flag; it asked %s" % f)
	var as_of_v: Variant = options.get("as_of")
	if as_of_v != null and OWLens.whole(as_of_v) == null:
		return _mistake(g, "world_graph: as_of is a whole number; got %s" % var_to_str(as_of_v))
	var clock_v: Variant = options.get("clock")
	if clock_v != null and OWLens.time_key(clock_v) == null:
		return _mistake(g, "world_graph: clock is a date-time; got %s" % var_to_str(clock_v))
	var lens: Variant = options.get("lens")
	if lens != null and not (lens is String or lens is Dictionary):
		return _mistake(g, "world_graph: lens is a lens body or its id")

	var as_of: Variant = OWLens.whole(as_of_v) if as_of_v != null else OWLens._world_now(world)
	var r := OWLens.View.new(world, reader, as_of)
	var seen_owner := r.seen_rung == "owner"
	var kinds := func(id: String) -> Array:
		var out := []
		if r.room.has(id):
			out.append("rooms")
		if r.hidden.has(id):
			out.append("hidden")
		if r.proposed.has(id):
			out.append("proposed")
		if MAP_SPACE.has(r.type_of[id]):
			out.append("map_space")
		if r.aid.has(id):
			out.append("reading_aid")
		return out
	# What the reader could see as a node: its view, and for the owner what is written as proposed too.
	var candidate := func(id: String) -> bool: return r.view.has(id) or (seen_owner and r.proposed.has(id))
	var out_by := func(id: String) -> Variant:
		for k in kinds.call(id):
			# A reading aid has no flag: only a lens that names its pair keeps one.
			if k == "reading_aid" or not flags[k]:
				return _reason_of_kind(k)
		return null

	var node_ids := {}
	var reason_of: Callable
	if lens != null:
		var lr: Array = OWLens._lens_reading(r, lens, clock_v)
		var reading: OWLens.Reading = lr[0]
		var cut_by_id: Dictionary = lr[1]
		for id in reading.kept:
			node_ids[id] = true
		g.cut = reading.cut.duplicate()
		g.unreadable = reading.unreadable
		reason_of = func(id: String) -> Variant:
			if cut_by_id.has(id):
				return cut_by_id[id]
			return "outside_lens" if r.view.has(id) else "not_visible"
	else:
		var counts := {}
		for id in r.order:
			if not candidate.call(id):
				continue
			var why: Variant = out_by.call(id)
			if why == null:
				node_ids[id] = true
			else:
				counts[why] = counts.get(why, 0) + 1
		g.cut = _tally(counts, r.owner)
		reason_of = func(id: String) -> Variant: return out_by.call(id) if candidate.call(id) else "not_visible"

	var ids: Array = node_ids.keys()
	ids.sort()   # Godot's String order is by code point
	for id in ids:
		var el: Dictionary = r.by_id[id]
		var type: String = r.type_of[id]
		var node := {"id": id, "type": type, "name": el["name"] if el.get("name") is String else null,
			"family": FAMILIES[type], "icon": ICONS[type]}
		var marks := []
		for k in kinds.call(id):
			if k != "map_space" and k != "reading_aid":
				marks.append(_reason_of_kind(k))
		if not marks.is_empty():
			node["marks"] = marks
		if r.stubs.has(id):
			node["known_of"] = true
		g.nodes.append(node)

	var cut_edges := {}
	var visit := func(source: String, field: String, target: Variant, index: int) -> void:
		if not (target is String) or not r.by_id.has(target):
			return
		if node_ids.has(target):
			g.edges.append({"source": source, "field": field, "target": target, "index": index})
			return
		var why: Variant = reason_of.call(target)
		if why != null:
			cut_edges[why] = cut_edges.get(why, 0) + 1
	for source in ids:
		if r.stubs.has(source):
			continue
		var el: Dictionary = r.by_id[source]
		# A schema link is served whole to the owner; any other view is served it less the ids outside that view.
		for lf in OWLens.link_fields_of(r.type_of[source]):
			var v: Variant = el.get(lf[0])
			var list: Array = (v if v is Array else []) if lf[1] else [v]
			var served := 0
			for i in list.size():
				var t: Variant = list[i]
				var in_served: bool = seen_owner or (t is String and r.view.has(t))
				visit.call(source, lf[0], t, i if seen_owner else served)
				if in_served:
					served += 1
		# A declared extension link is served as stored to every reader.
		for field in DECLARED_LINKS:
			var v: Variant = el.get(field)
			if v is Array:
				for i in v.size():
					visit.call(source, field, v[i], i)
	g.edges.sort_custom(func(a, b) -> bool:
		if a["source"] != b["source"]:
			return a["source"] < b["source"]
		if a["field"] != b["field"]:
			return a["field"] < b["field"]
		return a["index"] < b["index"])
	g.edges_cut = _tally(cut_edges, r.owner)
	return g

## Each node's degree in a graph [method world_graph] answered: its edges, in or out, each edge counted once for every
## node it touches (a mirror pair is two edges, so each end counts 2; a link to itself counts once). Every node is a
## key, 0 included, in the graph's node order. Edges join nodes only, so the count is the reader's. "Most linked" for
## a finder: rank by it, highest first.
static func degree_of(graph: Graph) -> Dictionary:
	var count := {}
	for n in graph.nodes:
		count[n["id"]] = 0
	for e in graph.edges:
		if count.has(e["source"]):
			count[e["source"]] += 1
		if e["target"] != e["source"] and count.has(e["target"]):
			count[e["target"]] += 1
	return count

## Each node's out-degree in a graph [method world_graph] answered: the number of distinct nodes its own link fields
## point at. A target listed in two fields counts once, a link to itself does not count, and a mirror pair (A lists B,
## B lists A) counts 1 at each end, since each counts its own list. Every node is a key, 0 included, in the graph's node
## order. Like [method degree_of], the count is the reader's. How far an element reaches out, apart from how often it
## is named.
static func out_degree_of(graph: Graph) -> Dictionary:
	var targets := {}
	for n in graph.nodes:
		targets[n["id"]] = {}
	for e in graph.edges:
		if e["target"] != e["source"] and targets.has(e["source"]):
			targets[e["source"]][e["target"]] = true
	var count := {}
	for id in targets:
		count[id] = targets[id].size()
	return count

## The flag's word as a reason and a mark: rooms brings back what is out as room.
static func _reason_of_kind(kind: String) -> String:
	return "room" if kind == "rooms" else kind

## Counts in the reasons' one order, a reason with no count left out, the owner's reasons kept for the owner.
static func _tally(counts: Dictionary, owner: bool) -> Dictionary:
	var out := {}
	for why in REASONS:
		if OWNER_ONLY_REASONS.has(why) and not owner:
			continue
		var n: int = counts.get(why, 0)
		if n > 0:
			out[why] = n
	return out

static func _mistake(g: Graph, message: String) -> Graph:
	g.error = message
	return g
