class_name OWClient
extends RefCounted
## A thin client for the OnlyWorlds v2 API (keel, onlyworlds.com): reads a world over the network into the SDK's own
## element models. Deliberately thin: no cache, no sync state, no retry. What it holds is the wire's contract: which
## header carries which credential, where the PIN goes and where it never goes, what a key may send at all (refused
## here, nothing sent, rather than a 401 from keel), opaque cursors, the cursor walk driven by [code]has_more[/code],
## and keel's error envelope as an [OWApiError].
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
## way. The health pulse carries no credential. Mirrors the TypeScript SDK's [code]OwV2Client[/code].

const DEFAULT_BASE_URL := "https://www.onlyworlds.com/api/v2"
## The key kinds, as [method key_kind_of] reads them.
const KEY_WRITE := "write"
const KEY_READ := "read"
const KEY_ACCOUNT := "account"
const KEY_LEGACY := "legacy"
const KEY_UNKNOWN := "unknown"
const KEY_NONE := "none"
## keel's cap on one page of the change feed; past it keel answers 422, where the element lists clamp.
const MAX_CHANGES_LIMIT := 1000

const _CONFIG_KEYS := ["api_key", "api_pin", "world", "base_url", "page_size", "transport"]
const _LIST_KEYS := ["limit", "cursor", "expand", "fields", "ids", "created_by", "name", "name_contains", "supertype",
	"subtype", "filter", "view_as"]
const _GET_KEYS := ["expand", "fields", "view_as"]
const _CHANGES_KEYS := ["since", "after"]
const _WORLD_READS := "list, list_all, get_element and get_world"

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

## Build a client from [param config]: [code]api_key[/code] (a world key, an account token, or none for a keyless
## reader), [code]api_pin[/code] (the world's PIN, or an agent seat's secret), [code]world[/code] (a world's id, for an
## account token or no key), [code]base_url[/code], [code]page_size[/code] (100 when absent or not above 0) and
## [code]transport[/code] (an [OWTransport]; an [OWHttpTransport] when absent). A config it refuses (an unknown key, a
## value of the wrong type, a [code]world[/code] beside a world key or empty, no key and no world) leaves
## [member error] saying why. Mirrors the TypeScript SDK's [code]new OwV2Client[/code].
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
	var r := _object(await _request("GET", "/%s/" % type, query, {"world_read": true}))
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
## them, sent in that order. The id is escaped as a path segment. On a client with [member world] set it reads that
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
	var r := _object(await _request("GET", "/%s/%s/" % [type, id.uri_encode()], query, {"world_read": true}))
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

# -- The one request path -----------------------------------------------------------------------------------------------

## Every call's request: the credential rules, then the send, then keel's envelope on a non-2xx. [param query] is
## [code][name, value][/code] pairs, escaped here. [param how]: [code]world_read[/code] (a GET keel serves an account
## token, or no key, with [code]world=<id>[/code]), [code]account_token[/code] ([code]"world"[/code]: a route keel
## declares the account token on beside the world key, naming its world with [code]world=[/code]),
## [code]auth[/code] (false: no credential at all), [code]if_none_match[/code], [code]not_modified[/code] (a 304 is
## answered, not an error). The value is the parsed body. The rule is the Unity SDK's
## [code]RequestWithResponseAsync[/code] and the TypeScript SDK's [code]request()[/code].
func _request(method: String, path: String, query: Array, how: Dictionary = {}) -> Reply:
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
	var tag: String = how.get("if_none_match", "")
	if tag != "":
		headers["If-None-Match"] = tag
	var response: OWTransport.Response = await transport.send(OWTransport.Request.make(method, url, headers))
	if response == null or response.failure != "":
		var why := "no response" if response == null else response.failure
		return Reply.failed(OWApiError.of(OWApiError.TRANSPORT, "OnlyWorlds request failed: %s %s: %s" % [method, path, why]),
			response)
	if how.get("not_modified", false) and response.status == 304:
		return Reply.of(null, response)
	if not response.is_success():
		return Reply.failed(OWApiError.from_response(response.status, response.body, response.headers), response)
	var json := JSON.new()
	if response.body.strip_edges() == "" or json.parse(response.body) != OK:
		return Reply.failed(OWApiError.of(OWApiError.ANSWER, "%s %s answered %d with a body that is not JSON"
			% [method, path, response.status], response.status, response.body), response)
	return Reply.of(json.data, response)

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
			"expand", "fields", "ids":
				var names_ok: bool = v is PackedStringArray or (v is Array and v.all(func(x): return x is String))
				if not names_ok:
					return "%s: %s is an Array of Strings; got %s. Nothing was sent." % [call, k, var_to_str(v)]
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
