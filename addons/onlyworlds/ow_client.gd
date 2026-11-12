class_name OWClient
extends RefCounted
## A thin client for the OnlyWorlds v2 API (keel, onlyworlds.com): reads a world over the network into the SDK's own
## element models, and writes its elements back. Deliberately thin: no cache, no sync state, no retry. What it holds is
## the wire's contract: which header carries which credential, where the PIN goes and where it never goes, what a key
## may send at all (refused here, nothing sent, rather than a 401 from keel), opaque cursors, the cursor walk driven by
## [code]has_more[/code], a write's body cleaned of what keel refuses, client-minted ids, and keel's error envelope as
## an [OWApiError].
##
## [codeblock]
## var client := OWClient.new({"api_key": "ow_r_...", "api_pin": ""})   # client.error: "" when built
## var r := await client.list_all("character")
## if not r.ok:
##     push_error(str(r.error))                                         # OnlyWorlds API 401 [invalid_credentials]: ...
##     return
## for c: OWCharacter in r.value:
##     print(c.name)
## var reader := OWClient.new({"world": world_id})                     # no key: a public world, as the public reads it
## [/codeblock]
##
## Every call returns through [code]await[/code] and answers a [Reply]: [member Reply.value] on success, else
## [member Reply.error]. The credential rules are the Unity SDK's [code]OWClient[/code] and the TypeScript SDK's
## [code]OwV2Client[/code], one rule: a world key ([code]ow_w_[/code], [code]ow_r_[/code], a 10-digit legacy key) is
## sent as [code]API-Key[/code], its PIN as [code]API-Pin[/code] only on [code]GET /me[/code] among the reads (keel
## verifies a PIN wherever it is sent, at a cost) and on every request of a legacy key; an account token
## ([code]ow_a_[/code]) as a Bearer, never with the PIN, and only on the reads that name a world with
## [code]world=[/code] (set [code]world[/code] in the config) and the roster; no key at all reads a public world the same
## way. The health pulse carries no credential. The writes ([method create], [method upsert], [method patch],
## [method delete], [method edit_links], [method bulk]) go with the PIN, [code]X-OW-Client[/code] (the config's
## [code]client[/code]) and, on a client the config declares an agent, [code]X-OW-Agent[/code]; an account token and a
## keyless client write nothing. Mirrors the TypeScript SDK's [code]OwV2Client[/code].
##
## [codeblock]
## var writer := OWClient.new({"api_key": "ow_w_...", "api_pin": "1234", "client": "my-game"})
## var made := await writer.create("character", {"name": "Ana"})            # the id minted here, a UUIDv7
## var r := await writer.patch("character", made.value.id, {"level": 4}, {"if_match": seq})
## if r.error and r.error.is_precondition_failed():
##     print(r.error.current())                                             # someone wrote first: the element now
## await writer.edit_links("character", made.value.id, "friends", {"add": [bo_id]})
## [/codeblock]

const DEFAULT_BASE_URL := "https://www.onlyworlds.com/api/v2"
## The name sent as [code]X-OW-Client[/code] on element writes when the config gives none.
const DEFAULT_CLIENT_NAME := "godot-sdk"
## Keys a write never sends: keel refuses them (a 422) or names them itself ([code]world[/code] from the key). A
## blacklist that must never become a whitelist: extension keys ([code]x_*[/code]) pass through every write untouched.
## The Unity SDK's [code]OWPayload.ReadOnlyFields[/code], the TypeScript SDK's [code]READ_ONLY_FIELDS[/code].
const READ_ONLY_FIELDS := ["world", "type", "created_at", "updated_at", "change_seq", "known_of"]
## The key kinds, as [method key_kind_of] reads them.
const KEY_WRITE := "write"
const KEY_READ := "read"
const KEY_ACCOUNT := "account"
const KEY_LEGACY := "legacy"
const KEY_UNKNOWN := "unknown"
const KEY_NONE := "none"
## keel's cap on one page of the change feed; past it keel answers 422, where the element lists clamp.
const MAX_CHANGES_LIMIT := 1000

const _CONFIG_KEYS := ["api_key", "api_pin", "world", "base_url", "page_size", "transport", "agent", "client"]
const _LIST_KEYS := ["limit", "cursor", "expand", "fields", "ids", "created_by", "name", "name_contains", "supertype",
	"subtype", "filter", "view_as"]
const _GET_KEYS := ["expand", "fields", "view_as"]
const _CHANGES_KEYS := ["since", "after"]
const _CREATE_KEYS := ["idempotency_key"]
const _IF_MATCH_KEYS := ["if_match"]
const _EDIT_KEYS := ["add", "remove"]
const _BULK_KEYS := ["atomic", "idempotency_key"]
const _WORLD_READS := "list, list_all, get_element and get_world"
## Around the refusal [method _seg] puts in a path for a value that is not one segment.
const _REFUSED_OPEN := "\u0001"
const _REFUSED_CLOSE := "\u0002"
static var _path_type: RegEx
static var _path_value: RegEx

## Why the client was not built ("" when it was): a config it refuses. Every call then answers that refusal and
## sends nothing.
var error := ""
## keel's API root, trailing slashes trimmed.
var base_url := DEFAULT_BASE_URL
## Elements a page; keel clamps at 1000 silently.
var page_size := 100
## The key's kind, one of the [code]KEY_*[/code] words; [constant KEY_NONE] for a keyless reader.
var key_kind := KEY_NONE
## The world an account token or a keyless client reads, or "".
var world := ""
## What the requests go through: the config's, else an [OWHttpTransport].
var transport: OWTransport
## The name this client sends as [code]X-OW-Client[/code] on element writes, and on no read: keel stores it on the
## element ([code]changed_client[/code]) and on a feed's delete row, so a reader can tell which tool made a change.
var client_name := DEFAULT_CLIENT_NAME
## True when the config declares this client an AI agent: every element write carries [code]X-OW-Agent[/code], and
## keel records it as agent-made. It describes the caller, so only the caller sets it; off in a tool people use. An
## agent seat's key is recorded as an agent without it.
var agent := false

var _api_key := ""
var _api_pin := ""
## The last tip read's ETag ("" when it sent none) and the tip its 200 answered, which a 304 hands back.
var _head_tag := ""
var _head_held: ChangesPage = null

## What a call answers: [member value] when it succeeded, else [member error] says why. [member response] is the
## transport's response when one came (an error's status and headers beside it), null when nothing was sent.
class Reply:
	var value: Variant = null
	var error: OWApiError = null
	var response: OWTransport.Response = null
	## True when the call succeeded.
	var ok: bool:
		get: return error == null

	static func of(v: Variant, r: OWTransport.Response = null) -> Reply:
		var out := Reply.new()
		out.value = v
		out.response = r
		return out

	static func failed(e: OWApiError, r: OWTransport.Response = null) -> Reply:
		var out := Reply.new()
		out.error = e
		out.response = r
		return out

## One cursor page of a type: [code]{data, has_more, next_cursor}[/code]. A page shorter than asked is no end: keel
## clamps the limit at 1000 silently, so walk by [member has_more] (as [method OWClient.list_all] does).
class Page:
	## The keys this reads from keel's answer (held to keel's document by the wire tests).
	const KEYS := ["data", "has_more", "next_cursor"]
	## The rows, each in its type's own model ([OWTypes.make]).
	var data: Array[OWElement] = []
	var has_more := false
	## The opaque cursor of the next page, "" when there is none. Pass it back as is.
	var next_cursor := ""

## One row of the change feed: an upsert carries the element whole, a delete its type and id.
class Change:
	## The keys this reads from a row of keel's answer.
	const KEYS := ["op", "type", "id", "change_seq", "updated_at", "changed_at", "changed_by", "changed_via", "element",
		"deleted_at", "deleted_by", "deleted_via", "deleted_client", "reason"]
	## [code]upsert[/code] or [code]delete[/code].
	var op := ""
	var type := ""
	var id := ""
	## The change's place in the world's feed.
	var change_seq := 0
	## On an upsert: when the element changed.
	var updated_at: Variant = null
	## On a hide's or an unhide's upsert row only: when, by whom (a membership id, null for the owner), by which door.
	var changed_at: Variant = null
	var changed_by: Variant = null
	var changed_via: Variant = null
	## On an upsert: the element as [code]GET /{type}/{id}[/code] serves it, in its type's model; null on a delete.
	var element: OWElement = null
	## On a delete: when, by which membership (null for the owner), through which door, the deleting client's name.
	var deleted_at: Variant = null
	var deleted_by: Variant = null
	var deleted_via: Variant = null
	var deleted_client: Variant = null
	## On a delete: why ([code]hidden[/code] for an element that left this key's view), or null.
	var reason: Variant = null

## A page of the change feed, or its tip ([method OWClient.changes_head]). World-settings edits are not in the feed:
## poll [method OWClient.get_world]'s [code]updated_at[/code] for them.
class ChangesPage:
	## The keys this reads from keel's answer.
	const KEYS := ["cursor", "changes", "has_more", "head", "epoch", "epoch_reason"]
	## Where the next page starts: pass it back as [code]since[/code]. Opaque: never parse or build one. keel sends a
	## bare number on a tip read; it is a String here too.
	var cursor := ""
	## The rows ([OWClient.Change]), in order.
	var changes: Array = []
	var has_more := false
	## The world's current [code]change_seq[/code]. A position past it means the world was rewound.
	var head := 0
	## A guest's or a contributor's view epoch (an int), null for other keys. It can move with [member head] unchanged.
	var epoch: Variant = null
	## Why [member epoch] last moved ([code]role[/code] or [code]view[/code]), or null.
	var epoch_reason: Variant = null
	## On a tip read: keel answered 304 to the tag this client held, so [member head], [member cursor] and
	## [member epoch] are the last 200's. False on every 200. Never on the wire.
	var unchanged := false

## What [method OWClient.bulk] answers. keel answers 200 even when slots failed: each slot's [member BulkSlot.status]
## is where the truth lives, so check [method failed] (or [method all_succeeded]) before trusting the write. After an
## atomic request with [member errors] true nothing was written, though the slots that would have succeeded still say
## 201 with the ids and timestamps they would have had: do not record those as created.
class BulkResult:
	## The keys this reads from keel's answer.
	const KEYS := ["errors", "items"]
	## True when any slot failed.
	var errors := false
	## The slots ([OWClient.BulkSlot]), in the order of the items sent.
	var items: Array = []
	## True when keel replayed the first answer for this [code]Idempotency-Key[/code] and wrote nothing (its
	## [code]Idempotent-Replay[/code] header). Never on the wire's body.
	var was_replay := false

	## The slots that did not succeed, in order.
	func failed() -> Array:
		return items.filter(func(s): return not s.succeeded())

	func succeeded_count() -> int:
		return items.size() - failed().size()

	## True when no slot failed and keel said none did.
	func all_succeeded() -> bool:
		return not errors and failed().is_empty()

## One item's outcome in a [BulkResult].
class BulkSlot:
	## The keys this reads from a slot of keel's answer.
	const KEYS := ["status", "id", "created_at", "updated_at", "error", "proposal"]
	## The item's own HTTP status: 201 created, 200 updated, 202 a proposal, else its failure.
	var status := 0
	## The element's id as served, a String; null when the slot answers none (a failure before the item was
	## identified), as the API document types it.
	var id: Variant = null
	## On a success: keel's timestamps, from which a sync baseline is set.
	var created_at: Variant = null
	var updated_at: Variant = null
	## On a failure: the slot's error as an [OWApiError] of kind [constant OWApiError.API], its status the slot's.
	var error: OWApiError = null
	## On a 202: the proposal row the item became (the element did not change), a Dictionary as served.
	var proposal: Variant = null

	func succeeded() -> bool:
		return status >= 200 and status < 300

	func is_proposed() -> bool:
		return status == 202

## Build a client from [param config]: [code]api_key[/code] (a world key, an account token, or none for a keyless
## reader), [code]api_pin[/code] (the world's PIN, or an agent seat's secret), [code]world[/code] (a world's id, for an
## account token or no key), [code]base_url[/code], [code]page_size[/code] (100 when absent or not above 0),
## [code]transport[/code] (an [OWTransport]; an [OWHttpTransport] when absent), [code]client[/code] (the name sent as
## [code]X-OW-Client[/code], keel's rule [code][a-z0-9-]{1,32}[/code] and no version: [code]atlas[/code], not
## [code]atlas-1.76[/code]; [constant DEFAULT_CLIENT_NAME] when absent) and [code]agent[/code] (a bool: declare this
## client an AI agent). A config it refuses (an unknown key, a value of the wrong type, a client name outside keel's
## rule, nothing trimmed; a [code]world[/code] beside a world key or empty, no key and no world) leaves [member error]
## saying why. Mirrors the TypeScript SDK's [code]new OwV2Client[/code].
func _init(config: Dictionary = {}) -> void:
	error = _configure(config)
	if transport == null:
		transport = OWHttpTransport.new()

func _configure(config: Dictionary) -> String:
	for k in config:
		if not (k is String and _CONFIG_KEYS.has(k)):
			return "OWClient: unknown key '%s' in the config; the keys are %s." % [k, ", ".join(_CONFIG_KEYS)]
	for k in ["api_key", "api_pin", "base_url"]:
		if config.get(k) != null and not (config[k] is String):
			return "OWClient: %s is a String; got %s." % [k, type_string(typeof(config[k]))]
	if config.get("page_size") != null and not (config["page_size"] is int):
		return "OWClient: page_size is an int; got %s." % type_string(typeof(config["page_size"]))
	if config.get("transport") != null and not (config["transport"] is OWTransport):
		return "OWClient: transport is an OWTransport."
	if config.get("agent") != null and not (config["agent"] is bool):
		return "OWClient: agent is a bool; got %s." % type_string(typeof(config["agent"]))
	agent = config.get("agent") == true
	var name = config.get("client")
	if name != null:
		if not (name is String):
			return "OWClient: client is a String; got %s." % type_string(typeof(name))
		if not _is_client_name(name):
			return ("OWClient: client must be lower case letters, digits and hyphens, 1 to 32 characters "
				+ "([a-z0-9-]{1,32}), such as 'atlas'; got %s. It is sent as X-OW-Client on element writes; leave it "
				+ "out for '%s'.") % [var_to_str(name), DEFAULT_CLIENT_NAME]
		client_name = name
	var key: String = config.get("api_key") if config.get("api_key") != null else ""
	key_kind = key_kind_of(key)
	var w = config.get("world")
	if w != null:
		if not (w is String) or w.strip_edges() == "":
			return ("OWClient: world is a world's id, not empty or white space; got %s. With it, an account token or no "
				+ "key reads that world through %s.") % [var_to_str(w), _WORLD_READS]
		if key_kind != KEY_NONE and key_kind != KEY_ACCOUNT:
			return ("OWClient: A world key reads its own world; world is for an account token (ow_a_) or no key, which "
				+ "read the world it names through %s.") % _WORLD_READS
		world = w
	if key_kind == KEY_NONE and world == "":
		return "OWClient: An API key is required, or world for a keyless reader of a public world."
	_api_key = key
	_api_pin = config.get("api_pin") if config.get("api_pin") != null else ""
	var base: String = config.get("base_url") if config.get("base_url") != null else DEFAULT_BASE_URL
	while base.ends_with("/"):
		base = base.trim_suffix("/")
	base_url = base
	var size = config.get("page_size")
	page_size = size if size != null and size > 0 else 100
	transport = config.get("transport")
	return ""

## A key's kind: [constant KEY_WRITE] ([code]ow_w_[/code]), [constant KEY_READ] ([code]ow_r_[/code]),
## [constant KEY_ACCOUNT] ([code]ow_a_[/code]), [constant KEY_LEGACY] (ten digits), [constant KEY_UNKNOWN] (anything
## else, sent as a world key is) or [constant KEY_NONE] (""). Mirrors the TypeScript SDK's [code]detectKeyKind[/code].
static func key_kind_of(key: String) -> String:
	if key == "":
		return KEY_NONE
	if key.begins_with("ow_w_"):
		return KEY_WRITE
	if key.begins_with("ow_r_"):
		return KEY_READ
	if key.begins_with("ow_a_"):
		return KEY_ACCOUNT
	if key.length() == 10 and key.is_valid_int() and not key.begins_with("-") and not key.begins_with("+"):
		return KEY_LEGACY
	return KEY_UNKNOWN

# -- Health and the world -------------------------------------------------------------------------------------------

## [code]GET /health/[/code]: is the server up. keel's liveness answer, the body as served
## ([code]{"status": "ok", "service": "keel"}[/code]). Sent with no credential at all on every client, and no
## [code]world=[/code]. Mirrors the TypeScript SDK's [code]health[/code].
func health() -> Reply:
	return _object(await _request("GET", "/health/", [], {"auth": false}))

## [code]GET /world/[/code]: the world's settings, the body as served (its name, its time fields, [code]counts[/code]
## as this reader may read). On a client with [member world] set it reads that world ([code]world=<id>[/code]).
## World-settings edits are not in the change feed: compare [code]updated_at[/code]. Mirrors the TypeScript SDK's
## [code]getWorld[/code].
func get_world() -> Reply:
	return _object(await _request("GET", "/world/", [], {"world_read": true}))

## [code]GET /me/[/code]: who this world key is, the body as served: [code]{world, scope, kind, role, membership,
## character, lenses, name?, front_door, reading_aids}[/code]. [code]OWCharter.served(reply.value)[/code] reads its
## reading aids (the Charter, the Guide, the Domains, the strand). The connection test: the one read sent with the
## PIN. A world key's call: an account token and a keyless client are refused, nothing sent. Mirrors the TypeScript
## SDK's [code]me[/code].
func me() -> Reply:
	return _object(await _request("GET", "/me/", []))

## [code]GET /members/[/code]: the world's roster, the rows of keel's [code]{data}[/code] (no paging), each a
## Dictionary as served: [code]id[/code] (the membership id that [code]created_by[/code] holds, null for the owner),
## [code]kind[/code], [code]role[/code], [code]character[/code], [code]status[/code] (removed rows stay),
## [code]lenses[/code], [code]lenses_from[/code], and [code]name[/code] where this key is served it; an answer
## without rows is an empty list. The list [OWMessage] takes as [code]members[/code]. A world key reads its own world's;
## an account token the one [member world] names (refused without it); a keyless client is refused: the roster has no
## public reader. Mirrors the TypeScript SDK's [code]members[/code].
func members() -> Reply:
	var r := _object(await _request("GET", "/members/", [], {"account_token": "world"}))
	if r.ok:
		var rows = r.value.get("data")
		r.value = rows if rows is Array else []
	return r

# -- Elements ---------------------------------------------------------------------------------------------------------

## [code]GET /{type}/[/code]: one cursor page of a type, a [Page] of typed elements. [param options], each optional:
## [code]limit[/code] (an int; the page size by default), [code]cursor[/code] (a page's [code]next_cursor[/code]),
## [code]expand[/code] and [code]fields[/code] (link fields to expand into stubs; a sparse body), [code]ids[/code]
## (only these, 1 to 200), [code]created_by[/code] (a membership id, or [code]owner[/code]), [code]name[/code],
## [code]name_contains[/code] (sent as [code]name__icontains[/code]), [code]supertype[/code], [code]subtype[/code],
## [code]filter[/code] (single-link filters by field name, [code]{"parent_location": id}[/code]; an empty value lists
## the rows with none) and [code]view_as[/code] (sent as [code]as[/code]: the owner reads as another reader). Sent in
## that order, the filter by field name, [code]as[/code] last; a list joined by commas; an empty value sends nothing
## (except in [code]filter[/code]). Refused, nothing sent: an unknown option, a value of the wrong type,
## [code]world[/code] in the filter (the client's [member world] names it), a filter key that is no field name or that
## an option sends in the same request. On a client with [member world] set it reads that world. Mirrors the
## TypeScript SDK's [code]list[/code].
func list(type: String, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _LIST_KEYS, "list")
	if refused != "":
		return _refused(refused)
	var typed := [
		["limit", str(options["limit"]) if options.get("limit") != null else str(page_size)],
		["cursor", _opt(options, "cursor")],
		["expand", ",".join(_names(options, "expand"))],
		["fields", ",".join(_names(options, "fields"))],
		["ids", ",".join(_names(options, "ids"))],
		["created_by", _opt(options, "created_by")],
		["name", _opt(options, "name")],
		["name__icontains", _opt(options, "name_contains")],
		["supertype", _opt(options, "supertype")],
		["subtype", _opt(options, "subtype")],
	]
	var view_as := _opt(options, "view_as")
	var query := typed.filter(func(p): return p[1] != "")
	var filter: Dictionary = options["filter"] if options.get("filter") != null else {}
	if filter.has("world"):
		return _refused(("list: world is not a filter; an account token or no key names its world with the config's "
			+ "world (OWClient.new({\"api_key\": ..., \"world\": ...})).") + " Nothing was sent.")
	var fields: Array = filter.keys()
	fields.sort()
	for field: String in fields:
		if not _is_field_name(field):
			return _refused("list: '%s' is not a field name to filter on. Nothing was sent." % field)
		if (field == "as" and view_as != "") or query.any(func(p): return p[0] == field):
			return _refused(("list: '%s' is sent by its own option in this request; give it there or in filter, not "
				+ "both. Nothing was sent.") % field)
		query.append([field, filter[field] if filter[field] != null else ""])
	if view_as != "":
		query.append(["as", view_as])
	var r := _object(await _request("GET", "/%s/" % _seg("type", type), query, {"world_read": true}))
	if not r.ok:
		return r
	var body: Dictionary = r.value
	var page := Page.new()
	var rows = body.get("data", [])
	if not (rows is Array):
		return _bad(r, "GET /%s/ answered data that is not a list" % type)
	for row in rows:
		if not (row is Dictionary):
			return _bad(r, "GET /%s/ answered a row that is not an element" % type)
		page.data.append(OWTypes.make(type, row))
	page.has_more = body.get("has_more") == true
	page.next_cursor = _cursor_text(body.get("next_cursor"))
	r.value = page
	return r

## Every element of a type, every page, as one list: [method list] page by page, each page with the same
## [param options] and the last page's cursor, until a page says [code]has_more[/code] false (never by its size: a
## short page is no end). Starts at [code]options.cursor[/code] when given, else the first page. Stops, answering no
## half list: at a page's error; at [code]has_more[/code] true with no cursor (an end, rather than a loop); at a page
## that hands back the cursor it was sent (an [OWApiError] of kind [constant OWApiError.ANSWER], rather than reading
## it forever). [param on_page], when valid, is called after each page with the page's number and the count so far.
## Mirrors the TypeScript SDK's [code]listAll[/code].
func list_all(type: String, options: Dictionary = {}, on_page: Callable = Callable()) -> Reply:
	var all: Array[OWElement] = []
	var cursor = options.get("cursor") if options.get("cursor") != null else ""
	var pages := 0
	while true:
		var page_options := options.duplicate()
		page_options["cursor"] = cursor
		var r := await list(type, page_options)
		if not r.ok:
			return r
		var page: Page = r.value
		all.append_array(page.data)
		pages += 1
		if on_page.is_valid():
			on_page.call(pages, all.size())
		if not page.has_more or page.next_cursor == "":
			return Reply.of(all, r.response)
		if page.next_cursor == cursor:
			return Reply.failed(OWApiError.of(OWApiError.ANSWER, ("list_all: GET /%s/ answered the cursor it was sent, "
				+ "with more to come; the walk stopped rather than read the same page again") % type,
				r.response.status, r.response.body), r.response)
		cursor = page.next_cursor
	return null

## [code]GET /{type}/{id}/[/code]: one element in its type's model. [param options], each optional:
## [code]expand[/code], [code]fields[/code] and [code]view_as[/code] (sent as [code]as[/code]), as [method list] takes
## them, sent in that order. The type and the id are each checked as one path segment (see [method _seg]): a value that is not one is refused, nothing sent. On a client with [member world] set it reads that
## world. Named [code]get_element[/code]: [code]get[/code] is [method Object.get]. Mirrors the TypeScript SDK's
## [code]get[/code].
func get_element(type: String, id: String, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _GET_KEYS, "get_element")
	if refused != "":
		return _refused(refused)
	var query := [
		["expand", ",".join(_names(options, "expand"))],
		["fields", ",".join(_names(options, "fields"))],
		["as", _opt(options, "view_as")],
	].filter(func(p): return p[1] != "")
	var r := _object(await _request("GET", "/%s/%s/" % [_seg("type", type), _seg("id", id)], query, {"world_read": true}))
	if r.ok:
		r.value = OWTypes.make(type, r.value)
	return r

# -- The change feed ----------------------------------------------------------------------------------------------------

## [code]GET /changes/[/code]: one page of the world's change feed, a [ChangesPage]. [param options], each optional:
## [code]since[/code] (the previous page's [member ChangesPage.cursor], passed back as is; none starts from the
## beginning) and [code]after[/code] (only the changes made at or after this ISO 8601 time, sent as given: a filter,
## not a position, so walk the window by passing each page's cursor back with the same [code]after[/code]). A page
## holds [member page_size] changes, at most 1000 (keel answers 422 past it). A 409 [code]resync_required[/code]
## ([method OWApiError.is_resync_required]) drops the tip read's tag, so the next [method changes_head] is a full one.
## Mirrors the TypeScript SDK's [code]changes[/code].
func changes(options: Dictionary = {}) -> Reply:
	var refused := _check(options, _CHANGES_KEYS, "changes")
	if refused != "":
		return _refused(refused)
	var query := [["since", _opt(options, "since")], ["limit", str(mini(page_size, MAX_CHANGES_LIMIT))],
		["after", _opt(options, "after")]].filter(func(p): return p[1] != "")
	var r := _object(await _request("GET", "/changes/", query))
	_drop_on_resync(r)
	return _changes_page(r)

## [code]GET /changes/?head=true[/code]: where the feed is now, with no page. [member ChangesPage.head] is the world's
## [code]change_seq[/code], [member ChangesPage.cursor] a position to pass as [code]since[/code] that re-sends nothing
## at the head, [member ChangesPage.epoch] a guest's or contributor's view epoch. Conditional: the client keeps the
## last 200's ETag and sends it as [code]If-None-Match[/code], exactly as received; when nothing moved keel answers
## 304 (refunded against the request budget) and this answers the last 200's head, cursor and epoch with
## [member ChangesPage.unchanged] true. Compare head and epoch with what you applied, never with the last poll's; the
## interval is yours, the client never polls on its own. The tag is per client; a 409 [code]resync_required[/code]
## from this or [method changes] drops it. A 304 while no tag is held is an [OWApiError] with status 304: the client
## never makes up a head. Mirrors the TypeScript SDK's [code]changesHead[/code].
func changes_head() -> Reply:
	var held := _head_held
	var r := await _request("GET", "/changes/", [["head", "true"]], {"if_none_match": _head_tag, "not_modified": true})
	if r.ok and r.response.status == 304:
		if held == null:
			return Reply.failed(OWApiError.of(OWApiError.API, ("GET /changes?head=true answered 304 Not Modified while "
				+ "nothing is held: no tip read has answered 200 on this client, so there is no head to return"),
				304, r.response.body), r.response)
		var tip := ChangesPage.new()
		tip.cursor = held.cursor
		tip.head = held.head
		tip.epoch = held.epoch
		tip.unchanged = true
		r.value = tip
		return r
	r = _object(r)
	_drop_on_resync(r)
	r = _changes_page(r)
	if r.ok:
		var page: ChangesPage = r.value
		var tag = r.response.header("ETag")
		_head_tag = tag if tag is String else ""
		var keep := ChangesPage.new()
		keep.cursor = page.cursor
		keep.head = page.head
		keep.epoch = page.epoch
		_head_held = keep
	return r

func _drop_on_resync(r: Reply) -> void:
	if r.error != null and r.error.is_resync_required():
		_head_tag = ""
		_head_held = null

func _changes_page(r: Reply) -> Reply:
	if not r.ok:
		return r
	var body: Dictionary = r.value
	var page := ChangesPage.new()
	page.cursor = _cursor_text(body.get("cursor"))
	page.has_more = body.get("has_more") == true
	page.head = int(body.get("head")) if (body.get("head") is float or body.get("head") is int) else 0
	var epoch = body.get("epoch")
	page.epoch = int(epoch) if (epoch is float or epoch is int) else null
	page.epoch_reason = body.get("epoch_reason") if body.get("epoch_reason") is String else null
	var rows = body.get("changes", [])
	if not (rows is Array):
		return _bad(r, "GET /changes/ answered changes that are not a list")
	for row in rows:
		if not (row is Dictionary):
			return _bad(r, "GET /changes/ answered a row that is not a change")
		var c := Change.new()
		c.op = _text(row.get("op"))
		c.type = _text(row.get("type"))
		c.id = _text(row.get("id"))
		var seq = row.get("change_seq")
		c.change_seq = int(seq) if (seq is float or seq is int) else 0
		for k in ["updated_at", "changed_at", "changed_by", "changed_via", "deleted_at", "deleted_by", "deleted_via",
				"deleted_client", "reason"]:
			c.set(k, row.get(k))
		if row.get("element") is Dictionary:
			c.element = OWTypes.make(c.type, row["element"])
		page.changes.append(c)
	r.value = page
	return r

# -- Element writes -----------------------------------------------------------------------------------------------------
#
# Each takes an element as an OWElement (its data is sent) or a Dictionary, never changed here: the body is a copy,
# cleaned as the Unity SDK's Sanitize cleans it (READ_ONLY_FIELDS left out, a null scalar string sent as "", the one
# unset the wire carries; a single link's null, an x_* value and an absent key left as they are), written as
# JavaScript's JSON.stringify writes it. A known-of stub (known_of: true) is refused before sending: its empty fields
# are not the element's values, and writing it would blank them. Every write is an element write: the PIN,
# X-OW-Client, and X-OW-Agent on an agent client. An account token and a keyless client are refused, nothing sent.

## [code]POST /{type}/[/code]: create one element, answering it as keel wrote it, in its type's model. An element with
## no id gets one minted here: a UUIDv7 ([method OWId.new_id]), or with [code]options.idempotency_key[/code] the id
## derived from the key ([method OWId.keyed], index 0), so a retry with the same key sends the same body and keel
## replays its first answer (24 hours), writing nothing; the same key with another body is a 409
## ([method OWApiError.is_idempotency_conflict]). The key goes as [code]Idempotency-Key[/code] only when given. An
## unkeyed retry of an element without an id creates a second one; one that carries its id answers 409
## [code]id_conflict[/code] when it already landed ([method OWApiError.is_id_conflict]). Never reuse a key for a new
## write: an undo that re-creates under the first key gets the old answer back. Mirrors the TypeScript SDK's
## [code]create[/code].
func create(type: String, element: Variant, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _CREATE_KEYS, "create")
	if refused != "":
		return _refused(refused)
	var body = _element_body(type, element, "create")
	if body is String:
		return _refused(body)
	var key := _opt(options, "idempotency_key")
	if _no_id(body):
		body["id"] = OWId.mint(key, 0)
	return _element(type, await _request("POST", "/%s/" % _seg("type", type), [], {"body": body, "idempotency_key": key, "write": true}))

## [code]PUT /{type}/{id}/[/code]: upsert by the caller's own id, creating the element under [param id] or writing it
## whole: the local-first write. keel's document declares no [code]Idempotency-Key[/code] or [code]If-Match[/code]
## here, so none is sent. An agent seat's PUT on an existing element, in a world that takes its writes as proposals,
## answers 202: an [OWApiError] of kind [constant OWApiError.API], status 202, its row in
## [member OWApiError.proposal] ([method OWApiError.is_proposed]), and the element did not change. Mirrors the
## TypeScript SDK's [code]upsert[/code].
func upsert(type: String, id: String, element: Variant) -> Reply:
	if id == "":
		return _refused("upsert: needs the element's id. Nothing was sent.")
	var body = _element_body(type, element, "upsert")
	if body is String:
		return _refused(body)
	return _element(type, await _request("PUT", _element_path(type, id), [],
		{"body": body, "write": true, "proposable": true}))

## [code]PATCH /{type}/{id}/[/code]: a partial update. Destructive on the keys sent: whatever is in [param partial]
## replaces what keel holds, so send only what changed; a key left out is left alone. Never patch a link array to add
## one id: a link array is sent as given and replaces the whole array, so a writer adding one id erases what another
## added since; change it with [method edit_links], keel's merge. [code]options.if_match[/code]: the element's
## [code]change_seq[/code] as read (an int, or a whole float as JSON reads it), sent as [code]If-Match[/code]; the
## write lands only if nobody changed the element since, else a 412 ([method OWApiError.is_precondition_failed]) whose
## [method OWApiError.current] is the element now. A 202 is a proposal, as on [method upsert]; a stale
## [code]If-Match[/code] is still a 412 first. Mirrors the TypeScript SDK's [code]patch[/code] and the Unity SDK's
## [code]PatchAsync[/code].
func patch(type: String, id: String, partial: Variant, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _IF_MATCH_KEYS, "patch")
	if refused != "":
		return _refused(refused)
	if id == "":
		return _refused("patch: needs the element's id. Nothing was sent.")
	var body = _element_body(type, partial, "patch")
	if body is String:
		return _refused(body)
	return _element(type, await _request("PATCH", _element_path(type, id), [],
		{"body": body, "if_match": options.get("if_match"), "write": true, "proposable": true}))

## [code]DELETE /{type}/{id}/[/code]: delete an element. keel writes a tombstone and takes the id out of every other
## element's links in the same write. Answers no value; an element already gone is the same 204.
## [code]options.if_match[/code] as on [method patch]: a stale one is a 412 and nothing is deleted. Never a proposal.
## Mirrors the TypeScript SDK's [code]delete[/code].
func delete(type: String, id: String, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _IF_MATCH_KEYS, "delete")
	if refused != "":
		return _refused(refused)
	if id == "":
		return _refused("delete: needs the element's id. Nothing was sent.")
	var r := await _request("DELETE", _element_path(type, id), [],
		{"if_match": options.get("if_match"), "write": true, "allow_empty": true})
	if r.ok:
		r.value = null
	return r

## [code]POST /{type}/{id}/links/{field}[/code] with [code]{add, remove}[/code]: change one link array, merged by keel
## (ids already there or already gone are fine), answering the element whole in its type's model. The way to change
## a link array: [method patch] sends one whole, erasing what another writer added since. [param edit] holds
## [code]add[/code] and [code]remove[/code], each an Array of ids, each optional and sent only when given.
## [code]options.if_match[/code] as on [method patch]: a link write moves the element too. A 202 is a proposal, as on
## [method upsert]. The type, the id and the field are each checked as one path segment and escaped: a value that is
## not one is refused, nothing sent. Mirrors the TypeScript SDK's [code]editLinks[/code].
func edit_links(type: String, id: String, field: String, edit: Dictionary, options: Dictionary = {}) -> Reply:
	var refused := _check(edit, _EDIT_KEYS, "edit_links")
	if refused == "":
		refused = _check(options, _IF_MATCH_KEYS, "edit_links")
	if refused != "":
		return _refused(refused)
	if id == "":
		return _refused("edit_links: needs the element's id. Nothing was sent.")
	if field == "":
		return _refused("edit_links: needs a link field's name (friends, species). Nothing was sent.")
	var body := {}
	for k in _EDIT_KEYS:
		if edit.get(k) != null:
			body[k] = Array(_names(edit, k))
	return _element(type, await _request("POST", "/%s/%s/links/%s" % [_seg("type", type), _seg("id", id), _seg("field", field)], [],
		{"body": body, "if_match": options.get("if_match"), "write": true, "proposable": true}))

## [code]POST /bulk/[/code]: write many elements of mixed types in one request, a [BulkResult]. [param items], in the
## order the slots come back: each an [OWElement] (its own type) or [code]{"type": slug, "element": element}[/code]
## (an absent element is an empty one). Each element is cleaned as a single write's is, and one without an id gets one
## by its position: under [code]options.idempotency_key[/code] the id derived from the key and the position, so a retry
## sends the same body and replays ([member BulkResult.was_replay]), else a fresh UUIDv7. [code]options.atomic[/code]
## true asks for all or nothing (false by default, as keel's). keel answers 200 even when slots failed: read the slots.
## Refused, nothing sent: no items, an item that is neither, one without a type, a known-of stub (named by its index).
## Mirrors the TypeScript SDK's [code]bulk[/code].
func bulk(items: Array, options: Dictionary = {}) -> Reply:
	var refused := _check(options, _BULK_KEYS, "bulk")
	if refused != "":
		return _refused(refused)
	if items.is_empty():
		return _refused("bulk: needs at least one item. Nothing was sent.")
	var key := _opt(options, "idempotency_key")
	var sent := []
	for i in items.size():
		var item = items[i]
		var where := "bulk: items[%d]" % i
		var type := ""
		var element: Variant = {}
		if item is OWElement:
			type = String(item.get_type())
			element = item
		elif item is Dictionary:
			for k in item:
				if not (k is String and (k == "type" or k == "element")):
					return _refused(("%s: unknown key '%s'; an item is {type, element} or an OWElement. Nothing was "
						+ "sent.") % [where, k])
			type = item["type"] if item.get("type") is String else ""
			element = item["element"] if item.get("element") != null else {}
		else:
			return _refused("%s is {type, element} or an OWElement; got %s. Nothing was sent." % [where, type_string(typeof(item))])
		if type == "":
			return _refused("%s needs a type. Nothing was sent." % where)
		var body = _element_body(type, element, where)
		if body is String:
			return _refused(body)
		if _no_id(body):
			body["id"] = OWId.mint(key, i)
		sent.append({"type": type, "element": body})
	var r := _object(await _request("POST", "/bulk/", [],
		{"body": {"items": sent, "atomic": options.get("atomic") == true}, "idempotency_key": key, "write": true}))
	if not r.ok:
		return r
	var result := BulkResult.new()
	result.errors = r.value.get("errors") == true
	var rows = r.value.get("items", [])
	if not (rows is Array):
		return _bad(r, "POST /bulk/ answered items that are not a list")
	for row in rows:
		if not (row is Dictionary):
			return _bad(r, "POST /bulk/ answered a slot that is not an object")
		var slot := BulkSlot.new()
		var status = row.get("status")
		slot.status = int(status) if (status is float or status is int) else 0
		slot.id = row.get("id") if row.get("id") is String else null
		slot.created_at = row.get("created_at")
		slot.updated_at = row.get("updated_at")
		if row.get("error") is Dictionary:
			slot.error = OWApiError.from_response(slot.status, JSON.stringify({"error": row["error"]}), {})
		slot.proposal = row["proposal"] if row.get("proposal") is Dictionary else null
		result.items.append(slot)
	var replay = r.response.header("Idempotent-Replay")
	result.was_replay = replay is String and replay.to_lower() == "true"
	r.value = result
	return r

## The body of an element write: a cleaned copy of [param element] (an [OWElement] of [param type], or a Dictionary),
## or the refusal as a String.
static func _element_body(type: String, element: Variant, where: String) -> Variant:
	var data: Dictionary
	if element is OWElement:
		var own := String(element.get_type())
		if own != "" and own != type:
			return "%s: the element is a %s, not a %s. Nothing was sent." % [where, own, type]
		data = element.to_dict()
	elif element is Dictionary:
		data = element
	else:
		return "%s: the element is a Dictionary or an OWElement; got %s. Nothing was sent." % [where, type_string(typeof(element))]
	var stub = data.get("known_of")
	if stub is bool and stub:
		return ("%s: this body is a known-of stub (known_of: true), not the element: its empty fields are not its "
			+ "values, and writing it would blank them. Write from a whole copy, or send only the fields you mean to "
			+ "change. Nothing was sent.") % where
	var body := data.duplicate(true)
	for f in READ_ONLY_FIELDS:
		body.erase(f)
	var script = OWTypes.SCRIPTS.get(type)
	for k in body:
		if body[k] != null or not (k is String):
			continue
		var kind = OWElement.BASE_FIELDS[k][0] if OWElement.BASE_FIELDS.has(k) else \
			(script.FIELDS[k][0] if script != null and script.FIELDS.has(k) else "")
		if kind == "scalar_str":
			body[k] = ""   # string-empty-is-unset: "" is the wire's unset, and keel has no null to store
	return body

## True when a body carries no id to keep: absent, null or "".
static func _no_id(body: Dictionary) -> bool:
	var id = body.get("id")
	return id == null or (id is String and id == "")

static func _element_path(type: String, id: String) -> String:
	return "/%s/%s/" % [_seg("type", type), _seg("id", id)]

## One value of a request path, checked as one segment and escaped. A type is a lower-case word
## ([code]^[a-z][a-z0-9_]*$[/code]); every other value is letters, digits and [code]_ . -[/code], not starting with a
## dot or a dash. keel decodes an escaped slash before it routes (measured on production: [code]/character/abc%2Fhidden/[/code]
## answers as [code]/character/abc/hidden/[/code] does), so the escape alone cannot hold a slash: a value that is not
## one segment is refused, and what passes is escaped as well. GDScript has no exceptions, so a refused value comes back
## as a marked refusal in the path, which [method _request] answers as a refused [Reply] before anything is sent.
## Mirrors the TypeScript SDK's [code]seg()[/code].
static func _seg(name: String, value: String) -> String:
	if _path_type == null:
		_path_type = RegEx.create_from_string("^[a-z][a-z0-9_]*\\z")
		_path_value = RegEx.create_from_string("^[A-Za-z0-9][A-Za-z0-9_.-]*\\z")
	var shape := _path_type if name == "type" else _path_value
	if shape.search(value) == null:
		return "%s%s %s is not one path segment. Nothing was sent.%s" % [_REFUSED_OPEN, name, JSON.stringify(value), _REFUSED_CLOSE]
	return value.uri_encode()

## A reply whose value is an element, typed as [param type]'s model.
func _element(type: String, r: Reply) -> Reply:
	r = _object(r)
	if r.ok:
		r.value = OWTypes.make(type, r.value)
	return r

# -- The one request path -----------------------------------------------------------------------------------------------

## Every call's request: the credential rules, then the send, then keel's envelope on a non-2xx. [param query] is
## [code][name, value][/code] pairs, escaped here. [param how]: [code]world_read[/code] (a GET keel serves an account
## token, or no key, with [code]world=<id>[/code]), [code]account_token[/code] ([code]"world"[/code]: a route keel
## declares the account token on beside the world key, naming its world with [code]world=[/code]),
## [code]auth[/code] (false: no credential at all), [code]if_none_match[/code], [code]not_modified[/code] (a 304 is
## answered, not an error), [code]body[/code] (sent as compact JSON with [code]Content-Type[/code]),
## [code]idempotency_key[/code], [code]if_match[/code] (a [code]change_seq[/code], sent quoted), [code]write[/code] (an
## element write: [code]X-OW-Client[/code], and [code]X-OW-Agent[/code] on an agent client, the operations keel's
## document declares both on), [code]proposable[/code] (a 202 is a proposal, never the element) and
## [code]allow_empty[/code] (an empty 2xx body answers null). The value is the parsed body. The rule is the Unity
## SDK's [code]RequestWithResponseAsync[/code] and the TypeScript SDK's [code]request()[/code].
func _request(method: String, path: String, query: Array, how: Dictionary = {}) -> Reply:
	var refusal := path.find(_REFUSED_OPEN)
	if refusal >= 0:
		return _refused(path.substr(refusal + 1, path.find(_REFUSED_CLOSE, refusal) - refusal - 1))
	if error != "":
		return _refused("OWClient was not built: %s Nothing was sent." % error)
	var auth: bool = how.get("auth", true)
	var keyless := key_kind == KEY_NONE
	var reads: bool = auth and how.get("world_read", false) and method == "GET"
	var token_route: String = how.get("account_token", "") if auth and key_kind == KEY_ACCOUNT else ""
	if auth and keyless and not (reads and world != ""):
		return _refused(("%s %s needs a key, and this client holds none: without one it reads the world the config's "
			+ "world names through %s only. Nothing was sent.") % [method, path, _WORLD_READS])
	if auth and key_kind == KEY_ACCOUNT and not _is_account_route(path):
		if not reads and token_route == "":
			return _refused(("%s %s needs a world key: an account token sends the /account routes and members, and "
				+ "with world set reads a world through %s only. Nothing was sent.") % [method, path, _WORLD_READS])
		if (reads or token_route == "world") and world == "":
			return _refused(("%s %s: an account token names the world it reads with the config's world "
				+ "(OWClient.new({\"api_key\": ..., \"world\": ...})); without it, it reads no world (%s) and no "
				+ "roster. Nothing was sent.") % [method, path, _WORLD_READS])
	var pairs := query.duplicate()
	if (reads or token_route == "world") and world != "":
		pairs.append(["world", world])
	var url := base_url + path
	if not pairs.is_empty():
		url += "?" + "&".join(pairs.map(func(p): return p[0] + "=" + str(p[1]).uri_encode()))
	var headers := {}
	if not auth or keyless:
		pass   # the health pulse, or a keyless reader's world read: no credential at all
	elif key_kind == KEY_ACCOUNT:
		headers["Authorization"] = "Bearer " + _api_key
	else:
		headers["API-Key"] = _api_key
		# The PIN only where keel checks it: keel verifies a PIN wherever it is sent (argon2, 64 MiB each), and reads
		# sent with one exhausted a server's memory on a cold cache. On every write, on GET /me (the connection test),
		# and on every request of a 10-digit legacy key, which needs it on reads of a world with a PIN.
		var me_route := path == "/me/" or path == "/me"
		if _api_pin != "" and (method != "GET" or me_route or key_kind == KEY_LEGACY):
			headers["API-Pin"] = _api_pin
	var body = how.get("body")
	if body != null:
		headers["Content-Type"] = "application/json"
	var key: String = how.get("idempotency_key", "")
	if key != "":
		headers["Idempotency-Key"] = key
	# Presence is the declaration, the value is never stored; opt-in, and on the element writes alone, where keel's
	# document declares it. The client's name goes on the same writes and never on a read.
	var write: bool = how.get("write", false)
	if agent and write:
		headers["X-OW-Agent"] = "1"
	if write:
		headers["X-OW-Client"] = client_name
	var tag: String = how.get("if_none_match", "")
	if tag != "":
		headers["If-None-Match"] = tag
	var if_match = how.get("if_match")
	if if_match != null:
		headers["If-Match"] = "\"%d\"" % int(if_match)
	var response: OWTransport.Response = await transport.send(
		OWTransport.Request.make(method, url, headers, _compact(body) if body != null else null))
	if response == null or response.failure != "":
		var why := "no response" if response == null else response.failure
		return Reply.failed(OWApiError.of(OWApiError.TRANSPORT, "OnlyWorlds request failed: %s %s: %s" % [method, path, why]),
			response)
	if how.get("not_modified", false) and response.status == 304:
		return Reply.of(null, response)
	if not response.is_success():
		return Reply.failed(OWApiError.from_response(response.status, response.body, response.headers), response)
	if how.get("proposable", false) and response.status == 202:
		return Reply.failed(_proposed(response, method, path), response)
	if how.get("allow_empty", false) and response.body.strip_edges() == "":
		return Reply.of(null, response)
	var json := JSON.new()
	if response.body.strip_edges() == "" or json.parse(response.body) != OK:
		return Reply.failed(OWApiError.of(OWApiError.ANSWER, "%s %s answered %d with a body that is not JSON"
			% [method, path, response.status], response.status, response.body), response)
	return Reply.of(json.data, response)

## A 202 on a write that may become a proposal: kind [constant OWApiError.API], status 202, carrying the row (the Unity
## SDK's [code]OWProposedError[/code]); a 202 whose body holds none is kind [constant OWApiError.ANSWER]: never the
## element, never a made-up proposal.
static func _proposed(response: OWTransport.Response, method: String, path: String) -> OWApiError:
	var json := JSON.new()
	var body = json.data if json.parse(response.body) == OK else null
	var row = body.get("proposal") if body is Dictionary else null
	if not (row is Dictionary):
		return OWApiError.of(OWApiError.ANSWER, ("%s %s answered 202 without a proposal: the write was not applied, and "
			+ "the answer is not an element") % [method, path], 202, response.body)
	var e := OWApiError.of(OWApiError.API, ("%s %s became a proposal (202): this world takes an agent seat's writes "
		+ "as proposals, so the element did not change. error.proposal is the row; the owner or a co-builder accepts or "
		+ "declines it.") % [method, path], 202, response.body)
	e.proposal = row
	return e

## A JSON value as JavaScript's [code]JSON.stringify[/code] writes it, compact: keys in order, a number as
## [method OWJson.number] writes it (an integral float as an integer: Godot reads every JSON number as a float),
## a string escaped as [method OWJson.quote] escapes it. [method OWJson.stringify] is the folder spec's indented form.
static func _compact(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k in v:
				parts.append(OWJson.quote(str(k)) + ":" + _compact(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts := PackedStringArray()
			for x in v:
				parts.append(_compact(x))
			return "[" + ",".join(parts) + "]"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return OWJson.number(v)
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_NIL:
			return "null"
	return OWJson.quote(str(v))   # a String, or a value that is no JSON written as its text, as OWJson writes it

## keel's rule for [code]X-OW-Client[/code], exact: lower case letters, digits and hyphens, 1 to 32 characters. Checked
## by hand, as the Unity SDK checks it, so nothing past the name (a trailing newline) gets through.
static func _is_client_name(s: String) -> bool:
	if s.length() < 1 or s.length() > 32:
		return false
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-"):
			return false
	return true

## The account routes, [code]/account[/code] and under it, which an account token sends with or without a world.
static func _is_account_route(path: String) -> bool:
	return path == "/account" or path.begins_with("/account/") or path.begins_with("/account?")

## A reply whose value must be a JSON object: any other answer is an [constant OWApiError.ANSWER].
func _object(r: Reply) -> Reply:
	if r.ok and not (r.value is Dictionary):
		return _bad(r, "the answer is not a JSON object")
	return r

func _bad(r: Reply, why: String) -> Reply:
	return Reply.failed(OWApiError.of(OWApiError.ANSWER, why, r.response.status, r.response.body), r.response)

func _refused(why: String) -> Reply:
	return Reply.failed(OWApiError.of(OWApiError.REFUSED, why))

## "" when [param options] holds only [param keys], each of its type; else the refusal.
static func _check(options: Dictionary, keys: Array, call: String) -> String:
	for k in options:
		if not (k is String and keys.has(k)):
			return "%s: unknown option '%s'; the options are %s. Nothing was sent." % [call, k, ", ".join(keys)]
	for k: String in options:
		var v = options[k]
		if v == null:
			continue
		match k:
			"limit":
				if not (v is int):
					return "%s: limit is an int; got %s. Nothing was sent." % [call, type_string(typeof(v))]
			"expand", "fields", "ids", "add", "remove":
				var names_ok: bool = v is PackedStringArray or (v is Array and v.all(func(x): return x is String))
				if not names_ok:
					return "%s: %s is an Array of Strings; got %s. Nothing was sent." % [call, k, var_to_str(v)]
			"if_match":
				# A change_seq: an int, or a whole float as Godot's JSON reads one; never negative.
				var whole: bool = (v is int and v >= 0) or (v is float and v == floorf(v) and v >= 0.0 and v < 9007199254740992.0)
				if not whole:
					return ("%s: if_match is a whole number (an element's change_seq, as read); got %s. Nothing was "
						+ "sent.") % [call, var_to_str(v)]
			"atomic":
				if not (v is bool):
					return "%s: atomic is a bool; got %s. Nothing was sent." % [call, type_string(typeof(v))]
			"filter":
				if not (v is Dictionary):
					return "%s: filter is a Dictionary of field name to id; got %s. Nothing was sent." % [call, type_string(typeof(v))]
				for f in v:
					if not (f is String):
						return "%s: '%s' is not a field name to filter on. Nothing was sent." % [call, f]
					if v[f] != null and not (v[f] is String):
						return "%s: filter values are Strings (an id, or \"\" for none); %s is %s. Nothing was sent." \
							% [call, f, type_string(typeof(v[f]))]
			_:
				if not (v is String):
					return "%s: %s is a String; got %s. Nothing was sent." % [call, k, type_string(typeof(v))]
	return ""

static func _opt(options: Dictionary, key: String) -> String:
	var v = options.get(key)
	return v if v is String else ""

static func _names(options: Dictionary, key: String) -> PackedStringArray:
	var v = options.get(key)
	return PackedStringArray(v) if v != null else PackedStringArray()

## A schema field's shape ([code]parent_location[/code]): a lowercase letter, then lowercase letters, digits and
## [code]_[/code].
static func _is_field_name(s: String) -> bool:
	if s == "" or s[0] < "a" or s[0] > "z":
		return false
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true

## A cursor as a String: keel sends some as numbers, which Godot's JSON reads as floats (17.0 is "17"); null is "".
static func _cursor_text(v: Variant) -> String:
	if v == null:
		return ""
	if v is float and v == floorf(v) and absf(v) < 9007199254740992.0:
		return str(int(v))
	return v if v is String else str(v)

static func _text(v: Variant) -> String:
	return v if v is String else ("" if v == null else str(v))
