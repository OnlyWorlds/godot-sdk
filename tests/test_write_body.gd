extends RefCounted
## A write's body the client cannot send as the caller gave it, through a fake transport (tests/fake_transport.gd):
## one that holds itself, one nested past 256 from the body's top, and one holding a NaN or an infinity, are refused
## with nothing sent, never sent cut or with a null in the number's place (the TypeScript SDK's 4.219.2 and 4.219.3). The
## TypeScript SDK's test (test/v2-client.test.mjs, 4.219.1: a body JSON cannot hold throws its own TypeError, and
## nothing is sent) ported in its cycle case; its BigInt case has no Godot value (an int is 64 bits and written
## exactly). Godot's own Dictionary.duplicate(true) stopped at the engine's recursion line and the cut copy was sent.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const ID := "11111111-2222-4333-8444-555555555555"

static func _client(fake) -> OWClient:
	return OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})

static func _refused(t, r: OWClient.Reply, fake, words: String, label: String) -> void:
	t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.contains(words),
		"%s: refused, '%s' (got %s)" % [label, words, r.error.message if r.error != null else "no error"])
	if r.error != null:
		t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so (%s)" % [label, r.error.message])
	t.eq(fake.calls.size(), 0, "%s: nothing sent" % label)

## A body whose deepest object sits at [param depth], the body itself at 1: [code]{x_deep: {d: {d: ...}}}[/code].
static func _nested(depth: int) -> Dictionary:
	var top := {"name": "K"}
	var at := top
	for i in depth - 1:
		var next := {}
		at["x_deep" if i == 0 else "d"] = next
		at = next
	return top

## How deep the text's objects and arrays open, its top value at 1.
static func _depth_of(text: String) -> int:
	var n := 0
	while OWJson.opens_past(text, n):
		n += 1
	return n

func test_a_body_that_holds_itself_is_refused_and_nothing_is_sent(t) -> void:
	var cyclic := {"name": "K"}
	cyclic["self"] = cyclic
	var calls := {
		"patch": func(c: OWClient): return await c.patch("character", ID, {"x_tool": cyclic}),
		"create": func(c: OWClient): return await c.create("character", {"name": "K", "x_tool": cyclic}),
		"upsert": func(c: OWClient): return await c.upsert("character", ID, {"name": "K", "x_tool": cyclic}),
		"bulk": func(c: OWClient): return await c.bulk([{"type": "character", "element": {"name": "A"}},
			{"type": "character", "element": {"name": "B", "x_tool": cyclic}}]),
		"propose": func(c: OWClient): return await c.propose("character", ID, {"x_tool": cyclic}, "a source"),
	}
	for name in calls:
		var fake = Fake.new()
		var r: OWClient.Reply = await calls[name].call(_client(fake))
		_refused(t, r, fake, "holds itself at x_tool.self", name)
	# a list inside itself, named by its index
	var fake = Fake.new()
	var looped := [1]
	looped.append(looped)
	_refused(t, await _client(fake).patch("character", ID, {"x_list": looped}), fake, "holds itself at x_list[1]", "a list")
	t.done()

func test_a_value_held_twice_is_no_cycle_and_is_sent_twice(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"%s\"}" % ID
	var shared := {"a": 1}
	var r: OWClient.Reply = await _client(fake).patch("character", ID, {"x_one": shared, "x_two": [shared, shared]})
	t.ok(r.ok, "sent: %s" % [r.error])
	t.eq(fake.calls.size(), 1, "one request")
	if fake.calls.size() == 1:
		t.eq(fake.last().body, "{\"x_one\":{\"a\":1},\"x_two\":[{\"a\":1},{\"a\":1}]}", "each place written")
	t.done()

## [param levels] - 1 arrays around 1: the object that holds it is [param levels] deep (the TypeScript SDK's nest()).
static func _nest(levels: int) -> Variant:
	var v: Variant = 1
	for i in range(1, levels):
		v = [v]
	return v

const TOO_DEEP := ("a request body is nested more than 256 deep (an object or list at the top is depth 1), past what "
	+ "onlyworlds.com reads. Nothing was sent.")

## The TypeScript SDK's 4.219.2 vector (test/v2-client.test.mjs, "a non-finite number anywhere in a body"): refused by
## name, with its place, nothing sent. Its patchWorld case goes through patch, whose body is the partial itself.
func test_a_non_finite_number_anywhere_in_a_body_is_refused_by_name_with_its_place(t) -> void:
	var calls := {
		"NaN at x_score": func(c: OWClient): return await c.patch("character", ID, {"x_score": NAN}),
		"Infinity at x_tool.scale[2]": func(c: OWClient): return await c.patch("character", ID, {"x_tool": {"scale": [1, 2, INF]}}),
		"-Infinity at items[1].element.x_weight": func(c: OWClient): return await c.bulk([
			{"type": "pin", "element": {"id": ID, "x": 1}}, {"type": "pin", "element": {"id": ID, "x_weight": -INF}}]),
		# beyond the TypeScript SDK's: a proposal's envelope, and a packed array written as a list
		"NaN at fields.x_score": func(c: OWClient): return await c.propose("character", ID, {"x_score": NAN}, "a source"),
		"NaN at x_v[1]": func(c: OWClient): return await c.patch("character", ID, {"x_v": PackedFloat64Array([1.0, NAN])}),
	}
	for want in calls:
		var fake = Fake.new()
		var r: OWClient.Reply = await calls[want].call(_client(fake))
		_refused(t, r, fake, ("a request body holds %s, which JSON cannot carry: send a finite number, or null to clear "
			+ "the field. Nothing was sent.") % want, want)
	t.done()

## The TypeScript SDK's 4.219.3 vector ("a body nested past 256 levels"): past 256 from the body's top, where keel stops
## reading a body, refused by name; 256 sent whole; a bulk element 200 deep, counted from the element as keel stores
## it, sent (the body 203 deep).
func test_a_body_past_256_deep_is_refused_and_256_is_sent_whole(t) -> void:
	var fake = Fake.new()
	_refused(t, await _client(fake).patch("character", ID, {"x_tool": _nest(257)}), fake, TOO_DEEP, "257 deep")
	# Far past the line, the same refusal. The TypeScript SDK's case is 200,000 deep; here the engine itself crashes freeing
	# a caller's Array that deep, whatever the client does, so the case is 10,000.
	var far = Fake.new()
	_refused(t, await _client(far).patch("character", ID, {"x_tool": _nest(10000)}), far, TOO_DEEP, "10,000 deep")
	var both = Fake.new()
	_refused(t, await _client(both).patch("character", ID, {"x_score": NAN, "x_tool": _nest(257)}), both, TOO_DEEP,
		"past the line and holding NaN: the depth is named")
	var sent = Fake.new()
	sent.body = "{\"id\":\"%s\"}" % ID
	var r: OWClient.Reply = await _client(sent).patch("character", ID, {"x_tool": _nest(256)})
	t.ok(r.ok, "256 deep: sent (%s)" % [r.error])
	t.eq(sent.calls.size(), 1, "256 deep: one request")
	if sent.calls.size() == 1:
		t.eq(_depth_of(sent.last().body), 256, "256 deep: sent whole, every level")
	t.done()

func test_a_bulk_element_200_deep_is_sent_and_the_envelope_counts(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"errors\":false,\"items\":[]}"
	var r: OWClient.Reply = await _client(fake).bulk([{"type": "character", "element": {"id": ID, "name": "K", "x_tool": _nest(200)}}])
	t.ok(r.ok, "an element 200 deep: sent (%s)" % [r.error])
	t.eq(fake.calls.size(), 1, "one request")
	if fake.calls.size() == 1:
		t.eq(_depth_of(fake.last().body), 203, "the element whole, at depth 4 of {items: [{element}]}")
	# an element 253 deep is a body 256 deep, sent; 254 is 257, refused
	r = await _client(fake).bulk([{"type": "character", "element": {"id": ID, "x_tool": _nest(253)}}])
	t.ok(r.ok, "an element 253 deep: sent (%s)" % [r.error])
	if fake.calls.size() == 2:
		t.eq(_depth_of(fake.last().body), 256, "253 deep: a body 256 deep")
	var deeper = Fake.new()
	_refused(t, await _client(deeper).bulk([{"type": "character", "element": {"id": ID, "x_tool": _nest(254)}}]), deeper,
		TOO_DEEP, "an element 254 deep")
	t.done()

func test_the_callers_body_is_not_changed(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"%s\"}" % ID
	var inner := {"b": null}
	var element := {"name": null, "created_at": "t0", "x_tool": inner}
	await _client(fake).patch("character", ID, element)
	t.eq(element, {"name": null, "created_at": "t0", "x_tool": {"b": null}}, "the caller's Dictionary as it was")
	t.ok(is_same(element["x_tool"], inner), "its inner Dictionary the same one")
	t.done()
