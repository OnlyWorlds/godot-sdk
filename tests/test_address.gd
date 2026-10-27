extends RefCounted
## OWAddress on the address profile's conformance fixture (schema-dist profiles/address.fixture.json, the pinned copy,
## unchanged since serial 77): every format case through element_address_from, every parse case through parse_link,
## each refusal by the reason the fixture names. Then what the fixture leaves open, as the npm and Python packages
## answer it: the writer's order, a moment of 3.0, an empty string, a key outside the shape.

const P = preload("res://tests/paths.gd")

const WORLD := "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e0f"
const ELEMENT := "019a1f3c-2b4e-7d10-8c3a-6f2e9b0d4a71"
const LENS := "019a2b7e-4c1d-7f20-9b3e-1a2c3d4e5f60"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(P.ADDRESS))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["address:" + c["name"], _case.bind(c)])
	return out

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var refuse = c.get("refuse")
	match c["kind"]:
		"format":
			var w := OWAddress.element_address_from(c["address"])
			if refuse != null:
				t.eq(w.reason, refuse, "refusal (wrote %s)" % (w.address if w.ok else "nothing"))
			else:
				t.eq(w.address, c["expect"], "written (refused as %s %s)" % [w.reason, w.message])
		"parse":
			var r := OWAddress.parse_link(c["text"])
			if refuse != null:
				t.ok(not r.ok, "refused (read %s)" % (JSON.stringify(r.to_dict()) if r.ok else ""))
				t.eq(r.reason, refuse, "refusal")
			else:
				t.ok(r.ok, "read (refused as %s)" % r.reason)
				t.eq(r.to_dict(), _reading(c["expect"]), "the reading")
		_:
			t.fail("a case of unknown kind %s" % c["kind"])
	t.done()

## A fixture reading with its moment as an int: Godot's JSON reads every number as a float.
func _reading(expect: Dictionary) -> Dictionary:
	var out := expect.duplicate()
	if out["moment"] != null:
		out["moment"] = int(out["moment"])
	return out

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(P.ADDRESS), manifest["profiles/address.fixture.json"], "the fixture's bytes are the dist's")
	var doc := _fixture()
	t.eq(doc["profile"], "address", "the profile")
	var cases: Array = doc["cases"]
	t.eq(cases.size(), 133, "133 cases")
	t.eq(cases.filter(func(c): return c["kind"] == "format").size(), 32, "format cases")
	t.eq(cases.filter(func(c): return c["kind"] == "parse").size(), 101, "parse cases")
	t.eq(cases.filter(func(c): return c.get("refuse") != null).size(), 70, "refusals: 16 format, 54 parse")
	t.done()

func test_the_type_words_and_refusals_are_the_fixtures(t) -> void:
	var types: Array = _fixture()["types"].duplicate()
	types.sort()
	var ours := Array(OWTypes.slugs())
	ours.sort()
	t.eq(ours, types, "the 22 type words")
	t.eq(OWAddress.REFUSALS, _fixture()["refusals"], "the refusals, in the order a reader checks them")
	t.done()

func test_every_reading_writes_back_canonical(t) -> void:
	var n := 0
	for c in _fixture()["cases"]:
		if c["kind"] != "parse" or c.get("expect") == null:
			continue
		var r := OWAddress.parse_link(c["text"])
		var w := r.to_address()
		if r.world_is_slug:
			t.eq(w.reason, "bad_world", "%s: a writer never writes a slug" % c["name"])
			continue
		t.ok(w.ok, "%s: writes back" % c["name"])
		if r.canonical:
			t.eq(w.address, c["text"], "%s: a canonical string is what the writer writes" % c["name"])
		var again := OWAddress.parse_link(w.address)
		t.ok(again.canonical, "%s: %s reads canonical" % [c["name"], w.address])
		t.eq(again.to_address().address, w.address, "%s: and writes the same" % c["name"])
		n += 1
	t.ok(n > 40, "readings written back: %d" % n)
	t.done()

func test_the_typed_writer_and_a_reading_of_a_world(t) -> void:
	t.eq(OWAddress.element_address(OWAddress.HUMAN, WORLD, "character", ELEMENT).address,
		"https://www.onlyworlds.com/w/%s/character/%s" % [WORLD, ELEMENT], "the human address")
	t.eq(OWAddress.element_address(OWAddress.TEXT, null, "object", ELEMENT, LENS, -7).address,
		"ow://object/%s@-7?lens=%s" % [ELEMENT, LENS], "in-world, a moment and a lens")
	t.eq(OWAddress.element_address(OWAddress.TEXT, WORLD.to_upper(), "location", ELEMENT.to_upper(), null, 2147483647).address,
		"ow://%s/location/%s@2147483647" % [WORLD, ELEMENT], "across worlds, written lowercase")
	t.eq(OWAddress.element_address(OWAddress.TEXT, WORLD).address, "ow://" + WORLD, "a world")
	t.eq(OWAddress.element_address(OWAddress.TEXT, WORLD, null, null, null, 2147483648).reason, "bad_moment", "past 32 bits")
	var world := OWAddress.parse_link("  ow://%s\t" % WORLD)
	t.ok(world.is_world(), "a world's own address")
	t.ok(not world.canonical, "untrimmed is not canonical")
	var el := OWAddress.parse_link("ow://object/" + ELEMENT)
	t.ok(el.ok and not el.is_world() and el.world == null, "an in-world element")
	t.eq(OWAddress.parse_link("ow://dragon/" + ELEMENT).reason, "unknown_type", "not a type word")
	t.eq(OWAddress.parse_link("\u001cow://" + WORLD).reason, "not_an_address", "U+001C is not White_Space")
	t.eq(OWAddress.parse_link("ow://marKer/" + ELEMENT).reason, "unknown_type", "the Kelvin sign is not a k")
	t.done()

# -- what the fixture leaves open -------------------------------------------------------------------------------------

func _refusal(json: String) -> String:
	var w := OWAddress.element_address_from(JSON.parse_string(json))
	return "wrote " + w.address if w.ok else w.reason

func test_the_writer_refuses_a_form_first_then_segments_then_no_world(t) -> void:
	# A type without an id and no world: segments before no_world.
	t.eq(_refusal('{"form": "human", "type": "pin"}'), "segments", "a type, no id, no world")
	t.eq(_refusal('{"form": "human", "id": "%s"}' % ELEMENT), "segments", "an id, no type, no world")
	t.eq(OWAddress.element_address(OWAddress.HUMAN, null, "character").reason, "segments", "typed: a type, no id")
	# A form it does not know before either.
	t.eq(_refusal('{"form": "url", "type": "pin"}'), "bad_form", "an unknown form and a type alone")
	t.eq(_refusal('{"type": "pin"}'), "bad_form", "no form")
	t.eq(_refusal('{"form": 1, "world": "%s"}' % WORLD), "bad_form", "a form that is not a string")
	# With a whole triple, or nothing, the missing world is what refuses.
	t.eq(_refusal('{"form": "human", "type": "pin", "id": "%s"}' % ELEMENT), "no_world", "human, no world")
	t.eq(_refusal('{"form": "text"}'), "no_world", "text, nothing")
	# Then the reader's order: the world before the type, the type before the id.
	t.eq(_refusal('{"form": "text", "world": "hyperion", "type": "dragon", "id": 7}'), "bad_world", "a slug never written")
	t.eq(_refusal('{"form": "text", "world": "%s", "type": "dragon", "id": 7}' % WORLD), "unknown_type", "type before id")
	t.done()

func test_a_moment_with_a_zero_fraction_is_a_whole_step(t) -> void:
	t.eq(_refusal('{"form": "text", "type": "character", "id": "%s", "moment": 3.0}' % ELEMENT).trim_prefix("wrote "),
		"ow://character/%s@3" % ELEMENT, "3.0 is @3")
	t.eq(OWAddress.element_address(OWAddress.TEXT, null, "character", ELEMENT, null, 3.0).address,
		"ow://character/%s@3" % ELEMENT, "typed: 3.0 is @3")
	t.eq(_refusal('{"form": "text", "world": "%s", "moment": -0.0}' % WORLD).trim_prefix("wrote "), "ow://%s@0" % WORLD, "-0.0 is @0")
	t.eq(_refusal('{"form": "text", "world": "%s", "moment": -2147483648.0}' % WORLD).trim_prefix("wrote "),
		"ow://%s@-2147483648" % WORLD, "the 32-bit floor")
	for m in ["1.5", "2147483648.0", "1e20", "1000000000000000000000000000000", "\"3\"", "true"]:
		t.eq(_refusal('{"form": "text", "world": "%s", "moment": %s}' % [WORLD, m]), "bad_moment", "moment %s" % m)
	# A refusal before the moment still names itself, whatever the moment holds.
	t.eq(_refusal('{"form": "human", "moment": 1000000000000000000000000000000}'), "no_world", "no_world before the moment")
	t.done()

func test_an_empty_string_is_present_only_null_or_a_missing_key_is_absent(t) -> void:
	t.eq(_refusal('{"form": "text", "world": "", "type": "character", "id": "%s"}' % ELEMENT), "bad_world", "world empty")
	t.eq(_refusal('{"form": "human", "world": ""}'), "bad_world", "human, world empty")
	t.eq(_refusal('{"form": "text", "world": "%s", "lens": ""}' % WORLD), "bad_lens", "lens empty")
	t.eq(_refusal('{"form": "text", "world": "%s", "type": "", "id": ""}' % WORLD), "unknown_type", "type and id empty")
	t.eq(_refusal('{"form": "text", "type": "", "id": "%s"}' % ELEMENT), "unknown_type", "type empty")
	t.eq(_refusal('{"form": "text", "type": "character", "id": ""}'), "bad_id", "id empty")
	t.eq(_refusal('{"form": "text", "world": "%s", "type": ""}' % WORLD), "segments", "a type with no id, even empty")
	# null and a missing key are the same absence.
	t.eq(_refusal('{"form": "text", "world": "%s", "type": null, "id": null, "lens": null, "moment": null}' % WORLD),
		"wrote ow://" + WORLD, "every other part null")
	t.done()

func test_a_key_the_shape_does_not_hold_is_an_error_not_a_refusal(t) -> void:
	for key in ["wrold", "Type", "ID", "x"]:
		var w := OWAddress.element_address_from(JSON.parse_string('{"form": "text", "world": "%s", "%s": null}' % [WORLD, key]))
		t.ok(not w.ok, "%s: not written" % key)
		t.eq(w.reason, "", "%s: no refusal" % key)
		t.ok(w.message.contains("'%s'" % key), "%s: the message names it (%s)" % [key, w.message])
	# A reading's two flags are keys of the shape, and ignored.
	t.eq(_refusal('{"form": "text", "world": "%s", "world_is_slug": true, "canonical": "no"}' % WORLD),
		"wrote ow://" + WORLD, "world_is_slug and canonical ignored")
	t.done()
