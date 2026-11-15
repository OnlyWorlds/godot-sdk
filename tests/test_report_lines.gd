extends RefCounted
## OWReport.read_line and read_lines on the report profile's lines fixture (schema-dist
## profiles/report-lines.fixture.json, rule 10, the pinned copy at dist.129, its sha256 checked against the manifest),
## read in the world its [code]world[/code] names: every case one line as it stands (its address and words), every
## text the lines it splits into, in order, each with its line, address and words; each compared exactly, character for
## character. [code]kind[/code], [code]status[/code] and [code]about[/code] are notes, never compared. Beside it, the
## npm package's own tests of the world: left out, and compared as given.

const LINES := "res://codegen/schema-dist/profiles/report-lines.fixture.json"
const ID := "01a1d4ef-0000-7000-8000-000000000084"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(LINES))
	return _doc

func _world() -> String:
	return _fixture()["world"]

func get_cases() -> Array:
	var out := []
	var cases: Array = _fixture()["cases"]
	for i in cases.size():
		out.append(["report-lines:case %03d %s" % [i, cases[i]["kind"]], _line.bind(cases[i])])
	var texts: Array = _fixture()["texts"]
	for i in texts.size():
		out.append(["report-lines:text %02d %s" % [i, texts[i]["kind"]], _text.bind(texts[i])])
	return out

func _line(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var line: String = c["line"]
	var got := OWReport.read_line(line, _world())
	t.eq(got.line, line, "the line as read")
	t.eq(got.address, c["address"], "the address")
	t.eq(got.words, c["words"], "the words")
	if c["address"] == null:
		t.ok(got.reading == null, "no reading without an address")
		t.ok(got.start == null and got.end == null, "no place without an address")
	elif got.reading != null and got.start is int and got.end is int:
		# The address as written stands at start..end (code points) and reads as the element named.
		var slice := line.substr(got.start, got.end - got.start)
		var r := OWAddress.parse_link(slice)
		t.ok(r.ok, "the slice reads as an address: " + slice)
		t.eq(r.to_dict(), got.reading.to_dict(), "the slice's reading is the line's")
		t.eq("ow://%s/%s" % [got.reading.type, got.reading.id], c["address"], "the address is the reading's")
	else:
		t.fail("an address with no reading or no place")
	t.done()

func _text(t, x: Dictionary) -> void:
	var want := []
	for l in x["lines"]:
		want.append([l["line"], l["address"], l["words"]])
	var got := []
	for l in OWReport.read_lines(x["text"], _world()):
		got.append([l.line, l.address, l.words])
	t.eq(got, want, "the lines, in order, each with its line, address and words")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(LINES), manifest["profiles/report-lines.fixture.json"], "the fixture's bytes are the dist's")
	var f := _fixture()
	t.eq(f["profile"], "report", "the profile")
	t.eq(f["table"], "lines", "the table")
	t.eq(f["cases"].size(), 101, "101 cases (dist.129)")
	t.eq(f["texts"].size(), 16, "16 texts (dist.129)")
	t.eq(get_cases().size(), 117, "every case and every text runs here, one test each")
	var none := false
	var whole := false
	var cut := false
	for c in f["cases"]:
		none = none or c["address"] == null
		whole = whole or (c["address"] != null and c["words"] == c["line"])
		cut = cut or (c["address"] != null and c["words"] != c["line"])
	t.ok(none and whole and cut, "rows of each kind: no address, shown whole, shown without it")
	t.done()

# -- beside the fixture ------------------------------------------------------------------------------------------------

func test_without_a_world_only_an_address_with_no_world_is_the_lines(t) -> void:
	var w := _world()
	t.eq(OWReport.read_line("Built: ow://%s/object/%s" % [w, ID]).address, null, "a world named, none given")
	t.eq(OWReport.read_line("Built: ow://object/%s" % ID).address, "ow://object/" + ID, "no world named")
	t.eq(OWReport.read_line("Built: ow://object/%s" % ID, null).words, "Built", "null is no world")
	t.eq(OWReport.read_line("Built: ow://%s/object/%s" % [w, ID], w).address, "ow://object/" + ID, "this world")
	t.done()

func test_the_world_is_compared_as_given(t) -> void:
	var w := _world()
	t.eq(OWReport.read_line("Built: ow://%s/object/%s" % [w, ID], w.to_upper()).address, null, "an upper-case world id names no world here")
	t.eq(OWReport.read_line("Built: ow://%s/object/%s" % [w, ID], 7).address, null, "a world that is no String is none")
	t.done()

func test_read_lines_splits_at_cr_and_lf_only(t) -> void:
	var text := "Built: ow://object/%s\r\n\r\n  nothing changed%sstill\n%s\n" % [ID, String.chr(0x2028), String.chr(0xA0)]
	var got := OWReport.read_lines(text)
	t.eq(got.size(), 2, "two lines")
	if got.size() == 2:
		t.eq(got[0].words, "Built", "the first, its address out")
		t.eq(got[1].line, "nothing changed%sstill" % String.chr(0x2028), "U+2028 stays inside a line")
		t.eq(got[1].address, null, "no address")
	t.eq(OWReport.read_lines("").size(), 0, "an empty text has no line")
	t.done()
