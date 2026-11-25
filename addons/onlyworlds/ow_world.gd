class_name OWWorld
extends RefCounted
## One world: world.json and its elements, typed, read from a world folder or an [code].owworld[/code].
##
## Writing: an element nobody edited is written back as the bytes it was read with; an edited one
## (and world.json, once edited) in the folder spec's section 5 form ([OWJson]). An edit to a file that is not UTF-8,
## or that holds a number too large for a double, is never written: the first is refused by name
## ([method write_refusal]), the second is not read as an element at all ([member errors]).
##
## [codeblock]
## var world := OWWorld.read_folder("res://worlds/moppetopia")
## for pin: OWPin in world.of_type("pin"):
##     print(pin.name, " at ", pin.x, ",", pin.y)
## [/codeblock]

const ELEMENT_FOLDERS := ["elements", "spatial"]   # spatial/: the format's dated layout, map, pin, zone, marker only
## The four types the dated spatial/ layout holds, the only type folders read under it (folder spec section 4.8).
const SPATIAL_TYPES := ["map", "pin", "zone", "marker"]

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
## What could not be read, one line each, the file's path first (a file that is not JSON, not an object, holds a number
## too large for a double ([constant OWJson.NUMBER_OUT_OF_RANGE]), an id seen twice; a name the folder format does not
## read as an element file, [method _name_refusal]). A file skipped this way stays in [member other_files] as its bytes,
## so a write or a pack carries it whole and a new element never takes its name. Ids are compared as written: one UUID
## in capitals and in lower case is two ids.
var errors := PackedStringArray()

var _by_id: Dictionary = {}

## Read a world folder: world.json and every [code]elements/<type>/*.json[/code] (and the legacy
## [code]spatial/{map,pin,zone,marker}/[/code]), the names compared as written, never by the file system's case-blind match: a type
## folder is one of the 22 type words in lower case, an element file ends in [code].json[/code] in lower case. A file
## that misses either only by its spelling ([code]X.JSON[/code], [code]elements/Character/[/code], or a folder that is no
## type) is skipped with a line in [member errors]. Media and records are not read. [code]null[/code] when there is no
## world.json, and when the folder holds world.json, elements/ or spatial/ in another case and not as written
## ([code]Elements/[/code], [code]World.JSON[/code]): those three names are read as written, so the world would read as
## empty, and the error printed names the cause, [code]name_case[/code], and both spellings ([method fixed_name_fault]).
static func read_folder(path: String) -> OWWorld:
	path = path.replace("\\", "/").trim_suffix("/")
	var why := folder_fault(path)
	if why != "":
		push_error("OnlyWorlds: the world folder %s is refused, %s" % [path, why])
		return null
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
				if name.begins_with(".") or not name.to_lower().ends_with(".json"):
					continue
				var rel: String = top + "/" + type + "/" + name
				w._add_file(rel, type, name, FileAccess.get_file_as_bytes(path + "/" + rel), json)
	return w

## A world from files keyed by their path inside it (what [method OWWorldArchive.Result.to_world] passes).
## [code]null[/code], as [method read_folder] answers, when a first-level name is world.json, elements or spatial in
## another case and the name itself is absent; the error printed names the cause and both spellings.
static func from_files(files: Dictionary) -> OWWorld:
	var tops := PackedStringArray()
	for rel: String in files:
		tops.append(rel.get_slice("/", 0))
	var why := fixed_name_fault(tops)
	if why != "":
		push_error("OnlyWorlds: the world's files are refused, %s" % why)
		return null
	var w := OWWorld.new()
	var json := JSON.new()
	var rels := files.keys()
	rels.sort()
	for rel: String in rels:
		if rel == "world.json":
			w._set_world_json(files[rel])
			continue
		var segs := rel.split("/")
		if segs.size() == 3 and ELEMENT_FOLDERS.has(segs[0]) and segs[2].to_lower().ends_with(".json") \
				and not segs[1].begins_with(".") and not segs[2].begins_with("."):
			w._add_file(rel, segs[1], segs[2], files[rel], json)
		else:
			w.other_files[rel] = files[rel]
	if w.info == null:
		w._set_world_json(PackedByteArray())
	return w

## The three fixed names of a world, read as written (folder spec section 4.8, ruled 2026-11-25).
const FIXED_NAMES := ["world.json", "elements", "spatial"]

## Why a level of a world holding [param names] is refused, or [code]""[/code]: a name of [param wanted] (the three fixed
## names) absent as written while one or more of [param names] is it in another case, compared by OW-18's fold
## ([method OWUnicode.fold]: NFC, then simple case folding), so [code]\u017Fpatial[/code] is spatial in another case. The
## reason begins with the cause, [code]name_case[/code], and names both spellings. A level holding both (only a disk that
## keeps case can) has no fault: the name as written is read, the other left unread. One listing answers it for the
## folder reader, [method from_files], the archive reader, the pack and the writer, never the file system's lookup,
## which folds case on Windows and macOS.
static func fixed_name_fault(names: PackedStringArray, wanted: Array = FIXED_NAMES) -> String:
	for want: String in wanted:
		if names.has(want):
			continue
		var key := OWUnicode.fold(want)
		var others := PackedStringArray()
		for n in names:
			if OWUnicode.fold(n) == key:
				others.append(n)
		if others.is_empty():
			continue
		others.sort()
		return ("name_case: it holds '%s' and no '%s', and the name is read as written, so '%s' is not %s and the "
			+ "world would read without it (folder spec section 4.8); rename it '%s'") \
			% ["', '".join(others), want, others[0], want, want]
	return ""

## [method fixed_name_fault] for a folder on disk, from its root's listing (files and folders, as written);
## [code]""[/code] for a folder that is not there.
static func folder_fault(path: String) -> String:
	if not DirAccess.dir_exists_absolute(path):
		return ""
	var names := DirAccess.get_files_at(path)
	names.append_array(DirAccess.get_directories_at(path))
	return fixed_name_fault(names)

## Why writing [param rels] (paths inside the world) into the folder [param path] would put a file into a type folder
## that is held in another spelling, by the folder's own listing or by another of [param rels], or [code]""[/code]. Type
## folders are the second level under elements/ and spatial/, compared by OW-18's fold ([method OWUnicode.fold]); the
## reason names both spellings. A folder holding both spellings already (only a disk that keeps case can) is written as
## each is spelled.
static func type_folder_fault(path: String, rels: Array) -> String:
	for top in ELEMENT_FOLDERS:
		var held := {}                          # each type folder's spelling, by its fold
		var base: String = path + "/" + top
		if DirAccess.dir_exists_absolute(base):
			for d in DirAccess.get_directories_at(base):
				held[d] = true
		var written := {}
		for rel: String in rels:
			var segs := rel.split("/")
			if segs.size() >= 3 and segs[0] == top:
				written[segs[1]] = true
		for name: String in written:
			for other: String in held.keys() + written.keys():
				if other != name and OWUnicode.fold(other) == OWUnicode.fold(name) and not (held.has(name) and held.has(other)):
					var pair := [name, other]
					pair.sort()
					return ("%s/%s/ and %s/%s/ are one folder on a disk that ignores case, and a type folder is read as written "
						+ "(folder spec section 4.8), so a file written into %s/%s/ would be read by no one; rename the "
						+ "folder") % [top, pair[0], top, pair[1], top, name]
	return ""

func _set_world_json(bytes: PackedByteArray) -> void:
	world_bytes = bytes
	var data = OWJson.parse_bytes(bytes)
	if OWJson.holds_out_of_range(data):
		errors.append("world.json: " + OWJson.OUT_OF_RANGE_WHY)   # no world: no id served, nothing written over it
		data = {}
	elif not (data is Dictionary):
		errors.append("world.json: not a JSON object")
		data = {}
	info = OWWorldInfo.new(data)
	info.source_path = "world.json"
	info.source_bytes = bytes

## Why the folder format does not read [param name] in the folder [param type] under [param top] (elements or spatial)
## as an element file, or "" when it does. Each name is read as written (the folder format): the type folder's name is
## one of the 22 type words in lower case, so [code]Character[/code] or [code]vessel[/code] is no type folder; under
## spatial/ it is one of the four it held ([constant SPATIAL_TYPES]), so [code]spatial/character/[/code] holds no
## Character and [code]spatial/Pin/[/code] no Pin (ruled 2026-11-25); and the extension is [code].json[/code] in lower
## case, so [code]X.JSON[/code] is no element file. Only a name ending in [code].json[/code] in some spelling is asked;
## any other file in a type folder is no element file and is passed over without a line.
static func _name_refusal(top: String, type: String, name: String) -> String:
	if top == "spatial" and not SPATIAL_TYPES.has(type):
		return "not read: spatial/%s is no type folder (under spatial/ a type folder is map, pin, zone, marker, in lower case)" % type
	if not OWTypes.SCRIPTS.has(type):
		return "not read: %s is no type folder (a type folder is named by one of the 22 type words, in lower case)" % type
	if not name.ends_with(".json"):
		return "not read: an element file's extension is .json in lower case, as written"
	return ""

## One file directly in a folder under elements/ or spatial/, its name ending in .json in some spelling: read as an
## element, or skipped with its reason and kept as bytes.
func _add_file(rel: String, type: String, name: String, bytes: PackedByteArray, json: JSON) -> void:
	var why := _name_refusal(rel.get_slice("/", 0), type, name)
	if why != "":
		errors.append("%s: %s" % [rel, why])
		other_files[rel] = bytes
		return
	_add_parsed(rel, type, bytes, json)

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
	if OWJson.holds_out_of_range(json.data):
		errors.append("%s: %s" % [rel, OWJson.OUT_OF_RANGE_WHY])
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

## Add a new element; it is written at [code]elements/<type>/<slug>--<id tail>.json[/code] (the folder format's name,
## §3.2: the slug is [method OWUnicode.file_slug] of its name; a name with no slug gives [code]<full id>.json[/code]), or
## with its full id in place of the tail when that path is held by a file of this world or by another new element (see
## [method to_files]). An element the world read keeps the file it was read from.
func add_element(e: OWElement) -> void:
	e.edited = true
	elements.append(e)
	if e.id != "":
		_by_id[e.id] = e

## Why [method write_folder] and [method pack] would refuse to write this world, or [code]""[/code] when they would
## not: a world.json to be written whose id is no non-empty String, or a new or edited element with no id (a non-empty
## String). A writer mints no id (folder spec §4.1; §3.4, format 0.3.22: a draft world conforms as any other, its id
## the tool's own until a host gives one), so the caller sets it. A file read with no id and not edited is not an
## element; it is carried back as read.
##
## Also an edited element (or world.json) whose file is not UTF-8: it was read leniently, a replacement character
## (U+FFFD) where its bytes could not be read, and written in the spec's form that character would stand in place of
## the person's bytes. Left unedited, such a file is written as its bytes, at every door.
func write_refusal(only_edited := false) -> String:
	if info.edited or not only_edited:
		var id = info.get_value("id")
		if not (id is String and OWUnicode.strip_ws(id) != ""):
			return "world.json has no id (a non-empty String), and a writer mints none: set info.id first"
	if info.edited and _read_not_utf8(info):
		return _not_utf8_refusal(info)
	for e in elements:
		if only_edited and not e.edited:
			continue
		var eid = e.get_value("id")
		if (e.edited or e.source_path == "") and not (eid is String and eid != ""):
			return "a new or edited %s has no id (a non-empty String), and a writer mints none: set its id first" % e.get_type()
		if e.edited and _read_not_utf8(e):
			return _not_utf8_refusal(e)
	var fresh := _new_paths()
	for e in fresh:
		if fresh[e] == "":
			var short := _name_of(e, false)
			var full := _name_of(e, true)
			if short == full:
				return "a new %s's file name (%s) is held by a file of this world, and a writer never writes over one: rename it" \
					% [e.get_type(), short]
			return "a new %s's two file names (%s, %s) are both held by files of this world, and a writer never writes over one: rename it" \
				% [e.get_type(), short, full]
	return ""

## True when [param e] was read from a file whose bytes are not well-formed UTF-8.
static func _read_not_utf8(e: OWElementCore) -> bool:
	return e.source_path != "" and not OWUnicode.is_utf8(e.source_bytes)

static func _not_utf8_refusal(e: OWElementCore) -> String:
	return ("%s is not UTF-8, so it was read with a replacement character where its bytes could not be read, and "
		+ "written edited that character would replace them: save the file as UTF-8 first, or leave it unedited") % e.source_path

## An element file's bytes: as read when unedited, else in the spec's section 5 form. These bytes are not checked:
## [method write_refusal] says whether they should be written, as [method write_folder] and [method pack] ask it.
static func element_bytes(e: OWElementCore) -> PackedByteArray:
	if not e.edited and e.source_path != "":
		return e.source_bytes
	return OWJson.to_bytes(e.to_dict())

## Every file of the world by its path inside it: world.json, each element, and [member other_files].
## [param only_edited] gives just the files an edit changed. A read element keeps the path it was read from; a new one
## takes its short name, or its full id in place of the tail when a file of this world (one it could not read among
## them) or another new element holds that path, so no file is written over by another.
func to_files(only_edited := false) -> Dictionary:
	var out := {}
	if not only_edited:
		out.merge(other_files)
	if info.edited or not only_edited:
		out["world.json"] = element_bytes(info)
	var fresh := _new_paths()
	for e in elements:
		if only_edited and not e.edited:
			continue
		var rel: String = e.source_path if e.source_path != "" else fresh[e]
		if rel != "":                    # "" only when write_refusal refuses the world
			out[rel] = element_bytes(e)
	return out

## Write the world as a folder at [param path]: world.json and every element file (and, for a world read from an
## archive, its other files). [param only_edited] writes just the edited files (writing back into the folder read).
## [constant ERR_INVALID_DATA], and nothing written, when [method write_refusal] says why it would not, and when the
## folder holds world.json, elements/ or spatial/ in another case and not as written: on a disk that folds case the
## files would land inside [code]Elements/[/code], where no reader reads them (the error printed says so,
## [method fixed_name_fault]). So too when a file would go into a type folder that the folder, or this write itself,
## holds in another spelling ([code]elements/character/[/code] beside [code]elements/Character/[/code]): on such a disk
## the two are one folder, and a type folder is read as written, so the file would be read by no one (the error printed
## names both folders, [method type_folder_fault]).
func write_folder(path: String, only_edited := false) -> Error:
	if write_refusal(only_edited) != "":
		return ERR_INVALID_DATA
	path = path.replace("\\", "/").trim_suffix("/")
	var why := folder_fault(path)
	if why != "":
		push_error("OnlyWorlds: nothing written to the world folder %s, %s" % [path, why])
		return ERR_INVALID_DATA
	var files := to_files(only_edited)
	why = type_folder_fault(path, files.keys())
	if why != "":
		push_error("OnlyWorlds: nothing written to the world folder %s: %s" % [path, why])
		return ERR_INVALID_DATA
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

## Pack the world as an [code].owworld[/code]'s bytes, its top folder [param top]. The author fields are left out
## of every file under elements/ and spatial/ that is one JSON object ([method OWWorldArchive.strip_author_fields],
## counted in [member OWWorldArchive.Packed.author_fields_left_out]) unless [param include_author_fields]. Not ok,
## its message [method write_refusal]'s, when the world would not be written.
func pack(top: String, include_author_fields := false) -> OWWorldArchive.Packed:
	var why := write_refusal()
	if why != "":
		var refused := OWWorldArchive.Packed.new()
		refused.message = why
		return refused
	var files := to_files()
	var left := PackedStringArray() if include_author_fields else OWWorldArchive.strip_author_fields(files)
	var packed := OWWorldArchive.pack_files(files, top)
	packed.author_fields_left_out = left
	return packed

## Where each new element (no [member OWElementCore.source_path]) is written: its short name
## ([code]<slug>--<id tail>.json[/code], [method _name_of]), or, when that path is already held, its full id in place of
## the tail (a name with no slug has one name only, [code]<full id>.json[/code]). A path
## is held by a file the world read (an element's own, or one it could not read, kept in [member other_files]: a writer
## never writes over a file it could not read) and by a new element ahead of it. New elements go id-ascending by code
## point, so of two whose short names meet the lower id keeps the short form (folder spec §3.2, the writer collision
## rule). Paths are compared case-blind, as a case-blind disk would meet them. [code]""[/code] for an element whose
## two names are both held.
func _new_paths() -> Dictionary:
	var held := {}
	for rel: String in other_files:
		held[rel.to_lower()] = true
	var fresh: Array[OWElement] = []
	for e in elements:
		if e.source_path != "":
			held[e.source_path.to_lower()] = true
		else:
			fresh.append(e)
	fresh.sort_custom(func(a: OWElement, b: OWElement) -> bool: return a.id < b.id)   # String order is code point order
	var out := {}
	for e in fresh:
		var pick := ""
		for rel in [_name_of(e, false), _name_of(e, true)]:
			if not held.has(rel.to_lower()):
				pick = rel
				break
		out[e] = pick
		if pick != "":
			held[pick.to_lower()] = true
	return out

## A new element's path by the folder format's RECOMMENDED profile (§3.2): [code]<slug>--<id tail>.json[/code], or
## with the full id in place of the tail when [param full_id]; [code]<full id>.json[/code] when the name gives no slug
## ([method OWUnicode.file_slug]). The same names as the TypeScript and Python packages' folder writers.
static func _name_of(e: OWElement, full_id: bool) -> String:
	var slug := OWUnicode.file_slug(e.name)
	if slug == "":
		return "elements/%s/%s.json" % [e.get_type(), e.id]
	return "elements/%s/%s--%s.json" % [e.get_type(), slug, e.id if full_id else _id_tail(e.id)]

## The id's last eight characters; when those would hold "--" or start with "-" (an id made by hand, never a uuid),
## the last eight of the id without its hyphens, so the separator stays readable.
static func _id_tail(id: String) -> String:
	if id.length() <= 8:
		return id
	var raw := id.right(8)
	if not raw.contains("--") and not raw.begins_with("-"):
		return raw
	return id.replace("-", "").right(8)
