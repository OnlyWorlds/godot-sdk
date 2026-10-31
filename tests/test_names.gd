extends RefCounted
## OWNames on the names profile's conformance fixture (schema-dist profiles/names.fixture.json, the pinned copy at
## dist.101, its sha256 checked against the manifest): every case's word, or null for the standard's name. Beside it,
## the readings the fixture does not hold, each as the npm SDK's typeWord reads it.

const NAMES := "res://codegen/schema-dist/profiles/names.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(NAMES))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["names:" + c["name"], _prints.bind(c)])
	return out

func _prints(t, c: Dictionary) -> void:
	var world := {"name": "W", "x_names": c["map"]}
	t.eq(OWNames.type_word(world, c["type"], c.get("supertype"), c["many"]), c["word"], "the word")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(NAMES), manifest["profiles/names.fixture.json"], "the fixture's bytes are the dist's")
	t.eq(_fixture()["profile"], "x_names", "the profile")
	var names := {}
	for c in _fixture()["cases"]:
		names[c["name"]] = true
	t.eq(_fixture()["cases"].size(), 29, "29 cases")
	t.eq(names.size(), 29, "every case's name is its own")
	t.eq(_fixture()["cases"].filter(func(c): return c["word"] == null).size(), 14, "14 print the standard's name")
	t.done()

## Godot's JSON reads every number as a float: the fixture's version 1 arrives as 1.0, its "one": 3 as 3.0. A number 1
## either way is a names map, as JavaScript's === 1 reads it; anything else that is not the number 1 is not.
func test_version_one_is_the_number_one(t) -> void:
	var types := {"character": {"one": "Employee"}}
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": types}}, "character"), "Employee", "an int 1, as code builds it")
	t.eq(OWNames.type_word({"x_names": {"version": 1.0, "types": types}}, "character"), "Employee", "a float 1.0, as JSON reads it")
	t.eq(JSON.parse_string('{"version": 1}')["version"], 1.0, "Godot's JSON reads 1 as 1.0")
	t.eq(OWNames.type_word({"x_names": {"version": "1", "types": types}}, "character"), null, "a string")
	t.eq(OWNames.type_word({"x_names": {"version": true, "types": types}}, "character"), null, "true")
	t.eq(OWNames.type_word({"x_names": {"version": 1.5, "types": types}}, "character"), null, "1.5")
	t.eq(OWNames.type_word({"x_names": {"types": types}}, "character"), null, "no version")
	t.done()

func test_no_world_no_map_or_a_map_that_is_not_an_object(t) -> void:
	t.eq(OWNames.type_word(null, "character"), null, "no world")
	t.eq(OWNames.type_word({"name": "W"}, "character"), null, "no map")
	t.eq(OWNames.type_word({"x_names": null}, "character"), null, "a null map")
	t.eq(OWNames.type_word({"x_names": "Employee"}, "character"), null, "a string")
	t.eq(OWNames.type_word({"x_names": [{"version": 1}]}, "character"), null, "a list")
	t.eq(OWNames.type_word("world", "character"), null, "a world that is not an object")
	t.done()

## npm refuses a types or supertypes key that is present and null (only an absent one is no map part).
func test_a_null_part_is_present_and_refused(t) -> void:
	var types := {"character": {"one": "Employee"}}
	var agent := {"character": {"Agent": {"one": "AI agent"}}}
	t.eq(OWNames.type_word({"x_names": {"version": 1, "supertypes": agent}}, "character", "Agent"), "AI agent", "the word, without the null")
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": null, "supertypes": agent}}, "character", "Agent"), null, "types: null")
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": types, "supertypes": null}}, "character"), null, "supertypes: null")
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": types, "supertypes": {"character": null}}}, "character"), null,
		"a supertypes value that is null")
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": types, "supertypes": {"zone": []}}}, "character"), null,
		"a supertypes value that is not an object refuses the map, for another type too")
	t.eq(OWNames.type_word({"x_names": {"version": 1, "types": types, "supertypes": {}}}, "character"), "Employee", "empty supertypes")
	t.done()

func test_the_slug_is_matched_as_the_schema_spells_it(t) -> void:
	var world := {"x_names": {"version": 1, "types": {"character": {"one": "Employee"}}}}
	t.eq(OWNames.type_word(world, "character"), "Employee", "the slug")
	t.eq(OWNames.type_word(world, &"character"), "Employee", "a StringName slug, as OWElement.get_type gives it")
	t.eq(OWNames.type_word(world, "Character"), null, "a type slug is lowercase; the fold is the supertype's")
	t.eq(OWNames.type_word(world, " character"), null, "a slug is never trimmed")
	t.eq(OWNames.type_word({"x_names": _fixture()["cases"][0]["map"]}, "employee"), null,
		"a key that is not one of the 22 is never read, asked for by name (the fixture asks only for species)")
	t.eq(OWNames.type_word(world, null), null, "no type")
	t.eq(OWNames.type_word(world, 3), null, "a type that is not text")
	t.done()

func test_the_supertype_is_trimmed_by_unicode_white_space(t) -> void:
	var world := {"x_names": {"version": 1, "supertypes": {"character": {"Agent": {"one": "AI agent"}}}}}
	t.eq(OWNames.type_word(world, "character", String.chr(0x3000) + "Agent" + String.chr(0xA0)), "AI agent",
		"ideographic and no-break spaces trim")
	t.eq(OWNames.type_word(world, "character", String.chr(0xFEFF) + "Agent"), null, "a byte order mark is not White_Space and stays")
	t.eq(OWNames.type_word(world, "character", String.chr(0x200B) + "Agent"), null, "a zero width space is not White_Space and stays")
	t.eq(OWNames.type_word(world, "character", &"agent"), "AI agent", "a StringName supertype")
	t.eq(OWNames.type_word(world, "character", 3), null, "a supertype that is not text is none")
	t.done()

func test_the_supertype_is_folded_by_simple_case_folding(t) -> void:
	var world := {"x_names": {"version": 1, "supertypes": {"character": {"Σοφός": {"one": "Sage"}}}}}
	t.eq(OWNames.type_word(world, "character", "ΣΟΦΌΣ"), "Sage", "capital sigma folds with final sigma")
	t.done()

func test_a_blank_supertype_goes_straight_to_the_types_word(t) -> void:
	var world := {"x_names": {"version": 1, "types": {"character": {"one": "Employee"}},
		"supertypes": {"character": {"": {"one": "Nobody"}, " ": {"one": "Nobody"}}}}}
	t.eq(OWNames.type_word(world, "character", "  "), "Employee", "white space only")
	t.eq(OWNames.type_word(world, "character", ""), "Employee", "empty")
	t.done()

## Two keys that fold to one supertype: the first in the map's order with a word prints.
func test_keys_that_fold_alike_go_in_the_maps_order(t) -> void:
	var world := {"x_names": {"version": 1, "supertypes": {"character": {
		"agent": {"one": " "}, "AGENT": {"one": "Second"}, "Agent": {"one": "Third"}}}}}
	t.eq(OWNames.type_word(world, "character", "Agent"), "Second", "an ignored entry is no entry; the next match prints")
	t.done()

func test_the_word_is_printed_as_written(t) -> void:
	var world := {"x_names": {"version": 1, "types": {"character": {"one": "eMPLOYEE", "many": "ai Agents"}}}}
	t.eq(OWNames.type_word(world, "character"), "eMPLOYEE", "one")
	t.eq(OWNames.type_word(world, "character", null, true), "ai Agents", "many")
	t.done()

## Pure: no reading moves the world.
func test_a_reading_never_moves_the_world(t) -> void:
	for c in _fixture()["cases"]:
		var world := {"x_names": c["map"]}
		var before := JSON.stringify(world, "", false, true)
		OWNames.type_word(world, c["type"], c.get("supertype"), c["many"])
		t.eq(JSON.stringify(world, "", false, true), before, "%s unchanged" % c["name"])
	t.done()
