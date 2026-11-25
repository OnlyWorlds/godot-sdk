extends RefCounted
## A file nested past 200, the text's top value at 1, objects and arrays both counted (the folder format's OW-25). Godot's
## parser reads deeper than that, so the reader draws the standard's line itself and refuses the file by name, with the
## word the TypeScript and Python packages use ([constant OWJson.TOO_DEEP]): an element file is skipped into
## [member OWWorld.errors] with its bytes kept in [member OWWorld.other_files], and a world.json nested that deep is no
## world. A file whose deepest object or array sits at 200 is read whole, a plain value inside it included.

const P = preload("res://tests/paths.gd")

const WORLD_ID := "019a9200-0000-7000-8000-000000000001"
const A := "elements/character/a--0000000a.json"
const B := "elements/character/b--0000000b.json"
const C := "elements/character/c--0000000c.json"

## A value whose deepest object or array sits at [param deepest] as a field of the file's top object (at 1): an array
## and an object in turn, a plain value inside the last, as the set's OW-25 cases nest.
static func _nest(deepest: int, arrays_only := false) -> String:
	var open := ""
	var close := ""
	for k in deepest - 1:
		var array := arrays_only or k % 2 == 0
		open += "[" if array else "{\"k\":"
		close = ("]" if array else "}") + close
	return open + "1" + close

static func _character(tail: String, name: String, extra := "") -> PackedByteArray:
	return ("{\n  \"id\": \"019a9200-0000-7000-8000-00000000000%s\",\n  \"name\": \"%s\"%s\n}\n" % [tail, name, extra]).to_utf8_buffer()

## A world of three Characters, the middle one holding [param deep] in an extension field.
static func _files(deep: String, world_deep := "") -> Dictionary:
	var world_extra := "" if world_deep == "" else ",\n  \"x_depth\": " + world_deep
	return {
		"world.json": ("{\n  \"id\": \"%s\",\n  \"name\": \"Deep\"%s\n}\n" % [WORLD_ID, world_extra]).to_utf8_buffer(),
		A: _character("a", "Ana"),
		B: _character("b", "Bo", ",\n  \"x_depth\": " + deep),
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

## The deepest bracket in a text with no bracket inside a string: a count no parser makes.
static func _deepest_in_text(text: String) -> int:
	var depth := 0
	var deepest := 0
	for ch in text:
		if ch == "{" or ch == "[":
			depth += 1
			deepest = maxi(deepest, depth)
		elif ch == "}" or ch == "]":
			depth -= 1
	return deepest

func test_the_fixture_nests_where_it_says(t) -> void:
	t.eq(_deepest_in_text(_character("b", "Bo", ",\"x\":" + _nest(200)).get_string_from_utf8()), 200, "200")
	t.eq(_deepest_in_text(_character("b", "Bo", ",\"x\":" + _nest(201)).get_string_from_utf8()), 201, "201")
	t.eq(_deepest_in_text(_nest(201).replace("[", "").replace("]", "")), 100, "half the nest is arrays")
	t.done()

func test_the_count_draws_the_line_at_200(t) -> void:
	for arrays_only in [false, true]:
		t.ok(not OWJson.opens_past(_character("b", "Bo", ",\"x\":" + _nest(200, arrays_only)).get_string_from_utf8()), "200 is not past (arrays only: %s)" % arrays_only)
		t.ok(OWJson.opens_past(_character("b", "Bo", ",\"x\":" + _nest(201, arrays_only)).get_string_from_utf8()), "201 is past (arrays only: %s)" % arrays_only)
	t.ok(not OWJson.opens_past("{\"s\": \"" + "[".repeat(300) + "\"}"), "brackets inside a string do not count")
	t.ok(not OWJson.opens_past("{\"s\": \"\\\"" + "[".repeat(300) + "\"}"), "nor after an escaped quote")
	t.ok(OWJson.opens_past("{\"x\": " + _nest(201) + ", \"x\": 1}"), "a key given twice: the deep value counts though a parser keeps the plain one")
	t.done()

func test_a_file_at_200_is_read_whole(t) -> void:
	var w := OWWorld.from_files(_files(_nest(200)))
	t.eq(_names(w), ["Ana", "Bo", "Cy"], "all three read")
	t.eq(w.errors.size(), 0, "no error (%s)" % str(w.errors))
	t.done()

func test_a_file_past_200_is_skipped_by_name_and_carried_whole(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/deep")
	var files := _files(_nest(201))
	_write_tree(root, files)
	var w := OWWorld.read_folder(root)
	t.eq(_names(w), ["Ana", "Cy"], "the folder: A and C read, B not")
	t.eq(w.errors.size(), 1, "one error (%s)" % str(w.errors))
	if w.errors.size() == 1:
		t.ok(w.errors[0].begins_with(B + ": too_deep"), "the error names the file and the word: " + w.errors[0])
	t.eq(w.other_files.get(B), files[B], "B's bytes kept, unchanged")

	var packed := w.pack("deep")
	t.ok(packed.ok, "the world packs")
	var back := OWWorldArchive.read(packed.bytes)
	t.ok(back.ok, "the pack reads back")
	t.eq(back.files.get(B), files[B], "the pack carries B unchanged")
	var bw: OWWorld = back.to_world()
	t.eq(_names(bw), ["Ana", "Cy"], "the .owworld: A and C read, B not")
	t.ok(bw.errors.size() == 1 and bw.errors[0].begins_with(B + ": too_deep"), "the .owworld names it: " + str(bw.errors))
	P.remove_tree(root)
	t.done()

func test_past_godots_own_line_is_the_same_refusal(t) -> void:
	var w := OWWorld.from_files(_files(_nest(5000)))
	t.eq(_names(w), ["Ana", "Cy"], "A and C read, B not")
	t.ok(w.errors.size() == 1 and w.errors[0].begins_with(B + ": too_deep"), "named too_deep, not 'not JSON': " + str(w.errors))
	t.done()

func test_a_share_leaves_it_out_as_unread(t) -> void:
	var files := _files(_nest(201))
	var left := OWWorldArchive.leave_out_for_share(files)
	t.eq(left["unread"], PackedStringArray([B]), "the share names B unread")
	t.done()

func test_a_world_json_past_200_is_no_world(t) -> void:
	var root := ProjectSettings.globalize_path(P.TMP + "/deep-world")
	_write_tree(root, _files(_nest(5), _nest(201)))
	var packed = OWWorldArchive.pack_folder(root)
	t.ok(not packed.ok, "refused")
	t.ok(str(packed.message).contains("too_deep"), "by the word: " + str(packed.message))
	P.remove_tree(root)
	t.done()
