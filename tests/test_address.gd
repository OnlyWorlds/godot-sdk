extends RefCounted
## OWAddress on the address profile's conformance fixture (schema-dist profiles/address.fixture.json, the pinned copy
## at dist.128): every format case through element_address_from, every parse case through parse_link, every prose case
## through read_link_at (serial 123), each refusal by the reason the fixture names. Then what the fixture leaves open, as the npm and Python packages
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
	for c in _start_cases():
		out.append(["start:" + c[0], _start_case.bind(c)])
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
		"prose":
			# read_link_at finds the address that starts at the case's index: the slice it covers, and the
			# whole-string parser's reading of that slice; or nothing, where the fixture finds nothing. A Godot
			# String counts code points, as index does: a case's index_utf16 (serial 127) is for UTF-16 readers.
			var want: Dictionary = c["expect"]
			var text: String = c["text"]
			var at := int(c["index"])
			var found := OWAddress.read_link_at(text, at)
			if want["address"] == null:
				t.ok(found == null, "no address (found %s)" % (text.substr(at, found.end - at) if found != null else ""))
				t.ok(want["reading"] == null, "no address, no reading")
			else:
				var address: String = want["address"]
				t.ok(found != null, "found an address at %d (the fixture finds %s)" % [at, address])
				if found != null:
					t.eq(found.end, at + address.length(), "the end")
					t.eq(text.substr(at, found.end - at), address, "the slice at the index")
					t.eq(found.reading.to_dict(), _reading(want["reading"]), "its reading")
		"prose-all":
			# find_links finds every address in the text, in order; found is each one's slice of the text, never an
			# index, so it reads the same in every language (serial 128). Each reading is the parser's of its slice.
			var text: String = c["text"]
			var all := OWAddress.find_links(text)
			t.eq(all.map(func(f): return text.substr(f.start, f.end - f.start)), c["found"], "the addresses found, in order")
			for f in all:
				t.eq(f.reading.to_dict(), OWAddress.parse_link(text.substr(f.start, f.end - f.start)).to_dict(), "the reading at %d" % f.start)
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
	t.eq(cases.size(), 230, "230 cases")
	t.eq(cases.filter(func(c): return c["kind"] == "format").size(), 36, "format cases")
	t.eq(cases.filter(func(c): return c["kind"] == "parse").size(), 109, "parse cases")
	t.eq(cases.filter(func(c): return c["kind"] == "prose").size(), 83, "prose cases (57 at dist.123, four more at dist.126, fifteen at dist.127, one at dist.146, six at dist.147)")
	t.eq(cases.filter(func(c): return c["kind"] == "prose-all").size(), 2, "prose-all cases (dist.128)")
	t.eq(cases.filter(func(c): return c.get("refuse") != null).size(), 80, "refusals: 20 format, 60 parse")
	t.done()

## index counts code points, as a Godot String does, so the prose loop reads it; index_utf16 (serial 127) is the same
## place in UTF-16 units, given only where the two differ: the text before the index holds a letter above U+FFFF.
func test_the_prose_index_is_in_code_points_and_index_utf16_only_where_the_units_differ(t) -> void:
	var differ := []
	for c in _fixture()["cases"].filter(func(x): return x["kind"] == "prose"):
		var before: String = c["text"].substr(0, int(c["index"]))
		var units := 0
		for i in before.length():
			units += 2 if before.unicode_at(i) > 0xFFFF else 1
		if c.has("index_utf16"):
			t.eq(int(c["index_utf16"]), units, "%s: index_utf16 is the code point index in UTF-16 units" % c["name"])
			differ.append(c["name"])
		else:
			t.eq(units, int(c["index"]), "%s: no index_utf16, so the two counts agree" % c["name"])
	t.eq(differ, ["prose-start-glued-astral-letter", "prose-start-astral-letter-then-space"], "the two cases that give index_utf16")
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

# -- an address in prose, beside the fixture ---------------------------------------------------------------------------

func test_read_link_at_the_index_defaults_to_0(t) -> void:
	var n := 0
	for c in _fixture()["cases"]:
		if c["kind"] != "prose" or int(c["index"]) != 0:
			continue
		var given := OWAddress.read_link_at(c["text"], 0)
		var defaulted := OWAddress.read_link_at(c["text"])
		t.eq(given == null, defaulted == null, c["name"])
		if given != null and defaulted != null:
			t.eq(defaulted.end, given.end, c["name"])
		n += 1
	t.ok(n > 40, "cases at index 0: %d" % n)
	t.done()

func test_read_link_at_counts_code_points_so_an_emoji_before_the_address_still_slices_right(t) -> void:
	# The npm package's case, where the emoji is two UTF-16 units and the index 19; a Godot String counts it as one.
	var address := "ow://object/%s@4" % ELEMENT
	var text := "Built " + String.chr(0x1F6A2) + " the gate: " + address + "."
	var at := text.find("ow://")
	t.eq(at, 18, "the emoji is one code point: 18 come before the address")
	var found := OWAddress.read_link_at(text, at)
	t.ok(found != null, "found")
	if found != null:
		t.eq(found.end, at + address.length(), "the end")
		t.eq(text.substr(at, found.end - at), address, "the slice")
		t.eq(text.substr(found.end, 1), ".", "the full stop after it")
		t.eq(found.reading.id, ELEMENT, "the id")
		t.eq(found.reading.moment, 4, "the moment")
	t.done()

func test_read_link_at_a_bad_index_or_an_empty_text_reads_nothing(t) -> void:
	t.ok(OWAddress.read_link_at("ow://x", -1) == null, "an index below 0")
	t.ok(OWAddress.read_link_at("ow://x", 99) == null, "past the end")
	t.ok(OWAddress.read_link_at("", 0) == null, "an empty text")
	t.ok(OWAddress.read_link_at("OW://object/" + ELEMENT) == null, "the prefix as written, lowercase")
	t.done()

func test_find_links_finds_every_address_in_order_by_read_link_at_at_each_prefix(t) -> void:
	# The npm package's doc example: a start glued to a word is prose.
	var id := "01a1d4ef-0000-7000-8000-000000000084"
	var one := OWAddress.find_links("See ow://object/%s, not elbow://object/%s." % [id, id])
	t.eq(one.size(), 1, "one address")
	if one.size() == 1:
		t.eq([one[0].start, one[0].end], [4, 52], "where it starts and ends")
		t.eq([one[0].reading.type, one[0].reading.id], ["object", id], "its reading")
	# Both forms, in the text's order, whichever prefix comes first; a start that reads nothing is passed by.
	var text := "Go to https://www.onlyworlds.com/w/%s/object/%s then ow://nothing, then ow://object/%s@3." % [WORLD, ELEMENT, ELEMENT]
	var all := OWAddress.find_links(text)
	t.eq(all.map(func(f): return text.substr(f.start, f.end - f.start)),
		["https://www.onlyworlds.com/w/%s/object/%s" % [WORLD, ELEMENT], "ow://object/%s@3" % ELEMENT], "both, in order")
	t.eq(all.map(func(f): return f.reading.form), [OWAddress.HUMAN, OWAddress.TEXT], "their forms")
	# Each is read_link_at's at its start, which counts code points: an emoji before it is one.
	var emoji := "Built " + String.chr(0x1F6A2) + " ow://object/" + ELEMENT + "."
	var e := OWAddress.find_links(emoji)
	t.eq(e.size(), 1, "one address after the emoji")
	if e.size() == 1:
		t.eq(e[0].start, emoji.find("ow://"), "its start, in code points")
		t.eq(e[0].end, OWAddress.read_link_at(emoji, e[0].start).end, "read_link_at's end")
	t.eq(OWAddress.find_links("").size(), 0, "an empty text")
	t.eq(OWAddress.find_links("no address here, OW://object/" + ELEMENT).size(), 0, "the prefix as written, lowercase")
	t.done()

## What the npm package's findOwLinks (4.203.0, its built dist/ on Node 22) took on each text below, in ms, the slower
## of two medians of five runs: the name finder's timed recipe "address prefixes with no address" (60,000
## "ow://character/", npm's test/fixtures/name-finder.cases.json) and 10,000 bare prefixes of both forms.
const _NPM_BARE_MS := {"recipe": 14.3, "both forms": 4.0}
## GDScript is an interpreter: on Godot 4.7 the name finder took 11 to 150 times Node's time on the recipes that time
## it alone (test_name_finder.gd). A hundred times npm sits inside that range, and far under the shape this test
## exists to catch: a parse of a fresh substring at every length of each run, 200 to 500 times npm on the recipe
## (2.8 s to 7.2 s, 47 to 120 microseconds a prefix, measured before the finder read each candidate once; about 23
## times npm after).
const _BARE_FACTOR := 100

func test_find_links_reads_each_bare_prefix_once(t) -> void:
	var texts := {
		"recipe": "ow://character/".repeat(60000),
		"both forms": "ow://the-world/character/someone https://www.onlyworlds.com/w/ab/character/ ".repeat(5000),
	}
	for name: String in texts:
		var t0 := Time.get_ticks_usec()
		var found := OWAddress.find_links(texts[name])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var line: float = _NPM_BARE_MS[name] * _BARE_FACTOR
		t.eq(found.size(), 0, "%s: no address" % name)
		t.ok(ms < line, "%s: %.1f ms, the line %.0f ms" % [name, ms, line])
		print("       %.1f ms: find_links on %s" % [ms, name])
	t.done()

func test_read_link_at_the_sites_form_a_run_cut_inside_a_word_is_no_address(t) -> void:
	var h := "https://www.onlyworlds.com/w/"
	t.ok(OWAddress.read_link_at(h + "hyperion" + String.chr(0x1D49C) + ".") == null, "a letter above U+FFFF cuts")
	t.ok(OWAddress.read_link_at(h + "cafe" + String.chr(0x301) + ".") == null, "a combining mark counts with the letters")
	t.ok(OWAddress.read_link_at(h + "hyper_ion.") == null, "an underscore")
	var found := OWAddress.read_link_at(h + "hyperion" + String.chr(0x1F6A2))
	t.eq(found.end if found != null else -1, (h + "hyperion").length(), "an emoji is no letter: the run ends before it")
	t.done()

# -- where an address in prose begins (schema-dist serial 127) ---------------------------------------------------------
# The mirror of the cut after a run: a letter of any script, a combining mark or an underscore before the prefix glues
# it into a word, and the text there is prose; anything else, or the start of the text, does not. Written ahead of the
# fixture and red first on the finder before the rule; the fixture's prose cases now carry the rule, and these stay as
# this SDK's own vectors (each found at the prefix by String.find, its end checked).

const START_ID := "01a1d4ef-0000-7000-8000-000000000084"

## name, text, the prefix the index is at, found.
func _start_cases() -> Array:
	return [
		["glued-letter", "Built the gate: elbow://object/%s." % START_ID, "ow://", false],
		["glued-underscore", "tag_ow://object/%s here" % START_ID, "ow://", false],
		["glued-non-ascii-letter", "caf" + String.chr(0xE9) + "ow://object/" + START_ID, "ow://", false],
		["glued-combining-mark", "e" + String.chr(0x301) + "ow://object/" + START_ID, "ow://", false],
		["glued-astral-letter", String.chr(0x1D49C) + "ow://object/" + START_ID, "ow://", false],
		["after-hyphen", "x-ow://object/" + START_ID, "ow://", true],
		["after-digit", "3ow://object/" + START_ID, "ow://", true],
		["after-space", "Built the gate: ow://object/%s." % START_ID, "ow://", true],
		["after-opening-bracket", "Built the gate (ow://object/%s)." % START_ID, "ow://", true],
		["after-quote", "Built the gate \"ow://object/%s\"." % START_ID, "ow://", true],
		["start-of-text", "ow://object/%s was built." % START_ID, "ow://", true],
		["glued-letter-site-form", "seehttps://www.onlyworlds.com/w/hyperion/object/" + START_ID, "https://", false],
	]

func _start_case(t, c: Array) -> void:
	var text: String = c[1]
	var at := text.find(c[2])
	var found := OWAddress.read_link_at(text, at)
	if not c[3]:
		t.ok(found == null, "the start is glued to a word: found %s at %d" % [text.substr(at, found.end - at) if found != null else "", at])
	else:
		t.ok(found != null, "found an address at %d" % at)
		if found != null:
			t.eq(found.reading.id, START_ID, "the id")
			t.eq(found.end, at + ("ow://object/" + START_ID).length(), "the address ends where its id ends")
	t.done()

func test_the_letters_and_marks_table(t) -> void:
	for c in [0x41, 0x7A, 0xE9, 0x301, 0x5D0, 0x938, 0x93F, 0x4E00, 0xAC00, 0x1D49C, 0x20000, 0x2B0, 0x20DD]:
		t.ok(OWUnicode.is_letter_or_mark(c), "U+%04X is L or M" % c)
	for c in [0x30, 0x5F, 0x2D, 0x20, 0x2E, 0xD7, 0x1F6A2, 0x10FFFF, 0x0, 0x3000, 0x660]:
		t.ok(not OWUnicode.is_letter_or_mark(c), "U+%04X is neither" % c)
	t.done()
