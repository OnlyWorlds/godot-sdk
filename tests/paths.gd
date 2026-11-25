extends RefCounted
## Where the tests find their worlds. The fixture set and the example world are the vendored, pinned copies; two large
## real worlds are optional folders named by environment variable, OW_SIKELIA and OW_MOPPETOPIA (unset or missing: the
## tests that need them are skipped, never passed).

## The conformance set: the vendored copy, or the folder the environment variable OW_OWWORLD_FIXTURES names when it
## holds a verdicts.json (a draft set before its serial, as the Unity SDK's runner takes it).
static var FIXTURES: String = _fixtures()
const EXAMPLE := "res://codegen/schema-dist/example/hyperion"
const ADDRESS := "res://codegen/schema-dist/profiles/address.fixture.json"
const LENS := "res://codegen/schema-dist/profiles/lens.fixture.json"
## The npm SDK's and the Python package's shared Open with fixture, vendored byte for byte (not a dist file).
const OPENERS := "res://tests/data/openers.fixture.json"
const TMP := "user://ow-test-tmp"

static func _fixtures() -> String:
	var env := OS.get_environment("OW_OWWORLD_FIXTURES").replace("\\", "/").trim_suffix("/")
	if env != "" and FileAccess.file_exists(env + "/verdicts.json"):
		return env
	return "res://codegen/schema-dist/fixtures/owworld"

static func sikelia() -> String:
	return OS.get_environment("OW_SIKELIA")

static func moppetopia() -> String:
	return OS.get_environment("OW_MOPPETOPIA")

static func remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		remove_tree(path + "/" + sub)
	DirAccess.remove_absolute(path)

## Every element file under a folder's elements/ (and spatial/), counted by a walk of its own, for comparison.
static func count_element_files(root: String) -> int:
	var n := 0
	for top in ["elements", "spatial"]:
		if not DirAccess.dir_exists_absolute(root + "/" + top):
			continue
		for type in DirAccess.get_directories_at(root + "/" + top):
			if type.begins_with("."):
				continue
			for f in DirAccess.get_files_at(root + "/" + top + "/" + type):
				if f.ends_with(".json") and not f.begins_with("."):
					n += 1
	return n
