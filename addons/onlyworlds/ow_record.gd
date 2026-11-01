class_name OWRecord
extends RefCounted
## The record profile (schema-dist [code]profiles/record.md[/code], serial 102): one run of a game a world's
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

## Each month's days in a common year; February has 29 in a Gregorian leap year.
const _MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const _MS_PER_DAY := 86400000

## The mark on [param element], normalised: [code]{tool, played_at, version, seed, outcome, seats}[/code], the two
## required members as written, each optional member null when unset, [code]seats[/code] a Dictionary ({} when unset),
## each a copy. Null when it is no mark: [param element] not a Dictionary whose [code]type[/code] is
## [code]"event"[/code] (a mark on any other element is no record), the value not a Dictionary, [code]tool[/code] not
## 1 to 32 of [code]a-z 0-9 -[/code], [code]played_at[/code] not a real instant in the profile's form (see
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
## A record is an Event with a mark ([method record_mark_of]), not proposed (the review profile's
## [code]x_review_proposed[/code] any value but null), whose [code]characters[/code] list names the Character: who
## took part is that list alone, never [code]seats[/code] (a seat for a Character not listed makes no record, and
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

## [code]played_at[/code] as whole milliseconds from 0001-01-01T00:00Z, or null when it is no instant in the profile's
## form. The form is the whole String: [code]YYYY-MM-DDTHH:MM[/code], then optionally [code]:SS[/code] and after it
## optionally [code].[/code] and one or more digits, then [code]Z[/code]; ASCII digits only, the T and the Z upper case,
## nothing before or after. The calendar is checked by its parts, never by a date parser: year 0001 or later, month 1
## to 12, the day within its month (Gregorian leap years), hour 0 to 23, minute and second 0 to 59. A fraction is
## truncated past three digits.
static func _instant_ms(at: Variant) -> Variant:
	if not at is String:
		return null
	var s: String = at
	var n := s.length()
	if n < 17 or not (_digits(s, 0, 4) and s[4] == "-" and _digits(s, 5, 2) and s[7] == "-" and _digits(s, 8, 2)
			and s[10] == "T" and _digits(s, 11, 2) and s[13] == ":" and _digits(s, 14, 2)):
		return null
	var i := 16
	var second := 0
	var ms := 0
	if s[i] == ":":
		if not _digits(s, i + 1, 2):
			return null
		second = s.substr(i + 1, 2).to_int()
		i += 3
		if i < n and s[i] == ".":
			var j := i + 1
			while j < n and _digit(s.unicode_at(j)):
				j += 1
			if j == i + 1:
				return null
			ms = s.substr(i + 1, mini(3, j - i - 1)).rpad(3, "0").to_int()
			i = j
	if i != n - 1 or s[i] != "Z":
		return null
	var year := s.substr(0, 4).to_int()
	var month := s.substr(5, 2).to_int()
	var day := s.substr(8, 2).to_int()
	var hour := s.substr(11, 2).to_int()
	var minute := s.substr(14, 2).to_int()
	if year < 1 or month < 1 or month > 12 or day < 1 or day > _month_days(year, month):
		return null
	if hour > 23 or minute > 59 or second > 59:
		return null
	return _days(year, month, day) * _MS_PER_DAY + ((hour * 60 + minute) * 60 + second) * 1000 + ms

static func _leap(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)

static func _month_days(year: int, month: int) -> int:
	return 29 if month == 2 and _leap(year) else _MONTH_DAYS[month - 1]

## Days from 0001-01-01 in the proleptic Gregorian calendar.
static func _days(year: int, month: int, day: int) -> int:
	var before := year - 1
	var days := before * 365 + before / 4 - before / 100 + before / 400
	for k in range(1, month):
		days += _month_days(year, k)
	return days + day - 1

static func _digit(c: int) -> bool:
	return c >= 0x30 and c <= 0x39

## True when [param count] ASCII digits stand at [param from] in [param s].
static func _digits(s: String, from: int, count: int) -> bool:
	if from + count > s.length():
		return false
	for k in count:
		if not _digit(s.unicode_at(from + k)):
			return false
	return true

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

## Proposed while [code]x_review_proposed[/code] holds any value but null; absent or null is settled.
static func _proposed(el: Dictionary) -> bool:
	return el.get(OWLens.PROPOSED_MARK) != null

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
