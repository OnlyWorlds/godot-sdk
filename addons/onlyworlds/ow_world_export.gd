class_name OWWorldExport
extends RefCounted
## The world export: the one file an owner downloads from their world's page on onlyworlds.com
## ([code]format: onlyworlds-world-export[/code], keel's API spec section 8c).
##
## The file is [code]{format, schema_version, exported_at, world{id, name, …}, elements{slug: [body, …]}}[/code]: the
## owner's whole world, each body as the API serves it, links as ids, extension fields riding along. It carries no
## media (a Map's picture is only its [code]image_url[/code]), no members and no cursor.
##
## [codeblock]
## var r := OWWorldExport.read_file("user://downloads/my-world.json")
## if not r.ok:
##     push_error(r.message)    # r.reason is one of REASONS
## var world := r.to_world()     # read as a world folder is read: of_type, get_element, errors
## [/codeblock]
##
## [method Result.to_world] gives what [method OWWorld.read_folder] gives, so a game opens the download as it opens a
## folder or an [code].owworld[/code], and the folder reader's rules hold: a body's own [code]type[/code], when it is one
## of the 22 slugs exactly, beats the group it sits in; unknown keys are ignored; each body is kept whole, in its key
## order. Inside the elements, what cannot be read is skipped with a line in [member OWWorld.errors] and the rest is
## read: a group that is not one of the 22 slugs as written, a group that is not a list, an entry that is not an object,
## a body with no id (a non-empty String), and of two bodies with one id the second (the first is served).

## The recognition key: a file whose [code]format[/code] is anything else is refused.
const FORMAT := "onlyworlds-world-export"

## The one list of refusal causes. [code]not_openable[/code]: no file. [code]not_json[/code]: not UTF-8, or not one JSON
## value. [code]too_deep[/code]: nested past [constant OWJson.MAX_DEPTH], the file counted whole.
## [code]number_out_of_range[/code]: a number past a double, anywhere in the file. [code]not_an_export[/code]: not a
## JSON object, or its [code]format[/code] is not [constant FORMAT]. [code]no_world_id[/code]: no [code]world[/code]
## object whose [code]id[/code] is a String, non-empty once trimmed.
const REASONS := ["not_openable", "not_json", "too_deep", "number_out_of_range", "not_an_export", "no_world_id"]

## What a read found. [member ok] true: the envelope's stamps, the world block, and [method to_world] and
## [method to_cache]. False: [member reason] (one of [constant REASONS]) and [member message].
class Result:
	var ok := false
	var reason := ""
	## Names the file first ([member source], else "the export").
	var message := ""
	## Where the file came from: [method OWWorldExport.read_file]'s path, or what [method OWWorldExport.read] was told.
	var source := ""
	## Always [constant OWWorldExport.FORMAT] on a read.
	var format := ""
	## The standard's version the elements follow ([code]00.34.01[/code], the API's [code]X-OW-Schema-Version[/code]).
	## Information, never checked: the envelope's shape is keyed by [member format] alone. [code]""[/code] when absent.
	var schema_version := ""
	## When the owner downloaded it, ISO 8601 as written. Information; [code]""[/code] when absent.
	var exported_at := ""
	## The world block whole, in its key order: the World's settings as the API serves them (so the now is
	## [code]time_range_current[/code], the API's name, which [member OWWorldInfo.time_current] does not read), its
	## extension keys, [code]origin[/code], and the download's own [code]source[/code] and [code]exported_as[/code].
	var world: Dictionary = {}
	var world_id := ""
	## The world block's [code]name[/code], [code]""[/code] when it has none.
	var world_name := ""

	var _text := ""

	## The file as an [OWWorld], read as a world folder is ([code]null[/code] on a refusal). Its
	## [member OWWorld.info] is the world block, its elements are in the file's order, each in its type's class, and
	## [member OWWorld.errors] holds one line per skip, [code]<source>#elements/<group>[/<index>]: <why>[/code]. No
	## element has a [member OWElementCore.source_path], so [method OWWorld.write_folder] writes each at the folder
	## format's name (section 3.2). Each call reads the file anew: two worlds, or a world and [method to_cache]'s cache,
	## share no element.
	func to_world() -> OWWorld:
		if not ok:
			return null
		var doc: Dictionary = JSON.parse_string(_text)
		return OWWorldExport._world_of(doc, source if source != "" else "the export")

	## The file as a frozen [OWWorldCache] ([code]null[/code] on a refusal): [member OWWorldCache.read_only], the
	## world's id and name, every element [method to_world] serves. A download carries no cursor, and the API's feed
	## never read it, so no sync can bring it up to date: [OWSync] refuses it, nothing sent. For a copy kept current,
	## sync a cache from the world's key instead.
	func to_cache() -> OWWorldCache:
		var w := to_world()
		if w == null:
			return null
		var cache := OWWorldCache.new(world_id, world_name, true)
		for e in w.elements:
			if not cache.has(e.id):
				cache.upsert(e)
		return cache

## Read a world export from disk (any path Godot can open).
static func read_file(path: String) -> Result:
	if path == "" or not FileAccess.file_exists(path):
		var r := Result.new()
		r.source = path
		return _refuse(r, "not_openable", "no file at %s" % (path if path != "" else "''"))
	return read(FileAccess.get_file_as_bytes(path), path)

## Read a world export's bytes (a download's body, a file's contents). [param source] names it in [member Result.message]
## and in each skip's line. A byte order mark at the start is read past.
static func read(bytes: PackedByteArray, source := "") -> Result:
	var r := Result.new()
	r.source = source
	var text = OWUnicode.decode_utf8(bytes)
	if text == null:
		return _refuse(r, "not_json", "is not JSON: its bytes are not UTF-8")
	if OWJson.opens_past(text):        # counted in the text before any parse, as an element file is (OW-25)
		return _refuse(r, "too_deep", "is refused, " + OWJson.TOO_DEEP_WHY)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _refuse(r, "not_json", "is not JSON (%s, line %d)" % [json.get_error_message(), json.get_error_line()])
	var doc = json.data
	if OWJson.holds_out_of_range(doc):  # the file is one JSON text, read whole
		return _refuse(r, "number_out_of_range", "is refused, " + OWJson.OUT_OF_RANGE_WHY)
	if not (doc is Dictionary):
		return _refuse(r, "not_an_export", "is not an OnlyWorlds world export: not a JSON object")
	var format = doc.get("format")
	if not (format is String and format == FORMAT):
		return _refuse(r, "not_an_export", "is not an OnlyWorlds world export (format is '%s', not '%s')" \
			% [format if format is String else "missing", FORMAT])
	var world = doc.get("world")
	var wid = world.get("id") if world is Dictionary else null
	if not (wid is String) or OWUnicode.strip_ws(wid) == "":
		return _refuse(r, "no_world_id", "has no world id (a non-empty String): a world without one cannot be keyed or compared")
	r.ok = true
	r.format = format
	r.schema_version = _string(doc.get("schema_version"))
	r.exported_at = _string(doc.get("exported_at"))
	r.world = world
	r.world_id = wid
	r.world_name = _string(world.get("name"))
	r._text = text
	r.message = "%s: world %s" % [_where(r), wid]
	return r

static func _where(r: Result) -> String:
	return r.source if r.source != "" else "the export"

static func _refuse(r: Result, reason: String, message: String) -> Result:
	r.ok = false
	r.reason = reason
	r.message = "%s %s" % [_where(r), message]
	return r

static func _string(v: Variant) -> String:
	return v if v is String else ""

## The world a parsed export holds, read as a folder is; [param where] names each skip's place.
static func _world_of(doc: Dictionary, where: String) -> OWWorld:
	var w := OWWorld.new()
	w.info = OWWorldInfo.new(doc["world"])
	var groups = doc.get("elements")
	if not (groups is Dictionary):
		return w                         # no elements key: an export of an empty world (section 8c: absence is zero)
	for key: String in groups:
		var at := "%s#elements/%s" % [where, key]
		if not OWTypes.SCRIPTS.has(key):
			w.errors.append("%s: not read: %s is no type (a group is named by one of the 22 type words, in lower case)" % [at, key])
			continue
		var list = groups[key]
		if not (list is Array):
			w.errors.append("%s: not a list" % at)
			continue
		for i in list.size():
			var body = list[i]
			if not (body is Dictionary):
				w.errors.append("%s/%d: not an object" % [at, i])
				continue
			var id = body.get("id")
			if not (id is String and id != ""):
				w.errors.append("%s/%d: no id in body" % [at, i])
				continue
			w._add_body("%s/%d" % [at, i], key, body)
	return w
