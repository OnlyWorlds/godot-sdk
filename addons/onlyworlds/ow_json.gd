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

## The word for a file or an answer that holds a number no double can hold (the TypeScript and Python packages' word).
const NUMBER_OUT_OF_RANGE := "number_out_of_range"
## What a refusal says after the file's name: [constant NUMBER_OUT_OF_RANGE] and why.
const OUT_OF_RANGE_WHY := NUMBER_OUT_OF_RANGE + ": holds a number too large for a double"

## The deepest an object or array may sit in a JSON text a reader reads, the text's top value at 1, objects and arrays
## both counted (the folder format's OW-25; the TypeScript package's OUTSIDE_JSON_MAX_DEPTH).
const MAX_DEPTH := 200
## The word for a file nested past [constant MAX_DEPTH] (the TypeScript and Python packages' word).
const TOO_DEEP := "too_deep"
## What a refusal says after the file's name: [constant TOO_DEEP] and why.
const TOO_DEEP_WHY := TOO_DEEP + ": nested more than 200 deep"

static var _needs_escape: RegEx

## True when a parsed value holds a number Godot's parser read as an infinity: one past the largest double, by its
## digits (4,301 nines) or its exponent ([code]1e400[/code]). JSON has no infinity, so the value read is not the number
## written, and the section 5 form has nothing to write it as. Godot's parser never shows a number's text, so this is
## the one line it can draw: any number a double cannot hold, as the TypeScript package draws it.
static func holds_out_of_range(value: Variant) -> bool:
	var stack: Array = [value]
	while not stack.is_empty():
		var v = stack.pop_back()
		match typeof(v):
			TYPE_FLOAT:
				if is_inf(v):
					return true
			TYPE_DICTIONARY:
				stack.append_array(v.values())
			TYPE_ARRAY:
				stack.append_array(v)
	return false

## True when a parsed value holds an object or array deeper than [constant MAX_DEPTH], the value itself at 1 when it
## is one. Godot's parser reads deeper than that (to its own recursion line), so the standard's line is drawn here, by a
## walk with its own stack, never recursion.
static func nested_past(value: Variant, limit: int = MAX_DEPTH) -> bool:
	var stack: Array = [[value, 1]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var v = pair[0]
		var d: int = pair[1]
		match typeof(v):
			TYPE_DICTIONARY:
				if d > limit:
					return true
				for x in v.values():
					stack.append([x, d + 1])
			TYPE_ARRAY:
				if d > limit:
					return true
				for x in v:
					stack.append([x, d + 1])
	return false

## Whether a failed parse failed on depth, past Godot's own recursion line: by the parser's own words.
static func failed_on_depth(json: JSON) -> bool:
	return json.get_error_message().to_lower().contains("too deep")

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
## that read back to the same double, in ECMAScript's Number::toString layout. NaN and the infinities are null, as
## JavaScript writes them: only a value a caller made can be one, since a file or an answer holding a number too large
## for a double is refused where it is read ([method holds_out_of_range]).
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
	# as the same double. "Reads back" is decided exactly, never by Godot's parser, which misreads about one long
	# decimal in ten and, far from 1, short ones too (9.322925914000258e-156 was taken as 9.32292591400026e-156).
	digits = digits.substr(0, 17)
	var exact := _Exact.new(absf(v), digits, point)
	var found := false
	for k in range(1, mini(digits.length(), 16)):   # 15 digits or fewer: at most one lies in the interval, the rounding
		var cand := _round_digits(digits, k)
		var c_digits: String = cand[0]
		var c_point: int = point + cand[1]
		if exact.distance(c_digits.to_int(), c_point - c_digits.length()) != null:
			digits = c_digits.rstrip("0")
			point = c_point
			found = true
			break
	# 16 and 17 digits: up to two lie in the interval, and the closest wins (ties to even), as ECMAScript and Python
	# choose; num_scientific's own 17 are not always the closest (249772149785718.88 came out ...718.87).
	var padded := digits + "0".repeat(17 - digits.length())
	for n in ([16, 17] if not found and digits.length() >= 16 else []):
		var head := padded.substr(0, n).to_int()
		var best = null
		var best_d := 0
		for d in [head - 1, head, head + 1]:
			var dist = exact.distance(d, point - n)
			if dist == null:
				continue
			var c := 0 if best == null else _big_cmp(dist, best)
			if best == null or c < 0 or (c == 0 and d % 2 == 0):
				best = dist
				best_d = d
		if best != null:
			var t := str(best_d)
			point = point - n + t.length()
			digits = t.rstrip("0")
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

## Whether a decimal D * 10^P reads back as a double, decided exactly: the double is M * 2^E, and a decimal reads
## back to it when it lies inside the double's rounding interval, its ends included when M is even (round half to
## even), the interval below a power of two half as wide. Both sides are scaled to integers and compared as big
## integers, so no float arithmetic decides; a cheap distance in num_scientific's own 17-digit units skips the
## candidates that are plainly outside first.
class _Exact:
	var m := 0
	var e := 0
	var lower_half := false
	var even := false
	var s17 := 0        # num_scientific's digits, padded to 17: the value is about s17 * 10^(point - 17)
	var point := 0
	var half_units := 0.0   # half the interval's width in those units, about

	func _init(x: float, digits: String, p: int) -> void:
		var b := PackedByteArray()
		b.resize(8)
		b.encode_double(0, x)
		var bits := b.decode_u64(0)    # x is positive: the sign bit is clear
		var ef := bits >> 52
		var frac := bits & 0xFFFFFFFFFFFFF
		m = frac if ef == 0 else frac | (1 << 52)
		e = -1074 if ef == 0 else ef - 1075
		lower_half = frac == 0 and ef > 1
		even = m % 2 == 0
		s17 = (digits + "0".repeat(17 - digits.length())).to_int()
		point = p
		half_units = pow(2.0, (e - 1) - (point - 17) * 3.321928094887362)

	## |4 * D * 10^P - 4 * x| on a common integer scale when D * 10^P reads back as x, else null.
	func distance(d: int, p: int):
		var shift := p - point + 17   # d * 10^p in s17's units is d * 10^shift; the candidates are at most 17 digits
		if shift >= 0 and str(d).length() + shift <= 18:
			var scaled := d
			for i in shift:
				scaled *= 10
			if float(absi(scaled - s17)) > 2.0 * half_units + 2.0:   # s17 is within half a unit of x
				return null
		var u := OWJson._big_pow10(OWJson._big_pow2(OWJson._big(1), maxi(e, 0)), maxi(-p, 0))
		var c4 := OWJson._big_pow2(OWJson._big_pow10(OWJson._big(d), maxi(p, 0)), maxi(-e, 0) + 2)
		var center := OWJson._big_pow2(OWJson._big_mul_int(u, m), 2)
		var hi := OWJson._big_add(center, OWJson._big_mul(u, 2))
		var lo := OWJson._big_sub(center, u if lower_half else OWJson._big_mul(u, 2))
		var c_hi := OWJson._big_cmp(c4, hi)
		var c_lo := OWJson._big_cmp(c4, lo)
		if c_hi > 0 or (c_hi == 0 and not even) or c_lo < 0 or (c_lo == 0 and not even):
			return null
		return OWJson._big_sub(c4, center) if OWJson._big_cmp(c4, center) >= 0 else OWJson._big_sub(center, c4)

# Big non-negative integers as little-endian limbs of 24 bits (an empty array is zero), only as much as _Exact needs.

static func _big(n: int) -> PackedInt64Array:
	var a := PackedInt64Array()
	while n > 0:
		a.append(n & 0xFFFFFF)
		n >>= 24
	return a

static func _big_mul(a: PackedInt64Array, k: int) -> PackedInt64Array:   # k below 2^30
	var r := PackedInt64Array()
	if k == 0:
		return r
	var carry := 0
	for x in a:
		var p := x * k + carry
		r.append(p & 0xFFFFFF)
		carry = p >> 24
	while carry > 0:
		r.append(carry & 0xFFFFFF)
		carry >>= 24
	return r

static func _big_mul_int(a: PackedInt64Array, n: int) -> PackedInt64Array:   # n below 2^54, in limbs of 24 bits
	var r := PackedInt64Array()
	var shift := 0
	while n > 0:
		r = _big_add(r, _big_pow2(_big_mul(a, n & 0xFFFFFF), shift))
		n >>= 24
		shift += 24
	return r

static func _big_pow2(a: PackedInt64Array, k: int) -> PackedInt64Array:   # a * 2^k
	if a.is_empty():
		return a
	var r := PackedInt64Array()
	r.resize(k / 24)
	r.fill(0)
	r.append_array(a)
	return _big_mul(r, 1 << (k % 24))

static func _big_pow10(a: PackedInt64Array, k: int) -> PackedInt64Array:   # a * 10^k
	while k >= 9:
		a = _big_mul(a, 1000000000)
		k -= 9
	var p := 1
	for i in k:
		p *= 10
	return _big_mul(a, p)

static func _big_add(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var r := PackedInt64Array()
	var carry := 0
	for i in maxi(a.size(), b.size()):
		var s := (a[i] if i < a.size() else 0) + (b[i] if i < b.size() else 0) + carry
		r.append(s & 0xFFFFFF)
		carry = s >> 24
	if carry > 0:
		r.append(carry)
	return r

static func _big_sub(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:   # a - b, a at least b
	var r := PackedInt64Array()
	var borrow := 0
	for i in a.size():
		var s := a[i] - (b[i] if i < b.size() else 0) - borrow
		borrow = 1 if s < 0 else 0
		r.append(s + (0x1000000 if s < 0 else 0))
	while not r.is_empty() and r[r.size() - 1] == 0:
		r.remove_at(r.size() - 1)
	return r

static func _big_cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:   # both without high zero limbs
	if a.size() != b.size():
		return 1 if a.size() > b.size() else -1
	for i in range(a.size() - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0

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
