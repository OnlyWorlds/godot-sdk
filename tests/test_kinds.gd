extends RefCounted
## A value the server would store as another is refused before sending, through a fake transport
## (tests/fake_transport.gd). The TypeScript SDK's test (test/v2-client.test.mjs, 4.220.0: "a value keel would store as
## another is refused before sending, as Python check_kinds refuses it") ported with its let-through half, and cases of
## our own: the pin's element_type is text, a NaN in an integer field is the kind's refusal (named null, as
## JSON.stringify names it), a typed element and a parsed 2.0 go.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const ID := "11111111-2222-4333-8444-555555555555"

static func _client(fake) -> OWClient:
	return OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})

func test_a_value_keel_would_store_as_another_is_refused_before_sending(t) -> void:
	# Each one keel takes with a 200 and stores as something else (measured on production 2026-11-28).
	var calls := {
		"create: character.height is an integer field; 2.5 would be stored as another value":
			func(c: OWClient): return await c.create("character", {"name": "K", "height": 2.5}),
		"upsert: character.height is an integer field; \"7\" would be stored as another value":
			func(c: OWClient): return await c.upsert("character", ID, {"name": "K", "height": "7"}),
		"patch: character.height is an integer field; true would be stored":
			func(c: OWClient): return await c.patch("character", ID, {"height": true}),
		"patch: character.supertype is a text field; [\"a\",\"b\"] is not a string":
			func(c: OWClient): return await c.patch("character", ID, {"supertype": ["a", "b"]}),
		"bulk: items[1]: character.supertype is a text field; 12 is not a string":
			func(c: OWClient): return await c.bulk([{"type": "character", "element": {"name": "K"}},
				{"type": "character", "element": {"name": "L", "supertype": 12}}]),
		"propose: character.height is an integer field; 1.5 would be stored":
			func(c: OWClient): return await c.propose("character", ID, {"height": 1.5}, "a source"),
		# beyond the TypeScript SDK's
		"patch: pin.element_type is a text field; 12 is not a string":
			func(c: OWClient): return await c.patch("pin", ID, {"element_type": 12}),
		"patch: character.height is an integer field; null would be stored as another value":
			func(c: OWClient): return await c.patch("character", ID, {"height": NAN}),
		"patch: character.supertype is a text field; \"(1, 2)\" is not a string":
			func(c: OWClient): return await c.patch("character", ID, {"supertype": Vector2i(1, 2)}),
	}
	for want in calls:
		var fake = Fake.new()
		var r: OWClient.Reply = await calls[want].call(_client(fake))
		t.ok(r.error != null and r.error.kind == OWApiError.REFUSED and r.error.message.begins_with(want),
			"refused, '%s' (got %s)" % [want, r.error.message if r.error != null else "no error"])
		if r.error != null:
			t.ok(r.error.message.ends_with("Nothing was sent."), "%s: the refusal says so" % want)
		t.eq(fake.calls.size(), 0, "%s: nothing sent" % want)
	t.done()

func test_what_it_lets_through(t) -> void:
	var fake = Fake.new()
	fake.body = "{\"id\":\"%s\"}" % ID
	var c := _client(fake)
	# The TypeScript SDK's: a whole number (2.0 is one), null, a string in a text field, an extension of any kind, a
	# link field, and a type outside the schema.
	var r: OWClient.Reply = await c.patch("character", ID, {"height": 2.0, "weight": null, "supertype": "hero",
		"x_tool": [1.5, true], "species": []})
	t.ok(r.ok, "the let-through body: sent (%s)" % [r.error])
	r = await c.patch("notatype", ID, {"height": 2.5})
	t.ok(r.ok, "a type outside the schema: sent (%s)" % [r.error])
	t.eq(fake.calls.size(), 2, "two requests")
	# Ours: a typed element, a StringName in a text field, the generic link's type key as text, an int.
	var ch := OWCharacter.new()
	ch.name = "K"
	ch.height = 7
	r = await c.patch("character", ID, ch)
	t.ok(r.ok, "a typed element: sent (%s)" % [r.error])
	r = await c.patch("character", ID, {"supertype": &"hero", "height": 3})
	t.ok(r.ok, "a StringName and an int: sent (%s)" % [r.error])
	r = await c.patch("pin", ID, {"element_type": "character", "x": 3.0})
	t.ok(r.ok, "the pin's type key as text, a whole float: sent (%s)" % [r.error])
	t.eq(fake.calls.size(), 5, "five requests")
	t.done()
