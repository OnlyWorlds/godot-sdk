class_name OWWorld
extends RefCounted
## One world: world.json and its elements, typed, read from a world folder or an [code].owworld[/code].
##
## Writing follows DECISIONS #2: an element nobody edited is written back as the bytes it was read with; an edited one
## (and world.json, once edited) in the folder spec's section 5 form ([OWJson]).
##
## [codeblock]
## var world := OWWorld.read_folder("C:/worlds/moppetopia")
## for pin: OWPin in world.of_type("pin"):
##     print(pin.name, " at ", pin.x, ",", pin.y)
## [/codeblock]

const ELEMENT_FOLDERS := ["elements", "spatial"]   # spatial/: the format's dated layout for the spatial types

## The folder read from ("" for a world read from an archive).
var root := ""
## world.json's typed view; its dictionary is the parsed file.
var info: OWWorldInfo
## world.json as read.
var world_bytes: PackedByteArray
## Every element, in the order read.
var elements: Array[OWElement] = []
## Files of the world that are not elements (media/, records/, a file of no known kind), by path inside the world,
## kept as bytes when the world came from an archive, so it packs back whole.
var other_files: Dictionary = {}
## What could not be read, one line each (a file that is not JSON, not an object, an id seen twice).
var errors := PackedStringArray()

var _by_id: Dictionary = {}

## Read a world folder: world.json and every [code]elements/<type>/*.json[/code] (and the legacy
## [code]spatial/<type>/[/code]). Media and records are not read. [code]null[/code] when there is no world.json.
static func read_folder(path: String) -> OWWorld:
	path = path.replace("\\", "/").trim_suffix("/")
	var wpath := path + "/world.json"
	if not FileAccess.file_exists(wpath):
		push_error("OnlyWorlds: no world.json in %s" % path)
		return null
	var w := OWWorld.new()
	w.root = path
	w._set_world_json(FileAccess.get_file_as_bytes(wpath))
	var json := JSON.new()
	for top in ELEMENT_FOLDERS:
		var base: String = path + "/" + top
		if not DirAccess.dir_exists_absolute(base):
			continue
		var types := Array(DirAccess.get_directories_at(base))
		types.sort()
		for type in types:
			if type.begins_with("."):
				continue
			var names := Array(DirAccess.get_files_at(base + "/" + type))
			names.sort()
			for name in names:
				if name.begins_with(".") or not name.ends_with(".json"):
					continue
				var rel: String = top + "/" + type + "/" + name
				w._add_parsed(rel, type, FileAccess.get_file_as_bytes(path + "/" + rel), json)
	return w

## A world from files keyed by their path inside it (what [method OWWorldArchive.Result.to_world] passes).
static func from_files(files: Dictionary) -> OWWorld:
	var w := OWWorld.new()
	var json := JSON.new()
	var rels := files.keys()
	rels.sort()
	for rel: String in rels:
		if rel == "world.json":
			w._set_world_json(files[rel])
			continue
		var segs := rel.split("/")
		if segs.size() == 3 and ELEMENT_FOLDERS.has(segs[0]) and segs[2].ends_with(".json") \
				and not segs[1].begins_with(".") and not segs[2].begins_with("."):
			w._add_parsed(rel, segs[1], files[rel], json)
		else:
			w.other_files[rel] = files[rel]
	if w.info == null:
		w._set_world_json(PackedByteArray())
	return w

func _set_world_json(bytes: PackedByteArray) -> void:
	world_bytes = bytes
	var data = OWJson.parse_bytes(bytes)
	if not (data is Dictionary):
		errors.append("world.json: not a JSON object")
		data = {}
	info = OWWorldInfo.new(data)
	info.source_path = "world.json"
	info.source_bytes = bytes

func _add_parsed(rel: String, type: String, bytes: PackedByteArray, json: JSON) -> void:
	var text := bytes.get_string_from_utf8()   # a byte order mark is read past (measured)
	if json.parse(text) != OK:
		errors.append("%s: not JSON (%s, line %d)" % [rel, json.get_error_message(), json.get_error_line()])
		other_files[rel] = bytes
		return
	if not (json.data is Dictionary):
		errors.append("%s: not a JSON object" % rel)
		other_files[rel] = bytes
		return
	var e := OWTypes.make(type, json.data)
	e.source_path = rel
	e.source_bytes = bytes
	elements.append(e)
	var id := e.id
	if id != "":
		if _by_id.has(id):
			errors.append("%s: id %s is also %s" % [rel, id, _by_id[id].source_path])
		else:
			_by_id[id] = e

## The world's id (world.json's [code]id[/code]).
func get_id() -> String:
	return info.id

## The element with this id, or [code]null[/code].
func get_element(id: String) -> OWElement:
	return _by_id.get(id)

## Every element of one type ([code]"pin"[/code]), in the order read.
func of_type(type: String) -> Array[OWElement]:
	var out: Array[OWElement] = []
	for e in elements:
		if e.get_type() == type:
			out.append(e)
	return out

## Add a new element; it is written at [code]elements/<type>/<name>--<id tail>.json[/code].
func add_element(e: OWElement) -> void:
	e.edited = true
	elements.append(e)
	if e.id != "":
		_by_id[e.id] = e

## An element file's bytes: as read when unedited, else in the spec's section 5 form.
static func element_bytes(e: OWElementCore) -> PackedByteArray:
	if not e.edited and e.source_path != "":
		return e.source_bytes
	return OWJson.to_bytes(e.to_dict())

## Every file of the world by its path inside it: world.json, each element, and [member other_files].
## [param only_edited] gives just the files an edit changed.
func to_files(only_edited := false) -> Dictionary:
	var out := {}
	if not only_edited:
		out.merge(other_files)
	if info.edited or not only_edited:
		out["world.json"] = element_bytes(info)
	for e in elements:
		if only_edited and not e.edited:
			continue
		out[_path_of(e)] = element_bytes(e)
	return out

## Write the world as a folder at [param path]: world.json and every element file (and, for a world read from an
## archive, its other files). [param only_edited] writes just the edited files (writing back into the folder read).
func write_folder(path: String, only_edited := false) -> Error:
	path = path.replace("\\", "/").trim_suffix("/")
	var files := to_files(only_edited)
	for rel: String in files:
		var full := path + "/" + rel
		var err := DirAccess.make_dir_recursive_absolute(full.get_base_dir())
		if err != OK:
			return err
		var f := FileAccess.open(full, FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_buffer(files[rel])
		f.close()
	return OK

## Pack the world as an [code].owworld[/code]'s bytes, its top folder [param top].
func pack(top: String) -> OWWorldArchive.Packed:
	return OWWorldArchive.pack_files(to_files(), top)

func _path_of(e: OWElementCore) -> String:
	if e.source_path != "":
		return e.source_path
	var slug := (e as OWElement).name.to_lower().strip_edges()
	var clean := ""
	for i in slug.length():
		var c := slug[i]
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "-"
	while clean.contains("--"):
		clean = clean.replace("--", "-")
	clean = clean.trim_prefix("-").trim_suffix("-")
	var id: String = (e as OWElement).id
	return "elements/%s/%s--%s.json" % [e.get_type(), clean if clean != "" else "element", id.right(8)]
