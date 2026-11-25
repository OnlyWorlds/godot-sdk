extends RefCounted
## A declared type (the folder format's section 4.1, ruled 2026-11-22): a String exactly equal to one of the 22 type
## slugs as the standard spells them; anything else in "type" (an unknown word, another case such as "Location", a
## number, null) declares nothing, and the directory fills it. A file whose body declares one of the 22 and sits in
## another type's directory is read as the body says, in that type's own class.
##
## The cases (tests/data/declared-type.cases.json) are the same bytes as the Python package's
## tests/fixtures/declared-type.cases.json and the TypeScript SDK's test/fixtures/declared-type.cases.json, held by
## their sha256. The folder on disk and the same files in memory (OWWorld.from_files, which a world file reads through)
## are each asked every case.

const P = preload("res://tests/paths.gd")

const CASES := "res://tests/data/declared-type.cases.json"
const CASES_SHA256 := "89968d85deaa4d5974a20a4d73aab80c7e8ec374ee4236b0809e00c405831b96"
const WORLD := "{\"id\": \"w\", \"name\": \"W\"}"

static func _cases() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(CASES))["cases"]

static func _root(tag: String) -> String:
	return ProjectSettings.globalize_path(P.TMP + "/declared-" + tag)

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(String(files[rel]).to_utf8_buffer())
		f.close()

## What the world serves for x1: [type, class matches the type's own], or ["<none>", false].
static func _served(w: OWWorld) -> Array:
	if w == null:
		return ["<no world>", false]
	var e := w.get_element("x1")
	if e == null:
		return ["<none>", false]
	var type := String(e.get_type())
	return [type, OWTypes.SCRIPTS.get(type) == e.get_script()]

func test_the_cases_file_is_the_pinned_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(CASES), CASES_SHA256, "the cases' bytes are the TypeScript SDK's and the Python package's")
	t.eq(_cases().size(), 21, "21 cases")
	t.done()

func test_every_case_the_folder_on_disk_serves_the_type_the_case_wants(t) -> void:
	var off := []
	var n := 0
	for c: Dictionary in _cases():
		var root := _root("case-%02d" % n)
		n += 1
		_write_tree(root, {"world.json": WORLD, c["path"]: c["text"]})
		var got := _served(OWWorld.read_folder(root))
		if got[0] != c["want"] or not got[1]:
			off.append("%s: served %s (its class the type's own: %s), want %s" % [c["name"], got[0], got[1], c["want"]])
		P.remove_tree(root)
	t.eq(off, [], "every case")
	t.done()

func test_every_case_the_same_files_in_memory_serve_the_type_the_case_wants(t) -> void:
	var off := []
	for c: Dictionary in _cases():
		var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), c["path"]: String(c["text"]).to_utf8_buffer()})
		var got := _served(w)
		if got[0] != c["want"] or not got[1]:
			off.append("%s: served %s (its class the type's own: %s), want %s" % [c["name"], got[0], got[1], c["want"]])
	t.eq(off, [], "every case")
	t.done()

func test_the_body_stays_as_written(t) -> void:
	var by_name := {}
	for c: Dictionary in _cases():
		by_name[c["name"]] = c
	var c: Dictionary = by_name["another type, capital first"]
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), c["path"]: String(c["text"]).to_utf8_buffer()})
	t.eq(w.get_element("x1").get_value("type"), "Location", "the body keeps what it says")
	t.ok(w.get_element("x1") is OWCharacter, "and the element is the directory's Character")
	c = by_name["another type's slug"]
	w = OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), c["path"]: String(c["text"]).to_utf8_buffer()})
	t.ok(w.get_element("x1") is OWLocation, "a Location in elements/character/ is an OWLocation")
	t.eq(w.get_element("x1").source_path, c["path"], "and keeps the file it was read from")
	t.eq(w.of_type("location").size(), 1, "of_type finds it by its type")
	t.eq(w.of_type("character").size(), 0, "and not by its folder")
	t.done()
