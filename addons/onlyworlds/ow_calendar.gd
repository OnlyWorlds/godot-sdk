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
## and [code]after_month[/code] is [code]Number.isInteger[/code] (any whole number). JSON cannot tell 1 from 1.0 and
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
const _I62 := 4611686018427387904.0            # an after_month past it matches no month, and is kept as -1
const _MAX_YEAR_CORRECTION := 10000            # npm's cap on the year seed's correction laps, per direction
## JavaScript's white space (\s and String.prototype.trim): WhiteSpace and LineTerminator.
const _JS_WS := "\\t\\n\\x{0B}\\f\\r \\x{A0}\\x{1680}\\x{2000}-\\x{200A}\\x{2028}\\x{2029}\\x{202F}\\x{205F}\\x{3000}\\x{FEFF}"
## A known token with no value, so the close-up pass finds it (npm's U+E000, a private-use code point).
const _EMPTY_KNOWN := "\ue000"

static var _token_re: RegEx
static var _collapse_re: RegEx
static var _runs_re: RegEx
static var _edges_re: RegEx

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
	## 0 before month 1, k after month k; one past the months (or below 0) sits in no month, kept as -1 when huge.
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

## A step taken apart (npm StepBreakdown). Null where the structure does not exist.
class Breakdown:
	var step := 0
	## The year index, from 0 at step 0.
	var abs_year := 0
	## The era's year (restart arithmetic applied), or [member abs_year] with no era or a label era.
	var year := 0
	var era: Era = null
	## 1-based, or null (an intercalary day, no months, a day placed nowhere).
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
## [code]offset[/code] or [code]except[/code] with no [code]every_years[/code] too, which the list does not name).
static func read_config(value: Variant) -> Calendar:
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
			var ic := _read_intercalary(e, cal.version)
			if ic == null:
				return null
			cal.intercalary.append(ic)
	var fmt: Variant = cfg.get("format")
	cal.format = fmt if fmt is String else null
	var fmt_i: Variant = cfg.get("format_intercalary")
	cal.format_intercalary = fmt_i if fmt_i is String else null
	return cal

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

static func _read_intercalary(e: Variant, version: int) -> Intercalary:
	if not (e is Dictionary) or not (e.get("name") is String) or not _is_integer(e.get("after_month")):
		return null
	var every: Variant = e.get("every_years")
	if every != null and not _is_positive_int(every):
		return null
	var ic := Intercalary.new()
	ic.raw = e
	ic.name = e["name"]
	var after: float = float(e["after_month"])
	ic.after_month = int(after) if absf(after) < _I62 else -1
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
## "intercalary" (a the entry) or "" (no slot: a day placed nowhere, or no months), and skipped the days before it
## that the free week does not count.
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
	b.abs_year = absolute_year(cal, step)
	var slot: Array = ["", null, null, 0]
	if cal.has_months:
		slot = _slot(cal, b.abs_year, step - year_start_step(cal, b.abs_year))
	b.era = era_for_step(cal, step)
	b.year = display_year(cal, step, b.era)
	if slot[0] == "month":
		b.month = slot[1]
		b.month_name = cal.month_names[slot[1] - 1]
		b.day = slot[2]
	elif slot[0] == "intercalary":
		b.intercalary = (slot[1] as Intercalary).name
	b.weekday = _weekday(cal, step, b.abs_year, slot)
	return b

# -- words ------------------------------------------------------------------------------------------------------------

## [param step] in words (the profile's step 5; npm [code]formatStep[/code]): the calendar's template, or the default
## for the step (an intercalary day's, with months, without), each known token filled; a known token with no value
## prints empty and one [code],[/code] [code];[/code] [code]·[/code] or white space on each side of it closes up (a dash
## never does); an unknown token prints as written. A null calendar prints the bare step.
static func format_step(cal: Calendar, step: int) -> String:
	if cal == null:
		return str(step)
	var b := breakdown_step(cal, step)
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
	var out := "".join(parts)
	out = _collapse_re.sub(out, " ", true)
	out = _runs_re.sub(out, " ", true)
	out = _edges_re.sub(out, "", true)   # trim, then the separators left at either edge: one pass covers both
	return out

static func _compile() -> void:
	if _token_re != null:
		return
	_token_re = RegEx.create_from_string("\\{([a-z_]+)\\}")
	var ws := "[" + _JS_WS + "]"
	_collapse_re = RegEx.create_from_string(ws + "*[,;·]?" + ws + "*" + _EMPTY_KNOWN + ws + "*[,;·]?" + ws + "*")
	_runs_re = RegEx.create_from_string(ws + "{2,}")
	_edges_re = RegEx.create_from_string("^[" + _JS_WS + ",;·]+|[" + _JS_WS + ",;·]+$")

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
