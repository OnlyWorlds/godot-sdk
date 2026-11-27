extends RefCounted
## A write's body the client cannot send as the caller gave it, through a fake transport (tests/fake_transport.gd):
## one that holds itself, and one nested past OWJson.MAX_DEPTH, are refused with nothing sent, never sent cut. The
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

func test_a_body_200_deep_is_sent_whole_and_201_deep_is_refused(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"%s\"}" % ID
	var r: OWClient.Reply = await _client(fake).patch("character", ID, _nested(OWJson.MAX_DEPTH))
	t.ok(r.ok, "200 deep: sent (%s)" % [r.error])
	t.eq(fake.calls.size(), 1, "200 deep: one request")
	if fake.calls.size() == 1:
		t.eq(_depth_of(fake.last().body), 200, "200 deep: sent whole, every level")
	var deeper = Fake.new()
	_refused(t, await _client(deeper).patch("character", ID, _nested(OWJson.MAX_DEPTH + 1)), deeper,
		"nested more than 200 deep", "201 deep")
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
