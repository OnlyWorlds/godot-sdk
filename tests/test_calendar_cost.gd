extends RefCounted
## A stored calendar does not set what one date label costs: the TypeScript SDK's and the Python package's shared cases
## (tests/data/calendar-cost.cases.json, the same bytes, held by its sha256): a long run of white space in a template
## or a name, a long run of marks at a label's edge, and a month of millions of days, each answered with its words
## inside the cases' line.

const CASES := "res://tests/data/calendar-cost.cases.json"
const CASES_SHA256 := "1e326d378cbdc6db91deba2219ed07cf67ad72211653bd25219f963fc81ebc0f"
## The cases' underMs is the TypeScript SDK's line, held here as written.
const FACTOR := 1

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	return _doc

## A value with each {"$repeat": [[piece, times], ...]} made its pieces joined, each repeated.
static func _expand(v: Variant) -> Variant:
	if v is Array:
		return v.map(func(x): return _expand(x))
	if v is Dictionary:
		if v.has("$repeat"):
			var parts := PackedStringArray()
			for p in v["$repeat"]:
				parts.append(String(p[0]).repeat(int(p[1])))
			return "".join(parts)
		var out := {}
		for k in v:
			out[k] = _expand(v[k])
		return out
	return v

## A JSON number the reader answers as an int: the cases' numbers are whole, and Godot reads them as floats.
static func _ints(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		return v.map(func(x): return _ints(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	return v

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["calendar cost: " + c["name"], _case.bind(c)])
	return out

func test_the_cases_file_is_the_pinned_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(CASES), CASES_SHA256, "the cases' bytes are the TypeScript SDK's and the Python package's")
	t.ok(_fixture()["cases"].size() >= 8, "%d cases" % _fixture()["cases"].size())
	t.done()

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	var cal := OWCalendar.read_config(_expand(c["cfg"]))
	t.ok(cal != null, "the case is a calendar the reader accepts")
	if cal == null:
		t.done()
		return
	var step := int(c["step"])
	var t0 := Time.get_ticks_usec()
	var got: Variant
	if c["call"] == "format":
		got = OWCalendar.format_step(cal, step)
	elif c["call"] == "weekday":
		got = OWCalendar.weekday_for_step(cal, step)
	else:
		var label := OWCalendar.format_step(cal, step)
		got = [label, OWCalendar.parse_date(cal, label)]
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.eq(got, _ints(_expand(c["want"])), "its words")
	var line := float(_fixture()["underMs"]) * FACTOR
	t.ok(ms < line, "%.1f ms, the line %d ms" % [ms, line])
	print("       %.2f ms: %s" % [ms, c["name"]])
	t.done()

# -- what the cases cannot hold ---------------------------------------------------------------------------------------

## The close-up and the trims as regular expressions, the way the calendar wrote them before the one-pass rewrite, kept
## here as the oracle: the rewrite must answer every made template as they did.
var _old: Dictionary

func _old_res() -> Dictionary:
	if _old.is_empty():
		var ws := "[" + OWCalendar._JS_WS + "]"
		var mark := "[,;" + String.chr(0xB7) + "]"
		var edge := "[" + OWCalendar._JS_WS + ",;" + String.chr(0xB7) + "]"
		var z := String.chr(92) + "z"
		_old = {
			"collapse": RegEx.create_from_string(ws + "*" + mark + "?" + ws + "*" + OWCalendar._EMPTY_KNOWN + ws + "*" + mark + "?" + ws + "*"),
			"runs": RegEx.create_from_string(ws + "{2,}"),
			"edges": RegEx.create_from_string("^" + edge + "+|" + edge + "+$"),
			"trim": RegEx.create_from_string("^" + ws + "+|" + ws + "+" + z),
		}
	return _old

## render_template as it was: the tokens filled as the calendar fills them, then the three regular expressions.
func _old_render(template: String, values: Dictionary) -> String:
	OWCalendar._compile()
	var parts := PackedStringArray()
	var at := 0
	for m in OWCalendar._token_re.search_all(template):
		parts.append(template.substr(at, m.get_start() - at))
		var token := m.get_string(1)
		if not OWCalendar.KNOWN_TOKENS.has(token):
			parts.append(m.get_string())
		else:
			var v: Variant = values.get(token)
			parts.append(OWCalendar._EMPTY_KNOWN if v == null or v == "" else String(v))
		at = m.get_end()
	parts.append(template.substr(at))
	var r := _old_res()
	var out: String = r["collapse"].sub("".join(parts), " ", true)
	out = r["runs"].sub(out, " ", true)
	return r["edges"].sub(out, "", true)

## The pieces a made template is drawn from: JavaScript's white space (and U+0085, which is not), the marks, a dash,
## known tokens with and without a value, an unknown token, lone braces, letters.
func _pieces() -> Array:
	var out := []
	for c in [0x20, 0x09, 0x0A, 0x0B, 0x0D, 0xA0, 0x1680, 0x2003, 0x2028, 0x202F, 0x3000, 0xFEFF, 0x85, 0x2C, 0x3B, 0xB7, 0x2D]:
		out.append(String.chr(c))
	out.append_array([" ", "  ", ",", ", ", " ; ", "{day}", "{month}", "{era}", "{weekday}", "{year}", "{nope}", "{", "}", "a", "Yule", "x y"])
	return out

## A made template: up to 24 pieces drawn by a 31-bit LCG, seeded, so a failure reruns the same.
func _made(state: Array) -> String:
	var pieces := _pieces()
	var s := ""
	state[0] = (state[0] * 1103515245 + 12345) % 2147483648
	var count: int = state[0] % 25
	for i in count:
		state[0] = (state[0] * 1103515245 + 12345) % 2147483648
		s += pieces[(state[0] >> 8) % pieces.size()]
	return s

func test_every_made_template_formats_as_the_regular_expressions_did(t) -> void:
	var values := {"day": null, "month": "", "era": "BT", "weekday": null, "year": "12", "step": "3", "intercalary": null}
	var state := [20261124]
	var differ := 0
	for i in 4000:
		var tpl := _made(state)
		var got := OWCalendar.render_template(tpl, values)
		var want := _old_render(tpl, values)
		if got != want:
			differ += 1
			if differ <= 5:
				t.fail("template %s: %s, the regular expressions %s" % [var_to_str(tpl), var_to_str(got), var_to_str(want)])
		var trimmed := OWCalendar._js_trim(tpl)
		var old_trim: String = _old_res()["trim"].sub(tpl, "", true)
		if trimmed != old_trim:
			differ += 1
			if differ <= 5:
				t.fail("trim %s: %s, the regular expression %s" % [var_to_str(tpl), var_to_str(trimmed), var_to_str(old_trim)])
	t.eq(differ, 0, "made templates and trims that answer otherwise")
	t.done()

## Not in the cases (the TypeScript SDK trims with the runtime's own trim): the calendar's trim was a regular
## expression of its own, quadratic on a long run of white space inside the text. A step word with 20,000 spaces in it.
func test_a_step_word_with_a_long_run_of_white_space_inside_is_trimmed_inside_the_line(t) -> void:
	var word := " day" + " ".repeat(20000) + "s "
	var cal := OWCalendar.read_config({"version": 1, "grain": "day", "step_name": word})
	t.ok(cal != null, "a calendar the reader accepts")
	var t0 := Time.get_ticks_usec()
	var got := OWCalendar.format_duration(cal, 2)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	t.eq(got, "2 day" + " ".repeat(20000) + "ss", "its words")
	t.ok(ms < float(_fixture()["underMs"]) * FACTOR, "%.1f ms, the line %d ms" % [ms, int(_fixture()["underMs"]) * FACTOR])
	print("       %.2f ms: a step word with 20000 spaces inside" % ms)
	t.done()
