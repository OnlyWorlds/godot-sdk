class_name OWFolderExport
extends RefCounted
## An onlyworlds.com world, read over the API, written as a world folder: an offline copy a game can ship or open
## later. The folder is the one the onlyworlds Python package's [code]export_world[/code] writes and the Unity SDK's
## [code]OWFolderExport[/code] writes, element files byte for byte.
##
## [codeblock]
## var client := OWClient.new({"api_key": "ow_r_...", "api_pin": ""})
## var report := await OWFolderExport.export(client, "user://worlds/my-world")
## if not report.ok:
##     push_error(report.message)        # report.error: the client's OWApiError when the server said no
## var world := OWWorld.read_folder(report.folder)
## [/codeblock]
##
## Only GETs: the world is never written. [code]GET /world/[/code], then [code]GET /me/[/code] (which part of the world
## the key reads), then every element of the 22 types, page by page, all read before the first file is written.
##
## [b]world.json[/b] is the [code]GET /world/[/code] body, every key in the order served ([method world_for_disk]: the now
## renamed [code]time_current[/code], [code]format_version[/code] added), with this export's provenance (folder spec
## section 4.2): [code]source[/code] (which server, which world, when the export began), [code]exported_as[/code] when
## [code]GET /me/[/code] can say which slice the key reads ([method exported_as]), and [code]producer[/code]
## ([method producer]). A world's [code]origin[/code], its first import as the server keeps it, rides along as served.
##
## [b]Elements[/b] are written as served, extension keys and the served-trimmed mark ([code]x_served_trimmed[/code])
## included; a known-of stub without its unset fields ([method known_of_for_disk]). Within a type a repeated id keeps
## its last body: a page walk that met a write serves an element twice, never skips one, and the later copy is the
## newer. File names follow the folder format (section 3.2), the collision rule included.
##
## [b]A folder is born whole or not at all.[/b] The folder must not exist, or be an empty directory. The tree is built
## in a sibling directory ([code].ow-<8 hex>[/code]) and moved into place as the last step, so a refusal leaves the
## folder as it was. Refused, with nothing written: an element with no id, one id under two types, an id that cannot
## be one file name in its type folder ([method OWWorld.write_refusal]), a world with no id or name.
##
## Not kept: Map images (the folder has their [code]image_url[/code]). Godot reads every JSON number as a double, so an
## integer past 2^53 in the world is written rounded, where the Python package writes every digit.

## The folder format version an export declares in world.json: the dist's folder check's [code]FORMAT_VERSION[/code].
const FORMAT_VERSION := "0.3.25"
## The name this addon's releases publish under ([code]onlyworlds-godot-X.Y.Z.zip[/code]): the [code]tool[/code] of
## the [code]producer[/code] line.
const PRODUCER_TOOL := "onlyworlds-godot"
## This addon's version, as [code]plugin.cfg[/code] says (a test holds the two equal): the [code]version[/code] of the
## [code]producer[/code] line.
const PRODUCER_VERSION := "0.14.0"
## The keys every known-of stub keeps, written even when empty (folder spec section 4.4).
const KNOWN_OF_KEEPS := ["id", "type", "name", "description", "supertype", "subtype", "image_url", "created_at",
	"updated_at", "change_seq"]
## The member roles whose slice is the role's, with no Character ([code]co_builder[/code] as keel serves it).
const MEMBER_ROLES := ["co_builder", "contributor"]
## Wire key to disk key for world.json (folder spec section 5).
const WIRE_TO_DISK_WORLD_KEYS := {"time_range_current": "time_current"}

const _OPTION_KEYS := ["clock", "on_progress"]

## What [method export] did.
class Report:
	## True when the folder was written.
	var ok := false
	## Why not, when [member ok] is false; "" when it is true.
	var message := ""
	## The client's error when a read was refused or got no answer ([method OWApiError.is_auth_error] for a wrong key or
	## PIN); null otherwise.
	var error: OWApiError = null
	## The folder, absolute.
	var folder := ""
	## The world's id and name, from its world.json.
	var world_id := ""
	var world_name := ""
	## Elements written per type slug, types with none left out.
	var counts := {}

	## Every element written.
	func total() -> int:
		var n := 0
		for type in counts:
			n += counts[type]
		return n

## The [code]producer[/code] line every folder [method export] makes carries (folder spec section 4.2):
## [code]{"tool": "onlyworlds-godot", "version": "<this addon's>", "input": "server"}[/code], the spec's key order,
## [code]server[/code] its word for an export from onlyworlds.com. A new Dictionary on every call.
static func producer() -> Dictionary:
	return {"tool": PRODUCER_TOOL, "version": PRODUCER_VERSION, "input": "server"}

## True for a known-of stub: [code]known_of[/code] is the JSON true. Anything else is a whole element.
static func is_known_of(body: Dictionary) -> bool:
	var v: Variant = body.get("known_of")
	return typeof(v) == TYPE_BOOL and v

## A known-of stub as the folder format writes it (section 4.4), its keys in received order, then
## [code]known_of: true[/code]: every [constant KNOWN_OF_KEEPS] key, and every other key the server sent with a value.
## The unset values keel serves on a stub ([code]""[/code], [code]null[/code], [code][][/code]) are left out: on disk
## they would read as a whole element with nothing filled in. [code]0[/code] and [code]false[/code] are values. The
## input is not changed.
static func known_of_for_disk(body: Dictionary) -> Dictionary:
	var disk := {}
	for key: String in body:
		if key == "known_of":
			continue
		var v: Variant = body[key]
		if KNOWN_OF_KEEPS.has(key) or _is_set(v):
			disk[key] = _copy(v)
	disk["known_of"] = true
	return disk

static func _is_set(v: Variant) -> bool:
	if v == null:
		return false
	if v is String:
		return v != ""
	if v is Array:
		return not v.is_empty()
	return true

## Why [param world] cannot be a world.json, or "": it needs an id that is a non-empty String and a name that is a
## String, which may be empty (folder spec section 4.1).
static func world_refusal(world: Dictionary) -> String:
	var id: Variant = world.get("id")
	if not (id is String and id != ""):
		return "world.json requires a non-empty string id (folder spec section 4.1)"
	if not (world.get("name") is String):
		return "world.json requires a string name, which may be empty (folder spec section 4.1)"
	return ""

## The world.json for a [code]GET /world/[/code] body (or a world.json read from a folder): every key carried in
## received order, [code]time_range_current[/code] renamed [code]time_current[/code] in place (both kept when both are
## there: dropping either would be a drop), [code]format_version[/code] added when absent (a carried one is kept, even
## null). [code]snapshot_counts[/code] belongs to snapshots alone: recounted from [param counts] (type to count) when the
## body has [code]snapshot_of[/code], else removed. [code]origin[/code] and the World's extension keys ride along. The
## input is not changed. [code]null[/code] when [method world_refusal] refuses the body.
static func world_for_disk(world: Dictionary, counts: Variant = null) -> Variant:
	if world_refusal(world) != "":
		return null
	var disk := {}
	for key: String in world:
		var to: String = WIRE_TO_DISK_WORLD_KEYS.get(key, key)
		disk[key if world.has(to) else to] = _copy(world[key])
	if disk.has("snapshot_counts"):
		if disk.has("snapshot_of") and counts is Dictionary:
			var recount := {}
			for type in counts:
				if counts[type] != 0:
					recount[type] = counts[type]
			disk["snapshot_counts"] = recount
		else:
			disk.erase("snapshot_counts")
	if not disk.has("format_version"):
		disk["format_version"] = FORMAT_VERSION
	return disk

## The [code]exported_as[/code] line (folder spec section 4.2) for a [code]GET /me/[/code] answer, or [code]null[/code]:
## write none. [code]kind: owner[/code] (an owner-minted or classic key) is the owner, role owner, no Character; a
## member with role [code]co_builder[/code] or [code]contributor[/code] is a member, its role, no Character; a guest of
## any kind (person, agent seat, player) is its Character, [code]{id, name}[/code], the name from
## [param character_name] (called with the id, answering a String or null). Anything else is null: no answer, a guest
## with no Character, a name that cannot be read, a kind or role this table does not name. An empty name is a name the
## server served, and is written.
static func exported_as(me: Variant, character_name: Callable) -> Variant:
	if not (me is Dictionary):
		return null
	var kind: Variant = me.get("kind")
	var role: Variant = me.get("role")
	if kind is String and kind == "owner":
		return {"kind": "owner", "role": "owner", "character": null}
	if role is String and MEMBER_ROLES.has(role):
		return {"kind": "member", "role": role, "character": null}
	if not (role is String and role == "guest"):
		return null
	var id: Variant = me.get("character")
	if not (id is String and id != ""):
		return null
	var name: Variant = character_name.call(id)
	if not (name is String):
		return null
	return {"kind": "character", "role": "guest", "character": {"id": id, "name": name}}

## Read the world [param client]'s key reaches and write it as a world folder at [param folder] (an absolute path, or
## [code]user://[/code] or [code]res://[/code]), which must not exist or be an empty directory; its parents are made.
## Await it. [param options], each optional: [code]clock[/code], a Callable answering the time as Unix seconds (a float),
## read once for [code]source.at[/code] before the first request (the system's when not given); [code]on_progress[/code],
## a Callable told [code](type, done, total)[/code] after each of the 22 types is read. See the class for what is written
## and what is refused.
static func export(client: OWClient, folder: String, options: Dictionary = {}) -> Report:
	var report := Report.new()
	for key in options:
		if not _OPTION_KEYS.has(key):
			return _refuse(report, "OWFolderExport.export: '%s' is not an option (%s). Nothing was read." % [key, ", ".join(_OPTION_KEYS)])
	var root := _root_of(folder)
	report.folder = root
	if root == "" or root.get_base_dir() == root or root.get_base_dir() == "":
		return _refuse(report, "'%s' has no parent directory to build the folder beside. Nothing was read." % folder)
	var occupied := _occupied(root)
	if occupied != "":
		return _refuse(report, occupied + " Nothing was read.")

	# -- Read everything first ----------------------------------------------------------------------------------------
	var clock: Callable = options.get("clock", Callable())
	var at := _iso(clock.call() if clock.is_valid() else Time.get_unix_time_from_system())
	var r := await client.get_world()
	if not r.ok:
		return _failed(report, r.error)
	if not (r.value is Dictionary):
		return _refuse(report, "GET /world/ answered no world object.")
	var world: Dictionary = (r.value as Dictionary).duplicate(true)
	var slice: Variant = await _exported_as_of(client)

	# The provenance lines after the wire's keys. An export is a folder's birth, so source and producer are this
	# export's own: a body that already carries either names the maker of another folder, and its line is replaced where
	# it stands. origin, the world's first import, is the server's and rides along as served.
	world["source"] = {"server": _origin(client.base_url), "world": world.get("id"), "at": at}
	if slice != null:
		world["exported_as"] = slice
	world["producer"] = producer()

	var types := OWTypes.slugs()
	var by_type := {}
	var on_progress: Callable = options.get("on_progress", Callable())
	for i in types.size():
		var listed := await client.list_all(types[i])
		if not listed.ok:
			return _failed(report, listed.error)
		var rows: Array = []
		for e: OWElement in listed.value:
			rows.append(e.to_dict())
		if not rows.is_empty():
			by_type[types[i]] = rows
		if on_progress.is_valid():
			on_progress.call(types[i], i + 1, types.size())

	# -- Settle what will be written, before any disk ------------------------------------------------------------------
	var owner := {}
	var elements := {}   # type -> (id -> body), each id once, a repeat keeping its last body at its last place
	for type in types:
		if not by_type.has(type):
			continue
		var slot := {}
		for body: Dictionary in by_type[type]:
			var id: Variant = body.get("id")
			if not (id is String and id != ""):
				return _refuse(report, "A %s element came back without a non-empty string id; nothing was written." % type)
			if owner.has(id) and owner[id] != type:
				return _refuse(report, "Element id %s came back under both %s and %s; nothing was written." % [id, owner[id], type])
			owner[id] = type
			slot.erase(id)
			slot[id] = body
		elements[type] = slot
	for type in elements:
		report.counts[type] = elements[type].size()
	var disk: Variant = world_for_disk(world, report.counts)
	if disk == null:
		return _refuse(report, world_refusal(world) + "; nothing was written.")

	var w := OWWorld.from_files({"world.json": OWJson.to_bytes(disk)})
	for type in types:
		if not elements.has(type):
			continue
		for id in elements[type]:
			var body: Dictionary = elements[type][id]
			w.add_element(OWTypes.make(type, known_of_for_disk(body) if is_known_of(body) else body))
	var why := w.write_refusal()
	if why != "":
		return _refuse(report, why + " Nothing was written.")

	# -- Build beside, then move into place ----------------------------------------------------------------------------
	var temp := root.get_base_dir() + "/.ow-" + Crypto.new().generate_random_bytes(4).hex_encode()
	var made := DirAccess.make_dir_recursive_absolute(temp)
	if made != OK:
		return _refuse(report, "could not make %s (%s); nothing was written." % [temp, error_string(made)])
	var wrote := w.write_folder(temp)
	if wrote != OK:
		_remove_tree(temp)
		return _refuse(report, "could not write the world into %s (%s); nothing was left." % [temp, error_string(wrote)])
	# Checked again: the folder may have been filled while the world was read.
	occupied = _occupied(root)
	if occupied != "":
		_remove_tree(temp)
		return _refuse(report, occupied + " Nothing was written.")
	if DirAccess.dir_exists_absolute(root):
		DirAccess.remove_absolute(root)
	var moved := DirAccess.rename_absolute(temp, root)
	if moved != OK:
		_remove_tree(temp)
		return _refuse(report, "could not move the built world to %s (%s); nothing was left." % [root, error_string(moved)])

	report.ok = true
	report.world_id = disk["id"]
	report.world_name = disk["name"]
	return report

## exported_as for the client's key: GET /me/, and for a guest its Character's name. A refusal or a body that is not
## what was asked gives null; so does a client that names its world (an account token or no key), which has no /me.
static func _exported_as_of(client: OWClient) -> Variant:
	if client.world != "":
		return null
	var me := await client.me()
	if not me.ok or not (me.value is Dictionary):
		return null
	var name: Variant = null
	var role: Variant = me.value.get("role")
	var cid: Variant = me.value.get("character")
	if role is String and role == "guest" and cid is String and cid != "":
		var c := await client.get_element("character", cid)
		if c.ok:
			var n: Variant = (c.value as OWElement).to_dict().get("name")
			name = n if n is String else null
	return exported_as(me.value, func(_id): return name)

## Why [param root] cannot be written, or "": it exists and is not an empty directory.
static func _occupied(root: String) -> String:
	var full := false
	if FileAccess.file_exists(root):
		full = true
	elif DirAccess.dir_exists_absolute(root):
		var d := DirAccess.open(root)
		if d != null:
			d.include_hidden = true
			d.include_navigational = false
			full = not d.get_files().is_empty() or not d.get_directories().is_empty()
	if full:
		return "'%s' exists and is not an empty directory; a world folder is written whole, once." % root
	return ""

static func _root_of(folder: String) -> String:
	if folder == "":
		return ""
	var path := folder
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	path = path.replace("\\", "/").simplify_path()
	while path.length() > 1 and path.ends_with("/"):
		path = path.trim_suffix("/")
	return path

## The scheme and host of the API's base URL ([code]https://www.onlyworlds.com[/code]), with its port when it names one.
static func _origin(base_url: String) -> String:
	var scheme := base_url.find("://")
	if scheme < 0:
		return base_url
	var slash := base_url.find("/", scheme + 3)
	return base_url if slash < 0 else base_url.substr(0, slash)

## Unix seconds as JavaScript's toISOString writes them: UTC, milliseconds, Z.
static func _iso(unix: float) -> String:
	var ms := int(round(unix * 1000.0))
	var seconds := floori(ms / 1000.0)
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(seconds, false), ms - seconds * 1000]

static func _copy(v: Variant) -> Variant:
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v

static func _refuse(report: Report, message: String) -> Report:
	report.ok = false
	report.message = message
	report.counts = {}
	return report

static func _failed(report: Report, error: OWApiError) -> Report:
	_refuse(report, str(error))
	report.error = error
	return report

static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_tree(path + "/" + sub)
	DirAccess.remove_absolute(path)
