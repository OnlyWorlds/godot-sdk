extends RefCounted
## OWClient's read calls through a fake transport (tests/fake_transport.gd): no test touches the network. Each call's
## request (method, URL, query, headers, body) on each credential, each refusal before sending, keel's error envelope,
## the cursor walk and the change feed's tip poll. The credential rules are the Unity SDK's OWClient
## (RequestWithResponseAsync), held call by call as its OWClientTests hold them. The one live test reads production's
## /health/ only with OW_LIVE=1 set, and is skipped otherwise.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const PAGE := "{\"data\":[],\"has_more\":false,\"next_cursor\":null}"

func _make(fake, key: Variant = "ow_w_test", pin: Variant = "0000", world: Variant = null) -> OWClient:
	var config := {"api_key": key, "api_pin": pin, "base_url": BASE, "transport": fake}
	if world != null:
		config["world"] = world
	return OWClient.new(config)

## The URL's path under BASE, without its query.
static func _path(url: String) -> String:
	return url.get_slice("?", 0).trim_prefix(BASE)

## The URL's query as [name, value] pairs, decoded, in order.
static func _query(url: String) -> Array:
	var out := []
	if not url.contains("?"):
		return out
	for pair in url.get_slice("?", 1).split("&"):
		out.append([pair.get_slice("=", 0).uri_decode(), pair.substr(pair.find("=") + 1).uri_decode()])
	return out

static func _names(url: String) -> Array:
	return _query(url).map(func(p): return p[0])

# -- The read calls, swept over every credential ---------------------------------------------------------------------

## Each read call: [name, PIN on a prefixed key, an account token with world sends it, a keyless client sends it, run].
## The answer every call reads is the fake's default body below.
func _calls() -> Array:
	return [
		["health", false, true, true, func(c): return await c.health()],
		["world", false, true, true, func(c): return await c.get_world()],
		["me", true, false, false, func(c): return await c.me()],
		["members", false, true, false, func(c): return await c.members()],
		["list", false, true, true, func(c): return await c.list("location")],
		["list (typed options)", false, true, true, func(c): return await c.list("location",
			{"ids": ["l1"], "created_by": "owner", "expand": ["zone"], "view_as": "public", "name_contains": "harb"})],
		["list all", false, true, true, func(c): return await c.list_all("location")],
		["get", false, true, true, func(c): return await c.get_element("location", "l1")],
		["changes", false, false, false, func(c): return await c.changes()],
		["changes head", false, false, false, func(c): return await c.changes_head()],
	]

const ANSWER := "{\"data\":[],\"has_more\":false,\"changes\":[],\"head\":0,\"cursor\":\"0\",\"id\":\"l1\"}"

## Every read call on its own client; the request each sent, as [name, pin expected, request]. A call such a client
## does not send is checked refused with nothing sent, and left out.
func _sweep(t, key: Variant, pin: Variant, world: Variant = null) -> Array:
	var sent := []
	for call in _calls():
		var fake = Fake.new()
		fake.body = ANSWER
		var c := _make(fake, key, pin, world)
		var r: OWClient.Reply = await call[4].call(c)
		var account: bool = key is String and key.begins_with("ow_a_")
		var keyless: bool = key == null or key == ""
		var sends: bool = (call[2] if account else call[3]) if (account or keyless) else true
		if not sends:
			t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused on this client" % call[0])
			t.eq(fake.calls.size(), 0, "%s: nothing sent" % call[0])
			continue
		t.ok(r.error == null, "%s: answered (%s)" % [call[0], r.error])
		t.eq(fake.calls.size(), 1, "%s: one request" % call[0])
		if fake.calls.size() == 1:
			t.eq(fake.last().method, "GET", "%s: a GET" % call[0])
			t.eq(fake.last().body, null, "%s: no body" % call[0])
			sent.append([call[0], call[1], fake.last()])
	return sent

## True for health, after checking it carried no credential at all.
static func _sent_with_none(t, name: String, sent) -> bool:
	if name != "health":
		return false
	for h in ["API-Key", "API-Pin", "Authorization"]:
		t.ok(not sent.headers.has(h), "health: no %s" % h)
	t.ok(not sent.url.contains("world="), "health: no world=")
	return true

func test_pin_world_key_with_a_pin_only_on_me(t) -> void:
	var all := await _sweep(t, "ow_w_test", "1234")
	t.eq(all.size(), 10, "every read call sent")
	for s in all:
		if _sent_with_none(t, s[0], s[2]):
			continue
		t.eq(s[2].headers.get("API-Key"), "ow_w_test", s[0])
		t.eq(s[2].headers.get("API-Pin"), "1234" if s[1] else null, "%s: the PIN only where keel checks it" % s[0])
		t.ok(not s[2].headers.has("Authorization"), "%s: no Bearer" % s[0])
		t.ok(not s[2].url.contains("world="), "%s: a world key names its own world" % s[0])
	t.done()

func test_pin_legacy_key_on_every_request(t) -> void:
	# A 10-digit legacy key needs its PIN on reads of a world with one (v1 parity).
	for s in await _sweep(t, "0123456789", "1234"):
		if _sent_with_none(t, s[0], s[2]):
			continue
		t.eq(s[2].headers.get("API-Key"), "0123456789", s[0])
		t.eq(s[2].headers.get("API-Pin"), "1234", s[0])
	t.done()

func test_pin_read_key_never_without_one(t) -> void:
	for s in await _sweep(t, "ow_r_share", null):
		if _sent_with_none(t, s[0], s[2]):
			continue
		t.eq(s[2].headers.get("API-Key"), "ow_r_share", s[0])
		t.ok(not s[2].headers.has("API-Pin"), s[0])
	t.done()

func test_pin_unknown_key_reads_as_a_prefixed_key(t) -> void:
	# A key of no known shape is sent as API-Key, its PIN on /me alone, as Unity's OWKeyKind.Unknown is.
	for s in await _sweep(t, "abc", "1234"):
		if _sent_with_none(t, s[0], s[2]):
			continue
		t.eq(s[2].headers.get("API-Key"), "abc", s[0])
		t.eq(s[2].headers.get("API-Pin"), "1234" if s[1] else null, s[0])
	t.done()

func test_account_token_bearer_never_a_pin_world_on_its_reads(t) -> void:
	var all := await _sweep(t, "ow_a_acct", "1234", "w1")
	t.eq(all.map(func(s): return s[0]), ["health", "world", "members", "list", "list (typed options)", "list all", "get"],
		"the health pulse, the world reads and the roster sent; /me and the feed refused")
	for s in all:
		if _sent_with_none(t, s[0], s[2]):
			continue
		t.eq(s[2].headers.get("Authorization"), "Bearer ow_a_acct", s[0])
		t.ok(not s[2].headers.has("API-Pin"), "%s: an account token never sends the PIN" % s[0])
		t.ok(not s[2].headers.has("API-Key"), s[0])
		t.eq(_names(s[2].url).back(), "world", "%s: world= last" % s[0])
		t.eq(_query(s[2].url).back(), ["world", "w1"], s[0])
	t.done()

func test_keyless_reader_sends_no_credential_and_world(t) -> void:
	var all := await _sweep(t, null, "1234", "w1")
	t.eq(all.map(func(s): return s[0]), ["health", "world", "list", "list (typed options)", "list all", "get"],
		"the health pulse and the world reads; the roster has no public reader")
	for s in all:
		for h in ["API-Key", "API-Pin", "Authorization"]:
			t.ok(not s[2].headers.has(h), "%s: no %s" % [s[0], h])
		if s[0] != "health":
			t.eq(_query(s[2].url).back(), ["world", "w1"], s[0])
	t.done()

func test_account_token_without_world_refuses_the_world_reads(t) -> void:
	for call in _calls():
		var fake = Fake.new()
		fake.body = ANSWER
		var r: OWClient.Reply = await call[4].call(_make(fake, "ow_a_acct", null))
		if call[0] == "health":
			t.ok(r.error == null, "health needs no world")
			continue
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused" % call[0])
		t.eq(fake.calls.size(), 0, "%s: nothing sent" % call[0])
		if r.error != null:
			t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so (%s)" % [call[0], r.error.message])
	t.done()

func test_world_reads_paths_and_world_placement(t) -> void:
	var fake = Fake.new()
	fake.body = ANSWER
	var c := _make(fake, "ow_a_acct", null, "w 1")
	await c.get_world()
	t.eq(fake.last().url, BASE + "/world/?world=w%201", "the world GET, the world escaped")
	await c.get_element("character", "c1", {"fields": ["name"]})
	t.eq(fake.last().url, BASE + "/character/c1/?fields=name&world=w%201", "world= beside the get's own query")
	await c.members()
	t.eq(fake.last().url, BASE + "/members/?world=w%201", "the roster names its world")
	await c.health()
	t.eq(fake.last().url, BASE + "/health/", "the health pulse names none")
	t.done()

# -- Construction ------------------------------------------------------------------------------------------------------

func test_config_refusals_answer_every_call_with_nothing_sent(t) -> void:
	var cases := [
		[{"api_key": "ow_w_k", "world": "w1"}, "A world key reads its own world"],
		[{"api_key": "0123456789", "world": "w1"}, "A world key reads its own world"],
		[{"api_key": "ow_r_k", "world": "w1"}, "A world key reads its own world"],
		[{"api_key": "ow_a_k", "world": ""}, "world is a world's id"],
		[{"api_key": "ow_a_k", "world": "  "}, "world is a world's id"],
		[{"world": " \t"}, "world is a world's id"],
		[{}, "An API key is required"],
		[{"api_key": ""}, "An API key is required"],
		[{"api_key": "ow_w_k", "api_pni": "0000"}, "unknown key 'api_pni'"],
		[{"api_key": 12}, "api_key is a String"],
		[{"api_key": "ow_a_k", "world": 7}, "world is a world's id"],
		[{"api_key": "ow_w_k", "page_size": "10"}, "page_size is an int"],
	]
	for case in cases:
		var fake = Fake.new()
		var config: Dictionary = case[0].duplicate()
		config["transport"] = fake
		var c := OWClient.new(config)
		t.ok(c.error.contains(case[1]), "%s: %s (got '%s')" % [case[0], case[1], c.error])
		var r: OWClient.Reply = await c.get_world()
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: a call is refused" % case[0])
		t.eq(fake.calls.size(), 0, "%s: nothing sent" % case[0])
	t.done()

func test_config_defaults_and_the_built_client(t) -> void:
	var c := OWClient.new({"api_key": "ow_w_k"})
	t.eq(c.error, "", "built")
	t.eq(c.base_url, "https://www.onlyworlds.com/api/v2", "production by default")
	t.eq(c.page_size, 100, "100 a page")
	t.ok(c.transport is OWHttpTransport, "Godot's own HTTP when none is given")
	t.eq(c.key_kind, OWClient.KEY_WRITE, "ow_w_")
	t.eq(OWClient.new({"api_key": "ow_a_k", "world": "w1", "base_url": "http://x/api/v2//", "page_size": 0}).base_url,
		"http://x/api/v2", "trailing slashes trimmed")
	t.eq(OWClient.new({"api_key": "ow_w_k", "page_size": 0}).page_size, 100, "a page size of 0 is the default")
	t.eq(OWClient.new({"api_key": "ow_w_k", "page_size": 7}).page_size, 7, "")
	var kinds := {"ow_w_x": OWClient.KEY_WRITE, "ow_r_x": OWClient.KEY_READ, "ow_a_x": OWClient.KEY_ACCOUNT,
		"0123456789": OWClient.KEY_LEGACY, "012345678": OWClient.KEY_UNKNOWN, "01234567890": OWClient.KEY_UNKNOWN,
		"ow_s_x": OWClient.KEY_UNKNOWN}
	for k in kinds:
		t.eq(OWClient.key_kind_of(k), kinds[k], k)
	t.eq(OWClient.key_kind_of(""), OWClient.KEY_NONE, "no key")
	var keyless := OWClient.new({"world": "w1"})
	t.eq(keyless.error, "", "a keyless reader with a world")
	t.eq(keyless.key_kind, OWClient.KEY_NONE, "")
	t.eq(keyless.world, "w1", "")
	t.done()

# -- list -------------------------------------------------------------------------------------------------------------

func test_list_sends_its_options_in_order_escaped(t) -> void:
	var fake = Fake.new()
	fake.body = PAGE
	var c := _make(fake)
	await c.list("character", {
		"view_as": "public", "subtype": "u", "supertype": "s w", "name_contains": "m&n", "name": "n",
		"created_by": "owner", "ids": ["c1", "c2"], "fields": PackedStringArray(["name", "supertype"]),
		"expand": ["friends"], "cursor": "c=1", "limit": 5, "filter": {"zone": "", "birthplace": "p1"}})
	t.eq(_path(fake.last().url), "/character/", "")
	t.eq(fake.last().url.get_slice("?", 1),
		"limit=5&cursor=c%3D1&expand=friends&fields=name%2Csupertype&ids=c1%2Cc2&created_by=owner&name=n"
		+ "&name__icontains=m%26n&supertype=s%20w&subtype=u&birthplace=p1&zone=&as=public",
		"limit, cursor, expand, fields, ids, created_by, the named filters, the filter by field name, as last")
	await c.list("character")
	t.eq(fake.last().url, BASE + "/character/?limit=100", "the page size alone")
	await c.list("character", {"cursor": "", "ids": [], "expand": [], "name": ""})
	t.eq(fake.last().url, BASE + "/character/?limit=100", "an empty option sends nothing")
	await c.list("character", {"filter": {"ids": "c9", "as": "public"}})
	t.eq(fake.last().url, BASE + "/character/?limit=100&as=public&ids=c9",
		"a filter key no typed option sends this time goes out once, in field order")
	t.done()

func test_list_reads_typed_elements(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"data\":[{\"id\":\"c1\",\"name\":\"Ana\",\"level\":3,\"x_tool\":{\"a\":1}},{\"id\":\"c2\",\"name\":\"Bo\"}],\"has_more\":true,\"next_cursor\":\"n2\"}"
	var r: OWClient.Reply = await _make(fake).list("character")
	t.ok(r.ok, "answered")
	var page: OWClient.Page = r.value
	t.eq(page.data.size(), 2, "two rows")
	t.ok(page.data[0] is OWCharacter, "a Character's own model")
	t.eq((page.data[0] as OWCharacter).level, 3, "an int field reads as an int")
	t.eq(page.data[0].get_value("x_tool"), {"a": 1.0}, "an extension key kept as served")
	t.eq(page.data[1].name, "Bo", "")
	t.ok(page.has_more, "")
	t.eq(page.next_cursor, "n2", "")
	fake.body = "{\"data\":[{\"id\":\"z\"}],\"has_more\":false,\"next_cursor\":null}"
	page = (await _make(fake).list("unknown_type")).value
	t.ok(page.data[0] is OWElement and page.data[0].get_type() == &"unknown_type", "a type not among the 22 kept whole")
	t.eq(page.next_cursor, "", "a null cursor is none")
	t.done()

func test_list_refusals_send_nothing(t) -> void:
	var cases := [
		[{"filter": {"world": "w2"}}, "world is not a filter"],
		[{"filter": {"Parent": "p"}}, "'Parent' is not a field name"],
		[{"filter": {"": "p"}}, "'' is not a field name"],
		[{"filter": {"2nd": "p"}}, "'2nd' is not a field name"],
		[{"filter": {"limit": "9"}}, "'limit' is sent by its own option"],
		[{"name": "n", "filter": {"name": "m"}}, "'name' is sent by its own option"],
		[{"view_as": "public", "filter": {"as": "public"}}, "'as' is sent by its own option"],
		[{"filter": {"zone": 3}}, "filter values are Strings"],
		[{"filter": "zone=z"}, "filter is a Dictionary"],
		[{"limt": 5}, "unknown option 'limt'"],
		[{"limit": "5"}, "limit is an int"],
		[{"ids": "c1,c2"}, "ids is an Array"],
		[{"ids": [1]}, "ids is an Array"],
		[{"name": 3}, "name is a String"],
	]
	for case in cases:
		var fake = Fake.new()
		var r: OWClient.Reply = await _make(fake).list("character", case[0])
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains(case[1]),
			"%s: %s (got %s)" % [case[0], case[1], r.error])
		t.eq(fake.calls.size(), 0, "%s: nothing sent" % [case[0]])
	t.done()

# -- list_all: the cursor walk ----------------------------------------------------------------------------------------

func test_list_all_walks_every_page_by_has_more(t) -> void:
	var fake = Fake.new()
	# The middle page is short: a short page is no end (keel clamps the limit at 1000 silently).
	fake.then(200, "{\"data\":[{\"id\":\"a\"},{\"id\":\"b\"}],\"has_more\":true,\"next_cursor\":\"p2\"}")
	fake.then(200, "{\"data\":[{\"id\":\"c\"}],\"has_more\":true,\"next_cursor\":\"p3\"}")
	fake.then(200, "{\"data\":[{\"id\":\"d\"}],\"has_more\":false,\"next_cursor\":null}")
	var pages := []
	var r: OWClient.Reply = await _make(fake).list_all("location", {"supertype": "City", "filter": {"zone": "z1"}},
		func(n, count): pages.append([n, count]))
	t.ok(r.ok, "answered")
	t.eq(r.value.map(func(e): return e.id), ["a", "b", "c", "d"], "every element, in order")
	t.ok(r.value[0] is OWLocation, "typed")
	t.eq(fake.calls.size(), 3, "three pages")
	t.eq(fake.calls.map(func(q): return _query(q.url)), [
		[["limit", "100"], ["supertype", "City"], ["zone", "z1"]],
		[["limit", "100"], ["cursor", "p2"], ["supertype", "City"], ["zone", "z1"]],
		[["limit", "100"], ["cursor", "p3"], ["supertype", "City"], ["zone", "z1"]],
	], "each page's cursor passed back, every filter on every page")
	t.eq(pages, [[1, 2], [2, 3], [3, 4]], "on_page: the page's number and the count so far")
	t.done()

func test_list_all_starts_at_a_given_cursor_and_stops_without_one(t) -> void:
	var fake = Fake.new()
	fake.then(200, "{\"data\":[{\"id\":\"a\"}],\"has_more\":true,\"next_cursor\":null}")
	var r: OWClient.Reply = await _make(fake).list_all("location", {"cursor": "k7"})
	t.eq(_query(fake.last().url), [["limit", "100"], ["cursor", "k7"]], "the walk starts where it was told")
	t.eq(fake.calls.size(), 1, "has_more with no cursor ends the walk rather than looping")
	t.eq(r.value.size(), 1, "")
	t.done()

func test_list_all_refuses_a_page_that_repeats_its_cursor(t) -> void:
	var fake = Fake.new()
	fake.then(200, "{\"data\":[{\"id\":\"a\"}],\"has_more\":true,\"next_cursor\":\"p2\"}")
	fake.then(200, "{\"data\":[{\"id\":\"b\"}],\"has_more\":true,\"next_cursor\":\"p2\"}")
	var r: OWClient.Reply = await _make(fake).list_all("location")
	t.eq(fake.calls.size(), 2, "the second page is not read again")
	t.ok(r.error != null and r.error.kind == OWApiError.ANSWER and r.error.message.contains("answered the cursor it was sent"),
		"an error, not a loop (%s)" % r.error)
	t.done()

func test_list_all_stops_at_an_error(t) -> void:
	var fake = Fake.new()
	fake.then(200, "{\"data\":[{\"id\":\"a\"}],\"has_more\":true,\"next_cursor\":\"p2\"}")
	fake.then(429, "{\"error\":{\"type\":\"rate_limit\",\"code\":\"too_many_requests\",\"message\":\"slow\"}}", {"retry-after": "3"})
	var r: OWClient.Reply = await _make(fake).list_all("location")
	t.eq(fake.calls.size(), 2, "")
	t.ok(r.error != null and r.error.status == 429, "the page's error")
	t.eq(r.error.retry_after if r.error else null, 3, "Retry-After read")
	t.eq(r.value, null, "no half list")
	t.done()

# -- get --------------------------------------------------------------------------------------------------------------

func test_get_element_sends_its_options_and_reads_the_model(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"p1\",\"name\":\"Gate\",\"element_type\":\"location\",\"element_id\":\"l1\",\"x\":4}"
	var c := _make(fake)
	var r: OWClient.Reply = await c.get_element("pin", "p1", {"view_as": "m1", "fields": ["name"], "expand": ["map", "zone"]})
	t.eq(fake.last().url, BASE + "/pin/p1/?expand=map%2Czone&fields=name&as=m1", "expand, fields, as")
	t.ok(r.value is OWPin, "a Pin's own model")
	t.eq(r.value.get_value("element_type"), "location", "")
	await c.get_element("pin", "a.b_c-D9")
	t.eq(fake.last().url, BASE + "/pin/a.b_c-D9/", "an id of one segment goes out as given")
	for bad in [{"viewAs": "x"}, {"fields": "name"}, {"view_as": 1}]:
		var f2 = Fake.new()
		var refused: OWClient.Reply = await _make(f2).get_element("pin", "p1", bad)
		t.ok(refused.error != null and refused.error.kind == OWApiError.REFUSED, "%s refused" % [bad])
		t.eq(f2.calls.size(), 0, "nothing sent")
	t.done()

func test_get_element_answer_not_an_object(t) -> void:
	var fake = Fake.new()
	fake.body = "[1]"
	var r: OWClient.Reply = await _make(fake).get_element("pin", "p1")
	t.ok(r.error != null and r.error.kind == OWApiError.ANSWER, "an answer that is not the element is an error")
	fake.body = "<html>"
	r = await _make(fake).get_world()
	t.ok(r.error != null and r.error.kind == OWApiError.ANSWER and r.error.status == 200, "a 200 that is not JSON")
	t.done()

# -- me, members, health, the world -------------------------------------------------------------------------------------

const ME := "{\"world\":{\"id\":\"w1\",\"name\":\"W\"},\"scope\":\"write\",\"kind\":\"owner\",\"role\":\"owner\",\"membership\":null,\"character\":null,\"lenses\":[],\"reading_aids\":{\"charter\":{\"id\":\"l1\",\"name\":\"House\",\"rules\":[],\"skill\":[]},\"guide\":null,\"domains\":[{\"id\":\"d1\",\"name\":\"Port\",\"sentence\":\"S\",\"hubs\":[]}],\"strand\":{\"narrative\":{\"id\":\"n1\",\"name\":\"Tale\"},\"event\":null,\"location\":null,\"character\":null,\"now\":null,\"same\":null}}}"

func test_me_and_its_reading_aids(t) -> void:
	var fake = Fake.new()
	fake.body = ME
	var r: OWClient.Reply = await _make(fake, "ow_w_k", "4821").me()
	t.eq(fake.last().url, BASE + "/me/", "GET /me/")
	t.eq(fake.last().headers.get("API-Pin"), "4821", "the connection test carries the PIN")
	t.eq(r.value["role"], "owner", "the body as served")
	var aids := OWCharter.served(r.value)
	t.ok(aids != null, "OWCharter.served reads its reading_aids")
	t.eq(aids.charter["name"], "House", "")
	t.eq(aids.domains.size(), 1, "")
	t.eq(aids.strand.narrative, {"id": "n1", "name": "Tale"}, "the strand fourth")
	t.done()

func test_members_reads_the_rows(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"data\":[{\"id\":null,\"kind\":\"owner\",\"role\":\"owner\"},{\"id\":\"m1\",\"kind\":\"agent\",\"role\":\"contributor\"}]}"
	var r: OWClient.Reply = await _make(fake).members()
	t.eq(fake.last().url, BASE + "/members/", "")
	t.eq(r.value.size(), 2, "the rows of {data}")
	t.eq(r.value[1]["kind"], "agent", "")
	fake.body = "{}"
	t.eq((await _make(fake).members()).value, [], "no rows: an empty list")
	t.done()

func test_health_and_world_are_the_bodies_as_served(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"status\":\"ok\",\"service\":\"keel\"}"
	var r: OWClient.Reply = await _make(fake).health()
	t.eq(fake.last().url, BASE + "/health/", "")
	t.eq(r.value, {"status": "ok", "service": "keel"}, "")
	fake.body = "{\"id\":\"w1\",\"name\":\"W\",\"time_range_current\":12}"
	r = await _make(fake).get_world()
	t.eq(fake.last().url, BASE + "/world/", "")
	t.eq(r.value["time_range_current"], 12.0, "as parsed")
	t.done()

# -- The change feed ----------------------------------------------------------------------------------------------------

func test_changes_page(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"changes\":[{\"op\":\"upsert\",\"type\":\"character\",\"id\":\"c1\",\"change_seq\":41,\"updated_at\":\"2026-10-30T10:00:00Z\",\"element\":{\"id\":\"c1\",\"name\":\"Ana\",\"level\":2}},{\"op\":\"delete\",\"type\":\"pin\",\"id\":\"p1\",\"change_seq\":42,\"deleted_at\":\"2026-10-30T11:00:00Z\",\"deleted_by\":\"m1\",\"deleted_via\":\"api\",\"deleted_client\":\"atlas\",\"reason\":\"hidden\"}],\"cursor\":\"4:abc\",\"has_more\":true,\"head\":42,\"epoch\":3,\"epoch_reason\":\"view\"}"
	var c := OWClient.new({"api_key": "ow_r_k", "base_url": BASE, "transport": fake, "page_size": 5000})
	var r: OWClient.Reply = await c.changes({"since": "4:a b", "after": "2026-10-22T00:00:00Z"})
	t.eq(fake.last().url, BASE + "/changes/?since=4%3Aa%20b&limit=1000&after=2026-10-22T00%3A00%3A00Z",
		"since, limit (the page size, at most 1000), after")
	var page: OWClient.ChangesPage = r.value
	t.eq(page.cursor, "4:abc", "")
	t.ok(page.has_more, "")
	t.eq(page.head, 42, "an int")
	t.eq(page.epoch, 3, "an int")
	t.eq(page.epoch_reason, "view", "")
	t.ok(not page.unchanged, "a page is never unchanged")
	t.eq(page.changes.size(), 2, "")
	var up: OWClient.Change = page.changes[0]
	t.eq([up.op, up.type, up.id, up.change_seq, up.updated_at], ["upsert", "character", "c1", 41, "2026-10-30T10:00:00Z"], "")
	t.ok(up.element is OWCharacter and up.element.level == 2, "an upsert's element, typed")
	var del: OWClient.Change = page.changes[1]
	t.eq([del.op, del.deleted_at, del.deleted_by, del.deleted_via, del.deleted_client, del.reason, del.element],
		["delete", "2026-10-30T11:00:00Z", "m1", "api", "atlas", "hidden", null], "a delete's row")
	await c.changes()
	t.eq(fake.last().url, BASE + "/changes/?limit=1000", "from the start")
	await _make(fake).changes()
	t.eq(fake.last().url, BASE + "/changes/?limit=100", "the page size")
	for bad in [{"cursor": "x"}, {"since": 4}, {"head": true}]:
		var f2 = Fake.new()
		var refused: OWClient.Reply = await _make(f2).changes(bad)
		t.ok(refused.error != null and refused.error.kind == OWApiError.REFUSED, "%s refused" % [bad])
		t.eq(f2.calls.size(), 0, "nothing sent")
	t.done()

func test_changes_cursor_served_as_a_number_is_a_string(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"changes\":[],\"cursor\":17,\"has_more\":false,\"head\":17,\"epoch\":null}"
	var page: OWClient.ChangesPage = (await _make(fake).changes()).value
	t.eq(page.cursor, "17", "never \"17.0\"")
	t.eq(page.epoch, null, "no epoch for this key")
	t.eq(page.epoch_reason, null, "")
	t.done()

func test_changes_head_polls_with_its_tag(t) -> void:
	var fake = Fake.new()
	var c := _make(fake)
	fake.then(200, "{\"head\":9,\"cursor\":9,\"epoch\":null,\"epoch_reason\":null}", {"etag": "W/\"9:-\""})
	fake.then(304, "", {})
	fake.then(200, "{\"head\":10,\"cursor\":\"10\",\"epoch\":2}", {"ETag": "\"10:2\""})
	var first: OWClient.ChangesPage = (await c.changes_head()).value
	t.eq(fake.last().url, BASE + "/changes/?head=true", "head=true alone")
	t.ok(not fake.last().headers.has("If-None-Match"), "nothing held: no tag")
	t.eq([first.head, first.cursor, first.epoch, first.unchanged], [9, "9", null, false], "the tip")
	var second: OWClient.ChangesPage = (await c.changes_head()).value
	t.eq(fake.last().headers.get("If-None-Match"), "W/\"9:-\"", "the tag sent back exactly as received")
	t.eq([second.head, second.cursor, second.epoch, second.unchanged], [9, "9", null, true], "a 304: the last 200's tip")
	var third: OWClient.ChangesPage = (await c.changes_head()).value
	t.eq(fake.last().headers.get("If-None-Match"), "W/\"9:-\"", "")
	t.eq([third.head, third.cursor, third.epoch, third.unchanged], [10, "10", 2, false], "moved")
	await c.changes_head()
	t.eq(fake.last().headers.get("If-None-Match"), "\"10:2\"", "the newest tag, read case-insensitively")
	t.done()

func test_changes_head_304_with_nothing_held_is_an_error(t) -> void:
	var fake = Fake.new()
	fake.then(304, "", {})
	var r: OWClient.Reply = await _make(fake).changes_head()
	t.ok(r.error != null and r.error.status == 304 and r.error.kind == OWApiError.API, "never a made-up head")
	t.done()

func test_resync_required_drops_the_tag(t) -> void:
	const RESYNC := "{\"error\":{\"type\":\"conflict\",\"code\":\"resync_required\",\"message\":\"walk again\",\"reason\":\"role\"}}"
	for from_page in [false, true]:
		var fake = Fake.new()
		var c := _make(fake)
		fake.then(200, "{\"head\":9,\"cursor\":\"9\"}", {"etag": "\"9\""})
		fake.then(409, RESYNC, {})
		fake.then(200, "{\"head\":9,\"cursor\":\"9\"}", {"etag": "\"9\""})
		await c.changes_head()
		var r: OWClient.Reply
		if from_page:
			r = await c.changes({"since": "9"})
		else:
			r = await c.changes_head()
		t.ok(r.error != null and r.error.is_resync_required(), "the 409")
		t.eq(r.error.resync_reason() if r.error else null, "role", "its reason")
		await c.changes_head()
		t.ok(not fake.last().headers.has("If-None-Match"), "the next tip read is a full one (from a page: %s)" % from_page)
	t.done()

# -- keel's error envelope ----------------------------------------------------------------------------------------------

func test_the_error_envelope(t) -> void:
	var fake = Fake.new()
	fake.then(404, "{\"error\":{\"type\":\"invalid_request\",\"code\":\"not_found\",\"message\":\"No such character.\",\"param\":\"id\",\"doc_url\":\"https://onlyworlds.com/docs/errors#not_found\"}}")
	var r: OWClient.Reply = await _make(fake).get_element("character", "c9")
	var e: OWApiError = r.error
	t.eq([e.kind, e.status, e.type, e.code, e.message, e.param, e.doc_url],
		[OWApiError.API, 404, "invalid_request", "not_found", "No such character.", "id", "https://onlyworlds.com/docs/errors#not_found"], "")
	t.ok(e.is_not_found(), "")
	t.eq(str(e), "OnlyWorlds API 404 [not_found] (field: id): No such character.", "the line it prints")
	t.ok(r.response != null and r.response.status == 404, "the response beside it")
	t.done()

func test_error_shapes_and_helpers(t) -> void:
	var cases := [
		# [status, body, headers, code, message, check]
		[401, "{\"code\":\"invalid_credentials\",\"message\":\"bad key\"}", {}, "invalid_credentials", "bad key", "is_auth_error"],
		[401, "{\"error\":{\"code\":\"key_revoked\"}}", {}, "key_revoked", "", "is_auth_error"],
		[413, "{\"error\":\"too_large\"}", {}, "too_large", "", ""],
		[422, "{\"error\":{\"code\":\"invalid_request\",\"param\":\"as\"}}", {}, "invalid_request", "", "is_validation_error"],
		[403, "{\"error\":{\"code\":\"owner_only\"}}", {}, "owner_only", "", "is_owner_only"],
		[503, "{\"error\":{\"code\":\"server_busy\"}}", {"Retry-After": " 12 "}, "server_busy", "", "is_retryable"],
		[409, "{\"error\":{\"code\":\"idempotency_in_flight\"}}", {}, "idempotency_in_flight", "", "is_retryable"],
	]
	for c in cases:
		var fake = Fake.new()
		fake.then(c[0], c[1], c[2])
		var e: OWApiError = (await _make(fake).get_world()).error
		t.eq([e.status, e.code, e.message], [c[0], c[3], c[4]], c[1])
		if c[5] != "":
			t.ok(e.call(c[5]), "%s: %s" % [c[1], c[5]])
	var html := "<html>" + "x".repeat(300) + "</html>"
	var fake = Fake.new()
	fake.then(502, html)
	var e: OWApiError = (await _make(fake).get_world()).error
	t.eq([e.status, e.code, e.message, e.raw_body], [502, "", html.substr(0, 200) + "...", html], "a proxy's page, not the envelope")
	t.ok(e.is_retryable(), "a 5xx is retryable")
	var quota := OWApiError.from_response(429, "{\"error\":{\"code\":\"quota_exceeded\"}}", {})
	t.ok(not quota.is_retryable(), "a used-up allowance is not")
	t.ok(not OWApiError.from_response(404, "{}", {}).is_not_found(), "a 404 without the code (a proxy's) is not keel's not_found")
	t.eq(OWApiError.parse_retry_after("Wed, 21 Oct 2026 07:28:00 GMT", 1792567670), 10, "an HTTP date, seconds from now")
	t.eq(OWApiError.parse_retry_after("Wed, 21 Oct 2026 07:28:00 GMT", 1792567690), 0, "a date passed: now")
	t.eq(OWApiError.parse_retry_after("soon", 0), null, "")
	t.eq(OWApiError.parse_retry_after("-1", 0), null, "")
	t.eq(OWApiError.parse_retry_after(null, 0), null, "")
	t.eq(OWApiError.from_response(409, "{\"error\":{\"code\":\"resync_required\",\"reason\":\"other\"}}", {}).resync_reason(), null,
		"a reason that is neither role nor view reads none")
	t.done()

func test_a_transport_failure_is_no_answer(t) -> void:
	var fake = Fake.new()
	fake.fail("can't connect")
	var r: OWClient.Reply = await _make(fake).get_world()
	t.eq([r.error.kind, r.error.status], [OWApiError.TRANSPORT, 0], "not keel's no")
	t.ok(r.error.message.contains("GET /world/") and r.error.message.contains("can't connect"), r.error.message)
	t.done()

# -- The transport seam and Godot's own HTTP ----------------------------------------------------------------------------

func test_http_transport_splits_a_url(t) -> void:
	t.eq(OWHttpTransport.split_url("https://www.onlyworlds.com/api/v2/health/"),
		["https", "www.onlyworlds.com", 443, "/api/v2/health/"], "")
	t.eq(OWHttpTransport.split_url("http://127.0.0.1:8000/api/v2/world/?world=w1"),
		["http", "127.0.0.1", 8000, "/api/v2/world/?world=w1"], "")
	t.eq(OWHttpTransport.split_url("https://example.test"), ["https", "example.test", 443, "/"], "")
	t.eq(OWHttpTransport.split_url("ftp://x/y"), [], "only http and https")
	t.eq(OWHttpTransport.split_url("https://:80/x"), [], "a host is needed")
	t.done()

func test_http_transport_answers_a_bad_url_without_sending(t) -> void:
	var r: OWTransport.Response = await OWHttpTransport.new().send(OWTransport.Request.make("GET", "nowhere", {}))
	t.eq(r.status, 0, "")
	t.ok(r.failure.contains("nowhere"), r.failure)
	t.done()

func test_response_header_is_case_insensitive(t) -> void:
	var r := OWTransport.Response.new()
	r.headers = {"etag": "\"1\"", "Retry-After": "2"}
	t.eq(r.header("ETag"), "\"1\"", "")
	t.eq(r.header("retry-after"), "2", "")
	t.eq(r.header("X-None"), null, "")
	t.done()

func test_live_health(t) -> void:
	# Production's health pulse through the default transport, polled between frames as a game polls it. Off by
	# default. It waits one frame first: inside a SceneTree's _init, before the first frame, Engine.get_main_loop() is
	# null and TLS does not start ("SSL module failed to initialize", measured on 4.7.2).
	if OS.get_environment("OW_LIVE") != "1":
		t.skip("set OW_LIVE=1 to read production's /health/")
		return
	await t.tree.process_frame
	var c := OWClient.new({"world": "none"})
	var r: OWClient.Reply = await c.health()
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value.get("status") if r.ok else null, "ok", "")
	var blocking := OWHttpTransport.new()
	blocking.blocking = true
	r = await OWClient.new({"world": "none", "transport": blocking}).health()
	t.ok(r.ok, "blocking, after the first frame (%s)" % r.error)
	t.done()
