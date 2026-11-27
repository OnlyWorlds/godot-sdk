class_name OWWorldArchive
extends RefCounted
## A world folder as one file: the [code].owworld[/code] archive (folder spec section 4.7, checks OW-1 to OW-22).
##
## [method read] holds an archive to every reader rule, in the reference checker's order
## ([code]run_py.py[/code]'s [code]read_archive[/code]), and refuses with one cause from the spec's list.
## [method pack] writes a folder as a portable [code].owworld[/code]: the marker stored first, only the folder's parts,
## entries in UTF-8 byte order, every one stamped 1980-01-01 00:00, methods 0 and 8, and who wrote each element left
## out unless asked ([method strip_author_fields]).

const MEDIA_TYPE := "application/vnd.onlyworlds.world+zip"
const MARKER := "mimetype"
const WORLD := "world.json"
const EXTENSION := "owworld"

## The floor every reader accepts (OW-15): 2 GiB inflated, 500,000 files.
const DEFAULT_MAX_BYTES := 2147483648
const DEFAULT_MAX_ENTRIES := 500000

## The one list of refusal causes (section 4.7; name_case, a fixed name in another case, section 4.8).
const REASONS := ["unsafe_path", "too_big", "too_many", "not_a_world", "more_than_one", "not_openable",
	"duplicate", "collision", "link", "method", "name", "marker", "name_case"]

const _JUNK := {"__MACOSX": true, ".DS_Store": true, "Thumbs.db": true}
const _PARTS := ["elements", "spatial", "media"]
const _RESERVED := {"CON": true, "PRN": true, "AUX": true, "NUL": true,
	"COM1": true, "COM2": true, "COM3": true, "COM4": true, "COM5": true, "COM6": true, "COM7": true, "COM8": true, "COM9": true,
	"LPT1": true, "LPT2": true, "LPT3": true, "LPT4": true, "LPT5": true, "LPT6": true, "LPT7": true, "LPT8": true, "LPT9": true}
const _BAD_CHARS := "<>:\"|?*"
const _S_IFREG := 0x8000
const _S_IFDIR := 0x4000

## What [method read] found. [member ok] true: the world and its files; false: [member reason] and [member message].
class Result:
	var ok := false
	var reason := ""
	var message := ""
	## For a [code]not_a_world[/code] whose world.json is there but cannot be read, what is wrong with it, in the
	## folder read report's words: [code]too_deep[/code] (nested past 200), [code]not_json[/code], or
	## [code]number_out_of_range[/code] (a number past a double). [code]""[/code] on every other refusal (no
	## world.json, one that is JSON but no object, one with no id) and on a world read. A tool reads this, never
	## [member message]. The TypeScript SDK's [code]OwWorldFileError.worldFault[/code].
	var world_fault := ""
	var world_id := ""
	## "" when world.json sits at the archive's root, else the top folder with its slash ("abbey/").
	var prefix := ""
	## Every file inside the world, by its path inside the world ("elements/character/ana--0000ab01.json") -> bytes.
	## world.json is the archive's own bytes, or, when it carried an api block, re-written without it.
	var files: Dictionary = {}
	## world.json parsed, without its api block.
	var world: Dictionary = {}
	## world.json as the archive holds it.
	var held_world_json: PackedByteArray
	var entries: Array = []

	## The archive as an [OWWorld]: its elements typed, every other file kept for writing back ([code]null[/code] only
	## where [method OWWorld.from_files] refuses, which an accepted archive never is).
	func to_world() -> OWWorld:
		return OWWorld.from_files(files)

## What [method pack] made. [member ok] false: [member message] says why, and nothing was written.
class Packed:
	var ok := false
	var message := ""
	var names := PackedStringArray()
	var bytes: PackedByteArray
	## The files written without their author fields, by path inside the world, in code point order
	## ([method strip_author_fields]); empty when they were asked to travel, and for [method pack_files].
	var author_fields_left_out := PackedStringArray()
	## On a share ([code]include_hidden[/code] false, folder spec section 4.8), by path inside the world in code point
	## order: the element files left out for their [code]hidden[/code] mark, and apart from them every other file under
	## elements/ and spatial/ left out because the folder reader would not serve it as one element. Empty on a copy.
	var hidden_left_out := PackedStringArray()
	var unread_left_out := PackedStringArray()

# -- read -------------------------------------------------------------------------------------------------------------

## Read an [code].owworld[/code] file from disk (any path Godot can open).
static func read_file(path: String, max_bytes := DEFAULT_MAX_BYTES, max_entries := DEFAULT_MAX_ENTRIES) -> Result:
	if not FileAccess.file_exists(path):
		return _refuse(Result.new(), "not_openable", "no file at %s" % path)
	return read(FileAccess.get_file_as_bytes(path), max_bytes, max_entries)

## Read an archive's bytes as a conforming reader does. Nothing is extracted; an entry is never inflated past what it
## declares.
static func read(raw: PackedByteArray, max_bytes := DEFAULT_MAX_BYTES, max_entries := DEFAULT_MAX_ENTRIES) -> Result:
	var r := Result.new()
	var w := OWZip.walk(raw)
	if w.error != "":
		return _refuse(r, w.error, w.message)
	r.entries = w.entries

	# Every entry, from the central directory alone, before anything is inflated.
	var seen := {}
	var files: Array = []
	var declared := 0
	for e: OWZip.Entry in w.entries:
		var name := e.name
		var is_dir := name.ends_with("/")
		var fault := path_fault(name.substr(0, name.length() - 1) if is_dir else name)
		if fault != "":
			return _refuse(r, "unsafe_path", "entry %s %s" % [name.c_escape(), fault])
		var kind := e.unix_type()
		if kind != 0 and kind != _S_IFREG and kind != _S_IFDIR:
			return _refuse(r, "link", "entry %s has Unix type %o (a link or a special file)" % [name.c_escape(), kind])
		if e.flags & (OWZip.FLAG_ENCRYPTED | OWZip.FLAG_STRONG):
			return _refuse(r, "method", "entry %s is encrypted" % name.c_escape())
		if e.method != 0 and e.method != 8:
			return _refuse(r, "method", "entry %s uses method %d (only 0 and 8)" % [name.c_escape(), e.method])
		if not (e.flags & OWZip.FLAG_UTF8) and not OWUnicode.is_ascii(name):
			return _refuse(r, "name", "entry %s is not ASCII and lacks the UTF-8 flag" % name.c_escape())
		fault = name_fault(name.rstrip("/"))
		if fault != "":
			return _refuse(r, "name", "entry %s: %s" % [name.c_escape(), fault])
		if seen.has(name):
			return _refuse(r, "duplicate", "entry %s appears twice" % name.c_escape())
		seen[name] = true
		if is_dir:
			continue
		files.append(e)
		if files.size() > max_entries:
			return _refuse(r, "too_many", "more than %d files" % max_entries)
		declared += e.usize
		if declared > max_bytes:
			return _refuse(r, "too_big", "declares more than %d bytes" % max_bytes)

	# OW-18: no two names (or folders) one after folding (NFC, then simple case folding).
	var folded := {}
	var done := {}
	for name: String in seen:
		var segs := name.rstrip("/").split("/")
		var prefix := ""
		for i in segs.size():
			prefix = segs[i] if i == 0 else prefix + "/" + segs[i]
			if done.has(prefix):
				continue
			done[prefix] = true
			var key := OWUnicode.fold(prefix)
			if folded.has(key):
				return _refuse(r, "collision", "names collide after NFC and case folding: %s, %s" % [folded[key].c_escape(), prefix.c_escape()])
			folded[key] = prefix

	# OW-19: no path is both a file and a folder.
	var names := {}
	for e: OWZip.Entry in files:
		names[e.name] = e
	for name: String in names:
		var segs := name.split("/")
		var prefix := ""
		for i in segs.size() - 1:
			prefix = segs[i] if i == 0 else prefix + "/" + segs[i]
			if names.has(prefix):
				return _refuse(r, "unsafe_path", "%s is a file and a folder" % prefix.c_escape())

	# OW-6: a marker is never required; one present with other bytes is refused. Its shape binds the writer only.
	if names.has(MARKER):
		var out := {}
		var got := OWZip.inflate(raw, names[MARKER], out)
		if out.has("error"):
			return _refuse(r, out["error"], out["message"])
		if got != MEDIA_TYPE.to_ascii_buffer():
			return _refuse(r, "marker", "mimetype holds other bytes than the media type")

	# OW-2: exactly one world; OW-4: anything beside its folder is ignored, a dot-folder never a world.
	var candidates: Array[String] = []
	for name: String in names:
		if name != MARKER and not _is_junk(name):
			candidates.append(name)
	if candidates.has(WORLD):
		r.prefix = ""
	else:
		var roots := {}
		for n in candidates:
			if n.count("/") == 1 and n.ends_with("/" + WORLD) and not n.begins_with("."):
				roots[n.get_slice("/", 0) + "/"] = true
		if roots.is_empty():
			# Section 4.8 (ruled 2026-11-25): a world.json in another case, where a world would sit, is said as its cause.
			var cased := PackedStringArray()
			for n in candidates:
				if n.count("/") <= 1 and not n.begins_with(".") \
						and OWWorld.fixed_name_fault(PackedStringArray([n.get_file()]), [WORLD]) != "":
					cased.append(n)
			if not cased.is_empty():
				cased.sort()
				return _refuse(r, "name_case", "world.json in another case and no world.json: %s" % str(cased))
			return _refuse(r, "not_a_world", "no world.json at the root or in one top-level folder")
		if roots.size() > 1:
			var list := roots.keys()
			list.sort()
			return _refuse(r, "more_than_one", "worlds in %s" % str(list))
		r.prefix = roots.keys()[0]

	# OW-5: no world.json inside the world but its own, except a producer's under records/, and except under a folder
	# whose name starts with a dot: a dot-folder is never a world, wherever it sits (ruled 2026-11-24; ..atlas/ too).
	# Only this check skips them: every other check reads their entries.
	var inside: Array[String] = []
	for n in candidates:
		if n.begins_with(r.prefix):
			inside.append(n)
			var rel := n.substr(r.prefix.length())
			if rel != WORLD and rel.ends_with("/" + WORLD) and not rel.begins_with("records/") and not _under_a_dot_folder(rel):
				return _refuse(r, "more_than_one", "a second world.json inside the world: %s" % n.c_escape())

	# Section 4.8 (ruled 2026-11-25): world.json, elements/ and spatial/ are read as written, and one held in another case
	# without the name itself refuses the archive, never reads as an empty world (OW-18 refuses the two side by side;
	# this, the one alone). Before one byte is inflated, as the reference checker orders it.
	var tops := PackedStringArray()
	for n in inside:
		tops.append(n.substr(r.prefix.length()).get_slice("/", 0))
	var why := OWWorld.fixed_name_fault(tops)
	if why != "":
		return _refuse(r, "name_case", why)

	# OW-14: every entry inflated within what it declares, its CRC and length right.
	var content := {}
	for e: OWZip.Entry in files:
		var out := {}
		var data := OWZip.inflate(raw, e, out)
		if out.has("error"):
			return _refuse(r, out["error"], out["message"])
		content[e.name] = data

	# OW-3: the world's own world.json is a JSON object whose id is a non-empty string once trimmed.
	r.held_world_json = content[r.prefix + WORLD]
	# OW-25: the world's own file counted as an element file is, in its text before any parse: a world.json the reader
	# cannot read, so no world (OW-3), its message naming the word.
	if OWJson.opens_past(r.held_world_json.get_string_from_utf8()):
		r.world_fault = "too_deep"
		return _refuse(r, "not_a_world", "world.json: " + OWJson.TOO_DEEP_WHY)
	var parsed := {}
	var world = _parse_strict(r.held_world_json, parsed)
	if not parsed.get("ok", false):
		r.world_fault = "not_json"
		return _refuse(r, "not_a_world", "world.json does not parse")
	if not (world is Dictionary):
		return _refuse(r, "not_a_world", "world.json is not an object")
	if OWJson.holds_out_of_range(world):
		r.world_fault = "number_out_of_range"
		return _refuse(r, "not_a_world", "world.json: " + OWJson.OUT_OF_RANGE_WHY)
	var wid = world.get("id")
	if not (wid is String) or OWUnicode.strip_ws(wid) == "":
		return _refuse(r, "not_a_world", "world.json has no id that is a non-empty string")

	for n in inside:
		r.files[n.substr(r.prefix.length())] = content[n]
	if world.has("api"):        # OW-10: stripped, never returned, the file still read
		world.erase("api")
		r.files[WORLD] = OWJson.to_bytes(world)
	r.world = world
	r.world_id = wid
	r.ok = true
	r.message = "world %s, %d files" % [wid, r.files.size()]
	return r

## Whether [param rel] sits under a folder whose name starts with a dot, at any depth (its last segment, the file, not
## counted). The names are already plain paths: OW-16 refused a segment that is exactly "." or "..".
static func _under_a_dot_folder(rel: String) -> bool:
	var segs := rel.split("/")
	for i in segs.size() - 1:
		if segs[i].begins_with("."):
			return true
	return false

static func _refuse(r: Result, reason: String, message: String) -> Result:
	r.ok = false
	r.reason = reason
	r.message = message
	return r

## OW-16, strict: a plain relative path, "/"-separated, no empty, "." or ".." segment, no drive, no backslash.
## "" when the name is one, else what is wrong with it.
static func path_fault(name: String) -> String:
	if name.contains("\\"):
		return "holds a backslash"
	if name.begins_with("/"):
		return "is absolute"
	if name.length() >= 2 and name[1] == ":" and _is_ascii_letter(name.unicode_at(0)):
		return "names a drive"
	for seg in name.split("/"):
		if seg == "" or seg == "." or seg == "..":
			return "has an empty, '.' or '..' segment"
	return ""

## OW-22: every segment lands on any disk. "" when it does.
static func name_fault(name: String) -> String:
	for seg in name.split("/"):
		for i in seg.length():
			var c := seg.unicode_at(i)
			if c < 0x20 or (c >= 0x7F and c <= 0x9F) or _BAD_CHARS.contains(String.chr(c)):
				return "segment %s holds a reserved or control character" % seg.c_escape()
		if seg.ends_with(".") or seg.ends_with(" "):
			return "segment %s ends in a dot or a space" % seg.c_escape()
		if _RESERVED.has(_ascii_upper(seg.get_slice(".", 0))):
			return "segment %s is a Windows reserved name" % seg.c_escape()
	return ""

static func _is_ascii_letter(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A)

static func _ascii_upper(s: String) -> String:
	return s.to_upper() if OWUnicode.is_ascii(s) else s   # the reserved names are ASCII; a non-ASCII base is none

static func _is_junk(name: String) -> bool:
	for seg in name.split("/"):
		if _JUNK.has(seg):
			return true
	return false

## JSON as Python's strict json.loads reads it, for world.json: UTF-8 (a leading byte order mark read past), and no
## raw control character inside a string (Godot's parser accepts one; the reference checker refuses it). [param out]
## gets [code]ok[/code] true when the text is JSON, so a world.json of [code]null[/code] is told from one that is none.
static func _parse_strict(bytes: PackedByteArray, out := {}) -> Variant:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	var text = OWUnicode.decode_utf8(bytes)
	if text == null:
		return null
	var in_str := false
	var esc := false
	for x in bytes:
		if in_str:
			if esc:
				esc = false
			elif x == 0x5C:
				esc = true
			elif x == 0x22:
				in_str = false
			elif x < 0x20:
				return null
		elif x == 0x22:
			in_str = true
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	out["ok"] = true
	return json.data

# -- pack -------------------------------------------------------------------------------------------------------------

## Pack a world folder into a portable [code].owworld[/code] at [param archive_path]. Writes only the archive.
## [param keep_api] keeps world.json's api block (a private copy, not a portable file, OW-10);
## [param include_private] carries the producers records/RECORDS.json marks private (section 4.5 rule 11);
## [param include_author_fields] carries the author fields, for a byte copy of your own folder
## ([method strip_author_fields] says what goes without it).
## [param include_hidden] true (the default) packs a copy: every file under elements/ and spatial/ byte for byte, as
## keel's own download keeps an owner's hidden elements and as a person backs up or moves their own world. False packs a
## share, a file to hand to someone else (folder spec section 4.8, ruled 2026-11-23): [method leave_out_for_share].
static func pack(folder: String, archive_path: String, keep_api := false, include_private := false,
		include_author_fields := false, include_hidden := true) -> Packed:
	var abs_folder := ProjectSettings.globalize_path(folder).simplify_path().trim_suffix("/")
	var abs_archive := ProjectSettings.globalize_path(archive_path).simplify_path()
	if abs_archive.to_lower().begins_with(abs_folder.to_lower() + "/"):
		var bad := Packed.new()
		bad.message = "the archive %s would be written inside the folder it packs" % archive_path
		return bad
	var p := pack_folder(folder, keep_api, include_private, include_author_fields, include_hidden)
	if not p.ok:
		return p
	var f := FileAccess.open(archive_path, FileAccess.WRITE)
	if f == null:
		p.ok = false
		p.message = "cannot write %s (error %d)" % [archive_path, FileAccess.get_open_error()]
		return p
	f.store_buffer(p.bytes)
	f.close()
	return p

## [method pack]'s bytes, in memory.
static func pack_folder(folder: String, keep_api := false, include_private := false,
		include_author_fields := false, include_hidden := true) -> Packed:
	var out := Packed.new()
	folder = folder.trim_suffix("/").trim_suffix("\\")
	if not DirAccess.dir_exists_absolute(folder):
		out.message = "no world folder at %s" % folder
		return out
	# Section 4.8: a folder its own reader refuses is never packed, so the file system's fold never turns Elements/ into
	# elements/ in the archive (Windows, macOS), nor packs a world without it (Linux).
	var why := OWWorld.folder_fault(folder)
	if why != "":
		out.message = "the world folder %s is refused, %s" % [folder, why]
		return out
	var world_path := folder + "/" + WORLD
	if not FileAccess.file_exists(world_path):
		out.message = "no world.json in %s" % folder
		return out
	var world_bytes := FileAccess.get_file_as_bytes(world_path)
	if OWJson.opens_past(world_bytes.get_string_from_utf8()):
		out.message = "world.json in %s: %s" % [folder, OWJson.TOO_DEEP_WHY]
		return out
	var world = OWJson.parse_bytes(world_bytes)
	if OWJson.holds_out_of_range(world):
		out.message = "world.json in %s: %s" % [folder, OWJson.OUT_OF_RANGE_WHY]
		return out
	if not (world is Dictionary) or not (world.get("id") is String) or OWUnicode.strip_ws(world["id"]) == "":
		out.message = "world.json in %s is not an object with an id (a non-empty string)" % folder
		return out
	if world.has("api") and not keep_api:
		if not OWUnicode.is_utf8(world_bytes):   # read leniently: rewritten, a replacement character would take its bytes' place
			out.message = ("world.json in %s is not UTF-8, so its api block cannot be stripped without writing a "
				+ "replacement character over its bytes: save it as UTF-8 first") % folder
			return out
		world.erase("api")
		world_bytes = OWJson.to_bytes(world)
	var files := {WORLD: world_bytes}
	for part in _PARTS:
		if DirAccess.dir_exists_absolute(folder + "/" + part):
			_collect(folder + "/" + part, part, files)
	var records := folder + "/records"
	if DirAccess.dir_exists_absolute(records):
		var left_out := {}
		if not include_private:
			var err := _private_producers(records, left_out)
			if err != "":
				out.message = err
				return out
		var d := _open_dir(records)
		for name in d.get_files():
			if not _is_unity_meta(records, name):
				files["records/" + name] = FileAccess.get_file_as_bytes(records + "/" + name)
		for name in d.get_directories():
			if not left_out.has(OWUnicode.fold(name)):
				_collect_records(records + "/" + name, "records/" + name, files)
	var top := folder.replace("\\", "/").get_file()
	if top == "":
		top = "world"
	var share := {} if include_hidden else leave_out_for_share(files)
	var left := PackedStringArray() if include_author_fields else strip_author_fields(files)
	var packed := pack_files(files, top)
	packed.author_fields_left_out = left
	if not include_hidden:
		packed.hidden_left_out = share["hidden"]
		packed.unread_left_out = share["unread"]
	return packed

# -- the share --------------------------------------------------------------------------------------------------------

## A share's read (folder spec section 4.8, ruled 2026-11-23), done in place on [param files] (paths inside the world
## to bytes): under elements/ and spatial/ nothing stays but a file the folder reader ([method OWWorld.from_files])
## serves as one element, its bytes UTF-8 and its id a non-empty string, with no [code]hidden[/code] mark (a mark is any
## value but absent, null and false). A served element with the mark is erased and named in [code]"hidden"[/code]; every
## other file there is erased and named in [code]"unread"[/code]: one that is not UTF-8 (the folder reader decodes
## leniently; a share reads strictly), not JSON, not an object, has no id or holds a number no double holds; one no
## reader serves (a notes.txt, a file in a deeper folder, a folder that is no type, a name spelled .JSON); and both files
## of an id two files hold, since the share cannot say which file's mark is the element's. Returns
## [code]{"hidden": PackedStringArray, "unread": PackedStringArray}[/code], each in code point order.
static func leave_out_for_share(files: Dictionary) -> Dictionary:
	var view := {}
	for rel: String in files:
		if rel == WORLD or rel.begins_with("elements/") or rel.begins_with("spatial/"):
			view[rel] = files[rel]
	var served := {}   # path -> carries the mark
	var w := OWWorld.from_files(view)
	if w != null:
		var holders := {}   # id -> how many files the strict reader parses as an element hold it
		var candidates: Array = []
		for e in w.elements:
			if e.id != "" and OWUnicode.is_utf8(e.source_bytes):
				holders[e.id] = holders.get(e.id, 0) + 1
				candidates.append(e)
		for rel: String in w.other_files:   # parsed with an id but refused for a number: still a holder of its id
			var id := _parsed_id(rel, w.other_files[rel])
			if id != "":
				holders[id] = holders.get(id, 0) + 1
		for e in candidates:
			if holders[e.id] == 1:
				served[e.source_path] = _is_hidden_mark(e._data)
	var hidden := PackedStringArray()
	var unread := PackedStringArray()
	var rels := files.keys()
	rels.sort()
	for rel: String in rels:
		if not (rel.begins_with("elements/") or rel.begins_with("spatial/")):
			continue
		if served.has(rel) and not served[rel]:
			continue
		if served.has(rel):
			hidden.append(rel)
		else:
			unread.append(rel)
		files.erase(rel)
	return {"hidden": hidden, "unread": unread}

## The id of a file in an element's place that the strict reader parses as an object with a non-empty string id, or "".
static func _parsed_id(rel: String, bytes: PackedByteArray) -> String:
	var segs := rel.split("/")
	if segs.size() != 3 or not OWWorld.ELEMENT_FOLDERS.has(segs[0]) or segs[1].begins_with(".") \
			or segs[2].begins_with(".") or OWWorld._name_refusal(segs[0], segs[1], segs[2]) != "" \
			or not OWUnicode.is_utf8(bytes):
		return ""
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return ""
	var id = json.data.get("id")
	return id if id is String and id != "" else ""

## Section 4.8's hidden mark: any value but absent, null and false (the Unity package's OWPayload.IsHiddenMark).
static func _is_hidden_mark(body: Dictionary) -> bool:
	if not body.has("hidden"):
		return false
	var mark = body["hidden"]
	return mark != null and not (mark is bool and not mark)

# -- author fields ----------------------------------------------------------------------------------------------------

## Which member and which tool wrote an element (a membership id, a door): nothing to someone the world is handed to,
## so a pack leaves them out unless asked. The TypeScript SDK's AUTHOR_FIELDS, in its order.
const AUTHOR_FIELDS := ["created_by", "changed_by", "changed_via", "changed_client", "doors"]
## The deepest nesting the TypeScript SDK reads a file it did not write to (OUTSIDE_JSON_MAX_DEPTH): an object or an
## array at the top is 1.
const OUTSIDE_JSON_MAX_DEPTH := 200

# One JSON token at the scan's offset, white space before it skipped: a string (1), a number (2), a word (3) or a
# mark (4), by RFC 8259's grammar. A string holds no raw character below U+0020 and only JSON's escapes.
static var _token_re: RegEx
static var _end_re: RegEx
static var _plain_re: RegEx
static var _high_re: RegEx
static var _point_zero_re: RegEx

## Leave the author fields out of [param files] (path inside the world -> bytes), in place: every file under
## elements/ or spatial/ that [method without_author_fields] rewrites. Returns their paths, in code point order.
## What [method pack_folder] and [method OWWorld.pack] do unless asked to carry them; [method pack_files] never does.
static func strip_author_fields(files: Dictionary) -> PackedStringArray:
	var left := PackedStringArray()
	var rels: Array = files.keys()
	rels.sort()               # String order is code point order
	var json := JSON.new()
	for rel: String in rels:
		if not (rel.begins_with("elements/") or rel.begins_with("spatial/")):
			continue
		var bare = without_author_fields(files[rel], json)
		if bare != null:
			files[rel] = bare
			left.append(rel)
	return left

## A file without its author fields, in the folder's own form ([method OWJson.to_bytes]: two-space indent, a trailing
## newline, the other keys in their order, no byte order mark), or [code]null[/code] when its bytes travel as they
## are: it holds none of the five at its top level, or it is not one JSON object as the TypeScript SDK reads a file it
## did not write (strict UTF-8, a byte order mark read past, one value by JSON's grammar and nothing after it but white
## space, at most [constant OUTSIDE_JSON_MAX_DEPTH] deep, every number one a double holds), or a rewrite would write
## a value other than JavaScript's. Only top-level keys go: an x_ value that holds one of the names stays.
## [br][br]
## A rewrite never writes a value the file does not hold, nor one JSON.stringify writes differently: each number's
## text must hold the value [method OWJson.number] writes for what Godot's parser read. Godot reads every number as
## a double, and about one long decimal in ten as its neighbour (measured on 4.7.2); OWJson.number writes a few doubles
## with 17 digits where 16 read back; an integer past 2^53 is read rounded. A file holding any of these keeps its
## bytes, the five included. So does one holding the escape of a lone surrogate ([code]"\ud800"[/code]).
static func without_author_fields(bytes: PackedByteArray, json: JSON = null) -> Variant:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	# Cheap first: a file with none of the five names written plainly, and no escape that could spell one, keeps its
	# bytes without a read.
	var ascii := bytes.get_string_from_ascii()
	if not ascii.contains("\\u"):
		var named := false
		for field: String in AUTHOR_FIELDS:
			if ascii.contains("\"" + field + "\""):
				named = true
				break
		if not named:
			return null
	# Bytes all below 0x80 are UTF-8 as they stand: get_string_from_ascii maps each byte to one character (a NUL ends
	# it short), so the same length and no character past 0x7F is exactly that, read natively.
	if _high_re == null:
		_high_re = RegEx.create_from_string("[^\\x01-\\x7f]")
	var plain := ascii.length() == bytes.size() and _high_re.search(ascii) == null
	if not plain and not OWUnicode.is_utf8(bytes):
		return null
	var text := bytes.get_string_from_utf8()
	if json == null:
		json = JSON.new()
	# A plain text (below) is one JSON value whose every number is an integer a double holds, so it skips the token
	# scan and the range walk, and its rewrite is written natively.
	var simple := _is_plain_json(text)
	if not simple and not _is_one_json_value(text, json):
		return null
	if json.parse(text) != OK or not (json.data is Dictionary):
		return null
	if not simple and OWJson.holds_out_of_range(json.data):
		return null
	var doc: Dictionary = json.data
	var present := false
	for field: String in AUTHOR_FIELDS:
		if doc.has(field):
			present = true
			doc.erase(field)
	if not present:
		return null
	return _plain_bytes(doc) if simple else OWJson.to_bytes(doc)

## Whether [param text] is one JSON value in a plain shape, matched natively in one pass: no \u escape, every number
## an integer of at most 15 digits other than -0 (a double holds it, and OWJson.number writes it as written), and too
## few brackets to nest past [constant OUTSIDE_JSON_MAX_DEPTH]. A plain text is one the token scan accepts; a text that
## is not plain may still be one, and only the scan says.
static func _is_plain_json(text: String) -> bool:
	if text.contains("\\u") or text.count("{") + text.count("[") > OUTSIDE_JSON_MAX_DEPTH:
		return false
	if _plain_re == null:
		var ws := '[ \\t\\n\\r]*+'
		var s := '"(?:[^"\\\\\\x00-\\x1f]++|\\\\["\\\\/bfnrt])*+"'
		var member := s + ws + ':' + ws + '(?&v)' + ws
		var item := '(?&v)' + ws
		_plain_re = RegEx.create_from_string('\\A' + ws + '(?<v>\\{' + ws + '(?:' + member + '(?:,' + ws + member
			+ ')*+)?+\\}|\\[' + ws + '(?:' + item + '(?:,' + ws + item + ')*+)?+\\]|' + s
			+ '|(?:0|-?+[1-9][0-9]{0,14}+)(?![0-9.eE])|true|false|null)' + ws + '\\z')
	return _plain_re.search(text) != null

## [method OWJson.to_bytes] for a document read from a plain text ([method _is_plain_json]), written by Godot's own
## JSON.stringify: on that shape the two differ only in that Godot writes each number, a double, with a ".0", which
## comes off every number outside a string. Measured equal to OWJson.to_bytes on every document of Sikelia's.
static func _plain_bytes(doc: Dictionary) -> PackedByteArray:
	if _point_zero_re == null:
		_point_zero_re = RegEx.create_from_string('("(?:[^"\\\\]++|\\\\.)*+")|(-?[0-9]++)\\.0(?![0-9])')
	return (_point_zero_re.sub(JSON.stringify(doc, "  ", false), "$1$2", true) + "\n").to_utf8_buffer()

## Whether [param text] is one JSON value by RFC 8259's grammar, with nothing after it but JSON's white space, nested at
## most [constant OUTSIDE_JSON_MAX_DEPTH] deep, every number one [method OWJson.number] writes back with the value its
## text holds, and no string holding a lone surrogate's escape. No value is built; [param json] reads each number.
static func _is_one_json_value(text: String, json: JSON) -> bool:
	if _is_plain_json(text):    # one native match first; any other text takes the scan below
		return true
	if _token_re == null:
		_token_re = RegEx.create_from_string('\\G[ \\t\\n\\r]*+(?:("(?:[^"\\\\\\x00-\\x1f]++|\\\\["\\\\/bfnrt]|\\\\u[0-9a-fA-F]{4})*+")|(-?(?:0|[1-9][0-9]*+)(?:\\.[0-9]++)?+(?:[eE][+-]?[0-9]++)?+)|(true|false|null)|([{}\\[\\],:]))')
		_end_re = RegEx.create_from_string('\\G[ \\t\\n\\r]*+\\z')
	# What comes next: a value; a key or the close of an object just opened; a key; the colon; a comma or the close;
	# a value or the close of an array just opened.
	const VALUE := 0
	const KEY_OR_CLOSE := 1
	const KEY := 2
	const COLON := 3
	const NEXT := 4
	const VALUE_OR_CLOSE := 5
	var open := PackedByteArray()   # 1 an object, 0 an array, innermost last
	var want := VALUE
	var at := 0
	while true:
		var m := _token_re.search(text, at)
		if m == null:
			return false
		at = m.get_end()
		var done := false     # a value ended here
		if m.get_start(1) >= 0:
			var s := m.get_string(1)
			if s.contains("\\u") and _holds_lone_surrogate(s):
				return false
			if want == KEY_OR_CLOSE or want == KEY:
				want = COLON
			elif want == VALUE or want == VALUE_OR_CLOSE:
				done = true
			else:
				return false
		elif m.get_start(2) >= 0 or m.get_start(3) >= 0:
			if want != VALUE and want != VALUE_OR_CLOSE:
				return false
			if m.get_start(2) >= 0 and not _number_as_written(m.get_string(2), json):
				return false
			done = true
		else:
			var c := m.get_string(4)
			if c == "{" or c == "[":
				if want != VALUE and want != VALUE_OR_CLOSE:
					return false
				if open.size() >= OUTSIDE_JSON_MAX_DEPTH:
					return false
				open.append(1 if c == "{" else 0)
				want = KEY_OR_CLOSE if c == "{" else VALUE_OR_CLOSE
			elif c == "}" or c == "]":
				var obj := c == "}"
				if open.is_empty() or (open[-1] == 1) != obj:
					return false
				if not (want == NEXT or (obj and want == KEY_OR_CLOSE) or (not obj and want == VALUE_OR_CLOSE)):
					return false
				open.resize(open.size() - 1)
				done = true
			elif c == ":":
				if want != COLON:
					return false
				want = VALUE
			else:   # ","
				if want != NEXT:
					return false
				want = KEY if open[-1] == 1 else VALUE
		if done:
			if open.is_empty():
				return _end_re.search(text, at) != null
			want = NEXT
	return false

## Whether the number [param lit] (JSON's grammar) is written back by [method OWJson.number], from what Godot's parser
## reads for it, as a text with the same value: so the rewrite writes what the file holds, in JavaScript's spelling.
static func _number_as_written(lit: String, json: JSON) -> bool:
	if json.parse(lit) != OK:
		return false
	var v = json.data
	if typeof(v) == TYPE_INT:
		return _decimal(str(v)) == _decimal(lit)
	if typeof(v) != TYPE_FLOAT or is_inf(v) or is_nan(v):
		return false
	return _decimal(OWJson.number(v)) == _decimal(lit)

## A JSON number's value as one text: its significant digits and the power of ten before the first ("12.50" and
## "1.25e1" are "125e2"), both zeros "0".
static func _decimal(s: String) -> String:
	var sign := ""
	if s.begins_with("-"):
		sign = "-"
		s = s.substr(1)
	var exp := 0
	var e := s.findn("e")
	if e >= 0:
		var x := s.substr(e + 1)
		if x.length() > 6:     # past any double either way; such a text never reaches here from a double's spelling
			return "?" + s
		exp = x.to_int()
		s = s.substr(0, e)
	var dot := s.find(".")
	var whole := s if dot < 0 else s.substr(0, dot)
	var digits := whole + ("" if dot < 0 else s.substr(dot + 1))
	var point := whole.length() + exp
	var lead := 0
	while lead < digits.length() and digits[lead] == "0":
		lead += 1
	digits = digits.substr(lead).rstrip("0")
	if digits == "":
		return "0"
	return "%s%se%d" % [sign, digits, point - lead]

## Whether a string token (its quotes included) holds a \u escape of a surrogate that is not one half of an escaped
## pair: Godot's parser does not keep one as JSON.parse does, so a rewrite would write another string.
static func _holds_lone_surrogate(s: String) -> bool:
	var pending := false   # the last character was an escaped high surrogate
	var i := 1
	var n := s.length() - 1
	while i < n:
		if s.unicode_at(i) == 0x5C and s.unicode_at(i + 1) == 0x75:
			var unit := s.substr(i + 2, 4).hex_to_int()
			i += 6
			if unit >= 0xDC00 and unit <= 0xDFFF:
				if not pending:
					return true
				pending = false
				continue
			if pending:
				return true
			pending = unit >= 0xD800 and unit <= 0xDBFF
			continue
		if pending:
			return true
		i += 2 if s.unicode_at(i) == 0x5C else 1
	return pending

## Pack exactly the files given (path inside the world -> bytes) under the top folder [param top]: the marker first,
## then every file in UTF-8 byte order, deflated (an empty one stored). Nothing is filtered: what a caller hands in is
## what it asked for (a read archive's files written back, OW-9, a tool's dot-folder included).
static func pack_files(files: Dictionary, top: String) -> Packed:
	var out := Packed.new()
	var rels: Array = files.keys()
	rels.sort()               # String order is code point order, which is UTF-8 byte order (OW-13; measured)
	var zw := OWZip.Writer.new()
	zw.add(MARKER, MEDIA_TYPE.to_ascii_buffer(), false)
	out.names.append(MARKER)
	var pre := "" if top == "" else top + "/"
	for rel in rels:
		var err := zw.add(pre + rel, files[rel], true)
		if err != OK:
			out.message = "could not deflate %s" % rel
			return out
		out.names.append(pre + rel)
	out.bytes = zw.finish()
	out.ok = true
	return out

static func _open_dir(path: String) -> DirAccess:
	var d := DirAccess.open(path)
	if d != null:
		d.include_hidden = true    # a dot-file in records/ is a producer's; Linux and macOS hide it otherwise
	return d

## A content folder: every file but a dot-name (a tool's state) and a .meta (Unity's), recursively.
static func _collect(dir: String, rel: String, into: Dictionary) -> void:
	var d := _open_dir(dir)
	if d == null:
		return
	for name in d.get_files():
		if name.begins_with(".") or name.to_lower().ends_with(".meta"):
			continue
		into[rel + "/" + name] = FileAccess.get_file_as_bytes(dir + "/" + name)
	for name in d.get_directories():
		if not name.begins_with("."):
			_collect(dir + "/" + name, rel + "/" + name, into)

## records/ whole: a producer's files are its own, dot-files and its own .meta included; only Unity's .meta goes.
static func _collect_records(dir: String, rel: String, into: Dictionary) -> void:
	var d := _open_dir(dir)
	if d == null:
		return
	for name in d.get_files():
		if not _is_unity_meta(dir, name):
			into[rel + "/" + name] = FileAccess.get_file_as_bytes(dir + "/" + name)
	for name in d.get_directories():
		_collect_records(dir + "/" + name, rel + "/" + name, into)

static var _unity_meta_head: RegEx

## Unity's own .meta: named after a file or folder beside it, and opening with Unity's two lines.
static func _is_unity_meta(dir: String, name: String) -> bool:
	if not name.to_lower().ends_with(".meta"):
		return false
	var owner := dir + "/" + name.substr(0, name.length() - 5)
	if not FileAccess.file_exists(owner) and not DirAccess.dir_exists_absolute(owner):
		return false
	if _unity_meta_head == null:
		_unity_meta_head = RegEx.create_from_string("\\AfileFormatVersion: [0-9]+\\r?\\nguid: [0-9a-f]{32}\\r?(\\n|\\z)")
	var f := FileAccess.open(dir + "/" + name, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(128)
	f.close()
	return _unity_meta_head.search(head.get_string_from_ascii()) != null

## The producers records/RECORDS.json marks "private": true, each by OW-18's fold. "" or why it cannot be told.
static func _private_producers(records: String, into: Dictionary) -> String:
	var path := records + "/RECORDS.json"
	if not FileAccess.file_exists(path):
		return ""
	var manifest = OWJson.parse_bytes(FileAccess.get_file_as_bytes(path))
	var why := "records/RECORDS.json in %s %s, so which records are private cannot be told; fix it, or pack with include_private"
	if not (manifest is Array):
		return why % [records, "is not a JSON array"]
	for entry in manifest:
		if not (entry is Dictionary):
			return why % [records, "holds an entry that is not an object"]
		if typeof(entry.get("private")) != TYPE_BOOL or not entry["private"]:
			continue          # anything but the boolean true marks nothing
		var producer = entry.get("producer")
		if not (producer is String) or producer == "" or producer == "." or producer == ".." \
				or producer.contains("/") or producer.contains("\\"):
			return why % [records, "marks private an entry whose producer is not one directory name"]
		into[OWUnicode.fold(producer)] = true
	return ""
