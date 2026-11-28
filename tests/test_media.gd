extends RefCounted
## OWClient's images through a fake transport (tests/fake_transport.gd): no test touches the network. The ticket from
## the API (POST /media/ticket, POST /media/remove-ticket, each with the key and the PIN), then the bytes or the
## removal at the host the ticket names, with the ticket alone; a ticket passed in used instead of asking for one; an
## image over the ticket's max_bytes refused as the host would refuse it, nothing sent; the API's and the host's
## refusals with their codes. Mirrors the TypeScript SDK's test/v2-client.test.mjs, "Images".

const Fake := preload("res://tests/fake_transport.gd")
const API := "https://www.onlyworlds.com/api/v2"

const TICKET := "{\"ticket\":\"tkt.sig\",\"upload_url\":\"https://upload.example/v1/upload\",\"prefix\":\"u/w1/\",\"max_bytes\":8,\"exp\":1900000000,\"uses\":1,\"issued_to\":{\"account\":\"a1\",\"membership\":null}}"
const UPLOADED := "{\"url\":\"https://media.example/u/w1/x.png\",\"key\":\"u/w1/x.png\",\"bytes\":4,\"type\":\"image/png\",\"etag\":\"e\"}"
const RTICKET := "{\"ticket\":\"d1.sig\",\"remove_url\":\"https://upload.example/v1/remove\",\"exp\":1900000000,\"key\":\"u/w1/x.png\",\"referenced\":2}"
const REMOVED := "{\"removed\":\"u/w1/x.png\",\"bytes\":4,\"cache\":\"may_linger\"}"

func _client(fake, more := {}) -> OWClient:
	var config := {"api_key": "ow_w_test", "api_pin": "1234", "transport": fake}
	config.merge(more, true)
	return OWClient.new(config)

## keel answers the ticket, the host answers [param host_status] with [param host_body].
static func _image_fake(host_status := 201, host_body := UPLOADED, host_headers := {}):
	var f = Fake.new()
	f.then(201, TICKET)
	f.then(host_status, host_body, host_headers)
	return f

static func _remove_fake(host_status := 200, host_body := REMOVED):
	var f = Fake.new()
	f.then(200, RTICKET)
	f.then(host_status, host_body)
	return f

static func _png() -> PackedByteArray:
	return PackedByteArray([0x89, 0x50, 0x4e, 0x47])

func test_create_media_ticket_posts_with_the_key_and_pin_and_no_body(t) -> void:
	var f = _image_fake()
	var r := await _client(f).create_media_ticket()
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, JSON.parse_string(TICKET), "the ticket as served")
	var q = f.calls[0]
	t.eq(q.url, API + "/media/ticket", "")
	t.eq(q.method, "POST", "")
	t.eq(q.body, null, "no body")
	t.ok(not q.headers.has("Content-Type"), "no body, no media type")
	t.eq(q.headers.get("API-Key"), "ow_w_test", "")
	t.eq(q.headers.get("API-Pin"), "1234", "")
	t.ok(not q.headers.has("X-OW-Client") and not q.headers.has("X-OW-Agent"), "no write header: keel lists none here")
	t.done()

func test_upload_image_ticket_from_keel_then_the_bytes_with_the_ticket_only(t) -> void:
	var f = _image_fake()
	var bytes := _png()
	var r := await _client(f).upload_image(bytes, {"key": "u/w1/x.png"})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, JSON.parse_string(UPLOADED), "the host's 201")
	t.eq(f.calls.size(), 2, "the ticket, then the upload")
	var q = f.calls[1]
	t.eq(q.url, "https://upload.example/v1/upload", "to the ticket's upload_url")
	t.eq(q.method, "POST", "")
	t.eq(q.body, bytes, "the raw bytes")
	t.eq(q.headers, {"Authorization": "Bearer tkt.sig", "X-Key": "u/w1/x.png"}, "the ticket alone, never the key or PIN")
	t.done()

func test_upload_image_with_a_ticket_passed_does_not_call_keel(t) -> void:
	var f = Fake.new()
	f.status = 201
	f.body = UPLOADED
	var r := await _client(f).upload_image(PackedByteArray([0, 0, 0]), {"ticket": JSON.parse_string(TICKET)})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(f.calls.map(func(q): return q.url), ["https://upload.example/v1/upload"], "the host alone")
	t.ok(not f.calls[0].headers.has("X-Key"), "no key given: no X-Key")
	t.done()

func test_upload_image_over_max_bytes_is_413_too_large_and_sends_nothing(t) -> void:
	var f = Fake.new()
	var big := PackedByteArray()
	big.resize(9)
	var r := await _client(f).upload_image(big, {"ticket": JSON.parse_string(TICKET)})
	t.ok(not r.ok, "refused")
	if not r.ok:
		t.eq([r.error.kind, r.error.status, r.error.code], [OWApiError.API, 413, "too_large"], "as the host would answer")
		t.eq(r.error.message, "Image is 9 bytes; this ticket accepts at most 8. Nothing was sent.", "")
		t.eq(JSON.parse_string(r.error.raw_body), {"error": "too_large", "max_bytes": 8.0, "got": 9.0}, "the TypeScript SDK's body")
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_upload_image_the_edges_refusal_arrives_with_its_code(t) -> void:
	var f = _image_fake(401, "{\"error\":\"ticket_used\",\"note\":\"one upload per ticket; request another\"}")
	var r := await _client(f).upload_image(PackedByteArray([1, 2, 3, 4]))
	t.ok(not r.ok, "refused")
	if not r.ok:
		t.eq([r.error.kind, r.error.status, r.error.code], [OWApiError.API, 401, "ticket_used"], "")
	t.done()

func test_upload_image_an_edge_that_cannot_be_reached_is_transport(t) -> void:
	var f = Fake.new()
	f.then(201, TICKET)
	f.fail("could not connect to upload.example:443 (cannot connect)")
	var r := await _client(f).upload_image(_png())
	t.ok(not r.ok, "no value")
	if not r.ok:
		t.eq(r.error.kind, OWApiError.TRANSPORT, "")
		t.eq(r.error.message, "OnlyWorlds image upload failed: POST https://upload.example/v1/upload: could not connect to upload.example:443 (cannot connect)", "")
	t.done()

func test_upload_image_a_ticket_missing_its_fields_is_refused(t) -> void:
	var good: Dictionary = JSON.parse_string(TICKET)
	var cases := []
	for k in ["ticket", "upload_url", "max_bytes"]:
		var d := good.duplicate(true)
		d.erase(k)
		cases.append([d, "no " + k])
	var bad_url := good.duplicate(true)
	bad_url["upload_url"] = "ftp://upload.example/v1/upload"
	cases.append([bad_url, "not http(s)"])
	var bad_max := good.duplicate(true)
	bad_max["max_bytes"] = "8"
	cases.append([bad_max, "max_bytes a String"])
	var empty := good.duplicate(true)
	empty["ticket"] = ""
	cases.append([empty, "an empty ticket"])
	for c in cases:
		var f = Fake.new()
		var r := await _client(f).upload_image(_png(), {"ticket": c[0]})
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused (%s)" % [c[1], r.error])
		if r.error != null:
			t.ok(r.error.message.ends_with("Nothing was sent."), "%s: says so (%s)" % [c[1], r.error.message])
			t.ok(not r.error.message.contains("tkt.sig"), "%s: the ticket is not in the message" % c[1])
		t.eq(f.calls.size(), 0, "%s: nothing sent" % c[1])
	var f2 = Fake.new()
	var r2 := await _client(f2).upload_image(_png(), {"ticket": "tkt.sig"})
	t.ok(r2.error != null and r2.error.kind == OWApiError.REFUSED and r2.error.message.contains("ticket is a Dictionary"),
		"a ticket that is not a Dictionary (%s)" % r2.error)
	t.eq(f2.calls.size(), 0, "")
	t.done()

func test_keels_ticket_missing_its_fields_is_an_answer_fault(t) -> void:
	var f = Fake.new()
	f.then(201, "{\"ticket\":\"tkt.sig\"}")
	var r := await _client(f).upload_image(_png())
	t.ok(r.error != null and r.error.kind == OWApiError.ANSWER, "keel's own ticket without an upload_url (%s)" % r.error)
	t.eq(f.calls.size(), 1, "the host is never called")
	t.done()

func test_create_removal_ticket_posts_the_key_and_cuts_a_whole_image_url(t) -> void:
	var f = Fake.new()
	f.body = RTICKET
	var c := _client(f)
	var r := await c.create_removal_ticket("u/w1/x.png")
	t.eq(r.value, JSON.parse_string(RTICKET), "the ticket as served")
	await c.create_removal_ticket("https://media.onlyworlds.com/u/w1/x.png")
	for q in f.calls:
		t.eq(q.url, API + "/media/remove-ticket", "")
		t.eq(q.method, "POST", "")
		t.eq(JSON.parse_string(q.body), {"key": "u/w1/x.png"}, q.body)
		t.eq(q.headers.get("API-Key"), "ow_w_test", "")
		t.eq(q.headers.get("API-Pin"), "1234", "")
		t.ok(not q.headers.has("X-OW-Client") and not q.headers.has("X-OW-Agent"), "no write header")
	t.done()

func test_a_whole_image_url_is_cut_as_a_url_parser_cuts_it(t) -> void:
	# decodeURIComponent keeps a "+" ("+" is a space only in a query); String.uri_decode would make it one. A query or
	# a fragment is not part of the path.
	var cases := [
		["https://media.onlyworlds.com/u/w1/a+b.png", "u/w1/a+b.png"],
		["https://media.onlyworlds.com/u/w1/a%20b%C3%A9.png", "u/w1/a bé.png"],
		["HTTPS://media.onlyworlds.com//u/w1/x.png?v=2#top", "u/w1/x.png"],
		["http://media.example:8080/u/w1/x.png", "u/w1/x.png"],
		["u/w1/a+b.png", "u/w1/a+b.png"],
	]
	for k in cases:
		var f = Fake.new()
		f.body = RTICKET
		await _client(f).create_removal_ticket(k[0])
		t.eq(JSON.parse_string(f.last().body).get("key"), k[1], k[0])
	t.done()

func test_remove_image_ticket_from_keel_then_the_removal_with_the_ticket_only(t) -> void:
	var f = _remove_fake()
	var r := await _client(f).remove_image("u/w1/x.png")
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, JSON.parse_string(REMOVED), "the host's 200")
	t.eq(f.calls.size(), 2, "")
	var q = f.calls[1]
	t.eq(q.url, "https://upload.example/v1/remove", "to the ticket's remove_url")
	t.eq(q.method, "POST", "")
	t.eq(q.body, null, "no body")
	t.eq(q.headers, {"Authorization": "Bearer d1.sig"}, "the ticket alone")
	t.done()

func test_remove_image_with_a_ticket_passed_does_not_call_keel(t) -> void:
	var f = Fake.new()
	f.body = REMOVED
	var r := await _client(f).remove_image("u/w1/x.png", {"ticket": JSON.parse_string(RTICKET)})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(f.calls.map(func(q): return q.url), ["https://upload.example/v1/remove"], "")
	var no_url: Dictionary = JSON.parse_string(RTICKET)
	no_url.erase("remove_url")
	var g = Fake.new()
	var bad := await _client(g).remove_image("u/w1/x.png", {"ticket": no_url})
	t.ok(bad.error != null and bad.error.kind == OWApiError.REFUSED, "a ticket with no remove_url (%s)" % bad.error)
	t.eq(g.calls.size(), 0, "")
	t.done()

func test_remove_image_keels_refusal_and_the_edges_arrive_with_their_codes(t) -> void:
	var keel = Fake.new()
	keel.then(409, "{\"error\":{\"type\":\"invalid_request\",\"code\":\"upload_pending\",\"message\":\"retry\"}}")
	var r := await _client(keel).remove_image("u/w1/x.png")
	t.eq([r.error.status, r.error.code] if r.error else null, [409, "upload_pending"], "keel's")
	t.eq(keel.calls.size(), 1, "the host is never called")
	var edge = _remove_fake(403, "{\"error\":\"not_removable\"}")
	r = await _client(edge).remove_image("u/w1/x.png")
	t.eq([r.error.kind, r.error.status, r.error.code] if r.error else null, [OWApiError.API, 403, "not_removable"], "the edge's")
	t.done()

func test_an_agent_never_declares_itself_on_images(t) -> void:
	var f = _image_fake()
	await _client(f, {"agent": true, "client": "my-game"}).upload_image(PackedByteArray([1, 2, 3]), {"key": "u/w1/x.png"})
	t.ok(not f.calls[0].headers.has("X-OW-Agent"), "not on the ticket")
	t.eq(f.calls[1].headers, {"Authorization": "Bearer tkt.sig", "X-Key": "u/w1/x.png"}, "nor to the host")
	var g = _remove_fake()
	await _client(g, {"agent": true}).remove_image("u/w1/x.png")
	t.ok(not g.calls[0].headers.has("X-OW-Agent") and not g.calls[1].headers.has("X-OW-Agent"), "nor on a removal")
	t.done()

func test_an_unknown_option_is_refused_by_name(t) -> void:
	var f = Fake.new()
	var c := _client(f)
	for call in [
		["remove_image", func(): return await c.remove_image("k", {"tickt": {}})],
		["upload_image", func(): return await c.upload_image(PackedByteArray([1]), {"kye": "k"})],
	]:
		var r: OWClient.Reply = await call[1].call()
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains("unknown option"),
			"%s: %s" % [call[0], r.error])
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_the_ticket_never_reaches_an_error_message(t) -> void:
	var answers := [[401, "{\"error\":\"ticket_used\"}"], [502, "<html>bad gateway</html>"], [201, "not json"], [0, ""]]
	for a in answers:
		var f = Fake.new()
		if a[0] == 0:
			f.fail("timed out after 30.0 s waiting for upload.example's answer")
		else:
			f.then(a[0], a[1])
		var r := await _client(f).upload_image(_png(), {"ticket": JSON.parse_string(TICKET)})
		t.ok(r.error != null, "%d: no value" % a[0])
		if r.error != null:
			t.ok(not r.error.message.contains("tkt.sig"), "%d: %s" % [a[0], r.error.message])
	t.done()

func test_images_need_a_world_key(t) -> void:
	for config in [{}, {"world": "w1"}, {"api_key": "ow_a_test", "world": "w1"}]:
		var f = Fake.new()
		config["transport"] = f
		var c := OWClient.new(config)
		for r: OWClient.Reply in [await c.create_media_ticket(), await c.upload_image(_png()),
				await c.create_removal_ticket("u/w1/x.png"), await c.remove_image("u/w1/x.png")]:
			t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused (%s)" % [config.keys(), r.error])
		t.eq(f.calls.size(), 0, "nothing sent")
	t.done()
