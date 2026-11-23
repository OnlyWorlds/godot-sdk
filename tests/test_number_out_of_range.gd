extends RefCounted
## A number a double cannot hold (4,301 digits, 1e400, -1e400). Godot's parser reads one as an infinity, and the
## section 5 writer has no form for an infinity, so a value read that way could only be served wrong or written back
## as null. The reader refuses the file instead, by name, with the word the TypeScript and Python packages use
## ([constant OWJson.NUMBER_OUT_OF_RANGE]): an element file is skipped into [member OWWorld.errors] with its bytes kept in
## [member OWWorld.other_files] (so every writer carries it whole), a world.json holding one is no world, and an answer
## from the API holding one is an unreadable answer.

const P = preload("res://tests/paths.gd")
const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"

const WORLD_ID := "019a9200-0000-7000-8000-000000000001"
const A := "elements/character/a--0000000a.json"
const B := "elements/character/b--0000000b.json"
const C := "elements/character/c--0000000c.json"

## The numbers no double holds: a 4,301-digit integer, past the largest double by exponent, and its negative.
static func _too_large() -> Array:
	return ["9".repeat(4301), "1e400", "-1e400"]

static func _character(tail: String, name: String, extra := "") -> PackedByteArray:
	return ("{\n  \"id\": \"019a9200-0000-7000-8000-00000000000%s\",\n  \"name\": \"%s\"%s\n}\n" % [tail, name, extra]).to_utf8_buffer()

## A world of three Characters, the middle one holding [param number] in an extension field.
static func _files(number: String) -> Dictionary:
	return {
		"world.json": ("{\n  \"id\": \"%s\",\n  \"name\": \"Numbers\"\n}\n" % WORLD_ID).to_utf8_buffer(),
		A: _character("a", "Ana"),
		B: _character("b", "Bo", ",\n  \"x_n\": " + number),
		C: _character("c", "Cy"),
	}

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(files[rel])
		f.close()

static func _names(w: OWWorld) -> Array:
	return w.elements.map(func(e): return e.name)

## The world read, held to the rule: B skipped by name, A and C read, B's bytes kept.
static func _skips_b(t, w: OWWorld, bytes: PackedByteArray, label: String) -> void:
	t.eq(_names(w), ["Ana", "Cy"], label + ": A and C read, B not")
	t.eq(w.errors.size(), 1, label + ": one error (%s)" % str(w.errors))
	if w.errors.size() == 1:
		t.ok(w.errors[0].begins_with(B + ": number_out_of_range"), label + ": the error names the file and the word: " + w.errors[0])
	t.eq(w.other_files.get(B), bytes, label + ": B's bytes kept, unchanged")

func test_an_element_holding_a_number_too_large_is_skipped_by_name_and_carried_whole(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/numbers")
	var out := ProjectSettings.globalize_path(P.TMP + "/numbers-out")
	for number: String in _too_large():
		var files := _files(number)
		var label := "%s (%d chars)" % [number.left(12), number.length()]
		_write_tree(root, files)

		var w := OWWorld.read_folder(root)
		_skips_b(t, w, files[B], label + ", the folder")

		# A pack of the world read carries B's bytes; the archive read back skips B the same way.
		var packed := w.pack("numbers")
		t.ok(packed.ok, label + ": the world packs")
		var back := OWWorldArchive.read(packed.bytes)
		t.ok(back.ok, label + ": the pack reads back")
		t.eq(back.files.get(B), files[B], label + ": the pack carries B unchanged")
		_skips_b(t, back.to_world(), files[B], label + ", the .owworld")

		# The folder packed straight from disk carries it too.
		var from_disk := OWWorldArchive.pack_folder(root)
		t.ok(from_disk.ok and OWWorldArchive.read(from_disk.bytes).files.get(B) == files[B], label + ": pack_folder carries B unchanged")

		# A edited: the whole world written elsewhere carries B as read; written back in place, B is not touched.
		w.elements[0].name = "Ana Edited"
		P.remove_tree(out)
		t.eq(w.write_folder(out), OK, label + ": the edited world writes")
		t.eq(FileAccess.get_file_as_bytes(out + "/" + B), files[B], label + ": B written as read, beside the edit")
		t.ok(FileAccess.get_file_as_string(out + "/" + A).contains("Ana Edited"), label + ": A's edit written")
		t.eq(w.write_folder(root, true), OK, label + ": the edit written back in place")
		t.eq(FileAccess.get_file_as_bytes(root + "/" + B), files[B], label + ": B on disk unchanged")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## The line is the double's: a 308-digit integer is a large double, read as one; only the infinities are refused.
func test_a_308_digit_integer_still_reads(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/numbers-308")
	var files := _files("9".repeat(308))
	_write_tree(root, files)
	var w := OWWorld.read_folder(root)
	t.eq(_names(w), ["Ana", "Bo", "Cy"], "all three read")
	t.eq(w.errors.size(), 0, "no error (%s)" % str(w.errors))
	var bo := w.get_element("019a9200-0000-7000-8000-00000000000b")
	var n = bo.get_value("x_n") if bo != null else null
	t.ok(n is float and not is_inf(n) and n > 9.9e307, "read as the double nearest it (%s)" % str(n))
	t.eq(w.to_files()[B], files[B], "written back unedited as its bytes")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## Nested anywhere: inside a list, inside an object inside a list.
func test_a_number_too_large_deep_in_the_file_is_found(t) -> void:
	for extra in [",\n  \"x_l\": [1, 2, 1e400]", ",\n  \"x_o\": [{\"k\": [-1e400]}]"]:
		var w := OWWorld.from_files({"world.json": _files("1")["world.json"], A: _character("a", "Ana"), B: _character("b", "Bo", extra)})
		t.eq(_names(w), ["Ana"], "%s: B skipped" % extra.strip_edges())
		t.ok(w.errors.size() == 1 and w.errors[0].begins_with(B + ": number_out_of_range"), "%s: by name (%s)" % [extra.strip_edges(), str(w.errors)])
	t.done()

func test_a_world_json_holding_a_number_too_large_is_no_world(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/numbers-world")
	for number: String in _too_large():
		var label := number.left(12)
		var files := _files("1")
		files["world.json"] = ("{\n  \"id\": \"%s\",\n  \"name\": \"Numbers\",\n  \"x_n\": %s\n}\n" % [WORLD_ID, number]).to_utf8_buffer()
		_write_tree(root, files)

		var w := OWWorld.read_folder(root)
		t.ok(w.errors.size() >= 1 and w.errors[0].begins_with("world.json: number_out_of_range"), label + ": the folder says why (%s)" % str(w.errors))
		t.eq(w.get_id(), "", label + ": no world id served")
		t.ok(w.write_refusal() != "", label + ": and no world written")

		var zipped := OWWorldArchive.pack_files(files, "numbers")
		var r := OWWorldArchive.read(zipped.bytes)
		t.ok(not r.ok and r.reason == "not_a_world" and r.message.contains("number_out_of_range"),
			label + ": the .owworld is no world, by the word (%s: %s)" % [r.reason, r.message])

		var p := OWWorldArchive.pack_folder(root)
		t.ok(not p.ok and p.message.contains("number_out_of_range"), label + ": pack_folder refuses, by the word (%s)" % p.message)

		# With an api block to strip, pack_folder would rewrite world.json: refused before, never written as null.
		files["world.json"] = ("{\n  \"id\": \"%s\",\n  \"api\": {\"k\": 1},\n  \"x_n\": %s\n}\n" % [WORLD_ID, number]).to_utf8_buffer()
		_write_tree(root, files)
		p = OWWorldArchive.pack_folder(root)
		t.ok(not p.ok and p.message.contains("number_out_of_range"), label + ": with an api block too (%s)" % p.message)
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

func test_an_answer_holding_a_number_too_large_is_an_unreadable_answer(t) -> void:
	for number: String in _too_large():
		var label := number.left(12)
		var fake = Fake.new()
		fake.body = "{\"id\":\"c1\",\"name\":\"Bo\",\"element_type\":\"character\",\"x_n\":%s}" % number
		var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})
		var r: OWClient.Reply = await c.get_element("character", "c1")
		t.ok(r.error != null and r.error.kind == OWApiError.ANSWER and r.error.message.contains("number_out_of_range"),
			label + ": get is an unreadable answer, by the word (%s)" % [r.error.message if r.error != null else "no error"])
		fake.body = "{\"data\":[{\"id\":\"c1\",\"name\":\"Bo\",\"x_n\":%s}],\"has_more\":false,\"next_cursor\":null}" % number
		r = await c.list("character")
		t.ok(r.error != null and r.error.kind == OWApiError.ANSWER and r.error.message.contains("number_out_of_range"),
			label + ": list too (%s)" % [r.error.message if r.error != null else "no error"])
		var j = Fake.new()
		j.body = "{\"kind\":\"player\",\"key\":\"ow_r_guest\",\"world\":{\"id\":\"w1\",\"name\":\"W\",\"x_n\":%s}}" % number
		r = await OWJoin.redeem("ow_j_EoEUrAfQ9xumy-lbBJqXix3q1xl49-P4", {"transport": j, "base_url": BASE})
		t.ok(r.error != null and r.error.kind == OWApiError.ANSWER and r.error.message.contains("number_out_of_range"),
			label + ": a join's answer too (%s)" % [r.error.message if r.error != null else "no error"])
	t.done()
