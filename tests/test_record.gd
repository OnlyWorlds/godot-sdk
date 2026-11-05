extends RefCounted
## OWRecord on the record profile's conformance fixture (schema-dist profiles/record.fixture.json, the pinned copy at
## dist.108, its sha256 checked against the manifest): every mark case through record_mark_of and every records case
## through records_of, by name. Beside it, what the fixture leaves open: ids ordered by code point where UTF-16 order
## differs, played_at's digits ASCII and its form the whole value, the calendar's edges, the order by the instant past
## the fixture's pairs, each optional member's kind, a name that is not text, a caller's mistake, an element without a
## String id, the review mark's other values, and a reading that never moves the world.

const RECORD := "res://codegen/schema-dist/profiles/record.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(RECORD))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		match c["kind"]:
			"mark":
				out.append(["record:" + c["name"], _mark.bind(c)])
			"records":
				out.append(["record:" + c["name"], _records.bind(c)])
			_:
				out.append(["record:" + c["name"], func(t): t.fail("a case of unknown kind %s" % c["kind"]); t.done()])
	return out

func _elements(c: Dictionary) -> Array:
	return _fixture()["worlds"][c["world"]]["elements"]

func _mark(t, c: Dictionary) -> void:
	var found := _elements(c).filter(func(e): return e["id"] == c["element"])
	t.eq(found.size(), 1, "the case's element is in its world")
	if found.size() == 1:
		t.eq(OWRecord.record_mark_of(found[0]), c["want"], "the mark")
	t.done()

func _records(t, c: Dictionary) -> void:
	t.eq(OWRecord.records_of(c["character"], _elements(c)), c["want"], "the records")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(RECORD), manifest["profiles/record.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "record", "the profile")
	t.eq(f["cases"].size(), 40, "40 cases")
	t.eq(f["cases"].filter(func(c): return c["kind"] == "mark").size(), 29, "29 mark cases")
	t.eq(f["cases"].filter(func(c): return c["kind"] == "records").size(), 11, "11 records cases")
	t.eq(f["mark"]["field"], OWRecord.MARK, "the mark's field")
	t.eq(f["mark"]["members"], OWRecord.MEMBERS, "the mark's members, in order")
	t.done()

## An Event marked for Character "c", played at [param at].
static func _ev(id: Variant, at: Variant, extra := {}) -> Dictionary:
	var e := {"id": id, "type": "event", "name": "E", "characters": ["c"], "x_record": {"tool": "subs", "played_at": at}}
	e.merge(extra, true)
	return e

static func _with_mark(extra: Dictionary) -> Dictionary:
	var e := _ev("e", "2026-11-01T00:30Z")
	e["x_record"].merge(extra, true)
	return e

static func _ids(records: Array) -> Array:
	return records.map(func(r): return r["event"]["id"])

## The page orders ids by code point. U+FF61 is below U+1F600 by code point and above it in UTF-16 (whose surrogate
## pair for U+1F600 starts at 0xD83D), so a UTF-16 order (JavaScript's <) puts them the other way round. No fixture
## case can tell the two apart: its ids are ASCII. Kills: an order by UTF-16 code unit, for the tie and the stories.
func test_ids_order_by_code_point(t) -> void:
	var low := "e" + String.chr(0xFF61)
	var high := "e" + String.chr(0x1F600)
	var got := OWRecord.records_of("c", [_ev(high, "2026-11-01T00:30Z"), _ev(low, "2026-11-01T00:30Z")])
	t.eq(_ids(got), [low, high], "a tie on the instant, by code point")
	var els := [_ev("e", "2026-11-01T00:30Z"),
		{"id": high, "type": "narrative", "name": "h", "protagonist": "c", "events": ["e"]},
		{"id": low, "type": "narrative", "name": "l", "narrator": "c", "events": ["e"]}]
	var one := OWRecord.records_of("c", els)
	var stories: Array = one[0]["stories"] if one.size() == 1 else []
	t.eq(stories.map(func(s): return s["id"]), [low, high], "the stories, by code point")
	t.done()

## The npm SDK 4.124.2's vector (test/record.test.mjs): ties order by code point, never UTF-16. U+FF00 is below
## U+1F600 by code point, and above it in UTF-16 (the surrogate pair starts at 0xD83D), for the Events' tie and for
## the stories. Kills: an order by UTF-16 code unit.
func test_ties_order_by_code_point_npm_vector(t) -> void:
	var emoji := String.chr(0x1F600)
	var bmp := String.chr(0xFF00)
	var at := "2026-11-01T00:00:00Z"
	var els := [
		{"id": "e" + emoji, "type": "event", "name": "hi", "characters": ["c"], "x_record": {"tool": "tangle", "played_at": at}},
		{"id": "e" + bmp, "type": "event", "name": "bmp", "characters": ["c"], "x_record": {"tool": "tangle", "played_at": at}},
		{"id": "n" + emoji, "type": "narrative", "name": "a", "protagonist": "c", "events": ["e" + emoji]},
		{"id": "n" + bmp, "type": "narrative", "name": "b", "protagonist": "c", "events": ["e" + emoji]}]
	var got := OWRecord.records_of("c", els)
	t.eq(_ids(got), ["e" + bmp, "e" + emoji], "the records, a tie by code point")
	var stories: Array = got[1]["stories"] if got.size() == 2 else []
	t.eq(stories.map(func(s): return s["id"]), ["n" + bmp, "n" + emoji], "the second record's stories, by code point")
	t.done()

## played_at's digits are ASCII (RFC 3339's): Arabic-Indic and fullwidth digits are no mark, though Python's \d and
## int() read the first. Kills: a digit test by Unicode category.
func test_played_at_digits_are_ascii(t) -> void:
	var arabic := ""
	for d in [2, 0, 2, 6]:
		arabic += String.chr(0x0660 + d)
	var fullwidth := ""
	for d in [2, 0, 2, 6]:
		fullwidth += String.chr(0xFF10 + d)
	for at in [arabic + "-11-01T00:30Z", fullwidth + "-11-01T00:30Z", "2026-11-01T00:3" + String.chr(0x0660 + 0) + "Z",
			String.chr(0xFF12) + "026-11-01T00:00Z"]:
		t.eq(OWRecord.record_mark_of(_ev("e", at)), null, at)
	t.done()

## played_at is the whole value in the profile's form: nothing after the Z (a regular expression's $ lets a trailing
## newline through), the T and the Z upper case, a fraction only after seconds and never empty, two digits each, four
## for the year. Kills: a $-anchored pattern, a case-folded match, a fraction read without seconds.
func test_played_at_is_the_whole_value(t) -> void:
	for at in ["2026-11-01T00:30Z\n", "2026-11-01T00:30Z ", "2026-11-01T00:30z", "2026-11-01t00:30Z",
			"2026-11-01T00:30.5Z", "2026-11-01T00:30:00.Z", "2026-11-01T00:30:0Z", "2026-11-01T00Z",
			"2026-11-01T0:30Z", "2026-1-01T00:30Z", "12026-11-01T00:30Z", "2026-11-01", "2026-11-01T00:30", "",
			"2026-11-01T00:30:00.5", "2026-11-01T00:30:00.5ZZ", "2026-11-01T00:30:00.5+00:00", 1730421000,
			"2026-11-01T00:00.5Z", "2026-11-01T00:00:00.Z"]:
		t.eq(OWRecord.record_mark_of(_ev("e", at)), null, var_to_str(at))
	for at in ["2026-11-01T00:30Z", "2026-11-01T00:30:00Z", "2026-11-01T00:30:00.5Z", "2026-11-01T00:30:00.123456789Z"]:
		var mark: Variant = OWRecord.record_mark_of(_ev("e", at))
		t.eq(mark["played_at"] if mark is Dictionary else null, at, at + " is kept as written")
	t.done()

## The calendar's edges past the fixture's: Gregorian centuries (1900 no leap year, 2000 one), a 31st in a 30-day
## month, month 0 and 13, day 0, minute 60, and year 0001 and the last instant of a year as marks. Kills: a leap year
## by four alone, one month length for every month.
func test_the_calendar(t) -> void:
	for at in ["1900-02-29T00:00Z", "2026-04-31T00:00Z", "2026-13-01T00:00Z", "2026-00-01T00:00Z", "2026-11-00T00:00Z",
			"2026-11-01T00:60Z", "2026-10-31T23:59:60Z", "2026-11-32T00:00Z"]:
		t.eq(OWRecord.record_mark_of(_ev("e", at)), null, at + " is no mark")
	for at in ["2000-02-29T00:00Z", "2024-02-29T12:00Z", "0001-01-01T00:00Z", "9999-12-31T23:59:59.999Z",
			"2026-12-31T23:59:59Z", "2026-04-30T00:00Z"]:
		t.ok(OWRecord.record_mark_of(_ev("e", at)) != null, at + " is a mark")
	t.done()

## The order is the instant: a fraction is the leading digits of a second (.5 is 500 ms, after .499), a minute
## without seconds is its first second, and years are counted from 0001. Kills: a fraction read as a whole number, an
## order by the string, a year read in two digits.
func test_the_order_is_the_instant(t) -> void:
	var els := [_ev("a", "2026-11-01T00:30:00.499Z"), _ev("b", "2026-11-01T00:30:00.5Z"), _ev("c", "2026-11-01T00:31Z"),
		_ev("d", "2026-11-01T00:30:59.999Z"), _ev("e", "0001-01-01T00:00Z"), _ev("f", "0099-12-31T23:59:59Z"),
		_ev("g", "2025-12-31T23:59:59.9999Z"), _ev("h", "2026-01-01T00:00Z")]
	t.eq(_ids(OWRecord.records_of("c", els)), ["c", "d", "b", "a", "h", "g", "f", "e"], "newest first")
	t.done()

## Each optional member's kind: a version or seed of any string (the empty one too) is a mark, a number or a bool is
## none; seats an empty object or null reads {}; a tool of 32 and of 1 is a mark, of 33, 0 or with an underscore none;
## an outcome with a digit none.
func test_each_member_its_kind(t) -> void:
	for extra in [{"version": ""}, {"seed": ""}, {"seats": {}}, {"seats": null}, {"tool": "a".repeat(32)}, {"tool": "a"},
			{"tool": "a-1"}, {"outcome": "z"}]:
		t.ok(OWRecord.record_mark_of(_with_mark(extra)) != null, var_to_str(extra) + " is a mark")
	var seatless: Variant = OWRecord.record_mark_of(_with_mark({"seats": null}))
	t.eq(seatless["seats"] if seatless is Dictionary else null, {}, "seats null reads {}")
	for extra in [{"version": 1}, {"version": true}, {"seed": 5.5}, {"seed": false}, {"seats": "x"}, {"seats": {"c": null}},
			{"tool": "a".repeat(33)}, {"tool": ""}, {"tool": "a_b"}, {"tool": 7}, {"tool": null}, {"outcome": "won1"},
			{"outcome": "w o"}, {"played_at": null}]:
		t.eq(OWRecord.record_mark_of(_with_mark(extra)), null, var_to_str(extra) + " is no mark")
	t.done()

## A name that is not text, null or absent reads "", on the Event and on a story (the packages' reading; keel's keeps
## a non-string name as served).
func test_a_name_that_is_not_text_reads_empty(t) -> void:
	for name in [7, null, "absent"]:
		var ev := _ev("e", "2026-11-01T00:30Z")
		var story := {"id": "n", "type": "narrative", "protagonist": "c", "events": ["e"]}
		if name is String:
			ev.erase("name")
		else:
			ev["name"] = name
			story["name"] = name
		var got := OWRecord.records_of("c", [ev, story])
		t.eq(got[0]["event"] if got.size() == 1 else null, {"id": "e", "name": ""}, var_to_str(name) + ": the event's name")
		t.eq(got[0]["stories"] if got.size() == 1 else null, [{"id": "n", "name": "", "as": "protagonist"}],
			var_to_str(name) + ": the story's name")
	t.done()

## A caller's mistake reads an empty list (GDScript has no exceptions; the packages raise): an id that is not a
## String, elements that are not an Array. An element that is not a Dictionary is skipped, and record_mark_of reads
## no mark from anything but a Dictionary.
func test_a_callers_mistake_reads_empty(t) -> void:
	var els := [_ev("e", "2026-11-01T00:30Z")]
	t.eq(OWRecord.records_of(null, els), [], "a null id")
	t.eq(OWRecord.records_of(7, els), [], "a number id")
	t.eq(OWRecord.records_of("c", null), [], "null elements")
	t.eq(OWRecord.records_of("c", {"e": els[0]}), [], "a Dictionary of elements")
	t.eq(_ids(OWRecord.records_of("c", [null, "e", 7, els[0], []])), ["e"], "what is not an element is skipped")
	for v in [null, "x_record", 7, [], {}]:
		t.eq(OWRecord.record_mark_of(v), null, var_to_str(v))
	t.done()

## An Event or a story without a String id is skipped: it can be neither ordered nor linked (keel and the Python
## package raise on a missing id; npm carries it as undefined). The profile does not say.
func test_an_element_without_a_string_id_is_skipped(t) -> void:
	var no_id := _ev("x", "2026-11-01T00:30Z")
	no_id.erase("id")
	var els := [no_id, _ev(5, "2026-11-01T00:30Z"), _ev("e", "2026-11-01T00:30Z"),
		{"id": 9, "type": "narrative", "protagonist": "c", "events": ["e"]},
		{"type": "narrative", "protagonist": "c", "events": ["e"]}]
	var got := OWRecord.records_of("c", els)
	t.eq(_ids(got), ["e"], "only the Event with an id")
	t.eq(got[0]["stories"] if got.size() == 1 else null, [], "no story without an id")
	t.done()

## The review mark as the review profile's proposedMarkOf reads it (serial 103, reader rule 1): a Dictionary with a key
## is proposed, on the run and on the story; null, an empty mark ({}, "", White_Space only, []) and a value that is not
## a Dictionary (false, 0, a word, a list with an entry) are settled, as the npm and Python readers read them. The type
## is the served "event" and "narrative" exactly, as the three readers read it.
func test_what_is_proposed_and_what_is_an_event(t) -> void:
	for v in [{"by": "k"}, {"x": null}]:
		t.eq(OWRecord.records_of("c", [_ev("e", "2026-11-01T00:30Z", {"x_review_proposed": v})]), [], var_to_str(v) + " on the run")
		var story := {"id": "n", "type": "narrative", "protagonist": "c", "events": ["e"], "x_review_proposed": v}
		var got := OWRecord.records_of("c", [_ev("e", "2026-11-01T00:30Z"), story])
		t.eq(got[0]["stories"] if got.size() == 1 else null, [], var_to_str(v) + " on the story")
	for v in [null, {}, "", " \t", [], false, 0, "yes", ["k"], true]:
		var story := {"id": "n", "type": "narrative", "protagonist": "c", "events": ["e"], "x_review_proposed": v}
		var got := OWRecord.records_of("c", [_ev("e", "2026-11-01T00:30Z", {"x_review_proposed": v}), story])
		t.eq(_ids(got), ["e"], var_to_str(v) + " on the run is settled")
		t.eq(got[0]["stories"].size() if got.size() == 1 else null, 1, var_to_str(v) + " on the story is settled")
	t.eq(OWRecord.record_mark_of(_ev("e", "2026-11-01T00:30Z", {"type": "Event"})), null, "Event is not the served type")
	t.eq(OWRecord.record_mark_of(_ev("e", "2026-11-01T00:30Z", {"type": "character"})), null, "a Character's mark")
	t.done()

## One Event is one record, whoever it names twice; a story names the Character by protagonist or narrator alone
## (not by its characters), and a story naming another Character is not theirs.
func test_one_event_one_record(t) -> void:
	var els := [_ev("e", "2026-11-01T00:30Z", {"characters": ["c", "c"]}),
		{"id": "n1", "type": "narrative", "characters": ["c"], "events": ["e"]},
		{"id": "n2", "type": "narrative", "protagonist": "d", "narrator": "d", "events": ["e"]},
		{"id": "n3", "type": "narrative", "protagonist": "c", "narrator": "d", "events": ["e"]}]
	var got := OWRecord.records_of("c", els)
	t.eq(_ids(got), ["e"], "one record")
	t.eq(got[0]["stories"] if got.size() == 1 else null, [{"id": "n3", "name": "", "as": "protagonist"}],
		"the protagonist's story alone")
	t.done()

## npm 4.124.1's test (test/record.test.mjs): a Narrative naming an Event twice is one story of it, other values in
## events name none, and no two records share a story (a story is a Dictionary, shared by reference unless copied per
## record). Kills: a story per mention, a non-String entry read as a name, one story Dictionary handed to two records.
func test_a_narrative_naming_an_event_twice_is_one_story(t) -> void:
	var c := "019a8000-0000-7000-8000-000000000101"
	var mk := func(id: String, at: String) -> Dictionary:
		return {"id": id, "type": "event", "name": id, "characters": [c], "x_record": {"tool": "tangle", "played_at": at}}
	var world := [mk.call("e1", "2026-11-02T00:00:00Z"), mk.call("e2", "2026-11-01T00:00:00Z"),
		{"id": "n1", "type": "narrative", "name": "One", "protagonist": c, "events": ["e1", "e1", "e2"]},
		{"id": "n2", "type": "narrative", "name": "Two", "narrator": c, "events": [7, null, {}, ["e1"], "e1"]}]
	var got := OWRecord.records_of(c, world)
	t.eq(got.map(func(r): return [r["event"]["id"], r["stories"].map(func(s): return "%s:%s" % [s["id"], s["as"]])]),
		[["e1", ["n1:protagonist", "n2:narrator"]], ["e2", ["n1:protagonist"]]], "one story per Narrative and Event")
	if got.size() == 2:
		got[0]["stories"][0]["name"] = "planted"
		t.eq(got[1]["stories"][0]["name"], "One", "no two records share a story")
	t.done()

## Reading never moves the world, and what it answers is the caller's own: a changed mark, seat or entry is not the
## element's, nor the next reading's.
func test_a_reading_never_moves_the_world(t) -> void:
	var els: Array = _fixture()["worlds"]["harbour"]["elements"].duplicate(true)
	var before := var_to_str(els)
	var who := "019a8000-0000-7000-8000-000000000101"
	var got := OWRecord.records_of(who, els)
	t.ok(not got.is_empty(), "a reading")
	if not got.is_empty():
		got[0]["event"]["name"] = "planted"
		got[0]["stories"].append({"id": "x", "name": "x", "as": "both"})
	var mark: Variant = OWRecord.record_mark_of(els.filter(func(e): return e["id"] == "019a8000-0000-7000-8000-000000000201")[0])
	t.ok(mark is Dictionary, "a mark")
	if mark is Dictionary:
		mark["seats"]["planted"] = "planted"
	t.eq(var_to_str(els), before, "the elements unmoved")
	var again := OWRecord.records_of(who, els)
	t.ok(again.is_empty() or again[0]["event"]["name"] != "planted", "the next reading its own")
	t.done()
