extends RefCounted
## OWNameFinder on the TypeScript SDK's and the Python package's shared cases (tests/data/name-finder.cases.json, the
## same bytes, held by its sha256): what find(text) answers and what shared lists on every case, then the timed recipes,
## then what the cases cannot hold: indexes in code points, the objects answered, purity, the caller's mistakes, the
## one fact about folding the matcher stands on, the word table, and inputs the cases are silent on, each held to the
## TypeScript SDK's answer.

const CASES := "res://tests/data/name-finder.cases.json"
const CASES_SHA256 := "8e91e79981830511055976011f9fc6d4f4b62fb0183c29bad61c2d05fd4b13e4"
## The cases' underMs (2,000) is the TypeScript SDK's line, about 28 times its slowest recipe on Node (70 ms). GDScript
## is an interpreter: on Godot 4.7 this matcher took 11 to 150 times Node's time on the recipes that time it alone, and
## about 400 times on "address prefixes with no address", whose cost is OWAddress.find_links (60,000 prefixes that
## read as no address, about 0.1 ms each: 3 to 7 s of the recipe's 7.6 s, measured twice). So npm's line cannot hold
## here. Fifteen times it, 30 s, sits about four times over the slowest recipe, room for a loaded machine (one probe
## read find_links twice as slow on its second run), and far under the shape this test exists to catch: a matcher that
## reads a 5,000-character name again at each of 200,000 places, a billion steps, minutes in GDScript.
const FACTOR := 15

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	return _doc

static func _names_of(e: Variant) -> Array:
	return e["names"] if e.get("names") is Array else [e.get("name")]

func _answer(c: Dictionary) -> Array:
	var find := OWNameFinder.name_finder(c["elements"], c["case"], _names_of)
	var out := []
	for f in find.find(c["text"]):
		out.append({"at": f.start, "length": f.end - f.start, "id": f.element["id"]})
	return out

static func _want(rows: Array) -> Array:
	var out := []
	for w in rows:
		out.append({"at": int(w["at"]), "length": int(w["length"]), "id": w["id"]})
	return out

func _shared(c: Dictionary) -> Array:
	var out := []
	for s in OWNameFinder.name_finder(c["elements"], c["case"], _names_of).shared:
		var ids := []
		for e in s.elements:
			ids.append(e["id"])
		out.append({"name": s.name, "ids": ids})
	return out

static func _spans(name: String, name_case: String, text: String) -> Array:
	var out := []
	for f in OWNameFinder.name_finder([{"id": "x", "name": name}], name_case).find(text):
		out.append([f.start, f.end])
	return out

func test_the_cases_file_is_the_shared_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(CASES), CASES_SHA256, "the bytes the TypeScript SDK and the Python package run")
	t.eq(int(_fixture()["version"]), 2, "version 2")
	t.eq(_fixture()["cases"].size(), 62, "62 cases")
	t.eq(_fixture()["timed"].size(), 10, "10 timed recipes")
	t.done()

func test_every_case_what_find_answers(t) -> void:
	var wrong := 0
	for c in _fixture()["cases"]:
		var got := _answer(c)
		var want := _want(c["want"])
		if JSON.stringify(got, "", false) != JSON.stringify(want, "", false):
			wrong += 1
			t.fail("%s\n    want %s\n    got  %s" % [c["name"], JSON.stringify(want, "", false), JSON.stringify(got, "", false)])
	t.eq(wrong, 0, "cases that disagree")
	t.done()

func test_every_case_what_shared_lists(t) -> void:
	var wrong := 0
	var listing := 0
	var folds := {}
	var more_than_one := false
	for c in _fixture()["cases"]:
		var got := _shared(c)
		if JSON.stringify(got, "", false) != JSON.stringify(c["shared"], "", false):
			wrong += 1
			t.fail("%s\n    want %s\n    got  %s" % [c["name"], JSON.stringify(c["shared"], "", false), JSON.stringify(got, "", false)])
		if c["shared"].size() > 0:
			listing += 1
			folds[c["case"]] = true
		if c["shared"].size() > 1:
			more_than_one = true
	t.eq(wrong, 0, "cases that disagree")
	t.ok(listing >= 10 and more_than_one, "ten cases list a shared name, one lists more than one")
	t.ok(folds.has("exact") and folds.has("folded"), "both folds list one")
	t.done()

func test_the_cases_hold_answers_of_both_kinds(t) -> void:
	var some := {}
	var none := false
	for c in _fixture()["cases"]:
		if c["want"].size() > 0:
			some[c["case"]] = true
		else:
			none = true
	t.ok(none and some.has("exact") and some.has("folded"), "some name found in both folds, and none")
	t.done()

static func _pattern(p: String, i: int) -> String:
	return p.replace("{i}", str(i))

static func _build(recipe: Dictionary) -> Array:
	var elements := []
	var long: Variant = recipe["elements"].get("long")
	for i in int(recipe["elements"]["count"]):
		var name: String
		if long == null:
			name = _pattern(recipe["elements"]["pattern"], i)
		else:
			name = String(long["repeat"]).repeat(int(long["times"])) + long["then"]
		elements.append({"id": "e%d" % i, "name": name})
	var text: String
	if recipe["text"].has("repeat"):
		text = String(recipe["text"]["repeat"]).repeat(int(recipe["text"]["times"]))
	else:
		var parts := PackedStringArray()
		var count := int(recipe["text"]["count"])
		for i in int(recipe["text"]["times"]):
			parts.append(_pattern(recipe["text"]["cycle"], i % count))
		text = "".join(parts)
	return [elements, text]

## Linear in the text whatever the names: each recipe answers its count under FACTOR times the cases' underMs. A
## matcher that reads a name again at each place (the TypeScript SDK's before 4.198.0) takes minutes on the three with a
## name of thousands of characters, far past the line.
func test_the_timed_recipes(t) -> void:
	var recipes: Array = _fixture()["timed"]
	var long := 0
	for r in recipes:
		if r["elements"].get("long") != null and int(r["elements"]["long"]["times"]) >= 2500:
			long += 1
	t.ok(long >= 3, "three recipes with a name of thousands of characters")
	var line := float(_fixture()["underMs"]) * FACTOR
	for r in recipes:
		var built := _build(r)
		var find := OWNameFinder.name_finder(built[0], OWNameFinder.EXACT)
		var t0 := Time.get_ticks_usec()
		var found := find.find(built[1])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("       timed: %s: %d found in %.0f ms" % [r["name"], found.size(), ms])
		t.eq(found.size(), int(r["count"]), r["name"])
		t.ok(ms < line, "%s: %.0f ms, the line %.0f" % [r["name"], ms, line])
	t.done()

func test_start_and_end_count_code_points_and_the_substr_is_the_name_as_written(t) -> void:
	var dragon := String.chr(0x1F409)
	var text := dragon + " Kira met " + dragon + dragon + " KIRA."
	var got := []
	for f in OWNameFinder.name_finder([{"id": "k", "name": "Kira"}], OWNameFinder.FOLDED).find(text):
		got.append([f.start, f.end, text.substr(f.start, f.end - f.start)])
	t.eq(got, [[2, 6, "Kira"], [14, 18, "KIRA"]], "the TypeScript SDK's [3, 7] and [17, 21], less one per character above U+FFFF")
	t.done()

func test_element_is_the_object_passed_in_and_the_default_name_is_its_name(t) -> void:
	var kira := {"id": "k", "name": "Kira", "type": "character", "description": "A watchman."}
	var f: Array = OWNameFinder.name_finder([kira], OWNameFinder.EXACT).find("Kira.")
	t.eq(f.size(), 1, "one found")
	t.ok(is_same(f[0].element, kira), "the Dictionary passed in")
	var ember := OWCharacter.new()
	ember.id = "01a1d4ef-0000-7000-8000-000000000001"
	ember.name = "Ember"
	var g: Array = OWNameFinder.name_finder([ember], OWNameFinder.EXACT).find("Ember's watch")
	t.ok(g.size() == 1 and is_same(g[0].element, ember), "a typed element, read by its id and name")
	t.done()

func test_shared_is_the_objects_passed_in_in_the_order_given_read_only_and_read_once(t) -> void:
	var a := {"id": "a", "name": "Ember"}
	var b := {"id": "b", "name": "EMBER "}
	var k := {"id": "k", "name": "Kira"}
	var elements := [k, b, a]
	var find := OWNameFinder.name_finder(elements, OWNameFinder.FOLDED)
	t.eq(find.shared.size(), 1, "one shared name")
	t.eq(find.shared[0].name, "ember", "as compared: trimmed and folded")
	t.ok(is_same(find.shared[0].elements[0], b) and is_same(find.shared[0].elements[1], a), "the objects, in the order given")
	t.ok(find.shared.is_read_only() and find.shared[0].elements.is_read_only(), "the list and its entries' elements are read only")
	t.ok(not a.is_read_only() and not elements.is_read_only(), "nothing given is made read only")
	elements.append({"id": "x", "name": "Kira"})
	t.eq(find.shared.size(), 1, "the names were read once, when the finder was made")
	var names := []
	for s in OWNameFinder.name_finder(elements, OWNameFinder.EXACT).shared:
		names.append(s.name)
	t.eq(names, ["Kira"], "exact: only Kira is shared now")
	t.eq(OWNameFinder.name_finder([], OWNameFinder.EXACT).shared, [], "no elements, nothing shared")
	var ids := []
	for f in find.find("Ember, ember, Kira"):
		ids.append(f.element["id"])
	t.eq(ids, ["k"], "a listed name is never answered")
	t.done()

## The matcher lays a mark before every character of a name that is not a word character, read from the name as
## folded, and before every such character of the text, read as written. The two agree only while no character changes
## kind when it is folded: held here on every row of the fold, against the word table this addon reads.
func test_folding_never_moves_a_character_into_or_out_of_a_word(t) -> void:
	var folds := 0
	var moved := []
	for c in OWUnicode.D.FOLD:
		var f := OWUnicode.fold_code_point(c)
		if f == c:
			continue
		folds += 1
		if OWNameFinder.is_word(c) != OWNameFinder.is_word(f):
			moved.append("U+%X" % c)
	t.ok(folds > 1400, "%d code points fold" % folds)
	t.eq(moved, [], "none changes kind")
	t.done()

## The word edge is a table generated from Unicode 15.1's UnicodeData (codegen/generate.py, the vendored file whose sha256
## the pinned MANIFEST.json holds). The digests are of Python 3.13.1's unicodedata (15.1.0), read apart from the
## generator: each range as "<first>-<last>;" in upper-case hex.
func test_the_word_table_is_unicode_15_1(t) -> void:
	t.eq(OWUnicode.D.UNICODE_VERSION, "15.1.0", "the tables' version")
	t.eq(_digest(OWUnicode.D.LETTER_OR_MARK), "8898e86dc4cdc725710d4e287677c8854e5a8a69538a4eb23d7421fba7af2f30", "L and M: 725 ranges")
	t.eq(_digest(OWUnicode.D.DECIMAL_DIGIT), "cf75098334890f09f69cceaad74d1ca0b5855ce45840969defa6bbf5a017450e", "Nd: 64 ranges")
	t.eq(_count(OWUnicode.D.LETTER_OR_MARK), 139176, "L and M code points")
	t.eq(_count(OWUnicode.D.DECIMAL_DIGIT), 680, "Nd code points")
	for c in [0x30, 0x39, 0x41, 0x5A, 0x5F, 0x61, 0x7A, 0xE9, 0x301, 0x660, 0x1E4D0, 0xA7C4, 0x10400]:
		t.ok(OWNameFinder.is_word(c), "U+%X is a word character" % c)
	for c in [0x20, 0x2D, 0x27, 0xB2, 0x216B, 0x2460, 0x1F409, 0x10D4A, 0xFFFD]:
		t.ok(not OWNameFinder.is_word(c), "U+%X is not" % c)
	t.done()

static func _digest(ranges: Array) -> String:
	var parts := PackedStringArray()
	for i in range(0, ranges.size(), 2):
		parts.append("%X-%X;" % [ranges[i], ranges[i + 1]])
	return "".join(parts).sha256_text()

static func _count(ranges: Array) -> int:
	var n := 0
	for i in range(0, ranges.size(), 2):
		n += ranges[i + 1] - ranges[i] + 1
	return n

func test_nothing_given_is_changed_and_one_finder_answers_the_same(t) -> void:
	var elements := [{"id": "k", "name": "  Kira  ", "aliases": ["The Watch"]}, {"id": "g", "name": "Iron Gate"}]
	var before := JSON.stringify(elements, "", false)
	var find := OWNameFinder.name_finder(elements, OWNameFinder.FOLDED, func(e): return [e["name"]] + e.get("aliases", []))
	var text := "the watch saw Kira at the IRON GATE"
	var first := find.find(text)
	t.eq(JSON.stringify(elements, "", false), before, "the elements as they were")
	var ids := []
	for f in first:
		ids.append(f.element["id"])
	t.eq(ids, ["k", "k", "g"], "each name of an element")
	first.clear()
	t.eq(find.find(text).size(), 3, "an answer is the caller's own list")
	elements.append({"id": "x", "name": "saw"})
	t.eq(find.find(text).size(), 3, "the names were read once, when the finder was made")
	t.done()

## A caller's mistake is the answer's error, said by name, and nothing is found; GDScript has no exceptions. A text
## that is not a String is GDScript's own refusal (find takes a String), as a TypeError is JavaScript's.
func test_the_callers_mistakes_each_by_name(t) -> void:
	var els := [{"id": "k", "name": "Kira"}]
	var rows := [
		[OWNameFinder.name_finder(els, null), "name_case is \"exact\" or \"folded\", and must be given; got null"],
		[OWNameFinder.name_finder(els, "Exact"), "name_case is \"exact\" or \"folded\""],
		[OWNameFinder.name_finder(els, OWNameFinder.EXACT, ["Kira"]), "names is a Callable"],
		[OWNameFinder.name_finder(null, OWNameFinder.EXACT), "elements is an Array"],
		[OWNameFinder.name_finder("Kira", OWNameFinder.EXACT), "elements is an Array"],
		[OWNameFinder.name_finder([{"name": "Kira"}], OWNameFinder.EXACT), "every element has a String id"],
		[OWNameFinder.name_finder([{"id": 7, "name": "Kira"}], OWNameFinder.EXACT), "every element has a String id"],
		[OWNameFinder.name_finder([{"id": "", "name": "Kira"}], OWNameFinder.EXACT), "every element has a String id"],
		[OWNameFinder.name_finder([null], OWNameFinder.EXACT), "every element has a String id"],
		[OWNameFinder.name_finder(els, OWNameFinder.EXACT, func(e): return "Kira"), "names answers an Array"],
	]
	for r in rows:
		var f: OWNameFinder = r[0]
		t.ok(f.error.begins_with("name_finder: ") and f.error.contains(r[1]), "%s in: %s" % [r[1], f.error])
		t.eq(f.find("Kira"), [], "nothing found: " + r[1])
		t.eq(f.shared, [], "nothing shared: " + r[1])
	t.eq(OWNameFinder.name_finder(els, OWNameFinder.EXACT).error, "", "no mistake")
	t.done()

## Inputs the shared cases are silent on, with the TypeScript SDK's answers (4.202.0's build, whose name-finder.ts is
## 4.198.0's), in code points. Its two that hold a lone surrogate cannot be written here: a Godot String holds none.
func test_where_the_cases_are_silent_the_answer_is_the_typescript_sdks(t) -> void:
	var acute := String.chr(0x301)
	var dragon := String.chr(0x1F409)
	t.eq(_spans("???", "exact", "Who??? and ??? and a???b and ????"), [[11, 14], [29, 32]], "a name of punctuation alone")
	t.eq(_spans(acute + "Ana", "exact", " " + acute + "Ana e" + acute + "Ana"), [[1, 5]], "a leading combining mark")
	t.eq(_spans("Kira", "exact", "[Kira]"), [[1, 5]], "brackets at the end are prose")
	t.eq(_spans("Kira", "exact", "[Kira]("), [[1, 5]], "a bracket and a parenthesis at the end are prose")
	t.eq(_spans("Kira", "exact", "[a](b(c)) Kira) Kira"), [[10, 14], [16, 20]], "a target ends at its first closing parenthesis")
	t.eq(_spans("Kira", "exact", "Kira[](x)Kira[x]()Kira"), [[0, 4], [9, 13], [18, 22]], "an empty label and an empty target")
	t.eq(_spans("Kira", "exact", "Kira" + String.chr(0x216B) + " and Kira"), [[0, 4], [10, 14]], "a letter number (Nl) is no word character")
	t.eq(_spans("Ab" + String.chr(0x10400), "folded", "AB" + String.chr(0x10428) + " ab" + String.chr(0x10400)), [[0, 3], [4, 7]], "folded: a Deseret letter")
	t.eq(_spans("Kira", "exact", dragon + "Kira " + dragon), [[1, 5]], "a character above U+FFFF on both sides")
	t.eq(_spans("a" + String.chr(0xA7C4) + "bc", "folded", "a" + String.chr(0xA7C4) + "bc a" + String.chr(0xA794) + "bc"), [[0, 4], [5, 9]], "folded: a capital Unicode 12.0 added, and its fold")
	t.eq(_spans("abc", "exact", "abc" + String.chr(0xA7C4) + " " + String.chr(0xA7C4) + "abc abc"), [[10, 13]], "that capital beside a name is a letter")
	t.done()
