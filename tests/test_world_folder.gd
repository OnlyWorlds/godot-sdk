extends RefCounted
## World folders into typed models, and back: an unedited world is its own bytes; an edited file is the spec's
## section 5 form (DECISIONS #2). Proven on Sikelia (about 20,570 element files) and Moppetopia.

const P = preload("res://tests/paths.gd")

var _number_line: RegEx

## A source line holding a number spelled N.0, rewritten as section 5 writes it (N): the one difference DECISIONS #2
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
		t.skip("no Sikelia at %s" % P.sikelia())
		return
	_check_world(t, P.sikelia(), "Sikelia", 20000)
	t.done()

func test_moppetopia(t) -> void:
	if not FileAccess.file_exists(P.moppetopia() + "/world.json"):
		t.skip("no Moppetopia at %s" % P.moppetopia())
		return
	_check_world(t, P.moppetopia(), "Moppetopia", 100)
	t.done()

func test_edit_writes_only_the_edited_file(t) -> void:
	if not FileAccess.file_exists(P.moppetopia() + "/world.json"):
		t.skip("no Moppetopia at %s" % P.moppetopia())
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
