extends RefCounted
## OWMessage on the message profile's conformance fixture (schema-dist profiles/message.fixture.json, the pinned copy
## at dist.89, its sha256 checked against the manifest): every case replayed by name through the reader its kind names,
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
			var mark: Variant = OWMessage.read_mark_of(c["relations"], c["reader"], _members(c))
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
	t.eq(doc["cases"].size(), 87, "87 cases")
	t.eq(counts, {"pair": 10, "addressed": 11, "sent_by": 3, "sender": 14, "unread": 17, "mark": 10, "thread": 4,
		"unseen": 3, "everyone": 3, "edited": 4, "note": 8}, "by kind")
	var names := {}
	for c in doc["cases"]:
		names[c["name"]] = true
	t.eq(names.size(), 87, "every case's name is its own")
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
## recipients are false, keyless or not; the read mark's tie keeps the first.
func test_the_edges_the_packages_pin(t) -> void:
	var msg := {"type": "narrative", "supertype": "Message"}
	t.eq(OWMessage.is_to_everyone(msg.merged({"characters": [""]})), false, "[''] is not everyone")
	t.eq(OWMessage.is_addressed_to(msg.merged({"characters": [""]}), A1), false, "[''] addresses nobody")
	t.eq(OWMessage.is_to_everyone(msg.merged({"characters": "all"})), false, "a string is not a list")
	t.eq(OWMessage.has_unseen_recipients({"type": "narrative", "supertype": "Note"}, true), false, "a Note, keyless")
	t.eq(OWMessage.is_sent_by(msg, ""), false, "an empty id sent nothing")
	var r1 := {"id": "d1", "type": "relation", "supertype": "Read", "actor": A1, "updated_at": "2026-10-26T10:00:00Z"}
	var r2 := {"id": "d2", "type": "relation", "supertype": "Read", "actor": A1, "updated_at": "2026-10-26T10:00:00Z"}
	t.eq(OWMessage.read_mark_of([r1, r2], A1, null)["id"], "d1", "equal times keep the first")
	t.eq(OWMessage.read_mark_of([r1, {"id": "d3", "type": "relation", "supertype": " READ ", "actor": A1,
		"updated_at": "2026-10-26T11:00:00Z"}], A1, null)["id"], "d3", "the mark's word trimmed and folded")
	var loop := [{"id": "x1", "type": "narrative", "supertype": "Message", "parent_narrative": "x2"},
		{"id": "x2", "type": "narrative", "supertype": "Message", "parent_narrative": "x1"}]
	t.eq(OWMessage.thread_of(loop, "r"), [], "a loop that never reaches the root ends")
	t.done()
