class_name OWCalendar
extends RefCounted
## The calendar profile (schema-dist [code]profiles/calendar.md[/code], field [code]atlas_calendar[/code]): a world's
## own names for its time line (months, weeks, eras, leap days). A calendar changes no date: every date stays an
## integer step, and this only says how to read a step aloud. [method read_value] refuses what the profile refuses
## (null: show bare numbers, never an error); [method breakdown_step] and [method format_step] read a step as the
## profile's steps 1 to 5 read it. The npm SDK's calendar kernel ([code]src/calendar/calendar.ts[/code], the
## reference the profile names: [code]readCalendarConfig[/code], [code]breakdownStep[/code],
## [code]formatStep[/code]) and the Python package's [code]calendar.py[/code], read against the profile's text, which
## wins; the fixture beside the profile is this file's test.
##
## Godot's JSON reads every number as a float. A whole number here is an int, or a float with no fraction; where the
## profile asks for a whole number it is JavaScript's [code]Number.isSafeInteger[/code] (at most 2^53 - 1 in size),
## and [code]after_month[/code] is [code]Number.isInteger[/code] (a whole number, from 0 to the year's month count; with no months, no intercalary day reads).
## JSON cannot tell 1 from 1.0 and
## neither can JavaScript, so 1.0 is 1 everywhere, the version included. A boolean is never a number, and only
## [code]false[/code] is false ([code]restart[/code], [code]in_week[/code]). The reader turns the value's numbers into
## ints once, so the arithmetic is integer arithmetic: exact where JavaScript's doubles are, and past 2^53 (a step
## or a year sum no world holds) exact where they are not.

## The field that holds a calendar, on any element: a reader finds calendars by its presence, never by type.
const FIELD := "atlas_calendar"
## The supertype Atlas gives a calendar Construct: convention and display only.
const SUPERTYPE := "calendar"

const DEFAULT_FORMAT_MONTHS := "{day} {month}, {year} {era}"
const DEFAULT_FORMAT_PLAIN := "{year} {era}"
const DEFAULT_FORMAT_INTERCALARY := "{intercalary}, {year} {era}"
const KNOWN_TOKENS := ["day", "month", "weekday", "year", "era", "step", "intercalary"]

const _MAX_SAFE := 9007199254740991            # 2^53 - 1: Number.MAX_SAFE_INTEGER
const _MAX_YEAR_CORRECTION := 10000            # npm's cap on the year seed's correction laps, per direction
## The profile's size bounds (serial 149): past one of them a value is not a calendar. A text's length is counted in
## Unicode code points, which is what a Godot String's length() counts (its characters are 32-bit; Godot's JSON joins
## a surrogate pair into one and refuses a document holding a lone surrogate).
const _MAX_ERAS := 256
const _MAX_MONTHS := 64
const _MAX_WEEK := 64                          # a week's length, and its count of names
const _MAX_INTERCALARY := 16
const _MAX_EXCEPT := 8
const _MAX_TEXT := 256                         # a template or a name
## JavaScript's white space (\s and String.prototype.trim): WhiteSpace and LineTerminator.
const _JS_WS := "\\t\\n\\x{0B}\\f\\r \\x{A0}\\x{1680}\\x{2000}-\\x{200A}\\x{2028}\\x{2029}\\x{202F}\\x{205F}\\x{3000}\\x{FEFF}"
## A known token with no value, so the close-up pass finds it (npm's U+E000, a private-use code point).
const _EMPTY_KNOWN := "\ue000"

static var _token_re: RegEx
static var _runs_re: RegEx
static var _ws_re: RegEx
static var _int_re: RegEx
static var _decimal_re: RegEx
static var _radix_re: RegEx

## One era as read. [member raw] is the entry as given.
class Era:
	var name := ""
	## The abbrev as given (any JSON value; null when absent): the era token prints it, or the name when null.
	var abbrev: Variant = null
	## An up era: the first step it holds. A down era: its pivot, the first step it does not hold.
	var start := 0
	## The end as given, an int, or null when absent: an up era's first step past it, a down era's lowest step.
	var end: Variant = null
	## False only when [code]restart[/code] is [code]false[/code]: the era is a label, its years the year index.
	var restart := true
	## 0 or 1 (default 1).
	var year_base := 1
	## True when [code]direction[/code] is [code]"down"[/code]; any other value, null or none counts up.
	var down := false
	## Its place in the calendar's [code]eras[/code] list.
	var index := 0
	var raw: Dictionary = {}

## One intercalary entry as read: a day in no month.
class Intercalary:
	var name := ""
	## 0 before month 1, k after month k; never below 0 or past the year's months (the value is then no calendar).
	var after_month := 0
	## The leap rule's period, or 0 when the day falls every year.
	var every_years := 0
	## Version 2 only (empty in version 1, which ignores the key): the divisors that flip the rule, in order.
	var except_years: PackedInt64Array = []
	## Version 2 only (0 in version 1): added to the year index before the rule.
	var offset := 0
	## False only when [code]in_week[/code] is [code]false[/code]: the free week does not advance over it.
	var in_week := true
	var raw: Dictionary = {}

## A calendar as read: [member raw] is the value itself, everything a writer must keep; the rest is what the
## arithmetic reads from it.
class Calendar:
	var raw: Dictionary = {}
	## 1 or 2.
	var version := 1
	var grain := ""
	var has_months := false
	var month_names: PackedStringArray = []
	var month_lengths: PackedInt64Array = []
	## [code]bundles.year.steps[/code], or 0 when absent (months win when both are there).
	var year_steps := 0
	var has_week := false
	var week_length := 0
	var week_names: PackedStringArray = []
	var week_nested := false
	var intercalary: Array[Intercalary] = []
	var eras: Array[Era] = []
	## The templates as given (null when absent); a value that is not a string prints the default template.
	var format: Variant = null
	var format_intercalary: Variant = null

## A step taken apart (npm StepBreakdown). Null where the structure does not exist, and every field but
## [member step] null for a date past the exact range ([method OWCalendar.is_past_exact_range]), which is shown as a
## plain number.
class Breakdown:
	var step := 0
	## The year index, from 0 at step 0: an int, or null for a date past the exact range.
	var abs_year: Variant = null
	## The era's year (restart arithmetic applied), or [member abs_year] with no era or a label era: an int, or null
	## for a date past the exact range.
	var year: Variant = null
	var era: Era = null
	## 1-based, or null (an intercalary day, no months).
	var month: Variant = null
	var month_name: Variant = null
	var day: Variant = null
	## The intercalary day's name when the step is one, else null.
	var intercalary: Variant = null
	var weekday: Variant = null

	func to_dict() -> Dictionary:
		return {"step": step, "abs_year": abs_year, "year": year, "era": era, "month": month, "month_name": month_name,
			"day": day, "intercalary": intercalary, "weekday": weekday}

# -- reading the value ------------------------------------------------------------------------------------------------

## The field's value as a calendar, or null for anything that is not one (bare numbers, never an error). An object, or
## the same object as a JSON string, strict JSON only: Godot's own parser takes a trailing comma, a leading zero, a
## number ending in a point and a raw control character in a string, so the text is checked against JSON's grammar
## first. npm [code]readCalendarValue[/code].
static func read_value(raw: Variant) -> Calendar:
	if raw == null:
		return null
	var value: Variant = raw
	if raw is String or raw is StringName:
		var text := String(raw)
		if not _is_strict_json(text):
			return null
		var json := JSON.new()
		if json.parse(text) != OK:
			return null
		value = json.data
	return read_config(value)

## [param value] as a calendar when it is an object the profile accepts, else null: every rule of the profile's "Not a
## calendar" list, as npm [code]readCalendarConfig[/code] reads it, the fixture's refusals among them (an
## [code]offset[/code] or [code]except[/code] with no [code]every_years[/code] too), the size bounds and the longest
## year among them (serial 149).
static func read_config(value: Variant) -> Calendar:
	return _read_config(value, true)

## [method read_config] without the size bounds and the longest year: for the cost tests, whose shared cases hold
## templates and names far past 256 code points. A [Calendar] made in code never meets the bounds, so what a label
## costs is still the formatter's to keep linear. Not part of the addon's API.
static func _read_config_past_the_bounds(value: Variant) -> Calendar:
	return _read_config(value, false)

static func _read_config(value: Variant, bounded: bool) -> Calendar:
	if not (value is Dictionary):
		return null
	var cfg: Dictionary = value
	var version: Variant = cfg.get("version")
	if not _is_number(version) or (version != 1 and version != 2):
		return null
	# The profile's grain is a string with something left after trimming the room profile's White_Space set.
	if not (cfg.get("grain") is String) or OWUnicode.trim_white_space(cfg["grain"]) == "":
		return null
	var cal := Calendar.new()
	cal.raw = cfg
	cal.version = int(version)
	cal.grain = cfg["grain"]
	var bundles: Variant = cfg.get("bundles")
	if not (bundles is Dictionary):
		bundles = {}     # npm reads cfg.bundles?.months: a bundles that is not an object holds nothing
	# Months: a falsy value (null, false, 0, "") is absent; anything else must be names and lengths.
	var months: Variant = bundles.get("months")
	if _truthy(months):
		if not (months is Dictionary):
			return null
		var names: Variant = months.get("names")
		var lengths: Variant = months.get("lengths")
		if not (names is Array) or not (lengths is Array) or names.size() != lengths.size() or names.is_empty():
			return null
		for n in names:
			if not (n is String):
				return null
		for l in lengths:
			if not _is_positive_int(l):
				return null
		cal.has_months = true
		cal.month_names = PackedStringArray(names)
		for l in lengths:
			cal.month_lengths.append(int(l))
	var year: Variant = bundles.get("year")
	if year != null:
		if not (year is Dictionary) or not _is_positive_int(year.get("steps")):
			return null
		cal.year_steps = int(year["steps"])
	var week: Variant = bundles.get("week")
	if week != null:
		if not (week is Dictionary) or not _is_positive_int(week.get("length")) or not (week.get("names") is Array):
			return null
		for n in week["names"]:
			if not (n is String):
				return null
		cal.has_week = true
		cal.week_length = int(week["length"])
		cal.week_names = PackedStringArray(week["names"])
		cal.week_nested = week.get("mode") is String and week["mode"] == "nested"
	var eras: Variant = cfg.get("eras")
	if eras != null:
		if not (eras is Array):
			return null
		for i in eras.size():
			var era := _read_era(eras[i], i)
			if era == null:
				return null
			cal.eras.append(era)
	var inter: Variant = cfg.get("intercalary")
	if inter != null:
		if not (inter is Array):
			return null
		for e in inter:
			var ic := _read_intercalary(e, cal.version, cal.month_names.size())
			if ic == null:
				return null
			cal.intercalary.append(ic)
	var fmt: Variant = cfg.get("format")
	cal.format = fmt if fmt is String else null
	var fmt_i: Variant = cfg.get("format_intercalary")
	cal.format_intercalary = fmt_i if fmt_i is String else null
	return cal if not bounded or _within_bounds(cal) else null

## The size bounds and the longest year, the profile's last two refusals (serial 149): at most 256 eras, 64 months, a
## week of 64 steps and 64 names, 16 entries in [code]intercalary[/code], an [code]except[/code] of 8 (read only on
## version 2), and templates and names of 256 code points, counted on the string as decoded, untrimmed and not
## normalised; and the longest year (the months' lengths plus every entry in [code]intercalary[/code], whether or not
## one year earns them all) at most 2^53 - 1. A template, a [code]step_name[/code] or an abbrev that is not a string
## is no text, and no length is counted on it.
static func _within_bounds(cal: Calendar) -> bool:
	if cal.eras.size() > _MAX_ERAS or cal.intercalary.size() > _MAX_INTERCALARY:
		return false
	if _too_long(cal.grain) or _too_long(cal.raw.get("step_name")) or _too_long(cal.format) or _too_long(cal.format_intercalary):
		return false
	for era in cal.eras:
		if _too_long(era.name) or _too_long(era.abbrev):
			return false
	if cal.has_months:
		if cal.month_names.size() > _MAX_MONTHS:
			return false
		for n in cal.month_names:
			if _too_long(n):
				return false
		# At most 64 lengths of at most 2^53 - 1 each, and 16 days: the sum stays inside a 64-bit int.
		var longest := cal.intercalary.size()
		for l in cal.month_lengths:
			longest += l
		if longest > _MAX_SAFE:
			return false
	if cal.has_week:
		if cal.week_length > _MAX_WEEK or cal.week_names.size() > _MAX_WEEK:
			return false
		for n in cal.week_names:
			if _too_long(n):
				return false
	for ic in cal.intercalary:
		if _too_long(ic.name) or ic.except_years.size() > _MAX_EXCEPT:
			return false
	return true

## A string longer than 256 code points; anything that is not a string is no text and never too long.
static func _too_long(s: Variant) -> bool:
	return (s is String or s is StringName) and String(s).length() > _MAX_TEXT

static func _read_era(e: Variant, i: int) -> Era:
	if not (e is Dictionary) or not (e.get("name") is String) or not _is_safe_int(e.get("start")):
		return null
	var end: Variant = e.get("end")
	if end != null and not _is_safe_int(end):
		return null
	var base: Variant = e.get("year_base")
	if base != null and (not _is_number(base) or (base != 0 and base != 1)):
		return null
	var era := Era.new()
	era.raw = e
	era.name = e["name"]
	era.abbrev = e.get("abbrev")
	era.start = int(e["start"])
	era.end = int(end) if end != null else null
	era.restart = not (e.get("restart") is bool and e["restart"] == false)
	era.year_base = int(base) if base != null else 1
	era.down = e.get("direction") is String and e["direction"] == "down"
	era.index = i
	return era

## [param month_count] is 0 without months: an after_month that names a month the year does not have (past the last,
## below the first), or any intercalary day on a calendar with no months (there is no place between months, 0
## included), gives the day no position, and the value is no calendar.
static func _read_intercalary(e: Variant, version: int, month_count: int) -> Intercalary:
	if not (e is Dictionary) or not (e.get("name") is String) or not _is_integer(e.get("after_month")):
		return null
	var after: float = float(e["after_month"])
	if month_count == 0 or after < 0 or after > month_count:
		return null
	var every: Variant = e.get("every_years")
	if every != null and not _is_positive_int(every):
		return null
	var ic := Intercalary.new()
	ic.raw = e
	ic.name = e["name"]
	ic.after_month = int(after)
	ic.every_years = int(every) if every != null else 0
	ic.in_week = not (e.get("in_week") is bool and e["in_week"] == false)
	if version != 2:
		return ic            # version 1 reads except and offset as unknown keys
	var ex: Variant = e.get("except")
	var off: Variant = e.get("offset")
	if ex == null and off == null:
		return ic
	if every == null:
		return null          # except and offset need every_years
	if off != null:
		if not _is_safe_int(off):
			return null
		ic.offset = int(off)
	if ex != null:
		if not (ex is Array):
			return null
		var prev: int = ic.every_years
		for d in ex:
			if not _is_positive_int(d) or int(d) <= prev or int(d) % prev != 0:
				return null  # each a multiple of the one before, and larger
			prev = int(d)
			ic.except_years.append(prev)
	return ic

## Every element of [param elements] whose [constant FIELD] reads as a calendar, in order:
## [code]{"id", "name", "calendar"}[/code], the name [code]"(unnamed calendar)"[/code] when it has none. One that is not a
## calendar is left out, never an error. npm [code]worldCalendars[/code].
static func world_calendars(elements: Array) -> Array:
	var out := []
	for el in elements:
		if not (el is Dictionary):
			continue
		var cal := read_value(el.get(FIELD))
		if cal == null:
			continue
		var name: Variant = el.get("name")
		out.append({"id": el.get("id"), "name": name if _truthy(name) else "(unnamed calendar)", "calendar": cal})
	return out

# -- the arithmetic ---------------------------------------------------------------------------------------------------

## Euclidean floor division (the profile's step 2): -1 / 20 is -1.
static func floor_div(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b

## The floored modulo: always from 0 to [param b] - 1.
static func floor_mod(a: int, b: int) -> int:
	return posmod(a, b)

static func _rules(cal: Calendar, only_skipped := false) -> Array[Intercalary]:
	var out: Array[Intercalary] = []
	for ic in cal.intercalary:
		if ic.every_years > 0 and (not only_skipped or not ic.in_week):
			out.append(ic)
	return out

## A year's length leap days aside: the months' lengths and every day that falls every year, or
## [code]bundles.year.steps[/code], or 1 (each step a year). Without months an intercalary day counts no step.
static func _base_len(cal: Calendar) -> int:
	if not cal.has_months:
		return cal.year_steps if cal.year_steps > 0 else 1
	var n := 0
	for l in cal.month_lengths:
		n += l
	for ic in cal.intercalary:
		if ic.every_years == 0:
			n += 1
	return n

## The leap rule (the profile's step 3): the year index plus the offset divides by the period, flipped by each
## except that divides it, the last that matches deciding.
static func _rule_holds(ic: Intercalary, y: int) -> bool:
	var yy := y + ic.offset
	var on := posmod(yy, ic.every_years) == 0
	for d in ic.except_years:
		if posmod(yy, d) == 0:
			on = not on
	return on

## How many k in [a, b) have floor_mod(k + offset, m) == 0.
static func _multiples_in(a: int, b: int, m: int, offset: int) -> int:
	return floor_div(b - 1 + offset, m) - floor_div(a - 1 + offset, m)

## The signed count of years the rule selects from 0 up to [param y] (or from y up to 0, negative): the closed form,
## since each except is a multiple of the divisor before it.
static func _leap_years_before(y: int, ic: Intercalary) -> int:
	var a := 0 if y >= 0 else y
	var b := y if y >= 0 else 0
	var count := _multiples_in(a, b, ic.every_years, ic.offset)
	var s := -1
	for d in ic.except_years:
		count += s * _multiples_in(a, b, d, ic.offset)
		s = -s
	return count if y >= 0 else -count

## True when the intercalary day falls in year [param y]: always without [code]every_years[/code], else by its rule.
static func intercalary_in_year(ic: Intercalary, y: int) -> bool:
	return ic.every_years == 0 or _rule_holds(ic, y)

## The first step of year index [param y]; year 0 opens at step 0 (the profile's step 1: no epoch offset).
static func year_start_step(cal: Calendar, y: int) -> int:
	var start := y * _base_len(cal)
	for ic in _rules(cal):
		start += _leap_years_before(y, ic)
	return start

## The length in steps of year index [param y].
static func year_length(cal: Calendar, y: int) -> int:
	var n := _base_len(cal)
	for ic in _rules(cal):
		if _rule_holds(ic, y):
			n += 1
	return n

## The year index of [param step]: a seed on the mean year length, then npm's bounded correction laps.
static func absolute_year(cal: Calendar, step: int) -> int:
	var mean := float(_base_len(cal))
	for ic in _rules(cal):
		var m := 1.0 / ic.every_years
		var s := -1.0
		for d in ic.except_years:
			m += s / d
			s = -s
		mean += m
	var y := int(floor(step / mean))
	var i := 0
	while i < _MAX_YEAR_CORRECTION and step < year_start_step(cal, y):
		y -= 1
		i += 1
	i = 0
	while i < _MAX_YEAR_CORRECTION and step >= year_start_step(cal, y + 1):
		y += 1
		i += 1
	return y

# -- eras -------------------------------------------------------------------------------------------------------------

## Each era's range, [code][era, lo, hi][/code] (lo inclusive, hi exclusive, as floats so an open side is infinite),
## in order of start, equal starts in list order. An up era with no end runs to the start of the next up era (a down
## era never holds a step at or above its pivot, so it never ends one); a down era runs from its end, or from the
## beginning, to its pivot. npm [code]resolveEraDomains[/code].
static func era_domains(cal: Calendar) -> Array:
	var sorted: Array[Era] = cal.eras.duplicate()
	sorted.sort_custom(func(a: Era, b: Era) -> bool: return a.start < b.start or (a.start == b.start and a.index < b.index))
	var out := []
	for i in sorted.size():
		var era := sorted[i]
		if era.down:
			out.append([era, float(era.end) if era.end != null else -INF, float(era.start)])
			continue
		var hi := INF
		if era.end != null:
			hi = float(era.end)
		else:
			for j in range(i + 1, sorted.size()):
				if not sorted[j].down:
					hi = float(sorted[j].start)
					break
		out.append([era, float(era.start), hi])
	return out

## The era holding [param step], or null (the profile's step 4): of the eras whose range holds it, the latest start,
## then an up era over a down one, then the later in the list. (An up and a down era of one start never both hold a
## step, the down era's range ending where the up era's begins; the middle rule is kept as npm's comparator holds it.)
static func era_for_step(cal: Calendar, step: int) -> Era:
	var best: Era = null
	for d in era_domains(cal):
		var era: Era = d[0]
		if step < d[1] or step >= d[2]:
			continue
		if best == null or era.start > best.start or (era.start == best.start and (
				(best.down and not era.down) or (best.down == era.down and era.index > best.index))):
			best = era
	return best

## The year [param era] shows for [param step]: an up era counts from the year its start falls in, from its
## year_base; a down era counts back from the year holding the step before its pivot, which is year_base; no era, or
## a label era, shows the year index.
static func display_year(cal: Calendar, step: int, era: Era) -> int:
	var y := absolute_year(cal, step)
	if era == null or not era.restart:
		return y
	if era.down:
		return absolute_year(cal, era.start - 1) - y + era.year_base
	return y - absolute_year(cal, era.start) + era.year_base

# -- a year's days ----------------------------------------------------------------------------------------------------

## Where [param offset] steps into year [param y] falls, by walking the months and the intercalary days placed between
## them (never listing the year's days): [code][kind, a, b, skipped][/code], kind "month" (a the month, b the day),
## "intercalary" (a the entry) or "" (no slot: an offset past the year's last day, which no caller passes), and skipped
## the days before it that the free week does not count.
static func _slot(cal: Calendar, y: int, offset: int) -> Array:
	var pos := 0
	var skipped := 0
	for after in cal.month_names.size() + 1:
		if after > 0:
			var days := cal.month_lengths[after - 1]
			if offset < pos + days:
				return ["month", after, offset - pos + 1, skipped]
			pos += days
		for ic in cal.intercalary:
			if ic.after_month != after or not intercalary_in_year(ic, y):
				continue
			if offset == pos:
				return ["intercalary", ic, null, skipped]
			if not ic.in_week:
				skipped += 1
			pos += 1
	return ["", null, null, skipped]

## The weekday of [param step], or null: no week, fewer (or more) names than its length, a nested week outside the
## months, an intercalary day the week skips. A free week runs across months from names[0] at step 0, past the days
## with [code]in_week[/code] false; a nested week restarts each month.
static func weekday_for_step(cal: Calendar, step: int) -> Variant:
	var y := absolute_year(cal, step)
	return _weekday(cal, step, y, _slot(cal, y, step - year_start_step(cal, y)) if cal.has_months else ["", null, null, 0])

static func _weekday(cal: Calendar, step: int, y: int, slot: Array) -> Variant:
	if not cal.has_week or cal.week_names.size() != cal.week_length:
		return null
	if cal.week_nested:
		return cal.week_names[posmod(slot[2] - 1, cal.week_length)] if slot[0] == "month" else null
	if slot[0] == "intercalary" and not (slot[1] as Intercalary).in_week:
		return null
	var before := 0
	for ic in cal.intercalary:
		if not ic.in_week and ic.every_years == 0:
			before += 1
	before *= y
	for ic in _rules(cal, true):
		before += _leap_years_before(y, ic)
	return cal.week_names[posmod(step - before - int(slot[3]), cal.week_length)]

## [param step] taken apart (npm [code]breakdownStep[/code]): its year index, its era and the era's year, its month
## and day or its intercalary day, its weekday.
static func breakdown_step(cal: Calendar, step: int) -> Breakdown:
	var b := Breakdown.new()
	b.step = step
	if _step_past_exact_range(step):
		return b             # a plain number: every other field null
	var y := absolute_year(cal, step)
	var era := era_for_step(cal, step)
	var shown := display_year(cal, step, era)
	if _year_past_exact_range(cal, y, shown):
		return b
	b.abs_year = y
	b.era = era
	b.year = shown
	var slot: Array = ["", null, null, 0]
	if cal.has_months:
		slot = _slot(cal, y, step - year_start_step(cal, y))
	if slot[0] == "month":
		b.month = slot[1]
		b.month_name = cal.month_names[slot[1] - 1]
		b.day = slot[2]
	elif slot[0] == "intercalary":
		b.intercalary = (slot[1] as Intercalary).name
	b.weekday = _weekday(cal, step, y, slot)
	return b

## True when [param step] is a date past the exact range (the profile, serial 149): the step, its year index plus each
## leap rule's [code]offset[/code], or the year it shows in its era lies outside -(2^53 - 1) to 2^53 - 1. Such a date
## is shown as a plain number, every field of its breakdown null; the calendar stays a calendar. The step is compared
## first, so the arithmetic after it never leaves a 64-bit int.
static func is_past_exact_range(cal: Calendar, step: int) -> bool:
	if _step_past_exact_range(step):
		return true
	var y := absolute_year(cal, step)
	return _year_past_exact_range(cal, y, display_year(cal, step, era_for_step(cal, step)))

static func _step_past_exact_range(step: int) -> bool:
	return step < -_MAX_SAFE or step > _MAX_SAFE

## The year index [param y] plus each leap rule's offset, or the year shown, outside the safe integers.
static func _year_past_exact_range(cal: Calendar, y: int, shown: int) -> bool:
	for ic in _rules(cal):
		var shifted := y + ic.offset
		if shifted < -_MAX_SAFE or shifted > _MAX_SAFE:
			return true
	return shown < -_MAX_SAFE or shown > _MAX_SAFE

# -- words ------------------------------------------------------------------------------------------------------------

## [param step] in words (the profile's step 5; npm [code]formatStep[/code]): the calendar's template, or the default
## for the step (an intercalary day's, with months, without), each known token filled; a known token with no value
## prints empty and one [code],[/code] [code];[/code] [code]·[/code] or white space on each side of it closes up (a dash
## never does); an unknown token prints as written. A null calendar, or a date past the exact range
## ([method is_past_exact_range]), prints the bare step.
static func format_step(cal: Calendar, step: int) -> String:
	if cal == null:
		return str(step)
	var b := breakdown_step(cal, step)
	if b.year == null:
		return str(step)     # past the exact range: a plain number
	var values := {
		"day": str(b.day) if b.day != null else null,
		"month": b.month_name,
		"weekday": b.weekday,
		"year": str(b.year),
		"era": (b.era.abbrev if b.era.abbrev != null else b.era.name) if b.era != null else null,
		"step": str(step),
		"intercalary": b.intercalary,
	}
	var template: String
	if b.intercalary != null:
		template = cal.format_intercalary if cal.format_intercalary != null else DEFAULT_FORMAT_INTERCALARY
	elif cal.format != null:
		template = cal.format
	else:
		template = DEFAULT_FORMAT_MONTHS if cal.has_months else DEFAULT_FORMAT_PLAIN
	return render_template(template, values)

## Fill [param template]'s tokens from [param values] and close up around the known ones with no value (npm's
## renderTemplate, its white space JavaScript's). A value that is not a string prints as JavaScript's String() does.
static func render_template(template: String, values: Dictionary) -> String:
	_compile()
	var parts := PackedStringArray()
	var at := 0
	for m in _token_re.search_all(template):
		parts.append(template.substr(at, m.get_start() - at))
		var token := m.get_string(1)
		if not KNOWN_TOKENS.has(token):
			parts.append(m.get_string())
		else:
			var v: Variant = values.get(token)
			parts.append(_EMPTY_KNOWN if v == null or (v is String and v == "") else _js_string(v))
		at = m.get_end()
	parts.append(template.substr(at))
	var out := _collapse_empty("".join(parts))
	out = _runs_re.sub(out, " ", true)
	return _trim_edges(out)   # trim, then the separators left at either edge: one pass covers both

## What [code]/\s*[,;·]?\s*MARKER\s*[,;·]?\s*/g[/code] replaced by one space (MARKER the empty-known code point), in
## one pass (npm 4.201.2's [code]collapseEmpty[/code]): each marker takes the white space, at most one mark and white
## space before it (back to where the last replacement ended) and the same after it. As a regular expression it took
## quadratic time on a long run of marks or white space before a marker.
static func _collapse_empty(text: String) -> String:
	var i := text.find(_EMPTY_KNOWN)
	if i == -1:
		return text
	var n := text.length()
	var done := 0
	var parts := PackedStringArray()
	while i != -1:
		var j := i
		while j > done and _is_js_ws(text.unicode_at(j - 1)):
			j -= 1
		if j > done and _is_mark(text.unicode_at(j - 1)):
			j -= 1
			while j > done and _is_js_ws(text.unicode_at(j - 1)):
				j -= 1
		var k := i + 1
		while k < n and _is_js_ws(text.unicode_at(k)):
			k += 1
		if k < n and _is_mark(text.unicode_at(k)):
			k += 1
			while k < n and _is_js_ws(text.unicode_at(k)):
				k += 1
		parts.append(text.substr(done, j - done))
		parts.append(" ")
		done = k
		i = text.find(_EMPTY_KNOWN, done)
	parts.append(text.substr(done))
	return "".join(parts)

## [param text] without the white space and the marks [code], ; ·[/code] at either edge (npm 4.201.2's
## [code]trimEdges[/code], after its trim), in one pass: the regular expression it replaces took quadratic time on a
## long run of marks that did not reach the end.
static func _trim_edges(text: String) -> String:
	var a := 0
	var b := text.length()
	while a < b and (_is_js_ws(text.unicode_at(a)) or _is_mark(text.unicode_at(a))):
		a += 1
	while b > a and (_is_js_ws(text.unicode_at(b - 1)) or _is_mark(text.unicode_at(b - 1))):
		b -= 1
	return text.substr(a, b - a)

## A mark the close-up absorbs: a comma, a semicolon or a middle dot (U+00B7).
static func _is_mark(c: int) -> bool:
	return c == 0x2C or c == 0x3B or c == 0xB7

## JavaScript's white space ([code]\s[/code] and [code]trim[/code]: WhiteSpace and LineTerminator), the set
## [constant _JS_WS] spells for the regular expressions.
static func _is_js_ws(c: int) -> bool:
	if c <= 0x20:
		return c == 0x20 or (c >= 0x09 and c <= 0x0D)
	if c < 0xA0:
		return false
	return c == 0xA0 or c == 0x1680 or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029 \
		or c == 0x202F or c == 0x205F or c == 0x3000 or c == 0xFEFF

static func _compile() -> void:
	if _token_re != null:
		return
	_token_re = RegEx.create_from_string("\\{([a-z_]+)\\}")
	var ws := "[" + _JS_WS + "]"
	_runs_re = RegEx.create_from_string(ws + "{2,}")
	_ws_re = RegEx.create_from_string(ws + "+")
	_int_re = RegEx.create_from_string("^-?[0-9]+\\z")   # JavaScript's \d with no u flag: ASCII digits only
	_decimal_re = RegEx.create_from_string("^[+-]?(Infinity|([0-9]+\\.?[0-9]*|\\.[0-9]+)([eE][+-]?[0-9]+)?)\\z")
	_radix_re = RegEx.create_from_string("^0(?:[xX]([0-9a-fA-F]+)|[oO]([0-7]+)|[bB]([01]+))\\z")

## JavaScript's String(v) for a JSON value: a number in its shortest form, a list its items joined by commas (null as
## empty), an object [code][object Object][/code].
static func _js_string(v: Variant) -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			if is_nan(v):
				return "NaN"
			if is_inf(v):
				return "Infinity" if v > 0 else "-Infinity"
			return OWJson.number(v)
		TYPE_ARRAY:
			var items := PackedStringArray()
			for x in v:
				items.append("" if x == null else _js_string(x))
			return ",".join(items)
		TYPE_DICTIONARY:
			return "[object Object]"
	return str(v)

# -- labels and durations ---------------------------------------------------------------------------------------------

## The compact year label for an axis tick zoomed wide (npm [code]formatYearLabel[/code]): the era's year and its
## abbrev, or its name when the abbrev is null; outside every era, or when that word is falsy as JavaScript reads it
## ([code]""[/code], 0, false), the year alone. A word that is not a string prints as JavaScript's String() does. A
## null calendar, or a date past the exact range, prints the bare step.
static func format_year_label(cal: Calendar, step: int) -> String:
	if cal == null or _step_past_exact_range(step):
		return str(step)
	var era := era_for_step(cal, step)
	var year := display_year(cal, step, era)
	if _year_past_exact_range(cal, absolute_year(cal, step), year):
		return str(step)     # past the exact range: a plain number
	if era == null:
		return str(year)
	var word: Variant = era.abbrev if era.abbrev != null else era.name
	return "%d %s" % [year, _js_string(word)] if _truthy(word) else str(year)

## The mid-rung label for dense axis ticks (npm [code]formatMidLabel[/code]): day, month and the era's year with no
## era word ("11 Greening 454"), an intercalary day's name and year ("Hearthmoot 454"), and on a calendar with no
## months [method format_year_label]. A null calendar, or a date past the exact range, prints the bare step.
static func format_mid_label(cal: Calendar, step: int) -> String:
	if cal == null:
		return str(step)
	var b := breakdown_step(cal, step)
	if b.year == null:
		return str(step)     # past the exact range: a plain number
	if b.intercalary != null:
		return "%s %d" % [b.intercalary, b.year]
	if b.month_name != null and b.day != null:
		return "%d %s %d" % [b.day, b.month_name, b.year]
	return format_year_label(cal, step)

## The base year length in steps, leap days left out (npm [code]approxYearLength[/code]): the months' days and every
## intercalary day that falls every year, or [code]bundles.year.steps[/code], or null when the calendar has no year
## above the step (a null calendar too). A zoom threshold: ticks tighter than this read full dates.
static func approx_year_length(cal: Calendar) -> Variant:
	if cal == null:
		return null
	if cal.has_months:
		return _base_len(cal)
	return cal.year_steps if cal.year_steps > 0 else null

## A span of [param steps] in words (npm [code]formatDuration[/code]), its sign dropped: "19 years" when the calendar
## has a year longer than one step and the span reaches it (the base year, leap days left out; one decimal under 10
## years, whole from 10, JavaScript's Math.round: half up), else the step word ("12 days", to two decimals). The step
## word is [code]step_name[/code], else the grain, trimmed as JavaScript trims, and [code]step[/code] when nothing is
## left ([code]step_name: ""[/code] reads [code]step[/code], never the grain); a grain or step word that lowercases
## to [code]year[/code] with no year structure makes each step a year (so the count stays in that word). The plural
## adds [code]s[/code] to anything but exactly 1. A [code]step_name[/code] that is not a string is passed over for
## the grain (npm throws on one). A null calendar counts steps.
static func format_duration(cal: Calendar, steps: float) -> String:
	var n := absf(steps)
	var unit := "step"
	var year_len: Variant = null
	if cal != null:
		var named: Variant = cal.raw.get("step_name")
		unit = _js_trim(named if named is String else cal.grain)
		if unit == "":
			unit = "step"
		if cal.has_months:
			year_len = _base_len(cal)
		elif cal.year_steps > 0:
			year_len = cal.year_steps
		elif unit.to_lower() == "year":    # no other code point lowercases to y, e, a or r, in JavaScript or Godot
			year_len = 1
	if year_len != null and year_len > 1 and n >= year_len:
		var years: float = n / year_len
		var rounded: float = roundf(years) if years >= 10.0 else roundf(years * 10.0) / 10.0
		return "%s %s" % [_js_string(rounded), "year" if rounded == 1.0 else "years"]
	var shown: float = roundf(n * 100.0) / 100.0   # roundf is half away from zero: JavaScript's half up, for n >= 0
	return "%s %s" % [_js_string(shown), unit if shown == 1.0 else unit + "s"]

## The first step of each month of year index [param year], in order (npm [code]monthStartSteps[/code]):
## [code]{"month", "name", "step"}[/code], the month 1-based, past the intercalary days that fall before it that
## year. Found by arithmetic, never by listing the days. Empty with no months (or no calendar).
static func month_start_steps(cal: Calendar, year: int) -> Array:
	var out := []
	if cal == null or not cal.has_months:
		return out
	var offset := 0
	for ic in cal.intercalary:
		if ic.after_month == 0 and intercalary_in_year(ic, year):
			offset += 1
	var start := year_start_step(cal, year)
	for m in range(1, cal.month_names.size() + 1):
		out.append({"month": m, "name": cal.month_names[m - 1], "step": start + offset})
		offset += cal.month_lengths[m - 1]
		for ic in cal.intercalary:
			if ic.after_month == m and intercalary_in_year(ic, year):
				offset += 1
	return out

# -- parsing a date ---------------------------------------------------------------------------------------------------

## The year index of [param year] as [param era] counts it, the inverse of [method display_year] (npm
## [code]absYearForEraYear[/code]): a label era's year is the year index; an up era counts from the year its start
## falls in, from its year_base; a down era counts back from the year holding the step before its pivot.
static func abs_year_for_era_year(cal: Calendar, era: Era, year: int) -> int:
	if not era.restart:
		return year
	if era.down:
		return absolute_year(cal, era.start - 1) - (year - era.year_base)
	return absolute_year(cal, era.start) + (year - era.year_base)

## A written date read to a step (npm [code]parseDate[/code]): [code]{"step": int}[/code], or
## [code]{"error": String}[/code] in npm's words ([method is_parse_error] tells them apart). A bare whole number
## ([code]"-454"[/code]) is always the raw step; otherwise the words are the calendar's, matched without regard to case
## (JavaScript's toLowerCase), commas and points read as spaces, the word [code]year[/code] dropped: an era (name or
## abbrev, the longest first), then an intercalary day (the longest first), else a month (in the calendar's order),
## and what is left must be whole numbers: a day and a year beside a month (the one that fits the month is the day,
## day first on a tie), a year beside an intercalary day, else a year. A date with no year reads in the year of the
## world's now, and with no now is an error, never a guess. A year with no era named reads in the era holding the now,
## else the latest-started open era (not [code]closed[/code]), else the latest-started; a date that falls outside
## that era reads as a year index, unless an era was named and the year index lands in another era ("not a date in").
## A partial date is the first step of its period. [code]format_step(parse_date(format_step(n)))[/code] is
## [code]format_step(n)[/code]; the step itself is not promised back under a lossy format.
##
## [param options]: [code]{"now": step}[/code], a whole number (a float with no fraction is its number) or null. An
## unknown key, options that are not a Dictionary or a now that is not a whole number are the caller's mistake, not the
## input's: the answer is [code]{"error", "refused"}[/code], [code]refused[/code] the key ([code]"options"[/code]
## for the value itself), and the error is also pushed (npm throws a TypeError for an unknown key). A null calendar
## reads only a bare step.
##
## Where Godot differs from npm: a number past a 64-bit int is [code]unrecognized[/code] (npm reads it as a rounded
## double), and one between 2^53 and 2^63 is exact; an era abbrev that is not a string is no word to match (npm throws
## on a truthy one); the lowercasing is Godot's, with U+0130 made JavaScript's two code units, and without
## JavaScript's final sigma (a capital sigma at a word's end lowers to σ here, ς there).
static func parse_date(cal: Calendar, input: String, options: Variant = null) -> Dictionary:
	var now: Variant = null
	if options != null:
		if not (options is Dictionary):
			return _refused_option("options", "parse_date: options is a Dictionary, such as {\"now\": 0}; got %s" % var_to_str(options))
		for k in options:
			if not (k is String or k is StringName) or String(k) != "now":
				return _refused_option(str(k), "parse_date: unknown option '%s'. The keys are now." % str(k))
		var given: Variant = options.get("now")
		if given != null:
			now = OWLens.whole(given)
			if now == null and given is int:
				now = given
			if now == null:
				return _refused_option("now", "parse_date: now is a whole number (a step) or null; got %s" % var_to_str(given))
	_compile()
	var raw := _js_trim(input)
	if raw == "":
		return {"error": "empty date"}
	if _int_re.search(raw) != null:
		var bare: Variant = _parse_int(raw)
		return {"step": bare} if bare != null else {"error": "unrecognized: \"%s\"" % raw}
	if cal == null:
		return {"error": "no calendar: only a bare step reads"}
	var rest := _normalize(raw).replace(" year ", " ")
	var era: Era = null
	var inter: Intercalary = null
	var month: Variant = null
	# Names are eaten before numbers are read: a name may hold digits ("2 Yule").
	var candidates := []
	for e in cal.eras:
		candidates.append([e.name, e, candidates.size()])
		if e.abbrev is String and e.abbrev != "":
			candidates.append([e.abbrev, e, candidates.size()])
	candidates.sort_custom(_longest_first)
	for c in candidates:
		var eaten: Variant = _eat(rest, c[0])
		if eaten != null:
			rest = eaten
			era = c[1]
			break
	var inter_candidates := []
	for ic in cal.intercalary:
		inter_candidates.append([ic.name, ic, inter_candidates.size()])
	inter_candidates.sort_custom(_longest_first)
	for c in inter_candidates:
		var eaten: Variant = _eat(rest, c[0])
		if eaten != null:
			rest = eaten
			inter = c[1]
			break
	if inter == null and cal.has_months:
		for m in cal.month_names.size():
			var eaten: Variant = _eat(rest, cal.month_names[m])
			if eaten != null:
				rest = eaten
				month = m + 1
				break
	var numbers: Array[int] = []
	for p in _js_trim(rest).split(" ", false):
		var n: Variant = _parse_int(p) if _int_re.search(p) != null else null
		if n == null:
			return {"error": "unrecognized: \"%s\"" % p}
		numbers.append(n)
	var day: Variant = null
	var year: Variant = null
	if month != null:
		var days: int = cal.month_lengths[month - 1]
		if numbers.size() == 2:
			var a := numbers[0]
			var b := numbers[1]
			if a >= 1 and a <= days:
				day = a
				year = b
			elif b >= 1 and b <= days:
				day = b
				year = a
			else:
				return {"error": "no day in %s matches %d/%d" % [cal.month_names[month - 1], a, b]}
		elif numbers.size() == 1:
			if numbers[0] >= 1 and numbers[0] <= days:
				day = numbers[0]
			else:
				year = numbers[0]
		elif numbers.size() != 0:
			return {"error": "too many numbers"}
	elif inter != null:
		if numbers.size() > 1:
			return {"error": "too many numbers"}
		year = numbers[0] if numbers.size() == 1 else null
	else:
		if numbers.size() != 1:
			return {"error": "expected a year"}
		year = numbers[0]
	var at := [month, day if day != null else 1, inter]
	if year == null:
		if now == null:
			return {"error": "add a year (the world clock has no now set)"}
		return _resolve_in_year(cal, absolute_year(cal, now), at)
	var target: Era = era if era != null else _default_era(cal, now)
	if target == null:
		return _resolve_in_year(cal, year, at)
	# The era's reading first; a step outside the era's own range (a format may print a year index under a literal era
	# word) falls back to the year index, so format(parse(format(n))) holds.
	var via_era := _resolve_in_year(cal, abs_year_for_era_year(cal, target, year), at)
	if is_parse_error(via_era) or era_for_step(cal, via_era["step"]) == target:
		return via_era
	var via_abs := _resolve_in_year(cal, year, at)
	# A named era names the date's era: a year index that lands in an era is a date the input never named.
	if era != null and not is_parse_error(via_abs) and era_for_step(cal, via_abs["step"]) != null:
		return {"error": "not a date in %s" % era.name}
	return via_abs

## True when [param result] is [method parse_date]'s error (npm [code]isParseError[/code]).
static func is_parse_error(result: Dictionary) -> bool:
	return result.has("error")

static func _refused_option(key: String, message: String) -> Dictionary:
	push_error("OWCalendar." + message)
	return {"error": message, "refused": key}

## The step of [param at] ([code][month, day, intercalary][/code]) in year index [param y], or an error: no month and
## no intercalary day is the year's first step.
static func _resolve_in_year(cal: Calendar, y: int, at: Array) -> Dictionary:
	var start := year_start_step(cal, y)
	if at[0] == null and at[2] == null:
		return {"step": start}
	var offset := _offset_in_year(cal, y, at[0] if at[0] != null else 0, at[1], at[2])
	if offset < 0:
		if at[2] != null:
			return {"error": "%s does not occur in that year" % (at[2] as Intercalary).name}
		return {"error": "that day does not exist in that month"}
	return {"step": start + offset}

## How many steps into year [param y] the intercalary day [param target] falls (when not null), else day [param day] of
## month [param month]; -1 when that year has no such day. The walk [method _slot] takes, the other way.
static func _offset_in_year(cal: Calendar, y: int, month: int, day: int, target: Intercalary) -> int:
	var pos := 0
	for after in cal.month_names.size() + 1:
		if after > 0:
			var days := cal.month_lengths[after - 1]
			if target == null and after == month:
				return pos + day - 1 if day >= 1 and day <= days else -1
			pos += days
		for ic in cal.intercalary:
			if ic.after_month != after or not intercalary_in_year(ic, y):
				continue
			if ic == target:
				return pos
			pos += 1
	return -1

## The era a year with no era named reads in: the era holding [param now], else the latest-started of the eras not
## [code]closed[/code] (JavaScript's truthiness), else of them all; on a tie the first listed (npm's sort is stable).
static func _default_era(cal: Calendar, now: Variant) -> Era:
	if cal.eras.is_empty():
		return null
	if now != null:
		var holder := era_for_step(cal, now)
		if holder != null:
			return holder
	var pool: Array = cal.eras.filter(func(e: Era) -> bool: return not _truthy(e.raw.get("closed")))
	if pool.is_empty():
		pool = cal.eras
	var best: Era = pool[0]
	for e in pool:
		if e.start > best.start:
			best = e
	return best

## Longer first by JavaScript's length (UTF-16 code units: an astral character counts two), then in list order.
static func _longest_first(a: Array, b: Array) -> bool:
	var la := _utf16_len(a[0])
	var lb := _utf16_len(b[0])
	return la > lb or (la == lb and a[2] < b[2])

## [param rest] with the first match of [param name]'s normalized form (a whole word run, spaces on both sides) put
## out as one space, or null when it is not there.
static func _eat(rest: String, name: String) -> Variant:
	var needle := _normalize(name)
	var at := rest.find(needle)
	if at < 0:
		return null
	return rest.substr(0, at) + " " + rest.substr(at + needle.length())

## npm's normalize: lowercased, commas and points to spaces, JavaScript's white space runs to one space, trimmed, then
## a space on each side.
static func _normalize(s: String) -> String:
	_compile()
	var l := _js_lower(s).replace(",", " ").replace(".", " ")
	return " " + _js_trim(_ws_re.sub(l, " ", true)) + " "

## JavaScript's toLowerCase as far as Godot's to_lower is it: measured over every code point (Node 22), the two agree
## but on U+0130 (JavaScript's i and a combining dot above) and on letters newer than Node's Unicode tables. Final
## sigma, the one rule that reads a neighbour, is not reproduced.
static func _js_lower(s: String) -> String:
	return s.replace("İ", "i̇").to_lower()

## A run of ASCII digits, with an optional minus, as a 64-bit int, or null past it (npm reads it as a double).
static func _parse_int(s: String) -> Variant:
	var neg := s.begins_with("-")
	var digits := s.substr(1) if neg else s
	digits = digits.lstrip("0")
	if digits == "":
		return 0
	if digits.length() > 19 or (digits.length() == 19 and digits > ("9223372036854775808" if neg else "9223372036854775807")):
		return null
	if neg and digits == "9223372036854775808":
		return -9223372036854775807 - 1
	var n := digits.to_int()
	return -n if neg else n

# -- checking a config ------------------------------------------------------------------------------------------------

## What a calendar builder says is wrong with [param value] (npm [code]validateCalendarConfig[/code]): every message,
## in npm's order and words, empty when nothing is. Loud where [method read_config] is quiet: a value the reader
## takes may still have problems here (eras that overlap, a week with too few day names, version-2 keys on version
## 1), and the messages are for a person. It reads the value as JavaScript does, so its answers are npm's on any JSON
## value: an absent key prints [code]undefined[/code] and a null one [code]null[/code], a value prints as String() does,
## a string's or a list's [code]length[/code] is read as one, a string in place of a list is its characters, a
## comparison of mixed values coerces as JavaScript's [code]<[/code] does, and the eras are ordered for the overlap
## check by V8's sort (binary insertion, exact for fewer than 64 eras) with npm's comparator, a start that is not a
## number included.
##
## Where npm throws (a value that is null, eras or intercalary that is an object, a number or true, an entry that is
## null), this answers: a null value or entry reads as one with no keys; [code]eras must be a list[/code] or
## [code]intercalary must be a list[/code], in the place npm's loop over it would start, and no check of that list.
static func validate_config(value: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	var version: Variant = _js_get(value, "version")
	if not _is_number(version) or (version != 1 and version != 2):
		errors.append("Unsupported calendar version: %s" % _js_str(version))
	var grain: Variant = _js_get(value, "grain")
	if not (grain is String) or OWUnicode.trim_white_space(grain) == "":
		errors.append("Grain is required")
	var bundles: Variant = _js_get(value, "bundles")
	var months: Variant = _js_get(bundles, "months")
	var year: Variant = _js_get(bundles, "year")
	if _jt(months):
		var names: Variant = _js_get(months, "names")
		var lengths: Variant = _js_get(months, "lengths")
		if not (names is Array) or not (lengths is Array) or names.is_empty() or names.size() != lengths.size():
			errors.append("months.names and months.lengths must be same-length non-empty arrays")
		elif lengths.any(func(l) -> bool: return not _is_integer(l) or l < 1):
			errors.append("Every month length must be a whole number, 1 or more")
		if _jt(year):
			errors.append("year.steps is legal only when no months are defined (year length is derived from months)")
	elif _jt(year):
		var steps: Variant = _js_get(year, "steps")
		if not _is_integer(steps) or steps < 1:
			errors.append("year.steps must be a positive integer")
	var week: Variant = _js_get(bundles, "week")
	if _jt(week):
		var length: Variant = _js_get(week, "length")
		var names: Variant = _js_get(week, "names")
		if not _is_integer(length) or length < 1:
			errors.append("The week length must be a whole number, 1 or more")
		elif not (names is Array) or names.size() != length:
			errors.append("Give the week as many day names as its length")
	var inter: Variant = _js_get(value, "intercalary")
	if _nullish(inter):
		inter = []
	var inter_length: Variant = _js_get(inter, "length")
	if _is_number(inter_length) and inter_length > 0 and not _jt(months):
		errors.append("Festival days need months")
	var names_of_months: Variant = _js_get(months, "names")
	var month_count: int = names_of_months.size() if names_of_months is Array else 0
	var inter_items: Variant = _js_items(inter)
	if inter_items == null:
		errors.append("intercalary must be a list")
		inter_items = []
	for ic in inter_items:
		var name := _js_str(_js_get(ic, "name"))
		var after: Variant = _js_get(ic, "after_month")
		if not _is_integer(after) or after < 0 or after > month_count:
			errors.append("Festival day \"%s\": pick the month it follows" % name)
		var every: Variant = _js_get(ic, "every_years")
		if not _nullish(every) and (not _is_integer(every) or every < 1):
			errors.append("Festival day \"%s\": every N yrs must be a whole number, 1 or more" % name)
		var rule := _leap_rule_problem(ic)
		if rule != "":
			errors.append("Festival day \"%s\": %s" % [name, rule])
		if _is_number(version) and version == 1 and (not _nullish(_js_get(ic, "except")) or not _nullish(_js_get(ic, "offset"))):
			errors.append("Festival day \"%s\": except and offset need calendar version 2" % name)
	var eras: Variant = _js_get(value, "eras")
	if _nullish(eras):
		eras = []
	var era_items: Variant = _js_items(eras)
	if era_items == null:
		errors.append("eras must be a list")
		return errors
	for era in era_items:
		var name := _js_str(_js_get(era, "name"))
		var start: Variant = _js_get(era, "start")
		var end: Variant = _js_get(era, "end")
		var direction: Variant = _js_get(era, "direction")
		if not _jt(_js_get(era, "name")):
			errors.append("Every era needs a name")
		if not _is_finite(start):
			errors.append("Era \"%s\": start must be a number" % name)
		if not _nullish(end) and not _is_finite(end):
			errors.append("Era \"%s\": end must be a number" % name)
		if _direction_is(direction, "up") and not _nullish(end) and _js_le(end, start):
			errors.append("Era \"%s\": end must be after start" % name)
		if _direction_is(direction, "down") and not _nullish(end) and _js_le(start, end):
			errors.append("Era \"%s\": a counting-down era must end below its start" % name)
	var bound := _bounds_problem(value)
	if bound != "":
		errors.append(bound)
	var domains := _raw_era_domains(era_items)
	for i in domains.size():
		for j in range(i + 1, domains.size()):
			var a: Array = domains[i]
			var b: Array = domains[j]
			if _js_less(a[1], b[2]) is bool and _js_less(a[1], b[2]) and _js_less(b[1], a[2]) is bool and _js_less(b[1], a[2]):
				errors.append("Eras \"%s\" and \"%s\" overlap" % [_js_str(_js_get(a[0], "name")), _js_str(_js_get(b[0], "name"))])
	return errors

## npm's boundsProblem on a raw value: the first of the profile's size bounds it is past, in npm's order and words, or
## "". Only lists count as lists here (a string in place of one holds nothing), only strings as names, only numbers as
## lengths; [code]except[/code] counts on version 2 alone, and the longest year (the months' lengths plus every entry in
## [code]intercalary[/code]) is summed as JavaScript sums it, in doubles.
static func _bounds_problem(value: Variant) -> String:
	var bundles: Variant = _js_get(value, "bundles")
	var months: Variant = _js_get(bundles, "months")
	var week: Variant = _js_get(bundles, "week")
	var eras: Array = _list_of(_js_get(value, "eras"))
	var inter: Array = _list_of(_js_get(value, "intercalary"))
	var month_names: Array = _list_of(_js_get(months, "names"))
	var day_names: Array = _list_of(_js_get(week, "names"))
	if eras.size() > _MAX_ERAS:
		return "A calendar holds at most %d eras" % _MAX_ERAS
	if month_names.size() > _MAX_MONTHS:
		return "A calendar holds at most %d months" % _MAX_MONTHS
	var week_length: Variant = _js_get(week, "length")
	if (_is_number(week_length) and week_length > _MAX_WEEK) or day_names.size() > _MAX_WEEK:
		return "A week holds at most %d steps and %d names" % [_MAX_WEEK, _MAX_WEEK]
	if inter.size() > _MAX_INTERCALARY:
		return "A calendar holds at most %d festival days" % _MAX_INTERCALARY
	var version: Variant = _js_get(value, "version")
	if _is_number(version) and version == 2:
		for ic in inter:
			var ex: Variant = _js_get(ic, "except")
			if ex is Array and ex.size() > _MAX_EXCEPT:
				return "An except list holds at most %d numbers" % _MAX_EXCEPT
	var text_bound := "A name or template holds at most %d characters" % _MAX_TEXT
	for key in ["grain", "step_name", "format", "format_intercalary"]:
		if _too_long(_js_get(value, key)):
			return text_bound
	for e in eras:
		if _too_long(_js_get(e, "name")) or _too_long(_js_get(e, "abbrev")):
			return text_bound
	for n in month_names + day_names:
		if _too_long(n):
			return text_bound
	for ic in inter:
		if _too_long(_js_get(ic, "name")):
			return text_bound
	var lengths: Variant = _js_get(months, "lengths")
	if _jt(months) and lengths is Array:
		var longest := float(inter.size())
		for l in lengths:
			if _is_number(l):
				longest += float(l)
		if longest > float(_MAX_SAFE):
			return "A year holds at most 2^53 - 1 steps"
	return ""

## A list, or an empty one in place of anything else (npm's [code]Array.isArray(v) ? v : [][/code]).
static func _list_of(v: Variant) -> Array:
	return v if v is Array else []

## npm's leapRuleProblem on a raw entry: why its version-2 keys cannot be read, or "".
static func _leap_rule_problem(ic: Variant) -> String:
	var ex: Variant = _js_get(ic, "except")
	var off: Variant = _js_get(ic, "offset")
	if _nullish(ex) and _nullish(off):
		return ""
	var every: Variant = _js_get(ic, "every_years")
	if _nullish(every):
		return "except and offset need every_years"
	if not _nullish(off) and not _is_safe_int(off):
		return "offset must be a whole number"
	if not _nullish(ex):
		if not (ex is Array):
			return "except must be a list"
		var prev: Variant = every
		for d in ex:
			if not _is_positive_int(d) or _js_le(d, prev) or not _remainder_is_zero(d, prev):
				return "each except must be a multiple of the number before it, and larger"
			prev = d
	return ""

## [code](direction ?? 'up') === word[/code].
static func _direction_is(direction: Variant, word: String) -> bool:
	if _nullish(direction):
		return word == "up"
	return direction is String and direction == word

## npm's resolveEraDomains over raw eras, as [code][era, lo, hi][/code]: sorted by V8's sort with
## [code](a, b) => a.start - b.start[/code], an up era's open end the next up era's start, a down era's open end
## -Infinity; the values as given, so the overlap check compares them as JavaScript does.
static func _raw_era_domains(eras: Array) -> Array:
	var sorted := _v8_sort(eras, func(a, b) -> float: return _js_number(_js_get(a, "start")) - _js_number(_js_get(b, "start")))
	var out := []
	for i in sorted.size():
		var era: Variant = sorted[i]
		var start: Variant = _js_get(era, "start")
		var end: Variant = _js_get(era, "end")
		if _direction_is(_js_get(era, "direction"), "down"):
			out.append([era, -INF if _nullish(end) else end, start])
			continue
		var hi: Variant = end
		if _nullish(hi):
			hi = INF
			for j in range(i + 1, sorted.size()):
				if _direction_is(_js_get(sorted[j], "direction"), "up"):
					var next_start: Variant = _js_get(sorted[j], "start")
					hi = INF if _nullish(next_start) else next_start
					break
		out.append([era, start, hi])
	return out

## V8's Array.prototype.sort for fewer than 64 items (its TimSort is then one run: the leading run found, a strictly
## descending one reversed, then binary insertion), with a comparator that may answer NaN (read as "not less").
## Past 63 items the same insertion, which a consistent comparator sorts as V8 does.
static func _v8_sort(items: Array, compare: Callable) -> Array:
	var a := items.duplicate()
	var n := a.size()
	if n < 2:
		return a
	var run := 2
	var descending: bool = compare.call(a[1], a[0]) < 0
	for i in range(2, n):
		var order: float = compare.call(a[i], a[i - 1])
		if (descending and order >= 0) or (not descending and order < 0):
			break
		run += 1
	if descending:
		var head := a.slice(0, run)
		head.reverse()
		for i in run:
			a[i] = head[i]
	for start in range(run, n):
		var pivot: Variant = a[start]
		var left := 0
		var right := start
		while left < right:
			var mid := left + ((right - left) >> 1)
			if compare.call(pivot, a[mid]) < 0:
				right = mid
			else:
				left = mid + 1
		for p in range(start, left, -1):
			a[p] = a[p - 1]
		a[left] = pivot
	return a

# -- choosing a calendar ----------------------------------------------------------------------------------------------

## [method resolve_calendar]'s default: no calendar was ever chosen (npm's [code]undefined[/code]), apart from null, a
## choice of none. A StringName holding a private-use character, so no id read from JSON (a String) is ever it.
const NOT_CHOSEN := &"not chosen"

## The calendar [param active_id] names among [param elements] (npm [code]resolveCalendar[/code]):
## [method world_calendars]'s [code]{"id", "name", "calendar"}[/code], or null (bare numbers) for a null or empty id, an
## id no element with a calendar has (compared as JavaScript's [code]===[/code]: a number id is not its string), or an
## element whose calendar does not read; the first element of that id wins. Left out ([constant NOT_CHOSEN]) and with
## [code]{"fallback_to_only": true}[/code] (JavaScript's truthiness), the world's one calendar when it holds exactly one;
## null is an explicit "no calendar" and stays null. An unknown option, or options that are not a Dictionary, is the
## caller's mistake: pushed as an error, and the answer is null (npm throws a TypeError).
static func resolve_calendar(elements: Array, active_id: Variant = NOT_CHOSEN, options: Variant = null) -> Variant:
	var fallback := false
	if options != null:
		if not (options is Dictionary):
			push_error("OWCalendar.resolve_calendar: options is a Dictionary, such as {\"fallback_to_only\": true}; got %s" % var_to_str(options))
			return null
		for k in options:
			if not (k is String or k is StringName) or String(k) != "fallback_to_only":
				push_error("OWCalendar.resolve_calendar: unknown option '%s'. The keys are fallback_to_only." % str(k))
				return null
		fallback = _truthy(options.get("fallback_to_only"))
	if active_id is StringName and active_id == NOT_CHOSEN:
		if not fallback:
			return null
		var all := world_calendars(elements)
		return all[0] if all.size() == 1 else null
	if not _truthy(active_id):
		return null
	for c in world_calendars(elements):
		if _js_strict_equal(c["id"], active_id):
			return c
	return null

## The World's key that names its calendar: the id of the element that carries it.
const WORLD_KEY := "x_calendar"

## Which calendar speaks for a world (the calendar profile's "Which calendar speaks"). [param world] is the World's own
## keys (world.json, or the body GET /world returns). Its [constant WORLD_KEY] names the element whose calendar speaks,
## by an id matched as written: when an element of [param elements] with that id carries a calendar that reads, the
## first such one speaks, as [method world_calendars]'s [code]{"id", "name", "calendar"}[/code]; anything else named (an
## id no element has, the id in another letter case, an element with no calendar or one that does not read, a value
## that is no String) gives null, never another calendar in its place. Named none (the key absent or null): the world's
## only calendar, or null when it holds several. A tool may keep its person's own pick over this
## ([method resolve_calendar]).
static func speaking_calendar(world: Variant, elements: Array) -> Variant:
	var named: Variant = world.get(WORLD_KEY) if world is Dictionary else null
	if named == null:
		var all := world_calendars(elements)
		return all[0] if all.size() == 1 else null
	if not (named is String):
		return null
	for c in world_calendars(elements):
		if c["id"] is String and c["id"] == named:
			return c
	return null

# -- JavaScript's values ----------------------------------------------------------------------------------------------

## A key that is not there, apart from null (JavaScript's undefined), for [method validate_config]'s reading: a
## StringName, which no JSON value is (a const Dictionary compared by identity did not hold: in Godot 4.7.2 the one
## another script passed in was not [code]is_same[/code] as this file's own).
const _UNDEFINED := &"undefined"

static func _undef(v: Variant) -> bool:
	return v is StringName and v == _UNDEFINED

## [code]v == null[/code] in JavaScript: null or undefined.
static func _nullish(v: Variant) -> bool:
	return v == null or _undef(v)

## JavaScript's truthiness, undefined included.
static func _jt(v: Variant) -> bool:
	return not _undef(v) and _truthy(v)

## JavaScript's String(v), undefined included.
static func _js_str(v: Variant) -> String:
	return "undefined" if _undef(v) else _js_string(v)

## [code]o.key[/code] in JavaScript on a JSON value: an object's own key, a string's or a list's [code]length[/code]
## (a string's in UTF-16 code units); anything else undefined (where npm reads a key of null it throws: read here as
## undefined).
static func _js_get(o: Variant, key: String) -> Variant:
	if o is Dictionary and not _undef(o):
		return o[key] if o.has(key) else _UNDEFINED
	if key == "length":
		if o is String:
			return _utf16_len(o)
		if o is Array:
			return o.size()
	return _UNDEFINED

## What a JavaScript for-of reads from [param v]: a list's items, a string's characters (code points), or null for
## anything that is not iterable (npm throws).
static func _js_items(v: Variant) -> Variant:
	if v is Array:
		return v
	if v is String:
		var out := []
		for i in v.length():
			out.append(v[i])
		return out
	return null

## Number.isFinite.
static func _is_finite(v: Variant) -> bool:
	return _is_number(v) and not is_nan(float(v)) and not is_inf(float(v))

## JavaScript's ToNumber on a JSON value (an object or a list through its String()).
static func _js_number(v: Variant) -> float:
	if _undef(v):
		return NAN
	match typeof(v):
		TYPE_NIL:
			return 0.0
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return _string_to_number(String(v))
	return _string_to_number(_js_string(v))

## JavaScript's StringToNumber: trimmed of its white space, empty is 0, a decimal (with Infinity), or 0x, 0o, 0b.
static func _string_to_number(s: String) -> float:
	_compile()
	var t := _js_trim(s)
	if t == "":
		return 0.0
	if _decimal_re.search(t) != null:
		if t.ends_with("Infinity"):
			return -INF if t.begins_with("-") else INF
		return t.to_float()
	var m := _radix_re.search(t)
	if m != null:
		var base := 16 if m.get_string(1) != "" else (8 if m.get_string(2) != "" else 2)
		var n := 0.0
		for ch in m.get_string(1) + m.get_string(2) + m.get_string(3):
			n = n * base + "0123456789abcdef".find(ch.to_lower())
		return n
	return NAN

## JavaScript's [code]a < b[/code] (the Abstract Relational Comparison): true, false, or null where it is undefined (a
## NaN), so [code]a <= b[/code] is [code]_js_less(b, a) == false[/code]. Two strings compare by UTF-16 code units.
static func _js_less(a: Variant, b: Variant) -> Variant:
	var pa: Variant = _js_primitive(a)
	var pb: Variant = _js_primitive(b)
	if pa is String and pb is String:
		return _utf16_less(pa, pb)
	var na := _js_number(pa)
	var nb := _js_number(pb)
	if is_nan(na) or is_nan(nb):
		return null
	return na < nb

## JavaScript's [code]a <= b[/code]: not [code]b < a[/code], and false where that is undefined.
static func _js_le(a: Variant, b: Variant) -> bool:
	var r: Variant = _js_less(b, a)
	return r is bool and not r

static func _js_primitive(v: Variant) -> Variant:
	if _undef(v):
		return v
	if v is Array or v is Dictionary:
		return _js_string(v)
	if v is StringName:
		return String(v)
	return v

## JavaScript's [code]d % prev === 0[/code] (the remainder takes the dividend's sign; -0 is 0; NaN is not).
static func _remainder_is_zero(d: Variant, prev: Variant) -> bool:
	var r := fmod(_js_number(d), _js_number(prev))
	return not is_nan(r) and r == 0.0

## JavaScript's [code]===[/code] on JSON values: numbers by value (1 and 1.0 alike), strings by text, booleans and null
## by value, a list or object only itself.
static func _js_strict_equal(a: Variant, b: Variant) -> bool:
	if _is_number(a) and _is_number(b):
		return a == b
	if (a is String or a is StringName) and (b is String or b is StringName):
		return String(a) == String(b)
	if a is bool and b is bool:
		return a == b
	if a == null and b == null:
		return true
	if (a is Array or a is Dictionary) and typeof(a) == typeof(b):
		return is_same(a, b)
	return false

## A string's JavaScript length: UTF-16 code units, an astral character two.
static func _utf16_len(s: String) -> int:
	var n := s.length()
	for i in s.length():
		if s.unicode_at(i) > 0xFFFF:
			n += 1
	return n

## Code unit order: code point order but where an astral character (its high surrogate, D800 to DBFF) meets one from
## E000 to FFFF.
static func _utf16_less(a: String, b: String) -> bool:
	var ua := a.to_utf16_buffer()
	var ub := b.to_utf16_buffer()
	var i := 0
	while i < ua.size() and i < ub.size():
		var ca := ua.decode_u16(i)
		var cb := ub.decode_u16(i)
		if ca != cb:
			return ca < cb
		i += 2
	return ua.size() < ub.size()

## String.prototype.trim: JavaScript's white space off both ends, in one pass (a regular expression's
## [code]\s+\z[/code] half took quadratic time on a long run of white space inside the text).
static func _js_trim(s: String) -> String:
	var a := 0
	var b := s.length()
	while a < b and _is_js_ws(s.unicode_at(a)):
		a += 1
	while b > a and _is_js_ws(s.unicode_at(b - 1)):
		b -= 1
	return s.substr(a, b - a)

# -- numbers and truth ------------------------------------------------------------------------------------------------

## A JSON number: an int or a float, never a boolean (and the check comes first: Godot's == between a boolean and a
## number is a script error, not false).
static func _is_number(v: Variant) -> bool:
	return v is int or v is float

## Number.isInteger: a number, finite and whole.
static func _is_integer(v: Variant) -> bool:
	if v is int:
		return true
	return v is float and not is_nan(v) and not is_inf(v) and floor(v) == v

## Number.isSafeInteger: whole and at most 2^53 - 1 in size.
static func _is_safe_int(v: Variant) -> bool:
	if v is int:
		return absi(v) <= _MAX_SAFE
	return _is_integer(v) and absf(v) <= float(_MAX_SAFE)

static func _is_positive_int(v: Variant) -> bool:
	return _is_safe_int(v) and v >= 1

## JavaScript's truthiness: null, false, 0, NaN and "" are false; an empty list or object is true.
static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT:
			return v != 0
		TYPE_FLOAT:
			return v != 0.0 and not is_nan(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v) != ""
	return true

# -- strict JSON ------------------------------------------------------------------------------------------------------

## True when [param text] is one JSON value (RFC 8259) with JSON's white space around it, as JSON.parse reads it.
## Godot's parser decides the value after; this only refuses the text it would take and JSON.parse would not.
static func _is_strict_json(text: String) -> bool:
	var at := _json_value(text, _json_ws(text, 0), 0)
	return at >= 0 and _json_ws(text, at) == text.length()

static func _json_ws(s: String, i: int) -> int:
	while i < s.length() and (s[i] == " " or s[i] == "\t" or s[i] == "\n" or s[i] == "\r"):
		i += 1
	return i

## The index just past the value at [param i], or -1.
static func _json_value(s: String, i: int, depth: int) -> int:
	if i >= s.length() or depth > 512:
		return -1
	var c := s[i]
	if c == "{" or c == "[":
		var close := "}" if c == "{" else "]"
		i = _json_ws(s, i + 1)
		if i < s.length() and s[i] == close:
			return i + 1
		while true:
			if c == "{":
				if i >= s.length() or s[i] != "\"":
					return -1
				i = _json_ws(s, _json_string(s, i))
				if i < 0 or i >= s.length() or s[i] != ":":
					return -1
				i = _json_ws(s, i + 1)
			i = _json_value(s, i, depth + 1)
			if i < 0:
				return -1
			i = _json_ws(s, i)
			if i >= s.length():
				return -1
			if s[i] == close:
				return i + 1
			if s[i] != ",":
				return -1
			i = _json_ws(s, i + 1)
	if c == "\"":
		return _json_string(s, i)
	for word in ["true", "false", "null"]:
		if s.substr(i, word.length()) == word:
			return i + word.length()
	return _json_number(s, i)

static func _json_string(s: String, i: int) -> int:
	i += 1
	while i < s.length():
		var u := s.unicode_at(i)
		if u == 0x22:
			return i + 1
		if u < 0x20:
			return -1
		if u == 0x5C:
			if i + 1 >= s.length():
				return -1
			var e := s[i + 1]
			if e == "u":
				if i + 6 > s.length():
					return -1
				for k in range(i + 2, i + 6):
					if not "0123456789abcdefABCDEF".contains(s[k]):
						return -1
				i += 6
				continue
			if not "\"\\/bfnrt".contains(e):
				return -1
			i += 2
			continue
		i += 1
	return -1

static func _json_number(s: String, i: int) -> int:
	if i < s.length() and s[i] == "-":
		i += 1
	if i >= s.length():
		return -1
	if s[i] == "0":
		i += 1
	elif s[i] >= "1" and s[i] <= "9":
		i = _json_digits(s, i)
	else:
		return -1
	if i < s.length() and s[i] == ".":
		var j := _json_digits(s, i + 1)
		if j == i + 1:
			return -1
		i = j
	if i < s.length() and (s[i] == "e" or s[i] == "E"):
		i += 1
		if i < s.length() and (s[i] == "+" or s[i] == "-"):
			i += 1
		var j := _json_digits(s, i)
		if j == i:
			return -1
		i = j
	return i

static func _json_digits(s: String, i: int) -> int:
	while i < s.length() and s[i] >= "0" and s[i] <= "9":
		i += 1
	return i
