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
