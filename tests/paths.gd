extends RefCounted
## Where the tests find their worlds. The fixture set is the vendored, pinned copy; the two real worlds are folders on
## this machine, overridable by environment variable (a test whose world is missing is skipped, never passed).

const FIXTURES := "res://codegen/schema-dist/fixtures/owworld"
const EXAMPLE := "res://codegen/schema-dist/example/hyperion"
const ADDRESS := "res://codegen/schema-dist/profiles/address.fixture.json"
const LENS := "res://codegen/schema-dist/profiles/lens.fixture.json"
## The npm SDK's and the Python package's shared Open with fixture, vendored byte for byte (not a dist file).
const OPENERS := "res://tests/data/openers.fixture.json"
const TMP := "user://ow-test-tmp"

static func sikelia() -> String:
	var p := OS.get_environment("OW_SIKELIA")
	return p if p != "" else "C:/Users/Titus/Development/OnlyWorlds/sikelia-world"

static func moppetopia() -> String:
	var p := OS.get_environment("OW_MOPPETOPIA")
	return p if p != "" else "C:/Users/Titus/Carrier/Armature/projects/moppetopia-world"

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
