extends RefCounted
## OWCharter on the charter profile's conformance fixture (schema-dist profiles/charter.fixture.json, the pinned copy
## at dist.133, its sha256 checked against the manifest): every case, the 41 charter readings (charterOf and domainsOf,
## the packet compared whole) and the 6 element cases (isCharterElement), and the profile's tables held equal to the
## fixture's.

const CHARTER := "res://codegen/schema-dist/profiles/charter.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CHARTER))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		match c["kind"]:
			"charter":
				out.append(["charter:" + c["name"], _reads.bind(c)])
			"element":
				out.append(["charter:" + c["name"], _element.bind(c)])
			_:
				out.append(["charter:" + c["name"], func(t): t.fail("a case of unknown kind %s" % c["kind"]); t.done()])
	return out

func _world(c: Dictionary) -> Dictionary:
	return _fixture()["worlds"][c["world"]] if c["world"] is String else c["world"]

func _reads(t, c: Dictionary) -> void:
	var world := _world(c)
	var reader: Dictionary = world["readers"][c["reader"]]
	var got := OWCharter.charter_of(world, reader)
	t.eq(got.error, "", "no caller's mistake")
	var want: Dictionary = c["want"]
	t.eq(got.to_dict(), want, "the packet, whole")
	t.eq(OWCharter.domains_of(world, reader), want["domains"], "domains_of is the list alone")
	t.done()

func _element(t, c: Dictionary) -> void:
	t.eq(OWCharter.is_charter_element(c["element"]), c["is_charter_element"], "is_charter_element")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(CHARTER), manifest["profiles/charter.fixture.json"], "the fixture's bytes are the dist's")
	var counts := {}
	for c in _fixture()["cases"]:
		counts[c["kind"]] = counts.get(c["kind"], 0) + 1
	t.eq(_fixture()["cases"].size(), 47, "47 cases")
	t.eq(counts, {"charter": 41, "element": 6}, "by kind")
	t.done()

func test_the_tables_are_the_fixtures(t) -> void:
	var f := _fixture()
	t.eq(f["profile"], "charter", "the profile")
	var pairs := []
	for p in f["pairs"]:
		pairs.append(OWUnicode.profile_fold(p["type"]) + "/" + OWUnicode.profile_fold(p["supertype"]))
	t.eq(pairs, OWCharter.PAIRS, "the pairs, folded, in the fixture's order")
	t.eq(f["mark"]["field"], OWCharter.MARK, "the mark")
	t.eq(f["rules_field"], OWCharter.RULES_FIELD, "the rules field")
	t.eq(int(f["skill_max"]), OWCharter.SKILL_MAX, "skill_max")
	var hubs := []
	for h in f["hub_fields"]:
		hubs.append([h["field"], h["type"]])
	t.eq(hubs, OWCharter.hub_fields(), "the hub fields are the generated Construct's links, in the schema's order")
	t.done()

## Each entry is written in the page's order, type beside id (serial 133): the fixture's key order carries no meaning,
## so the replay's whole compare cannot see it.
func test_each_entry_is_written_in_the_pages_order(t) -> void:
	var harbour: Dictionary = _fixture()["worlds"]["harbour"]
	var got := OWCharter.charter_of(harbour, {"rung": "owner"})
	t.eq(got.charter.keys() if got.charter is Dictionary else null, ["id", "type", "name", "rules", "skill"], "the Charter")
	t.eq(got.guide.keys() if got.guide is Dictionary else null, ["id", "type", "name"], "the Guide")
	t.ok(got.domains.size() > 0, "harbour has Domains")
	for d in got.domains:
		t.eq(d.keys(), ["id", "type", "name", "sentence", "hubs"], "a Domain")
	t.done()

## The packet says the pair's own word (serial 133, amendment 1): a Charter stored as " Law " and a Domain stored as
## "CONSTRUCT" are aids, written law and construct. Kills: the stored spelling.
func test_a_type_stored_in_another_spelling_is_written_as_the_pairs_word(t) -> void:
	var world := {"id": "w", "elements": [
		{"id": "019a7f00-0000-7000-8000-0000000002c0", "type": " Law ", "name": "Rules", "supertype": "Charter",
			"x_charter_of": "w"},
		{"id": "019a7f00-0000-7000-8000-0000000002c1", "type": "CONSTRUCT", "name": "Docks", "supertype": "Domain",
			"x_charter_of": "w"},
	]}
	var got := OWCharter.charter_of(world, {"rung": "owner"})
	t.eq(got.charter["type"] if got.charter is Dictionary else null, "law", "the Charter")
	t.eq(got.domains.size(), 1, "the Domain is an aid")
	t.eq(got.domains[0]["type"] if got.domains.size() == 1 else null, "construct", "the Domain")
	t.done()

## The lens profile's first_line: trimmed, cut at the first line feed or carriage return, trimmed again.
func test_first_line(t) -> void:
	t.eq(OWCharter.first_line("  One.  \nTwo."), "One.", "trimmed both sides of the cut")
	t.eq(OWCharter.first_line("One.\rTwo."), "One.", "a carriage return cuts")
	t.eq(OWCharter.first_line("One.\r\nTwo."), "One.", "a CRLF cuts once")
	t.eq(OWCharter.first_line("\n\nOne."), "One.", "leading breaks are trimmed first")
	t.eq(OWCharter.first_line("　One"), "One", "an ideographic space is White_Space")
	t.eq(OWCharter.first_line(null), "", "no text")
	t.eq(OWCharter.first_line(3), "", "not text")
	t.done()

## A caller's mistake is no reading: the message names it, and the packet is empty.
func test_a_callers_mistake_is_named(t) -> void:
	t.ok(OWCharter.charter_of({"no": "elements"}, {"rung": "owner"}).error.contains("world"), "a world without elements")
	t.ok(OWCharter.charter_of({"elements": []}, {"rung": "king"}).error.contains("rung"), "a rung outside the four")
	var bad := OWCharter.charter_of(3, {"rung": "owner"})
	t.eq(bad.to_dict(), {"charter": null, "guide": null, "domains": []}, "nothing read")
	t.eq(OWCharter.domains_of(3, {"rung": "owner"}), [], "domains_of: an empty list")
	t.done()

## Pure: no reading moves the world.
func test_a_reading_never_moves_the_world(t) -> void:
	for name in _fixture()["worlds"]:
		var world: Dictionary = _fixture()["worlds"][name]
		var before := JSON.stringify(world, "", false, true)
		for r in world["readers"]:
			OWCharter.charter_of(world, world["readers"][r])
		t.eq(JSON.stringify(world, "", false, true), before, "%s unchanged" % name)
	t.done()

## A Charter over one Object, its text naming the skill as given: the skill list the owner reads.
func _skill_of(text: String, object_id: String) -> Variant:
	var world := {"id": "w", "elements": [
		{"id": "019a7f00-0000-7000-8000-0000000002b0", "type": "law", "name": "Rules", "supertype": "Charter",
			"x_charter_of": "w", "description": text},
		{"id": object_id, "type": "object", "name": "Skill"},
	]}
	var charter = OWCharter.charter_of(world, {"rung": "owner"}).to_dict()["charter"]
	return null if charter == null else charter["skill"]

## The address profile's rule for the same id, at the Charter's door: a skill id named in lowercase in the text is not
## an Object whose own id is held in upper case, since the Object's id is read as written. Kills: the held id folded.
func test_a_skill_named_in_lowercase_is_not_an_object_held_in_upper_case(t) -> void:
	t.eq(_skill_of("Read ow://object/019a7f00-0000-7000-8000-0000000002bf.", "019A7F00-0000-7000-8000-0000000002BF"), [],
		"not kept")
	t.done()

## An id found in the text is read in either case and taken in lowercase: named in upper case, it is the Object held in
## lowercase, and the skill lists the Object's own id. Kills: the text's id matched as written.
func test_a_skill_named_in_upper_case_is_the_object_held_in_lowercase(t) -> void:
	t.eq(_skill_of("Read 019A7F00-0000-7000-8000-0000000002BE.", "019a7f00-0000-7000-8000-0000000002be"),
		["019a7f00-0000-7000-8000-0000000002be"], "kept, as the Object's own id")
	t.done()
