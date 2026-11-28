extends RefCounted
## OWClient's files on elements through a fake transport (tests/fake_transport.gd): no test touches the network.
## list_files, world_files, create_file_ticket, upload_file, file_download_link and remove_file: each route's method,
## path and body; no Idempotency-Key on the ticket; the kind read from the name as keel reads it; the two-step upload
## (the ticket from the API, the raw bytes to upload_url with the ticket alone); the API's and the upload host's
## refusals as OWApiErrors with their helpers. Mirrors the TypeScript SDK's test/files.test.mjs.

const Fake := preload("res://tests/fake_transport.gd")
const API := "https://www.onlyworlds.com/api/v2"
const EL := "018f0000-0000-7000-8000-0000000000e1"
const FID := "018f0000-0000-7000-8000-0000000000f1"

const ROW := "{\"id\":\"018f0000-0000-7000-8000-0000000000f1\",\"name\":\"Map notes.pdf\",\"kind\":\"pdf\",\"size\":5,\"label\":\"description\",\"added_by\":{\"name\":\"Ada\",\"membership\":null,\"agent\":false,\"owner\":true},\"added_at\":\"2026-10-19T18:00:00Z\"}"
const WORLD := "{\"data\":[{\"id\":\"018f0000-0000-7000-8000-0000000000f1\",\"name\":\"Map notes.pdf\",\"kind\":\"pdf\",\"size\":5,\"label\":\"description\",\"added_by\":{\"name\":\"Ada\",\"membership\":null,\"agent\":false,\"owner\":true},\"added_at\":\"2026-10-19T18:00:00Z\",\"element_type\":\"location\",\"element_id\":\"018f0000-0000-7000-8000-0000000000e1\"}],\"used_bytes\":42991616,\"cap_bytes\":262144000}"
const TICKET := "{\"ticket\":\"f1.sig\",\"upload_url\":\"https://upload.example/v1/file\",\"prefix\":\"w/w1/018f0000-0000-7000-8000-0000000000e1/\",\"key\":\"w/w1/018f0000-0000-7000-8000-0000000000e1/018f0000-0000-7000-8000-0000000000f1.pdf\",\"max_bytes\":8,\"exp\":1900000000,\"uses\":1,\"issued_to\":{\"account\":\"a1\",\"membership\":null},\"kind\":\"file\",\"file_id\":\"018f0000-0000-7000-8000-0000000000f1\"}"
const STORED := "{\"key\":\"w/w1/018f0000-0000-7000-8000-0000000000e1/018f0000-0000-7000-8000-0000000000f1.pdf\",\"fid\":\"018f0000-0000-7000-8000-0000000000f1\",\"bytes\":5,\"type\":\"application/pdf\",\"etag\":\"e\"}"
const LINK := "{\"url\":\"https://files.example/v1/get?t=g1.sig\",\"exp\":1900000300,\"name\":\"Map notes.pdf\",\"kind\":\"pdf\",\"size\":5}"

func _client(fake, more := {}) -> OWClient:
	var config := {"api_key": "ow_w_test", "api_pin": "1234", "transport": fake}
	config.merge(more, true)
	return OWClient.new(config)

## keel answers the ticket with [param keel_status] and [param keel_body] (default: the 201), the host answers its own.
static func _upload_fake(host_status := 201, host_body := STORED, keel_status := 201, keel_body := TICKET, keel_headers := {}):
	var f = Fake.new()
	f.then(keel_status, keel_body, keel_headers)
	f.then(host_status, host_body)
	return f

static func _pdf() -> PackedByteArray:
	return PackedByteArray([0x25, 0x50, 0x44, 0x46, 0x2d])   # %PDF-

static func _body(q) -> Variant:
	return JSON.parse_string(q.body) if q.body is String else null

static func _refused(t, r: OWClient.Reply, label: String) -> void:
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused (%s)" % [label, r.error])
	if r.error != null:
		t.ok(r.error.message.ends_with("Nothing was sent."), "%s: says so (%s)" % [label, r.error.message])

# -- the API routes ------------------------------------------------------------------------------------------------------

func test_list_files_gets_the_elements_files_with_the_key(t) -> void:
	var f = Fake.new()
	f.body = "{\"data\":[%s]}" % ROW
	var r := await _client(f).list_files("location", EL)
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, [JSON.parse_string(ROW)], "the rows")
	var q = f.last()
	t.eq(q.url, "%s/location/%s/files" % [API, EL], "")
	t.eq(q.method, "GET", "")
	t.eq(q.body, null, "")
	t.eq(q.headers.get("API-Key"), "ow_w_test", "")
	t.ok(not q.headers.has("API-Pin"), "a read: no PIN")
	f.body = "{}"
	t.eq((await _client(f).list_files("location", EL)).value, [], "no data: no rows")
	t.done()

func test_world_files_gets_the_rows_and_the_total_as_keel_sends_them(t) -> void:
	var f = Fake.new()
	f.body = WORLD
	var r := await _client(f).world_files()
	t.eq(r.value, JSON.parse_string(WORLD), "")
	t.eq(f.last().url, API + "/world/files", "")
	t.eq(f.last().method, "GET", "")
	t.ok(not f.last().headers.has("API-Pin"), "a read: no PIN")
	t.done()

func test_create_file_ticket_posts_name_kind_size_label_with_the_key_and_pin_and_no_idempotency_key(t) -> void:
	var f = Fake.new()
	f.status = 201
	f.body = TICKET
	var c := _client(f)
	var r := await c.create_file_ticket("location", EL, "Map notes.pdf", 5, {"label": "description"})
	t.eq(r.value, JSON.parse_string(TICKET), "the ticket as served")
	await c.create_file_ticket("location", EL, "Map notes.pdf", 5)
	t.eq(f.calls[0].url, "%s/location/%s/files" % [API, EL], "")
	t.eq(f.calls[0].method, "POST", "")
	t.eq(_body(f.calls[0]), {"name": "Map notes.pdf", "kind": "pdf", "size": 5.0, "label": "description"}, "")
	t.eq(_body(f.calls[1]), {"name": "Map notes.pdf", "kind": "pdf", "size": 5.0}, "no label: none sent")
	for q in f.calls:
		t.eq(q.headers.get("API-Key"), "ow_w_test", "")
		t.eq(q.headers.get("API-Pin"), "1234", "")
		t.ok(not q.headers.keys().any(func(h): return h.to_lower() == "idempotency-key"), "no Idempotency-Key")
		t.ok(not q.headers.has("X-OW-Client"), "keel does not read the client's name here")
	await c.create_file_ticket("location", EL, "Map notes.pdf", 5, {"label": null})
	t.eq(_body(f.last()), {"name": "Map notes.pdf", "kind": "pdf", "size": 5.0, "label": null}, "a null label is sent as null")
	t.done()

func test_the_kind_is_read_from_the_name_as_keel_reads_it(t) -> void:
	var f = Fake.new()
	f.status = 201
	f.body = TICKET
	var c := _client(f)
	var cases := [
		["rules.yml", "yaml"], ["rules.yaml", "yaml"], ["README.markdown", "md"], ["notes.md", "md"],
		["MAP.PDF", "pdf"], ["a.tar.zip", "zip"], ["C:\\worlds\\lore.txt", "txt"], ["data/table.csv", "csv"],
		["x.json", "json"], ["Cargo.toml", "toml"],
		["home.png", "png"], ["shot.jpg", "jpg"], ["Photo.JPEG", "jpg"], ["mock.webp", "webp"], ["frame.avif", "avif"],
	]
	for k in cases:
		await c.create_file_ticket("character", EL, k[0], 1)
	t.eq(f.calls.map(func(q): return _body(q).get("kind")), cases.map(func(k): return k[1]), "")
	t.eq(_body(f.calls[6]).get("name"), "C:\\worlds\\lore.txt", "the name goes as given: keel cleans it")
	t.done()

func test_a_kind_passed_is_sent_as_passed(t) -> void:
	var f = Fake.new()
	f.status = 201
	f.body = TICKET
	await _client(f).create_file_ticket("character", EL, "odd.bin", 1, {"kind": "txt"})
	t.eq(_body(f.last()).get("kind"), "txt", "")
	t.done()

func test_a_name_with_no_extension_keel_takes_is_refused_naming_the_ones_it_takes(t) -> void:
	var f = _upload_fake()
	var c := _client(f)
	var names := RegEx.create_from_string("\\.pdf .*\\.yml .*\\.zip")
	for name in ["report.docx", "noextension", ".pdf", "trailing.", "image.gif", "logo.svg"]:
		var r := await c.create_file_ticket("character", EL, name, 1)
		_refused(t, r, name)
		t.ok(r.error != null and names.search(r.error.message) != null, "%s: names the extensions (%s)" % [name, r.error])
		_refused(t, await c.upload_file("character", EL, _pdf(), {"name": name}), "upload_file " + name)
	_refused(t, await c.create_file_ticket("character", EL, "", 1), "an empty name")
	_refused(t, await c.create_file_ticket("character", EL, "  ", 1), "a blank name")
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_file_download_link_gets_the_link_and_its_exp(t) -> void:
	var f = Fake.new()
	f.body = LINK
	var r := await _client(f).file_download_link("location", EL, FID)
	t.eq(r.value, JSON.parse_string(LINK), "")
	t.eq(f.last().url, "%s/location/%s/files/%s/download" % [API, EL, FID], "")
	t.eq(f.last().method, "GET", "")
	t.ok(not f.last().headers.has("API-Pin"), "a read: no PIN")
	t.done()

func test_remove_file_deletes_and_a_204_is_no_value(t) -> void:
	var f = Fake.new()
	f.status = 204
	f.body = ""
	var r := await _client(f).remove_file("location", EL, FID)
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, null, "")
	t.eq(f.last().url, "%s/location/%s/files/%s" % [API, EL, FID], "")
	t.eq(f.last().method, "DELETE", "")
	t.eq(f.last().body, null, "")
	t.eq(f.last().headers.get("API-Pin"), "1234", "a write: the PIN")
	t.ok(not f.last().headers.has("X-OW-Client") and not f.last().headers.has("X-OW-Agent"), "no write header")
	t.done()

func test_remove_file_neither_owner_nor_uploader_is_a_403_permission_error(t) -> void:
	var f = Fake.new()
	f.status = 403
	f.body = "{\"error\":{\"type\":\"permission_error\",\"code\":\"permission_error\",\"message\":\"Only the file's uploader or the world's owner can remove it.\"}}"
	var r := await _client(f).remove_file("location", EL, FID)
	t.eq([r.error.kind, r.error.status, r.error.type] if r.error else null, [OWApiError.API, 403, "permission_error"], "")
	t.done()

func test_an_id_that_is_not_one_path_segment_is_refused(t) -> void:
	var f = Fake.new()
	var c := _client(f)
	_refused(t, await c.list_files("location", "a/b"), "list_files")
	_refused(t, await c.create_file_ticket("location", "a/b", "a.pdf", 1), "create_file_ticket")
	_refused(t, await c.file_download_link("location", EL, "../x"), "file_download_link")
	_refused(t, await c.remove_file("location", EL, "a?b"), "remove_file")
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

# -- the upload ----------------------------------------------------------------------------------------------------------

func test_upload_file_the_ticket_with_the_byte_size_then_the_raw_bytes_with_the_ticket_alone(t) -> void:
	var f = _upload_fake()
	var bytes := _pdf()
	var r := await _client(f).upload_file("location", EL, bytes, {"name": "Map notes.pdf", "label": "description"})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(r.value, JSON.parse_string(STORED), "the host's 201")
	t.eq(f.calls.size(), 2, "")
	t.eq(_body(f.calls[0]), {"name": "Map notes.pdf", "kind": "pdf", "size": 5.0, "label": "description"}, "")
	var q = f.calls[1]
	t.eq(q.url, "https://upload.example/v1/file", "")
	t.eq(q.method, "POST", "")
	t.eq(q.body, bytes, "the raw bytes")
	t.eq(q.headers, {"Authorization": "Bearer f1.sig"}, "the ticket alone")
	t.done()

func test_upload_file_the_size_is_the_byte_length(t) -> void:
	var f = _upload_fake()
	var file := PackedByteArray()
	file.resize(5)
	await _client(f).upload_file("location", EL, file, {"name": "a.txt"})
	t.eq(_body(f.calls[0]).get("size"), 5.0, "")
	t.eq(f.calls[1].body, file, "")
	t.done()

func test_upload_file_with_no_name_and_no_ticket_is_refused(t) -> void:
	var f = _upload_fake()
	var r := await _client(f).upload_file("location", EL, _pdf())
	_refused(t, r, "no name")
	t.ok(r.error != null and r.error.message.contains("options.name"), "says what to pass (%s)" % r.error)
	_refused(t, await _client(f).upload_file("location", EL, _pdf(), {"name": " "}), "a blank name")
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_upload_file_with_a_ticket_passed_does_not_call_keel(t) -> void:
	var f = Fake.new()
	f.status = 201
	f.body = STORED
	var r := await _client(f).upload_file("location", EL, _pdf(), {"ticket": JSON.parse_string(TICKET)})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(f.calls.map(func(q): return q.url), ["https://upload.example/v1/file"], "")
	t.done()

func test_upload_file_over_max_bytes_is_413_too_large_and_sends_nothing(t) -> void:
	var f = _upload_fake()
	var big := PackedByteArray()
	big.resize(9)
	var r := await _client(f).upload_file("location", EL, big, {"ticket": JSON.parse_string(TICKET)})
	t.ok(not r.ok, "")
	if not r.ok:
		t.eq([r.error.kind, r.error.status, r.error.code], [OWApiError.API, 413, "too_large"], "")
		t.ok(not r.error.is_file_too_large(), "not keel's file_too_large")
		t.eq(r.error.message, "File is 9 bytes; this ticket accepts at most 8. Nothing was sent.", "")
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_upload_file_a_ticket_missing_its_fields_is_refused(t) -> void:
	for k in ["ticket", "upload_url", "max_bytes"]:
		var d: Dictionary = JSON.parse_string(TICKET)
		d.erase(k)
		var f = Fake.new()
		_refused(t, await _client(f).upload_file("location", EL, _pdf(), {"ticket": d}), "no " + k)
		t.eq(f.calls.size(), 0, "no %s: nothing sent" % k)
	t.done()

func test_keels_413_file_too_large_is_is_file_too_large_and_the_host_is_never_called(t) -> void:
	var f = _upload_fake(201, STORED, 413, "{\"error\":{\"type\":\"invalid_request\",\"code\":\"file_too_large\",\"message\":\"This file is 41 MB; a file can be at most 25 MB.\",\"param\":\"size\",\"doc_url\":\"https://onlyworlds.github.io/api/errors#file_too_large\"}}")
	var r := await _client(f).upload_file("location", EL, _pdf(), {"name": "big.pdf"})
	t.ok(r.error != null and r.error.is_file_too_large() and r.error.param == "size" and r.error.message.contains("41 MB")
		and not r.error.is_files_full(), "%s" % r.error)
	t.eq(f.calls.size(), 1, "the host is never called")
	t.done()

func test_keels_429_quota_exceeded_is_is_quota_exceeded_with_its_retry_after(t) -> void:
	var f = _upload_fake(201, STORED, 429, "{\"error\":{\"type\":\"rate_limited\",\"code\":\"quota_exceeded\",\"message\":\"This world has reached its daily file upload limit.\"}}", {"Retry-After": "3600"})
	var r := await _client(f).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.ok(r.error != null and r.error.is_quota_exceeded(), "%s" % r.error)
	t.eq(r.error.retry_after if r.error else null, 3600, "")
	t.eq(f.calls.size(), 1, "")
	t.done()

func test_keels_403_files_full_is_is_files_full_and_not_is_not_author(t) -> void:
	var f = _upload_fake(201, STORED, 403, "{\"error\":{\"type\":\"permission_error\",\"code\":\"files_full\",\"message\":\"This world has 249.6 MB of its 250 MB. This file is 4 MB. Remove a file, or ask the owner.\"}}")
	var r := await _client(f).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.ok(r.error != null and r.error.is_files_full() and not r.error.is_not_author() and not r.error.is_file_too_large(), "%s" % r.error)
	var g = _upload_fake(201, STORED, 403, "{\"error\":{\"type\":\"permission_error\",\"code\":\"not_author\",\"message\":\"x\"}}")
	r = await _client(g).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.ok(r.error != null and r.error.is_not_author() and not r.error.is_files_full(), "not_author (%s)" % r.error)
	t.done()

func test_the_upload_hosts_refusals_arrive_with_their_codes(t) -> void:
	var exists = _upload_fake(409, "{\"error\":\"exists\",\"key\":\"w/w1/x.pdf\",\"note\":\"this file id is already stored; ask keel for a new ticket\"}")
	var r := await _client(exists).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.eq([r.error.kind, r.error.status, r.error.code] if r.error else null, [OWApiError.API, 409, "exists"], "")
	var wrong = _upload_fake(415, "{\"error\":\"unsupported_type\",\"reason\":\"not a pdf\",\"accepted\":[\"pdf\"]}")
	r = await _client(wrong).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.eq([r.error.status, r.error.code] if r.error else null, [415, "unsupported_type"], "")
	var later = Fake.new()
	later.then(201, TICKET)
	later.then(409, "{\"error\":\"exists\",\"key\":\"w/w1/x.pdf\"}", {"Retry-After": "7"})
	r = await _client(later).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.eq([r.error.code, r.error.retry_after] if r.error else null, ["exists", 7], "the host's Retry-After")
	t.done()

func test_upload_file_a_host_that_cannot_be_reached_is_transport(t) -> void:
	var f = Fake.new()
	f.then(201, TICKET)
	f.fail("could not connect to upload.example:443 (cannot connect)")
	var r := await _client(f).upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	t.eq(r.error.kind if r.error else null, OWApiError.TRANSPORT, "")
	t.ok(r.error != null and r.error.message.begins_with("OnlyWorlds file upload failed: POST https://upload.example/v1/file: "), "%s" % r.error)
	t.done()

func test_an_agent_declares_itself_on_the_ticket_alone(t) -> void:
	var f = Fake.new()
	var c := _client(f, {"agent": true, "client": "my-game"})
	f.body = "{\"data\":[]}"
	await c.list_files("location", EL)
	f.body = WORLD
	await c.world_files()
	f.then(201, TICKET)
	f.then(201, STORED)
	await c.upload_file("location", EL, _pdf(), {"name": "a.pdf"})
	f.body = LINK
	await c.file_download_link("location", EL, FID)
	f.status = 204
	f.body = ""
	await c.remove_file("location", EL, FID)
	t.eq(f.calls.size(), 6, "")
	for q in f.calls:
		var ticket: bool = q.method == "POST" and q.url.begins_with(API) and q.url.ends_with("/files")
		t.eq(q.headers.has("X-OW-Agent"), ticket, "%s %s" % [q.method, q.url])
		t.ok(not q.headers.has("X-OW-Client"), "%s %s: no client name" % [q.method, q.url])
	var plain = Fake.new()
	plain.status = 201
	plain.body = TICKET
	await _client(plain).create_file_ticket("location", EL, "a.pdf", 3)
	t.ok(not plain.last().headers.has("X-OW-Agent"), "a person's client never declares an agent")
	t.done()

func test_on_progress_is_called_once_with_the_total_after_success_and_never_on_a_failure(t) -> void:
	var seen := []
	var f = _upload_fake()
	await _client(f).upload_file("location", EL, _pdf(), {"name": "a.pdf", "on_progress": func(l, n): seen.append([l, n])})
	t.eq(seen, [[5, 5]], "")
	t.eq(f.calls[1].url, "https://upload.example/v1/file", "")
	var none := []
	var failed = _upload_fake(409, "{\"error\":\"exists\"}")
	var r := await _client(failed).upload_file("location", EL, _pdf(), {"name": "a.pdf", "on_progress": func(l, n): none.append([l, n])})
	t.ok(not r.ok, "")
	t.eq(none, [], "")
	t.done()

func test_an_unknown_option_or_one_of_the_wrong_type_is_refused(t) -> void:
	var f = Fake.new()
	var c := _client(f)
	for call in [
		["create_file_ticket", func(): return await c.create_file_ticket("location", "x", "a.pdf", 1, {"lable": "l"})],
		["upload_file", func(): return await c.upload_file("location", "x", PackedByteArray([1]), {"name": "a.pdf", "onprogress": func(a, b): pass})],
		["upload_file on_progress", func(): return await c.upload_file("location", "x", PackedByteArray([1]), {"name": "a.pdf", "on_progress": "f"})],
		["upload_file ticket", func(): return await c.upload_file("location", "x", PackedByteArray([1]), {"ticket": []})],
		["create_file_ticket kind", func(): return await c.create_file_ticket("location", "x", "a.pdf", 1, {"kind": 3})],
	]:
		_refused(t, await call[1].call(), call[0])
	t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_files_need_a_world_key(t) -> void:
	for config in [{}, {"world": "w1"}, {"api_key": "ow_a_test", "world": "w1"}]:
		var f = Fake.new()
		config["transport"] = f
		var c := OWClient.new(config)
		for r: OWClient.Reply in [await c.list_files("location", EL), await c.world_files(),
				await c.create_file_ticket("location", EL, "a.pdf", 1), await c.upload_file("location", EL, _pdf(), {"name": "a.pdf"}),
				await c.file_download_link("location", EL, FID), await c.remove_file("location", EL, FID)]:
			t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "%s: refused (%s)" % [config.keys(), r.error])
		t.eq(f.calls.size(), 0, "nothing sent")
	t.done()

func test_file_extensions_and_file_kind_of_for_a_file_picker(t) -> void:
	var keys: Array = OWClient.FILE_EXTENSIONS.keys()
	keys.sort()
	t.eq(keys, ["avif", "csv", "jpeg", "jpg", "json", "markdown", "md", "pdf", "png", "toml", "txt", "webp", "yaml", "yml", "zip"], "")
	t.ok(OWClient.FILE_EXTENSIONS.is_read_only(), "read-only")
	t.eq(OWClient.file_kind_of("Notes/Letters.PDF"), "pdf", "")
	t.eq(OWClient.file_kind_of("rules.yml"), "yaml", "")
	t.eq(OWClient.file_kind_of("photo.png"), "png", "")
	t.eq(OWClient.file_kind_of("photo.jpeg"), "jpg", "")
	t.eq(OWClient.file_kind_of("anim.gif"), "", "")
	t.eq(OWClient.file_kind_of("logo.svg"), "", "")
	t.eq(OWClient.file_kind_of(".md"), "", "")
	t.done()
