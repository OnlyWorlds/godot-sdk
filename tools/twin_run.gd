extends SceneTree
## The lens twin's Godot side: read a cases file of random small worlds, answer each through this SDK's lens and graph
## readers, and write the answers in the shape the npm side writes, so one compare reads both.
##   godot --headless --path . --script res://tools/twin_run.gd -- <cases.jsonl> <out.jsonl>
## Each case is one JSON line: {i, kind: "resolve", world, lens, reader, as_of, clock} or
## {i, kind: "graph", world, reader, options} (options as world_graph takes them). Each answer is {i, got}: for resolve
## {kept, cut, rows, notes_ignored, mail, unreadable}, for graph {nodes, edges, edges_cut, cut, unreadable}, and for
## a call the reader refuses {threw: "refused", names, msg}, names being the flags its message names (npm's TypeError).
## A call that dies in a script error answers {threw: "error"}.
## The layout twin's cases ride in the same shape: {i, kind: "by-kind", graph} or {i, kind: "around", graph, focus,
## steps}, answered {points} through OWLayout, each point [id, x, y] or [id, depth, x, y] with every coordinate as its
## float64 bits in 16 hex digits (Godot's JSON would misread some decimals), or {threw: "refused", msg}.
## Two more arguments, <from> <to>, answer only the cases with from <= i < to, for a file too long for one run.

const FLAGS := ["hidden", "proposed", "rooms", "map_space", "reading_aids"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var out := PackedStringArray()
	var from := int(args[2]) if args.size() > 3 else 0
	var to := int(args[3]) if args.size() > 3 else 1 << 62
	for line in FileAccess.get_file_as_string(args[0]).split("\n", false):
		var c: Dictionary = JSON.parse_string(line)
		if int(c["i"]) < from or int(c["i"]) >= to:
			continue
		out.append(JSON.stringify({"i": int(c["i"]), "got": _answer(c)}, "", false, true))
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("godot: %d results in %.1f s" % [out.size(), (Time.get_ticks_msec() - started) / 1000.0])
	quit(0)

static func _hex(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	b.reverse()
	return b.hex_encode()

func _layout(c: Dictionary) -> Dictionary:
	var r := OWLayout.layout_by_kind(c["graph"]) if c["kind"] == "by-kind" else OWLayout.layout_around(c["graph"], c["focus"], int(c["steps"]))
	if r.has("error"):
		return {"threw": "refused", "msg": r["error"]}
	var points := []
	for p in r["points"]:
		points.append([p["id"], _hex(p["x"]), _hex(p["y"])] if c["kind"] == "by-kind" else [p["id"], p["depth"], _hex(p["x"]), _hex(p["y"])])
	return {"points": points}

func _answer(c: Dictionary) -> Dictionary:
	var msg := ""
	if c["kind"] == "by-kind" or c["kind"] == "around":
		return _layout(c)
	if c["kind"] == "resolve":
		var r: OWLens.Reading = OWLens.resolve(c["world"], c["lens"], c["reader"], {"as_of": c["as_of"], "clock": c["clock"]})
		if r == null:
			return {"threw": "error", "names": [], "msg": "script error"}
		if r.error == "":
			return r.to_dict()
		msg = r.error
	else:
		var g: OWGraph.Graph = OWGraph.world_graph(c["world"], c["reader"], c["options"])
		if g == null:
			return {"threw": "error", "names": [], "msg": "script error"}
		if g.error == "" and g.refused == "":
			return g.to_dict()
		msg = g.error
	return {"threw": "refused", "names": FLAGS.filter(func(x: String) -> bool: return msg.contains(x)), "msg": msg}
