extends RefCounted
## OWCharter on the charter profile's conformance fixture (schema-dist profiles/charter.fixture.json, the pinned copy
## at dist.83, its sha256 checked against the manifest): every case, the 17 charter readings (charterOf and
## domainsOf) and the 5 element cases (isCharterElement), and the profile's tables held equal to the fixture's.

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
	t.eq(got.charter, want["charter"], "charter")
	t.eq(got.guide, want["guide"], "guide")
	t.eq(got.domains, want["domains"], "domains")
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
	t.eq(_fixture()["cases"].size(), 22, "22 cases")
	t.eq(counts, {"charter": 17, "element": 5}, "by kind")
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
