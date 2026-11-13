extends RefCounted
## OWMessage on the message profile's conformance fixture (schema-dist profiles/message.fixture.json, the pinned copy
## at dist.121, its sha256 checked against the manifest): every case replayed by name through the reader its kind names,
## the fixture's pairs held equal to the reader's constants, and then what the fixture leaves open, as the profile's
## text and the npm and Python packages answer it.

const MESSAGE := "res://codegen/schema-dist/profiles/message.fixture.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(MESSAGE))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["message:" + c["name"], _case.bind(c)])
	return out

## The members list a case reads: its own when it carries the key (null: a reader with no list), else the world's.
func _members(c: Dictionary) -> Variant:
	return c["members"] if c.has("members") else _fixture()["members"]

func _ids(list: Array) -> Array:
	return list.map(func(m): return m.get("id"))

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	match c["kind"]:
		"pair":
			t.eq(OWMessage.is_message(c["element"]), c["is_message"], "is_message")
		"addressed":
			t.eq(OWMessage.is_addressed_to(c["message"], c["character"]), c["addressed"], "is_addressed_to")
		"sent_by":
			t.eq(OWMessage.is_sent_by(c["message"], c["character"]), c["sent_by"], "is_sent_by")
		"sender":
			var s := OWMessage.sender_status(c["message"], _members(c))
			t.eq(s.status, c["status"], "status")
			t.eq(s.claimed, c["claimed"], "claimed")
			t.eq(s.written_by, c.get("written_by"), "written_by")
		"unread":
			t.eq(_ids(OWMessage.unread_for(c["messages"], c["reader"], c["read_mark"], _members(c))), c["unread"], "unread_for")
		"mark":
			# A case without keyless has a credential, or is a folder.
			var mark: Variant = OWMessage.read_mark_of(c["relations"], c["reader"], _members(c), c.get("keyless") == true)
			t.eq(mark.get("id") if mark is Dictionary else mark, c["mark"], "read_mark_of")
		"thread":
			t.eq(_ids(OWMessage.thread_of(c["messages"], c["root"])), c["thread"], "thread_of")
		"unseen":
			t.eq(OWMessage.is_addressed_to(c["message"], c["character"]), c["addressed"], "is_addressed_to")
			t.eq(OWMessage.has_unseen_recipients(c["message"]), c["unseen_recipients"], "has_unseen_recipients")
		"everyone":
			t.eq(OWMessage.is_to_everyone(c["message"], c["keyless"]), c["to_everyone"], "is_to_everyone")
			t.eq(OWMessage.has_unseen_recipients(c["message"], c["keyless"]), c["unseen_recipients"], "has_unseen_recipients")
		"edited":
			var e := OWMessage.edited_by(c["message"], _members(c))
			t.eq(e.edited, c["edited"], "edited")
			t.eq(e.by, c["edited_by"], "by")
		"note":
			t.eq(OWMessage.note_of(c["notes"], c["character"], _members(c)), c["line"], "note_of")
		_:
			t.fail("a case of unknown kind %s" % c["kind"])
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(MESSAGE), manifest["profiles/message.fixture.json"], "the fixture's bytes are the dist's")
	var doc := _fixture()
	t.eq(doc["profile"], "message", "the profile")
	var counts := {}
	for c in doc["cases"]:
		counts[c["kind"]] = counts.get(c["kind"], 0) + 1
	t.eq(doc["cases"].size(), 93, "93 cases (dist.121)")
	t.eq(counts, {"pair": 10, "addressed": 11, "sent_by": 3, "sender": 14, "unread": 22, "mark": 11, "thread": 4,
		"unseen": 3, "everyone": 3, "edited": 4, "note": 8}, "by kind")
	var names := {}
	for c in doc["cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 93, "every case's name is its own")
	t.done()

func test_the_pairs_are_the_fixtures(t) -> void:
	var f := _fixture()
	t.eq({"type": OWMessage.PAIR_TYPE, "supertype": OWMessage.PAIR_SUPERTYPE}, f["pair"], "the message pair")
	t.eq({"type": OWMessage.PAIR_TYPE, "supertype": OWMessage.NOTE_SUPERTYPE}, f["note_pair"], "the Note pair")
	t.eq({"type": OWMessage.READ_MARK_TYPE, "supertype": OWMessage.READ_MARK_SUPERTYPE,
		"name": OWMessage.READ_MARK_NAME_PREFIX + "<the reader's name>", "reader_field": OWMessage.READ_MARK_READER_FIELD,
		"messages_field": OWMessage.READ_MARK_MESSAGES_FIELD}, f["read_mark"], "the read mark")
	t.done()

# -- what the fixture leaves open, as the profile's text and the npm and Python packages read it ------------------------

const A1 := "019a3b10-0000-7000-8000-0000000000a1"
const A2 := "019a3b10-0000-7000-8000-0000000000a2"
const B2 := "019a3b10-0000-7000-8000-0000000000b2"

func _note(id: String, at: String, extra: Dictionary = {}) -> Dictionary:
	var n := {"id": id, "type": "narrative", "supertype": "Note", "narrator": A2, "created_by": B2, "characters": [],
		"created_at": at}
	n.merge(extra, true)
	return n

## The profile: a Note is not the line when proposed, "x_review_proposed an object"; the packages read it through
## proposedMarkOf / proposed_mark_of (an object with something in it). A doubt (a string, a list) and an empty mark
## leave the Note shown; a reader that hands a world on reads the doubt otherwise (OWLens.is_proposed).
func test_a_note_is_proposed_only_by_an_object(t) -> void:
	var older := _note("n1", "2026-10-26T09:00:00Z")
	for mark in ["yes", ["x"], 1.0, {}, "", "  "]:
		var newer := _note("n2", "2026-10-26T11:00:00Z", {"x_review_proposed": mark})
		t.eq(OWMessage.note_of([older, newer], A2, _fixture()["members"]), "n2", "the newer stands with a mark of %s" % var_to_str(mark))
	var proposed := _note("n2", "2026-10-26T11:00:00Z", {"x_review_proposed": {"by": B2}})
	t.eq(OWMessage.note_of([older, proposed], A2, _fixture()["members"]), "n1", "an object proposes it")
	t.done()

## The hidden mark: any value but absent, null and false (npm isHiddenMark, Python is_hidden); Godot reads a JSON 0 as
## 0.0, which is not false either.
func test_a_note_is_hidden_by_any_mark_but_null_and_false(t) -> void:
	var older := _note("n1", "2026-10-26T09:00:00Z")
	for mark in [true, 0.0, 1.0, "", [], {}]:
		var newer := _note("n2", "2026-10-26T11:00:00Z", {"hidden": mark})
		t.eq(OWMessage.note_of([older, newer], A2, _fixture()["members"]), "n1", "hidden %s leaves it out" % var_to_str(mark))
	for mark in [null, false]:
		var newer := _note("n2", "2026-10-26T11:00:00Z", {"hidden": mark})
		t.eq(OWMessage.note_of([older, newer], A2, _fixture()["members"]), "n2", "hidden %s is not hidden" % var_to_str(mark))
	t.done()

## The newest Note: a readable time beats an unreadable one; equal times, the later in the list; none readable, the last.
func test_the_newest_note_by_the_order(t) -> void:
	var m: Array = _fixture()["members"]
	t.eq(OWMessage.note_of([_note("n1", "2026-10-26T09:00:00Z"), _note("n2", "yesterday")], A2, m), "n1", "readable beats unreadable")
	t.eq(OWMessage.note_of([_note("n1", "2026-10-26T09:00:00Z"), _note("n2", "2026-10-26T09:00:00Z")], A2, m), "n2", "a tie, the later")
	t.eq(OWMessage.note_of([_note("n1", "x"), _note("n2", "y")], A2, m), "n2", "none readable, the last")
	t.eq(OWMessage.note_of([_note("n1", "2026-10-26T09:00:00Z")], "", m), null, "an empty id has no line")
	t.done()

func test_recipients_of(t) -> void:
	t.eq(OWMessage.recipients_of({"type": "narrative", "supertype": "Message", "characters": [A1, "", 3.0, A2]}), [A1, A2], "ids only, in order")
	t.eq(OWMessage.recipients_of({"type": "narrative", "supertype": "Message"}), [], "absent is empty")
	t.eq(OWMessage.recipients_of({"type": "narrative", "supertype": "Message", "characters": null}), [], "null is empty")
	t.eq(OWMessage.recipients_of({"type": "narrative", "supertype": "Note", "characters": [A1]}), [], "a Note has none")
	t.done()

## A list that names no valid id, or a value that is not a list, addresses nobody, never everyone; a Note's unseen
## recipients are false, keyless or not; the read mark's tie goes to the higher id.
func test_the_edges_the_packages_pin(t) -> void:
	var msg := {"type": "narrative", "supertype": "Message"}
	t.eq(OWMessage.is_to_everyone(msg.merged({"characters": [""]})), false, "[''] is not everyone")
	t.eq(OWMessage.is_addressed_to(msg.merged({"characters": [""]}), A1), false, "[''] addresses nobody")
	t.eq(OWMessage.is_to_everyone(msg.merged({"characters": "all"})), false, "a string is not a list")
	t.eq(OWMessage.has_unseen_recipients({"type": "narrative", "supertype": "Note"}, true), false, "a Note, keyless")
	t.eq(OWMessage.is_sent_by(msg, ""), false, "an empty id sent nothing")
	var r1 := {"id": "d1", "type": "relation", "supertype": "Read", "actor": A1, "updated_at": "2026-10-26T10:00:00Z"}
	var r2 := {"id": "d2", "type": "relation", "supertype": "Read", "actor": A1, "updated_at": "2026-10-26T10:00:00Z"}
	t.eq(OWMessage.read_mark_of([r1, r2], A1, null)["id"], "d2", "equal times, the higher id")
	t.eq(OWMessage.read_mark_of([r1, {"id": "d3", "type": "relation", "supertype": " READ ", "actor": A1,
		"updated_at": "2026-10-26T11:00:00Z"}], A1, null)["id"], "d3", "the mark's word trimmed and folded")
	var loop := [{"id": "x1", "type": "narrative", "supertype": "Message", "parent_narrative": "x2"},
		{"id": "x2", "type": "narrative", "supertype": "Message", "parent_narrative": "x1"}]
	t.eq(OWMessage.thread_of(loop, "r"), [], "a loop that never reaches the root ends")
	t.done()

func _mark(id: String, at: Variant) -> Dictionary:
	var rel := {"id": id, "type": "relation", "supertype": "Read", "actor": A1}
	if not (at is String and at == ABSENT):
		rel["updated_at"] = at
	return rel

## The message page's read mark (serial 123): of two marks, one whose updated_at cannot be read never wins; two that
## can be read and are the same instant, an instant written two ways included, tie by the higher id, compared by code
## point as written. Each pair in both list orders, so no answer depends on the order.
func test_the_read_mark_tie_goes_to_the_higher_id_in_either_order(t) -> void:
	var a := "aaaaaaaa-0000-4000-8000-00000000000a"
	var b := "aaaaaaaa-0000-4000-8000-00000000000b"
	var pairs := [
		["the same text", _mark(a, "2026-10-26T10:00:00Z"), _mark(b, "2026-10-26T10:00:00Z"), b],
		["one instant written two ways", _mark(a, "2026-10-26T11:00:00+01:00"), _mark(b, "2026-10-26T10:00:00Z"), b],
		["two ways, the other way", _mark(a, "2026-10-26T10:00:00Z"), _mark(b, "2026-10-26T11:00:00+01:00"), b],
		["a newer lower id still wins", _mark(a, "2026-10-26T10:00:01Z"), _mark(b, "2026-10-26T10:00:00Z"), a],
		["a lower id, the higher unreadable", _mark(a, "2026-10-26T10:00:00Z"), _mark(b, "garbage"), a],
		["a lower id, the higher absent", _mark(a, "2026-10-26T10:00:00Z"), _mark(b, ABSENT), a],
		["a lower id, the higher a date alone", _mark(a, "2026-10-26T10:00:00Z"), _mark(b, "2026-10-26"), a],
		["upper case is lower by code point", _mark("aaaaaaaa-0000-4000-8000-00000000000A", "2026-10-26T10:00:00Z"),
			_mark(a, "2026-10-26T10:00:00Z"), a],
	]
	for p in pairs:
		t.eq(OWMessage.read_mark_of([p[1], p[2]], A1, null)["id"], p[3], p[0] + ", listed first to last")
		t.eq(OWMessage.read_mark_of([p[2], p[1]], A1, null)["id"], p[3], p[0] + ", listed last to first")
	t.done()

# -- created_at as the message reader reads it: OWLens.time_key, through unread_for's order -----------------------------

## A message addressed to "a1" by "a3", no created_by (a folder's): unread for a1, whatever its time. [param at] is
## its created_at; ABSENT leaves the key out.
const ABSENT := "<absent>"

func _timed(id: String, at: Variant) -> Dictionary:
	var m := {"id": id, "type": "narrative", "supertype": "Message", "name": id, "story": "", "narrator": "a3",
		"characters": ["a1"]}
	if not (at is String and at == ABSENT):
		m["created_at"] = at
	return m

func _unread_ids(given: Array) -> Array:
	return _ids(OWMessage.unread_for(given, "a1", null, null))

func _reversed(list: Array) -> Array:
	var out := list.duplicate()
	out.reverse()
	return out

## The TypeScript SDK's message edge case created-at-order-and-the-readable-rule, its 28 created_at texts in its
## order and its wanted order: a time with no offset reads as UTC, a fraction counts to its sixth digit (later digits
## dropped, never rounded), equal instants keep the list's order, and an unreadable time (a date alone among them)
## comes after every readable one, in the list's order.
func test_a_time_with_no_offset_is_utc_and_a_fraction_counts_to_its_sixth_digit(t) -> void:
	var texts := [["t01", "2026-10-26T10:00:00Z"], ["t02", "2026-10-26T12:00:00+02:00"], ["t03", "2026-10-26t09:00:00z"],
		["t04", "2026-10-26T09:30:00"], ["t05", "2026-10-26T09:30:00.5Z"], ["t06", "2026-10-26T09:30:00.000001Z"],
		["t07", "2026-02-29T00:00:00Z"], ["t08", "2024-02-29T00:00:00Z"], ["t09", "2026-10-26"],
		["t10", "2026-10-26 10:00:00Z"], ["t11", " 2026-10-26T10:00:00Z"], ["t12", "2026-10-26T24:00:00Z"],
		["t13", "2026-10-26T23:59:60Z"], ["t14", "2026-10-26T10:00:00+24:00"], ["t15", "2026-10-26T10:00Z"],
		["t16", "2026-10-26T10:00:00,5Z"], ["t17", null], ["t18", ABSENT], ["t19", 5], ["t20", "yesterday"],
		["t21", "0000-01-01T00:00:00+01:00"], ["t22", "9999-12-31T23:59:59.9999999Z"],
		["t23", "2026-10-26T09:30:00.0000005Z"], ["t24", "2026-10-26T10:00:00-00:30"], ["t25", "2026-10-26T09:61:00Z"],
		["t26", "2026-1-26T10:00:00Z"],
		["t27", String.chr(0xFF12) + String.chr(0xFF10) + String.chr(0xFF12) + String.chr(0xFF16) + "-10-26T10:00:00Z"],
		["t28", "2026-10-26T10:00:00Z\n"]]
	var given := texts.map(func(p): return _timed(p[0], p[1]))
	t.eq(_unread_ids(given), ["t21", "t08", "t03", "t04", "t23", "t06", "t05", "t01", "t02", "t24", "t22", "t07", "t09",
		"t10", "t11", "t12", "t13", "t14", "t15", "t16", "t17", "t18", "t19", "t20", "t25", "t26", "t27", "t28"],
		"the edge case's order")
	var z := "2026-10-26T09:00:00Z"
	var bare := "2026-10-26T09:30:00"
	var half := "2026-10-26T09:30:00.0000005Z"
	var micro := "2026-10-26T09:30:00.000001Z"
	t.eq(OWLens.time_key(bare), OWLens.time_key("2026-10-26T09:30:00Z"), "no offset reads as UTC")
	t.eq(OWLens.time_key(bare) - OWLens.time_key(z), 1800 * 1000000, "half an hour after 09:00Z")
	t.eq(OWLens.time_key(half), OWLens.time_key(bare), "the seventh digit is dropped: the same instant as 09:30:00")
	t.eq(OWLens.time_key(micro) - OWLens.time_key(bare), 1, "the sixth digit counts: one microsecond later")
	t.eq(OWLens.time_key("2026-10-26"), null, "a date alone is unreadable")
	var four := [_timed("bare", bare), _timed("z", z), _timed("half", half), _timed("micro", micro),
		_timed("date", "2026-10-26")]
	t.eq(_unread_ids(four), ["z", "bare", "half", "micro", "date"], "as given: the equal two keep the list's order")
	t.eq(_unread_ids(_reversed(four)), ["z", "half", "bare", "micro", "date"], "reversed: the equal two keep it again")
	t.done()

## The year's two ends: year 0000 reads, and an offset may carry an instant before it or past the end of 9999. The
## leap rule is taken on the year number as written, so 0000 is a leap year and its 29 February reads. The seconds
## since 1970 are the TypeScript SDK 4.159.0's and onlyworlds 0.120.0's for the same texts; time_key holds
## microseconds in a 64-bit int, with no float on its path.
func test_the_years_two_ends_order_as_instants_with_the_packages_seconds(t) -> void:
	var times := [["E1", "9999-12-31T23:00:00-02:00", 253402304400], ["E2", "0000-01-01T00:00:00Z", -62167219200],
		["R", "2026-11-12T10:00:00Z", 1794477600], ["E3", "0000-01-01T00:00:00+01:00", -62167222800],
		["L", "0000-02-29T00:00:00Z", -62162121600]]
	for e in times:
		var key: Variant = OWLens.time_key(e[1])
		t.ok(key is int, "%s %s is an int, not a float" % [e[0], e[1]])
		t.eq(key, e[2] * 1000000, "%s %s" % [e[0], e[1]])
	var given := times.map(func(e): return _timed(e[0], e[1]))
	t.eq(_unread_ids(given), ["E3", "E2", "L", "R", "E1"], "as given")
	t.eq(_unread_ids(_reversed(given)), ["E3", "E2", "L", "R", "E1"], "reversed")
	t.done()

## The forms, a row each: what reads and what does not. A readable row sorts before a message at 11:00Z, an
## unreadable one after it.
func test_the_forms_of_a_time_read_or_do_not(t) -> void:
	var at_ten := 1794477600 * 1000000
	var rows := [
		["lower-case t and z", "2026-11-12t10:00:00z", at_ten],
		["a ten-digit fraction", "2026-11-12T10:00:00.1234567891Z", at_ten + 123456],
		["a space for the T", "2026-11-12 10:00:00Z", null],
		["no seconds", "2026-11-12T10:00Z", null],
		["an offset without its colon", "2026-11-12T12:00:00+0200", null],
		["30 February", "2026-02-30T10:00:00Z", null],
		["hour 24", "2026-11-12T24:00:00Z", null],
		["second 60", "2026-11-12T10:00:60Z", null],
		["an offset of 24 hours", "2026-11-12T10:00:00+24:00", null],
		["a time followed by a line break", "2026-11-12T10:00:00Z\n", null],
	]
	for r in rows:
		t.eq(OWLens.time_key(r[1]), r[2], r[0])
		var want := ["row", "eleven"] if r[2] != null else ["eleven", "row"]
		t.eq(_unread_ids([_timed("eleven", "2026-11-12T11:00:00Z"), _timed("row", r[1])]), want, r[0] + ", sorted")
	t.done()
