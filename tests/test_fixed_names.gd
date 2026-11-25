extends RefCounted
## The three fixed names, world.json, elements/ and spatial/, are read as written at every door (the folder format's
## section 4.8, ruled 2026-11-25): a folder or a world file that holds one of them in another case, and not the name
## itself, is refused with the cause name_case, never read as an empty world. The folder reader, OWWorld.from_files,
## the archive reader, the pack and the writer ask the same question of one listing, compared by OW-18's fold.
##
## On Windows and macOS the file system folds a name's case, so a reader that asks it for "elements" is served
## "Elements/"; on ext4 it is served nothing. These tests build the folder on disk and pass on both; the line the run
## prints says which this disk is.

const P = preload("res://tests/paths.gd")

const WORLD := "{\n  \"id\": \"019a9400-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const ID_A := "019a9400-0000-7000-8000-00000000000a"
const ID_B := "019a9400-0000-7000-8000-00000000000b"

static func _body(id: String, name := "A") -> String:
	return "{\n  \"id\": \"%s\",\n  \"name\": \"%s\"\n}\n" % [id, name]

static func _root(tag: String) -> String:
	return ProjectSettings.globalize_path(P.TMP + "/fixed-" + tag)

static func _write_tree(root: String, files: Dictionary) -> void:
	P.remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
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

static func _cleanup() -> void:
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))

## Whether this disk serves Elements/ to a lookup of elements, said in the run's output.
static func _say_the_disk(root: String) -> void:
	if DirAccess.dir_exists_absolute(root + "/elements"):
		print("       this disk folds case: the lookup of elements finds Elements/, so the refusal is the listing's")
	else:
		print("       this disk keeps case: the lookup of elements finds nothing, so the refusal is the listing's")

## Every file name under a folder, relative to it, by a walk of its own.
static func _files_under(root: String, rel := "") -> Array:
	var out := []
	var here := root if rel == "" else root + "/" + rel
	for f in DirAccess.get_files_at(here):
		out.append(f if rel == "" else rel + "/" + f)
	for d in DirAccess.get_directories_at(here):
		out.append_array(_files_under(root, d if rel == "" else rel + "/" + d))
	out.sort()
	return out

func test_a_folder_holding_elements_in_another_case_is_refused(t) -> void:
	var root := _root("elements")
	_write_tree(root, {"world.json": WORLD, "Elements/character/a.json": _body(ID_A)})
	_say_the_disk(root)
	t.ok(OWWorld.read_folder(root) == null, "refused, never read as the world it would be on another disk")
	_cleanup()
	t.done()

func test_a_folder_holding_world_json_or_spatial_in_another_case_is_refused(t) -> void:
	for tag in ["World.JSON", "Spatial/pin/p.json", "\u017Fpatial/pin/p.json"]:
		var root := _root("other")
		var files := {"elements/character/a.json": _body(ID_A)}
		if tag != "World.JSON":
			files["world.json"] = WORLD
		files[tag] = WORLD if tag == "World.JSON" else _body(ID_B)
		_write_tree(root, files)
		t.ok(OWWorld.read_folder(root) == null, "%s: refused" % tag)
	_cleanup()
	t.done()

func test_a_folder_with_the_names_as_written_reads_as_before(t) -> void:
	var root := _root("plain")
	_write_tree(root, {"world.json": WORLD, "elements/character/a.json": _body(ID_A), "Media/a.png": "x"})
	var w := OWWorld.read_folder(root)
	t.ok(w != null and w.get_element(ID_A) != null, "read, the element served")
	_cleanup()
	t.done()

func test_files_holding_a_fixed_name_in_another_case_are_refused(t) -> void:
	t.ok(OWWorld.from_files(_as_bytes({"world.json": WORLD, "Elements/character/a.json": _body(ID_A)})) == null,
		"Elements/: refused, never a world with no elements")
	t.ok(OWWorld.from_files(_as_bytes({"World.JSON": WORLD, "elements/character/a.json": _body(ID_A)})) == null,
		"World.JSON: refused")
	var both := OWWorld.from_files(_as_bytes({"world.json": WORLD, "elements/character/a.json": _body(ID_A),
		"Elements/character/b.json": _body(ID_B)}))
	t.ok(both != null and both.get_element(ID_A) != null and both.get_element(ID_B) == null,
		"both spellings: elements/ read as written, Elements/ left unread")
	t.done()

func test_an_archive_holding_a_fixed_name_in_another_case_is_refused_name_case(t) -> void:
	var cases := {
		"elements": {"abbey/world.json": WORLD, "abbey/Elements/character/a.json": _body(ID_A)},
		"world in its folder": {"abbey/World.JSON": WORLD, "abbey/elements/character/a.json": _body(ID_A)},
		"world at the root": {"WORLD.json": WORLD, "elements/character/a.json": _body(ID_A)},
		"spatial": {"abbey/world.json": WORLD, "abbey/Spatial/pin/p.json": _body(ID_B)},
	}
	for label: String in cases:
		var packed := OWWorldArchive.pack_files(_as_bytes(cases[label]), "")
		var r := OWWorldArchive.read(packed.bytes)
		t.eq(r.reason, "name_case", "%s: the cause (%s)" % [label, r.message])
	t.done()

func test_a_pack_of_a_folder_holding_a_fixed_name_in_another_case_is_refused(t) -> void:
	for tag in ["Elements/character/a.json", "World.json"]:
		var root := _root("pack")
		var files := {"elements/character/b.json": _body(ID_B)} if tag == "World.json" else {"world.json": WORLD}
		files[tag] = WORLD if tag == "World.json" else _body(ID_A)
		_write_tree(root, files)
		var p := OWWorldArchive.pack_folder(root)
		t.ok(not p.ok, "%s: refused, never packed under the fixed name nor as an empty world" % tag)
		t.ok(p.message.contains("name_case") and p.message.contains("'" + tag.get_slice("/", 0) + "'"),
			"%s: the message names the cause and the spelling (%s)" % [tag, p.message])
	_cleanup()
	t.done()

func test_a_write_into_a_folder_holding_elements_in_another_case_is_refused(t) -> void:
	var root := _root("write")
	_write_tree(root, {"world.json": WORLD, "Elements/character/a.json": _body(ID_A)})
	var w := OWWorld.from_files(_as_bytes({"world.json": WORLD}))
	w.add_element(OWCharacter.new({"id": ID_B, "name": "Bo"}))
	t.eq(w.write_folder(root), ERR_INVALID_DATA, "refused")
	t.eq(_files_under(root), ["Elements/character/a.json", "world.json"],
		"nothing written (on a disk that folds case, elements/character/ would land in Elements/)")
	_cleanup()
	t.done()

func test_a_write_into_a_new_folder_writes_as_before(t) -> void:
	var root := _root("fresh")
	P.remove_tree(root)
	var w := OWWorld.from_files(_as_bytes({"world.json": WORLD}))
	w.add_element(OWCharacter.new({"id": ID_B, "name": "Bo"}))
	t.eq(w.write_folder(root), OK, "written")
	var back := OWWorld.read_folder(root)
	t.ok(back != null and back.get_element(ID_B) != null, "read back")
	_cleanup()
	t.done()
