extends RefCounted
## OWStrand on the strand profile's conformance fixture (schema-dist profiles/strand.fixture.json): every case's six
## slots by name, and the mark held equal to the fixture's. Beside it, what the fixture leaves open: the public rung on
## a closed and an open world, the mark shapes that are no mark (an empty-string member among them), a story alone, a
## non-list multi-link, a nameless slot, the slot's key order, a caller's mistake, and a reading that never moves the
## world.
##
## Serial 134 (each filled slot carries its type) is staged, not published: its fixture is held apart in
## tests/data/serial-134/, its sha256 the staged one, so the vendored dist and its manifest stay the pin's. When the pin
## reaches 134, point STRAND back at res://codegen/schema-dist/profiles/strand.fixture.json, check it against the
## manifest again, and drop the staged copy.

const STRAND := "res://tests/data/serial-134/strand.fixture.json"
const STAGED_SHA256 := "2b1221f1c611e94ac5851669330ab75ba62332c51764786105bcdba23b5be7e6"
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
	t.eq(FileAccess.get_sha256(STRAND), STAGED_SHA256, "the fixture's bytes are serial 134's staged copy")
	var f := _fixture()
	t.eq(f["profile"], "strand", "the profile")
	t.eq(f["cases"].size(), 29, "29 cases")
	t.eq(f["cases"].filter(func(c): return c["kind"] == "strand").size(), 29, "every case a strand case")
	t.eq(f["worlds"].size(), 26, "26 worlds")
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

## A value that is not the profile's shape is no mark (serial 99): the story's member missing, null or not a String;
## the event's or the place's an empty string, a number or a Dictionary; the mark a list, a bare id, null, no key.
## Kills: a mark read from whichever members are strings, and one that refuses only the empty string.
func test_a_mark_that_is_not_the_profiles_shape_is_no_mark(t) -> void:
	var harbour: Dictionary = _fixture()["worlds"]["harbour"]
	var m: Dictionary = harbour[OWStrand.MARK]
	var bad := [_without(m, "narrative"), _with(m, "narrative", null), _with(m, "narrative", 7), _with(m, "event", 7),
		_with(m, "location", 7), _with(m, "event", {}), _with(m, "location", []),
		[m["narrative"], m["event"], m["location"]], STORY, null]
	for mark in bad:
		var world := harbour.duplicate(true)
		world[OWStrand.MARK] = mark
		t.eq(OWStrand.strand_of(world, {"rung": "owner"}).to_dict(), EMPTY, var_to_str(mark))
	var none := harbour.duplicate(true)
	none.erase(OWStrand.MARK)
	t.eq(OWStrand.strand_of(none, {"rung": "owner"}).to_dict(), EMPTY, "no key")
	t.done()

## An empty string in the event's or the place's member is neither an id nor unset, so the whole value is no mark
## (ruled for serial 99, the npm and Python readers' reading). Kills: an empty string read as an empty slot.
func test_an_empty_string_member_is_no_mark(t) -> void:
	for member in ["event", "location"]:
		var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
		world[OWStrand.MARK][member] = ""
		t.eq(OWStrand.strand_of(world, {"rung": "owner"}).to_dict(), EMPTY, member)
	t.done()

## Only the story is required (serial 99): the event and the place null or absent read as unset, so a story alone is a
## strand begun, its hero and now read; a place named with no event is an empty place. Kills: an unset member read as
## no mark, and a place read without its event.
func test_a_story_alone_is_a_strand_begun(t) -> void:
	var m: Dictionary = _fixture()["worlds"]["harbour"][OWStrand.MARK]
	for mark in [_with(_with(m, "event", null), "location", null), _without(_without(m, "event"), "location"),
			_with(m, "event", null), _without(m, "event")]:
		var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
		world[OWStrand.MARK] = mark
		var got := OWStrand.strand_of(world, {"rung": "owner"})
		var what := var_to_str(mark)
		t.eq(got.narrative["id"] if got.narrative is Dictionary else null, STORY, what + ": the story")
		t.eq(got.event, null, what + ": no happening")
		t.eq(got.location, null, what + ": a place with no happening is an empty place")
		t.eq(got.character["id"] if got.character is Dictionary else null, "019a7f00-0000-7000-8000-000000000331", what + ": the hero")
		t.eq(got.now["id"] if got.now is Dictionary else null, "019a7f00-0000-7000-8000-000000000322", what + ": now")
		t.eq(got.same, null, what + ": same")
	t.done()

## A multi-link that is not a list is empty (serial 99): the owner's stored story with a bare string in its events
## lists nothing, so the event and the place are empty and the rest reads. Kills: keel's one-item reading.
func test_a_multi_link_that_is_not_a_list_is_empty(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
	for el in world["elements"]:
		if el["id"] == STORY:
			el["events"] = "019a7f00-0000-7000-8000-000000000311"
	var got := OWStrand.strand_of(world, {"rung": "owner"})
	t.eq(got.narrative["id"] if got.narrative is Dictionary else null, STORY, "the story")
	t.eq(got.event, null, "no event")
	t.eq(got.location, null, "no place")
	t.eq(got.character["id"] if got.character is Dictionary else null, "019a7f00-0000-7000-8000-000000000331", "the hero")
	t.done()

## A slot whose element has no name, a null one or one that is not text reads an empty string, never null (serial 99).
func test_a_slot_without_a_name_reads_an_empty_string(t) -> void:
	for name in ["absent", null, 7]:
		var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
		for el in world["elements"]:
			if el["id"] == "019a7f00-0000-7000-8000-000000000322":
				if name is String:
					el.erase("name")
				else:
					el["name"] = name
		t.eq(OWStrand.strand_of(world, {"rung": "owner"}).now,
			{"id": "019a7f00-0000-7000-8000-000000000322", "type": "location", "name": ""}, var_to_str(name))
	t.done()

## A type is matched to a slot trimmed and folded, and the slot says its kind word (serial 134, amendment 1): the story
## stored as " Narrative " fills the slot as narrative. Kills: the stored spelling written.
func test_a_story_stored_in_another_spelling_fills_its_slot_as_narrative(t) -> void:
	var world: Dictionary = _fixture()["worlds"]["harbour"].duplicate(true)
	for el in world["elements"]:
		if el["id"] == STORY:
			el["type"] = " Narrative "
	var want := OWStrand.strand_of(_fixture()["worlds"]["harbour"], {"rung": "owner"}).to_dict()
	var got := OWStrand.strand_of(world, {"rung": "owner"})
	t.eq(got.narrative["type"] if got.narrative is Dictionary else null, "narrative", "the slot's kind word")
	t.eq(got.to_dict(), want, "the strand as for narrative")
	t.done()

## Each filled slot is written {id, type, name}, the page's order (serial 134), its type the slot's kind.
func test_a_filled_slot_is_id_type_name(t) -> void:
	var got := OWStrand.strand_of(_fixture()["worlds"]["harbour"], {"rung": "owner"})
	for slot in ["narrative", "event", "location", "character", "now"]:
		var v: Variant = got.to_dict()[slot]
		t.eq(v.keys() if v is Dictionary else null, ["id", "type", "name"], slot)
	t.eq(got.now["type"], "location", "now a location")
	t.done()

static func _with(m: Dictionary, key: String, value: Variant) -> Dictionary:
	var out := m.duplicate(true)
	out[key] = value
	return out

static func _without(m: Dictionary, key: String) -> Dictionary:
	var out := m.duplicate(true)
	out.erase(key)
	return out

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
