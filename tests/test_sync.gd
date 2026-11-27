extends RefCounted
## OWSync through a fake transport (tests/fake_transport.gd): no test touches the network. Ported test by test from the
## Unity SDK's OWSyncTests, each named as it is there. The shapes scripted below are keel's (core/changes.py
## compute_head, compute_changes): an owner's tip cursor is the bare change_seq as a number; a guest's is
## "seq:<max uuid>:epoch", with the epoch beside it; a page's cursor is "seq:id" (a guest's "seq:id:epoch"). The keys
## they use are held to keel's API document by test_client_wire.gd. The feed's rules: keel's changes page,
## https://onlyworlds.github.io/docs/development/api/changes

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const MAX_UUID := "ffffffff-ffff-ffff-ffff-ffffffffffff"
const ID_A := "069620b9-0794-708d-8000-00000000000a"
const ID_B := "069620b9-0794-708d-8000-00000000000b"
const EMPTY_PAGE := "{\"data\":[],\"has_more\":false,\"next_cursor\":null}"

func _client(fake) -> OWClient:
	return OWClient.new({"api_key": "ow_w_test", "api_pin": "1234", "base_url": BASE, "transport": fake})

static func _cache() -> OWWorldCache:
	return OWWorldCache.new("w-1", "Test World")

static func _head(head: int) -> String:
	return "{\"cursor\":%d,\"head\":%d,\"changes\":[],\"has_more\":false,\"epoch\":null}" % [head, head]

static func _guest_tip(head: int, epoch: int) -> String:
	return "%d:%s:%d" % [head, MAX_UUID, epoch]

static func _guest_head(head: int, epoch: int) -> String:
	return "{\"cursor\":\"%s\",\"head\":%d,\"changes\":[],\"has_more\":false,\"epoch\":%d}" % [_guest_tip(head, epoch), head, epoch]

static func _upsert(id: String, seq: int, name: String) -> String:
	return ("{\"op\":\"upsert\",\"type\":\"character\",\"id\":\"%s\",\"change_seq\":%d,\"updated_at\":\"2026-10-16T00:00:00Z\","
		+ "\"element\":{\"id\":\"%s\",\"name\":\"%s\",\"level\":3}}") % [id, seq, id, name]

static func _enqueue_baseline(fake, head: String) -> void:
	fake.then(200, head)
	for i in OWTypes.slugs().size():
		fake.then(200, EMPTY_PAGE)

## The since parameter of a request, decoded, or null.
static func _since(call: OWTransport.Request) -> Variant:
	var url: String = call.url
	if not url.contains("?"):
		return null
	for pair in url.get_slice("?", 1).split("&"):
		if pair.begins_with("since="):
			return pair.substr(6).uri_decode()
	return null

static func _result(t, r: OWClient.Reply) -> OWSync.Result:
	t.ok(r.ok, "the sync answered: %s" % [str(r.error) if r.error else ""])
	return r.value if r.ok else OWSync.Result.new()

# -- Baseline -----------------------------------------------------------------------------------------------------------

func test_baseline_reads_the_tip_before_fetching(t) -> void:
	# Order matters: taking the tip AFTER the walk means any change landing during it sits silently below the recorded
	# cursor and never syncs again.
	var fake = Fake.new()
	var cache := _cache()
	_enqueue_baseline(fake, _head(500))
	var result := _result(t, await OWSync.baseline(_client(fake), cache))
	t.ok(fake.calls[0].url.contains("head=true"), "the tip check must be the FIRST request")
	t.eq(result.cursor, 500, "")
	t.eq(cache.cursor, 500, "")
	t.done()

func test_baseline_walks_every_element_type(t) -> void:
	var fake = Fake.new()
	_enqueue_baseline(fake, _head(1))
	var walked := []
	await OWSync.baseline(_client(fake), _cache(), func(type, n): walked.append([type, n]))
	t.eq(fake.calls.size(), 23, "1 tip check + one list call per type")
	t.eq(OWTypes.slugs().size(), 22, "the standard has 22 element types")
	t.eq(walked.size(), 22, "on_type once per type")
	t.done()

func test_baseline_stores_elements_and_clears_first(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "stale", "name": "Old"}))
	fake.then(200, _head(10))
	for type in OWTypes.slugs():
		fake.then(200, "{\"data\":[{\"id\":\"c1\",\"name\":\"Fresh\"}],\"has_more\":false}" if type == "character" else EMPTY_PAGE)
	var result := _result(t, await OWSync.baseline(_client(fake), cache))
	t.eq(result.fetched, 1, "")
	t.ok(result.was_rebaselined, "")
	t.ok(not cache.has("stale"), "a baseline replaces; it does not merge")
	t.ok(cache.get_element("c1") is OWCharacter, "typed")
	t.eq(cache.get_element("c1").name, "Fresh", "")
	t.done()

func test_baseline_stores_the_tips_own_cursor_and_epoch(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	_enqueue_baseline(fake, _guest_head(40, 3))
	await OWSync.baseline(_client(fake), cache)
	t.eq(cache.cursor, 40, "")
	t.eq(cache.cursor_token, _guest_tip(40, 3), "the next sync resumes from the server's cursor; a guest's carries its epoch")
	t.eq(cache.epoch, 3, "")
	t.done()

# -- Incremental --------------------------------------------------------------------------------------------------------

func test_incremental_with_no_cursor_falls_back_to_baseline(t) -> void:
	var fake = Fake.new()
	_enqueue_baseline(fake, _head(5))
	var result := _result(t, await OWSync.incremental(_client(fake), _cache()))
	t.ok(result.was_rebaselined, "nothing cached yet means there is nothing to increment from")
	t.done()

func test_incremental_at_the_tip_does_nothing(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(100))
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(not result.changed_anything, "")
	t.eq(fake.calls.size(), 1, "a no-op sync costs exactly one tip check")
	t.done()

func test_incremental_applies_upserts_from_the_element_they_carry(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(101))
	fake.then(200, "{\"cursor\":\"101:%s\",\"has_more\":false,\"head\":101,\"epoch\":null,\"changes\":[%s]}" % [ID_A, _upsert(ID_A, 101, "Updated")])
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.eq(result.fetched, 1, "")
	t.eq(cache.get_element(ID_A).name, "Updated", "")
	t.eq(cache.get_element(ID_A).level, 3, "")
	t.eq(fake.calls.size(), 2, "an upsert carries the element whole: the tip and one page, no GET per element")
	t.done()

func test_incremental_fetches_the_body_only_when_an_op_has_none(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(101))
	fake.then(200, "{\"cursor\":\"101:%s\",\"has_more\":false,\"head\":101,\"epoch\":null,\"changes\":[{\"op\":\"upsert\",\"type\":\"character\",\"id\":\"%s\",\"change_seq\":101}]}" % [ID_A, ID_A])
	fake.then(200, "{\"id\":\"%s\",\"name\":\"Fetched\"}" % ID_A)
	await OWSync.incremental(_client(fake), cache)
	t.eq(cache.get_element(ID_A).name if cache.has(ID_A) else "", "Fetched", "")
	t.ok(fake.last().url.ends_with("/character/%s/" % ID_A), "the GET by id: %s" % fake.last().url)
	t.done()

func test_incremental_resumes_from_the_stored_cursor_not_from_the_seq(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	var token := "100:%s:3" % ID_A
	cache.set_cursor(100, token, 3, "t")
	fake.then(200, _guest_head(101, 3))
	fake.then(200, "{\"cursor\":\"101:%s:3\",\"has_more\":false,\"head\":101,\"epoch\":3,\"changes\":[%s]}" % [ID_B, _upsert(ID_B, 101, "Seen")])
	await OWSync.incremental(_client(fake), cache)
	t.eq(_since(fake.calls[1]), token, "the cursor goes back as the server sent it; a bare 100 from a guest is a 409")
	t.eq(cache.cursor_token, "101:%s:3" % ID_B, "the last page's cursor is the next resume point")
	t.eq(cache.cursor, 101, "")
	t.done()

func test_incremental_a_cache_with_no_token_resumes_from_its_bare_seq(t) -> void:
	# A cache saved with only its seq (a file written by hand, or before the token was kept) resumes exactly as it did.
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(101))
	fake.then(200, "{\"cursor\":\"101:%s\",\"has_more\":false,\"head\":101,\"epoch\":null,\"changes\":[%s]}" % [ID_A, _upsert(ID_A, 101, "A")])
	await OWSync.incremental(_client(fake), cache)
	t.eq(_since(fake.calls[1]), "100", "")
	t.eq(cache.cursor_token, "101:%s" % ID_A, "")
	t.done()

func test_incremental_after_baselining_an_empty_world_is_a_no_op(t) -> void:
	# Head 0 used to read as "no cursor", so an empty world re-baselined on every sync.
	var fake = Fake.new()
	var cache := _cache()
	_enqueue_baseline(fake, _head(0))
	await OWSync.baseline(_client(fake), cache)
	fake.calls.clear()
	fake.then(200, _head(0))
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(not result.changed_anything, "")
	t.eq(fake.calls.size(), 1, "")
	t.done()

# -- The resync rule ----------------------------------------------------------------------------------------------------
#
# What a reset keeps (keel's changes page, "What a reset keeps"): a 409 walks the world again from the start; what the
# copy holds that the new walk does not name is KEPT on role or on no reason (sharing is forward-only: out of view, not
# gone) and DROPPED on view. A reset never empties a copy on its own.

static func _resync(reason: Variant) -> String:
	return ("{\"error\":{\"type\":\"invalid_request\",\"code\":\"resync_required\",\"param\":\"since\",\"message\":\"m\""
		+ ("" if reason == null else ",\"reason\":\"%s\"" % reason) + "}}")

## A tip, then a 409 on the walk from the cache's cursor, then a baseline naming only [param named].
static func _enqueue_reset(fake, tip: String, resync: String, named: String) -> void:
	fake.then(200, tip)
	fake.then(409, resync)
	fake.then(200, tip)
	for type in OWTypes.slugs():
		fake.then(200, "{\"data\":[{\"id\":\"%s\",\"name\":\"Fresh\"}],\"has_more\":false}" % named if type == "character" else EMPTY_PAGE)

## A copy holding two Characters: one the next walk names again (a), one it no longer names (b).
static func _cache_two(cursor: int, token: String, epoch: Variant) -> OWWorldCache:
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "a", "name": "Old A"}))
	cache.upsert(OWTypes.make("character", {"id": "b", "name": "Out of view"}))
	cache.set_cursor(cursor, token, epoch, "t")
	return cache

func test_incremental_a409_for_the_view_drops_what_the_new_walk_does_not_name(t) -> void:
	var fake = Fake.new()
	var cache := _cache_two(100, _guest_tip(100, 2), 2)
	_enqueue_reset(fake, _guest_head(101, 3), _resync("view"), "a")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(result.was_rebaselined, "")
	t.eq(result.resync_reason, "view", "")
	t.eq(result.kept, 0, "")
	t.ok(cache.has("a"), "")
	t.eq(cache.get_element("a").name, "Fresh", "the walk's body replaces the old one")
	t.ok(not cache.has("b"), "view: something left this key's view, so it goes")
	t.eq(cache.cursor_token, _guest_tip(101, 3), "")
	t.eq(cache.epoch, 3, "")
	t.done()

func test_incremental_a409_for_the_role_keeps_what_the_new_walk_does_not_name(t) -> void:
	var fake = Fake.new()
	var cache := _cache_two(100, _guest_tip(100, 2), 2)
	_enqueue_reset(fake, _guest_head(101, 3), _resync("role"), "a")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(result.was_rebaselined, "")
	t.eq(result.resync_reason, "role", "")
	t.eq(result.kept, 1, "")
	t.eq(cache.get_element("a").name, "Fresh", "what the walk names, it refreshes")
	t.ok(cache.has("b"), "role: out of this key's view now, not gone; sharing is forward-only")
	t.eq(cache.get_element("b").name if cache.has("b") else "", "Out of view", "")
	t.eq(cache.cursor_token, _guest_tip(101, 3), "the cursor is the new walk's")
	t.eq(cache.epoch, 3, "")
	t.done()

func test_incremental_a409_with_no_reason_is_kept_like_role(t) -> void:
	# A guest key with a cache that holds only its seq: keel answers its bare since=100 with 409 resync_required
	# (core/changes.py parse_cursor). A server older than 2026-10-20 sends no reason.
	var fake = Fake.new()
	var cache := _cache_two(100, "", null)
	_enqueue_reset(fake, _guest_head(101, 2), _resync(null), "a")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(result.was_rebaselined, "")
	t.ok(result.rebaseline_reason.contains("resync_required"), result.rebaseline_reason)
	t.eq(result.resync_reason, null, "")
	t.eq(result.kept, 1, "")
	t.ok(cache.has("b"), "no reason: kept, as for role; a reset never empties a copy")
	t.eq(cache.cursor_token, _guest_tip(101, 2), "")
	t.eq(cache.epoch, 2, "")
	t.done()

func test_incremental_at_the_head_but_a_moved_epoch_is_not_current(t) -> void:
	# A Character given or taken moves a guest's epoch with head unmoved.
	var fake = Fake.new()
	var cache := _cache_two(100, _guest_tip(100, 3), 3)
	_enqueue_reset(fake, _guest_head(100, 4), _resync("view"), "a")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(result.was_rebaselined, "same head, another epoch: the walk answers 409 and the cache rebuilds")
	t.eq(cache.epoch, 4, "")
	t.ok(not cache.has("b"), "")
	t.done()

func test_incremental_a_reset_whose_walk_fails_leaves_the_copy_and_its_cursor_as_they_were(t) -> void:
	# A tool never empties a copy on its own: a reset that cannot finish its walk changes nothing.
	var fake = Fake.new()
	var cache := _cache_two(100, _guest_tip(100, 2), 2)
	fake.then(200, _guest_head(101, 3))
	fake.then(409, _resync("view"))
	fake.then(200, _guest_head(101, 3))
	fake.then(503, "{\"error\":{\"type\":\"api_error\",\"code\":\"server_busy\",\"message\":\"busy\"}}")
	var r: OWClient.Reply = await OWSync.incremental(_client(fake), cache)
	t.ok(r.error != null and r.error.status == 503, "the walk's failure is the answer")
	t.eq(cache.count(), 2, "")
	t.eq(cache.get_element("a").name, "Old A", "")
	t.ok(cache.has("b"), "")
	t.eq(cache.cursor, 100, "")
	t.eq(cache.cursor_token, _guest_tip(100, 2), "")
	t.eq(cache.epoch, 2, "")
	t.done()

func test_incremental_a_delete_row_for_a_hide_is_dropped(t) -> void:
	# A contributor learns of a hide from a delete op with reason hidden: dropped, as for view.
	var fake = Fake.new()
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "c1", "name": "Hidden now"}))
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(102))
	fake.then(200, "{\"cursor\":\"c-1\",\"has_more\":false,\"head\":102,\"changes\":[{\"op\":\"delete\",\"type\":\"character\",\"id\":\"c1\",\"change_seq\":102,\"reason\":\"hidden\"}]}")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.eq(result.removed, 1, "")
	t.ok(not cache.has("c1"), "")
	t.done()

func test_incremental_applies_deletes(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "c1", "name": "Doomed"}))
	cache.set_cursor(100, "", null, "t")
	fake.then(200, _head(102))
	fake.then(200, "{\"cursor\":\"c-1\",\"has_more\":false,\"head\":102,\"changes\":[{\"op\":\"delete\",\"type\":\"character\",\"id\":\"c1\",\"change_seq\":102}]}")
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.eq(result.removed, 1, "")
	t.ok(not cache.has("c1"), "")
	t.done()

# -- Paging the changes feed --------------------------------------------------------------------------------------------

func test_incremental_does_not_claim_the_tip_when_the_feed_breaks_early(t) -> void:
	# A server that says "more changes exist" but hands back no cursor to reach them. Breaking is right, but changes
	# below the tip were never applied: recording the tip anyway would lose them silently, with a cache that looks
	# current.
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(10, "", null, "t")
	fake.then(200, _head(900))
	fake.then(200, "{\"changes\":[%s],\"has_more\":true,\"cursor\":\"11:%s\",\"head\":900,\"epoch\":null}" % [_upsert(ID_A, 11, "One"), ID_A])
	fake.then(200, "{\"changes\":[%s],\"has_more\":true,\"cursor\":null,\"head\":900,\"epoch\":null}" % _upsert(ID_B, 12, "Two"))
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.eq(result.fetched, 2, "")
	t.eq(cache.cursor_token, "11:%s" % ID_A, "the next sync resumes from the last cursor the server gave")
	t.eq(cache.cursor, 10, "the seq stays put: 12 is no claim, and the tip would lose every change between 12 and 900")
	t.done()

func test_incremental_walks_every_page_and_takes_the_tip_when_it_finishes(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(10, "", null, "t")
	fake.then(200, _head(30))
	fake.then(200, "{\"changes\":[%s],\"has_more\":true,\"cursor\":\"11:%s\",\"head\":30,\"epoch\":null}" % [_upsert(ID_A, 11, "One"), ID_A])
	fake.then(200, "{\"changes\":[%s],\"has_more\":false,\"cursor\":\"12:%s\",\"head\":30,\"epoch\":null}" % [_upsert(ID_B, 12, "Two"), ID_B])
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.eq(result.fetched, 2, "both pages must be applied")
	t.ok(cache.has(ID_A), "")
	t.ok(cache.has(ID_B), "")
	t.eq(_since(fake.calls[2]), "11:%s" % ID_A, "page two starts at page one's cursor, as is")
	t.eq(cache.cursor, 30, "having reached the end of the feed, the tip is the correct cursor")
	t.eq(cache.cursor_token, "12:%s" % ID_B, "")
	t.done()

# -- The rewind rule ----------------------------------------------------------------------------------------------------

func test_incremental_rebaselines_when_cursor_is_ahead_of_head_and_keeps_what_the_walk_does_not_name(t) -> void:
	# A cursor ahead of head means the server was restored from a backup: the world is walked again, and what the copy
	# holds that the walk does not name is kept (a reset never empties a copy).
	var fake = Fake.new()
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "stale", "name": "Old"}))
	cache.set_cursor(9999, "", null, "t")
	fake.then(200, _head(100))   # the tip check: head is BEHIND our cursor
	_enqueue_baseline(fake, _head(100))
	var result := _result(t, await OWSync.incremental(_client(fake), cache))
	t.ok(result.was_rebaselined, "")
	t.eq(cache.cursor, 100, "the cursor must come down to the server's truth")
	t.ok(cache.has("stale"), "a restore rewinds the server, not what this copy read")
	t.eq(result.kept, 1, "")
	t.eq(result.resync_reason, null, "no 409 was involved")
	t.ok(result.rebaseline_reason.contains("restored from a backup"), result.rebaseline_reason)
	t.ok(result.rebaseline_reason.contains("9999"), "the cursor rewound FROM")
	t.ok(result.rebaseline_reason.contains("head 100"), "the head rewound TO")
	t.done()

# -- Frozen snapshots ---------------------------------------------------------------------------------------------------

func test_sync_refuses_a_read_only_cache(t) -> void:
	var fake = Fake.new()
	var snapshot := OWWorldCache.new("w-1", "Chapter 1", true)
	var r: OWClient.Reply = await OWSync.incremental(_client(fake), snapshot)
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED, "refused")
	t.ok(r.error != null and r.error.message.contains("read-only"), "")
	t.eq(fake.calls.size(), 0, "it must refuse before touching the network")
	var b: OWClient.Reply = await OWSync.baseline(_client(fake), snapshot)
	t.ok(b.error != null and b.error.kind == OWApiError.REFUSED, "a baseline too")
	t.eq(fake.calls.size(), 0, "")
	t.done()

# -- Cheap tip check ----------------------------------------------------------------------------------------------------

func test_has_changes_compares_head_to_cursor(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "", null, "t")
	var c := _client(fake)
	fake.then(200, _head(100))
	t.eq((await OWSync.has_changes(c, cache)).value, false, "")
	fake.then(200, _head(101))
	t.eq((await OWSync.has_changes(c, cache)).value, true, "")
	t.done()

func test_has_changes_sees_a_guests_moved_epoch(t) -> void:
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, _guest_tip(100, 3), 3, "t")
	var c := _client(fake)
	fake.then(200, _guest_head(100, 3))
	t.eq((await OWSync.has_changes(c, cache)).value, false, "")
	fake.then(200, _guest_head(100, 4))
	t.eq((await OWSync.has_changes(c, cache)).value, true, "head unmoved, view changed: a sync is due")
	t.done()

# -- Godot's own --------------------------------------------------------------------------------------------------------

func test_incremental_a_bodiless_upsert_whose_get_fails_answers_that_error_and_leaves_the_cursor(t) -> void:
	# No Unity test holds this: the feed names an upsert with no body, and the GET for it fails. The sync answers that
	# error and claims nothing, so the next sync replays from where this one began.
	var fake = Fake.new()
	var cache := _cache()
	cache.set_cursor(100, "100:x", null, "t")
	fake.then(200, _head(102))
	fake.then(200, "{\"cursor\":\"102:%s\",\"has_more\":false,\"head\":102,\"epoch\":null,\"changes\":[{\"op\":\"upsert\",\"type\":\"character\",\"id\":\"%s\",\"change_seq\":102}]}" % [ID_A, ID_A])
	fake.then(404, "{\"error\":{\"type\":\"invalid_request\",\"code\":\"not_found\",\"message\":\"No such character.\",\"param\":\"id\"}}")
	var r: OWClient.Reply = await OWSync.incremental(_client(fake), cache)
	t.ok(r.error != null and r.error.is_not_found(), "the GET's error is the answer")
	t.eq(cache.cursor, 100, "")
	t.eq(cache.cursor_token, "100:x", "")
	t.ok(not cache.has(ID_A), "")
	t.done()
