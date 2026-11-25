extends RefCounted
## The writer refuses a new element whose type is not one of the 22 type slugs as the standard spells them: such a type
## has no folder a reader reads (a type folder is one of the 22 as written, folder spec section 4.8), so write_folder
## and pack refuse it, naming the cause, as the TypeScript SDK's and the Python package's folder writers refuse an
## unknown type. That covers "" (a path elements//x.json) and a type that is a path ("../x", "../../x"), which wrote
## the file outside elements/ and outside the world folder.

const P = preload("res://tests/paths.gd")

const WORLD := "{\"id\": \"w\", \"name\": \"W\"}"

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

## Every file and folder under a folder, relative to it, by a walk of its own.
static func _tree(root: String, rel := "") -> Array:
	var out := []
	var here := root if rel == "" else root + "/" + rel
	for f in DirAccess.get_files_at(here):
		out.append(f if rel == "" else rel + "/" + f)
	for d in DirAccess.get_directories_at(here):
		var sub: String = d if rel == "" else rel + "/" + d
		out.append(sub + "/")
		out.append_array(_tree(root, sub))
	out.sort()
	return out

## A world of one new element of [param type] ("" a plain OWElement with no type), and its id.
static func _world_with(type: String) -> OWWorld:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
	var d := {"id": "n1", "name": "N"}
	w.add_element(OWElement.new(d) if type == "" else OWTypes.make(type, d))
	return w

const NO_TYPES := ["Character", "CHARACTER", " character", "character ", "ſpecies", "widget", "characters"]
const PATH_TYPES := ["../escape", "../../escape", "character/../../escape", "..", "."]

## write_folder and pack refuse, the reason naming the cause, and nothing is written.
func _refused(t, type: String, cause: String) -> void:
	var w := _world_with(type)
	var why := w.write_refusal()
	t.ok(why.contains(cause), "%s: the refusal names the cause: %s" % [type, why])
	var root := _root("write")
	_write_tree(root, {})
	t.eq(w.write_folder(root + "/world"), ERR_INVALID_DATA, "%s: write_folder refuses" % type)
	t.eq(_tree(root), [], "%s: nothing written, inside the folder or beside it" % type)
	var packed := w.pack("w")
	t.ok(not packed.ok and packed.message == why, "%s: pack refuses with the same words" % type)
	P.remove_tree(root)

func test_writer_a_type_outside_the_22_is_refused_naming_the_cause(t) -> void:
	for type: String in NO_TYPES:
		_refused(t, type, "not one of the 22 type slugs")
	t.done()

func test_writer_a_type_that_is_a_path_is_refused_and_nothing_is_written_outside_elements(t) -> void:
	for type: String in PATH_TYPES:
		_refused(t, type, "not one of the 22 type slugs")
	t.done()

func test_writer_an_element_with_no_type_is_refused(t) -> void:
	_refused(t, "", "has no type")
	t.done()

func test_writer_each_of_the_22_is_written_into_its_own_folder(t) -> void:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
	for slug: String in OWTypes.slugs():
		w.add_element(OWTypes.make(slug, {"id": slug + "-1", "name": "N"}))
	t.eq(w.write_refusal(), "", "no refusal")
	var root := _root("write22")
	_write_tree(root, {})
	t.eq(w.write_folder(root), OK, "written")
	var back := OWWorld.read_folder(root)
	t.eq(back.elements.size(), 22, "22 read back")
	for slug: String in OWTypes.slugs():
		t.eq(back.of_type(slug).size(), 1, slug + ": one, under its own folder")
	P.remove_tree(root)
	t.done()
