class_name OWWorldCache
extends RefCounted
## One world held by a game, kept current from the API by [OWSync], and kept between launches in a file of its own
## ([method write_file], [method read_file]). It reads as [OWWorld] reads ([method get_element], [method of_type]), so
## a game's reading code is the same against either; it holds no folder, and writes none.
##
## [codeblock]
## var client := OWClient.new({"api_key": "ow_r_..."})
## var world := OWWorldCache.read_file("user://world.owcache")   # empty the first time
## var r := await OWSync.incremental(client, world)             # the first call walks the whole world, later ones the changes
## if r.ok: world.write_file("user://world.owcache")
## for c: OWCharacter in world.of_type("character"): print(c.name)
## [/codeblock]
##
## Each element is held in its type's own model ([method OWTypes.make]), its body whole: [method OWElementCore.to_dict]
## is the body as served, extension fields included. Beside the elements, where the last sync stopped: [member cursor],
## [member cursor_token] and [member epoch]. Mirrors the Unity SDK's [code]OWWorldCache[/code].

## The file's [code]format[/code] key, which [method read_file] checks.
const FORMAT := "onlyworlds-godot-cache"
## The file's [code]version[/code].
const VERSION := 1

## The world's id, as the game names it (informational: a sync does not check it).
var world_id := ""
var world_name := ""
## A frozen snapshot, never to be written into: [OWSync] refuses it, nothing sent. Consumers must honour it.
var read_only := false
## The [code]change_seq[/code] the last sync reached; 0 before any.
var cursor: int:
	get: return _cursor
## The feed's own cursor where the last sync stopped, opaque, as the server sent it; [code]""[/code] when there is none,
## and a sync then resumes from [member cursor].
var cursor_token: String:
	get: return _cursor_token
## The view epoch the last sync ran under (an int): a guest's or a contributor's key; [code]null[/code] for the others.
var epoch: Variant:
	get: return _epoch
## When the last sync stopped (ISO 8601, UTC), [code]""[/code] before any.
var synced_at: String:
	get: return _synced_at

var _cursor := 0
var _cursor_token := ""
var _epoch: Variant = null
var _synced_at := ""
## Ids in the order first held; [member _by_id] holds the element.
var _ids: Array[String] = []
var _by_id: Dictionary = {}

func _init(id := "", name := "", frozen := false) -> void:
	world_id = id
	world_name = name
	read_only = frozen

## How many elements are held.
func count() -> int:
	return _ids.size()

## The element with this id, or [code]null[/code].
func get_element(id: String) -> OWElement:
	return _by_id.get(id)

## True when an element with this id is held.
func has(id: String) -> bool:
	return _by_id.has(id)

## True when the id is held as a known-of stub ([code]known_of: true[/code], folder format section 4.4): a model whose
## unset fields read as empty, exactly as a whole element with nothing filled in would. False for a whole element and
## for an id not held.
func is_known_of(id: String) -> bool:
	var e: OWElement = _by_id.get(id)
	return e != null and e.to_dict().get("known_of") == true

## Every element held, in the order first held.
func elements() -> Array[OWElement]:
	var out: Array[OWElement] = []
	for id in _ids:
		out.append(_by_id[id])
	return out

## Every element of one type ([code]"pin"[/code]), in the order first held.
func of_type(type: String) -> Array[OWElement]:
	var out: Array[OWElement] = []
	for id in _ids:
		var e: OWElement = _by_id[id]
		if e.get_type() == type:
			out.append(e)
	return out

## The elements a list of ids names (an Array or a link field's [PackedStringArray]), in its order, skipping the ids
## not held: a dangling link is normal (a partial sync, a sparse read), and [method has] says which.
func resolve(ids: Variant) -> Array[OWElement]:
	var out: Array[OWElement] = []
	if not (ids is Array or ids is PackedStringArray):
		return out
	for id in ids:
		var e: OWElement = _by_id.get(id) if id is String else null
		if e != null:
			out.append(e)
	return out

## Hold [param element] under its own id, replacing the one held there; its type is its model's, so an element whose
## type changed moves with it. False, and nothing held, for an element with no id.
func upsert(element: OWElement) -> bool:
	if element == null or element.id == "":
		return false
	if not _by_id.has(element.id):
		_ids.append(element.id)
	_by_id[element.id] = element
	return true

## Let go of the element with this id. False when none was held.
func remove(id: String) -> bool:
	if not _by_id.has(id):
		return false
	_by_id.erase(id)
	_ids.erase(id)
	return true

## Let go of every element, and of where the last sync stopped ([member cursor], [member cursor_token],
## [member epoch]). The world's id, name and [member read_only] stay.
func clear() -> void:
	_ids.clear()
	_by_id.clear()
	_cursor = 0
	_cursor_token = ""
	_epoch = null

## Record where a sync stopped: the [code]change_seq[/code], the server's cursor, the view epoch, the time. A bare
## [param seq] drops any token and epoch held, since a token beside a seq set by hand would resume from the wrong place.
func set_cursor(seq: int, token := "", view_epoch: Variant = null, at := "") -> void:
	_cursor = seq
	_cursor_token = token
	_epoch = view_epoch
	_synced_at = at

## Write the cache to [param path] as one JSON file ([OWJson]'s form): the world's id and name, [member read_only], where
## the last sync stopped, and every element's type and body. An [enum Error] from opening the file, else [constant OK].
func write_file(path: String) -> Error:
	var rows := []
	for id in _ids:
		var e: OWElement = _by_id[id]
		rows.append({"type": String(e.get_type()), "element": e.to_dict()})
	var doc := {"format": FORMAT, "version": VERSION, "world_id": world_id, "world_name": world_name,
		"read_only": read_only, "cursor": _cursor, "cursor_token": _cursor_token, "epoch": _epoch,
		"synced_at": _synced_at, "elements": rows}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(OWJson.to_bytes(doc))
	f.close()
	return OK

## A cache read from [param path], as [method write_file] wrote it: an empty cache when there is no file (a first
## launch), [code]null[/code] when the file is not a cache's (not JSON, another [code]format[/code], a newer
## [code]version[/code]). A key the file lacks reads as unset: a file with no [code]cursor_token[/code] resumes from its
## [code]cursor[/code].
static func read_file(path: String) -> OWWorldCache:
	if not FileAccess.file_exists(path):
		return OWWorldCache.new()
	var doc = OWJson.parse_bytes(FileAccess.get_file_as_bytes(path))
	if not (doc is Dictionary) or doc.get("format") != FORMAT or not _is_number(doc.get("version")) \
			or int(doc["version"]) > VERSION:
		return null
	var out := OWWorldCache.new(_string(doc.get("world_id")), _string(doc.get("world_name")), doc.get("read_only") == true)
	var e = doc.get("epoch")
	out.set_cursor(int(doc["cursor"]) if _is_number(doc.get("cursor")) else 0, _string(doc.get("cursor_token")),
		int(e) if _is_number(e) else null, _string(doc.get("synced_at")))
	var rows = doc.get("elements")
	if rows is Array:
		for row in rows:
			if row is Dictionary and row.get("type") is String and row.get("element") is Dictionary:
				out.upsert(OWTypes.make(row["type"], row["element"]))
	return out

static func _is_number(v: Variant) -> bool:
	return v is int or v is float

static func _string(v: Variant) -> String:
	return v if v is String else ""
