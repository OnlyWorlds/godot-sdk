extends RefCounted
## OWCalendar on the calendar profile's conformance fixture (schema-dist profiles/calendar.fixture.json, the pinned copy
## at dist.107, its sha256 checked against the manifest): every case replayed by name, a refused value refused and a
## calendar's every step read to the fixture's words and breakdown; then what the fixture leaves open, as the profile's
## text and the npm and Python packages answer it, and where Godot's one number type could change an answer.

const CALENDAR := "res://codegen/schema-dist/profiles/calendar.fixture.json"

## The fixture's breakdown keys (npm's StepBreakdown, its era the era's name) and the reader's.
const KEYS := {"absYear": "abs_year", "year": "year", "era": "era", "month": "month", "monthName": "month_name",
	"day": "day", "intercalary": "intercalary", "weekday": "weekday"}

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CALENDAR))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["calendar:" + c["name"], _case.bind(c)])
	return out

## A JSON number as the reader answers it: the fixture's numbers are whole, and Godot reads them as floats.
func _int(v: Variant) -> Variant:
	return int(v) if v is float else v

## The breakdown as the fixture writes it: its keys, its era the era's name.
func _seen(b: OWCalendar.Breakdown) -> Dictionary:
	var d := b.to_dict()
	var out := {}
	for k in KEYS:
		out[k] = d[KEYS[k]]
	out["era"] = b.era.name if b.era != null else null
	return out

func _want(breakdown: Dictionary) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = _int(breakdown[k])
	return out

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var cal := OWCalendar.read_value(c["value"])
	t.eq(cal != null, c["valid"], "read_value: a calendar")
	if cal != null and c["valid"]:
		for s in c["steps"]:
			var step: int = int(s["step"])
			t.eq(OWCalendar.format_step(cal, step), s["words"], "format_step(%d)" % step)
			t.eq(_seen(OWCalendar.breakdown_step(cal, step)), _want(s["breakdown"]), "breakdown_step(%d)" % step)
	if c.has("elements"):
		t.eq(OWCalendar.world_calendars(c["elements"]).map(func(f): return f["id"]), c["found"], "world_calendars: by the field")
	t.done()

func test_the_fixture_is_the_pinned_one(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(CALENDAR), manifest["profiles/calendar.fixture.json"], "the fixture's bytes are the dist's")
	var doc := _fixture()
	t.eq(doc["profile"], OWCalendar.FIELD, "the profile is the field")
	var valid := 0
	var steps := 0
	var names := {}
	for c in doc["cases"]:
		names[c["name"]] = true
		if c["valid"]:
			valid += 1
			steps += c["steps"].size()
			for s in c["steps"]:
				t.eq(s.keys(), ["step", "words", "breakdown"], "%s: a step's keys" % c["name"])
				t.eq(s["breakdown"].keys(), KEYS.keys(), "%s: the breakdown's keys, every one compared" % c["name"])
		else:
			t.ok(not c.has("steps"), "%s: a refused value reads no step" % c["name"])
	t.eq(doc["cases"].size(), 76, "76 cases")
	t.eq(valid, 34, "34 calendars")
	t.eq(doc["cases"].size() - valid, 42, "42 refusals")
	t.eq(steps, 209, "209 steps")
	t.eq(names.size(), 76, "every case's name is its own")
	t.done()

# -- what the fixture leaves open -------------------------------------------------------------------------------------

const FROST := {"version": 1, "grain": "day", "bundles": {"months": {"names": ["Frost", "Thaw"], "lengths": [10, 10]},
	"week": {"length": 3, "names": ["A", "B", "C"]}}, "eras": [{"name": "Age", "abbrev": "AG", "start": 0}]}

func _with(base: Dictionary, path: Array, v: Variant) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var at: Variant = out
	for i in path.size() - 1:
		at = at[path[i]]
	at[path[-1]] = v
	return out

## Godot's JSON reads every number as a float: a value built by hand with ints reads as the same value parsed.
func test_ints_and_floats_read_alike(t) -> void:
	var by_hand := OWCalendar.read_value(FROST)
	var parsed := OWCalendar.read_value(JSON.parse_string(JSON.stringify(FROST)))
	t.ok(by_hand != null and parsed != null, "both read")
	for step in [-21, -1, 0, 9, 10, 19, 20, 205]:
		t.eq(OWCalendar.format_step(by_hand, step), OWCalendar.format_step(parsed, step), "format_step(%d)" % step)
		t.eq(_seen(OWCalendar.breakdown_step(by_hand, step)), _seen(OWCalendar.breakdown_step(parsed, step)), "breakdown_step(%d)" % step)
	t.eq(OWCalendar.format_step(parsed, -1), "10 Thaw, -1", "a step before every era prints no era")
	t.done()

## JSON cannot tell 1 from 1.0, nor can JavaScript's JSON.parse: an integral float is whole wherever a whole number is
## asked for, the version included.
func test_an_integral_float_is_whole(t) -> void:
	var text := '{"version":1.0,"grain":"day","bundles":{"months":{"names":["Frost","Thaw"],"lengths":[10.0,1e1]}},"eras":[{"name":"Age","start":0.0,"year_base":1.0}]}'
	var cal := OWCalendar.read_value(text)
	t.ok(cal != null, "1.0 and 1e1 are whole")
	if cal != null:
		t.eq(OWCalendar.format_step(cal, 25), "6 Frost, 2 Age", "and read as 1 and 10")
	t.done()

## A whole number in the profile is JavaScript's Number.isSafeInteger: at most 2^53 - 1 in size. 2^53 is a double
## Godot and JavaScript both hold exactly, and refuse alike; 2^53 + 1 parses to 2^53 in both.
func test_a_whole_number_is_a_safe_one(t) -> void:
	var at := '{"version":1,"grain":"year","eras":[{"name":"Age","start":%s}]}'
	t.ok(OWCalendar.read_value(at % "9007199254740991") != null, "2^53 - 1 is whole")
	t.ok(OWCalendar.read_value(at % "-9007199254740991") != null, "-(2^53 - 1) is whole")
	t.eq(OWCalendar.read_value(at % "9007199254740992"), null, "2^53 is not safe")
	t.eq(OWCalendar.read_value(at % "9007199254740993"), null, "2^53 + 1 reads as 2^53")
	t.eq(OWCalendar.read_value(at % "1e400"), null, "infinity is not whole")
	t.eq(OWCalendar.read_value(_with(FROST, ["eras", 0, "start"], 9007199254740992)), null, "an int past 2^53 - 1 is not safe either")
	t.ok(OWCalendar.read_value(_with(FROST, ["eras", 0, "start"], 9007199254740991)) != null, "an int at 2^53 - 1 is")
	t.done()

## after_month names a month the year has, or 0 (before the first): past the last, below the first, or above 0 with no
## months, the day has no position and the value is no calendar. Any size refuses, not only a safe integer's.
func test_after_month_names_a_month_the_year_has(t) -> void:
	var gap := func(base: Dictionary, v: Variant) -> Variant:
		return OWCalendar.read_value(_with(base, ["intercalary"], [{"name": "Gap", "after_month": v}]))
	for v in [1e300, 3.0, 3, -1.0, -1, -1e300]:
		t.eq(gap.call(FROST, v), null, "two months, after_month %s" % var_to_str(v))
	for v in [0, 0.0, 1, 2, 2.0]:
		t.ok(gap.call(FROST, v) != null, "two months, after_month %s" % var_to_str(v))
	var both := _with(FROST, ["bundles", "year"], {"steps": 50})
	t.eq(gap.call(both, 3), null, "months and a year length: the months count")
	t.ok(gap.call(both, 2) != null, "and their last month reads")
	var no_months := _with(FROST, ["bundles"], {"year": {"steps": 10}})
	t.eq(gap.call(no_months, 1), null, "no months: after_month 1")
	# No months: an intercalary day has no place between months, so even after_month 0 refuses (ruled ahead of its case).
	t.eq(gap.call(no_months, 0), null, "no months: after_month 0")
	t.eq(gap.call(_with(FROST, ["bundles", "months"], false), 1), null, "months false is no months")
	t.eq(gap.call(_with(FROST, ["bundles", "months"], false), 0), null, "months false: after_month 0")
	t.done()

## The profile's grain is a string, and an empty string is no grain (ruled ahead of the fixture's own case).
func test_an_empty_grain_is_no_grain(t) -> void:
	t.eq(OWCalendar.read_value(_with(FROST, ["grain"], "")), null, "grain ''")
	t.ok(OWCalendar.read_value(_with(FROST, ["grain"], "day")) != null, "grain 'day'")
	t.done()

## Something must be left after trimming the room profile's White_Space set, as for the marks.
func test_a_grain_of_white_space_is_no_grain(t) -> void:
	t.eq(OWCalendar.read_value(_with(FROST, ["grain"], " \t\n")), null, "ASCII white space")
	t.eq(OWCalendar.read_value(_with(FROST, ["grain"], " 　 ")), null, "Unicode White_Space")
	t.ok(OWCalendar.read_value(_with(FROST, ["grain"], " day ")) != null, "a padded grain")
	t.ok(OWCalendar.read_value(_with(FROST, ["grain"], "​")) != null, "U+200B is not White_Space")
	t.done()

## A boolean is not a number, and only false is false: Godot compares across the two, so the reader checks the type.
func test_a_boolean_is_not_a_number(t) -> void:
	t.eq(OWCalendar.read_value(_with(FROST, ["version"], true)), null, "version true")
	t.eq(OWCalendar.read_value(_with(FROST, ["bundles", "months", "lengths"], [10, true])), null, "a month length true")
	t.eq(OWCalendar.read_value(_with(FROST, ["eras", 0, "year_base"], false)), null, "year_base false is not 0")
	t.eq(OWCalendar.read_value(_with(FROST, ["eras", 0, "start"], false)), null, "start false is not 0")
	t.eq(OWCalendar.read_value(_with(FROST, ["intercalary"], [{"name": "Gap", "after_month": true}])), null, "after_month true")
	# restart 0 and in_week 0 are not false: the era restarts, the day counts in the week.
	var cal := OWCalendar.read_value(_with(FROST, ["eras", 0, "restart"], 0))
	t.eq(OWCalendar.format_step(cal, 25), "6 Frost, 2 AG", "restart 0 restarts")
	cal = OWCalendar.read_value(_with(FROST, ["eras", 0, "restart"], false))
	t.eq(OWCalendar.format_step(cal, 25), "6 Frost, 1 AG", "restart false shows the year index")
	var gap := _with(FROST, ["intercalary"], [{"name": "Gap", "after_month": 0, "in_week": 0}])
	t.eq(OWCalendar.breakdown_step(OWCalendar.read_value(gap), 1).weekday, "B", "in_week 0 counts in the week")
	gap = _with(FROST, ["intercalary"], [{"name": "Gap", "after_month": 0, "in_week": false}])
	t.eq(OWCalendar.breakdown_step(OWCalendar.read_value(gap), 1).weekday, "A", "in_week false does not")
	t.done()

## The JSON-string form is strict JSON, as JSON.parse reads it. Godot's own parser takes more (each measured): a
## trailing comma, a leading zero, a number ending in a point, a raw control character inside a string.
func test_a_json_string_is_strict_json(t) -> void:
	var good := '{"version":1,"grain":"day"}'
	t.ok(OWCalendar.read_value(good) != null, "strict JSON reads")
	t.ok(OWCalendar.read_value(" \t\r\n" + good + "\n ") != null, "JSON's own white space around it")
	t.ok(OWCalendar.read_value('{"version":1,"grain":"d\\u00e1y","x":[1,-2.5e+3,true,null,{}],"y":"\\"\\\\\\/\\b\\f\\n\\r\\t"}') != null, "every escape and literal")
	for bad in ['{"version":1,"grain":"day",}', '{"version":1,"grain":"day","x":[1,]}', '{"version":01,"grain":"day"}',
			'{"version":1,"grain":"day","x":5.}', '{"version":1,"grain":"d\tay"}', "\ufeff" + good, "\u00a0" + good,
			'{"version":1,"grain":"day"} x', '{"version":1,"grain":"day","x":.5}', '{"version":1,"grain":"day","x":-}',
			'{"version":1,"grain":"day","x":1e}', '{"version":1,"grain":"\\x"}', '{"version":1,"grain":"\\u00e"}', ""]:
		t.eq(OWCalendar.read_value(bad), null, "refused: %s" % bad.c_escape())
	t.eq(OWCalendar.read_value(JSON.stringify(good)), null, "a JSON string holding a JSON string is a string, not a calendar")
	t.eq(OWCalendar.read_value('[{"version":1,"grain":"day"}]'), null, "a list is not a calendar")
	t.eq(OWCalendar.read_value(null), null, "null")
	t.done()

## A format that is not a string is ignored and the default template prints (the profile's "What a reader may ignore",
## ruled at serial 89, where the fixture holds a number and an object); null is absent, and an empty string is a string.
func test_a_format_that_is_not_text_reads_as_the_default(t) -> void:
	var cal := OWCalendar.read_value(_with(FROST, ["format"], 5))
	t.eq(OWCalendar.format_step(cal, 25), "6 Frost, 2 AG", "format 5")
	cal = OWCalendar.read_value(_with(FROST, ["format"], null))
	t.eq(OWCalendar.format_step(cal, 25), "6 Frost, 2 AG", "format null is absent")
	cal = OWCalendar.read_value(_with(FROST, ["format"], ""))
	t.eq(OWCalendar.format_step(cal, 25), "", "an empty format prints nothing")
	t.done()

## The era token prints the abbrev as JavaScript's String() prints it; an empty abbrev closes up, null is absent.
func test_the_era_token(t) -> void:
	var cases := [["", "6 Frost, 2"], [null, "6 Frost, 2 Age"], [7.0, "6 Frost, 2 7"], [2.5, "6 Frost, 2 2.5"],
		[true, "6 Frost, 2 true"], [["a", 1.0], "6 Frost, 2 a,1"]]
	for c in cases:
		var v := _with(FROST, ["eras", 0], {"name": "Age", "start": 0, "abbrev": c[0]})
		t.eq(OWCalendar.format_step(OWCalendar.read_value(v), 25), c[1], "abbrev %s" % var_to_str(c[0]))
	t.done()

## The template's white space is JavaScript's \s: a no-break space closes up around an empty token like a space.
func test_the_template_closes_up_on_javascript_white_space(t) -> void:
	var v := _with(FROST, ["format"], "{day}\u00a0{month},\u00a0{weekday}\u3000·\u00a0{year}")
	v.erase("eras")
	v["bundles"].erase("week")
	t.eq(OWCalendar.format_step(OWCalendar.read_value(v), 25), "6\u00a0Frost 1", "no-break and ideographic spaces")
	t.eq(OWCalendar.format_step(OWCalendar.read_value(_with(FROST, ["format"], "{day} $1 {month} \\1")), 25), "6 $1 Frost \\1",
		"a template with $ and \\ prints as written")
	t.eq(OWCalendar.format_step(OWCalendar.read_value(_with(FROST, ["bundles", "months", "names"], ["$0 \\1", "Thaw"])), 25),
		"6 $0 \\1, 2 AG", "a value with $ and \\ too")
	t.eq(OWCalendar.format_step(OWCalendar.read_value(_with(FROST, ["format"], ", ;{day} {month}· ")), 25), "6 Frost",
		"separators and white space at either edge are trimmed, a filled template's too")
	var no_week := _with(FROST, ["bundles", "week"], null)
	t.eq(OWCalendar.format_step(OWCalendar.read_value(_with(no_week, ["format"], "{year} · {weekday} · {day}")), 25),
		"2 6", "a middle dot closes up around an empty token (one on each side)")
	t.done()

## A month of 10^12 steps reads by arithmetic, not by listing its days.
func test_a_long_month_reads_without_listing_its_days(t) -> void:
	var cal := OWCalendar.read_value(_with(FROST, ["bundles", "months", "lengths"], [1000000000000, 10]))
	var t0 := Time.get_ticks_msec()
	t.eq(OWCalendar.format_step(cal, 1000000000005), "6 Thaw, 1 AG", "a step in the second month")
	t.eq(OWCalendar.breakdown_step(cal, 999999999999).day, 1000000000000, "the long month's last day")
	t.ok(Time.get_ticks_msec() - t0 < 1000, "in under a second")
	t.done()

## The profile: a reader finds calendars by the field being present, never by type or supertype; one that is not a
## calendar is skipped, never an error. npm worldCalendars.
func test_world_calendars_by_the_field(t) -> void:
	var els := [
		{"id": "a", "type": "construct", "supertype": "calendar", "name": "Reckoning", "atlas_calendar": FROST},
		{"id": "b", "type": "location", "name": "", "atlas_calendar": JSON.stringify(FROST)},
		{"id": "c", "type": "construct", "supertype": "calendar", "name": "No field"},
		{"id": "d", "type": "construct", "name": "Broken", "atlas_calendar": {"version": 3, "grain": "day"}},
		"not an element",
	]
	var found := OWCalendar.world_calendars(els)
	t.eq(found.map(func(c): return [c["id"], c["name"]]), [["a", "Reckoning"], ["b", "(unnamed calendar)"]], "by the field")
	if not found.is_empty():
		t.ok(found[0]["calendar"] is OWCalendar.Calendar, "each with its calendar")
		t.eq(found[0]["calendar"].raw, FROST, "the value as read, for a writer to keep")
	t.done()
