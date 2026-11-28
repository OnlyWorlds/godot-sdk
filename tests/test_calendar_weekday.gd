extends RefCounted
## A weekday in a written date: OWCalendar.parse_date reads a weekday name after every other name and refuses one that
## is not the date's own. The TypeScript SDK's four tests (test/calendar-kernel.test.mjs, 4.220.1, after "down-era
## years parse back") on its own fixtures, Kirrowmoss and Harptos, copied here; then its answers over 400 random
## calendars with a week (tests/data/weekday-parse.json, made from a seeded generator and npm 4.220.1's own formatStep
## and parseDate).

const KIRROWMOSS := {"version":1,"grain":"day","eras":[{"name":"Kingsreckoning","abbrev":"KR","start":-131400,"end":-3600,"restart":true,"closed":true},{"name":"Occupation Count","abbrev":"OC","start":-3600,"restart":true,"closed":true},{"name":"Freehold Tally","abbrev":"FT","start":0,"restart":true}],"bundles":{"months":{"names":["Sowmarch","Thistlewane","Greening","Suncrest","Longhay","Ashfall","Rootdeep","Frostwake","Bellmoot","Hearthtide","Graytide","Coldmark"],"lengths":[30,28,32,30,31,29,30,28,32,30,29,31]},"week":{"length":6,"names":["Ondel","Tresk","Mireth","Aldun","Volk","Hearth"],"mode":"free"}},"format":"{day} {month}, Year {year} {era}"}
const HARPTOS := {"version":1,"grain":"day","eras":[{"name":"Dalereckoning","abbrev":"DR","start":0,"restart":true,"year_base":0}],"bundles":{"months":{"names":["Hammer","Alturiak","Ches","Tarsakh","Mirtul","Kythorn","Flamerule","Eleasis","Eleint","Marpenoth","Uktar","Nightal"],"lengths":[30,30,30,30,30,30,30,30,30,30,30,30]},"week":{"length":10,"names":["1st","2nd","3rd","4th","5th","6th","7th","8th","9th","10th"],"mode":"nested"}},"intercalary":[{"name":"Midwinter","after_month":1},{"name":"Greengrass","after_month":3},{"name":"Midsummer","after_month":7},{"name":"Shieldmeet","after_month":7,"every_years":4},{"name":"Highharvestide","after_month":9},{"name":"Feast of the Moon","after_month":11}],"format":"{day} {month}, {year} {era}","format_intercalary":"{intercalary}, {year} {era}"}
const WEEKDAY_PARSE := "res://tests/data/weekday-parse.json"

static func _cal(value: Dictionary) -> OWCalendar.Calendar:
	return OWCalendar.read_config(value)

static func _with_format(value: Dictionary, format: String) -> Dictionary:
	var v := value.duplicate(true)
	v["format"] = format
	return v

## A parse result as compared: the step as an int (JSON reads every number as a float), or the error.
static func _answer(r: Dictionary) -> Dictionary:
	return {"step": int(r["step"])} if r.has("step") else r

func test_a_weekday_beside_a_whole_date_is_read_and_one_not_the_dates_own_is_refused_naming_both(t) -> void:
	var k := _cal(KIRROWMOSS)
	var own: Variant = OWCalendar.weekday_for_step(k, 7603)
	t.eq(own, "Tresk", "the date's own weekday")
	for s in ["%s, 14 Thistlewane, Year 22 FT" % own, "%s 14 Thistlewane Year 22 FT" % own,
			"14 Thistlewane, %s. Year 22 FT" % String(own).to_upper()]:
		t.eq(OWCalendar.parse_date(k, s), {"step": 7603}, s)
	t.eq(OWCalendar.parse_date(k, "Ondel, 14 Thistlewane, Year 22 FT"), {"error": "that date falls on Tresk, not Ondel"},
		"another weekday, refused naming both")
	# With no year the date reads in the now's year, and is checked there.
	t.eq(OWCalendar.parse_date(k, "%s, Thistlewane 14" % own, {"now": 7900}), {"step": 7603}, "in the now's year")
	t.eq(OWCalendar.parse_date(k, "Volk, Thistlewane 14", {"now": 7900}), {"error": "that date falls on Tresk, not Volk"},
		"in the now's year, refused")
	# A refusal the date already had comes first.
	t.eq(OWCalendar.parse_date(k, "%s, Thistlewane 14" % own), {"error": "add a year (the world clock has no now set)"},
		"the date's own refusal first")
	t.done()

func test_a_weekday_names_no_date_alone_and_a_day_outside_the_week_has_none_to_match(t) -> void:
	var k := _cal(KIRROWMOSS)
	t.ok(OWCalendar.is_parse_error(OWCalendar.parse_date(k, "Tresk")), "a weekday alone")
	t.ok(OWCalendar.is_parse_error(OWCalendar.parse_date(k, "Tresk FT")), "a weekday and an era")
	# Harptos' week is nested in the months: Shieldmeet, between them, has no weekday.
	var h := _cal(HARPTOS)
	t.ok(not OWCalendar.is_parse_error(OWCalendar.parse_date(h, "Shieldmeet 1372")), "Shieldmeet reads")
	t.eq(OWCalendar.parse_date(h, "1st, Shieldmeet 1372"), {"error": "that date has no weekday, not 1st"}, "no weekday")
	t.eq(OWCalendar.parse_date(h, "3rd, 3 Hammer 1372"), OWCalendar.parse_date(h, "3 Hammer 1372"), "its own weekday")
	t.eq(OWCalendar.parse_date(h, "3rd Hammer 1372"), {"error": "that date falls on 1st, not 3rd"}, "the 1st, not the 3rd")
	t.done()

func test_weekday_names_are_tried_last_never_as_numbers_and_only_from_a_calendar_that_prints_one(t) -> void:
	var months := {"names": ["Frost", "Thaw"], "lengths": [10, 10]}
	# A word that is a month's and a weekday's reads as the month.
	var shared := _cal({"version": 1, "grain": "day", "bundles": {"months": months, "week": {"length": 2, "names": ["Frost", "Sunday"]}}})
	t.eq(OWCalendar.parse_date(shared, "3 Frost 4"), {"step": 4 * 20 + 2}, "the month")
	# A name that reads as a number is never tried: "1 Frost 4" stays day 1.
	var numeric := _cal({"version": 1, "grain": "day", "bundles": {"months": months, "week": {"length": 2, "names": ["1", "2"]}}})
	t.eq(OWCalendar.parse_date(numeric, "1 Frost 4"), {"step": 4 * 20}, "day 1")
	# Fewer or more names than the week's length print no weekday, and read none.
	for names in [["Moonday"], ["Moonday", "Sunday", "Starday"]]:
		var ragged := _cal({"version": 1, "grain": "day", "bundles": {"months": months, "week": {"length": 2, "names": names}}})
		t.eq(OWCalendar.parse_date(ragged, "Moonday, 1 Frost 4"), {"error": "unrecognized: \"moonday\""}, str(names))
	t.done()

func test_a_template_with_the_weekday_parses_back_every_step_of_three_years(t) -> void:
	var bad := 0
	for format in ["{weekday}, {day} {month}, Year {year} {era}", "{weekday} {day} {month} {year} {era}", "{day} {month} {year} {era}, {weekday}"]:
		var cal := _cal(_with_format(KIRROWMOSS, format))
		for n in range(7200, 7200 + 3 * 360):
			var p := OWCalendar.parse_date(cal, OWCalendar.format_step(cal, n))
			if OWCalendar.is_parse_error(p) or p["step"] != n:
				bad += 1
				if bad <= 3:
					t.ok(false, "%s at %d: %s" % [format, n, p])
	t.eq(bad, 0, "every step parses back")
	t.done()

func test_random_calendars_with_a_week_answer_as_the_typescript_sdk(t) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WEEKDAY_PARSE))
	t.eq(doc["npm"]["commit"], "7e754d6", "npm's commit")
	var slots := 0
	var refusals := 0
	var differences := 0
	for c in doc["cases"]:
		var cal := _cal(c["cfg"])
		t.ok(cal != null, "the calendar reads: %s" % JSON.stringify(c["cfg"]))
		if cal == null:
			continue
		var got := []
		for s in c["steps"]:
			var text := OWCalendar.format_step(cal, int(s))
			got.append(text)
			got.append(_answer(OWCalendar.parse_date(cal, text)))
		for input in c["inputs"]:
			got.append(_answer(OWCalendar.parse_date(cal, input)))
		var want: Array = c["npm"]
		t.eq(got.size(), want.size(), "as many answers")
		for i in mini(got.size(), want.size()):
			slots += 1
			var w: Variant = want[i]
			if w is Dictionary:
				w = _answer(w)
				if String(w.get("error", "")).begins_with("that date "):
					refusals += 1
			if not (w == got[i]):
				differences += 1
				if differences <= 3:
					t.ok(false, "%s [%d]: npm %s, here %s" % [JSON.stringify(c["cfg"]), i, w, got[i]])
	t.eq(slots, 4000, "every answer compared")
	t.ok(refusals > 0, "the sample holds weekday refusals (%d)" % refusals)
	t.eq(differences, 0, "no answer differs")
	t.done()
