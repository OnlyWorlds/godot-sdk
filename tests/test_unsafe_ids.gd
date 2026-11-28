extends RefCounted
## A new element whose id cannot be one file name inside its type folder is refused before anything is written (folder
## spec section 3.2): the id is one non-empty segment (no "/", no "\", not "." or ".."), and the file name made from
## it, short or with the full id, passes the archive's own name checks (OWWorldArchive.path_fault and name_fault,
## section 4.7's OW-16 and OW-22). Then every resolved path lies inside the folder written, whatever made the name, and
## pack holds every entry name to the reader's checks. Each case writes into box/world two levels inside its own
## temporary folder, so a write that left the world folder would still land where the case looks.

const P = preload("res://tests/paths.gd")

const U := "0191f3a2-7c4e-7b1a-9d2e-3f4a5b6c7d8e"
const WORLD := "{\"id\": \"0191f3a2-7c4e-7b1a-9d2e-3f4a5b6c7d8e\", \"name\": \"W\"}"

## Ids no writer names a file from: probe ids, a drive or a root, a colon, a character Windows refuses, a control
## character, a device name.
static func _refused_ids() -> Array:
	return ["../x", "../../../escaped", "a/b", "a\\b", "..", ".", "ctl" + String.chr(1) + "id", "urn:uuid:" + U,
		"C:evil", "C:\\evil", "C:\\x", "\\x", "/x", "a<b", "a|b", "a?b", "a*b", "a\"b", "x" + String.chr(0x85)]

static func _root() -> String:
	return ProjectSettings.globalize_path(P.TMP + "/unsafe-ids")

static func _fresh() -> String:
	var root := _root()
	P.remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root + "/box")
	return root

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

static func _world(id: String, name: String) -> OWWorld:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
	w.add_element(OWTypes.make("character", {"id": id, "name": name}))
	return w

func get_cases() -> Array:
	var cases := []
	for id in _refused_ids():
		for name in ["", "Probe Name"]:
			var label := "%s, name '%s'" % [OWJson.quote(id), name]
			cases.append(["unsafe ids: written %s is refused, nothing written" % label, _refused.bind(id, name)])
			cases.append(["unsafe ids: a download holding %s is refused, nothing written" % label, _download_refused.bind(id, name)])
	for pair in [[U, ""], [U, "Probe Name"], ["c-1", ""], ["c-1", "Probe Name"], ["con", "Probe Name"], ["x ", ""]]:
		cases.append(["unsafe ids: %s, name '%s' is one file name and is written" % [OWJson.quote(pair[0]), pair[1]],
			_written.bind(pair[0], pair[1])])
	return cases

func _assert_refused(t, w: OWWorld, id: String, label: String) -> void:
	var why := w.write_refusal()
	t.ok(why.begins_with("character element id %s " % OWJson.quote(id)), "%s: the refusal names the id: %s" % [label, why])
	var root := _fresh()
	t.eq(w.write_folder(root + "/box/world"), ERR_INVALID_DATA, "%s: write_folder refuses" % label)
	t.eq(_files(root), [], "%s: nothing written, inside the folder or beside it" % label)
	var packed := w.pack("world")
	t.ok(not packed.ok and packed.message == why, "%s: pack refuses with the same words: %s" % [label, packed.message])
	P.remove_tree(root)

func _refused(t, id: String, name: String) -> void:
	_assert_refused(t, _world(id, name), id, OWJson.quote(id))
	t.done()

## Someone else's file: the onlyworlds.com download read (OWWorldExport), then written as a folder.
func _download_refused(t, id: String, name: String) -> void:
	var doc := {"format": "onlyworlds-world-export", "world": {"id": U, "name": "W"},
		"elements": {"character": [{"id": id, "type": "character", "name": name}]}}
	var r := OWWorldExport.read(OWJson.to_bytes(doc), "crafted.json")
	t.ok(r.ok, "the download is read: the writer is what refuses (%s)" % r.message)
	var w := r.to_world()
	t.eq(w.elements.size(), 1, "the reader serves the element")
	_assert_refused(t, w, id, "download " + OWJson.quote(id))
	t.done()

func _written(t, id: String, name: String) -> void:
	var w := _world(id, name)
	t.eq(w.write_refusal(), "", "%s: no refusal" % id)
	var root := _fresh()
	t.eq(w.write_folder(root + "/box/world"), OK, "%s: written" % id)
	var files := _files(root)
	t.eq(files.size(), 2, "%s: world.json and one element file: %s" % [id, files])
	var element: String = files[0]
	t.ok(element.begins_with("box/world/elements/character/") and element.count("/") == 4,
		"%s: in its type folder: %s" % [id, element])
	t.ok(w.pack("world").ok, "%s: packed" % id)
	P.remove_tree(root)
	t.done()

func test_the_refusal_names_the_rule_in_the_words_the_other_packages_use(t) -> void:
	t.eq(_world("../x", "").write_refusal(),
		"character element id \"../x\" cannot be a file name: it holds a path separator, / or \\.", "a separator")
	t.eq(_world("a\\b", "Named").write_refusal(),
		"character element id \"a\\\\b\" cannot be a file name: it holds a path separator, / or \\.", "a backslash, named")
	t.eq(_world("..", "").write_refusal(), "character element id \"..\" cannot be a file name: it is . or ...", "dot dot")
	t.eq(_world("C:evil", "").write_refusal(), "character element id \"C:evil\" cannot be a file name: it holds a colon.",
		"a drive")
	t.eq(_world("urn:uuid:" + U, "Probe Name").write_refusal(),
		"character element id \"urn:uuid:%s\" cannot be a file name: it holds a colon." % U,
		"a colon in the id, though the short name is plain")
	t.eq(_world("ctl" + String.chr(1) + "id", "").write_refusal(),
		"character element id \"ctl\\u0001id\" cannot be a file name: it holds a control character.", "a control character, escaped")
	# Behind those rules, the archive's name checks, wider, in their own words.
	t.ok(_world("x" + String.chr(0x7f), "").write_refusal().begins_with(
		"character element id \"x%s\" cannot be a file name: its file name " % String.chr(0x7f)), "U+007F, the name check's")
	t.ok(_world("con", "").write_refusal().contains("con.json"), "a device name")
	t.done()

## A refused element takes no path, so it takes no name from a sibling either.
func test_a_refused_id_is_left_out_of_to_files(t) -> void:
	var w := _world("../x", "")
	w.add_element(OWTypes.make("character", {"id": "c-1", "name": ""}))
	var rels := w.to_files().keys()
	rels.sort()
	t.eq(rels, ["elements/character/c-1.json", "world.json"], "only the plain id has a path")
	t.done()

## The second guard: a path that leaves the folder is refused whatever made it (here a file of the world's own).
func test_write_folder_refuses_a_path_that_would_leave_the_folder(t) -> void:
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), "media/../../escaped.txt": "x".to_utf8_buffer()})
	var root := _fresh()
	t.eq(w.write_folder(root + "/box/world"), ERR_INVALID_DATA, "refused")
	t.eq(_files(root), [], "nothing written")
	P.remove_tree(root)
	t.done()

## pack holds every entry name to the reader's own checks, as pack_folder does.
func test_pack_refuses_an_entry_name_its_reader_refuses(t) -> void:
	for rel in ["media/a:b.png", "media/../x.png", "media/con.png"]:
		var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), rel: "x".to_utf8_buffer()})
		var packed := w.pack("world")
		t.ok(not packed.ok and packed.message.contains("nothing was written"), "%s: refused: %s" % [rel, packed.message])
		t.eq(packed.bytes.size(), 0, "%s: no bytes" % rel)
	t.done()
