extends RefCounted
## OWReport on the report profile's conformance fixture (schema-dist profiles/report.fixture.json, the pinned copy at
## dist.136, its sha256 checked against the manifest): every thread case by name, parents compared whole and in the
## order given, groups and lints each as a set, as the fixture's notes say, and every talk case (serial 135), the
## talks a reader shows a report with, as a set. Beside it, the corners dist.120's fixture
## left open, each a case of dist.121's (named on each test) and kept here to pin the reader beside it: a time with no
## offset, one id given twice, a parent that is no String or an expanded object, a parent with padding; then a caller's
## mistake, and a reading that never changes the bodies.

const REPORT := "res://codegen/schema-dist/profiles/report.fixture.json"
const WORLD := "019a7120-0000-7000-8000-000000000000"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["thread_cases"]:
		out.append(["report:" + c["name"], _case.bind(c)])
	for c in _fixture()["talk_cases"]:
		out.append(["report-talk:" + c["name"], _talks.bind(c)])
	return out

## The fixture's talk_cases (serial 135): the talks on an element a reader shows each Narrative with, as a set.
func _talks(t, c: Dictionary) -> void:
	var got := OWReport.talks_of(c["report"])
	var once := {}
	for x in got:
		once[JSON.stringify(x, "", true)] = true
	t.eq(once.size(), got.size(), "each talk listed once")
	t.eq(_as_set(got), _as_set(c["talks"]), "the talks, as a set")
	t.done()

## A list compared as a set: each entry as JSON with its keys sorted, the list sorted.
static func _as_set(list: Array) -> Array:
	var out := list.map(func(x): return JSON.stringify(x, "", true))
	out.sort()
	return out

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var got := OWReport.threads_of(c["narratives"])
	var want: Dictionary = c["want"]
	t.eq(got.parents, want["parents"], "parents")
	t.eq(got.parents.keys(), want["parents"].keys(), "parents, in the order given")
	t.eq(_as_set(got.groups), _as_set(want["groups"]), "groups, as a set")
	t.eq(_as_set(got.lints), _as_set(want["lints"]), "lints, as a set")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(REPORT), manifest["profiles/report.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "report", "the profile")
	t.eq(f["profile_page"], "profiles/report.md", "its page")
	t.eq(f["pair"], {"type": OWReport.PAIR_TYPE, "supertype": OWReport.REPORT_SUPERTYPE}, "the report's pair")
	t.eq(f["board_pair"], {"type": OWReport.PAIR_TYPE, "supertype": OWReport.BOARD_SUPERTYPE}, "the board entry's pair")
	t.eq(f["mark"]["field"], OWLens.ROOM_MARK, "the mark's field")
	t.eq(f["thread_cases"].size(), 29, "29 thread cases (dist.122)")
	var names := {}
	for c in f["thread_cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 29, "each case named once")
	# The talk list is read whole (serial 135): a case added later must not pass unseen.
	var talks := {}
	for c in f["talk_cases"]:
		talks[c["name"]] = true
	t.eq(f["talk_cases"].size(), 9, "9 talk cases (6 at serial 135, 9 at serial 138)")
	t.eq(talks.size(), 9, "each talk case named once")
	t.eq(get_cases().size(), 38, "every case runs here, one test each")
	t.done()

# -- beside the fixture ------------------------------------------------------------------------------------------------

func _report(id: String, parent: Variant, at: Variant = "2026-10-26T09:00:00Z") -> Dictionary:
	return {"id": id, "type": "narrative", "supertype": "Report", "x_room_of": WORLD, "parent_narrative": parent,
		"relations": [], "created_at": at}

## A created_at with no offset reads as UTC, as the message reader reads it (OWLens.time_key): 09:30:00 is after
## 09:00:00Z and before 09:00:00-01:00 (10:00Z). Compared as text, the bare time would sort last. The fixture's case:
## thread-created-at-with-no-offset-is-read-as-utc.
func test_a_created_at_with_no_offset_reads_as_utc(t) -> void:
	var given := [_report("r1", null), _report("r4", "r1", "2026-10-26T09:00:00-01:00"),
		_report("r2", "r1", "2026-10-26T09:30:00"), _report("r3", "r1", "2026-10-26T09:00:00Z")]
	t.eq(OWReport.threads_of(given).groups, [{"parent": "r1", "kind": "report", "reports": ["r3", "r2", "r4"]}],
		"09:00Z, 09:30 (UTC), 10:00Z")
	t.done()

## One id given twice: the first copy is read and the later one is ignored entirely, neither a report nor a parent.
## The fixture's case: one-id-given-twice-keeps-the-first (two reports); here also a lore copy first.
func test_one_id_given_twice_reads_the_first_copy(t) -> void:
	var lore := {"id": "r1", "type": "narrative", "supertype": "Report", "parent_narrative": null}
	var later := _report("r1", null)
	var got := OWReport.threads_of([lore, later, _report("r2", "r1")])
	t.eq(got.parents, {"r2": "other"}, "the first copy is lore: r1 is no report, and r2's parent is other")
	t.eq(got.groups, [], "no group")
	var first := _report("r3", null)
	var copy := _report("r3", "r9")
	got = OWReport.threads_of([first, _report("r4", "r3"), copy])
	t.eq(got.parents, {"r3": "none", "r4": "report"}, "the later copy's parent is never read")
	t.eq(got.groups, [{"parent": "r3", "kind": "report", "reports": ["r4"]}], "the first copy heads the thread")
	var twice := _report("r5", "r3", "2026-10-26T10:00:00Z")
	got = OWReport.threads_of([first, twice, twice.duplicate()])
	t.eq(got.groups, [{"parent": "r3", "kind": "report", "reports": ["r5"]}], "a report given twice is listed once")
	t.done()

## A parent that is no String reads none and is never matched as text, though an element's id is that text: a number
## (Godot's JSON gives a float), a whole int, true, a list holding the id, and an expanded parent object. The
## fixture's case: parent-that-is-not-a-string (a number, a list, an object).
func test_a_parent_that_is_no_string_reads_none(t) -> void:
	var held := [_report("5", null), _report("r1", null)]
	for parent in [5.0, 5, true, ["r1"], {"id": "r1", "type": "narrative"}]:
		var got := OWReport.threads_of(held + [_report("r2", parent)])
		t.eq(got.parents["r2"], "none", "%s reads none" % var_to_str(parent))
		t.eq(got.groups, [], "%s groups nothing" % var_to_str(parent))
	t.done()

## A parent with content is read as written, never trimmed before the lookup: " r1 " beside a held r1 is missing, and
## a parent that is White_Space only (U+3000 among it) is none, as empty once trimmed is; U+001C is no White_Space.
## The fixture's case: parent-is-a-held-id-with-a-space-at-each-end.
func test_a_parent_with_padding_is_read_as_written(t) -> void:
	var held := [_report("r1", null)]
	var got := OWReport.threads_of(held + [_report("r2", " r1 ")])
	t.eq(got.parents["r2"], "missing", "\" r1 \" is no id given")
	t.eq(got.groups, [], "and groups nothing")
	got = OWReport.threads_of(held + [_report("r2", "r1\n")])
	t.eq(got.parents["r2"], "missing", "a trailing line break is kept")
	got = OWReport.threads_of(held + [_report("r2", " " + String.chr(0x3000) + "\t")])
	t.eq(got.parents["r2"], "none", "White_Space only is none")
	got = OWReport.threads_of(held + [_report("r2", String.chr(0x1C))])
	t.eq(got.parents["r2"], "missing", "U+001C is no White_Space: a parent, and not held")
	got = OWReport.threads_of([_report(" r1 ", null), _report("r2", " r1 ")])
	t.eq(got.groups, [{"parent": " r1 ", "kind": "report", "reports": ["r2"]}], "as written, it names the id written")
	t.done()

## The pair is the room profile's, trimmed and folded; the mark by presence. A board entry is never read as a report.
func test_the_pair_and_the_mark_are_the_room_readers(t) -> void:
	var odd := {"id": "r1", "type": " Narrative ", "supertype": "REPORT", "x_room_of": WORLD}
	var board := {"id": "b1", "type": "narrative", "supertype": "board", "x_room_of": WORLD}
	t.ok(OWReport.is_report(odd), "trimmed and folded")
	t.ok(not OWReport.is_report(board) and OWReport.is_board_entry(board), "a board entry is no report")
	t.ok(not OWReport.is_report(odd.merged({"x_room_of": "  "}, true)), "a blank mark is no mark")
	t.ok(not OWReport.is_report({"id": "m1", "type": "narrative", "supertype": "Message", "x_room_of": WORLD}), "a message")
	var got := OWReport.threads_of([odd, board, _report("r2", "r1"), _report("r3", "b1")])
	t.eq(got.parents, {"r1": "none", "r2": "report", "r3": "board"}, "parents")
	t.eq(_as_set(got.groups), _as_set([{"parent": "r1", "kind": "report", "reports": ["r2"]},
		{"parent": "b1", "kind": "board", "reports": ["r3"]}]), "one thread, one board entry")
	t.done()

## A caller's mistake answers nothing; a row that is no element is passed over; the bodies are never changed.
func test_a_callers_mistake_and_rows_that_are_no_element(t) -> void:
	for bad in [null, "r1", 7, {"id": "r1"}]:
		t.eq(OWReport.threads_of(bad).to_dict(), {"parents": {}, "groups": [], "lints": []}, var_to_str(bad))
	var given := [null, 7, "r1", [], {"id": "", "type": "narrative", "supertype": "Report", "x_room_of": WORLD},
		{"id": 3.0, "type": "narrative", "supertype": "Report", "x_room_of": WORLD}, _report("r1", null), _report("r2", "r1")]
	var before := var_to_str(given)
	var got := OWReport.threads_of(given)
	t.eq(got.parents, {"r1": "none", "r2": "report"}, "only the two with a non-empty String id")
	t.eq(var_to_str(given), before, "the bodies are unchanged")
	t.done()
