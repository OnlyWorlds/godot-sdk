class_name OWViews
extends RefCounted
## How an element is shown by its kind: schema-dist [code]views.json[/code] (at the dist's root since serial 113,
## version 3 since serial 115), baked by [code]codegen/generate.py[/code] into [code]ow_views_table.gd[/code]. In the
## file's words, "presentation data, not the standard": for a report, a charter, a message and a line in a room, which
## field gives the one sentence, which fields lead the page and which fold, the layout, and the marks shown at the head
## of any element's page. "A kind with no row draws as its type draws today, in the standard's section order. Each tool
## keeps its own drawing and reads the row; nothing here says who may see or do what (that is the server's, by what it
## serves)."
##
## [method view_of] answers one element's [OWViews.View]: its row, its one sentence, its banners and the order its page
## draws its fields in. Ported from the TypeScript SDK's [code]viewOf[/code] (4.152.0; its reader is unchanged since
## 4.151.0) and the Unity SDK's [code]OWViews.ViewOf[/code] (628418d), with version 3's generic link built to the
## file's words and its fixture (no package had published a version-3 reader at serial 115); the file's own fixture,
## [code]views.fixture.json[/code], is this file's test. A profile's pair is matched by that profile's own reader here:
## the room's in [OWLens] ([code]_is_room_element[/code]), the charter's [method OWLens.is_charter_element].
##
## Element bodies are Dictionaries as the API or a world folder gives them (JSON as Godot parses it: a list is an Array,
## an object a Dictionary, a number a float).

const _T = preload("res://addons/onlyworlds/ow_views_table.gd")

## views.json's format ([code]_meta.version[/code]) as baked: 3.
const VERSION := _T.VERSION
## sha256 of the views.json the table was baked from, as the pinned MANIFEST.json lists it.
const SHA256 := _T.SHA256
## The marks every page shows at its head, in the file's order, each [code]{mark, defined_by}[/code]. Read-only.
const BANNERS := _T.BANNERS
## The layouts the file defines, by name ([code]document[/code], [code]conversation[/code]), each with its sentence.
const LAYOUTS := _T.LAYOUTS
## The rows, in the file's order, each as the file writes it ([code]id[/code], [code]kind[/code], [code]from[/code],
## [code]sentence[/code], [code]lead[/code], [code]fold[/code], [code]layout[/code], [code]banner[/code]). Read-only.
const ROWS := _T.ROWS
## Each type's section fields in the schema's own order (schema/<type>.yaml: its sections as listed, and each section's
## fields as listed), as the walk lists them: the order the document layout draws the rest in. A Pin's generic link is
## its one name, [code]element[/code], as the schema lists it (see [method view_of]).
const SECTION_FIELDS := _T.SECTION_FIELDS
## Each type's generic links and the two keys a served body carries for each, [code][type_key, id_key][/code], from
## the walk: [code]{"pin": {"element": ["element_type", "element_id"]}}[/code]. Read-only.
const GENERIC_LINKS := _T.GENERIC_LINKS

## What [method view_of] answers for one element. Each answer is its own: changing one changes no other, and never the
## table.
class View:
	## The row that shows it, the table's own (read-only) Dictionary; null when no row matches and the element draws
	## as its type.
	var row: Variant = null
	## The one sentence for a card, a list row or a hover, a String; null when there is no row or no field the row names
	## holds anything.
	var sentence: Variant = null
	## The marks to show at the head of its page, in order: the table's banners the element carries, then the row's own.
	var banners := PackedStringArray()
	## The fields its page draws, in the order drawn (the file's [code]document[/code] layout); see [method OWViews.view_of].
	var order := PackedStringArray()

	## The answer in the fixture's shape: [code]{row, sentence, banners, order}[/code], the row by its id.
	func to_dict() -> Dictionary:
		return {"row": row["id"] if row is Dictionary else null, "sentence": sentence, "banners": Array(banners),
			"order": Array(order)}

## How [param element] is shown, by the table baked at this pin: the row that matches it, its one sentence, the marks
## to show at the head of its page, and the fields its page draws in order. Pass the element as the reader is served
## it: the banners read what was served (a known-of stub, the hidden mark, a trimmed list). Anything that is not a
## Dictionary has no row, no sentence, no banners and no fields drawn.
##
## [b]The row[/b] (the file's [code]match[/code]): "a row's kind is a type alone, a type with a supertype, or a
## profile's pair, which matches only with that profile's mark, by that profile's own reader". Types and supertypes are
## trimmed and folded as the room profile defines once ([method OWUnicode.profile_fold]). "The most specific row wins: a
## profile's pair, then a type with a supertype, then a type alone." "A reader drawing a page never refuses over the
## table: where two rows match on one rung, the first in the file wins." (Two rows on one kind are a fault "refused
## where it is built": [code]codegen/generate.py[/code] refuses such a file.)
##
## [b]The sentence[/b]: "the first field named in the row's [code]sentence[/code] whose value is a string that holds
## something after trimming; that value trimmed, cut at its first line break (U+000A or U+000D), and trimmed again,
## whitespace being the room profile's White_Space set. A field whose value is not a string holds nothing." So U+2028
## is no cut.
##
## [b]The banners[/b], in [constant BANNERS]' order: "[code]known_of[/code] and [code]hidden[/code] only when true, the
## two review marks only when the value is an object with something in it" (the review profile's rules 1, 4 and 5), and
## "[code]x_served_trimmed[/code] only when it names a field (its list holds at least one string with something left
## after trimming: a list of blanks shows no banner)". Then the row's own [code]banner[/code] marks, "each read by
## presence as the room profile reads a mark: not null, a string only when something is left after trimming, any other
## value counts" (a mark that is one of the table's is read as the table reads it). "An element no row matches has no
## row and draws as its type; the banners still show."
##
## [b]The order[/b] (the [code]document[/code] layout): "lead open, then the rest, then fold; a field the row names in
## both lead and fold is drawn in the lead", each field once. The rest are the type's [constant SECTION_FIELDS] the row
## puts in neither lead nor fold. "A field that holds nothing (absent, null, a string with nothing left after trimming,
## a list with no items, an object with no keys; a list of blank strings holds something here, whatever a banner reads
## of one) is not drawn: an empty lead field is skipped, and a fold whose field holds nothing draws no fold." A number
## (0 too) and a bool (false too) hold something. The base fields (name, description, supertype, subtype, image_url)
## are the page's head and are in the order only where the row names one in lead or fold; extension keys never are.
## With no row, the type's section fields. A [code]conversation[/code] draws "each line's own fields as a document
## draws them", so its order is read the same way; following the chain ([code]layout.by[/code]) is the caller's.
## "A generic link (a Pin's [code]element[/code]) is one field of the order, under its schema name and at its place,
## never its two keys as two entries: it is read as the two keys schema.json gives it ([code]type_key[/code],
## [code]id_key[/code]), and it holds something only when both are strings with something left after trimming; one
## alone, or both empty, holds nothing" (version 3; [constant GENERIC_LINKS]). A body's own [code]element[/code] key is
## not one of the two and is never read.
##
## [codeblock]
## OWViews.view_of({"type": "narrative", "supertype": "Message", "story": "See you at the gate.\nBring the map."}).to_dict()
## # {"row": "message", "sentence": "See you at the gate.", "banners": [], "order": ["story"]}
## OWViews.view_of({"type": "character", "name": "Ilse"}).to_dict()
## # {"row": null, "sentence": null, "banners": [], "order": []}
## [/codeblock]
static func view_of(element: Variant) -> View:
	return _view_in({"banners": BANNERS, "rows": ROWS}, element)

## [method view_of] against a given table ([code]{banners, rows}[/code] in views.json's shape). For the shared
## fixture's tests, which read a case against a table of the fixture's own (one at fault on purpose, two rows on one
## kind); as the TypeScript SDK's [code]viewIn[/code] and the Unity SDK's internal [code]ViewOf[/code] overload, not
## part of the surface.
static func _view_in(table: Dictionary, element: Variant) -> View:
	var out := View.new()
	if not (element is Dictionary):
		return out
	var el: Dictionary = element
	var best := 0
	for r in table.get("rows", []):
		var s := _score(r, el)
		if s > best:   # strictly greater: on one rung the first row keeps it
			best = s
			out.row = r
	for b in table.get("banners", []):
		if _carries(el, b["mark"]):
			out.banners.append(b["mark"])
	if out.row == null:
		out.order = _draw_order(null, el)
		return out
	for m in out.row.get("banner", []):
		if _carries(el, m):
			out.banners.append(m)
	out.sentence = _sentence_of(out.row, el)
	out.order = _draw_order(out.row, el)
	return out

## How specifically [param row] matches: 3 a profile's pair with its mark, 2 a type with a supertype, 1 a type alone,
## 0 not at all.
static func _score(row: Dictionary, el: Dictionary) -> int:
	var type: Variant = el.get("type")
	if not (type is String):
		return 0
	var supertype: Variant = el.get("supertype")
	var kind: Dictionary = row["kind"]
	if kind.has("profile"):
		var pair: String = kind["pair"]
		var slash := pair.find("/")
		if OWUnicode.profile_fold(type) != OWUnicode.profile_fold(pair.substr(0, slash)):
			return 0
		if not (supertype is String) or OWUnicode.profile_fold(supertype) != OWUnicode.profile_fold(pair.substr(slash + 1)):
			return 0
		match kind["profile"]:
			"room":
				return 3 if OWLens._is_room_element(el) else 0
			"charter":
				return 3 if OWLens.is_charter_element(el) else 0
		return 0
	if OWUnicode.profile_fold(type) != OWUnicode.profile_fold(kind["type"]):
		return 0
	if not kind.has("supertype"):
		return 1
	return 2 if supertype is String and OWUnicode.profile_fold(supertype) == OWUnicode.profile_fold(kind["supertype"]) else 0

## Whether [param el] carries the banner [param mark], read as the file reads that mark.
static func _carries(el: Dictionary, mark: String) -> bool:
	var v: Variant = el.get(mark)
	match mark:
		"hidden", "known_of":
			return v is bool and v
		"x_served_trimmed":
			# it names a field: at least one String with something left after trimming (a list of blanks names none)
			if v is Array:
				for x in v:
					if x is String and OWUnicode.trim_white_space(x) != "":
						return true
			return false
		"x_review_proposed", "x_review_checked":
			return v is Dictionary and not v.is_empty()
	return OWLens._has_mark(el, mark)

## The one sentence: the first field the row names whose value is a String holding something after trimming, cut at
## its first line break (U+000A or U+000D) and trimmed again; null when none does.
static func _sentence_of(row: Dictionary, el: Dictionary) -> Variant:
	for f in row.get("sentence", []):
		var v: Variant = el.get(f)
		if not (v is String):
			continue
		var text := OWUnicode.trim_white_space(v)
		if text == "":
			continue
		var cut := -1
		for i in text.length():
			var c := text.unicode_at(i)
			if c == 0x0A or c == 0x0D:
				cut = i
				break
		return OWUnicode.trim_white_space(text if cut < 0 else text.substr(0, cut))
	return null

## A field holds nothing when absent, null, a String with nothing left after trimming, an empty Array, or an empty
## Dictionary.
static func _holds(el: Dictionary, field: String) -> bool:
	if not el.has(field):
		return false
	var v: Variant = el[field]
	if v == null:
		return false
	if v is String:
		return OWUnicode.trim_white_space(v) != ""
	if v is Array or v is Dictionary:
		return not v.is_empty()
	return true

## A generic link (a Pin's [code]element[/code]) holds something only when both its keys are Strings with something
## left after trimming White_Space; any other field holds as [method _holds] says. [param generic] is the type's
## [constant GENERIC_LINKS] entry, field name -> [code][type_key, id_key][/code].
static func _field_holds(el: Dictionary, field: String, generic: Dictionary) -> bool:
	if not generic.has(field):
		return _holds(el, field)
	for k in generic[field]:
		var v: Variant = el.get(k)
		if not (v is String and OWUnicode.trim_white_space(v) != ""):
			return false
	return true

## The fields drawn, in order: lead, then the type's section fields in neither lead nor fold, then fold; each once. A
## generic link is one field at its place, read by its two keys (views.json version 3).
static func _draw_order(row: Variant, el: Dictionary) -> PackedStringArray:
	var type: Variant = el.get("type")
	var sections: Array = SECTION_FIELDS.get(OWUnicode.profile_fold(type), []) if type is String else []
	var generic: Dictionary = GENERIC_LINKS.get(OWUnicode.profile_fold(type), {}) if type is String else {}
	var lead: Array = row.get("lead", []) if row is Dictionary else []
	var folds := []
	if row is Dictionary:
		for f in row.get("fold", []):
			folds.append(f["field"])
	var drawn := PackedStringArray()
	for f in lead:
		if not drawn.has(f) and _field_holds(el, f, generic):
			drawn.append(f)
	for f in sections:
		if not lead.has(f) and not folds.has(f) and not drawn.has(f) and _field_holds(el, f, generic):
			drawn.append(f)
	for f in folds:
		if not drawn.has(f) and _field_holds(el, f, generic):
			drawn.append(f)
	return drawn
