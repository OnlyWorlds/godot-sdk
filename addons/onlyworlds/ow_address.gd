class_name OWAddress
extends RefCounted
## The address profile (schema-dist [code]profiles/address.md[/code], serial 77): one element, or a world, named by
## one triple (the world's id, the type word, the element's id) in three spellings, with an optional moment and lens.
##
## [codeblock]
## https://www.onlyworlds.com/w/<world id>/<type>/<id>     a link for a person
## ow://<type>/<id>                                        an element of the same world, in a text field
## ow://<world id>/<type>/<id>                             an element of another world
## https://www.onlyworlds.com/w/<world id>  ow://<world id>   a world alone
## ...@<step>?lens=<id>                                    a moment and a lens, the moment first
## [/codeblock]
##
## [method parse_link] reads one string whole and refuses it with the first check that fails, in the profile's order;
## [method read_link_at] reads an address found inside other text from the index where its prefix starts, and says
## where it ends. [method element_address] writes: lowercase, the world's
## id (never its slug), the moment before the lens, nothing else. The npm and Python packages' [code]parseOwLink[/code]
## and [code]elementAddress[/code]; the fixture beside the profile is this file's test.
##
## A field that holds an address is public text: never resolve, fetch or unfurl it on a server. An address is not a
## foreign key, not an identity key and not a promise that its target exists.

const HUMAN := "human"
const TEXT := "text"
const HUMAN_PREFIX := "https://www.onlyworlds.com/w/"
const TEXT_PREFIX := "ow://"
## The one query key the profile reads.
const LENS_KEY := "lens"

## Every refusal, in the order a reader checks them; the last two are a writer's only (the fixture's own list).
const REFUSALS := ["not_an_address", "uppercase", "segments", "bad_world", "unknown_type", "bad_id", "bad_moment",
	"bad_lens", "no_world", "bad_form"]

## The keys of an address as a Dictionary: its six parts, then a reading's two flags (ignored by the writer).
const KEYS := ["form", "world", "type", "id", "lens", "moment", "world_is_slug", "canonical"]

const _I32_MIN := -2147483648
const _I32_MAX := 2147483647

## What [method parse_link] read. [member ok] true: the parts; false: [member reason], one of [constant REFUSALS].
## A part that is absent is [code]null[/code].
class Reading:
	var ok := false
	var reason := ""
	## [constant HUMAN] or [constant TEXT].
	var form := ""
	## The world's id in lowercase, or its slug as written when [member world_is_slug]; null in the in-world text form.
	var world: Variant = null
	## The human address named its world by slug: read, never canonical, never written back.
	var world_is_slug := false
	## One of the 22 type words; null for a world's own address.
	var type: Variant = null
	## The element's id in lowercase; null for a world's own address.
	var id: Variant = null
	## The lens's element id in lowercase, or null. A lens never widens what a reader may see.
	var lens: Variant = null
	## The step after [code]@[/code], in the world's [code]time_basic_unit[/code], or null. A tool that cannot show a
	## moment may ignore it: the address is the same address.
	var moment: Variant = null
	## The string as received is exactly what a writer writes for this reading.
	var canonical := false

	## A world's own address: no type and no id.
	func is_world() -> bool:
		return ok and id == null

	## The reading in the fixture's shape: every key, null for an absent part.
	func to_dict() -> Dictionary:
		return {"form": form, "world": world, "world_is_slug": world_is_slug, "type": type, "id": id,
			"lens": lens, "moment": moment, "canonical": canonical}

	## The canonical address for this reading (a reading by slug refuses as [code]bad_world[/code]).
	func to_address() -> Written:
		return OWAddress.element_address(form, world, type, id, lens, moment)

## What [method read_link_at] found: the address read, and the index just past it in the text.
class Found:
	## What [method parse_link] reads from [code]text.substr(index, end - index)[/code].
	var reading: Reading
	## The index just past the address: the text's first character that is not part of it, or its length. A Godot
	## String index, so it counts code points, as [method String.substr] and [method String.find] do.
	var end := 0
	## The index of the address's first character: the index [method read_link_at] was given, and where
	## [method find_links] found it (serial 128).
	var start := 0

## What [method element_address] wrote. [member ok] true: [member address]; false: [member reason], one of
## [constant REFUSALS], or "" for a caller's mistake that is no refusal (a key the shape does not hold), with
## [member message] saying which.
class Written:
	var ok := false
	var address := ""
	var reason := ""
	var message := ""

# -- read -------------------------------------------------------------------------------------------------------------

## Read [param text] as the profile's reader does: the checks in its order, the first that fails names the refusal.
static func parse_link(text: String) -> Reading:
	var r := Reading.new()

	# 1. Trim White_Space at both ends.
	var s := OWUnicode.trim_white_space(text)

	# 2. The prefix, as written; in another case it is uppercase.
	if s.begins_with(HUMAN_PREFIX):
		r.form = HUMAN
	elif s.begins_with(TEXT_PREFIX):
		r.form = TEXT
	else:
		return _refuse(r, "uppercase" if _begins_ascii_nocase(s, HUMAN_PREFIX) or _begins_ascii_nocase(s, TEXT_PREFIX) else "not_an_address")
	var rest := s.substr((HUMAN_PREFIX if r.form == HUMAN else TEXT_PREFIX).length())

	# 3. Drop a fragment, split off the query at the first ?, split the path on /, and the last segment at its first @
	# into the id and the moment.
	var hash := rest.find("#")
	if hash >= 0:
		rest = rest.substr(0, hash)
	var query: Variant = null
	var q := rest.find("?")
	if q >= 0:
		query = rest.substr(q + 1)
		rest = rest.substr(0, q)
	var segs := rest.split("/")
	var moment: Variant = null
	var last := segs[segs.size() - 1]
	var at := last.find("@")
	if at >= 0:
		moment = last.substr(at + 1)
		segs[segs.size() - 1] = last.substr(0, at)

	# 4. Segments: the human form one or three, a text form one to three, none empty; a lone type word is a type with
	# no id.
	var n := segs.size()
	var count_ok := (n == 1 or n == 3) if r.form == HUMAN else (n >= 1 and n <= 3)
	if not count_ok or segs.has("") or (n == 1 and _is_type_word(segs[0])):
		return _refuse(r, "segments")
	var world: Variant = null
	var type: Variant = null
	var id: Variant = null
	if n == 1:
		world = segs[0]
	elif n == 2:
		type = segs[0]
		id = segs[1]
	else:
		world = segs[0]
		type = segs[1]
		id = segs[2]

	# 5. The world: an id, or in the human form only a slug.
	if world != null:
		if is_uuid(world):
			world = world.to_lower()
		elif r.form == HUMAN and _is_slug(world):
			r.world_is_slug = true
		else:
			return _refuse(r, "bad_world")

	# 6. The type word; 7. the element id.
	if type != null:
		var why := _type_refusal(type)
		if why != "":
			return _refuse(r, why)
		if not is_uuid(id):
			return _refuse(r, "bad_id")
		id = id.to_lower()

	# 8. The moment.
	var step: Variant = null
	if moment != null:
		step = _text_step(moment)
		if step == null:
			return _refuse(r, "bad_moment")

	# 9. The lens; any other query key is ignored (and the address is not canonical).
	var lens: Variant = null
	if query != null:
		var lenses := 0
		for pair: String in query.split("&"):
			var eq := pair.find("=")
			var key := pair.substr(0, eq) if eq >= 0 else pair
			if key == LENS_KEY:
				lenses += 1
				lens = pair.substr(eq + 1) if eq >= 0 else ""
			elif _ascii_lower(key) == LENS_KEY:
				return _refuse(r, "bad_lens")
		if lenses > 1 or (lenses == 1 and not is_uuid(lens)):
			return _refuse(r, "bad_lens")
		if lens != null:
			lens = lens.to_lower()

	r.ok = true
	r.world = world
	r.type = type
	r.id = id
	r.lens = lens
	r.moment = step
	# Canonical: the string as received (untrimmed) is what a writer writes for this reading; a slug never is.
	if not r.world_is_slug:
		var w := _write(r.form, world, type, id, lens, step, "")
		r.canonical = w.ok and w.address == text
	return r

# -- an address in prose ----------------------------------------------------------------------------------------------

## The query that continues an address found in prose; no other key does.
const _LENS_QUERY := "?lens="
## An id is 36 characters: a lens found in prose ends where its id ends.
const _ID_LENGTH := 36

static var _type_word_max := 0

## The address that starts exactly at [param index] in a text, found in prose, and where it ends; null when the text
## there is not an address (the address page's "An address in prose", serial 123; the npm package's
## [code]readOwLinkAt[/code] and the Python package's [code]read_ow_link_at[/code]).
##
## Both forms, [code]ow://[/code] and [code]https://www.onlyworlds.com/w/[/code], the prefix as written (lowercase).
## In the site's form the run after [code]/w/[/code] is read whole, once: it ends at the first character outside the
## slug's alphabet (lowercase letters, digits, hyphens) or the id's (hex in either case); exactly an id's form is the
## id, any other run [method parse_link] reads as a slug is the slug, else there is no address. A run followed by a
## letter of any script, a combining mark or an underscore is cut inside a word and is no address
## ([code]/w/mopPetopia.[/code], [code]/w/hyper_ion.[/code]).
##
## After the world, or in the text form from the prefix, the path is the longest one [method parse_link] reads. After
## it the address continues only with [code]@[/code] and a moment (its whole run of an optional minus and digits, taken
## only when it reads as a step) and then [code]?lens=[/code] and a lens (an id, which ends where its 36 characters
## end). Any other query key or a fragment is not part of an address found in prose: the address ends before its
## [code]?[/code], [code]&[/code] or [code]#[/code]. What follows is prose, a full stop included. [method parse_link]
## itself still reads a string whole: [code]ow://object/<id>.[/code] handed to it is refused.
##
## An address begins at the start of the text or after a character that does not glue it to a word: after a letter of
## any script, a combining mark or an underscore the start is inside a word and this answers null
## ([code]elbow://object/<id>[/code]); a hyphen, a digit, white space or punctuation before it does not glue
## ([code]x-ow://[/code], [code]3ow://[/code], [code](ow://[/code]). The same set read from both ends (schema-dist
## serial 127).
##
## [param index] and [member Found.end] are Godot String indexes, which count code points (not UTF-16 units as in
## JavaScript), so they match [method String.find] and [method String.substr]. An index below 0 or past the end reads
## nothing.
## [codeblock]
## var line := "Built the gate: ow://object/01a1d4ef-0000-7000-8000-000000000084."
## var found := OWAddress.read_link_at(line, 16)
## # found.end == 64: line[64] is the full stop; found.reading.id == "01a1d4ef-0000-7000-8000-000000000084"
## [/codeblock]
static func read_link_at(text: String, index := 0) -> Found:
	var n := text.length()
	if index < 0 or index > n:
		return null
	# A start glued to a word is prose, the mirror of the cut after a run (schema-dist serial 127). One index back is
	# one whole code point in a Godot String, so a letter above U+FFFF glues too.
	if index > 0 and _is_in_a_word(text, index - 1):
		return null
	var human := _starts_at(text, index, HUMAN_PREFIX)
	var start: int
	if human:
		start = index + HUMAN_PREFIX.length()
	elif _starts_at(text, index, TEXT_PREFIX):
		start = index + TEXT_PREFIX.length()
	else:
		return null

	if _type_word_max == 0:
		for slug in OWTypes.slugs():
			_type_word_max = maxi(_type_word_max, slug.length())
	var end := -1
	var low := start
	var run := start
	if human:
		# The site's form: the run after /w/ is read whole, once, with no order between an id and a slug.
		var w := start
		while w < n and _is_world_run_char(text.unicode_at(w)):
			w += 1
		if _is_in_a_word(text, w):
			return null
		var world := text.substr(start, w - start)
		if not is_uuid(world) and not _is_slug(world):
			return null
		end = w
		low = w
		run = w
		var element_path_max := 1 + _type_word_max + 1 + _ID_LENGTH
		while run < n and run - w <= element_path_max and _is_path_char(text.unicode_at(run)):
			run += 1
	else:
		var path_max := _ID_LENGTH + 1 + _type_word_max + 1 + _ID_LENGTH
		while run < n and run - start <= path_max and _is_path_char(text.unicode_at(run)):
			run += 1

	# Every path the parser takes here ends in an id (a world's in the text form, an element's after a world), so an
	# end whose last 36 characters are not an id is passed over without a parse, as npm's readOwLinkAt does: a parse
	# reads a fresh substring whole, and a run of bare prefixes paid one at every length of each run.
	var p := run
	while p > low:
		var at := p - _ID_LENGTH
		if at >= start and _hyphens_at(text, at) and is_uuid(text.substr(at, _ID_LENGTH)) \
				and _worth_parsing(text, start, at) and _parses(text, index, p):
			end = p
			break
		p -= 1
	if end == -1:
		return null

	# A moment: its whole run of an optional minus and digits, taken only when it reads as a step (a step the parser
	# refuses is passed over without a parse).
	if end < n and text.unicode_at(end) == 0x40:
		var step_end := end + 1
		if step_end < n and text.unicode_at(step_end) == 0x2D:
			step_end += 1
		var digits := step_end
		while step_end < n and text.unicode_at(step_end) >= 0x30 and text.unicode_at(step_end) <= 0x39:
			step_end += 1
		if step_end > digits and _text_step(text.substr(end + 1, step_end - end - 1)) != null \
				and _parses(text, index, step_end):
			end = step_end

	# A lens: an id, which ends where its 36 characters end.
	if _starts_at(text, end, _LENS_QUERY):
		var lens_end := end + _LENS_QUERY.length() + _ID_LENGTH
		if lens_end <= n and is_uuid(text.substr(end + _LENS_QUERY.length(), _ID_LENGTH)) and _parses(text, index, lens_end):
			end = lens_end

	var found := Found.new()
	found.reading = parse_link(text.substr(index, end - index))
	found.end = end
	found.start = index
	return found

## Every address in a text, in order, each a [Found] ([member Found.start], [member Found.end],
## [member Found.reading]): what [method read_link_at] reads at each place either prefix ([code]ow://[/code],
## [code]https://www.onlyworlds.com/w/[/code]) starts, so a start glued to a word is prose and what follows an address
## is prose as [method read_link_at] says (the address page's find-all, schema-dist serial 128; npm
## [code]findOwLinks[/code], Python [code]find_ow_links[/code]). The search goes on from the end of each address found,
## so no two overlap and a prefix inside an address found is no start, and from just past a start that reads nothing.
## Linear in the text: each prefix's next place is searched once, and a start reads a bounded stretch. Indexes count
## code points, as a Godot String does (npm counts UTF-16 units, Python code points).
## [codeblock]
## var found := OWAddress.find_links("See ow://object/01a1d4ef-0000-7000-8000-000000000084, not elbow://object/01a1d4ef-0000-7000-8000-000000000084.")
## # one address: found[0].start == 4, found[0].end == 52, found[0].reading.type == "object"
## [/codeblock]
static func find_links(text: String) -> Array[Found]:
	var found: Array[Found] = []
	var next_text := text.find(TEXT_PREFIX)
	var next_human := text.find(HUMAN_PREFIX)
	var at := 0
	while true:
		if next_text != -1 and next_text < at:
			next_text = text.find(TEXT_PREFIX, at)
		if next_human != -1 and next_human < at:
			next_human = text.find(HUMAN_PREFIX, at)
		var start: int = next_human if next_text == -1 else (next_text if next_human == -1 else mini(next_text, next_human))
		if start == -1:
			return found
		var got := read_link_at(text, start)
		if got == null:
			at = start + 1
		else:
			found.append(got)
			at = got.end
	return found

## Whether [param prefix] is written at [param index] of the text, as written.
static func _starts_at(text: String, index: int, prefix: String) -> bool:
	return index + prefix.length() <= text.length() and text.substr(index, prefix.length()) == prefix

## Whether the text from [param index] to [param end] parses whole as an address.
static func _parses(text: String, index: int, end: int) -> bool:
	return parse_link(text.substr(index, end - index)).ok

## An id's four hyphens at their places in the text from [param at]: checked before a substring is cut, so an end that
## holds no id costs four reads. The caller holds [code]at + 36[/code] within the text.
static func _hyphens_at(text: String, at: int) -> bool:
	return text.unicode_at(at + 8) == 0x2D and text.unicode_at(at + 13) == 0x2D and text.unicode_at(at + 18) == 0x2D \
			and text.unicode_at(at + 23) == 0x2D

## Whether an id at [param at] is worth a parse: right after the prefix (a world's), not after a [code]/[/code], or
## after [code]/<word>/[/code] whose word is one of the 22 types as written. An id after any other word is one the
## parser refuses (uppercase or unknown_type), so it is passed over without a parse (npm's worthParsing).
static func _worth_parsing(text: String, start: int, at: int) -> bool:
	if at == start or text.unicode_at(at - 1) != 0x2F:
		return true
	var from := maxi(text.rfind("/", at - 2) + 1, start)
	return _is_type_word(text.substr(from, at - 1 - from))

## The characters a path segment can hold (an id, a slug, a type word in any case) and the slash between them.
static func _is_path_char(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or c == 0x2F or c == 0x2D

## The run after /w/: the slug's alphabet (lowercase letters, digits, hyphens) and the id's (hex in either case).
static func _is_world_run_char(c: int) -> bool:
	return (c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x7A) or (c >= 0x41 and c <= 0x46) or c == 0x2D

## Whether the character at [param i] glues a run into a word: a letter of any script, a combining mark (Unicode
## categories L and M) or an underscore. A Godot String holds code points, so one index is one whole character.
static func _is_in_a_word(text: String, i: int) -> bool:
	if i < 0 or i >= text.length():
		return false
	var c := text.unicode_at(i)
	return c == 0x5F or OWUnicode.is_letter_or_mark(c)

# -- write ------------------------------------------------------------------------------------------------------------

## The address a writer writes for these parts. A world's own address takes no [param type] and no [param id]; an
## absent part is [code]null[/code], and an empty string is present (it refuses as that part would). [param moment]
## is an int, or a float with no fraction ([code]3.0[/code] is the step 3, as JSON has one number), within 32 bits.
## Refusals come in the writer's order: [code]bad_form[/code], [code]segments[/code], [code]no_world[/code], then
## the reader's.
static func element_address(form: Variant, world: Variant = null, type: Variant = null, id: Variant = null,
		lens: Variant = null, moment: Variant = null) -> Written:
	var step: Variant = null
	var moment_refusal := ""
	if moment != null:
		step = _json_step(moment)
		if step == null:
			moment_refusal = "bad_moment"
	return _write(_part(form, true), _part(world), _part(type), _part(id), _part(lens), step, moment_refusal)

## [method element_address] for parts as a Dictionary, in the shape the npm and Python packages take and the fixture
## writes ([constant KEYS]; a reading's [code]world_is_slug[/code] and [code]canonical[/code] are ignored). A missing
## key is absent like a null. A key outside the shape (a misspelling, another case) is a caller's mistake, not a
## refusal: [member Written.reason] is "" and [member Written.message] names it.
static func element_address_from(parts: Dictionary) -> Written:
	for key in parts:
		if not (key is String or key is StringName) or not KEYS.has(String(key)):
			var w := Written.new()
			w.message = "Not a key of an address: '%s'. The keys are %s." % [key, ", ".join(KEYS)]
			return w
	return element_address(parts.get("form"), parts.get("world"), parts.get("type"), parts.get("id"),
		parts.get("lens"), parts.get("moment"))

static func _write(form: Variant, world: Variant, type: Variant, id: Variant, lens: Variant, step: Variant,
		moment_refusal: String) -> Written:
	var w := Written.new()
	if form != HUMAN and form != TEXT:
		return _refuse(w, "bad_form")
	if (type == null) != (id == null):
		return _refuse(w, "segments")
	if world == null and (form == HUMAN or type == null):
		return _refuse(w, "no_world")
	if world != null and not is_uuid(world):
		return _refuse(w, "bad_world")
	if type != null:
		var why := _type_refusal(type)
		if why != "":
			return _refuse(w, why)
		if not is_uuid(id):
			return _refuse(w, "bad_id")
	if moment_refusal != "":
		return _refuse(w, moment_refusal)
	if lens != null and not is_uuid(lens):
		return _refuse(w, "bad_lens")
	var path := PackedStringArray()
	if world != null:
		path.append(world.to_lower())
	if type != null:
		path.append(type)
		path.append(id.to_lower())
	w.address = (HUMAN_PREFIX if form == HUMAN else TEXT_PREFIX) + "/".join(path)
	if step != null:
		w.address += "@%d" % step
	if lens != null:
		w.address += "?%s=%s" % [LENS_KEY, lens.to_lower()]
	w.ok = true
	return w

## A part as the writer reads it: a String, or null when absent. Anything else is present and never valid: a form
## that is not a String is no form at all, any other part its text.
static func _part(v: Variant, is_form := false) -> Variant:
	if v == null:
		return null
	if v is String or v is StringName:
		return String(v)
	return "" if is_form else str(v)

## A moment given as a number: an int, or a float with no fraction, within the 32-bit range; else null.
static func _json_step(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return v if v >= _I32_MIN and v <= _I32_MAX else null
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v) or floorf(v) != v or v < _I32_MIN or v > _I32_MAX:
				return null
			return int(v)          # -0.0 is the step 0
	return null

# -- the grammar's pieces ---------------------------------------------------------------------------------------------

## A UUID in the hyphenated 8-4-4-4-12 form, any version, its hex in either case. Nothing else.
static func is_uuid(s: String) -> bool:
	if s.length() != 36:
		return false
	for i in 36:
		var c := s.unicode_at(i)
		if i == 8 or i == 13 or i == 18 or i == 23:
			if c != 0x2D:
				return false
		elif not ((c >= 0x30 and c <= 0x39) or (c >= 0x61 and c <= 0x66) or (c >= 0x41 and c <= 0x46)):
			return false
	return true

## A world's slug: 3 to 40 lowercase letters, numbers and single hyphens, no hyphen at either end, never a type word
## (the site reserves them).
static func _is_slug(s: String) -> bool:
	if s.length() < 3 or s.length() > 40 or s.begins_with("-") or s.ends_with("-") or s.contains("--"):
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39) or c == 0x2D):
			return false
	return not _is_type_word(s)

## A moment as written: decimal, an optional minus, no plus, no leading zero, no -0, within the 32-bit range; else null.
static func _text_step(s: String) -> Variant:
	var digits := s.substr(1) if s.begins_with("-") else s
	if digits.is_empty() or digits.length() > 10:
		return null
	for i in digits.length():
		var c := digits.unicode_at(i)
		if c < 0x30 or c > 0x39:
			return null
	if digits.begins_with("0") and (digits.length() > 1 or s.length() > 1):
		return null
	var n := s.to_int()
	return n if n >= _I32_MIN and n <= _I32_MAX else null

static func _is_type_word(word: String) -> bool:
	return OWTypes.SCRIPTS.has(word)

## "" for one of the 22 words; uppercase for one in another case; else unknown_type. ASCII letters fold, nothing else.
static func _type_refusal(word: String) -> String:
	if _is_type_word(word):
		return ""
	return "uppercase" if _is_type_word(_ascii_lower(word)) else "unknown_type"

static func _begins_ascii_nocase(s: String, prefix: String) -> bool:
	return s.length() >= prefix.length() and _ascii_lower(s.substr(0, prefix.length())) == prefix

## A-Z to a-z and nothing else: no Unicode case mapping (the Kelvin sign is not a k).
static func _ascii_lower(s: String) -> String:
	var out := PackedStringArray()
	for i in s.length():
		var c := s.unicode_at(i)
		out.append(String.chr(c + 32) if c >= 0x41 and c <= 0x5A else String.chr(c))
	return "".join(out)

static func _refuse(x: Variant, reason: String) -> Variant:
	x.ok = false
	x.reason = reason
	return x
