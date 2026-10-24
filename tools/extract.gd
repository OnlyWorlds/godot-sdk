extends SceneTree
## Read an .owworld and write its world as a folder (every file inside the world, as the reader returns it):
##   godot --headless --path <project> --script res://tools/extract.gd -- <file.owworld> <out folder>
## Exits 1 on a refusal, naming its cause.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <file.owworld> <out folder>")
		quit(2)
		return
	var r := OWWorldArchive.read_file(args[0])
	if not r.ok:
		printerr("refused: %s (%s)" % [r.reason, r.message])
		quit(1)
		return
	var out := args[1].replace("\\", "/").trim_suffix("/")
	for rel: String in r.files:
		DirAccess.make_dir_recursive_absolute((out + "/" + rel).get_base_dir())
		var f := FileAccess.open(out + "/" + rel, FileAccess.WRITE)
		f.store_buffer(r.files[rel])
		f.close()
	print("world %s: %d files -> %s" % [r.world_id, r.files.size(), out])
	quit(0)
