extends RefCounted
## OWClient's element writes through a fake transport (tests/fake_transport.gd): no test touches the network. Each
## write's request (method, URL, headers, body) on each credential, the body cleaned as the Unity SDK's Sanitize
## cleans it, the ids a create and a bulk mint, each refusal before sending, and the answers: the element typed, a 202
## proposal, a 412 and the 409s, a delete's empty 204, bulk's slots and its replay header. The rules are the Unity
## SDK's OWClient (CreateAsync ... BulkAsync and RequestWithResponseAsync), held as its OWClientTests hold them.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const V7 := "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
const ELEMENT := "{\"id\":\"c1\",\"name\":\"Ana\",\"level\":3,\"change_seq\":42}"

func _make(fake, key: Variant = "ow_w_test", pin: Variant = "0000", more := {}) -> OWClient:
	var config := {"api_key": key, "api_pin": pin, "base_url": BASE, "transport": fake}
	config.merge(more, true)
	return OWClient.new(config)

static func _body(request) -> Variant:
	return JSON.parse_string(request.body) if request.body is String else null

static func _refused(t, r: OWClient.Reply, fake, words: String, label: String) -> void:
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains(words),
		"%s: refused, '%s' (got %s)" % [label, words, r.error])
	if r.error != null:
		t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so (%s)" % [label, r.error.message])
	t.eq(fake.calls.size(), 0, "%s: nothing sent" % label)

## Each write: [name, method, path, run]. Every one is an element write: the PIN, X-OW-Client, X-OW-Agent on an agent.
func _writes() -> Array:
	return [
		["create", "POST", "/character/", func(c): return await c.create("character", {"name": "Ana"})],
		["upsert", "PUT", "/character/c1/", func(c): return await c.upsert("character", "c1", {"id": "c1", "name": "Ana"})],
		["patch", "PATCH", "/character/c1/", func(c): return await c.patch("character", "c1", {"name": "Bo"})],
		["delete", "DELETE", "/character/c1/", func(c): return await c.delete("character", "c1")],
		["edit_links", "POST", "/character/c1/links/friends", func(c): return await c.edit_links("character", "c1", "friends", {"add": ["c2"]})],
		["bulk", "POST", "/bulk/", func(c): return await c.bulk([{"type": "character", "element": {"name": "Ana"}}])],
	]

## Every write on its own client, each answered with [param answer]: the requests sent, [name, request], or the
## refusals checked when [param sends] is false.
func _sweep(t, key: Variant, pin: Variant, more := {}, sends := true) -> Array:
	var sent := []
	for w in _writes():
		var fake = Fake.new()
		fake.body = ELEMENT if w[0] != "bulk" else "{\"errors\":false,\"items\":[]}"
		var r: OWClient.Reply = await w[3].call(_make(fake, key, pin, more))
		if not sends:
			_refused(t, r, fake, "needs", w[0])
			continue
		t.ok(r.ok, "%s: answered (%s)" % [w[0], r.error])
		t.eq(fake.calls.size(), 1, "%s: one request" % w[0])
		if fake.calls.size() != 1:
			continue
		var q = fake.last()
		t.eq(q.method, w[1], w[0])
		t.eq(q.url, BASE + w[2], w[0])
		if w[0] == "delete":
			t.eq(q.body, null, "delete: no body")
			t.ok(not q.headers.has("Content-Type"), "delete: no body, no media type")
		else:
			t.eq(q.headers.get("Content-Type"), "application/json", "%s: a JSON body" % w[0])
			t.ok(_body(q) is Dictionary, "%s: the body is an object" % w[0])
		sent.append([w[0], q])
	return sent

# -- Credentials and the write headers ----------------------------------------------------------------------------

func test_pin_and_client_name_on_every_write_of_a_world_key(t) -> void:
	var sent := await _sweep(t, "ow_w_test", "1234")
	t.eq(sent.size(), 6, "every write sent")
	for s in sent:
		t.eq(s[1].headers.get("API-Key"), "ow_w_test", s[0])
		t.eq(s[1].headers.get("API-Pin"), "1234", "%s: the PIN on every write" % s[0])
		t.eq(s[1].headers.get("X-OW-Client"), "godot-sdk", "%s: the client's name" % s[0])
		t.ok(not s[1].headers.has("X-OW-Agent"), "%s: not an agent unless declared" % s[0])
		t.ok(not s[1].headers.has("Authorization"), s[0])
		t.ok(not s[1].url.contains("?"), "%s: no query" % s[0])
	t.done()

func test_pin_on_writes_of_every_key_that_holds_one(t) -> void:
	for key in ["0123456789", "abc", "ow_r_share"]:
		for s in await _sweep(t, key, "1234"):
			t.eq(s[1].headers.get("API-Key"), key, s[0])
			t.eq(s[1].headers.get("API-Pin"), "1234", "%s %s" % [key, s[0]])
	for s in await _sweep(t, "ow_w_test", null):
		t.ok(not s[1].headers.has("API-Pin"), "%s: no PIN held, none sent" % s[0])
	t.done()

func test_an_account_token_and_no_key_send_no_write(t) -> void:
	await _sweep(t, "ow_a_acct", "1234", {"world": "w1"}, false)
	await _sweep(t, "ow_a_acct", "1234", {}, false)
	await _sweep(t, null, null, {"world": "w1"}, false)
	t.done()

func test_an_agent_declares_itself_on_every_write_and_no_read(t) -> void:
	for s in await _sweep(t, "ow_w_test", "1234", {"agent": true, "client": "my-game"}):
		t.eq(s[1].headers.get("X-OW-Agent"), "1", "%s: presence is the declaration" % s[0])
		t.eq(s[1].headers.get("X-OW-Client"), "my-game", "%s: its own name" % s[0])
	var fake = Fake.new()
	fake.body = "{\"data\":[],\"has_more\":false,\"changes\":[],\"head\":0,\"cursor\":\"0\",\"id\":\"c1\"}"
	var c := _make(fake, "ow_w_test", "1234", {"agent": true, "client": "my-game"})
	await c.health()
	await c.get_world()
	await c.me()
	await c.members()
	await c.list("character")
	await c.get_element("character", "c1")
	await c.changes()
	t.eq(fake.calls.size(), 7, "")
	for q in fake.calls:
		t.ok(not q.headers.has("X-OW-Agent") and not q.headers.has("X-OW-Client"), "%s: a read carries neither" % q.url)
	t.done()

func test_the_client_name_and_agent_config(t) -> void:
	t.eq(OWClient.new({"api_key": "ow_w_k"}).client_name, "godot-sdk", "the default name")
	t.eq(OWClient.DEFAULT_CLIENT_NAME, "godot-sdk", "")
	t.eq(OWClient.new({"api_key": "ow_w_k", "client": "a"}).client_name, "a", "one character")
	t.eq(OWClient.new({"api_key": "ow_w_k", "client": "x".repeat(32)}).error, "", "32 characters")
	t.ok(not OWClient.new({"api_key": "ow_w_k"}).agent, "not an agent by default")
	for bad in ["", "Atlas", "atlas-1.76", "x".repeat(33), "atlas\n", " atlas", "atlas_2"]:
		t.ok(OWClient.new({"api_key": "ow_w_k", "client": bad}).error.contains("[a-z0-9-]{1,32}"),
			"%s refused, nothing trimmed" % var_to_str(bad))
	t.ok(OWClient.new({"api_key": "ow_w_k", "client": 7}).error.contains("client is a String"), "")
	t.ok(OWClient.new({"api_key": "ow_w_k", "agent": "yes"}).error.contains("agent is a bool"), "")
	t.done()

# -- Each write's request -----------------------------------------------------------------------------------------

func test_create_mints_a_v7_id_and_sends_no_key_unless_given(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	var c := _make(fake)
	var r: OWClient.Reply = await c.create("character", {"name": "Ana"})
	var body = _body(fake.last())
	t.eq(body.keys(), ["name", "id"], "the id appended")
	t.ok(RegEx.create_from_string(V7).search(body["id"]) != null, "a UUIDv7: %s" % body["id"])
	t.ok(not fake.last().headers.has("Idempotency-Key"), "no key unless given")
	await c.create("character", {"name": "Ana"})
	t.ok(_body(fake.last())["id"] != body["id"], "a fresh id each call")
	for given in [null, ""]:
		await c.create("character", {"id": given, "name": "Ana"})
		var minted = _body(fake.last())
		t.eq(minted.keys(), ["id", "name"], "an id of %s is minted in its place" % var_to_str(given))
		t.ok(RegEx.create_from_string(V7).search(minted["id"]) != null, "")
	await c.create("character", {"id": "mine", "name": "Ana"})
	t.eq(_body(fake.last())["id"], "mine", "an id given is kept")
	t.ok(r.value is OWCharacter, "the element as keel answers it, typed")
	t.eq(r.value.id, "c1", "")
	t.eq(r.value.level, 3, "")
	t.done()

func test_create_under_a_key_derives_the_id_from_it(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	await _make(fake).create("character", {"name": "Ana"}, {"idempotency_key": "retry-1"})
	t.eq(fake.last().headers.get("Idempotency-Key"), "retry-1", "the key sent")
	t.eq(_body(fake.last())["id"], "1b88c4e4-831f-503c-8149-cece1519ca32", "the keyed id: index 0")
	await _make(fake).create("character", {"name": "Ana"}, {"idempotency_key": "retry-1"})
	t.eq(fake.last().body, fake.calls[0].body, "a retry sends the same body, so keel replays")
	await _make(fake).create("character", {"name": "Ana"}, {"idempotency_key": ""})
	t.ok(not fake.last().headers.has("Idempotency-Key"), "an empty key sends none")
	t.done()

func test_upsert_patch_delete_and_if_match(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	var c := _make(fake)
	await c.upsert("character", "c 1/x", {"id": "c 1/x", "name": "Ana"})
	t.eq(fake.last().url, BASE + "/character/c%201%2Fx/", "upsert: the id escaped as a path segment")
	t.eq(_body(fake.last()), {"id": "c 1/x", "name": "Ana"}, "the element whole")
	for h in ["If-Match", "Idempotency-Key"]:
		t.ok(not fake.last().headers.has(h), "upsert: keel declares no %s on PUT" % h)
	await c.patch("character", "c1", {"name": "Bo"}, {"if_match": 41})
	t.eq([fake.last().method, fake.last().url], ["PATCH", BASE + "/character/c1/"], "")
	t.eq(fake.last().headers.get("If-Match"), "\"41\"", "patch: the change_seq, quoted")
	t.eq(_body(fake.last()), {"name": "Bo"}, "only what changed")
	await c.patch("character", "c1", {"name": "Bo"}, {"if_match": 41.0})
	t.eq(fake.last().headers.get("If-Match"), "\"41\"", "a whole float (a change_seq read from JSON) as an integer")
	await c.patch("character", "c1", {"name": "Bo"}, {"if_match": 0})
	t.eq(fake.last().headers.get("If-Match"), "\"0\"", "0 is a change_seq")
	await c.patch("character", "c1", {"name": "Bo"})
	t.ok(not fake.last().headers.has("If-Match"), "unconditional without one")
	fake.body = ""
	fake.status = 204
	var r: OWClient.Reply = await c.delete("character", "c1", {"if_match": 41})
	t.eq([fake.last().method, fake.last().url, fake.last().body], ["DELETE", BASE + "/character/c1/", null], "")
	t.eq(fake.last().headers.get("If-Match"), "\"41\"", "delete: the change_seq, quoted")
	t.ok(r.ok and r.value == null, "a 204: answered, no value (%s)" % r.error)
	await c.delete("character", "c1")
	t.ok(not fake.last().headers.has("If-Match"), "")
	t.done()

func test_edit_links_sends_add_and_remove(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"c1\",\"name\":\"Ana\",\"friends\":[\"c2\"]}"
	var c := _make(fake)
	var r: OWClient.Reply = await c.edit_links("character", "c1", "friends", {"add": ["c2"], "remove": PackedStringArray(["c3"])},
		{"if_match": 7})
	t.eq([fake.last().method, fake.last().url], ["POST", BASE + "/character/c1/links/friends"], "the links route")
	t.eq(fake.last().body, "{\"add\":[\"c2\"],\"remove\":[\"c3\"]}", "the edit as given, compact")
	t.eq(fake.last().headers.get("If-Match"), "\"7\"", "a link write moves the element: If-Match")
	t.ok(r.value is OWCharacter and r.value.friends == PackedStringArray(["c2"]), "the element whole, typed")
	await c.edit_links("character", "c1", "friends", {"remove": []})
	t.eq(fake.last().body, "{\"remove\":[]}", "only the keys given")
	await c.edit_links("character", "c/1", "a b", {"add": ["c2"]})
	t.eq(fake.last().url, BASE + "/character/c%2F1/links/a%20b", "the id and the field escaped")
	t.done()

func test_bulk_mints_by_position_and_reads_the_replay(t) -> void:
	var fake = Fake.new()
	fake.then(200, "{\"errors\":false,\"items\":[]}", {"idempotent-replay": "true"})
	var ana := OWTypes.make("location", {"name": "Port", "created_at": "2026-10-30T10:00:00Z"})
	var r: OWClient.Reply = await _make(fake).bulk([
		{"type": "character", "element": {"name": "A"}},
		{"type": "character", "element": {"id": "b1", "name": "B"}},
		{"type": "pin", "element": {"id": "p1"}},
		ana,
	], {"atomic": true, "idempotency_key": "retry-1"})
	t.eq([fake.last().method, fake.last().url], ["POST", BASE + "/bulk/"], "")
	t.eq(fake.last().headers.get("Idempotency-Key"), "retry-1", "")
	var body = _body(fake.last())
	t.eq(body.keys(), ["items", "atomic"], "")
	t.eq(body["atomic"], true, "")
	t.eq(body["items"].map(func(i): return i["type"]), ["character", "character", "pin", "location"],
		"each item's type; a model's own")
	t.eq(body["items"][0]["element"], {"name": "A", "id": "1b88c4e4-831f-503c-8149-cece1519ca32"}, "position 0, keyed")
	t.eq(body["items"][1]["element"]["id"], "b1", "an id given is kept")
	t.eq(body["items"][3]["element"], {"name": "Port", "id": "44bb129d-48b9-5fc2-b3c9-cc5f549e3e6e"},
		"position 3 (not the third minted), cleaned")
	t.ok(r.ok and r.value.was_replay, "the replay header, lowercase on the wire")
	t.eq(ana.to_dict().has("id"), false, "the caller's element is not changed")
	await _make(fake).bulk([{"type": "character"}])
	t.eq(_body(fake.last()), {"items": [{"type": "character", "element": {"id": _body(fake.last())["items"][0]["element"]["id"]}}],
		"atomic": false}, "an item without an element is an empty one; atomic false by default")
	t.done()

# -- The body, cleaned as every element write's is ------------------------------------------------------------------

func test_the_body_is_cleaned_as_unity_cleans_it(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	var element := {"world": "w1", "type": "character", "id": "c1", "name": null, "created_at": "t0", "updated_at": "t1",
		"change_seq": 41.0, "known_of": false, "description": "", "background": null, "birthplace": null, "level": 3.0,
		"height": 1.5, "weight": 0.30000000000000004, "traits": ["t1"], "x_tool": {"a": null, "b": 2.0}, "x_null": null}
	var before := element.duplicate(true)
	await _make(fake).upsert("character", "c1", element)
	t.eq(fake.last().body, "{\"id\":\"c1\",\"name\":\"\",\"description\":\"\",\"background\":\"\",\"birthplace\":null,"
		+ "\"level\":3,\"height\":1.5,\"weight\":0.30000000000000004,\"traits\":[\"t1\"],\"x_tool\":{\"a\":null,\"b\":2},"
		+ "\"x_null\":null}",
		"the six read-only keys left out; a null string field as \"\"; a single link's null kept; x_* as given; "
		+ "numbers as JSON.stringify writes them; key order kept; compact")
	t.eq(element, before, "the caller's dictionary is not changed")
	await _make(fake).patch("character", "c1", {"description": null})
	t.eq(fake.last().body, "{\"description\":\"\"}", "an absent key stays absent: a patch leaves it alone")
	await _make(fake).create("not_a_type", {"name": null, "thing": null, "id": "z"})
	t.eq(fake.last().body, "{\"name\":\"\",\"thing\":null,\"id\":\"z\"}", "a type not among the 22: its base strings only")
	t.done()

func test_a_model_is_written_as_its_data(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	var ana := OWTypes.make("character", JSON.parse_string(
		"{\"id\":\"c1\",\"name\":\"Ana\",\"level\":3,\"change_seq\":42,\"created_at\":\"t\",\"type\":\"character\",\"x_k\":[1,2.5]}"))
	await _make(fake).upsert("character", "c1", ana)
	t.eq(fake.last().body, "{\"id\":\"c1\",\"name\":\"Ana\",\"level\":3,\"x_k\":[1,2.5]}", "an OWCharacter read from keel, cleaned")
	t.eq(ana.to_dict()["change_seq"], 42.0, "the model is not changed")
	await _make(fake).patch("character", "c1", OWTypes.make("character", {"name": "Bo"}))
	t.eq(fake.last().body, "{\"name\":\"Bo\"}", "a model as a partial")
	t.done()

# -- Refusals before sending -----------------------------------------------------------------------------------------

func test_refusals_send_nothing(t) -> void:
	var stub := {"id": "c1", "name": "Ana", "known_of": true}
	var cases := [
		["create a stub", func(c): return await c.create("character", stub), "known-of stub"],
		["upsert a stub", func(c): return await c.upsert("character", "c1", stub), "known-of stub"],
		["patch a stub", func(c): return await c.patch("character", "c1", stub), "known-of stub"],
		["bulk a stub", func(c): return await c.bulk([{"type": "character", "element": {}}, {"type": "character", "element": stub}]), "bulk: items[1]"],
		["patch a link array", func(c): return await c.patch("character", "c1", {"name": "Bo", "traits": ["t1"]}), "edit_links"],
		["patch a model's link array", func(c): return await c.patch("character", "c1", OWTypes.make("character", {"friends": []})), "'friends' is a link array"],
		["create not an element", func(c): return await c.create("character", "Ana"), "a Dictionary or an OWElement"],
		["upsert null", func(c): return await c.upsert("character", "c1", null), "a Dictionary or an OWElement"],
		["create another type's model", func(c): return await c.create("location", OWTypes.make("character", {})), "is a character, not a location"],
		["upsert no id", func(c): return await c.upsert("character", "", {}), "the element's id"],
		["patch no id", func(c): return await c.patch("character", "", {}), "the element's id"],
		["delete no id", func(c): return await c.delete("character", ""), "the element's id"],
		["links no id", func(c): return await c.edit_links("character", "", "friends", {}), "the element's id"],
		["if_match negative", func(c): return await c.patch("character", "c1", {}, {"if_match": -1}), "if_match is a whole number"],
		["if_match a fraction", func(c): return await c.delete("character", "c1", {"if_match": 2.5}), "if_match is a whole number"],
		["if_match a string", func(c): return await c.edit_links("character", "c1", "friends", {}, {"if_match": "41"}), "if_match is a whole number"],
		["create's options", func(c): return await c.create("character", {}, {"idempotencyKey": "k"}), "unknown option 'idempotencyKey'"],
		["patch's options", func(c): return await c.patch("character", "c1", {}, {"ifMatch": 1}), "unknown option 'ifMatch'"],
		["delete's options", func(c): return await c.delete("character", "c1", {"force": true}), "unknown option 'force'"],
		["a key not a String", func(c): return await c.create("character", {}, {"idempotency_key": 5}), "idempotency_key is a String"],
		["links' edit", func(c): return await c.edit_links("character", "c1", "friends", {"adds": ["c2"]}), "unknown option 'adds'"],
		["links' ids", func(c): return await c.edit_links("character", "c1", "friends", {"add": "c2"}), "add is an Array of Strings"],
		["links' field", func(c): return await c.edit_links("character", "c1", "", {"add": ["c2"]}), "a link field's name"],
		["bulk nothing", func(c): return await c.bulk([]), "at least one item"],
		["bulk no type", func(c): return await c.bulk([{"element": {}}]), "items[0] needs a type"],
		["bulk a stray", func(c): return await c.bulk([{"type": "character"}, "Ana"]), "items[1] is"],
		["bulk an item's key", func(c): return await c.bulk([{"type": "character", "elements": {}}]), "items[0]: unknown key 'elements'"],
		["bulk an element", func(c): return await c.bulk([{"type": "character", "element": "Ana"}]), "a Dictionary or an OWElement"],
		["bulk's atomic", func(c): return await c.bulk([{"type": "character"}], {"atomic": "yes"}), "atomic is a bool"],
		["bulk's options", func(c): return await c.bulk([{"type": "character"}], {"idempotencyKey": "k"}), "unknown option 'idempotencyKey'"],
	]
	for case in cases:
		var fake = Fake.new()
		var r: OWClient.Reply = await case[1].call(_make(fake))
		_refused(t, r, fake, case[2], case[0])
	t.done()

func test_a_patch_takes_a_single_link_and_a_scalar(t) -> void:
	var fake = Fake.new()
	fake.body = ELEMENT
	var r: OWClient.Reply = await _make(fake).patch("character", "c1", {"birthplace": "l1", "level": 4, "x_list": ["a"]})
	t.ok(r.ok, "a single link, a number, an extension's array (%s)" % r.error)
	t.eq(fake.last().body, "{\"birthplace\":\"l1\",\"level\":4,\"x_list\":[\"a\"]}", "")
	t.done()

# -- The answers ------------------------------------------------------------------------------------------------------

func test_a_202_is_a_proposal_not_an_element(t) -> void:
	const PROPOSED := "{\"proposal\":{\"id\":\"pr1\",\"status\":\"open\",\"fields\":{\"name\":\"Bo\"}}}"
	var calls := [
		["upsert", func(c): return await c.upsert("character", "c1", {"name": "Bo"})],
		["patch", func(c): return await c.patch("character", "c1", {"name": "Bo"})],
		["edit_links", func(c): return await c.edit_links("character", "c1", "friends", {"add": ["c2"]})],
	]
	for call in calls:
		var fake = Fake.new()
		fake.then(202, PROPOSED)
		var r: OWClient.Reply = await call[1].call(_make(fake, "ow_w_seat", "ow_s_x", {"agent": true}))
		var e: OWApiError = r.error
		t.ok(e != null and e.kind == OWApiError.PROPOSED and e.is_proposed(), "%s: a proposal (%s)" % [call[0], e])
		if e == null:
			continue
		t.eq([e.status, e.proposal], [202, {"id": "pr1", "status": "open", "fields": {"name": "Bo"}}], "%s: the row" % call[0])
		t.ok(e.message.contains("became a proposal"), e.message)
		t.eq(r.value, null, "%s: no element" % call[0])
		t.ok(r.response != null and r.response.status == 202, "")
		fake.then(202, "{}")
		e = (await call[1].call(_make(fake))).error
		t.ok(e != null and e.kind == OWApiError.ANSWER and e.status == 202 and not e.is_proposed(),
			"%s: a 202 without a proposal is no element and no made-up proposal (%s)" % [call[0], e])
	t.done()

func test_conflicts_and_their_helpers(t) -> void:
	var fake = Fake.new()
	fake.then(412, "{\"error\":{\"type\":\"conflict\",\"code\":\"precondition_failed\",\"message\":\"changed\"},\"current\":{\"id\":\"c1\",\"name\":\"Cy\",\"change_seq\":43}}")
	var e: OWApiError = (await _make(fake).patch("character", "c1", {"name": "Bo"}, {"if_match": 41})).error
	t.ok(e.is_precondition_failed(), "412 precondition_failed")
	t.eq(e.current(), {"id": "c1", "name": "Cy", "change_seq": 43.0}, "the element as it is now")
	t.ok(not e.is_proposed(), "")
	fake.then(409, "{\"error\":{\"code\":\"id_conflict\",\"message\":\"taken\"}}")
	e = (await _make(fake).create("character", {"id": "c1"})).error
	t.ok(e.is_id_conflict() and not e.is_idempotency_conflict(), "a create that already landed")
	t.eq(e.current(), null, "current only on a 412")
	fake.then(409, "{\"error\":{\"code\":\"idempotency_error\"}}")
	e = (await _make(fake).create("character", {}, {"idempotency_key": "k"})).error
	t.ok(e.is_idempotency_conflict() and not e.is_retryable(), "the same key with another body")
	fake.then(409, "{\"error\":{\"code\":\"idempotency_in_flight\"}}")
	t.ok((await _make(fake).bulk([{"type": "character"}], {"idempotency_key": "k"})).error.is_retryable(), "in flight: retry")
	fake.then(422, "{\"error\":{\"code\":\"known_of_not_writable\"}}")
	t.ok((await _make(fake).upsert("character", "c1", {})).error.is_known_of_not_writable(), "")
	t.ok(not OWApiError.from_response(412, "<html>", {}).is_precondition_failed(), "a proxy's 412 is not keel's")
	t.eq(OWApiError.from_response(412, "<html>", {}).current(), null, "")
	t.done()

func test_bulk_reads_its_slots(t) -> void:
	var fake = Fake.new()
	fake.then(200, "{\"errors\":true,\"items\":[{\"status\":201,\"id\":\"a\",\"created_at\":\"t0\",\"updated_at\":\"t1\"},"
		+ "{\"status\":422,\"id\":\"b\",\"error\":{\"type\":\"invalid_request\",\"code\":\"invalid_link\",\"message\":\"no such\",\"param\":\"friends\"}},"
		+ "{\"status\":202,\"id\":\"c\",\"proposal\":{\"id\":\"pr1\"}}]}", {"Idempotent-Replay": "TRUE"})
	var r: OWClient.Reply = await _make(fake).bulk([{"type": "character"}, {"type": "character"}, {"type": "character"}])
	var result: OWClient.BulkResult = r.value
	t.ok(result.errors, "")
	t.ok(result.was_replay, "the header read by any case")
	t.eq(result.items.size(), 3, "")
	var a: OWClient.BulkSlot = result.items[0]
	t.eq([a.status, a.id, a.created_at, a.updated_at, a.error, a.proposal], [201, "a", "t0", "t1", null, null], "a 201")
	t.ok(a.succeeded() and not a.is_proposed(), "")
	var b: OWClient.BulkSlot = result.items[1]
	t.ok(not b.succeeded(), "")
	t.eq([b.error.kind, b.error.status, b.error.code, b.error.param, b.error.message], [OWApiError.API, 422, "invalid_link", "friends", "no such"],
		"the slot's error as an OWApiError, its status the slot's")
	t.ok(b.error.is_validation_error(), "")
	var c: OWClient.BulkSlot = result.items[2]
	t.ok(c.is_proposed() and c.succeeded(), "a 202 slot: never thrown")
	t.eq(c.proposal, {"id": "pr1"}, "")
	t.eq(result.failed(), [b], "")
	t.eq(result.succeeded_count(), 2, "")
	t.ok(not result.all_succeeded(), "")
	fake.then(200, "{\"errors\":false,\"items\":[{\"status\":201,\"id\":\"a\"}]}")
	result = (await _make(fake).bulk([{"type": "character"}])).value
	t.ok(result.all_succeeded() and not result.was_replay, "no header: not a replay")
	fake.then(200, "{\"errors\":false,\"items\":{}}")
	t.ok((await _make(fake).bulk([{"type": "character"}])).error.kind == OWApiError.ANSWER, "items that are not a list")
	t.done()

func test_a_write_answer_that_is_not_the_element(t) -> void:
	var fake = Fake.new()
	fake.then(201, "[1]")
	t.eq((await _make(fake).create("character", {})).error.kind, OWApiError.ANSWER, "")
	fake.then(200, "<html>")
	t.eq((await _make(fake).delete("character", "c1")).error.kind, OWApiError.ANSWER, "a delete's body, when there is one, is JSON")
	fake.then(200, "{\"ok\":true}")
	t.ok((await _make(fake).delete("character", "c1")).ok, "")
	fake.fail("reset")
	var e: OWApiError = (await _make(fake).patch("character", "c1", {})).error
	t.ok(e.kind == OWApiError.TRANSPORT and e.message.contains("PATCH /character/c1/"), str(e))
	t.done()
