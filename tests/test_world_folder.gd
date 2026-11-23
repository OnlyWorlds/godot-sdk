extends RefCounted
## World folders into typed models, and back: an unedited world is its own bytes; an edited file is the spec's
## section 5 form. Proven on two real worlds when their folders are given (OW_SIKELIA, about 20,570 element files;
## OW_MOPPETOPIA); the vendored example world's byte-for-byte rewrite is test_json.gd's.

const P = preload("res://tests/paths.gd")

var _number_line: RegEx

## A source line holding a number spelled N.0, rewritten as section 5 writes it (N): the one difference the writing rule
## allows between an element file and its edited form.
func _normalised(text: String) -> String:
	if _number_line == null:
		_number_line = RegEx.create_from_string("^(\\s*(?:\"(?:[^\"\\\\]|\\\\.)*\": )?-?\\d+)\\.0(,?)$")
	var lines := text.split("\n")
	for i in lines.size():
		var m := _number_line.search(lines[i])
		if m != null:
			lines[i] = m.get_string(1) + m.get_string(2)
	return "\n".join(lines)

func _check_world(t, root: String, label: String, expect_min: int) -> void:
	var expected := P.count_element_files(root)
	var t0 := Time.get_ticks_msec()
	var w := OWWorld.read_folder(root)
	var ms := Time.get_ticks_msec() - t0
	t.ok(w != null, "%s reads" % label)
	if w == null:
		return
	print("       %s: %d element files on disk, %d read as typed models in %d ms, %d errors" % [label, expected, w.elements.size(), ms, w.errors.size()])
	t.ok(expected >= expect_min, "%s has its element files (%d)" % [label, expected])
	t.eq(w.elements.size(), expected, "%s: every element file read" % label)
	t.eq(w.errors.size(), 0, "%s: read errors %s" % [label, str(w.errors.slice(0, 3))])
	var typed := 0
	for e in w.elements:
		if e.get_script() != OWElement:
			typed += 1
	t.eq(typed, w.elements.size(), "%s: every element in its type's class" % label)
	t.eq(w.get_id(), (JSON.parse_string(FileAccess.get_file_as_string(root + "/world.json")) as Dictionary)["id"], "%s: world id" % label)

	# Unedited: every file written back is the file read.
	var files := w.to_files()
	var same := 0
	for rel in files:
		if files[rel] == FileAccess.get_file_as_bytes(root + "/" + rel):
			same += 1
	t.eq(same, expected + 1, "%s: unedited rewrite byte-equal (elements and world.json)" % label)
	t.eq(w.to_files(true).size(), 0, "%s: nothing to write when nothing was edited" % label)

	# Edited: every element in section 5 form.
	t0 = Time.get_ticks_msec()
	var equal := 0
	var only_numbers := 0
	var other := 0
	for e in w.elements:
		var out := OWJson.to_bytes(e.to_dict())
		if out == e.source_bytes:
			equal += 1
			continue
		var src := e.source_bytes.get_string_from_utf8()
		if out.get_string_from_utf8() == _normalised(src) and JSON.parse_string(src) == JSON.parse_string(out.get_string_from_utf8()):
			only_numbers += 1
		else:
			other += 1
			if other <= 3:
				t.fail("%s: the section 5 form differs by more than N.0 -> N: %s" % [label, e.source_path])
	print("       %s edited form: %d byte-equal, %d differ only by N.0 -> N, %d otherwise, in %d ms" % [label, equal, only_numbers, other, Time.get_ticks_msec() - t0])
	t.eq(other, 0, "%s: files whose section 5 form differs by anything else" % label)

func test_sikelia(t) -> void:
	if not FileAccess.file_exists(P.sikelia() + "/world.json"):
		t.skip("no Sikelia folder at OW_SIKELIA ('%s')" % P.sikelia())
		return
	_check_world(t, P.sikelia(), "Sikelia", 20000)
	t.done()

func test_moppetopia(t) -> void:
	if not FileAccess.file_exists(P.moppetopia() + "/world.json"):
		t.skip("no Moppetopia folder at OW_MOPPETOPIA ('%s')" % P.moppetopia())
		return
	_check_world(t, P.moppetopia(), "Moppetopia", 100)
	t.done()

func test_edit_writes_only_the_edited_file(t) -> void:
	if not FileAccess.file_exists(P.moppetopia() + "/world.json"):
		t.skip("no Moppetopia folder at OW_MOPPETOPIA ('%s')" % P.moppetopia())
		return
	var w := OWWorld.read_folder(P.moppetopia())
	var pin: OWPin = w.of_type("pin")[0]
	pin.x = pin.x + 1
	var changed := w.to_files(true)
	t.eq(changed.keys(), [pin.source_path], "one file to write")
	var text: String = changed[pin.source_path].get_string_from_utf8()
	t.ok(text.contains("\"x\": %d," % pin.x), "the new x, as an integer")
	t.ok(text.ends_with("}\n") and not text.contains("\r"), "LF and one trailing newline")
	# write it somewhere else and read it back
	var out := P.TMP + "/edit"
	P.remove_tree(ProjectSettings.globalize_path(out))
	t.eq(w.write_folder(ProjectSettings.globalize_path(out), true), OK, "written")
	var again := OWWorld.read_folder(ProjectSettings.globalize_path(out)) if FileAccess.file_exists(ProjectSettings.globalize_path(out) + "/world.json") else null
	t.eq(again, null, "only the edited file went out (no world.json)")
	var back := OWPin.new(JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(out) + "/" + pin.source_path)))
	t.eq(back.x, pin.x, "read back")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

# -- No id, no write (folder format §4.1; §3.4, v0.3.22: a draft world conforms as any other, and a writer mints no id) --

## A world in memory with no world.json id: write_folder writes nothing and says why, pack refuses; set the id and both go.
func test_a_world_json_with_no_id_is_refused_and_nothing_is_written(t) -> void:
	var out := ProjectSettings.globalize_path(P.TMP + "/draft-no-id")
	for given in [{}, {"world.json": "{\"name\": \"Draft\"}".to_utf8_buffer()},
			{"world.json": "{\"id\": \"\", \"name\": \"Draft\"}".to_utf8_buffer()},
			{"world.json": "{\"id\": 7, \"name\": \"Draft\"}".to_utf8_buffer()}]:
		var w := OWWorld.from_files(given)
		var label := "world.json %s" % (given.get("world.json", PackedByteArray()).get_string_from_utf8())
		P.remove_tree(out)
		t.ok(w.write_refusal() != "", label + ": a refusal")
		t.eq(w.write_folder(out), ERR_INVALID_DATA, label + ": write_folder refuses")
		t.ok(not DirAccess.dir_exists_absolute(out), label + ": nothing written")
		t.ok(not w.pack("draft").ok, label + ": pack refuses")
	var draft := OWWorld.from_files({})
	draft.info.id = "019a9200-0000-7000-8000-000000000001"
	draft.info.name = "Draft"
	t.eq(draft.write_refusal(), "", "with the tool's own id, no refusal")
	t.eq(draft.write_folder(out), OK, "a draft with its id is written")
	t.ok(FileAccess.file_exists(out + "/world.json"), "its world.json")
	t.ok(draft.pack("draft").ok, "and packs")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## A new element with no id: the writer mints none, so write_folder and pack refuse the whole world; given an id, it goes.
func test_a_new_element_with_no_id_is_refused_and_nothing_is_written(t) -> void:
	var out := ProjectSettings.globalize_path(P.TMP + "/element-no-id")
	P.remove_tree(out)
	var w := OWWorld.from_files({"world.json": "{\"id\": \"w1\", \"name\": \"Draft\"}".to_utf8_buffer()})
	var loc := OWLocation.new({"name": "Harbour"})
	w.add_element(loc)
	t.ok(w.write_refusal() != "", "a refusal")
	t.eq(w.write_folder(out), ERR_INVALID_DATA, "write_folder refuses")
	t.ok(not DirAccess.dir_exists_absolute(out), "nothing written")
	t.ok(not w.pack("draft").ok, "pack refuses")
	t.eq(w.write_folder(out, true), ERR_INVALID_DATA, "an edited-only write refuses too")
	loc.id = "019a9200-0000-7000-8000-0000000e0001"
	t.eq(w.write_refusal(), "", "with an id, no refusal")
	t.eq(w.write_folder(out), OK, "written")
	t.ok(FileAccess.file_exists(out + "/elements/location/harbour--000e0001.json"), "its file")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()
