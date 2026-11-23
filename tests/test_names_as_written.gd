extends RefCounted
## Three names a reader takes as written (the folder format and the address profile): an element file's extension is ".json" in
## lower case, so "X.JSON" is not an element file; a type folder's name is one of the 22 type words in lower case, so
## "elements/Character/" (or "elements/vessel/") is no type folder; and an id is compared as written, never as a UUID,
## so one UUID in capitals in one file and in lower case in another is two elements. The first two are skipped with a
## reason in [member OWWorld.errors] and kept as bytes in [member OWWorld.other_files], so a write or a pack carries them
## and a new element never takes their name. Each holds for a world folder and for an .owworld's files.

const P = preload("res://tests/paths.gd")

const WORLD := "{\n  \"id\": \"019a9400-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const ID_A := "019a9400-0000-7000-8000-00000000000a"
const ID_B := "019a9400-0000-7000-8000-00000000000b"
const ID_BO := "019a9300-0000-7000-8000-00000000000b"          # a new Character "Bo": short name bo--0000000b.json

static func _body(id: String, name := "A") -> String:
	return "{\n  \"id\": \"%s\",\n  \"name\": \"%s\"\n}\n" % [id, name]

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(String(files[rel]).to_utf8_buffer())
		f.close()

static func _as_bytes(files: Dictionary) -> Dictionary:
	var out := {}
	for rel: String in files:
		out[rel] = String(files[rel]).to_utf8_buffer()
	return out

## The three ways in: a world folder on disk, OWWorld.from_files, and an .owworld packed and read back.
static func _worlds(tag: String, files: Dictionary) -> Array:
	var root := ProjectSettings.globalize_path(P.TMP + "/names-" + tag)
	_write_tree(root, files)
	var packed := OWWorldArchive.pack_files(_as_bytes(files), "w")
	var r := OWWorldArchive.read(packed.bytes)
	return [["folder", OWWorld.read_folder(root)], ["files", OWWorld.from_files(_as_bytes(files))],
		["archive", r.to_world() if r.ok else null]]

static func _error_for(w: OWWorld, rel: String) -> String:
	for line in w.errors:
		if line.begins_with(rel + ": "):
			return line
	return ""

## A path in [param files] that [param rel] would write over on a disk that ignores case.
static func _met_case_blind(files: Dictionary, rel: String) -> String:
	for other: String in files:
		if other != rel and other.to_lower() == rel.to_lower():
			return other
	return ""

## Ruling 1: ".JSON" and ".Json" are not ".json". On a case-blind disk the file system's own match would take them;
## the reader compares the name as written.
func test_an_extension_in_another_spelling_is_skipped_with_a_reason(t) -> void:
	var files := {"world.json": WORLD,
		"elements/character/a.json": _body(ID_A),
		"elements/character/UPPER.JSON": _body(ID_B, "Upper"),
		"elements/location/mixed.Json": _body("019a9400-0000-7000-8000-00000000000c", "Mixed")}
	for pair in _worlds("ext", files):
		var how: String = pair[0]
		var w: OWWorld = pair[1]
		if w == null:
			t.fail(how + ": the world did not read")
			continue
		t.eq(w.elements.size(), 1, how + ": only a.json is an element")
		t.ok(w.get_element(ID_B) == null, how + ": UPPER.JSON is not served")
		for rel in ["elements/character/UPPER.JSON", "elements/location/mixed.Json"]:
			var line := _error_for(w, rel)
			t.ok(line.contains(".json"), "%s: %s skipped with a reason (%s)" % [how, rel, str(w.errors)])
			t.eq(w.other_files.get(rel), String(files[rel]).to_utf8_buffer(), "%s: %s kept as its bytes" % [how, rel])
		t.ok(w.to_files().has("elements/character/UPPER.JSON"), how + ": a whole write or pack carries it")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## A new element never takes the name of a skipped ".JSON" file, which a case-blind disk would write over.
func test_a_new_element_never_lands_on_a_skipped_upper_case_file(t) -> void:
	var upper := "elements/character/BO--0000000B.JSON"
	for pair in _worlds("ext-new", {"world.json": WORLD, upper: _body(ID_B, "Old Bo")}):
		var how: String = pair[0]
		var w: OWWorld = pair[1]
		w.add_element(OWCharacter.new({"id": ID_BO, "name": "Bo"}))
		var files := w.to_files()
		var fresh := ""
		for rel: String in files:
			if files[rel].get_string_from_utf8().contains(ID_BO):
				fresh = rel
		t.ok(fresh != "", how + ": the new element is written (%s)" % str(files.keys()))
		var around := files.duplicate()
		around[upper] = true            # the folder it was read from holds the file, whether to_files carries it or not
		t.eq(_met_case_blind(around, fresh), "", "%s: the new element's %s meets no other file case-blind" % [how, fresh])
		t.eq(files.get(upper), _body(ID_B, "Old Bo").to_utf8_buffer(), how + ": the skipped file keeps its bytes")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## Ruling 2: a folder under elements/ or spatial/ whose name is not one of the 22 type words in lower case is no type
## folder, an upper-case type word among them; its files are not read.
func test_a_folder_that_is_no_type_word_is_not_read(t) -> void:
	var files := {"world.json": WORLD,
		"elements/location/a.json": _body(ID_A),
		"elements/Character/b.json": _body(ID_B, "B"),
		"elements/vessel/v.json": _body("019a9400-0000-7000-8000-00000000000d", "V"),
		"spatial/Pin/p.json": _body("019a9400-0000-7000-8000-00000000000e", "P")}
	for pair in _worlds("type", files):
		var how: String = pair[0]
		var w: OWWorld = pair[1]
		if w == null:
			t.fail(how + ": the world did not read")
			continue
		t.eq(w.elements.size(), 1, how + ": only location/a.json is an element (%s)" % str(w.elements.map(func(e): return e.source_path)))
		t.ok(w.get_element(ID_B) == null, how + ": elements/Character/b.json is not served")
		for rel in ["elements/Character/b.json", "elements/vessel/v.json", "spatial/Pin/p.json"]:
			var line := _error_for(w, rel)
			t.ok(line.contains("type folder"), "%s: %s skipped with a reason (%s)" % [how, rel, str(w.errors)])
			t.eq(w.other_files.get(rel), String(files[rel]).to_utf8_buffer(), "%s: %s kept as its bytes" % [how, rel])
		t.ok(w.to_files().has("elements/Character/b.json"), how + ": a whole write or pack carries it")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## A new element never takes the name of a file in an upper-case folder, which a case-blind disk would write over.
func test_a_new_element_never_lands_on_a_file_in_an_upper_case_folder(t) -> void:
	var held := "elements/Character/bo--0000000b.json"
	for pair in _worlds("type-new", {"world.json": WORLD, held: _body(ID_B, "Old Bo")}):
		var how: String = pair[0]
		var w: OWWorld = pair[1]
		w.add_element(OWCharacter.new({"id": ID_BO, "name": "Bo"}))
		var files := w.to_files()
		var fresh := ""
		for rel: String in files:
			if files[rel].get_string_from_utf8().contains(ID_BO):
				fresh = rel
		t.ok(fresh != "", how + ": the new element is written (%s)" % str(files.keys()))
		var around := files.duplicate()
		around[held] = true
		t.eq(_met_case_blind(around, fresh), "", "%s: the new element's %s meets no other file case-blind" % [how, fresh])
		t.eq(files.get(held), _body(ID_B, "Old Bo").to_utf8_buffer(), how + ": the unread file keeps its bytes")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

## Ruling 3: an id is compared as written. One UUID in capitals, in lower case, in braces and without its hyphens is
## four ids: four elements, each found by its own spelling only, and no duplicate reported.
func test_an_id_is_compared_as_written_never_as_a_uuid(t) -> void:
	var spellings := [ID_A, ID_A.to_upper(), "{" + ID_A + "}", ID_A.replace("-", "")]
	var files := {"world.json": WORLD}
	for i in spellings.size():
		files["elements/character/c%d.json" % i] = _body(spellings[i], "C%d" % i)
	for pair in _worlds("ids", files):
		var how: String = pair[0]
		var w: OWWorld = pair[1]
		if w == null:
			t.fail(how + ": the world did not read")
			continue
		t.eq(w.elements.size(), 4, how + ": four elements")
		t.eq(w.errors, PackedStringArray(), how + ": no duplicate reported")
		for i in spellings.size():
			var e := w.get_element(spellings[i])
			t.ok(e != null and e.source_path == "elements/character/c%d.json" % i,
				"%s: %s is c%d.json's element" % [how, spellings[i], i])
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()
