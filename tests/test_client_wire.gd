extends RefCounted
## Every request OWClient's read and write calls make, held to keel's own document, and every key the client's models
## read held to what keel serves. The client tests beside this one assert what the client SENDS, which cannot catch a
## client that sends the wrong thing consistently; this asserts what keel SERVES: the path is one keel has, the method
## one it takes there, every query parameter and header sent one keel declares on that operation, no body on a read and
## a JSON object on a write, every body key one keel declares there (a bulk item's element as its type's create); the
## other way round, every key a model reads is one keel's answer declares, and every error code an OWApiError helper
## names is one keel lists. The checks are the Unity SDK's OWWireContractTests, those that apply to these calls.
##
## The fixture is keel's published document as the Unity SDK's tools/refresh_wire.py reduces it, vendored byte for
## byte from unity-sdk (Packages/com.onlyworlds.sdk/Tests/Editor/Fixtures/wire/keel-wire.json at 31b91d8, fetched
## 2026-11-16T08:18+01:00 from https://www.onlyworlds.com/api/v2/openapi.json): tests/data/keel-wire.json, sha256
## bdfae49e8e7b957c93abcccb11e67b1edda99df433d8decb2fc6ef5776cedd23, checked below. A trailing slash is ignored when
## matching (keel serves both spellings). Answer keys go one level down there: data[].name, world.id.

const Fake := preload("res://tests/fake_transport.gd")
const WIRE := "res://tests/data/keel-wire.json"
const WIRE_SHA256 := "bdfae49e8e7b957c93abcccb11e67b1edda99df433d8decb2fc6ef5776cedd23"
const BASE := "https://example.test/api/v2"

## Never a declared parameter in OpenAPI: a body's media type.
const UNDECLARABLE := ["Content-Type"]

## Keys a model reads that keel does not serve on that answer, on purpose, each with why. Each must stay absent from
## the document: when keel starts serving one, drop it here.
const NOT_SERVED := {
	"world": "OWElement.world is the folder format's base field (schema base); keel names an element's world by the key, and serves no world key on the body",
}

## Codes a helper names that keel's document does not list yet, each with why. Each must stay unlisted.
const RESERVED := {
	"world_gone": "OWApiError.is_auth_error names it as reserved, as the Unity and TypeScript SDKs do (keel has no world_gone row yet)",
}

var _wire: Dictionary

func _doc() -> Dictionary:
	if _wire.is_empty():
		_wire = JSON.parse_string(FileAccess.get_file_as_string(WIRE))
	return _wire

## Every write, every option given, with a body that holds each kind of key a write cleans or keeps.
static func _writes(c: OWClient) -> void:
	await c.create("character", {"name": "Ana", "world": "w1", "created_at": "t", "background": null, "x_tool": 1})
	await c.create("character", {"name": "Ana"}, {"idempotency_key": "k1"})
	await c.upsert("character", "c1", {"id": "c1", "name": "Ana", "type": "character", "change_seq": 4.0, "friends": ["c2"],
		"birthplace": null, "level": 3.0})
	await c.patch("character", "c1", {"name": "Bo", "birthplace": "l1"}, {"if_match": 4})
	await c.delete("character", "c1", {"if_match": 4})
	await c.edit_links("character", "c1", "friends", {"add": ["c2"], "remove": ["c3"]}, {"if_match": 4})
	await c.bulk([{"type": "character", "element": {"name": "A", "updated_at": "t"}},
		{"type": "location", "element": {"name": "Port", "parent_location": null}}], {"atomic": true, "idempotency_key": "k2"})

## Every read call and every write, every option given, on each credential: keel's requests, which the checks below
## judge. An agent client reads too, so a declaration sent on a read would be seen.
func _record() -> Array:
	var fake = Fake.new()
	var clients := [
		OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake}),
		OWClient.new({"api_key": "0123456789", "api_pin": "0000", "base_url": BASE, "transport": fake}),
		OWClient.new({"api_key": "ow_r_test", "base_url": BASE, "transport": fake}),
		OWClient.new({"api_key": "ow_w_seat", "api_pin": "ow_s_x", "agent": true, "client": "wire-test", "base_url": BASE,
			"transport": fake}),
	]
	for c: OWClient in clients:
		fake.body = "{}"
		await _writes(c)
		fake.body = "{}"
		await c.health()
		await c.get_world()
		await c.me()
		await c.members()
		fake.body = "{\"data\":[],\"has_more\":false}"
		await c.list("character", {"limit": 5, "cursor": "c", "fields": ["name"], "name": "n", "name_contains": "m",
			"supertype": "s", "subtype": "u", "expand": ["friends"], "ids": ["c1", "c2"], "created_by": "owner",
			"view_as": "public"})
		# Single-link filters: each field must be one keel declares on that list operation.
		await c.list("location", {"filter": {"parent_location": "p1", "zone": ""}})
		await c.list_all("character", {"supertype": "s"})
		fake.body = "{}"
		await c.get_element("character", "c1")
		await c.get_element("character", "c1", {"expand": ["friends"], "fields": ["name"], "view_as": "public"})
		fake.body = "{\"changes\":[],\"has_more\":false,\"head\":0,\"cursor\":\"0\"}"
		await c.changes({"since": "4:069620b9-0794-708d-8000-42b0ea685f38", "after": "2026-10-22T00:00:00Z"})
		fake.headers = {"etag": "W/\"0:-\""}
		await c.changes_head()
		await c.changes_head()   # sends If-None-Match
		fake.headers = {}
	# The world reads an account token, or no key, sends with a world: world= beside each read's own query.
	for c: OWClient in [
		OWClient.new({"api_key": "ow_a_test", "api_pin": "0000", "world": "w1", "base_url": BASE, "transport": fake}),
		OWClient.new({"world": "w1", "base_url": BASE, "transport": fake}),
	]:
		fake.body = "{}"
		await c.health()
		await c.get_world()
		await c.get_element("character", "c1", {"expand": ["friends"], "fields": ["name"], "view_as": "public"})
		await c.members()   # the account token's; the keyless client's is refused, nothing sent
		fake.body = "{\"data\":[],\"has_more\":false}"
		await c.list("character", {"limit": 5, "cursor": "c", "fields": ["name"], "name": "n", "name_contains": "m",
			"supertype": "s", "subtype": "u", "expand": ["friends"], "ids": ["c1"], "created_by": "owner", "view_as": "public"})
		await c.list("location", {"filter": {"parent_location": "p1"}})
		fake.body = "{}"
		await _writes(c)   # refused, nothing sent: neither writes
	return fake.calls

static func _keel_path(url: String) -> String:
	return "/api/v2" + url.get_slice("?", 0).trim_prefix(BASE).trim_suffix("/")

## [operation, why]: the operation keel serves for this request, or null and why not.
func _find(request) -> Array:
	var path := _keel_path(request.url)
	for key: String in _doc()["paths"]:
		var re := RegEx.create_from_string("^" + _escape(key) + "$")
		if re.search(path) == null:
			continue
		var op = _doc()["paths"][key].get(request.method)
		return [op, "" if op != null else "keel serves %s but not %s there" % [key, request.method]]
	return [null, "keel serves no path matching %s" % path]

## A document path as a pattern: {name} matches one segment, everything else is literal.
static func _escape(key: String) -> String:
	var out := ""
	var i := 0
	while i < key.length():
		var ch := key[i]
		if ch == "{":
			var end := key.find("}", i)
			out += "[^/]+"
			i = end + 1
			continue
		out += ("\\" + ch) if ".+*?()[]^$|\\".contains(ch) else ch
		i += 1
	return out

func test_the_fixture_is_the_vendored_bytes(t) -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(WIRE))
	t.eq(ctx.finish().hex_encode(), WIRE_SHA256, "tests/data/keel-wire.json is unity-sdk 31b91d8's copy, byte for byte")
	t.eq(_doc()["fetched"], "2026-11-16T08:18+01:00", "")
	t.done()

func test_every_call_hits_a_path_and_method_keel_serves(t) -> void:
	for call in await _record():
		var found := _find(call)
		t.ok(found[0] != null, "%s %s: %s" % [call.method, call.url, found[1]])
	t.done()

func test_every_query_parameter_is_one_keel_declares(t) -> void:
	for call in await _record():
		var op = _find(call)[0]
		if op == null or not call.url.contains("?"):
			continue
		for pair in call.url.get_slice("?", 1).split("&"):
			var name: String = pair.get_slice("=", 0).uri_decode()
			t.ok(op["query"].has(name), "%s %s: '%s' is not a query parameter keel declares there (%s)"
				% [call.method, call.url, name, ", ".join(op["query"])])
	t.done()

func test_every_header_is_one_keel_declares(t) -> void:
	var auth: Array = _doc()["auth_headers"].map(func(h): return h.to_lower())
	for call in await _record():
		var op = _find(call)[0]
		if op == null:
			continue
		var declared: Array = op["header"].map(func(h): return h.to_lower())
		for name: String in call.headers:
			var n := name.to_lower()
			t.ok(auth.has(n) or declared.has(n) or UNDECLARABLE.any(func(u): return u.to_lower() == n),
				"%s %s: header '%s' is not one keel declares there" % [call.method, call.url, name])
	t.done()

func test_no_read_sends_a_body_and_every_write_body_is_a_json_object(t) -> void:
	for call in await _record():
		var label := "%s %s" % [call.method, call.url]
		if call.method == "GET" or call.method == "DELETE":
			t.eq(call.body, null, label)
			t.ok(not call.headers.has("Content-Type"), "%s: no body, no media type" % label)
			continue
		t.ok(call.body is String and JSON.parse_string(call.body) is Dictionary, "%s: a JSON object" % label)
		t.eq(call.headers.get("Content-Type"), "application/json", label)
	t.done()

## [top-level keys, patterns] a write operation declares for its body, or for the part under [param prefix].
static func _declared_body(op: Dictionary, prefix := "") -> Array:
	var keys: Array = op.get("body", [])
	return [_below(keys, prefix) if prefix != "" else _top(keys), op.get("body_patterns", [])]

static func _undeclared(body: Dictionary, declared: Array) -> Array:
	var out := []
	for k: String in body:
		if not declared[0].has(k) and not declared[1].any(func(p): return RegEx.create_from_string(p).search(k) != null):
			out.append(k)
	return out

func test_every_body_key_is_one_keel_declares(t) -> void:
	var paths: Dictionary = _doc()["paths"]
	var checked := 0
	for call in await _record():
		var op = _find(call)[0]
		if op == null or not (call.body is String):
			continue
		var label := "%s %s" % [call.method, call.url]
		var body: Dictionary = JSON.parse_string(call.body)
		t.eq(_undeclared(body, _declared_body(op)), [], "%s: every key one keel declares on the body (%s)" % [label, op.get("body")])
		checked += 1
		if not body.has("items"):
			continue
		for item: Dictionary in body["items"]:
			t.eq(_undeclared(item, _declared_body(op, "items[].")), [], "%s: an item's keys" % label)
			var create: Dictionary = paths["/api/v2/" + item["type"]]["POST"]
			t.eq(_undeclared(item["element"], _declared_body(create)), [],
				"%s: a %s item's element, every key one POST /%s/ declares" % [label, item["type"], item["type"]])
			checked += 1
	t.eq(checked, 4 * (6 + 2), "six bodies and two bulk items on each world key")
	t.done()

func test_the_recording_covers_every_read_and_write(t) -> void:
	# An empty recording would pass the checks above with nothing checked.
	var calls := await _record()
	t.eq(calls.size(), 4 * (12 + 7) + 6 + 5,
		"12 reads and 7 writes on each world key (list_all one page), 6 reads on an account token, 5 on no key (its "
		+ "roster refused); neither writes")
	var paths := {}
	for c in calls:
		paths[c.method + " " + _keel_path(c.url)] = true
	for p in ["GET /api/v2/health", "GET /api/v2/world", "GET /api/v2/me", "GET /api/v2/members", "GET /api/v2/character",
			"GET /api/v2/location", "GET /api/v2/character/c1", "GET /api/v2/changes", "POST /api/v2/character",
			"PUT /api/v2/character/c1", "PATCH /api/v2/character/c1", "DELETE /api/v2/character/c1",
			"POST /api/v2/character/c1/links/friends", "POST /api/v2/bulk"]:
		t.ok(paths.has(p), "%s is recorded" % p)
	t.eq(calls.filter(func(c): return c.url.contains("world=")).size(), 9, "the world reads of an account token and of no key")
	t.ok(calls.any(func(c): return c.headers.has("If-None-Match")), "a tip read with a tag is recorded")
	t.ok(calls.any(func(c): return c.headers.has("API-Pin")), "a PIN is recorded")
	t.ok(calls.any(func(c): return c.headers.has("Authorization")), "a Bearer is recorded")
	t.ok(calls.any(func(c): return c.url.contains("head=true")), "")
	t.ok(calls.any(func(c): return c.url.contains("after=")), "")
	for h in ["If-Match", "Idempotency-Key", "X-OW-Client", "X-OW-Agent", "Content-Type"]:
		t.ok(calls.any(func(c): return c.headers.has(h)), "%s is recorded" % h)
	t.eq(calls.filter(func(c): return c.method == "GET" and c.headers.has("API-Pin") and c.headers.get("API-Key") == "ow_w_seat").size(),
		1, "the agent reads too (its /me alone with the PIN)")
	t.done()

# -- What the models read ----------------------------------------------------------------------------------------------

static func _top(keys: Array) -> Array:
	return keys.filter(func(k): return not k.contains(".") and not k.contains("[]"))

static func _below(keys: Array, prefix: String) -> Array:
	return keys.filter(func(k): return k.begins_with(prefix)).map(func(k): return k.substr(prefix.length())) \
		.filter(func(k): return not k.contains(".") and not k.contains("[]"))

## Every key an element model reads: the base fields and the type's own, as the generated model names them.
static func _model_keys(type: String) -> Array:
	var keys: Array = OWElement.BASE_FIELDS.keys()
	keys.append_array(OWTypes.SCRIPTS[type].FIELDS.keys())
	return keys

func test_every_key_an_element_model_reads_is_one_keel_serves(t) -> void:
	var paths: Dictionary = _doc()["paths"]
	for type in OWTypes.slugs():
		var list_op: Dictionary = paths["/api/v2/" + type]["GET"]
		var get_op: Dictionary = paths["/api/v2/" + type + "/{id}"]["GET"]
		var listed := _below(list_op["response"], "data[].")
		var got := _top(get_op["response"])
		for key in _model_keys(type):
			if NOT_SERVED.has(key):
				t.ok(not listed.has(key) and not got.has(key), "%s.%s: keel serves it now; drop it from NOT_SERVED" % [type, key])
				continue
			t.ok(listed.has(key), "%s.%s is not a key GET /%s/ serves on a row" % [type, key, type])
			t.ok(got.has(key), "%s.%s is not a key GET /%s/{id} serves" % [type, key, type])
		t.eq(OWClient.Page.KEYS.filter(func(k): return not list_op["response"].has(k)), [],
			"OWClient.Page reads only what GET /%s/ serves" % type)
	t.done()

func test_the_changes_page_reads_what_keel_serves_and_every_key_of_a_row(t) -> void:
	var served: Array = _doc()["paths"]["/api/v2/changes"]["GET"]["response"]
	t.eq(OWClient.ChangesPage.KEYS.filter(func(k): return not served.has(k)), [], "OWClient.ChangesPage reads only keys keel serves")
	var rows := _below(served, "changes[].")
	var read: Array = OWClient.Change.KEYS.duplicate()
	rows.sort()
	read.sort()
	t.eq(read, rows, "OWClient.Change reads every key of a row, and only those")
	t.done()

func test_the_bulk_result_reads_what_keel_serves_and_every_key_of_a_slot(t) -> void:
	var served: Array = _doc()["paths"]["/api/v2/bulk"]["POST"]["response"]
	t.eq(OWClient.BulkResult.KEYS.filter(func(k): return not served.has(k)), [], "OWClient.BulkResult reads only keys keel serves")
	var slots := _below(served, "items[].")
	var read: Array = OWClient.BulkSlot.KEYS.duplicate()
	slots.sort()
	read.sort()
	t.eq(read, slots, "OWClient.BulkSlot reads every key of a slot, and only those")
	t.done()

func test_every_write_answers_the_element_a_model_reads(t) -> void:
	# create, upsert, patch and edit_links answer the element whole: the keys a model reads are served there too.
	var paths: Dictionary = _doc()["paths"]
	for type in OWTypes.slugs():
		for op in [paths["/api/v2/" + type]["POST"], paths["/api/v2/" + type + "/{id}"]["PUT"],
				paths["/api/v2/" + type + "/{id}"]["PATCH"], paths["/api/v2/" + type + "/{id}/links/{field}"]["POST"]]:
			var served := _top(op["response"])
			for key in _model_keys(type):
				if not NOT_SERVED.has(key):
					t.ok(served.has(key), "%s.%s is not a key a write's answer serves" % [type, key])
	t.done()

func test_the_reading_aids_are_the_packet_owcharter_served_reads(t) -> void:
	# reading_aids beside front_door on /me (and an agent's join answer): OWCharter.served reads
	# {charter, guide, domains, strand}, the packet to_dict writes. keel always serves the strand (serial 100).
	var empty := {"reading_aids": {"charter": null, "guide": null, "domains": [],
		"strand": {"narrative": null, "event": null, "location": null, "character": null, "now": null, "same": null}}}
	var read: Array = OWCharter.served(empty).to_dict().keys()
	read.sort()
	for op in [["/api/v2/me", "GET"], ["/api/v2/join", "POST"]]:
		var served := _below(_doc()["paths"][op[0]][op[1]]["response"], "reading_aids.")
		served.sort()
		t.eq(read, served, "%s %s" % [op[1], op[0]])
	t.done()

func test_the_members_and_me_answers_serve_what_their_docs_name(t) -> void:
	# members() and me() answer the bodies as served; their doc comments name these keys.
	var members: Array = _below(_doc()["paths"]["/api/v2/members"]["GET"]["response"], "data[].")
	for k in ["id", "kind", "role", "character", "status", "lenses", "lenses_from", "name"]:
		t.ok(members.has(k), "GET /members serves data[].%s" % k)
	var me: Array = _top(_doc()["paths"]["/api/v2/me"]["GET"]["response"])
	for k in ["world", "scope", "kind", "role", "membership", "character", "lenses", "reading_aids", "front_door"]:
		t.ok(me.has(k), "GET /me serves %s" % k)
	t.done()

# -- Errors -------------------------------------------------------------------------------------------------------------

func test_every_error_code_a_helper_names_is_one_keel_lists(t) -> void:
	var listed: Dictionary = _doc()["error_codes"]
	var source := FileAccess.get_file_as_string("res://addons/onlyworlds/ow_api_error.gd")
	var named := {}
	for m in RegEx.create_from_string("code == \"([a-z_]+)\"").search_all(source):
		named[m.get_string(1)] = true
	# A match arm: a line of quoted codes alone, ending with its colon.
	for m in RegEx.create_from_string("(?m)^\\t+((?:\"[a-z_]+\", )*\"[a-z_]+\"):$").search_all(source):
		for q in RegEx.create_from_string("\"([a-z_]+)\"").search_all(m.get_string(1)):
			named[q.get_string(1)] = true
	t.ok(named.size() > 5, "the helpers' codes were read: %s" % [named.keys()])
	t.ok(named.has("not_found") and named.has("media_unavailable"), "both forms read, a comparison and a match arm")
	for code in named:
		t.ok(listed.has(code) or RESERVED.has(code), "'%s' is named by an OWApiError helper but keel's document does not list it" % code)
	for m in RegEx.create_from_string("status == (\\d+) and code == \"([a-z_]+)\"").search_all(source):
		var code := m.get_string(2)
		if not listed.has(code):
			continue
		var want = listed[code]
		var statuses: Array = want if want is Array else [want]
		t.ok(statuses.has(float(m.get_string(1))), "'%s': a helper checks status %s, keel lists %s" % [code, m.get_string(1), want])
	for code in RESERVED:
		t.ok(not listed.has(code), "'%s' is listed by keel now; drop it from RESERVED" % code)
	t.done()
