class_name OWReport
extends RefCounted
## The report profile's rule 9 (schema-dist [code]profiles/report.md[/code], serial 120): reports grouped into
## threads by their [code]parent_narrative[/code], read as written. A report is a Narrative with supertype
## [code]Report[/code] and the room's mark [code]x_room_of[/code]; a board entry is one with supertype
## [code]Board[/code] and the mark; without the mark either is lore. Both are room pairs, matched by the room reader
## [OWLens] already holds (the trim, the fold and the mark by presence), never a second copy, and a thread is ordered
## by [code]created_at[/code] as [OWMessage] orders messages ([method OWLens.time_key], the profiles' one time rule).
## The npm SDK's [code]reportThreadsOf[/code] (4.159.0) and the Python package's [code]report_threads_of[/code]
## (0.120.0), read against the page's text, which wins. The fixture beside the page,
## [code]profiles/report.fixture.json[/code], is this file's test.

## What a report's parent is (the fixture's [code]parents[/code] words).
const NONE := "none"
const REPORT := "report"
const BOARD := "board"
const MISSING := "missing"
const OTHER := "other"
const SELF := "self"
## The two lints, the only ones: [constant CHAIN] on a report whose parent is a report that itself names a report the
## reader holds, [constant SELF] on a report that names itself.
const CHAIN := "chain"

## The two room pairs this reader tells apart.
const PAIR_TYPE := "narrative"
const REPORT_SUPERTYPE := "Report"
const BOARD_SUPERTYPE := "Board"

## [method threads_of]'s answer.
class Threads:
	## For each report given, by its id, in the order given: what its [code]parent_narrative[/code] names.
	var parents := {}
	## One [code]{parent, kind, reports}[/code] per parent that is a report or a board entry and that some report
	## names: [code]kind[/code] [constant REPORT] or [constant BOARD], [code]reports[/code] the ids of the reports that
	## name it in rule 9's order, the parent itself left out. In the order each parent is first named; the page rules
	## no order between groups.
	var groups := []
	## Each [code]{kind, report}[/code], in the order of the reports; the page rules no order between them.
	var lints := []

	## The answer in the fixture's shape.
	func to_dict() -> Dictionary:
		return {"parents": parents, "groups": groups, "lints": lints}

## [method read_line]'s answer: one line of a report's [code]consequences[/code] (the report profile's rule 10).
class Line:
	## The line as read.
	var line := ""
	## The words a reader shows: the line with its address taken out where nothing the writer wrote is lost, else the
	## whole line.
	var words := ""
	## The element the line names, written [code]ow://<type>/<id>[/code] with the id in lowercase, or null when no
	## address in the line names an element of this world (which is no fault).
	var address: Variant = null
	## What [method OWAddress.parse_link] reads in the address as written, or null.
	var reading: OWAddress.Reading = null
	## Where the address as written starts in [member line] (a Godot String index: code points), or null.
	var start: Variant = null
	## The index just past the address as written, or null.
	var end: Variant = null

	## The line in the fixture's shape.
	func to_dict() -> Dictionary:
		return {"line": line, "address": address, "words": words}

## The closing marks, character by character (code points): a question mark is none, since after an address it
## begins a query.
const _CLOSING := {0x2E: true, 0x2C: true, 0x3B: true, 0x3A: true, 0x21: true, 0x29: true, 0x5D: true, 0x7D: true,
	0x27: true, 0x22: true, 0x2019: true, 0x201D: true, 0xBB: true}
## The pairs an address may stand in, each opener's code point with its closer's (a brace makes no pair).
const _PAIRS := {0x28: 0x29, 0x5B: 0x5D, 0x22: 0x22, 0x27: 0x27, 0x201C: 0x201D, 0x2018: 0x2019, 0xAB: 0xBB}

## One line of a report's [code]consequences[/code], read as the report profile reads it (rule 10, parts 2 and 3):
## the element it names and the words a reader shows. The npm package's [code]readReportLine[/code] (4.169.0) and the
## Python package's twin; the page's lines fixture is the test.
##
## The line's address is the last address in it, found as the address profile finds one in prose
## ([method OWAddress.find_links]), that names an element of this world: an [code]ow://[/code] or site address,
## canonical or not, whose world is [param world] or is left out, with a type word and an id. An address of another
## world, one whose world is a slug, a world's own address or a lens with no element is prose and stays in the words; a
## line with only those has no address, which is no fault. Whether the element still exists is the caller's to read.
##
## The address leaves the shown words only when nothing the writer wrote is lost: it is canonical, carries no moment and
## no lens, and stands apart (before it the line's start, White_Space or one colon; after it the line's end,
## White_Space or a closing mark, [code]. , ; : ! ) ] } ' "[/code] and the right single and double quotation marks and
## the right guillemet), alone or inside a matched pair ([code]()[/code], [code][][/code], [code]""[/code],
## [code]''[/code], the curly double and single quotes, the guillemets). Then it goes with the White_Space on both sides
## and one colon before it (and the White_Space before that colon), and the two halves join with one space, or none
## when the second is empty or begins with a closing mark. In every other shape, and when nothing stands before the
## address, the whole line is shown as written, still naming its element.
##
## The line is read as given, untrimmed: [method read_lines] splits and trims a whole text. [param world] is this
## world's id, lowercase as the world holds it, compared exactly with the address's world (whose hex is read
## lowercase); null, or anything that is not a String, and only an address with no world names an element here.
## [codeblock]
## var got := OWReport.read_line("Renamed the Consul's Steinway: ow://object/01a1d4ef-0000-7000-8000-000000000084.")
## # got.words == "Renamed the Consul's Steinway.", got.address == "ow://object/01a1d4ef-0000-7000-8000-000000000084"
## [/codeblock]
static func read_line(line: String, world: Variant = null) -> Line:
	var out := Line.new()
	out.line = line
	out.words = line
	# Part 2: the last address that names an element of this world, from the text alone.
	var here: OWAddress.Found = null
	for f in OWAddress.find_links(line):
		var r := f.reading
		if r.type == null or r.id == null:
			continue
		if r.world == null or (not r.world_is_slug and world is String and r.world == world):
			here = f
	if here == null:
		return out
	var reading := here.reading
	var start := here.start
	var end := here.end
	out.address = "ow://%s/%s" % [reading.type, reading.id]
	out.reading = reading
	out.start = start
	out.end = end
	# Part 3: it leaves the words only when nothing the writer wrote is lost.
	if not reading.canonical or reading.moment != null or reading.lens != null:
		return out
	var from := start
	var to := end
	if start > 0 and _PAIRS.has(line.unicode_at(start - 1)):
		# A matched pair goes with it (3a); an opener not closed right after keeps the whole line.
		if end >= line.length() or line.unicode_at(end) != _PAIRS[line.unicode_at(start - 1)]:
			return out
		from = start - 1
		to = end + 1
	var apart_before := from == 0 or OWUnicode._is_white_space(line.unicode_at(from - 1)) or line.unicode_at(from - 1) == 0x3A
	var apart_after := to == line.length() or OWUnicode._is_white_space(line.unicode_at(to)) or _CLOSING.has(line.unicode_at(to))
	if not apart_before or not apart_after:
		return out
	# The White_Space on both sides goes, and one colon before it with the White_Space before that colon (3c).
	var left := _trim_end(line.substr(0, from))
	if left.ends_with(":"):
		left = _trim_end(left.substr(0, left.length() - 1))
	var right := _trim_start(line.substr(to))
	# Nothing stands before the address (3b): the whole line stays, so a line is never shown empty.
	if left == "":
		return out
	if right == "":
		out.words = left
	elif _CLOSING.has(right.unicode_at(0)):
		out.words = left + right
	else:
		out.words = left + " " + right
	return out

## Every line of a report's [code]consequences[/code], each read by [method read_line] (the report profile's rule 10,
## part 1). The text is split at every carriage return and every line feed, so a CRLF is one break and nothing else
## breaks a line (U+000B, U+000C, U+2028, U+2029 and U+0085 stay inside it); each piece is trimmed of Unicode
## White_Space at both ends, and a piece with nothing left is no line. A byte order mark is no White_Space: a line of
## one alone is a line. The npm package's [code]readReportLines[/code].
static func read_lines(text: String, world: Variant = null) -> Array[Line]:
	var out: Array[Line] = []
	var start := 0
	for i in text.length() + 1:
		if i == text.length() or text.unicode_at(i) == 0x0A or text.unicode_at(i) == 0x0D:
			var line := OWUnicode.trim_white_space(text.substr(start, i - start))
			if line != "":
				out.append(read_line(line, world))
			start = i + 1
	return out

static func _trim_end(s: String) -> String:
	var b := s.length()
	while b > 0 and OWUnicode._is_white_space(s.unicode_at(b - 1)):
		b -= 1
	return s.substr(0, b)

static func _trim_start(s: String) -> String:
	var a := 0
	while a < s.length() and OWUnicode._is_white_space(s.unicode_at(a)):
		a += 1
	return s.substr(a)

## True when [param element] is a report: the pair [code]narrative[/code] + [code]Report[/code] (each trimmed and
## folded) and the mark [code]x_room_of[/code] by presence. The room profile's matcher, [OWLens]'s.
static func is_report(element: Variant) -> bool:
	return _room_kind_of(element) == REPORT

## True when [param element] is a board entry: the pair [code]narrative[/code] + [code]Board[/code] and the mark.
static func is_board_entry(element: Variant) -> bool:
	return _room_kind_of(element) == BOARD

## Reports grouped into threads (the report profile's rule 9). Give it the Narratives as the reader is served them,
## in the order served (a Dictionary per body, as the API or a world folder gives it).
##
## Only reports are read for a parent and grouped: a message, a board entry or a lore Narrative that names a report is
## in no part of the answer. [member Threads.parents] reads each report's parent: [constant NONE] (absent, null, not a
## String, or nothing left after trimming White_Space as the room profile trims; a parent with content is read as
## written, never trimmed), [constant SELF], [constant MISSING] (no element of that id given: a folder or an export
## without it, an id that dangles), [constant REPORT], [constant BOARD], or [constant OTHER] (any other element, a
## Narrative with supertype [code]Report[/code] or [code]Board[/code] and no mark among them). A report whose parent is
## a report or a board entry is in that parent's group, ordered by [code]created_at[/code] as an instant (equal times
## keep the order given; one that cannot be read after every one that can), never by id or by the time's text. A
## report that names itself is in no group, with a [constant SELF] lint, and reads as naming no parent: it still heads
## the group of the reports that name it, and those are no chain. A report whose parent is a report that itself has a
## report the reader holds for its parent is shown under the parent it names, with a [constant CHAIN] lint, never
## repaired; nothing is walked further up, and no thread is guessed from names, days or a [code]description[/code].
## A thread takes nothing away from where a report hangs: its [code]relations[/code] and [code]events[/code] still
## hold it.
##
## An element that is not a Dictionary, or has no id that is a non-empty String, is passed over; of two with one id,
## the first is read and the later copy is ignored entirely (no report, no parent). Not an Array: an empty answer.
## Pure: the bodies are never changed.
static func threads_of(narratives: Variant) -> Threads:
	var out := Threads.new()
	if not (narratives is Array):
		return out
	var by_id := {}
	var reports := []
	for el in narratives:
		if not (el is Dictionary and el.get("id") is String and el["id"] != "") or by_id.has(el["id"]):
			continue
		by_id[el["id"]] = el
		if is_report(el):
			reports.append(el)
	var members := {}
	for report in reports:
		var id: String = report["id"]
		var kind := _parent_kind(report, by_id)
		out.parents[id] = kind
		if kind == REPORT or kind == BOARD:
			var parent: String = _parent_of(report)
			if not members.has(parent):
				members[parent] = []
			members[parent].append(report)
		if kind == SELF:
			out.lints.append({"kind": SELF, "report": id})
		# A chain: the parent is a report whose own parent reads as a report. One that names itself reads as naming no
		# parent, so a report under it is no chain.
		if kind == REPORT and _parent_kind(by_id[_parent_of(report)], by_id) == REPORT:
			out.lints.append({"kind": CHAIN, "report": id})
	for parent in members:
		out.groups.append({"parent": parent, "kind": _room_kind_of(by_id[parent]),
			"reports": OWMessage._in_created_order(members[parent]).map(func(r): return r["id"])})
	return out

## What [param report]'s parent is among [param by_id] (the first copy of each id).
static func _parent_kind(report: Dictionary, by_id: Dictionary) -> String:
	var parent: Variant = _parent_of(report)
	if parent == null:
		return NONE
	if parent == report["id"]:
		return SELF
	if not by_id.has(parent):
		return MISSING
	var kind := _room_kind_of(by_id[parent])
	return kind if kind != "" else OTHER

## [code]parent_narrative[/code] as written, or null for no parent: absent, null, not a String, or nothing left after
## trimming White_Space ([code]""[/code], [code]"   "[/code]). A parent with content is never trimmed.
static func _parent_of(element: Dictionary) -> Variant:
	var parent: Variant = element.get("parent_narrative")
	if not (parent is String) or OWUnicode.trim_white_space(parent) == "":
		return null
	return parent

## [constant REPORT] or [constant BOARD] for a room element of that pair (the pair AND the mark), else "".
static func _room_kind_of(element: Variant) -> String:
	if not (element is Dictionary) or not OWLens._is_room_element(element):
		return ""
	if OWMessage._matches(element, PAIR_TYPE, REPORT_SUPERTYPE):
		return REPORT
	if OWMessage._matches(element, PAIR_TYPE, BOARD_SUPERTYPE):
		return BOARD
	return ""
