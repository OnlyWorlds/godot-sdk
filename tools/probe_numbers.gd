extends SceneTree
## Measure OWJson.number against Python's repr on exact doubles, and Godot's parser against the same doubles.
##   godot --headless --path . --script res://tools/probe_numbers.gd -- <file>
## Each line of <file>: "<16 hex digits of a positive double's bits> <Python repr>", for doubles in [1e-4, 1e16),
## where Python's repr and JavaScript's Number toString lay the digits out alike (an integral one aside: ".0").
func _init() -> void:
	var lines := FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]).split("\n", false)
	var writer_bad := 0
	var parser_bad := 0
	var shown := 0
	for l in lines:
		var parts := l.strip_edges().split(" ")
		var b := PackedByteArray()
		b.resize(8)
		b.encode_u64(0, parts[0].hex_to_int())
		var exact := b.decode_double(0)
		var want: String = parts[1].trim_suffix(".0")
		var got := OWJson.number(exact)
		if got != want:
			writer_bad += 1
			if shown < 5:
				shown += 1
				print("writer: %s -> %s" % [want, got])
		var pb := PackedByteArray()
		pb.resize(8)
		pb.encode_double(0, float(JSON.parse_string(parts[1])))
		if pb != b:
			parser_bad += 1
	print("doubles=%d  OWJson.number differs from the shortest=%d  JSON.parse_string not the exact double=%d" % [lines.size(), writer_bad, parser_bad])
	quit(0)
