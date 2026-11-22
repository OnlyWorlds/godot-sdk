extends RefCounted
## Joining a world by link through a fake transport (tests/fake_transport.gd): no test touches the network. The code's
## shape in a pasted link ([method OWJoin.parse_link]), the two keyless POSTs ([method OWJoin.preview],
## [method OWJoin.redeem]) and both of /join's answers, the refusals keel answers and the ones made before sending, and
## a person's join on an account token ([method OWClient.accept_join]). Ported from the Unity SDK's OWJoinTests and
## OWAccountRouteTests (AcceptJoin), with the TypeScript SDK's vectors (test/player-join.test.mjs, test/v2-client.test.mjs)
## where they ask more. The bodies are keel's schemas field for field (accounts/join_api.py: PLAYER_JOINED_SCHEMA,
## JOIN_SCHEMA, PREVIEW_SCHEMA).

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const CODE := "ow_j_EoEUrAfQ9xumy-lbBJqXix3q1xl49-P4"

const PLAYER_JOINED := {"kind": "player", "key": "ow_r_guest",
	"world": {"id": "0196f0a2-0000-7000-8000-000000000001", "name": "Moppetopia", "description": ""},
	"character": {"id": "0196f0a2-0000-7000-8000-0000000000c1", "name": "Pip"}, "role": "guest"}

const AGENT_JOINED := {"kind": "agent",
	"world": {"id": "0196f0a2-0000-7000-8000-000000000001", "name": "Moppetopia", "description": ""},
	"seat": {"id": "s1", "role": "contributor", "agent_name": "Scribe"},
	"with_character": false, "character": null, "key": "ow_w_seat", "pin": "ow_s_secret",
	"base_url": "https://example.test/api/v2", "env": "OW_KEY=ow_w_seat", "next": [], "members": [],
	"front_door": {"sponsor": {"id": "m-sam", "kind": "person", "name": "The Mapmaker"},
		"sponsor_character": "c-map", "my_character": null, "charter": "law-1", "charter_skill": ["obj-1", "obj-2"]},
	"reading_aids": {"charter": {"id": "law-1", "name": "House rules", "rules": [], "skill": ["obj-1", "obj-2"]},
		"guide": null, "domains": [{"id": "con-d1", "name": "The Harbour", "sentence": "Where the ships come in.", "hubs": []}]}}

const PREVIEW := {"reader": "player", "world": {"name": "Moppetopia", "description": "A demo"},
	"invited_by": "Sam", "note": null, "owner_character": "The Mapmaker", "role": "guest", "with_character": true,
	"expires_at": "2026-10-26T14:00:00+00:00", "glimpse": null}

## A person link's preview with the note its maker wrote (keel's preview, accounts/join_api.py: [code]note[/code], a
## person link's only, plain text with its line breaks, else null).
const PERSON_PREVIEW := {"reader": "person", "world": {"name": "Moppetopia", "description": "A demo"},
	"invited_by": "Sam", "note": "Come and help with the harbour.\nBring the maps.", "owner_character": null,
	"role": "contributor", "with_character": false, "expires_at": "2026-10-26T14:00:00+00:00", "glimpse": null}

## The glimpse the TypeScript SDK's test sends (4.189.0): a contributor's link, two things, one link between them.
const GLIMPSE := {"picked_by": "links", "things": [{"name": "Gela", "type": "location"}, {"name": "Ada", "type": "character"}],
	"links": [{"from": 1, "to": 0, "field": "location", "label": "is at"}]}

## A party link's preview: keel's table_preview keys after the seven (accounts/agents.py, PR 110).
const TABLE_PREVIEW := {"reader": "player", "world": {"name": "Moppetopia", "description": "A demo"},
	"invited_by": "Sam", "note": null, "owner_character": null, "role": "guest", "with_character": true,
	"expires_at": "2026-10-26T14:00:00+00:00", "glimpse": null,
	"max_uses": 4, "uses_left": 3, "name_required": false,
	"characters": [{"id": "c-ana", "name": "Ana", "image_url": null, "taken": false},
		{"id": "c-bo", "name": "Bo", "image_url": "https://media.onlyworlds.com/bo.webp", "taken": true}]}

const MEMBERSHIP := {"id": "m7", "world_id": "w1", "world_name": "Ostvik", "role": "contributor",
	"joined_at": "2026-10-31T01:00:00+00:00", "roster_character": null}

static func _json(v: Variant) -> String:
	return JSON.stringify(v, "", false)

static func _answering(answer_status: int, answer: Variant):
	var fake = Fake.new()
	fake.status = answer_status
	fake.body = answer if answer is String else _json(answer)
	return fake

static func _refusing(answer_status: int, code: String, param: Variant):
	return _answering(answer_status, {"error": {"type": "invalid_request", "code": code, "param": param, "message": "refused"}})

static func _body(request) -> Variant:
	return JSON.parse_string(request.body) if request.body is String else null

static func _no_credential(t, request, label: String) -> void:
	for h in ["API-Key", "API-Pin", "Authorization"]:
		t.ok(not request.headers.has(h), "%s: no %s" % [label, h])

static func _sorted_headers(request) -> Array:
	var names: Array = request.headers.keys()
	names.sort()
	return names

static func _refused(t, r: OWClient.Reply, fake, words: String, label: String) -> void:
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains(words),
		"%s: refused, '%s' (got %s)" % [label, words, r.error])
	if r.error != null:
		t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so (%s)" % [label, r.error.message])
	t.eq(fake.calls.size(), 0, "%s: nothing sent" % label)

func _redeem(fake, options := {}) -> OWClient.Reply:
	var o := {"transport": fake, "base_url": BASE}
	o.merge(options, true)
	return await OWJoin.redeem(CODE, o)

func _preview(fake) -> OWClient.Reply:
	return await OWJoin.preview(CODE, {"transport": fake, "base_url": BASE})

# -- parse_link ---------------------------------------------------------------------------------------------------------

func test_parse_link_finds_the_code(t) -> void:
	for c in [
		["https://www.onlyworlds.com/join#" + CODE, "the site's link"],
		["  http://localhost:8000/join#" + CODE + "\n", "any host, white space round it"],
		["https://www.onlyworlds.com/join/0196f0a2-0000-7000-8000-000000000001#" + CODE, "the link with the preview on"],
		[CODE, "a bare code"],
		["#" + CODE, "the fragment alone"],
		["https://www.onlyworlds.com/join# " + CODE + " ", "white space after the #"],
		["　" + CODE + " ", "Unicode's white space trimmed"],
	]:
		t.eq(OWJoin.parse_link(c[0]), CODE, c[1])
	t.done()

func test_parse_link_refuses_text_with_no_code(t) -> void:
	for text in [null, "", "   ", "https://www.onlyworlds.com/join", "https://www.onlyworlds.com/join#", "ow_j_",
			"ow_r_readkey", "ow_j_two words", "ow_j_two words", "OW_J_upper", 7]:
		t.eq(OWJoin.parse_link(text), "", "no code in %s" % var_to_str(text))
	t.done()

# -- The requests -------------------------------------------------------------------------------------------------------

func test_redeem_posts_the_code_and_name_with_no_credential(t) -> void:
	var fake = _answering(201, PLAYER_JOINED)
	var r := await _redeem(fake, {"name": "Ana"})
	t.ok(r.ok, "answered (%s)" % r.error)
	t.eq(fake.calls.size(), 1, "one request")
	var a = fake.last()
	t.eq(a.method, "POST", "the verb")
	t.eq(a.url, BASE + "/join", "the path, no query")
	t.eq(a.body, "{\"code\":\"%s\",\"name\":\"Ana\"}" % CODE, "the code and the name, in keel's spelling")
	t.eq(_sorted_headers(a), ["Content-Type"], "the media type alone: no credential")
	_no_credential(t, a, "redeem")
	t.done()

func test_redeem_leaves_out_what_the_caller_left_out(t) -> void:
	# A blank name means the Character's own name; an absent one, or a null, must not arrive as null.
	var fake = _answering(201, PLAYER_JOINED)
	await _redeem(fake)
	await _redeem(fake, {"name": null, "agent_name": null, "character": null})
	t.eq(fake.calls.size(), 2, "both sent")
	for a in fake.calls:
		t.eq(_body(a), {"code": CODE}, "the code alone")
	t.done()

func test_redeem_sends_an_agents_name(t) -> void:
	var fake = _answering(201, AGENT_JOINED)
	await _redeem(fake, {"agent_name": "Scribe"})
	t.eq(_body(fake.last()), {"code": CODE, "agent_name": "Scribe"}, "agent_name, and no name")
	t.done()

func test_redeem_sends_the_pick(t) -> void:
	# The TypeScript SDK's table vector: the pick as character, with or without a name, in keel's order.
	var fake = _answering(201, PLAYER_JOINED)
	await _redeem(fake, {"character": "c-ana"})
	t.eq(fake.last().body, "{\"code\":\"%s\",\"character\":\"c-ana\"}" % CODE, "the code and the pick, nothing else")
	await _redeem(fake, {"character": "c-ana", "name": "Ana"})
	t.eq(fake.last().body, "{\"code\":\"%s\",\"name\":\"Ana\",\"character\":\"c-ana\"}" % CODE, "name before character")
	await _redeem(fake, {"character": "c1", "agent_name": "A", "name": "N"})
	t.eq(fake.last().body, "{\"code\":\"%s\",\"name\":\"N\",\"agent_name\":\"A\",\"character\":\"c1\"}" % CODE,
		"every option, in keel's order whatever the caller's")
	t.done()

func test_preview_posts_the_code_with_no_credential(t) -> void:
	var fake = _answering(200, PREVIEW)
	var r := await _preview(fake)
	t.ok(r.ok, "answered (%s)" % r.error)
	var a = fake.last()
	t.eq(a.method, "POST", "the verb")
	t.eq(a.url, BASE + "/join/preview", "the path, no query")
	t.eq(a.body, "{\"code\":\"%s\"}" % CODE, "the code alone")
	t.eq(_sorted_headers(a), ["Content-Type"], "the media type alone: no credential")
	_no_credential(t, a, "preview")
	t.done()

func test_the_default_host_is_production(t) -> void:
	var fake = _answering(200, PREVIEW)
	await OWJoin.preview(CODE, {"transport": fake})
	t.eq(fake.last().url, "https://www.onlyworlds.com/api/v2/join/preview", "production, when no base_url is given")
	await OWJoin.redeem(CODE, {"transport": fake, "base_url": BASE + "//"})
	t.eq(fake.last().url, BASE + "/join", "a base_url's trailing slashes trimmed")
	t.done()

# -- The answers --------------------------------------------------------------------------------------------------------

func test_a_players_answer_is_a_read_key_and_its_character(t) -> void:
	var r := await _redeem(_answering(201, PLAYER_JOINED))
	t.ok(r.value is OWJoin.Joined, "an OWJoin.Joined (%s)" % r.error)
	if r.value is OWJoin.Joined:
		var j: OWJoin.Joined = r.value
		t.ok(j.is_player(), "a player's")
		t.ok(not j.is_agent(), "not an agent's")
		t.eq(j.key, "ow_r_guest", "the key")
		t.eq(OWClient.key_kind_of(j.key), OWClient.KEY_READ, "a read key")
		t.eq(j.pin, null, "no PIN")
		t.eq(j.world.id, "0196f0a2-0000-7000-8000-000000000001", "the world's id, the code spent")
		t.eq(j.world.name, "Moppetopia", "its name")
		t.eq(j.character.id, "0196f0a2-0000-7000-8000-0000000000c1", "the Character it reads as")
		t.eq(j.character.name, "Pip", "its name")
		t.eq(j.role_in_world(), "guest", "the role, on the answer")
		t.eq(j.seat, null, "no seat")
		t.eq(j.served, PLAYER_JOINED, "the answer as served")
	t.done()

func test_an_agents_answer_is_a_seat_key_and_secret(t) -> void:
	var r := await _redeem(_answering(201, AGENT_JOINED), {"agent_name": "Scribe"})
	t.ok(r.value is OWJoin.Joined, "an OWJoin.Joined (%s)" % r.error)
	if r.value is OWJoin.Joined:
		var j: OWJoin.Joined = r.value
		t.ok(j.is_agent(), "an agent's")
		t.ok(not j.is_player(), "not a player's")
		t.eq(j.key, "ow_w_seat", "the seat's write key")
		t.eq(j.pin, "ow_s_secret", "its secret")
		t.eq(j.role, null, "no role on the answer itself")
		t.eq(j.role_in_world(), "contributor", "the role, from the seat")
		t.eq(j.seat.id, "s1", "the seat")
		t.eq(j.seat.agent_name, "Scribe", "its agent's name")
		t.eq(j.character, null, "no Character")
		t.eq(j.base_url, "https://example.test/api/v2", "the base URL its key is for")
		t.eq(j.env, "OW_KEY=ow_w_seat", "the .env lines")
	t.done()

func test_an_agents_answer_carries_the_front_door_and_the_reading_aids(t) -> void:
	# The sponsor who answers for the seat, their Character and the Charter to read first; the same packet as GET /me's.
	var r := await _redeem(_answering(201, AGENT_JOINED), {"agent_name": "Scribe"})
	var j: OWJoin.Joined = r.value
	t.eq(j.front_door, AGENT_JOINED["front_door"], "the front door as served")
	if j.front_door is Dictionary:
		t.eq(j.front_door["sponsor"]["id"], "m-sam", "the sponsor")
		t.eq(j.front_door["sponsor_character"], "c-map", "the sponsor's Character")
		t.eq(j.front_door["charter_skill"], ["obj-1", "obj-2"], "the Charter's skill")
	t.ok(j.reading_aids is OWCharter.Packet, "the reading aids, as OWCharter.served reads them")
	if j.reading_aids is OWCharter.Packet:
		t.eq(j.reading_aids.charter["id"], "law-1", "the Charter")
		t.eq(j.reading_aids.charter["skill"], ["obj-1", "obj-2"], "its skill")
		t.eq(j.reading_aids.guide, null, "no Guide")
		t.eq(j.reading_aids.domains.map(func(d): return d["name"]), ["The Harbour"], "one Domain")
	t.done()

func test_a_players_answer_has_no_front_door(t) -> void:
	var j: OWJoin.Joined = (await _redeem(_answering(201, PLAYER_JOINED))).value
	t.ok(j != null, "answered")
	if j != null:
		t.eq(j.front_door, null, "no front door")
		t.eq(j.reading_aids, null, "nor the aids")
	t.done()

func test_a_preview_reads_every_field(t) -> void:
	var r := await _preview(_answering(200, PREVIEW))
	t.ok(r.value is OWJoin.Preview, "an OWJoin.Preview (%s)" % r.error)
	if r.value is OWJoin.Preview:
		var p: OWJoin.Preview = r.value
		t.eq(p.reader, "player", "reader")
		t.eq(p.world.name, "Moppetopia", "the world's name")
		t.eq(p.world.description, "A demo", "its description")
		t.eq(p.world.id, null, "no id: the code is unspent")
		t.eq(p.invited_by, "Sam", "invited_by")
		t.eq(p.owner_character, "The Mapmaker", "owner_character")
		t.eq(p.role, "guest", "role")
		t.eq(p.with_character, true, "with_character")
		t.eq(p.expires_at, "2026-10-26T14:00:00+00:00", "expires_at, as sent")
		t.eq(p.note, null, "a player link keeps no note")
		t.eq(p.glimpse, null, "a player's link shows no glimpse")
		# A link for one carries none of a table's keys.
		t.ok(not p.is_table(), "not a table")
		t.eq(p.max_uses, null, "max_uses")
		t.eq(p.uses_left, null, "uses_left")
		t.eq(p.name_required, null, "name_required")
		t.eq(p.characters, null, "characters")
	t.done()

func test_a_person_links_preview_reads_the_note_as_written_line_break_kept(t) -> void:
	# The TypeScript SDK's OwJoinPreview.note (4.188.0): a string or null. Kills: the note left unread, read under another
	# key, or its line break lost.
	var p: OWJoin.Preview = (await _preview(_answering(200, PERSON_PREVIEW))).value
	t.ok(p != null, "answered")
	if p != null:
		t.eq(p.reader, "person", "a person's link")
		t.eq(p.note, "Come and help with the harbour.\nBring the maps.", "the note, its line break kept")
		t.eq(p.invited_by, "Sam", "the note is not the inviter's name")
		t.eq(p.with_character, false, "no Character for a person")
		t.eq(p.owner_character, null, "no owner's Character set")
	t.done()

func test_a_preview_reads_the_glimpse_a_group_or_null(t) -> void:
	# The TypeScript SDK's previewJoin glimpse vector (4.189.0): the group comes back as it was sent, and null reads null.
	# Written back out, the group is the JSON that came in, key for key and in order, so a thing read with an id, a link
	# without its label or a key read under another name fails here.
	var with_one := PERSON_PREVIEW.duplicate(true)
	with_one["note"] = null
	with_one["glimpse"] = GLIMPSE.duplicate(true)
	var p: OWJoin.Preview = (await _preview(_answering(200, with_one))).value
	t.ok(p != null and p.glimpse is OWJoin.Glimpse, "a contributor's link shows its glimpse")
	if p != null and p.glimpse is OWJoin.Glimpse:
		var g: OWJoin.Glimpse = p.glimpse
		t.eq(g.picked_by, "links", "picked_by")
		t.ok(g.is_links(), "by links")
		t.ok(not g.is_strand(), "not the strand")
		t.eq(g.things.map(func(x): return x.name), ["Gela", "Ada"], "the things' names, in order")
		t.eq(g.things.map(func(x): return x.type), ["location", "character"], "their types")
		t.eq(g.links.size(), 1, "one link")
		if g.links.size() == 1:
			t.eq(g.links[0].from, 1, "from is the thing whose field holds the link: Ada, a whole number")
			t.eq(g.links[0].to, 0, "to, a whole number")
			t.eq(g.links[0].field, "location", "the field")
			t.eq(g.links[0].label, "is at", "the words")
		t.eq(OWClient._compact(g.to_dict()), OWClient._compact(GLIMPSE), "the glimpse written back is the one sent")
	var strand := with_one.duplicate(true)
	strand["glimpse"]["picked_by"] = "strand"
	var s: OWJoin.Preview = (await _preview(_answering(200, strand))).value
	t.ok(s != null and s.glimpse != null and s.glimpse.is_strand() and not s.glimpse.is_links(), "the strand")
	var none: OWJoin.Preview = (await _preview(_answering(200, PERSON_PREVIEW))).value
	t.ok(none != null, "answered")
	if none != null:
		t.eq(none.glimpse, null, "null reads null")
	t.done()

func test_a_table_preview_reads_its_places_and_its_characters_in_order(t) -> void:
	var p: OWJoin.Preview = (await _preview(_answering(200, TABLE_PREVIEW))).value
	t.ok(p != null, "answered")
	if p != null:
		t.ok(p.is_table(), "a table")
		t.eq(p.max_uses, 4, "max_uses, a whole number")
		t.eq(p.uses_left, 3, "uses_left, a whole number")
		t.eq(p.name_required, false, "name_required")
		t.eq(p.owner_character, null, "owner_character")
		t.ok(p.characters is Array and p.characters.size() == 2, "two to pick from")
		if p.characters is Array and p.characters.size() == 2:
			t.ok(p.characters[0] is OWJoin.Pick, "each an OWJoin.Pick")
			t.eq(p.characters.map(func(c): return c.id), ["c-ana", "c-bo"], "in the owner's order")
			t.eq(p.characters[1].name, "Bo", "a name")
			t.eq(p.characters[0].image_url, null, "no picture")
			t.eq(p.characters[1].image_url, "https://media.onlyworlds.com/bo.webp", "a picture")
			t.eq([p.characters[0].taken, p.characters[1].taken], [false, true], "taken")
	var fresh := TABLE_PREVIEW.duplicate(true)
	fresh["max_uses"] = 6
	fresh["uses_left"] = 6
	fresh["name_required"] = true
	fresh["characters"] = []
	var q: OWJoin.Preview = (await _preview(_answering(200, fresh))).value
	t.ok(q != null and q.is_table() and q.name_required == true and q.characters == [], "a table that lists none")
	t.done()

# -- Refusals keel answers ----------------------------------------------------------------------------------------------

func test_a_bad_code_is_keels_one_not_found(t) -> void:
	var body := {"error": {"type": "invalid_request", "code": "not_found",
		"message": "This join code is not valid. It may have been used, revoked, or expired."}}
	for r in [await _redeem(_answering(404, body)), await _preview(_answering(404, body))]:
		t.ok(r.error != null and r.error.kind == OWApiError.API, "keel's refusal")
		if r.error != null:
			t.ok(r.error.is_not_found(), "is_not_found")
			t.ok(not r.error.is_already_member(), "and nothing else")
			t.ok(not r.error.is_character_taken(), "and nothing else")
		t.eq(r.value, null, "no answer")
	t.done()

func test_a_missing_agent_name_names_its_param(t) -> void:
	var r := await _redeem(_refusing(422, "invalid_request", "agent_name"))
	t.ok(r.error != null and r.error.param == "agent_name", "the param (%s)" % r.error)
	if r.error != null:
		t.ok(not r.error.is_character_invalid(), "not a refused pick")
	t.done()

func test_a_taken_pick_is_character_taken_and_nothing_else(t) -> void:
	var e: OWApiError = (await _redeem(_refusing(422, "character_taken", "character"), {"character": "c-bo"})).error
	t.ok(e != null, "refused")
	if e != null:
		t.eq([e.is_character_taken(), e.is_character_invalid(), e.is_world_full()], [true, false, false], "taken")
		t.ok(e.is_validation_error(), "a validation error")
	var other: OWApiError = (await _redeem(_refusing(409, "character_taken", "character"))).error
	t.ok(other != null and not other.is_character_taken(), "the code on another status is not it")
	t.done()

func test_a_pick_off_the_list_is_character_invalid_but_a_missing_name_is_not(t) -> void:
	var off: OWApiError = (await _redeem(_refusing(422, "invalid_request", "character"), {"character": "c-zed"})).error
	t.ok(off != null, "refused")
	if off != null:
		t.eq([off.is_character_taken(), off.is_character_invalid(), off.is_world_full()], [false, true, false], "off the list")
	# The TypeScript SDK's: any other param's 422, a 400, another code: never a refused pick.
	for c in [[422, "invalid_request", "name"], [422, "invalid_request", "characters"], [422, "invalid_request", "max_uses"],
			[422, "invalid_request", null], [400, "invalid_request", "character"], [422, "invalid_link", "character"]]:
		var e: OWApiError = (await _redeem(_refusing(c[0], c[1], c[2]))).error
		t.ok(e != null and not e.is_character_invalid(), "%d %s on %s is not a refused pick" % [c[0], c[1], c[2]])
	var no_name: OWApiError = (await _redeem(_refusing(422, "invalid_request", "name"))).error
	t.eq(no_name.param, "name", "the missing name names its param")
	t.done()

func test_a_full_world_is_world_full_only_as_a_422(t) -> void:
	var full: OWApiError = (await _redeem(_refusing(422, "world_full", null))).error
	t.ok(full != null, "refused")
	if full != null:
		t.eq([full.is_character_taken(), full.is_character_invalid(), full.is_world_full()], [false, false, true], "full")
	var other: OWApiError = (await _redeem(_refusing(409, "world_full", null))).error
	t.ok(other != null and not other.is_world_full(), "the code on another status is not it")
	t.done()

func test_a_dropped_connection_is_a_transport_error_and_an_answer_not_an_object_is_an_answer_error(t) -> void:
	var fake = Fake.new()
	fake.fail("can't connect")
	var r := await _redeem(fake)
	t.ok(r.error != null and r.error.kind == OWApiError.TRANSPORT and r.error.message.contains("POST /join")
		and r.error.message.contains("can't connect"), "no answer: %s" % r.error)
	for answer in ["not json", "[]", ""]:
		var p := await _preview(_answering(200, answer))
		t.ok(p.error != null and p.error.kind == OWApiError.ANSWER and p.error.status == 200,
			"a 200 of %s is not the answer: %s" % [var_to_str(answer), p.error])
	t.done()

# -- Refusals before sending --------------------------------------------------------------------------------------------

func test_no_code_or_a_bad_option_is_the_callers_error_nothing_sent(t) -> void:
	var fake = Fake.new()
	_refused(t, await OWJoin.redeem("", {"transport": fake}), fake, "OWJoin.redeem: a join code is required", "redeem, no code")
	_refused(t, await OWJoin.preview("", {"transport": fake}), fake, "OWJoin.preview: a join code is required", "preview, no code")
	_refused(t, await OWJoin.redeem(CODE, {"transport": fake, "nmae": "A"}), fake, "unknown option 'nmae'", "a misspelt option")
	_refused(t, await OWJoin.preview(CODE, {"transport": fake, "name": "A"}), fake, "unknown option 'name'",
		"a preview takes no name")
	_refused(t, await OWJoin.redeem(CODE, {"transport": fake, "name": 7}), fake, "name is a String", "a name that is no String")
	_refused(t, await OWJoin.redeem(CODE, {"transport": "fake"}), fake, "transport is an OWTransport", "a transport that is none")
	_refused(t, await OWJoin.preview(CODE, {"transport": fake, "base_url": 1}), fake, "base_url is a String", "a base_url that is none")
	t.done()

# -- accept_join: a person's link, on an account token ------------------------------------------------------------------

func _account(fake, key: Variant = "ow_a_acct", more := {}) -> OWClient:
	var config := {"api_key": key, "api_pin": "pin-for-tests", "base_url": BASE, "transport": fake, "agent": true, "client": "atlas"}
	config.merge(more, true)
	return OWClient.new(config)

# The TypeScript SDK's acceptJoin() (4.12.0): POST /account/join with {code} alone, the Bearer, no PIN (accepting needs
# none) and no write header. Kills: the wrong verb or path, the code under another key or beside others, the PIN or a
# write header sent, or the membership misread.
func test_accept_join_posts_account_join_the_code_alone_the_bearer_and_answers_the_membership(t) -> void:
	var fake = _answering(201, MEMBERSHIP)
	var r := await _account(fake).accept_join("ow_j_abc")
	t.eq(fake.calls.size(), 1, "one request")
	var a = fake.last()
	t.eq(a.method, "POST", "the verb")
	t.eq(a.url, BASE + "/account/join", "the path, no query")
	t.eq(a.body, "{\"code\":\"ow_j_abc\"}", "the code alone")
	t.eq(_sorted_headers(a), ["Authorization", "Content-Type"], "the Bearer and the media type: no PIN, no write header")
	t.eq(a.headers.get("Authorization"), "Bearer ow_a_acct", "the account token as its Bearer")
	t.ok(r.value is OWJoin.JoinedMembership, "an OWJoin.JoinedMembership (%s)" % r.error)
	if r.value is OWJoin.JoinedMembership:
		var m: OWJoin.JoinedMembership = r.value
		t.eq([m.id, m.world_id, m.world_name, m.role, m.joined_at, m.roster_character],
			["m7", "w1", "Ostvik", "contributor", "2026-10-31T01:00:00+00:00", null], "the membership")
	var with_character := MEMBERSHIP.duplicate()
	with_character["roster_character"] = "c1"
	var m2: OWJoin.JoinedMembership = (await _account(_answering(201, with_character)).accept_join("ow_j_abc")).value
	t.ok(m2 != null and m2.roster_character == "c1", "the roster Character's id")
	t.done()

# Kills: an empty code reaching the transport (keel's 404 would read as a bad code, not a missing one).
func test_accept_join_no_code_is_refused_nothing_sent(t) -> void:
	var fake = Fake.new()
	_refused(t, await _account(fake).accept_join(""), fake, "accept_join: a join code is required", "no code")
	t.done()

# Kills: a world key, a read key, a legacy key or no key reaching /account/join, which keel answers 401; the TypeScript
# SDK refuses a world key with a TypeError before sending.
func test_accept_join_any_key_but_an_account_token_is_refused_nothing_sent(t) -> void:
	for c in [["a write key", "ow_w_test", {}], ["a read key", "ow_r_test", {}], ["a legacy key", "0123456789", {}],
			["no key, world set", null, {"world": "w1"}]]:
		var fake = Fake.new()
		var r := await _account(fake, c[1], c[2]).accept_join("ow_j_abc")
		_refused(t, r, fake, "accept_join needs an account token (ow_a_)", c[0])
		if r.error != null:
			t.ok(r.error.message.contains("holds none" if c[1] == null else "holds a "), "%s: says what it holds" % c[0])
			t.ok(r.error.message.contains("OWJoin.redeem"), "%s: names the keyless call" % c[0])
	t.done()

# Kills: keel's refusals read as anything else (each leaves the code unspent). npm's two 409s, told apart by code
# without reading the message, and Unity's 404.
func test_accept_join_already_member_pin_required_and_not_found_are_told_apart(t) -> void:
	var member: OWApiError = (await _account(_answering(409, {"error": {"type": "conflict_error", "code": "already_member",
		"message": "Already a member."}})).accept_join("ow_j_abc")).error
	t.ok(member != null, "refused")
	if member != null:
		t.eq([member.is_already_member(), member.is_pin_required(), member.is_not_found()], [true, false, false], "a member")
	var pin: OWApiError = (await _account(_refusing(409, "pin_required", null)).accept_join("ow_j_abc")).error
	t.ok(pin != null, "refused")
	if pin != null:
		t.eq([pin.is_already_member(), pin.is_pin_required()], [false, true], "no PIN yet")
	var bad: OWApiError = (await _account(_answering(404, {"error": {"type": "not_found_error", "code": "not_found",
		"message": "Not a valid link."}})).accept_join("ow_j_abc")).error
	t.ok(bad != null, "refused")
	if bad != null:
		t.eq([bad.is_not_found(), bad.is_already_member()], [true, false], "a bad code")
	var other: OWApiError = (await _account(_refusing(422, "already_member", null)).accept_join("ow_j_abc")).error
	t.ok(other != null and not other.is_already_member(), "the code on another status is not it")
	t.done()
