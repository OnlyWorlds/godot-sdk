extends RefCounted
## OWStrand on the strand profile's conformance fixture (schema-dist profiles/strand.fixture.json, the pinned copy at
## dist.98, its sha256 checked against the manifest): every case's six slots by name, and the mark held equal to the
## fixture's. Beside it, what the fixture leaves open: the public rung on a closed and an open world, the mark shapes
## that are no mark, an empty-string member (an empty slot, by the page's words), and a reading that never moves the
## world.

const STRAND := "res://codegen/schema-dist/profiles/strand.fixture.json"
const STORY := "019a7f00-0000-7000-8000-000000000301"
const EMPTY := {"narrative": null, "event": null, "location": null, "character": null, "now": null, "same": null}

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(STRAND))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		match c["kind"]:
			"strand":
				out.append(["strand:" + c["name"], _reads.bind(c)])
			_:
				out.append(["strand:" + c["name"], func(t): t.fail("a case of unknown kind %s" % c["kind"]); t.done()])
	return out

func _world(c: Dictionary) -> Dictionary:
	return _fixture()["worlds"][c["world"]] if c["world"] is String else c["world"]

func _reads(t, c: Dictionary) -> void:
	var world := _world(c)
	var reader: Dictionary = world["readers"][c["reader"]]
	var got := OWStrand.strand_of(world, reader)
	t.eq(got.error, "", "no caller's mistake")
	t.eq(got.to_dict(), c["want"], "the six slots")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(STRAND), manifest["profiles/strand.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "strand", "the profile")
	t.eq(f["cases"].size(), 17, "17 cases")
	t.eq(f["cases"].filter(func(c): return c["kind"] == "strand").size(), 17, "every case a strand case")
	t.eq(f["worlds"].size(), 15, "15 worlds")
	t.eq(f["mark"]["field"], OWStrand.MARK, "the mark's field")
	t.eq(f["mark"]["members"], OWStrand.MEMBERS, "the mark's members, in order")
	t.done()

## The public reader reads no strand of a world that is not open, and the owner's strand of one that is, as the
## charter reader reads the public rung (the npm SDK's test/strand.test.mjs). The owner reading as the public reads a
## closed world as the public does.
func test_the_public_reads_nothing_of_a_closed_world(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
	var owner := OWStrand.strand_of(world, {"rung": "owner"}).to_dict()
	t.eq(OWStrand.strand_of(world, {"rung": "public"}).to_dict(), EMPTY, "closed: nothing")
	t.eq(OWStrand.strand_of(world, {"rung": "owner", "as": {"rung": "public"}}).to_dict(), EMPTY, "the owner as the public")
	world["open"] = true
	t.eq(OWStrand.strand_of(world, {"rung": "public"}).to_dict(), owner, "open: the owner's strand")
	t.done()

## A mark that is not a Dictionary of three Strings is no mark: a member missing, null, a number, the mark a list, a
## bare id, null, no key. Kills: a mark read from whichever members are strings.
func test_a_mark_that_is_not_three_strings_is_no_mark(t) -> void:
	var harbour: Dictionary = _fixture()["worlds"]["harbour"]
	var m: Dictionary = harbour[OWStrand.MARK]
	var no_event := m.duplicate()
	no_event.erase("event")
	var null_place := m.duplicate()
	null_place["location"] = null
	var number_story := m.duplicate()
	number_story["narrative"] = 7
	for bad in [no_event, null_place, number_story, [m["narrative"], m["event"], m["location"]], STORY, null]:
		var world := harbour.duplicate(true)
		world[OWStrand.MARK] = bad
		t.eq(OWStrand.strand_of(world, {"rung": "owner"}).to_dict(), EMPTY, var_to_str(bad))
	var none := harbour.duplicate(true)
	none.erase(OWStrand.MARK)
	t.eq(OWStrand.strand_of(none, {"rung": "owner"}).to_dict(), EMPTY, "no key")
	t.done()

## The page's words on a member that is an empty string: a String, so the mark's shape holds, and an id that names no
## element in the view, so its slot is empty and the rest still read (keel's mark_of). The npm SDK and the Python
## package read it as no mark; the difference is open with the profile's owner.
func test_an_empty_string_member_is_an_empty_slot(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
	world[OWStrand.MARK]["event"] = ""
	var got := OWStrand.strand_of(world, {"rung": "owner"})
	t.eq(got.narrative["id"] if got.narrative is Dictionary else null, STORY, "the story reads")
	t.eq(got.event, null, "the event is empty")
	t.eq(got.location, null, "the place hangs off the event")
	t.eq(got.character["id"] if got.character is Dictionary else null, "019a7f00-0000-7000-8000-000000000331", "the hero reads")
	t.eq(got.now["id"] if got.now is Dictionary else null, "019a7f00-0000-7000-8000-000000000322", "now reads")
	t.eq(got.same, null, "same needs both")
	t.done()

## A caller's mistake is no reading: the message names it, and the strand is empty.
func test_a_callers_mistake_is_named(t) -> void:
	t.ok(OWStrand.strand_of({"no": "elements"}, {"rung": "owner"}).error.contains("world"), "a world without elements")
	t.ok(OWStrand.strand_of({"elements": []}, {"rung": "king"}).error.contains("rung"), "a rung outside the four")
	t.eq(OWStrand.strand_of(3, {"rung": "owner"}).to_dict(), EMPTY, "nothing read")
	t.done()

## Pure: no reading moves the world, and a strand handed out is the caller's own.
func test_a_reading_never_moves_the_world(t) -> void:
	for name in _fixture()["worlds"]:
		var world: Dictionary = _fixture()["worlds"][name]
		var before := JSON.stringify(world, "", false, true)
		for r in world["readers"]:
			var got := OWStrand.strand_of(world, world["readers"][r])
			if got.narrative is Dictionary:
				got.narrative["name"] = "planted"
		t.eq(JSON.stringify(world, "", false, true), before, "%s unchanged" % name)
	t.done()
