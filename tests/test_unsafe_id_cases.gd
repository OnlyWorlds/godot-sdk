extends RefCounted
## The TypeScript SDK's and the Python package's shared unsafe-id cases (tests/data/unsafe-ids.cases.json, the same
## bytes, held by its sha256), each run through OWWorld.write_refusal and write_folder: a refused id is refused before
## any file lands, in their words; a written id lands at their path.
##
## Three cases part from the packages on purpose. An empty id meets the writer's own no-id refusal first, which names
## what a maker has to do; the packages' "it is empty" is never reached from a write. "c-\u007f", which the packages
## write, is refused: the archive's name check behind their rules takes a control character as general category Cc
## (folder spec section 4.7, OW-22), U+007F among them. And "a\u0000b" cannot be posed in Godot: its String turns
## U+0000 into U+FFFD before any reader sees it (Godot 4.7.2 prints "Unicode parsing error, some characters were
## replaced with � (U+FFFD): Unexpected NUL character"), so that case is skipped. The two other cases holding U+0000
## are held, since their first rule (a separator, a colon) comes before it.

const P = preload("res://tests/paths.gd")

const CASES := "res://tests/data/unsafe-ids.cases.json"
const CASES_SHA256 := "cc6c0c016b441c0ebdc2840304f28c69e05a7ddf6eb0a333b343188717eb5581"
const WORLD := "{\"id\": \"0191f3a2-7c4e-7b1a-9d2e-3f4a5b6c7d8e\", \"name\": \"W\"}"
## The one case a Godot String cannot hold, as the cases file spells it.
const NOT_POSED := "\"a\\u0000b\""

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	return _doc

## The id as the cases file spells it (JSON text): a U+FFFD here is the U+0000 Godot's String cannot hold (the file
## holds no U+FFFD of its own).
static func _spelled(c: Dictionary) -> String:
	return OWJson.quote(c["id"]).replace(String.chr(0xfffd), "\\u0000")

static func _root() -> String:
	return ProjectSettings.globalize_path(P.TMP + "/unsafe-id-cases")

## Every file under a folder, relative to it (hidden ones too).
static func _files(root: String, rel := "") -> Array:
	var out := []
	var here := root if rel == "" else root + "/" + rel
	var d := DirAccess.open(here)
	if d == null:
		return out
	d.include_hidden = true
	for f in d.get_files():
		out.append(f if rel == "" else rel + "/" + f)
	for sub in d.get_directories():
		out.append_array(_files(root, sub if rel == "" else rel + "/" + sub))
	out.sort()
	return out

## Writes one case's element into a fresh box/world two levels inside the temporary folder: [the refusal, the error,
## every file under the temporary folder].
static func _write(c: Dictionary) -> Array:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
	w.add_element(OWTypes.make("character", {"id": c["id"], "name": c["name"]}))
	var why := w.write_refusal()
	var root := _root()
	P.remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root + "/box")
	var err := w.write_folder(root + "/box/world")
	var files := _files(root)
	P.remove_tree(root)
	return [why, err, files]

func get_cases() -> Array:
	var out := []
	for c in _fixture()["refused"]:
		out.append(["unsafe id cases: %s, name '%s' is refused" % [_spelled(c), c["name"]], _refused.bind(c)])
	for c in _fixture()["written"]:
		out.append(["unsafe id cases: %s, name '%s' is written" % [_spelled(c), c["name"]], _written.bind(c)])
	return out

func test_the_cases_file_is_the_shared_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(CASES), CASES_SHA256, "the cases' bytes are the TypeScript SDK's and the Python package's")
	t.eq(_fixture()["refused"].size(), 19, "the refused cases' count")
	t.eq(_fixture()["written"].size(), 5, "the written cases' count")
	t.done()

func _refused(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var spelled := _spelled(c)
	if spelled == NOT_POSED:
		t.skip("a Godot String cannot hold U+0000 (it becomes U+FFFD), so this id cannot be posed")
		return
	var got := _write(c)
	var why: String = got[0]
	if c["id"] == "":
		# By design: an empty id keeps the writer's no-id refusal, which runs first and tells a maker what to do; the
		# packages' "it is empty" is their guard's word for the same refusal.
		t.ok(why.begins_with("a new or edited character has no id"), "%s: the no-id refusal: %s" % [spelled, why])
	else:
		t.eq(why, "character element id %s cannot be a file name: %s." % [OWJson.quote(c["id"]), c["why"]],
			"%s: in the packages' words" % spelled)
	t.eq(got[1], ERR_INVALID_DATA, "%s: write_folder refuses" % spelled)
	t.eq(got[2], [], "%s: nothing written, inside the folder or beside it" % spelled)
	t.done()

func _written(t, c: Dictionary) -> void:
	var spelled := _spelled(c)
	var got := _write(c)
	if c["id"] == "c-" + String.chr(0x7f):
		# By design: the archive's name check, behind the packages' rules, refuses U+007F (general category Cc, folder
		# spec section 4.7, OW-22), where the packages refuse U+0000 to U+001F only.
		t.ok(String(got[0]).begins_with("character element id %s cannot be a file name: its file name " % OWJson.quote(c["id"])),
			"%s: the name check's refusal: %s" % [spelled, got[0]])
		t.eq(got[1], ERR_INVALID_DATA, "%s: write_folder refuses" % spelled)
		t.eq(got[2], [], "%s: nothing written" % spelled)
		t.done()
		return
	t.eq(got[0], "", "%s: no refusal" % spelled)
	t.eq(got[1], OK, "%s: written" % spelled)
	t.eq(got[2], ["box/world/" + String(c["path"]), "box/world/world.json"], "%s: at the packages' path" % spelled)
	t.done()
