extends RefCounted
## An element file that is not UTF-8 (one Latin-1 byte in a string). The reader decodes it leniently, so the string it
## serves holds a replacement character where the byte was. No writer may put that character back over the person's
## byte: an unedited such file is written as its bytes, at every door; an edit to such an element (or to such a
## world.json) is refused, naming the file, before anything is written.

const P = preload("res://tests/paths.gd")

const WORLD_ID := "019a9200-0000-7000-8000-000000000001"
const C1 := "elements/character/one--000000c1.json"
const C2 := "elements/character/lat--000000c2.json"
const C2_ID := "019a9200-0000-7000-8000-0000000000c2"

static func _files() -> Dictionary:
	var c2 := ("{\n  \"id\": \"%s\",\n  \"name\": \"Lat\",\n  \"description\": \"caf" % C2_ID).to_utf8_buffer()
	c2.append(0xE9)                                   # é in Latin-1: not UTF-8
	c2.append_array("\"\n}\n".to_utf8_buffer())
	return {
		"world.json": ("{\n  \"id\": \"%s\",\n  \"name\": \"Lenient\"\n}\n" % WORLD_ID).to_utf8_buffer(),
		C1: "{\n  \"id\": \"019a9200-0000-7000-8000-0000000000c1\",\n  \"name\": \"One\"\n}\n".to_utf8_buffer(),
		C2: c2,
	}

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(files[rel])
		f.close()

## The bytes from "caf" to the end, as hex: the byte, or what was written over it.
static func _around(bytes: PackedByteArray) -> String:
	var at := bytes.get_string_from_ascii().find("caf")
	var hex := PackedStringArray()
	for i in range(maxi(at, 0), bytes.size()):
		hex.append("%02X" % bytes[i])
	return "%d bytes, %s" % [bytes.size(), " ".join(hex)]

static func _same(t, label: String, got: PackedByteArray, want: PackedByteArray) -> void:
	print("       %s: %s" % [label, _around(got)])
	t.eq(got, want, label + ": the file's own bytes")

func test_the_reader_reads_it_leniently(t) -> void:
	var w := OWWorld.from_files(_files())
	var c2 := w.get_element(C2_ID)
	t.ok(c2 != null, "read as an element")
	if c2 != null:
		var d: String = c2.get_value("description")
		print("       description read as: %s (code points %s)" % [d.c_escape(), str(Array(d.to_utf32_buffer().to_int32_array())).right(30)])
		t.ok(d.begins_with("caf") and d.length() == 4 and d.unicode_at(3) == 0xFFFD, "with U+FFFD where the byte was")
	t.done()

## (a) Nothing edited: every door that saves writes the file as it is.
func test_unedited_it_is_written_as_its_bytes_at_every_door(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/lenient")
	var out := ProjectSettings.globalize_path(P.TMP + "/lenient-out")
	var files := _files()
	_write_tree(root, files)
	print("       before: %s" % _around(files[C2]))
	var w := OWWorld.read_folder(root)
	var c2 := w.get_element(C2_ID)
	P.remove_tree(out)
	t.eq(w.write_folder(out), OK, "write_folder, whole")
	_same(t, "(a) write_folder whole", FileAccess.get_file_as_bytes(out + "/" + C2), files[C2])
	t.eq(w.write_folder(root, true), OK, "write_folder, only the edited")
	_same(t, "(a) write_folder edited-only, in place", FileAccess.get_file_as_bytes(root + "/" + C2), files[C2])
	_same(t, "(a) element_bytes", OWWorld.element_bytes(c2), files[C2])
	var packed := w.pack("lenient")
	t.ok(packed.ok, "pack")
	_same(t, "(a) pack", OWWorldArchive.read(packed.bytes).files.get(C2, PackedByteArray()), files[C2])
	var from_disk := OWWorldArchive.pack_folder(root)
	t.ok(from_disk.ok, "pack_folder")
	_same(t, "(a) pack_folder", OWWorldArchive.read(from_disk.bytes).files.get(C2, PackedByteArray()), files[C2])
	# The .owworld read back, then packed again untouched.
	var again := OWWorldArchive.read(packed.bytes).to_world().pack("lenient")
	_same(t, "(a) .owworld read, packed again", OWWorldArchive.read(again.bytes).files.get(C2, PackedByteArray()), files[C2])
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## (b) Another field of that element edited: refused by name, nothing written, at every door.
func test_an_edit_to_it_is_refused_by_name_and_nothing_is_written(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/lenient")
	var out := ProjectSettings.globalize_path(P.TMP + "/lenient-out")
	var files := _files()
	_write_tree(root, files)
	for source in ["folder", "owworld"]:
		var w := OWWorld.read_folder(root) if source == "folder" else \
			OWWorldArchive.read(OWWorldArchive.pack_folder(root).bytes).to_world()
		w.get_element(C2_ID).supertype = "Cook"
		print("       (b) %s, element_bytes of the edited element: %s" % [source, _around(OWWorld.element_bytes(w.get_element(C2_ID)))])
		var why := w.write_refusal(true)
		t.ok(why.contains(C2), "(b) %s: write_refusal names the file (%s)" % [source, why])
		P.remove_tree(out)
		t.eq(w.write_folder(out), ERR_INVALID_DATA, "(b) %s: write_folder whole refuses" % source)
		t.ok(not DirAccess.dir_exists_absolute(out), "(b) %s: nothing written elsewhere" % source)
		t.eq(w.write_folder(root, true), ERR_INVALID_DATA, "(b) %s: write_folder in place refuses" % source)
		_same(t, "(b) %s, the file in place after" % source, FileAccess.get_file_as_bytes(root + "/" + C2), files[C2])
		var packed := w.pack("lenient")
		t.ok(not packed.ok and packed.message.contains(C2), "(b) %s: pack refuses by name (%s)" % [source, packed.message])
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## A batch: one element edited that is fine and this one edited too: refused before the first write.
func test_a_batch_holding_such_an_edit_writes_nothing(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/lenient")
	var files := _files()
	_write_tree(root, files)
	var w := OWWorld.read_folder(root)
	w.get_element("019a9200-0000-7000-8000-0000000000c1").name = "One Edited"
	w.get_element(C2_ID).supertype = "Cook"
	t.eq(w.write_folder(root, true), ERR_INVALID_DATA, "refused")
	t.eq(FileAccess.get_file_as_bytes(root + "/" + C1), files[C1], "the other edited file not written either")
	t.eq(FileAccess.get_file_as_bytes(root + "/" + C2), files[C2], "this one unchanged")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## (c) A different element edited: that one is written, this one left as it is.
func test_an_edit_to_another_element_leaves_it_as_it_is(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/lenient")
	var out := ProjectSettings.globalize_path(P.TMP + "/lenient-out")
	var files := _files()
	_write_tree(root, files)
	var w := OWWorld.read_folder(root)
	var one := w.get_element("019a9200-0000-7000-8000-0000000000c1")
	one.name = "One Edited"
	t.eq(w.write_folder(root, true), OK, "(c) the edit written in place")
	t.ok(FileAccess.get_file_as_string(root + "/" + C1).contains("One Edited"), "(c) the other element's edit landed")
	_same(t, "(c) write_folder edited-only, in place", FileAccess.get_file_as_bytes(root + "/" + C2), files[C2])
	P.remove_tree(out)
	t.eq(w.write_folder(out), OK, "(c) the whole world written elsewhere")
	_same(t, "(c) write_folder whole", FileAccess.get_file_as_bytes(out + "/" + C2), files[C2])
	var packed := w.pack("lenient")
	t.ok(packed.ok, "(c) pack")
	_same(t, "(c) pack", OWWorldArchive.read(packed.bytes).files.get(C2, PackedByteArray()), files[C2])
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## world.json is read leniently too: unedited it is its bytes; edited, refused by name; and pack_folder, which rewrites
## it to strip an api block, refuses rather than write the replacement character.
func test_a_world_json_that_is_not_utf8(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/lenient")
	var out := ProjectSettings.globalize_path(P.TMP + "/lenient-out")
	var files := _files()
	var wj := ("{\n  \"id\": \"%s\",\n  \"name\": \"Lenient\",\n  \"description\": \"caf" % WORLD_ID).to_utf8_buffer()
	wj.append(0xE9)
	wj.append_array("\"\n}\n".to_utf8_buffer())
	files["world.json"] = wj
	_write_tree(root, files)
	var w := OWWorld.read_folder(root)
	t.eq(w.get_id(), WORLD_ID, "read, leniently")
	P.remove_tree(out)
	t.eq(w.write_folder(out), OK, "unedited: written")
	_same(t, "world.json unedited, write_folder", FileAccess.get_file_as_bytes(out + "/world.json"), wj)
	w.info.name = "Renamed"
	var why := w.write_refusal(true)
	t.ok(why.contains("world.json"), "edited: refused by name (%s)" % why)
	t.eq(w.write_folder(root, true), ERR_INVALID_DATA, "edited: write_folder refuses")
	_same(t, "world.json edited, in place after", FileAccess.get_file_as_bytes(root + "/world.json"), wj)

	var with_api := ("{\n  \"id\": \"%s\",\n  \"api\": {\"k\": 1},\n  \"description\": \"caf" % WORLD_ID).to_utf8_buffer()
	with_api.append(0xE9)
	with_api.append_array("\"\n}\n".to_utf8_buffer())
	files["world.json"] = with_api
	_write_tree(root, files)
	var p := OWWorldArchive.pack_folder(root)
	if p.ok:
		print("       pack_folder with an api block wrote world.json: %s" % _around(OWWorldArchive.read(p.bytes).held_world_json))
	t.ok(not p.ok and p.message.contains("world.json"), "pack_folder with an api block refuses by name (%s)" % p.message)
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()
