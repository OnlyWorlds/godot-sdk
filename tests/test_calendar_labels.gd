extends RefCounted
## OWCalendar's labels, durations, month starts, parse_date, validate_config and resolve_calendar against the npm SDK's
## own answers: tests/data/calendar_parity.json, made by codegen/generate_calendar_parity.mjs from the package's built
## code (the file names the version and commit). Every calendar dist.148's profile fixture reads as one, by name, and
## the calendars the generator writes for the traps (each says what it is for). Where npm throws, Godot answers instead:
## those answers are here, by name. Then what vectors cannot carry: a caller's mistake, the answers' shapes, a null
## calendar, numbers past JavaScript's, and the lowercasing Godot does not reproduce.

const PARITY := "res://tests/data/calendar_parity.json"
const CALENDAR := "res://codegen/schema-dist/profiles/calendar.fixture.json"
## The profile fixture the vectors were made from: dist.148's (and dist.147's) calendar.fixture.json, whose 91 cases the
## vendored fixture holds unchanged, by name; the vectors are remade when the TypeScript SDK reads serial 149.
const DIST_148_FIXTURE_SHA256 := "1ae922bc7af243453cac62053a31b2d10180e0ebb4843639dde9479f16e87206"

## Godot's answer where npm's validateCalendarConfig throws (a TypeError: a list it loops over is not iterable, or a
## key read on null).
const VALIDATE_WHERE_NPM_THROWS := {
	"refuse-eras-not-list": ["eras must be a list"],
	"refuse-eras-falsy": ["eras must be a list"],
	"refuse-eras-false": ["eras must be a list"],
	"refuse-intercalary-not-list": ["intercalary must be a list"],
	"null": ["Unsupported calendar version: undefined", "Grain is required"],
	"eras-an-object": ["eras must be a list"],
	"eras-a-number": ["eras must be a list"],
	"eras-true": ["eras must be a list"],
	"eras-entry-null": ["Every era needs a name", "Era \"undefined\": start must be a number"],
	"festival-an-object": ["intercalary must be a list"],
	"festival-entry-null": ["Festival day \"undefined\": pick the month it follows"],
	"festival-a-number": ["intercalary must be a list"],
}

## npm's option names and Godot's: the two spellings swap, so each package's other spelling stays an unknown key.
const OPTION_NAMES := {"fallbackToOnly": "fallback_to_only", "fallback_to_only": "fallbackToOnly"}

var _doc: Dictionary
var _fx: Dictionary

func _parity() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(PARITY))
	return _doc

func _fixture_values() -> Dictionary:
	if _fx.is_empty():
		for c in JSON.parse_string(FileAccess.get_file_as_string(CALENDAR))["cases"]:
			_fx[c["name"]] = c["value"]
	return _fx

func get_cases() -> Array:
	var out := []
	for c in _parity()["calendars"]:
		var name: String = c["case"] if c.has("case") else c["name"]
		out.append(["parity:" + name, _calendar.bind(c)])
	out.append(["parity:validate", _validate])
	out.append(["parity:resolve", _resolve])
	return out

## A JSON number as Godot's JSON reads it, made the int npm's whole number is.
func _int(v: Variant) -> Variant:
	return int(v) if v is float else v

func _calendar(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var name: String = c["case"] if c.has("case") else c["name"]
	var value: Variant = c["value"] if c.has("value") else _fixture_values()[name]
	var cal := OWCalendar.read_value(value)
	t.ok(cal != null, "%s: a calendar" % name)
	if cal == null:
		t.done()
		return
	for row in c["labels"]:
		var step: int = int(row[0])
		t.eq(OWCalendar.format_year_label(cal, step), row[1], "%s: format_year_label(%d)" % [name, step])
		t.eq(OWCalendar.format_mid_label(cal, step), row[2], "%s: format_mid_label(%d)" % [name, step])
	for row in c["month_starts"]:
		var want := []
		for m in row[1]:
			want.append({"month": int(m[0]), "name": m[1], "step": int(m[2])})
		t.eq(OWCalendar.month_start_steps(cal, int(row[0])), want, "%s: month_start_steps(%d)" % [name, int(row[0])])
	t.eq(OWCalendar.approx_year_length(cal), _int(c["approx_year_length"]), "%s: approx_year_length" % name)
	for row in c["durations"]:
		var n: float = row[0]
		if row.size() > 2:   # a fraction's exact bits: Godot's JSON reads some long decimals as a neighbouring double
			var be: PackedByteArray = String(row[2]).hex_decode()
			be.reverse()
			n = be.decode_double(0)
		t.eq(OWCalendar.format_duration(cal, n), row[1], "%s: format_duration(%s)" % [name, String.num_scientific(n)])
	for row in c["era_years"]:
		var era: OWCalendar.Era = cal.eras[int(row[0])]
		t.eq(OWCalendar.abs_year_for_era_year(cal, era, int(row[1])), int(row[2]),
			"%s: abs_year_for_era_year(%s, %d)" % [name, era.name, int(row[1])])
	var thrown := 0
	for row in c["parse"]:
		var options: Variant = null if row[1] == null else {"now": int(row[1])}
		var got := OWCalendar.parse_date(cal, row[0], options)
		var want: Dictionary = row[2]
		var label := "%s: parse_date(%s, now %s)" % [name, JSON.stringify(row[0]), str(row[1])]
		if want.has("throws"):
			thrown += 1   # npm's TypeError on an abbrev that is not a string: Godot's answer is test_an_abbrev_not_a_string
			t.ok(got.has("step") or got.has("error"), label + ": an answer where npm throws")
			continue
		t.eq(got, {"step": int(want["step"])} if want.has("step") else want, label)
	t.eq(thrown, {"era-label-array-abbrev": 75, "era-label-number-abbrev": 84}.get(name, 0), "%s: where npm throws" % name)
	t.done()

func _validate(t) -> void:
	var rows: Array = _parity()["validate"]
	t.eq(rows.size(), 162, "the validate rows")
	var thrown := 0
	for row in rows:
		var name: String = row["case"] if row.has("case") else row["name"]
		var value: Variant = row["value"] if row.has("name") else _fixture_values()[name]
		if row.has("case") and value is String:
			value = JSON.parse_string(value)
		var want: Variant = row["answer"]
		if want is Dictionary:
			thrown += 1
			t.ok(VALIDATE_WHERE_NPM_THROWS.has(name), "%s: npm throws (%s); Godot's answer is listed" % [name, want["throws"]])
			want = VALIDATE_WHERE_NPM_THROWS.get(name, [])
		t.eq(OWCalendar.validate_config(value), PackedStringArray(want), "validate_config(%s)" % name)
	t.eq(thrown, VALIDATE_WHERE_NPM_THROWS.size(), "every listed answer is a row where npm throws")
	t.done()

func _resolve(t) -> void:
	var sets: Dictionary = _parity()["element_sets"]
	var rows: Array = _parity()["resolve"]
	t.eq(rows.size(), 784, "the resolve rows")
	for row in rows:
		var elements: Array = sets[row["set"]]
		var active: Variant = row["active"] if row.has("active") else OWCalendar.NOT_CHOSEN
		var options: Variant = null
		if row.has("options"):
			options = {}
			for k in row["options"]:
				options[OPTION_NAMES.get(k, k)] = row["options"][k]
		var want: Variant = row["answer"]
		if want is Dictionary and want.has("throws"):
			want = null    # npm's TypeError on an unknown option: Godot pushes the error and answers null
		var got: Variant = OWCalendar.resolve_calendar(elements, active, options)
		if got != null:
			got = {"id": got["id"], "name": got["name"]}
		t.eq(got, want, "resolve_calendar(%s, %s, %s)" % [row["set"], var_to_str(row.get("active", "<not chosen>")), var_to_str(options)])
	t.done()

# -- what the vectors cannot carry -------------------------------------------------------------------------------------

func _two() -> OWCalendar.Calendar:
	return OWCalendar.read_value({"version": 1, "grain": "day", "bundles": {"months": {"names": ["Frost", "Thaw"], "lengths": [10, 10]}},
		"eras": [{"name": "After Gate", "abbrev": "AG", "start": 0}]})

func test_the_vectors_name_their_source(t) -> void:
	var doc := _parity()
	t.eq(doc["npm"]["package"], "@onlyworlds/sdk", "the package")
	t.ok(doc["npm"]["commit"] is String and doc["npm"]["commit"].length() == 7, "the commit")
	# Made from dist.148's fixture, not the vendored dist.149 one: serial 149's hundred new cases are bounds and dates
	# past the exact range, which the TypeScript SDK does not read yet, so its answers there would be the old reading.
	# The vectors move when it takes serial 149; the 91 cases they were made from are unchanged in dist.149.
	t.eq(doc["fixture_sha256"], DIST_148_FIXTURE_SHA256, "made from dist.148's fixture")
	var named := 0
	for c in doc["calendars"]:
		if c.has("case"):
			named += 1
	t.eq(named, 48, "every calendar of the fixture")
	t.done()

func test_parse_refuses_a_callers_mistake(t) -> void:
	var cal := _two()
	t.eq(OWCalendar.parse_date(cal, "454", {"Now": 12}),
		{"error": "parse_date: unknown option 'Now'. The keys are now.", "refused": "Now"}, "an unknown key, before the input is read")
	t.eq(OWCalendar.parse_date(cal, "Frost 3", 12)["refused"], "options", "options that are not a Dictionary")
	for bad in ["12", 1.5, true, [1], INF]:
		t.eq(OWCalendar.parse_date(cal, "Frost 3", {"now": bad})["refused"], "now", "now %s" % var_to_str(bad))
	t.eq(OWCalendar.parse_date(cal, "Frost 3", {"now": 25.0}), {"step": 22}, "now 25.0 is 25: year 1, Frost 3")
	t.eq(OWCalendar.parse_date(cal, "Frost 3", {"now": 25}), {"step": 22}, "now 25")
	t.eq(OWCalendar.parse_date(cal, "Frost 3", {"now": null}), {"error": "add a year (the world clock has no now set)"}, "now null is no now")
	t.eq(OWCalendar.parse_date(cal, "Frost 3", {}), {"error": "add a year (the world clock has no now set)"}, "no options")
	t.done()

func test_parse_answers_shape(t) -> void:
	var cal := _two()
	var ok := OWCalendar.parse_date(cal, "3 Thaw 2 AG")
	t.eq(ok.keys(), ["step"], "a date: one key")
	t.eq(typeof(ok["step"]), TYPE_INT, "the step an int")
	t.eq(ok["step"], 32, "3 Thaw of year 2")
	t.ok(not OWCalendar.is_parse_error(ok), "not an error")
	var bad := OWCalendar.parse_date(cal, "3 Thaw zzz")
	t.eq(bad, {"error": "unrecognized: \"zzz\""}, "an error: one key, npm's words, the word as normalized")
	t.ok(OWCalendar.is_parse_error(bad), "an error")
	t.done()

func test_a_null_calendar_reads_bare_numbers(t) -> void:
	t.eq(OWCalendar.format_year_label(null, -5), "-5", "year label")
	t.eq(OWCalendar.format_mid_label(null, 7), "7", "mid label")
	t.eq(OWCalendar.approx_year_length(null), null, "no year")
	t.eq(OWCalendar.month_start_steps(null, 0), [], "no months")
	t.eq(OWCalendar.format_duration(null, -3), "3 steps", "steps")
	t.eq(OWCalendar.format_duration(null, 1), "1 step", "one step")
	t.eq(OWCalendar.parse_date(null, " -12 "), {"step": -12}, "a bare step")
	t.eq(OWCalendar.parse_date(null, "5 AE"), {"error": "no calendar: only a bare step reads"}, "words")
	t.done()

func test_numbers_past_javascripts(t) -> void:
	var cal := _two()
	t.eq(OWCalendar.parse_date(cal, "9007199254740993"), {"step": 9007199254740993}, "past 2^53, exact (npm: ...992)")
	t.eq(OWCalendar.parse_date(cal, "9223372036854775807"), {"step": 9223372036854775807}, "the largest int")
	t.eq(OWCalendar.parse_date(cal, "-9223372036854775808"), {"step": -9223372036854775807 - 1}, "the smallest int")
	t.eq(OWCalendar.parse_date(cal, "9223372036854775808"), {"error": "unrecognized: \"9223372036854775808\""}, "past a 64-bit int")
	t.eq(OWCalendar.parse_date(cal, "-000000000000000000000012"), {"step": -12}, "leading zeros are no size")
	t.eq(OWCalendar.parse_date(cal, "Frost 99999999999999999999"), {"error": "unrecognized: \"99999999999999999999\""}, "beside a word")
	t.done()

## The profile (serial 149): a date whose step, year index plus a leap rule's offset, or shown year is past the safe
## integers is a plain number. The fixture reads format_step and breakdown_step; the two labels follow it here.
func test_a_date_past_the_exact_range_is_a_plain_number_in_every_label(t) -> void:
	# An era starting at -(2^53 - 1): step 0 shows year 2^53 there (the fixture's era-starting-at-the-line case).
	var long := OWCalendar.read_value({"version": 1, "grain": "year", "eras": [{"name": "Long", "abbrev": "L", "start": -9007199254740991}]})
	t.ok(OWCalendar.is_past_exact_range(long, 0), "step 0 is past the range")
	t.eq(OWCalendar.format_year_label(long, 0), "0", "the year label is the plain step, never a rounded year")
	t.eq(OWCalendar.format_mid_label(long, 0), "0", "the mid label too")
	t.ok(not OWCalendar.is_past_exact_range(long, -9007199254740991), "the era's first year is inside the range")
	t.eq(OWCalendar.format_year_label(long, -9007199254740991), "1 L", "and is worded")
	# A leap rule's offset at the line: year 0 plus it is inside, year 1 plus it past; the mid label's day and its
	# intercalary day are worded in year 0, and a date of year 1 is the plain step.
	var leap := OWCalendar.read_value({"version": 2, "grain": "day", "bundles": {"months": {"names": ["A"], "lengths": [1]}},
		"intercalary": [{"name": "Leap", "after_month": 1, "every_years": 1, "offset": 9007199254740991}]})
	t.eq(OWCalendar.format_mid_label(leap, 0), "1 A 0", "a day of year 0")
	t.eq(OWCalendar.format_mid_label(leap, 1), "Leap 0", "the leap day of year 0")
	t.eq(OWCalendar.format_mid_label(leap, 2), "2", "a day of year 1: the plain step")
	t.eq(OWCalendar.format_year_label(leap, 3), "3", "its leap day's year label too")
	var b := OWCalendar.breakdown_step(leap, 2)
	t.eq([b.step, b.abs_year, b.year, b.era, b.month, b.day, b.intercalary, b.weekday], [2, null, null, null, null, null, null, null],
		"its breakdown: the step, every other field null")
	t.done()

func test_an_abbrev_not_a_string(t) -> void:
	# npm's parseDate throws a TypeError here (it lowercases the abbrev); Godot passes over it as no word to match.
	var five := OWCalendar.read_value({"version": 1, "grain": "year", "eras": [{"name": "Fifth", "abbrev": 5, "start": 0}]})
	t.eq(OWCalendar.parse_date(five, "3 5"), {"error": "expected a year"}, "two numbers, no era word")
	t.eq(OWCalendar.parse_date(five, "Year 3 Fifth"), {"step": 2}, "the name still reads (as npm, which matches it first)")
	t.eq(OWCalendar.format_year_label(five, 2), "3 5", "the label prints it")
	var lists := OWCalendar.read_value({"version": 1, "grain": "year", "eras": [{"name": "More", "abbrev": ["a", "b"], "start": 0}]})
	t.eq(OWCalendar.parse_date(lists, "1 a,b"), {"error": "unrecognized: \"a\""}, "a list's printed words are no era")
	t.done()

func test_the_lowercasing_godot_does_not_reproduce(t) -> void:
	# JavaScript lowers a final capital sigma to ς (it reads the next character); Godot to σ everywhere. npm answers
	# "σασ 5" unrecognized: "σασ" and "5 σας" step 4 (Node 22, sdk 3cd810b); Godot the other way round.
	var cal := OWCalendar.read_value({"version": 1, "grain": "year", "eras": [{"name": "ΣΑΣ", "start": 0}]})
	t.eq(OWCalendar.parse_date(cal, "σασ 5"), {"step": 4}, "the name lowers to σασ here")
	t.eq(OWCalendar.parse_date(cal, "5 σας"), {"error": "unrecognized: \"σας\""}, "a typed final sigma is not σ")
	t.eq(OWCalendar.parse_date(cal, "ΣΑΣ 5"), {"step": 4}, "the name as written reads in both")
	t.done()

func test_a_step_name_not_a_string(t) -> void:
	# npm throws a TypeError (it trims the value); Godot reads the grain.
	var cal := OWCalendar.read_value({"version": 1, "grain": "day", "step_name": 5})
	t.eq(OWCalendar.format_duration(cal, 3), "3 days", "the grain's word")
	t.eq(OWCalendar.format_duration(cal, 2.5), "2.5 days", "a fraction of a step")
	t.done()

func test_resolve_never_chosen_is_its_own_value(t) -> void:
	var one := [{"id": "c1", "name": "Imperial", "atlas_calendar": {"version": 1, "grain": "day"}}]
	t.eq(OWCalendar.resolve_calendar(one), null, "never chosen, no fallback")
	t.eq(OWCalendar.resolve_calendar(one, OWCalendar.NOT_CHOSEN, {"fallback_to_only": true})["id"], "c1", "never chosen: the only one")
	t.eq(OWCalendar.resolve_calendar(one, null, {"fallback_to_only": true}), null, "null is a choice of none")
	t.eq(OWCalendar.resolve_calendar(one, String(OWCalendar.NOT_CHOSEN), {"fallback_to_only": true}), null, "its text is an id, not the sentinel")
	t.eq(OWCalendar.resolve_calendar(one, "c1")["calendar"].grain, "day", "the calendar read")
	t.eq(OWCalendar.resolve_calendar(one, "c1", {"fallbackToOnly": true}), null, "an unknown key: refused, not dropped")
	t.eq(OWCalendar.resolve_calendar(one, "c1", true), null, "options that are not a Dictionary")
	t.done()

func test_month_starts_shape(t) -> void:
	var starts := OWCalendar.month_start_steps(_two(), -1)
	t.eq(starts, [{"month": 1, "name": "Frost", "step": -20}, {"month": 2, "name": "Thaw", "step": -10}], "year -1")
	t.eq(starts[0].keys(), ["month", "name", "step"], "npm's keys, in its order")
	t.eq(typeof(starts[1]["step"]), TYPE_INT, "ints")
	t.done()

func test_validate_reads_a_calendar_read_config_takes(t) -> void:
	# The builder is loud where the reader is quiet: a value read_config takes can still have problems.
	var raw := {"version": 1, "grain": "day", "bundles": {"months": {"names": ["A"], "lengths": [5]}, "week": {"length": 3, "names": ["x"]}},
		"eras": [{"name": "Old", "start": 0, "end": 10}, {"name": "New", "start": 5}]}
	t.ok(OWCalendar.read_config(raw) != null, "a calendar")
	t.eq(OWCalendar.validate_config(raw), PackedStringArray(["Give the week as many day names as its length", "Eras \"Old\" and \"New\" overlap"]), "two problems")
	t.eq(OWCalendar.validate_config(OWCalendar.read_config(raw).raw), OWCalendar.validate_config(raw), "the read calendar's raw value")
	t.done()

func test_validate_names_the_size_bound_past_its_line_and_not_at_it(t) -> void:
	# As npm 4.212.0's validateCalendarConfig: 256 eras and a year of 2^53 - 1 steps are inside the profile's bounds
	# (serial 149), 257 eras and a year one step longer are past them.
	var eras_of := func(n: int) -> Dictionary:
		var eras := []
		for i in n:
			eras.append({"name": "E%d" % i, "start": i * 10, "end": i * 10 + 5})
		return {"version": 1, "grain": "year", "eras": eras}
	var year_of := func(lengths: Array) -> Dictionary:
		var names := []
		for i in lengths.size():
			names.append("M%d" % i)
		return {"version": 1, "grain": "day", "bundles": {"months": {"names": names, "lengths": lengths}}}
	var safe := 9007199254740991
	t.eq(OWCalendar.validate_config(eras_of.call(256)), PackedStringArray(), "256 eras: at the line")
	t.eq(OWCalendar.validate_config(eras_of.call(257)), PackedStringArray(["A calendar holds at most 256 eras"]), "257 eras: past it")
	t.eq(OWCalendar.validate_config(year_of.call([safe])), PackedStringArray(), "a year of 2^53 - 1 steps: at the line")
	t.eq(OWCalendar.validate_config(year_of.call([safe, 1])), PackedStringArray(["A year holds at most 2^53 - 1 steps"]), "a year one step longer: past it")
	var parsed: Variant = JSON.parse_string(JSON.stringify(year_of.call([safe, 1])))
	t.eq(OWCalendar.validate_config(parsed), PackedStringArray(["A year holds at most 2^53 - 1 steps"]), "the same, read from JSON")
	t.done()
