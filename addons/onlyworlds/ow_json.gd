class_name OWJson
extends RefCounted
## JSON in the folder format's own form (folder spec section 5), the bytes JavaScript's
## [code]JSON.stringify(value, null, 2)[/code] gives, plus one trailing newline.
##
## Godot's [method JSON.stringify] differs from that form in three ways, each measured: it sorts keys unless told
## not to, it writes an integer read back from JSON as [code]1.0[/code], and it writes a control character raw (an
## invalid JSON string). This writer keeps key order, writes an integral float as an integer and any other number in
## JavaScript's shortest form, and escapes as JavaScript does: [code]\"[/code], [code]\\[/code], [code]\b \f \n \r \t[/code],
## and [code]\u00XX[/code] for the other characters below U+0020. Everything else is written as itself, in UTF-8.

const _MAX_SAFE := 9007199254740992.0   # 2^53: past it a float no longer holds every integer

static var _needs_escape: RegEx

## [param value] in the spec's form: 2-space indent, key order kept, a trailing newline.
static func stringify(value: Variant) -> String:
	var parts := PackedStringArray()
	_write(value, "", parts)
	parts.append("\n")
	return "".join(parts)

## [method stringify] as UTF-8 bytes (no byte order mark).
static func to_bytes(value: Variant) -> PackedByteArray:
	return stringify(value).to_utf8_buffer()

## Parse UTF-8 JSON bytes; a byte order mark at the start is read past. [code]null[/code] when they do not parse.
static func parse_bytes(bytes: PackedByteArray) -> Variant:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return null
	return json.data

static func _write(v: Variant, indent: String, parts: PackedStringArray) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.is_empty():
				parts.append("{}")
				return
			var inner := indent + "  "
			parts.append("{\n")
			var first := true
			for k in v:
				if not first:
					parts.append(",\n")
				first = false
				parts.append(inner)
				parts.append(quote(str(k)))
				parts.append(": ")
				_write(v[k], inner, parts)
			parts.append("\n")
			parts.append(indent)
			parts.append("}")
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if v.is_empty():
				parts.append("[]")
				return
			var inner := indent + "  "
			parts.append("[\n")
			var first := true
			for x in v:
				if not first:
					parts.append(",\n")
				first = false
				parts.append(inner)
				_write(x, inner, parts)
			parts.append("\n")
			parts.append(indent)
			parts.append("]")
		TYPE_STRING, TYPE_STRING_NAME:
			parts.append(quote(str(v)))
		TYPE_INT:
			parts.append(str(v))
		TYPE_FLOAT:
			parts.append(number(v))
		TYPE_BOOL:
			parts.append("true" if v else "false")
		TYPE_NIL:
			parts.append("null")
		_:
			parts.append(quote(str(v)))   # not a JSON value; written as its text rather than dropped

## A float as JavaScript writes a number: an integer when integral (and within 2^53), otherwise the shortest digits
## that read back to the same double, in ECMAScript's Number::toString layout. NaN and the infinities are null.
static func number(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "null"
	if v == 0.0:
		return "0"                     # -0 too, as JavaScript writes it
	if v == floorf(v) and absf(v) < _MAX_SAFE:
		return str(int(v))
	var s := String.num_scientific(v)  # shortest round-trip digits, measured: 0.30000000000000004, 2.5e-05, 1e+21
	var sign := ""
	if s.begins_with("-"):
		sign = "-"
		s = s.substr(1)
	var exp := 0
	var e := s.find("e")
	if e >= 0:
		exp = int(s.substr(e + 1))
		s = s.substr(0, e)
	var dot := s.find(".")
	var digits := s.replace(".", "")
	var point := (dot if dot >= 0 else s.length()) + exp   # value = 0.digits * 10^point
	var lead := 0
	while lead < digits.length() - 1 and digits[lead] == "0":
		lead += 1
	digits = digits.substr(lead)
	point -= lead
	digits = digits.rstrip("0")
	if digits == "":
		return "0"
	# num_scientific is not always the shortest (measured: 11 of 20,000 six-decimal numbers come out with 17 digits,
	# 2966.215418 as 2966.2154180000002). Try each shorter rounding of its digits and keep the first that reads back
	# as the same double; Godot's parser was exact on every candidate of 15 digits or fewer measured.
	for k in range(1, mini(digits.length(), 16)):   # 15 digits or fewer: one double each, read exactly
		var cand := _round_digits(digits, k)
		var c_digits: String = cand[0]
		var c_point: int = point + cand[1]
		var probe := "0." + c_digits + "e" + str(c_point)
		if probe.to_float() == absf(v):
			digits = c_digits.rstrip("0")
			point = c_point
			break
	var k := digits.length()
	var n := point
	if k <= n and n <= 21:
		return sign + digits + "0".repeat(n - k)
	if 0 < n and n <= 21:
		return sign + digits.substr(0, n) + "." + digits.substr(n)
	if -6 < n and n <= 0:
		return sign + "0." + "0".repeat(-n) + digits
	var e_part := "e" + ("+" if n - 1 >= 0 else "-") + str(absi(n - 1))
	if k == 1:
		return sign + digits + e_part
	return sign + digits[0] + "." + digits.substr(1) + e_part

## [param digits] rounded half-up to [param k] significant digits: [rounded digits, how far the point moved (a carry
## out of the first digit moves it by one)].
static func _round_digits(digits: String, k: int) -> Array:
	var head := digits.substr(0, k)
	if digits.unicode_at(k) < 0x35:      # the next digit is below 5
		return [head, 0]
	var chars := head.to_utf8_buffer()
	var i := chars.size() - 1
	while i >= 0:
		if chars[i] == 0x39:
			chars[i] = 0x30
			i -= 1
		else:
			chars[i] += 1
			return [chars.get_string_from_ascii(), 0]
	return ["1" + chars.get_string_from_ascii(), 1]

## A string as a JSON string literal, escaped as JavaScript escapes it.
static func quote(s: String) -> String:
	if _needs_escape == null:
		_needs_escape = RegEx.create_from_string("[\\x00-\\x1f\"\\\\]")
	if _needs_escape.search(s) == null:
		return "\"" + s + "\""
	var out := PackedStringArray(["\""])
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22: out.append("\\\"")
			0x5C: out.append("\\\\")
			0x08: out.append("\\b")
			0x0C: out.append("\\f")
			0x0A: out.append("\\n")
			0x0D: out.append("\\r")
			0x09: out.append("\\t")
			_:
				if c < 0x20:
					out.append("\\u%04x" % c)
				else:
					out.append(String.chr(c))
	out.append("\"")
	return "".join(out)
