extends RefCounted
## A writer never writes over a file it could not read: a new element whose name lands on such a file takes the next
## name, the full id in place of its eight-character tail (folder spec §3.2's writer collision rule), and the unread
## file keeps its bytes. Two new elements whose names land on one path part the same way, the lower id (by code point)
## keeping the short form.

const P = preload("res://tests/paths.gd")

const WORLD := "{\n  \"id\": \"019a9200-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const SHORT := "elements/character/bo--0000000b.json"
const OLD_ID := "019a9200-0000-7000-8000-00000000000b"
const NEW_ID := "019a9300-0000-7000-8000-00000000000b"     # the same eight-character tail
const FULL := "elements/character/bo--019a9300-0000-7000-8000-00000000000b.json"

static func _unread() -> Array:
	return [["cut short", "{\n  \"id\": \"%s\",\n  \"name\": \"Bo\"" % OLD_ID],
		["a number too large", "{\n  \"id\": \"%s\",\n  \"name\": \"Bo\",\n  \"x_n\": 1e400\n}\n" % OLD_ID],
		["not an object", "[1, 2]\n"]]

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(String(files[rel]).to_utf8_buffer())
		f.close()

func test_a_new_element_never_takes_the_name_of_a_file_the_reader_could_not_read(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/unread-name")
	var out := ProjectSettings.globalize_path(P.TMP + "/unread-name-out")
	for u in _unread():
		var label: String = u[0]
		var cut: String = u[1]
		_write_tree(root, {"world.json": WORLD, SHORT: cut})
		var w := OWWorld.read_folder(root)
		t.eq(w.elements.size(), 0, label + ": not read as an element")
		var bo := OWCharacter.new({"id": NEW_ID, "name": "Bo"})
		w.add_element(bo)
		var files := w.to_files()
		t.eq(files.get(SHORT), cut.to_utf8_buffer(), label + ": to_files keeps the unread file's bytes at its path")
		t.ok(files.has(FULL), label + ": the new element takes the next name, the full id (%s)" % str(files.keys()))

		P.remove_tree(out)
		t.eq(w.write_folder(out), OK, label + ": write_folder whole")
		t.eq(FileAccess.get_file_as_string(out + "/" + SHORT), cut, label + ": whole: the unread file's bytes")
		t.ok(FileAccess.get_file_as_string(out + "/" + FULL).contains(NEW_ID), label + ": whole: the new element at the full name")

		t.eq(w.write_folder(root, true), OK, label + ": write_folder edited-only, in place")
		t.eq(FileAccess.get_file_as_string(root + "/" + SHORT), cut, label + ": in place: the unread file's bytes")
		t.ok(FileAccess.get_file_as_string(root + "/" + FULL).contains(NEW_ID), label + ": in place: the new element at the full name")

		var packed := w.pack("w")
		var back := OWWorldArchive.read(packed.bytes) if packed.ok else null
		t.ok(back != null and back.files.get(SHORT) == cut.to_utf8_buffer() and back.files.has(FULL), label + ": pack carries both")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## A read element's own file is its own: a new element never takes it either.
func test_a_new_element_never_takes_a_read_elements_name(t) -> void:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(),
		SHORT: ("{\n  \"id\": \"%s\",\n  \"name\": \"Bo\"\n}\n" % OLD_ID).to_utf8_buffer()})
	t.eq(w.elements.size(), 1, "the old Bo read")
	w.add_element(OWCharacter.new({"id": NEW_ID, "name": "Bo"}))
	var files := w.to_files()
	t.ok(files.get(SHORT, PackedByteArray()).get_string_from_utf8().contains(OLD_ID), "the old Bo keeps its file")
	t.ok(files.has(FULL), "the new Bo at the full name (%s)" % str(files.keys()))
	t.done()

## Both names held by files the reader could not read: refused by name, nothing written over.
func test_both_names_held_is_a_refusal(t) -> void:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), SHORT: "[1]".to_utf8_buffer(), FULL: "[2]".to_utf8_buffer()})
	w.add_element(OWCharacter.new({"id": NEW_ID, "name": "Bo"}))
	var why := w.write_refusal(true)
	t.ok(why.contains(SHORT) and why.contains(FULL), "the refusal names both (%s)" % why)
	t.ok(not w.pack("w").ok, "pack refuses")
	var out := ProjectSettings.globalize_path(P.TMP + "/unread-both")
	P.remove_tree(out)
	t.eq(w.write_folder(out), ERR_INVALID_DATA, "write_folder refuses")
	t.ok(not DirAccess.dir_exists_absolute(out), "nothing written")
	t.done()

## Two new elements, one name, one tail: the lower id keeps the short form, the other takes its full id, both written.
func test_two_new_elements_on_one_name_both_written(t) -> void:
	for order in [[OLD_ID, NEW_ID], [NEW_ID, OLD_ID]]:
		var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
		for id in order:
			w.add_element(OWCharacter.new({"id": id, "name": "Bo"}))
		var files := w.to_files()
		var label := "the lower id added first" if order[0] == OLD_ID else "the higher id added first"
		t.eq(files.size(), 3, "%s: world.json and two element files (%s)" % [label, str(files.keys())])
		t.ok(files.get(SHORT, PackedByteArray()).get_string_from_utf8().contains(OLD_ID), label + ": the lower id keeps the short name")
		t.ok(files.get(FULL, PackedByteArray()).get_string_from_utf8().contains(NEW_ID), label + ": the higher id takes its full id")
	t.done()
