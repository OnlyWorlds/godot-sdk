extends RefCounted
## Proposed changes through a fake transport (tests/fake_transport.gd): no test touches the network. propose,
## list_proposals, world_proposals, accept_proposal, decline_proposal, withdraw_proposal and review_new_element: each
## route's method, path, query, headers and body against what is sent, and each answer read; OWProposal and the queue's
## two kinds of row, a new element's evidence and expires as stored; the eight codes keel answers on these routes, and
## stale_proposal's conflicts and current. Ported from the Unity SDK's OWProposalTests (its proposals.test.mjs port from
## the TypeScript SDK 4.58.0, the queue's second kind of row from 4.66.0, the stored values from 4.156.0). A 202 on a
## write is held in test_client_writes.gd; the review mark's reading in test_review.gd. Every request is also held to
## keel's document in test_client_wire.gd.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const EL := "018f0000-0000-7000-8000-0000000000e1"
const PID := "018f0000-0000-7000-8000-0000000000a1"
const NEW_EL := "018f0000-0000-7000-8000-0000000000e2"
const BY := "018f0000-0000-7000-8000-0000000000b1"

## One row as keel's Proposal component gives it, as the Unity SDK's test writes it (house left out: an older server's).
static func _proposal() -> Dictionary:
	return {
		"kind": "proposal", "id": PID, "element_type": "location", "element_id": EL, "state": "open",
		"fields": {"description": "A harbour town."}, "omitted": [], "base": {"description": ""},
		"base_seq": 41, "evidence": "Chapter 3 names the harbour.", "expires": "2026-11-21T16:00:00Z",
		"by": BY, "via": "api", "client": "unity-sdk",
		"decided_by": null, "decided_at": null, "decline_reason": null,
		"created_at": "2026-10-22T16:00:00Z", "updated_at": "2026-10-22T16:00:00Z",
	}

## A queue row for a new element written as proposed (keel's ProposedNewElement): all ten keys.
static func _new_element_row() -> Dictionary:
	return {
		"kind": "new_element", "id": NEW_EL, "element_type": "character", "element_id": NEW_EL, "state": "open",
		"by": BY, "evidence": "Met her in chapter 4.", "expires": "2026-11-22",
		"created_at": "2026-10-23T07:00:00Z", "updated_at": "2026-10-23T07:00:00Z",
	}

static func _element() -> Dictionary:
	return {"id": EL, "name": "Harbour", "type": "location", "description": "A harbour town.", "change_seq": 42}

static func _json(v: Variant) -> String:
	return OWClient._compact(v)

static func _proposed(row: Dictionary) -> String:
	return _json({"proposal": row})

static func _list(rows: Array, more := true, cursor: Variant = "c2") -> String:
	return _json({"data": rows, "has_more": more, "next_cursor": cursor})

static func _envelope(type: String, code: String, extra := {}) -> String:
	var body := {"error": {"type": type, "code": code, "message": code, "param": null,
		"doc_url": "https://onlyworlds.github.io/api/errors#" + code}}
	body.merge(extra)
	return _json(body)

func _make(fake, more := {}) -> OWClient:
	var config := {"api_key": "ow_w_test", "api_pin": "1234", "base_url": BASE, "transport": fake}
	config.merge(more, true)
	return OWClient.new(config)

static func _names(request) -> Array:
	var names: Array = request.headers.keys()
	names.sort()
	return names

static func _query(request) -> Dictionary:
	var out := {}
	if not request.url.contains("?"):
		return out
	for pair in request.url.get_slice("?", 1).split("&"):
		out[pair.get_slice("=", 0).uri_decode()] = pair.get_slice("=", 1).uri_decode()
	return out

static func _path(request) -> String:
	return request.url.get_slice("?", 0)

static func _body(request) -> Variant:
	return JSON.parse_string(request.body) if request.body is String else null

## The value of [param r], or a failure and null: a test that gets null returns before done(), and is counted failed.
static func _value(t, r: OWClient.Reply, label: String) -> Variant:
	if not r.ok or r.value == null:
		t.fail("%s: no value (%s)" % [label, r.error])
		return null
	return r.value

static func _refused(t, r: OWClient.Reply, fake, words: String, label: String) -> void:
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains(words),
		"%s: refused, '%s' (got %s)" % [label, words, r.error])
	if r.error != null:
		t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so (%s)" % [label, r.error.message])
	t.eq(fake.calls.size(), 0, "%s: nothing sent" % label)

# -- propose -----------------------------------------------------------------------------------------------------------

func test_propose_posts_fields_evidence_and_expires_and_answers_the_row(t) -> void:
	var fake = Fake.new()
	fake.status = 201
	fake.body = _proposed(_proposal())
	var r := await _make(fake).propose("location", EL, {"description": "A harbour town."}, "Chapter 3 names the harbour.",
		{"expires": "2026-11-21T16:00:00Z"})
	var row: OWProposal = _value(t, r, "propose")
	if row == null:
		return
	t.eq([row.id, row.state, row.base_seq, row.fields.get("description")], [PID, "open", 41, "A harbour town."], "the row")
	t.eq(fake.calls.size(), 1, "one request")
	var q = fake.last()
	t.eq(q.url, BASE + "/location/" + EL + "/proposals", "the element's proposals")
	t.eq(q.method, "POST", "")
	t.eq(_body(q), {"fields": {"description": "A harbour town."}, "evidence": "Chapter 3 names the harbour.",
		"expires": "2026-11-21T16:00:00Z"}, "the body")
	# X-OW-Client is a header keel's document lists on this route (kept as `client`); no Idempotency-Key unless given.
	t.eq(_names(q), ["API-Key", "API-Pin", "Content-Type", "X-OW-Client"], "the headers")
	t.eq(q.headers.get("X-OW-Client"), "godot-sdk", "the client's name")
	t.done()

func test_propose_sends_an_idempotency_key_when_given_and_no_expires_unless_given(t) -> void:
	var fake = Fake.new()
	fake.status = 201
	fake.body = _proposed(_proposal())
	var r := await _make(fake).propose("location", EL, {"name": "Harbour"}, "x", {"idempotency_key": "prop-1"})
	t.ok(r.ok, str(r.error))
	t.eq(fake.last().headers.get("Idempotency-Key"), "prop-1", "the key as the header")
	t.eq(_body(fake.last()), {"fields": {"name": "Harbour"}, "evidence": "x"}, "no expires")
	t.done()

func test_propose_cleans_the_fields_as_a_patch_body_is_cleaned(t) -> void:
	var fake = Fake.new()
	fake.status = 201
	fake.body = _proposed(_proposal())
	var r := await _make(fake).propose("location", EL, {"name": "Harbour", "x_tangle_battle": 3, "world": "w",
		"type": "location", "created_at": "a", "updated_at": "b", "change_seq": 9}, "x")
	t.ok(r.ok, str(r.error))
	var body = _body(fake.last()) if fake.calls.size() == 1 else {}
	t.eq(body.get("fields"), {"name": "Harbour", "x_tangle_battle": 3.0}, "read-only keys left out, x_* kept")
	t.done()

func test_propose_refuses_a_known_of_stub_or_no_fields_before_sending(t) -> void:
	var fake = Fake.new()
	var c := _make(fake)
	_refused(t, await c.propose("location", EL, {"name": "", "known_of": true}, "x"), fake, "known-of stub", "a stub")
	_refused(t, await c.propose("location", EL, null, "x"), fake, "Dictionary or an OWElement", "no fields")
	_refused(t, await c.propose("location", EL, {"name": "H"}, "x", {"expires": 20991121}), fake, "expires is a String",
		"expires as a number")
	_refused(t, await c.propose("location", EL, {"name": "H"}, "x", {"since": "x"}), fake, "unknown option", "an option")
	t.done()

func test_the_proposal_routes_send_no_agent_header_and_the_clients_own_name(t) -> void:
	# keel's document lists X-OW-Client on propose, accept and review, and X-OW-Agent on none of them.
	var fake = Fake.new()
	var c := _make(fake, {"agent": true, "client": "atlas"})
	fake.then(201, _proposed(_proposal()))
	t.ok((await c.propose("location", EL, {"name": "H"}, "x")).ok, "propose")
	fake.then(200, _json({"proposal": _proposal(), "element": _element()}))
	t.ok((await c.accept_proposal("location", EL, PID)).ok, "accept")
	fake.then(200, _json({"deleted": NEW_EL}))
	t.ok((await c.review_new_element("character", NEW_EL, "decline")).ok, "review")
	t.eq(fake.calls.size(), 3, "three requests")
	for q in fake.calls:
		t.ok(not q.headers.has("X-OW-Agent"), "%s: no agent header" % q.url)
		t.eq(q.headers.get("X-OW-Client"), "atlas", "%s: the client's own name" % q.url)
	t.done()

# -- the lists ---------------------------------------------------------------------------------------------------------

func test_list_proposals_sends_state_since_limit_and_cursor_and_reads_the_page(t) -> void:
	var fake = Fake.new()
	fake.body = _list([_proposal()])
	var r := await _make(fake).list_proposals("location", EL, {"state": "all", "since": "2026-10-22T00:00:00Z",
		"limit": 5, "cursor": "c1"})
	var page: OWProposal.Page = _value(t, r, "list_proposals")
	if page == null:
		return
	t.eq(page.data.size(), 1, "one row")
	t.ok(page.data[0] is OWProposal and page.data[0].id == PID, "the row, typed")
	t.eq([page.has_more, page.next_cursor], [true, "c2"], "the page")
	var q = fake.last()
	t.eq(_path(q), BASE + "/location/" + EL + "/proposals", "")
	t.eq(q.method, "GET", "")
	t.eq(_query(q), {"state": "all", "since": "2026-10-22T00:00:00Z", "limit": "5", "cursor": "c1"}, "the query")
	t.eq(q.body, null, "no body")
	t.eq(_names(q), ["API-Key"], "a read: no PIN")
	t.done()

func test_list_proposals_with_no_options_sends_only_the_page_size(t) -> void:
	var fake = Fake.new()
	fake.body = _list([_proposal()])
	t.ok((await _make(fake, {"page_size": 25}).list_proposals("location", EL)).ok, "")
	t.eq(fake.last().url, BASE + "/location/" + EL + "/proposals?limit=25", "")
	t.done()

func test_list_proposals_refuses_the_world_queues_element_filter_before_sending(t) -> void:
	var fake = Fake.new()
	_refused(t, await _make(fake).list_proposals("location", EL, {"element": EL}), fake, "world_proposals", "element")
	_refused(t, await _make(fake).list_proposals("location", EL, {"limit": "5"}), fake, "limit is an int", "limit")
	_refused(t, await _make(fake).world_proposals({"bogus": 1}), fake, "unknown option", "world_proposals")
	t.done()

func test_world_proposals_sends_state_since_element_limit_and_cursor(t) -> void:
	var fake = Fake.new()
	fake.body = _list([_proposal()])
	var r := await _make(fake).world_proposals({"state": "open", "since": "2026-10-21T00:00:00Z", "element": EL,
		"limit": 10, "cursor": "c1"})
	var page: OWProposal.Page = _value(t, r, "world_proposals")
	if page == null:
		return
	t.eq(page.data[0].id, PID, "")
	t.eq(_path(fake.last()), BASE + "/world/proposals", "")
	t.eq(fake.last().method, "GET", "")
	t.eq(_query(fake.last()), {"state": "open", "since": "2026-10-21T00:00:00Z", "element": EL, "limit": "10",
		"cursor": "c1"}, "the query")
	var bare = Fake.new()
	bare.body = _list([_proposal()])
	await _make(bare).world_proposals()
	t.eq(bare.last().url, BASE + "/world/proposals?limit=100", "the page size alone")
	t.done()

func test_world_proposals_reads_both_kinds_in_keels_order_and_sends_the_cursor_back_as_it_came(t) -> void:
	# npm 4.66.0's and py 0.35.0's vector: one order, both kinds; the cursor is opaque (`<microseconds>.<id>` today),
	# never the last row's id.
	var opaque := "1761202800000000." + NEW_EL
	var fake = Fake.new()
	fake.body = _list([_new_element_row(), _proposal()], true, opaque)
	var c := _make(fake)
	var page: OWProposal.Page = _value(t, await c.world_proposals({"state": "all"}), "world_proposals")
	if page == null:
		return
	t.eq(page.data.map(func(p): return p.kind), ["new_element", "proposal"], "the kinds, in keel's order")
	t.eq(page.data.map(func(p): return p.is_new_element()), [true, false], "")
	var marked: OWProposal = page.data[0]
	t.eq([marked.id, marked.element_type, marked.element_id, marked.state, marked.by],
		[NEW_EL, "character", NEW_EL, "open", BY], "the new element's row")
	t.eq([marked.evidence, marked.expires, marked.created_at], ["Met her in chapter 4.", "2026-11-22",
		"2026-10-23T07:00:00Z"], "its mark's values, as stored")
	t.eq([marked.fields, marked.omitted, marked.base, marked.base_seq], [null, null, null, 0], "not sent: null")
	var proposal: OWProposal = page.data[1]
	t.eq([proposal.id, proposal.omitted], [PID, []], "")
	t.eq(proposal.evidence, "Chapter 3 names the harbour.", "")
	t.eq(proposal.expires, "2026-11-21T16:00:00Z", "a date-time string stays a string")
	t.eq(page.next_cursor, opaque, "")
	await c.world_proposals({"cursor": page.next_cursor})
	t.eq(_query(fake.last()).get("cursor"), opaque, "sent back as it came")
	await c.world_proposals({"cursor": PID})
	t.eq(_query(fake.last()).get("cursor"), PID, "an old bare proposal id is sent as given")
	t.done()

# -- a new element's evidence and expires, as stored (npm 4.156.0) -----------------------------------------------------

## The values keel's queue serves a new element's mark's evidence and expires as, each as itself (keel's own test of
## the queue row's values; the TypeScript SDK 4.156.0, where both became unknown), the Unity SDK's fourteen.
static func _stored_values() -> Array:
	return [
		["a line of text", "\"the Harbour Ledger, entry 14\""],
		["an empty string", "\"\""],
		["White_Space alone", "\"   \""],
		["a list of ids", "[\"0199c3a0-0000-7000-8000-0000000000a1\",\"0199c3a0-0000-7000-8000-0000000000b2\"]"],
		["an empty list", "[]"],
		["an object", "{\"k\":1}"],
		["an integer", "14"],
		["a date as a number", "20991121"],
		["a fraction", "2.5"],
		["true", "true"],
		["false", "false"],
		["null", "null"],
		["a date-time string stays a string", "\"2026-11-22T07:00:00Z\""],
		["an integer past 2^53", "9007199254740993"],
	]

## The one value Godot cannot hold: its JSON reads every number as a 64-bit float, so 2^53 + 1 is read, and written
## back, as 2^53. Held as Godot reads it, so a reader that keeps the digit turns this red.
const KNOWN_LOSS := {"9007199254740993": "9007199254740992"}

func get_cases() -> Array:
	var out := []
	for key in ["evidence", "expires"]:
		for v in _stored_values():
			out.append(["proposals:writes_back:%s:%s" % [key, v[0]], _writes_back.bind(key, v[1])])
			out.append(["proposals:reads:%s:%s" % [key, v[0]], _reads.bind(key, v[1])])
	return out

## A queue row for a new element whose mark holds [param json] at [param key], read through the client.
func _read_row_with(t, key: String, json: String) -> OWProposal:
	var row := _new_element_row()
	row.erase(key)
	var text := _json(row)
	text = text.substr(0, text.length() - 1) + ",\"%s\":%s}" % [key, json]
	var fake = Fake.new()
	fake.body = "{\"data\":[" + text + "],\"has_more\":false,\"next_cursor\":null}"
	var page: OWProposal.Page = _value(t, await _make(fake).world_proposals(), "world_proposals")
	if page == null or page.data.size() != 1:
		t.fail("one row")
		return null
	return page.data[0]

func _writes_back(t, key: String, json: String) -> void:   # bound arguments come after the call's
	var row := await _read_row_with(t, key, json)
	if row == null:
		return
	var written := row.to_dict()
	t.ok(written.has(key), "%s is written" % key)
	t.eq(_json(written.get(key)), KNOWN_LOSS.get(json, json), "%s written back as served" % key)
	t.done()

func _reads(t, key: String, json: String) -> void:
	var row := await _read_row_with(t, key, json)
	if row == null:
		return
	var read = row.evidence if key == "evidence" else row.expires
	var served = JSON.parse_string("{\"v\":" + json + "}")["v"]
	if served == null:
		t.eq(read, null, "a JSON null reads as null")
		t.done()
		return
	# The same JSON kind as Godot reads it (an integer is a float here, as every number Godot's JSON reads).
	t.eq(typeof(read), typeof(served), "the same kind")
	t.eq(read, served, "%s as itself" % key)
	t.eq(_json(read), KNOWN_LOSS.get(json, json), "the same value, to the digit")
	t.done()

func test_a_new_element_row_without_the_keys_reads_null_and_writes_null(t) -> void:
	var row := _new_element_row()
	row.erase("evidence")
	row.erase("expires")
	var fake = Fake.new()
	fake.body = _list([row], false, null)
	var page: OWProposal.Page = _value(t, await _make(fake).world_proposals(), "world_proposals")
	if page == null:
		return
	var read: OWProposal = page.data[0]
	t.eq([read.evidence, read.expires], [null, null], "absent: null")
	var written := read.to_dict()
	t.ok(written.has("evidence") and written.has("expires"), "both written")
	t.eq([written.get("evidence"), written.get("expires")], [null, null], "as null")
	t.done()

# The queue names the part of the house rules a row would change (keel's `house`): one of three words to the world's
# owner and co-builders, null to anyone else and for any other row.
func test_a_queue_row_reads_its_house_on_both_kinds_and_null_as_null(t) -> void:
	for c in [["proposal", "charter", OWProposal.HOUSE_CHARTER], ["proposal", "skill", OWProposal.HOUSE_SKILL],
			["proposal", "new_charter", OWProposal.HOUSE_NEW_CHARTER],
			["new_element", "new_charter", OWProposal.HOUSE_NEW_CHARTER], ["new_element", "skill", OWProposal.HOUSE_SKILL],
			["proposal", null, null], ["new_element", null, null]]:
		var row := _proposal() if c[0] == "proposal" else _new_element_row()
		row["house"] = c[1]
		var fake = Fake.new()
		fake.body = _list([row], false)
		var page: OWProposal.Page = (await _make(fake).world_proposals()).value
		var label := "%s, house %s" % [c[0], c[1]]
		if page == null or page.data.size() != 1:
			t.fail("%s: one row" % label)
			continue
		t.eq(page.data[0].house, c[2], label)
		t.eq(page.data[0].is_new_element(), c[0] == "new_element", label)
	t.eq([OWProposal.HOUSE_CHARTER, OWProposal.HOUSE_SKILL, OWProposal.HOUSE_NEW_CHARTER], ["charter", "skill", "new_charter"], "keel's words")
	t.done()

func test_a_queue_row_from_a_server_that_sends_no_house_reads_null(t) -> void:
	var fake = Fake.new()
	fake.body = _list([_proposal(), _new_element_row()], false)
	var page: OWProposal.Page = _value(t, await _make(fake).world_proposals(), "world_proposals")
	if page == null:
		return
	t.eq(page.data.size(), 2, "")
	t.eq(page.data.map(func(p): return p.house), [null, null], "")
	t.done()

func test_the_text_readers_read_a_string_as_itself_and_any_other_value_as_its_json_text(t) -> void:
	var ids := "[\"0199c3a0-0000-7000-8000-0000000000a1\",\"0199c3a0-0000-7000-8000-0000000000b2\"]"
	for c in [["evidence", "\"Met her in chapter 4.\"", "Met her in chapter 4."], ["evidence", "\"   \"", "   "],
			["evidence", "null", null], ["evidence", ids, ids], ["evidence", "{\"k\":1}", "{\"k\":1}"],
			["evidence", "true", "true"], ["expires", "\"2026-11-22\"", "2026-11-22"], ["expires", "20991121", "20991121"],
			["expires", "2.5", "2.5"]]:
		var row := await _read_row_with(t, c[0], c[1])
		if row == null:
			continue
		t.eq(row.evidence_text() if c[0] == "evidence" else row.expires_text(), c[2], "%s %s" % [c[0], c[1]])
	t.done()

func test_to_dict_writes_the_wire_keys_and_nothing_else(t) -> void:
	var row := OWProposal.new()
	row.evidence = ["0199c3a0-0000-7000-8000-0000000000a1"]
	row.expires = 20991121
	var written := row.to_dict()
	t.eq(_json(written.get("evidence")), "[\"0199c3a0-0000-7000-8000-0000000000a1\"]", "")
	t.eq(_json(written.get("expires")), "20991121", "")
	var keys: Array = written.keys()
	var wire: Array = OWProposal.KEYS.duplicate()
	keys.sort()
	wire.sort()
	t.eq(keys, wire, "the twenty keys keel serves on a row, and no other")
	t.eq(OWProposal.KEYS.size(), 20, "")
	t.done()

func test_a_proposal_row_reads_its_kind_and_omitted_and_a_row_with_no_kind_is_a_proposal(t) -> void:
	# An upsert's proposal names the fields it would empty.
	var row := _proposal()
	row["omitted"] = ["supertype", "location"]
	var fake = Fake.new()
	fake.then(201, _proposed(row))
	var read: OWProposal = _value(t, await _make(fake).propose("location", EL, {"name": "H"}, "x"), "propose")
	if read == null:
		return
	t.eq([read.kind, read.is_new_element(), read.omitted], ["proposal", false, ["supertype", "location"]], "")
	# A row from an older server carries no kind and is a proposal.
	row.erase("kind")
	fake.then(201, _proposed(row))
	var old: OWProposal = _value(t, await _make(fake).propose("location", EL, {"name": "H"}, "x"), "propose")
	if old == null:
		return
	t.eq([old.kind, old.is_new_element()], [null, false], "no kind: a proposal")
	t.eq([OWProposal.KIND_PROPOSAL, OWProposal.KIND_NEW_ELEMENT], ["proposal", "new_element"], "keel's words")
	t.done()

func test_of_reads_a_202s_row_and_nothing_else(t) -> void:
	var fake = Fake.new()
	fake.then(202, _proposed(_proposal()))
	var e: OWApiError = (await _make(fake).patch("location", EL, {"description": "A harbour town."})).error
	t.ok(e != null and e.is_proposed(), "a 202")
	if e == null:
		return
	var row := OWProposal.of(e.proposal)
	t.ok(row != null and row.id == PID and row.fields.get("description") == "A harbour town.", "the row, typed")
	for v in [null, "x", 3, ["a"]]:
		t.eq(OWProposal.of(v), null, var_to_str(v))
	t.done()

# -- a new element written as proposed ---------------------------------------------------------------------------------

func test_review_new_element_accept_posts_the_decision_with_the_pin_and_x_ow_client_and_answers_the_element(t) -> void:
	var settled := _element()
	settled["id"] = NEW_EL
	settled["type"] = "character"
	settled["x_review_proposed"] = null
	var fake = Fake.new()
	fake.body = _json({"element": settled})
	var answer: OWProposal.Reviewed = _value(t, await _make(fake).review_new_element("character", NEW_EL, "accept"), "review")
	if answer == null:
		return
	t.ok(answer.element is OWCharacter, "the element, typed")
	if answer.element != null:
		t.eq(answer.element.to_dict(), JSON.parse_string(_json(settled)), "as served, the mark cleared")
	t.eq(answer.deleted, null, "")
	t.eq(fake.calls.size(), 1, "")
	var q = fake.last()
	t.eq(q.url, BASE + "/character/" + NEW_EL + "/review", "")
	t.eq(q.method, "POST", "")
	t.eq(q.body, "{\"decision\":\"accept\"}", "")
	t.eq(_names(q), ["API-Key", "API-Pin", "Content-Type", "X-OW-Client"], "")
	t.eq(q.headers.get("X-OW-Client"), "godot-sdk", "")
	t.eq([OWProposal.Reviewed.ACCEPT, OWProposal.Reviewed.DECLINE], ["accept", "decline"], "")
	t.done()

func test_review_new_element_decline_sends_the_reason_when_given_none_without_and_answers_deleted(t) -> void:
	var fake = Fake.new()
	fake.body = _json({"deleted": NEW_EL})
	var c := _make(fake)
	var answer: OWProposal.Reviewed = _value(t, await c.review_new_element("character", NEW_EL, "decline", "Not canon."), "review")
	if answer == null:
		return
	t.eq([answer.deleted, answer.element], [NEW_EL, null], "")
	t.eq(fake.last().body, "{\"decision\":\"decline\",\"reason\":\"Not canon.\"}", "")
	await c.review_new_element("character", NEW_EL, "decline")
	t.eq(fake.last().body, "{\"decision\":\"decline\"}", "")
	t.done()

func test_review_new_element_refuses_another_decision_or_a_reason_on_an_accept_before_sending(t) -> void:
	var fake = Fake.new()
	var c := _make(fake)
	for bad in ["Accept", "delete", "approve", ""]:
		_refused(t, await c.review_new_element("character", NEW_EL, bad), fake, "decision must be 'accept' or 'decline'", bad)
	# keel answers a reason on an accept 422 (its body is {decision: accept} or {decision: decline, reason?}): py's
	# ValueError, refused here before sending.
	_refused(t, await c.review_new_element("character", NEW_EL, "accept", "fine"), fake, "decline only", "a reason")
	t.done()

func test_review_new_element_an_answer_without_the_key_its_decision_settles_is_refused(t) -> void:
	# py 0.35.0's vector: a 200 that does not say the review landed is never read as settled.
	for c in [["accept", "{\"deleted\":\"" + NEW_EL + "\"}"], ["decline", "{\"element\":{}}"], ["accept", "{}"]]:
		var fake = Fake.new()
		fake.body = c[1]
		var e: OWApiError = (await _make(fake).review_new_element("character", NEW_EL, c[0])).error
		t.ok(e != null and e.kind == OWApiError.ANSWER and e.status == 200 and e.message.contains("answered 200 without its"),
			"%s %s: %s" % [c[0], c[1], e])
	t.done()

func test_review_new_element_not_proposed_and_proposed_only_have_their_helpers(t) -> void:
	var fake = Fake.new()
	fake.then(422, _envelope("invalid_request_error", "not_proposed"))
	fake.then(403, _envelope("permission_error", "proposed_only"))
	fake.then(422, _envelope("invalid_request_error", "invalid_request"))
	var c := _make(fake)
	var e: OWApiError = (await c.review_new_element("character", NEW_EL, "accept")).error
	t.ok(e != null and e.is_not_proposed() and not e.is_proposed_only(), "not_proposed")
	e = (await c.review_new_element("character", NEW_EL, "accept")).error
	t.ok(e != null and e.is_proposed_only() and not e.is_not_proposed(), "proposed_only")
	e = (await c.review_new_element("character", NEW_EL, "accept")).error
	t.ok(e != null and not e.is_not_proposed(), "another 422 is not it")
	t.done()

# -- deciding ----------------------------------------------------------------------------------------------------------

func test_accept_proposal_posts_with_no_body_and_answers_the_row_and_the_element_as_written(t) -> void:
	var accepted := _proposal()
	accepted["state"] = "accepted"
	accepted["decided_by"] = "owner"
	accepted["decided_at"] = "2026-10-22T17:00:00Z"
	var fake = Fake.new()
	fake.body = _json({"proposal": accepted, "element": _element()})
	var outcome: OWProposal.Accepted = _value(t, await _make(fake).accept_proposal("location", EL, PID), "accept")
	if outcome == null:
		return
	t.ok(outcome.proposal is OWProposal and outcome.element is OWLocation, "both, typed")
	if outcome.proposal == null or outcome.element == null:
		return
	t.eq([outcome.proposal.state, outcome.proposal.decided_by], ["accepted", "owner"], "the row")
	t.eq(outcome.element.get_value("change_seq"), 42.0, "the element as written")
	var q = fake.last()
	t.eq(q.url, BASE + "/location/" + EL + "/proposals/" + PID + "/accept", "")
	t.eq(q.method, "POST", "")
	t.eq(q.body, null, "no body")
	t.eq(_names(q), ["API-Key", "API-Pin", "X-OW-Client"], "")
	t.done()

func test_decline_proposal_sends_the_reason_when_given_no_body_without_and_answers_the_row(t) -> void:
	var declined := _proposal()
	declined["state"] = "declined"
	declined["decided_by"] = "owner"
	declined["decline_reason"] = "Not canon."
	var fake = Fake.new()
	fake.body = _proposed(declined)
	var c := _make(fake)
	var row: OWProposal = _value(t, await c.decline_proposal("location", EL, PID, "Not canon."), "decline")
	if row == null:
		return
	t.eq([row.state, row.decline_reason], ["declined", "Not canon."], "")
	var q = fake.last()
	t.eq(q.url, BASE + "/location/" + EL + "/proposals/" + PID + "/decline", "")
	t.eq(q.method, "POST", "")
	t.eq(_body(q), {"reason": "Not canon."}, "")
	t.eq(_names(q), ["API-Key", "API-Pin", "Content-Type"], "keel's document lists no X-OW-Client here")
	await c.decline_proposal("location", EL, PID)
	t.eq(fake.last().body, null, "no reason, no body")
	t.eq(_names(fake.last()), ["API-Key", "API-Pin"], "")
	t.done()

func test_withdraw_proposal_deletes_and_answers_nothing(t) -> void:
	var fake = Fake.new()
	fake.status = 204
	fake.body = ""
	var r := await _make(fake).withdraw_proposal("location", EL, PID)
	t.ok(r.ok and r.value == null, str(r.error))
	t.eq(fake.calls.size(), 1, "")
	if fake.calls.size() != 1:
		return
	var q = fake.last()
	t.eq(q.url, BASE + "/location/" + EL + "/proposals/" + PID, "")
	t.eq(q.method, "DELETE", "")
	t.eq(q.body, null, "")
	t.eq(_names(q), ["API-Key", "API-Pin"], "")
	t.done()

func test_each_call_checks_its_path_values_and_its_key_before_sending(t) -> void:
	var calls := [
		["propose", func(c, pid): return await c.propose("location", pid, {"name": "H"}, "x")],
		["list_proposals", func(c, pid): return await c.list_proposals("location", pid)],
		["accept_proposal", func(c, pid): return await c.accept_proposal("location", EL, pid)],
		["decline_proposal", func(c, pid): return await c.decline_proposal("location", EL, pid)],
		["withdraw_proposal", func(c, pid): return await c.withdraw_proposal("location", EL, pid)],
		["review_new_element", func(c, pid): return await c.review_new_element("location", pid, "accept")],
	]
	for call in calls:
		var fake = Fake.new()
		_refused(t, await call[1].call(_make(fake), "a/b"), fake, "is not one path segment", call[0])
	calls.append(["world_proposals", func(c, _pid): return await c.world_proposals()])
	# An account token and a keyless client send none of them.
	for more in [{"api_key": "ow_a_test", "world": "w1"}, {"api_key": null, "api_pin": null, "world": "w1"}]:
		for call in calls:
			var fake = Fake.new()
			_refused(t, await call[1].call(_make(fake, more), PID), fake, "needs", "%s on %s" % [call[0], more.get("api_key")])
	t.done()

# -- the codes ---------------------------------------------------------------------------------------------------------

## [helper, status, type, code]: the six proposal codes, review_by_another (a review mark whose `by` is not the
## writer's own membership id, from a key below co-builder) and review_mark_empty (a write carrying an empty mark).
static func _codes() -> Array:
	return [
		["is_field_not_visible", 422, "invalid_request", "field_not_visible"],
		["is_too_many_open", 422, "invalid_request", "too_many_open"],
		["is_stale_proposal", 409, "invalid_request", "stale_proposal"],
		["is_proposed_only", 403, "permission_error", "proposed_only"],
		["is_own_proposal", 403, "permission_error", "own_proposal"],
		["is_not_proposed", 422, "invalid_request", "not_proposed"],
		["is_review_by_another", 403, "permission_error", "review_by_another"],
		["is_review_mark_empty", 422, "invalid_request", "review_mark_empty"],
	]

func test_each_code_has_a_helper_true_for_its_own_status_and_code_only(t) -> void:
	for c in _codes():
		var extra := {"conflicts": [], "current": _element()} if c[3] == "stale_proposal" else {}
		var fake = Fake.new()
		fake.then(c[1], _envelope(c[2], c[3], extra))
		fake.then(400, _envelope(c[2], c[3]))
		var client := _make(fake)
		var e: OWApiError = (await client.accept_proposal("location", EL, PID)).error
		if e == null:
			t.fail("%s: no error" % c[0])
			continue
		for other in _codes():
			t.eq(e.call(other[0]), other[0] == c[0], "%s: %s" % [c[0], other[0]])
		var off: OWApiError = (await client.accept_proposal("location", EL, PID)).error
		t.ok(off != null and not off.call(c[0]), "%s at 400" % c[0])
	t.done()

func test_a_write_with_an_empty_mark_is_422_review_mark_empty(t) -> void:
	var fake = Fake.new()
	fake.then(422, _envelope("invalid_request", "review_mark_empty"))
	var e: OWApiError = (await _make(fake).patch("location", EL, {"x_review_proposed": {}})).error
	t.ok(e != null and e.is_review_mark_empty(), "review_mark_empty")
	if e != null:
		for other in _codes():
			if other[0] != "is_review_mark_empty":
				t.ok(not e.call(other[0]), other[0])
	fake.then(422, _envelope("invalid_request", "not_proposed"))
	e = (await _make(fake).patch("location", EL, {"name": "x"})).error
	t.ok(e != null and not e.is_review_mark_empty(), "not_proposed is not it")
	t.done()

func test_stale_proposal_carries_its_conflicts_and_current(t) -> void:
	var current := _element()
	current["description"] = "A fishing village."
	current["change_seq"] = 43
	var conflicts := [{"field": "description", "base": "", "current": "A fishing village."}, {"field": 3, "base": 1}]
	var fake = Fake.new()
	fake.then(409, _envelope("invalid_request", "stale_proposal", {"conflicts": conflicts, "current": current}))
	var e: OWApiError = (await _make(fake).accept_proposal("location", EL, PID)).error
	if e == null:
		t.fail("no error")
		return
	t.ok(e.is_stale_proposal(), "")
	var read := e.conflicts()
	t.eq(read.size(), 1, "one conflict; an item with no field name is left out")
	if read.size() == 1:
		t.ok(read[0] is OWProposal.Conflict, "typed")
		t.eq([read[0].field, read[0].base, read[0].current], ["description", "", "A fishing village."], "")
	t.eq(e.current(), JSON.parse_string(_json(current)), "the element now")
	# A stale_proposal with neither still parses.
	fake.then(409, _envelope("invalid_request", "stale_proposal"))
	e = (await _make(fake).accept_proposal("location", EL, PID)).error
	t.ok(e != null and e.is_stale_proposal() and e.conflicts().is_empty() and e.current() == null, "a bare one")
	# Another 409 is not one, and carries neither.
	fake.then(409, _envelope("invalid_request", "id_conflict", {"conflicts": conflicts, "current": current}))
	e = (await _make(fake).create("location", {"name": "x"})).error
	t.ok(e != null and not e.is_stale_proposal() and e.conflicts().is_empty() and e.current() == null, "id_conflict")
	t.done()

# -- the world's switch ------------------------------------------------------------------------------------------------

func test_get_world_reads_agent_writes_proposed_through(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"w\",\"name\":\"W\",\"agent_writes_proposed\":true}"
	var r := await _make(fake).get_world()
	t.ok(r.ok and r.value.get("agent_writes_proposed") == true, str(r.error))
	t.done()
