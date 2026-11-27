extends RefCounted
## OWApiError.limit and its three predicates through a fake transport (tests/fake_transport.gd): keel's three size
## refusals keep the code invalid_request and name the limit passed in the envelope's limit, a key of the API
## document's info.x-ow-limits. The TypeScript SDK's test (test/v2-client.test.mjs, 4.219.0) ported, with a bulk
## slot's case and a limit that is not a String beside it.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const FLAGS := {"element_bytes": "is_element_too_large", "element_link_ids": "is_element_too_many_links",
	"extensions_bytes": "is_extensions_too_large"}

static func _envelope(code: String, limit: Variant = null) -> Dictionary:
	var inner := {"type": "invalid_request", "code": code, "message": "m", "param": null,
		"doc_url": "https://example.test/e"}
	if limit != null:
		inner["limit"] = limit
	return {"error": inner}

static func _client(fake) -> OWClient:
	return OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})

## The error a create of a Character answers when keel says [param answer_status] with [param body].
func _create_refused(answer_status: int, body: Dictionary) -> OWApiError:
	var fake = Fake.new()
	fake.then(answer_status, JSON.stringify(body, "", false))
	var r: OWClient.Reply = await _client(fake).create("character", {"name": "K"})
	return r.error

static func _flags(e: OWApiError) -> Dictionary:
	var out := {}
	for name in FLAGS:
		out[FLAGS[name]] = e.call(FLAGS[name])
	return out

func test_limit_names_the_size_limit_a_422_passed_and_the_three_predicates_read_it(t) -> void:
	for limit in FLAGS:
		var e: OWApiError = await _create_refused(422, _envelope("invalid_request", limit))
		t.eq(e.code, "invalid_request", "%s: the code stays" % limit)
		t.eq(e.limit(), limit, "%s: limit" % limit)
		var want := {}
		for name in FLAGS:
			want[FLAGS[name]] = name == limit
		t.eq(_flags(e), want, "%s: exactly its own predicate" % limit)
	t.done()

func test_limit_is_an_open_string_none_without_one_and_never_off_a_422(t) -> void:
	# a value the package does not know is read, and no predicate claims it
	var later: OWApiError = await _create_refused(422, _envelope("invalid_request", "element_fields"))
	t.eq(later.limit(), "element_fields", "an unknown value is read")
	t.ok(not _flags(later).values().has(true), "and no predicate claims it")
	var plain: OWApiError = await _create_refused(422, _envelope("invalid_request"))
	t.eq(plain.limit(), null, "no limit sent")
	t.eq(plain.is_element_too_large(), false, "no limit sent: false")
	# a limit that is not a String is not one
	var number: OWApiError = await _create_refused(422, _envelope("invalid_request", 5))
	t.eq(number.limit(), null, "a number")
	t.ok(not _flags(number).values().has(true), "a number: no predicate")
	# never off a 422: a 409 resync_required carries reason, and a limit there is not read
	var fake = Fake.new()
	fake.then(409, JSON.stringify(_envelope("resync_required", "element_bytes"), "", false))
	var resync: OWApiError = (await _client(fake).changes({"since": "12:abc"})).error
	t.ok(resync != null and resync.is_resync_required(), "the 409 is a resync")
	if resync != null:
		t.eq(resync.limit(), null, "a 409: none")
		t.eq(resync.is_element_too_large(), false, "a 409: false")
	# the client's own refusal, which sends nothing
	t.eq(OWApiError.of(OWApiError.REFUSED, "no").limit(), null, "the client's own refusal")
	t.done()

func test_limit_is_on_a_bulk_slots_error(t) -> void:
	var fake = Fake.new()
	fake.then(200, JSON.stringify({"errors": true, "items": [{"status": 201, "id": "a"},
		{"status": 422, "error": _envelope("invalid_request", "element_link_ids")["error"]}]}, "", false))
	var r: OWClient.Reply = await _client(fake).bulk([{"type": "character", "element": {"name": "A"}},
		{"type": "character", "element": {"name": "B"}}])
	t.ok(r.ok, "the bulk answered: %s" % [r.error])
	if r.ok:
		var result: OWClient.BulkResult = r.value
		t.eq(result.items[0].error, null, "the created slot has no error")
		var slot: OWClient.BulkSlot = result.items[1]
		t.eq(slot.error.limit(), "element_link_ids", "the failed slot's limit")
		t.ok(slot.error.is_element_too_many_links(), "and its predicate")
		t.eq(slot.error.code, "invalid_request", "its code stays")
	t.done()
