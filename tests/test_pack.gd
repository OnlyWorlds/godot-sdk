extends RefCounted
## OWWorldArchive.pack: its own zip bytes, held to the writer's MUST rules (the marker stored first and bare, only the
## folder's parts, UTF-8 byte order, 1980 stamps, methods 0 and 8), read back by the reader, and the folder rules
## (records/ whole, private producers left out unless asked, tool litter dropped). The reference checker's own
## check_writer runs on its output from a shell: tools/check_writer.py.

const P = preload("res://tests/paths.gd")

func _doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(P.FIXTURES + "/verdicts.json"))

func _tmp(name: String) -> String:
	return ProjectSettings.globalize_path(P.TMP + "/" + name)

func _write_tree(root: String, files: Dictionary) -> void:
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(files[rel])
		f.close()

## The writer's MUST rules on an archive's bytes; returns the faults found.
func _writer_faults(bytes: PackedByteArray, source: Dictionary, prefix: String) -> PackedStringArray:
	var faults := PackedStringArray()
	var w := OWZip.walk(bytes)
	if w.error != "":
		return PackedStringArray(["does not walk: " + w.message])
	var first: OWZip.Entry = w.entries[0]
	if first.name != OWWorldArchive.MARKER or first.offset != 0:
		faults.append("OW-6: the marker is not the first entry")
	if first.method != 0 or first.extra.size() != 0 or bytes.decode_u16(28) != 0:
		faults.append("OW-6: the marker is compressed or carries an extra field")
	var prev := PackedByteArray()
	for i in w.entries.size():
		var e: OWZip.Entry = w.entries[i]
		var lo := e.offset
		if bytes.decode_u16(lo + 10) != 0 or bytes.decode_u16(lo + 12) != 0x21:
			faults.append("OW-12: %s's local header is not stamped 1980-01-01 00:00" % e.name)
		if e.method != 0 and e.method != 8:
			faults.append("OW-21: %s uses method %d" % [e.name, e.method])
		if e.usize > 0 and e.method != 8 and i > 0:
			faults.append("%s is stored, not deflated" % e.name)
		if i > 0:
			if i > 1 and not _bytes_less(prev, e.raw_name):
				faults.append("OW-12/13: %s is out of UTF-8 byte order" % e.name)
			prev = e.raw_name
			if (e.flags & OWZip.FLAG_UTF8 != 0) != (e.raw_name.size() != e.name.length()):
				faults.append("OW-22: %s's UTF-8 flag is wrong" % e.name)
	var cd: int = bytes.decode_u32(bytes.size() - 22 + 16)
	for k in w.entries.size():
		var p := cd
		if bytes.decode_u16(p + 12) != 0 or bytes.decode_u16(p + 14) != 0x21:
			faults.append("OW-12: a directory record is not stamped 1980-01-01 00:00")
		cd += 46 + bytes.decode_u16(p + 28) + bytes.decode_u16(p + 30) + bytes.decode_u16(p + 32)
	var r := OWWorldArchive.read(bytes)
	if not r.ok:
		faults.append("the reader refuses it: %s" % r.message)
		return faults
	for rel: String in source["files"]:
		if not r.files.has(rel):
			faults.append("OW-8/9: %s from the source is missing" % rel)
		else:
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_SHA256)
			ctx.update(r.files[rel])
			if ctx.finish().hex_encode() != source["files"][rel]:
				faults.append("OW-8/11: %s differs from the source's bytes" % rel)
	if r.files.size() != source["files"].size():
		faults.append("%d files, the source has %d" % [r.files.size(), source["files"].size()])
	return faults

func _bytes_less(a: PackedByteArray, b: PackedByteArray) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()

func test_base_world_packs_to_a_conforming_file(t) -> void:
	var doc := _doc()
	var r := OWWorldArchive.read_file(P.FIXTURES + "/pass-good.owworld")
	var packed := OWWorldArchive.pack_files(r.files, "abbey")
	t.ok(packed.ok, "packed")
	t.eq(packed.names[0], "mimetype", "the marker first")
	var faults := _writer_faults(packed.bytes, doc["source"], "abbey/")
	t.eq(faults, PackedStringArray(), "writer faults")
	var again := OWWorldArchive.pack_files(r.files, "abbey")
	t.eq(again.bytes, packed.bytes, "same input, same bytes (OW-12)")
	t.done()

func test_folder_on_disk_packs_the_parts_only(t) -> void:
	var doc := _doc()
	var root := _tmp("abbey")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	var r := OWWorldArchive.read_file(P.FIXTURES + "/pass-good.owworld")
	_write_tree(root, r.files)
	# what a folder in a repository carries that is not the world
	_write_tree(root, {"README.md": "# abbey".to_utf8_buffer(), ".git/HEAD": "ref".to_utf8_buffer(),
		".atlas/charts.json": "{}".to_utf8_buffer(), "elements/character/.DS_Store": PackedByteArray([0]),
		"elements/character/ana--0000ab01.json.meta": "fileFormatVersion: 2\nguid: 0123456789abcdef0123456789abcdef\n".to_utf8_buffer()})
	var packed := OWWorldArchive.pack_folder(root)
	t.ok(packed.ok, "packed (%s)" % packed.message)
	t.eq(_writer_faults(packed.bytes, doc["source"], "abbey/"), PackedStringArray(), "writer faults")
	t.ok("records/lab/ledger.bin.meta" in OWWorldArchive.read(packed.bytes).files, "a producer's own .meta travels")
	t.ok("records/lab/.cursor" in OWWorldArchive.read(packed.bytes).files, "a producer's dot-file travels")
	var out := _tmp("abbey.owworld")
	var written := OWWorldArchive.pack(root, out)
	t.ok(written.ok, "written to disk")
	t.eq(FileAccess.get_file_as_bytes(out), packed.bytes, "the file is the bytes")
	t.ok(not OWWorldArchive.pack(root, root + "/self.owworld").ok, "refuses to write inside the folder it packs")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

func test_private_records_left_out_unless_asked(t) -> void:
	var doc := _doc()
	var asked := OWWorldArchive.read_file(P.FIXTURES + "/pass-OW-8-private-asked.owworld")
	var left := OWWorldArchive.read_file(P.FIXTURES + "/pass-OW-8-private-left-out.owworld")
	var root := _tmp("abbey")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	_write_tree(root, asked.files)
	var by_default := OWWorldArchive.read(OWWorldArchive.pack_folder(root).bytes)
	t.eq(by_default.files, left.files, "the default side: records/fold/ out whole, RECORDS.json byte-exact")
	var when_asked := OWWorldArchive.read(OWWorldArchive.pack_folder(root, false, true).bytes)
	t.eq(when_asked.files, asked.files, "the asked side: records/fold/ whole")
	t.eq(_writer_faults(OWWorldArchive.pack_folder(root, false, true).bytes, doc["sources"]["private"], "abbey/"), PackedStringArray(), "writer faults, asked")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

func test_api_block_stripped_unless_kept(t) -> void:
	var r := OWWorldArchive.read_file(P.FIXTURES + "/pass-OW-10-api.owworld")
	var root := _tmp("abbey")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	_write_tree(root, {"world.json": r.held_world_json})
	var stripped := OWWorldArchive.read(OWWorldArchive.pack_folder(root).bytes)
	t.ok(not stripped.held_world_json.get_string_from_utf8().contains("\"api\""), "a portable file has no api block")
	var kept := OWWorldArchive.read(OWWorldArchive.pack_folder(root, true).bytes)
	t.eq(kept.held_world_json, r.held_world_json, "keep_api: world.json byte for byte")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

func _pack_real(t, root: String, label: String) -> void:
	var t0 := Time.get_ticks_msec()
	var packed := OWWorldArchive.pack_folder(root)
	var ms_pack := Time.get_ticks_msec() - t0
	t.ok(packed.ok, "%s packs (%s)" % [label, packed.message])
	t0 = Time.get_ticks_msec()
	var r := OWWorldArchive.read(packed.bytes)
	var ms_read := Time.get_ticks_msec() - t0
	t.ok(r.ok, "%s reads back (%s)" % [label, r.message])
	# By default the author fields are left out: a file the pack lists has lost them and is the same object otherwise;
	# every other file is the folder's bytes. A file that holds one and keeps it was not one the pack may rewrite
	# (OWWorldArchive.without_author_fields: a number Godot reads or writes otherwise, mostly).
	var left := {}
	for rel in packed.author_fields_left_out:
		left[rel] = true
	var same := 0
	var stripped := 0
	var holding := 0
	for rel: String in r.files:
		var src := FileAccess.get_file_as_bytes(root + "/" + rel)
		if not left.has(rel):
			if r.files[rel] == src:
				same += 1
			if rel.begins_with("elements/") or rel.begins_with("spatial/"):
				var ascii := src.get_string_from_ascii()
				for field: String in OWWorldArchive.AUTHOR_FIELDS:
					if ascii.contains("\"" + field + "\""):
						holding += 1
						break
			continue
		var was = JSON.parse_string(src.get_string_from_utf8())
		var now = JSON.parse_string((r.files[rel] as PackedByteArray).get_string_from_utf8())
		for field: String in OWWorldArchive.AUTHOR_FIELDS:
			was.erase(field)
		if now == was and r.files[rel] != src:
			stripped += 1
	t.eq(same + stripped, r.files.size(), "%s: every packed file is the folder's bytes, or its object without the author fields" % label)
	t.eq(stripped, packed.author_fields_left_out.size(), "%s: every file listed lost them" % label)
	print("       %s: %d files without their author fields, %d kept with them (a number Godot reads or writes otherwise)" % [label, stripped, holding])
	var copy := OWWorldArchive.pack_folder(root, false, false, true)
	t.ok(copy.author_fields_left_out.is_empty(), "%s: asked, nothing left out" % label)
	var back := OWWorldArchive.read(copy.bytes)
	var copied := 0
	for rel: String in back.files:
		if back.files[rel] == FileAccess.get_file_as_bytes(root + "/" + rel):
			copied += 1
	t.eq(copied, back.files.size(), "%s: asked, every packed file is the folder's bytes" % label)
	var w := r.to_world()
	t.eq(w.elements.size(), P.count_element_files(root), "%s: every element in the archive" % label)
	print("       %s: %d entries, %.1f MB, packed in %d ms, read back (every rule, every CRC) in %d ms" % [label, packed.names.size(), packed.bytes.size() / 1e6, ms_pack, ms_read])

func test_moppetopia_round_trip(t) -> void:
	if not FileAccess.file_exists(P.moppetopia() + "/world.json"):
		t.skip("no Moppetopia folder at OW_MOPPETOPIA ('%s')" % P.moppetopia())
		return
	_pack_real(t, P.moppetopia(), "Moppetopia")
	t.done()

func test_sikelia_round_trip(t) -> void:
	if not FileAccess.file_exists(P.sikelia() + "/world.json"):
		t.skip("no Sikelia folder at OW_SIKELIA ('%s')" % P.sikelia())
		return
	_pack_real(t, P.sikelia(), "Sikelia")
	t.done()

func test_zip64_from_65535_entries(t) -> void:
	var files := {"world.json": "{\n  \"id\": \"w\"\n}\n".to_utf8_buffer()}
	for i in 65534:
		files["media/%05d.txt" % i] = PackedByteArray([i & 0xFF])
	var packed := OWWorldArchive.pack_files(files, "big")
	var w := OWZip.walk(packed.bytes)
	t.ok(w.zip64, "the zip64 end record is written")
	t.eq(w.entries.size(), 65536, "every entry in the directory (the marker too)")
	var r := OWWorldArchive.read(packed.bytes)
	t.ok(r.ok, "reads (%s)" % r.message)
	t.eq(r.files.size(), 65535, "every file back")
	t.done()
