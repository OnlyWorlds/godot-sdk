class_name OWRecord
extends RefCounted
## The record profile (schema-dist [code]profiles/record.md[/code], serials 102 and 103): one run of a game a world's
## Characters took part in (a battle, a crossing, a match), kept in that world on kinds the standard already has. The
## run is an Event carrying the mark [code]x_record[/code]; its chronicle and each Character's stories are Narratives
## that list the Event in [code]events[/code]. A Character's experience is the list [method records_of] reads, never a
## field on the Character.
##
## [method record_mark_of] reads the mark, [method records_of] a Character's records: keel's
## [code]elements/record.py[/code] ([code]record_mark[/code], [code]records_of[/code]) is the reading this follows, the
## npm SDK's [code]recordMarkOf[/code] / [code]recordsOf[/code] and the Python package's [code]record_mark_of[/code] /
## [code]records_of[/code] the same. The fixture beside the profile is this file's test.

## The Event's field that carries the mark (the packages' [code]RECORD_FIELD[/code]).
const MARK := "x_record"
## The mark's six members, in the profile's order; [code]tool[/code] and [code]played_at[/code] are required.
const MEMBERS := ["tool", "played_at", "version", "seed", "outcome", "seats"]

## The mark on [param element], normalised: [code]{tool, played_at, version, seed, outcome, seats}[/code], the two
## required members as written, each optional member null when unset, [code]seats[/code] a Dictionary ({} when unset),
## each a copy. Null when it is no mark: [param element] not a Dictionary whose [code]type[/code] is
## [code]"event"[/code] (a mark on any other element is no record), the value not a Dictionary, [code]tool[/code] not
## 1 to 32 of [code]a-z 0-9 -[/code], [code]played_at[/code] not an instant as the message grammar reads one (see
## [method _instant_ms]), or [code]version[/code], [code]seed[/code], [code]outcome[/code] (1 to 24 of [code]a-z[/code])
## or [code]seats[/code] (a Dictionary of String to String) anything but its kind, null or absent. A broken writer
## never shows as a record.
static func record_mark_of(element: Variant) -> Variant:
	if not (element is Dictionary and element.get("type") == "event"):
		return null
	var m: Variant = element.get(MARK)
	if not m is Dictionary:
		return null
	var tool: Variant = m.get("tool")
	if not (tool is String and _tool_ok(tool)):
		return null
	if _instant_ms(m.get("played_at")) == null:
		return null
	var version: Variant = m.get("version")
	var seed: Variant = m.get("seed")
	var outcome: Variant = m.get("outcome")
	var seats: Variant = m.get("seats")
	if not (version == null or version is String):
		return null
	if not (seed == null or seed is String):
		return null
	if not (outcome == null or (outcome is String and _outcome_ok(outcome))):
		return null
	if not (seats == null or _seats_ok(seats)):
		return null
	return {"tool": tool, "played_at": m["played_at"], "version": version, "seed": seed, "outcome": outcome,
		"seats": seats.duplicate() if seats is Dictionary else {}}

## [param character_id]'s records in [param elements] (the world as the reader is served it), newest first by
## [code]played_at[/code] as an instant to the millisecond (a fraction truncated past three digits, never the string),
## a tie by the Event's id in code point order. Each entry is
## [code]{event: {id, name}, tool, played_at, version, seed, outcome, seat, stories: [{id, name, as}]}[/code].
## Pure: nothing is stored or written, and every entry is the caller's own.
##
## A record is an Event with a mark ([method record_mark_of]), not proposed (as the review profile reads it: an
## [code]x_review_proposed[/code] Dictionary with a key; an empty mark is settled), whose [code]characters[/code]
## list names the Character: who took part is that list alone, never [code]seats[/code] (a seat for a Character not listed makes no record, and
## [code]seat[/code] is the mark's seat for this Character, null when none). Its stories are the Narratives, not
## proposed, whose [code]events[/code] list names the Event and that name the Character as [code]protagonist[/code],
## [code]narrator[/code] or both ([code]as[/code]), in code point order of their ids; a chronicle naming no one is no
## Character's story. A multi-link that is not a list lists nothing, and a name that is not a String reads "".
##
## An empty list for a Character no record names, an id in no element, or a caller's mistake ([param character_id]
## not a String, [param elements] not an Array). An element that is not a Dictionary, and an Event or a Narrative
## without a String [code]id[/code], are skipped.
static func records_of(character_id: Variant, elements: Variant) -> Array:
	if not (character_id is String and elements is Array):
		return []
	# This Character's stories, by each Event they name (once per Narrative, however often it names it; a value in
	# events that is not a String names nothing): one pass over the world, then a lookup per record (npm 4.124.1).
	var stories_of := {}
	for n in elements:
		if not (n is Dictionary and n.get("type") == "narrative" and n.get("id") is String) or _proposed(n):
			continue
		var p := _names(n.get("protagonist"), character_id)
		var r := _names(n.get("narrator"), character_id)
		if not (p or r):
			continue
		var story := {"id": n["id"], "name": _name(n), "as": "both" if p and r else "protagonist" if p else "narrator"}
		var seen := {}
		for e in _list(n.get("events")):
			if e is String and not seen.has(e):
				seen[e] = true
				if not stories_of.has(e):
					stories_of[e] = []
				stories_of[e].append(story)
	var keyed := []
	for ev in elements:
		var mark: Variant = record_mark_of(ev)
		if mark == null or _proposed(ev) or not ev.get("id") is String:
			continue
		if not _list(ev.get("characters")).has(character_id):
			continue
		var id: String = ev["id"]
		var stories := []
		for s in stories_of.get(id, []):
			stories.append(s.duplicate())   # every entry is the caller's own, never shared with another record
		stories.sort_custom(func(a, b) -> bool: return a["id"] < b["id"])   # Godot's String order is by code point
		var seat: Variant = mark["seats"].get(character_id)
		var entry := {"event": {"id": id, "name": _name(ev)}, "tool": mark["tool"], "played_at": mark["played_at"],
			"version": mark["version"], "seed": mark["seed"], "outcome": mark["outcome"],
			"seat": seat if seat is String else null, "stories": stories}
		keyed.append([_instant_ms(mark["played_at"]), id, entry])
	keyed.sort_custom(func(a, b) -> bool: return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return keyed.map(func(k): return k[2])

## [code]played_at[/code] as whole milliseconds from 1970-01-01T00:00:00Z, or null when it is no instant. It is read by
## the message page's grammar (serial 123: one grammar for a time in the standard), [method OWLens.time_key], the one
## the message and lens readers call: [code]YYYY-MM-DDTHH:MM:SS[/code], an optional fraction, then [code]Z[/code],
## [code]+HH:MM[/code], [code]-HH:MM[/code] or nothing (UTC); the T and the Z in either case; seconds required; a real
## calendar date, years 0000 to 9999; ASCII digits only, the whole String, nothing trimmed. The order is to the
## millisecond: the instant floored to it, so a fraction is truncated past three digits, never rounded.
static func _instant_ms(at: Variant) -> Variant:
	var micros: Variant = OWLens.time_key(at)
	if micros == null:
		return null
	return (micros - posmod(micros, 1000)) / 1000

static func _digit(c: int) -> bool:
	return c >= 0x30 and c <= 0x39

## The tools list's id form: 1 to 32 of a-z, 0-9 and -.
static func _tool_ok(s: String) -> bool:
	if s.is_empty() or s.length() > 32:
		return false
	for k in s.length():
		var c := s.unicode_at(k)
		if not ((c >= 0x61 and c <= 0x7A) or _digit(c) or c == 0x2D):
			return false
	return true

## One lowercase word: 1 to 24 of a-z.
static func _outcome_ok(s: String) -> bool:
	if s.is_empty() or s.length() > 24:
		return false
	for k in s.length():
		var c := s.unicode_at(k)
		if c < 0x61 or c > 0x7A:
			return false
	return true

## A Dictionary of Character id to seat, every key and every seat a String.
static func _seats_ok(v: Variant) -> bool:
	if not v is Dictionary:
		return false
	for k in v:
		if not (k is String and v[k] is String):
			return false
	return true

## Proposed exactly when the review profile's reader that shows a world says so (record reader rule 1, serial 103;
## the packages' [code]proposedMarkOf[/code] / [code]proposed_mark_of[/code]): [code]x_review_proposed[/code] a
## Dictionary with a key. Absent, null, an empty mark ([code]{}[/code], [code]""[/code] or White_Space only,
## [code][][/code]) and a value that is not a Dictionary are settled.
static func _proposed(el: Dictionary) -> bool:
	return OWLens.is_proposed(el) and el[OWLens.PROPOSED_MARK] is Dictionary

## A multi-link's ids: the list itself, or nothing when the value is not a list.
static func _list(v: Variant) -> Array:
	return v if v is Array else []

## True when a single link [param v] names [param id].
static func _names(v: Variant, id: String) -> bool:
	return v is String and v == id

## A name as served, "" when it is not a String.
static func _name(el: Dictionary) -> String:
	var name: Variant = el.get("name")
	return name if name is String else ""
