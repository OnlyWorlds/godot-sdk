extends SceneTree
## Pack a world folder, or repack an .owworld, from a shell:
##   godot --headless --path <project> --script res://tools/pack.gd -- <folder | file.owworld> <out.owworld> [--keep-api] [--include-private]
##       [--include-author-fields]
## A folder goes through OWWorldArchive.pack (only the folder's parts, the author fields left out unless asked); an
## .owworld is read, then its files are packed back as they are (OW-9). Prints the entry count; exits 1 on a refusal.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <folder | file.owworld> <out.owworld> [--keep-api] [--include-private] [--include-author-fields]")
		quit(2)
		return
	var src := args[0]
	var dst := args[1]
	var p: OWWorldArchive.Packed
	if FileAccess.file_exists(src):
		var r := OWWorldArchive.read_file(src)
		if not r.ok:
			printerr("refused: %s (%s)" % [r.reason, r.message])
			quit(1)
			return
		p = OWWorldArchive.pack_files(r.files, r.prefix.trim_suffix("/"))
		if p.ok:
			var f := FileAccess.open(dst, FileAccess.WRITE)
			f.store_buffer(p.bytes)
			f.close()
	else:
		p = OWWorldArchive.pack(src, dst, args.has("--keep-api"), args.has("--include-private"),
			args.has("--include-author-fields"))
	if not p.ok:
		printerr("not packed: %s" % p.message)
		quit(1)
		return
	print("packed %d entries, %d bytes, %d files without their author fields -> %s" % [p.names.size(), p.bytes.size(),
		p.author_fields_left_out.size(), dst])
	quit(0)
