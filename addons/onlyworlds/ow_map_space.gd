class_name OWMapSpace
extends RefCounted
## The map space profile (schema-dist [code]profiles/map-space.md[/code], serial 106): how a reader turns a world's
## Maps, Zones, Markers and Pins into geometry, a Map's frame, a Zone's outline from its Markers, a Pin's point. It
## adds nothing to the world: structure and coordinates in the Map's own pixels; looks, cameras, walls, doors and units
## are a drawing tool's. The npm SDK's [code]mapSpace[/code] and the Python package's [code]map_space[/code], ported;
## the fixture beside the profile is this file's test. Since serial 110 also the profile's second, small reading,
## [method layout_of]: one Map's layout keys ([code]x_layout[/code] on the Map, [code]x_hand[/code] on its Pins),
## the fixture's [code]layout_cases[/code] its test.

## The reasons [member MapSpace.out] counts, in the order it lists them.
const OUT_REASONS := ["no_point", "no_markers", "dangling", "no_map"]

## What [method map_space] answers: the four parts, always all there. [member error] names a caller's mistake (nothing
## read), "" otherwise.
class MapSpace:
	## One [code]{id, width, height, depth, z_max, scale, location, parent_map}[/code] per Map, by id in code point
	## order, with [code]extent: "points"[/code] last when [code]width[/code] or [code]height[/code] was measured.
	var maps := []
	## One [code]{zone, map, shape, points}[/code] per Zone and Map it has placed Markers on, by zone id, then map id;
	## each point [code][x, y, z][/code].
	var zones := []
	## One [code]{pin, map, element_type, element_id, x, y, z}[/code] per Pin read, by id in code point order.
	var pins := []
	## What the reading left aside, by reason, in [constant OUT_REASONS]'s order; a reason with nothing counted is
	## absent.
	var out := {}
	var error := ""

	## The answer in the fixture's shape: the four keys in order.
	func to_dict() -> Dictionary:
		return {"maps": maps, "zones": zones, "pins": pins, "out": out}

## The map space of [param elements] (an Array of element Dictionaries, each with its [code]type[/code] and
## [code]id[/code], as the reader is served them: a folder's rows or the API's), the profile's [code]mapSpace[/code].
## Visibility is already applied, so a Zone the reader may not see is not in the input and never brought back. Pure:
## the elements are never changed and every part of the answer is the caller's own.
##
## Coordinates count from the bottom left of the Map in its pixels; [code]z[/code] is an elevation, never a height,
## and reads 0 when absent or not whole. A whole number is read by value ([method _whole]: [code]2.0[/code] is 2, as
## Godot's JSON reads every number as a float; a bool, a fraction or a string is not one). A Zone's outline is the
## Markers that name it and one Map, by [code]order[/code] ascending; a Marker without a whole [code]order[/code]
## sorts after every ordered one, then by id. A Marker whose Zone or Map is not served is counted
## [code]dangling[/code] (checked first), one without a whole [code]x[/code] and [code]y[/code]
## [code]no_point[/code]; a Zone without a placed Marker [code]no_markers[/code]; a Pin whose Map is not served
## [code]no_map[/code], one without a point [code]no_point[/code]. A Pin's element is its two keys,
## [code]element_type[/code] and [code]element_id[/code], or both null when it has only one. A Map's
## [code]width[/code] or [code]height[/code] that is not whole is the largest x or y among its own outline and Pin
## points ([code]extent: "points"[/code]); [code]z_max[/code] is their largest z, kept past [code]depth[/code];
## [code]scale[/code] is [code]x_metres_per_pixel[/code] when a positive number, as given. A row without a non-empty
## String id or a String type is no element: ignored, never counted; two rows of one type with one id read as the last
## one served, even when it reads less. [code]type[/code] and [code]shape[/code] are read as written
## ([code]Map[/code] is no Map, [code]Line[/code] a polygon). Ids compare by code point (Godot's String order), so
## the same elements give the same answer.
static func map_space(elements: Variant) -> MapSpace:
	var a := MapSpace.new()
	if not elements is Array:
		a.error = "map_space: elements is an Array of element Dictionaries; got %s" % var_to_str(elements)
		return a
	# One row per id within a type, the last served (reading I): an element is its id. The type is read as written
	# (reading K: "Map" is no Map).
	var by_type := {}   # type -> {id -> row}
	for e in elements:
		# A row without a non-empty String id is no element: ignored, never counted.
		if not (e is Dictionary and e.get("type") is String and _id_of(e.get("id")) != null):
			continue
		if not by_type.has(e["type"]):
			by_type[e["type"]] = {}
		by_type[e["type"]][_id_of(e["id"])] = e
	var maps: Dictionary = by_type.get("map", {})
	var zones: Dictionary = by_type.get("zone", {})
	var out := {"no_point": 0, "no_markers": 0, "dangling": 0, "no_map": 0}

	# Markers: dangling first, then no_point; a Marker counts once.
	var placed := {}   # JSON of [zone, map] -> {zone, map, markers}
	for mk in by_type.get("marker", {}).values():
		var z: Variant = _id_of(mk.get("zone"))
		var m: Variant = _id_of(mk.get("map"))
		if z == null or m == null or not zones.has(z) or not maps.has(m):
			out["dangling"] += 1
			continue
		if _whole(mk.get("x")) == null or _whole(mk.get("y")) == null:
			out["no_point"] += 1
			continue
		var key := JSON.stringify([z, m])
		if not placed.has(key):
			placed[key] = {"zone": z, "map": m, "markers": []}
		placed[key]["markers"].append(mk)

	var zone_ids: Array = zones.keys()
	zone_ids.sort()
	for zid in zone_ids:
		var groups: Array = placed.values().filter(func(g): return g["zone"] == zid)
		if groups.is_empty():
			out["no_markers"] += 1
			continue
		groups.sort_custom(func(x, y) -> bool: return x["map"] < y["map"])
		var shape := "line" if zones[zid].get("shape") is String and zones[zid]["shape"] == "line" else "polygon"
		for g in groups:
			var markers: Array = g["markers"].duplicate()
			markers.sort_custom(func(x, y) -> bool: return _marker_before(x, y))
			var points := markers.map(func(mk): return _point(mk))
			a.zones.append({"zone": zid, "map": g["map"], "shape": shape, "points": points})

	var pin_rows: Array = by_type.get("pin", {}).values()
	pin_rows.sort_custom(func(x, y) -> bool: return _id_of(x["id"]) < _id_of(y["id"]))
	for p in pin_rows:
		var m: Variant = _id_of(p.get("map"))
		if m == null or not maps.has(m):
			out["no_map"] += 1
			continue
		if _whole(p.get("x")) == null or _whole(p.get("y")) == null:
			out["no_point"] += 1
			continue
		var et: Variant = _id_of(p.get("element_type"))
		var ei: Variant = _id_of(p.get("element_id"))
		if et == null or ei == null:   # a link needs both keys; one alone reads as neither
			et = null
			ei = null
		var pt := _point(p)
		a.pins.append({"pin": _id_of(p["id"]), "map": m, "element_type": et, "element_id": ei,
			"x": pt[0], "y": pt[1], "z": pt[2]})

	var map_ids: Array = maps.keys()
	map_ids.sort()
	for mid in map_ids:
		var mp: Dictionary = maps[mid]
		var own := []
		for o in a.zones:
			if o["map"] == mid:
				own.append_array(o["points"])
		for q in a.pins:
			if q["map"] == mid:
				own.append([q["x"], q["y"], q["z"]])
		var measured := false
		var size := []
		for slot in [["width", 0], ["height", 1]]:
			var v: Variant = _whole(mp.get(slot[0]))
			if v == null:
				measured = true
				v = _largest(own, slot[1])
			size.append(v)
		var row := {"id": mid, "width": size[0], "height": size[1], "depth": _whole(mp.get("depth")),
			"z_max": _largest(own, 2), "scale": _scale(mp.get("x_metres_per_pixel")),
			"location": _id_of(mp.get("location")), "parent_map": _id_of(mp.get("parent_map"))}
		if measured:
			row["extent"] = "points"
		a.maps.append(row)

	for k in OUT_REASONS:
		if out[k] > 0:
			a.out[k] = out[k]
	return a

## What [method layout_of] answers: the layout reading's three parts, always all there. [member error] names a
## caller's mistake (nothing read), "" otherwise.
class MapLayout:
	## The Map's [code]x_layout.method[/code] when the Map is a layout map ([code]"hand"[/code] for a board, a method
	## no page names answering itself), else null.
	var layout: Variant = null
	## When [member layout] is not null, the id in [code]x_layout.settings.ground.map[/code] when it names a served Map
	## other than this one, else null. Its size is not returned: the served Map's own wins, and the caller holds it.
	var ground: Variant = null
	## The ids of this Map's Pins a new lay-out keeps where they are, by id in code point order.
	var hand := []
	var error := ""

	## The answer in the fixture's shape: the three keys in order.
	func to_dict() -> Dictionary:
		return {"layout": layout, "ground": ground, "hand": hand}

## One Map's layout keys, the map space profile's layout reading (rules 8 to 10, serial 110; the npm SDK's
## [code]layoutOf[/code] and the Python package's [code]layout_of[/code], ported): [param map] the Map read,
## [param maps] the Maps the reader is served, [param pins] every Pin the caller holds, of any Map, as served. The
## reader keeps the Pins whose [code]map[/code] names this Map's id, so a caller passes every Pin it has. Rows are read
## as [method map_space] reads them: a row without a non-empty String id is no element (a Map row without one is no
## layout map), and of two Pin rows with one id the last served is read. Pure: nothing in the input is changed and the
## answer is the caller's own.
##
## The Map is a layout map when its [code]x_layout[/code] is a Dictionary whose [code]method[/code] is a non-empty
## String; anything else (absent, null, a string, no [code]method[/code], [code]""[/code], a number) is no layout, and
## its ground and Pins are not read. On a board ([code]method[/code] [code]"hand"[/code]) every Pin of the Map is
## kept, marked or not; on any other layout map only the Pins whose [code]x_hand[/code] is exactly [code]true[/code]
## (a bool: [code]1[/code], [code]1.0[/code] and [code]"true"[/code] are not); on a Map that is not a layout map none,
## whatever its Pins carry. A Pin whose element the reader cannot see is still a Pin. How a method places Pins, and
## its own settings, are a layout tool's: a tool that cannot run one draws the Pins where they are.
static func layout_of(map: Variant, maps: Variant, pins: Variant) -> MapLayout:
	var a := MapLayout.new()
	if not map is Dictionary:
		a.error = "layout_of: map is one Map element Dictionary; got %s" % var_to_str(map)
		return a
	if not maps is Array:
		a.error = "layout_of: maps is an Array of Map elements; got %s" % var_to_str(maps)
		return a
	if not pins is Array:
		a.error = "layout_of: pins is an Array of Pin elements; got %s" % var_to_str(pins)
		return a
	var id: Variant = _id_of(map.get("id"))
	if id == null:
		return a

	# Rule 8: the mark is x_layout alone, a Dictionary with a non-empty String method.
	var recipe: Variant = map.get("x_layout")
	if not recipe is Dictionary:
		return a
	var method: Variant = _id_of(recipe.get("method"))
	if method == null:
		return a

	# Rule 9: the ground is a served Map other than this one, named by settings.ground.map.
	var settings: Variant = recipe.get("settings")
	if settings is Dictionary and settings.get("ground") is Dictionary:
		var g: Variant = _id_of(settings["ground"].get("map"))
		if g != null and g != id and maps.any(func(m): return m is Dictionary and _id_of(m.get("id")) == g):
			a.ground = g

	# Rule 10: one row per Pin id, the last served; this Map's Pins, every one on a board, else the marked ones.
	var held := {}
	for p in pins:
		if p is Dictionary and _id_of(p.get("id")) != null:
			held[_id_of(p["id"])] = p
	var board: bool = method == "hand"
	for pid in held:
		var p: Dictionary = held[pid]
		if _id_of(p.get("map")) != id:
			continue
		var mark: Variant = p.get("x_hand")
		if board or (typeof(mark) == TYPE_BOOL and mark):
			a.hand.append(pid)
	a.hand.sort()
	a.layout = method
	return a

## A whole number by value, or null: an int, or a float with no fraction within 2^53 - 1, the range a double holds
## exactly ([method OWLens.whole]: [code]2.0[/code] is 2, as Godot's JSON reads every number as a float). A float past
## it may be a value the parse had to round, so it is past this reader's integer range and reads as not whole, as the
## page says (the fixture keeps every number within 2^53).
## A bool, NaN, an infinity, a fraction or a string is not one.
static func _whole(v: Variant) -> Variant:
	return OWLens.whole(v)

## An id: a non-empty String (a StringName read as its String); anything else reads as none.
static func _id_of(v: Variant) -> Variant:
	if (v is String or v is StringName) and String(v) != "":
		return String(v)
	return null

## A scale: a positive number as given (never a bool), else null.
static func _scale(v: Variant) -> Variant:
	if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v > 0:
		return v
	return null

## [code][x, y, z][/code] of a Marker or Pin whose x and y are whole; a z that is absent or not whole reads 0.
static func _point(e: Dictionary) -> Array:
	var z: Variant = _whole(e.get("z"))
	return [_whole(e["x"]), _whole(e["y"]), 0 if z == null else z]

## The ordered Markers by order, then the rest; each tie by id in code point order.
static func _marker_before(x: Dictionary, y: Dictionary) -> bool:
	var ox: Variant = _whole(x.get("order"))
	var oy: Variant = _whole(y.get("order"))
	if ox != null and oy != null and ox != oy:
		return ox < oy
	if (ox == null) != (oy == null):
		return ox != null
	return _id_of(x["id"]) < _id_of(y["id"])

## The largest value at [param index] among [param points], null when there are none.
static func _largest(points: Array, index: int) -> Variant:
	var best: Variant = null
	for p in points:
		if best == null or p[index] > best:
			best = p[index]
	return best
