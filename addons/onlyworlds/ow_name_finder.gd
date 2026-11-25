class_name OWNameFinder
extends RefCounted
## Element names found in prose: [method name_finder] reads a world's names once and answers a finder,
## whose [method find] lists them in any text. It finds and never writes: what a game does with a found name (a hover,
## a tooltip, a link a player follows) is the game's.
##
## The TypeScript SDK's [code]nameFinder[/code] (4.198.0) and the Python package's [code]name_finder[/code], ported: a
## rule of those packages, not of the standard. All three run one file of cases (here
## [code]tests/data/name-finder.cases.json[/code], the same bytes).

## Compare a name with the text as written.
const EXACT := "exact"
## Compare by simple case folding (the C and S rows of CaseFolding 15.1, the fold the [code].owworld[/code] reader uses).
const FOLDED := "folded"

## A name shorter than this many characters (code points, after its white space is trimmed) is never looked for.
const NAME_MIN := 3
## The mark the matcher reads between two characters wherever a name may end: before a character that is not a word
## character, and at the end of the text. No code point is negative.
const _END := -1

## Whether each ASCII character is a word character (1) or not (0): [method is_word] for the first 128 code points.
static var _ascii_word: PackedByteArray = _ascii_table()

## One name found in a text.
class Found:
	## The index of the name's first character: a Godot String index, which counts code points, as
	## [method String.substr] and [method OWAddress.find_links] do.
	var start := 0
	## The index just past the name's last character.
	var end := 0
	## The element the name belongs to: the same Dictionary or Object [method OWNameFinder.name_finder] was given.
	var element: Variant

## A name two or more elements hold: [method OWNameFinder.find] answers nothing for it, and this says it is there.
class Shared:
	## The name as the finder compares it: trimmed of white space, and folded when the case is [constant FOLDED].
	var name := ""
	## The elements that hold it, two at least, in the order they were given: the same values the finder was given.
	## Read only.
	var elements: Array = []

## One name as compared, and every element that holds it.
class _Hit:
	var length := 0
	var elements: Array = []
	## The ids of [member elements], kept once a second element holds the name.
	var ids: Variant = null
	var name := ""

## A caller's mistake, said by name, when [method name_finder] read nothing; "" otherwise. A finder with an error finds
## nothing and shares nothing.
var error := ""
## Every name two or more elements hold, each a [Shared], in the order each name was first met. [method find] never
## answers one of these, so a game reads this list to say why a name stays plain. The list and each entry's
## [member Shared.elements] are read only.
var shared: Array = []

var _folded := false
var _hits: Array = []
## The matcher's states by index, 0 the root: each one's next states by token, its failure state, and the longest name
## that ends at it (an index into [member _hits], or -1).
var _next: Array = []
var _fail := PackedInt32Array()
var _longest := PackedInt32Array()

## A finder of a world's element names in prose: read the names once, then call [method find] on each text.
##
## [param elements] is an Array of elements, each a Dictionary or an Object (an [OWElement] of any type) with a
## non-empty String [code]id[/code] and a [code]name[/code]. [param name_case] must be given: [constant EXACT] (a name
## as written) or [constant FOLDED] (simple case folding, Unicode 15.1), with no default, so a game never gets the other
## rule by leaving it out. [param names] is a Callable from an element to an Array of the names it is found by; without
## it an element is found by its [code]name[/code] alone. A name that is not a String is passed over.
##
## What [method find] answers, every [Found] in order, none overlapping:
##
## - A whole name only: the character on each side of it is not a letter, a combining mark, a decimal digit or an
##   underscore, in any script (general categories L, M and Nd as Unicode 15.1 assigns them, the table this addon
##   generates; [method is_word]). So "Kira's" and "Kira-led" hold the name "Kira", and "Kiran" does not.
## - A name is trimmed of white space (Unicode's White_Space, [method OWUnicode.trim_white_space]) and is three
##   characters at least; a shorter one is never looked for.
## - Where several names start at one place, the longest whole one is taken ("Iron Gate" over "Iron").
## - A name two elements share is never answered, and nothing inside it is: the text stays plain there. One element
##   listed twice, or found by two of its own names, is one element (by its id, as written).
## - Nothing is read inside an address (what [method OWAddress.find_links] finds), a Markdown link
##   [code][label](target)[/code], a bare web address ([code]https://…[/code] to the next white space or [code]<[/code])
##   or an autolink ([code]<scheme:…>[/code]), and no name is read across the edge of one. With
##   [code]find(text, true)[/code], for a text known to be Markdown, nothing is read inside an inline code span, a fenced
##   code block, an HTML tag or comment, or a reference definition's line either. An indented code block, a fence
##   inside a quote or a list, and a definition's title on the next line are read as prose.
## - Text is compared as written: no Unicode normalisation, and a space in a name matches that one space.
##
## [member shared] lists every name two or more elements hold. Nothing given is changed. The work for one text grows
## with its length alone, whatever the names and however many: the text is read once, from its end to its start, and no
## character is read again for another name. Reading the names grows with their total length.
## [codeblock]
## var finder := OWNameFinder.name_finder([{"id": "a1", "name": "Iron Gate"}, {"id": "b2", "name": "Kira"}], OWNameFinder.EXACT)
## for f in finder.find("Kira's watch ends at the Iron Gate."):
##     print(f.start, " ", f.end, " ", f.element["id"])      # 0 4 b2, then 25 34 a1
## [/codeblock]
static func name_finder(elements: Variant, name_case: Variant, names: Variant = null) -> OWNameFinder:
	var f := OWNameFinder.new()
	f.shared.make_read_only()
	if not (name_case is String and (name_case == EXACT or name_case == FOLDED)):
		return f._mistake("name_case is \"exact\" or \"folded\", and must be given; got %s" % var_to_str(name_case))
	if names != null and not (names is Callable):
		return f._mistake("names is a Callable from an element to its names; got %s" % var_to_str(names))
	if not (elements is Array):
		return f._mistake("elements is an Array of elements with an id and a name; got %s" % var_to_str(elements))
	f._folded = name_case == FOLDED
	f._next = [{}]
	f._fail = PackedInt32Array([-1])
	f._longest = PackedInt32Array([-1])
	var hit_at := PackedInt32Array([-1])   # the name that is this state, read backwards, or -1
	for element in elements:
		var id: Variant = element.get("id") if (element is Dictionary or element is Object) else null
		if not (id is String) or id == "":
			return f._mistake("every element has a String id that is not empty; got %s" % var_to_str(element))
		var raws: Variant = [element.get("name")]
		if names != null:
			raws = names.call(element)
			if raws is PackedStringArray:
				raws = Array(raws)
			if not (raws is Array):
				return f._mistake("names answers an Array of names for each element; got %s" % var_to_str(raws))
		for raw in raws:
			if not (raw is String):
				continue
			var trimmed := OWUnicode.trim_white_space(raw)
			var n := trimmed.length()
			if n < NAME_MIN:
				continue
			var points := PackedInt32Array()
			points.resize(n)
			for i in n:
				var c := trimmed.unicode_at(i)
				points[i] = OWUnicode.fold_code_point(c) if f._folded else c
			# The name backwards: the end mark, then each character from the last to the first, and the mark again
			# after (so, in the text, before) every character but the first that is not a word character.
			var tokens := PackedInt32Array([_END])
			for k in range(n - 1, -1, -1):
				tokens.append(points[k])
				if k > 0 and not is_word(points[k]):
					tokens.append(_END)
			var state := 0
			for token in tokens:
				var child: int = f._next[state].get(token, -1)
				if child == -1:
					child = f._next.size()
					f._next.append({})
					f._fail.append(-1)
					f._longest.append(-1)
					hit_at.append(-1)
					f._next[state][token] = child
				state = child
			if hit_at[state] == -1:
				var hit := _Hit.new()
				hit.length = n
				hit.elements = [element]
				hit.name = trimmed if not f._folded else _string_of(points)
				hit_at[state] = f._hits.size()
				f._hits.append(hit)
			else:
				var hit: _Hit = f._hits[hit_at[state]]
				if hit.ids == null:
					var first: String = hit.elements[0].get("id")
					if first != id:
						hit.ids = {first: true, id: true}
						hit.elements.append(element)
				elif not hit.ids.has(id):
					hit.ids[id] = true
					hit.elements.append(element)

	# The failure links, level by level: where the matcher goes on when the text leaves the name it was reading.
	var level := PackedInt32Array()
	for token in f._next[0]:
		var child: int = f._next[0][token]
		f._fail[child] = 0
		f._longest[child] = hit_at[child]
		level.append(child)
	while not level.is_empty():
		var deeper := PackedInt32Array()
		for state in level:
			var nexts: Dictionary = f._next[state]
			for token in nexts:
				var child: int = nexts[token]
				var back := f._fail[state]
				while back != -1 and not f._next[back].has(token):
					back = f._fail[back]
				var fail: int = 0 if back == -1 else f._next[back][token]
				f._fail[child] = fail
				f._longest[child] = hit_at[child] if hit_at[child] != -1 else f._longest[fail]
				deeper.append(child)
		level = deeper

	var listed := []
	for hit: _Hit in f._hits:
		if hit.elements.size() > 1:
			var s := Shared.new()
			s.name = hit.name
			s.elements = hit.elements.duplicate()
			s.elements.make_read_only()
			listed.append(s)
	listed.make_read_only()
	f.shared = listed
	return f

## Every name of the finder's elements in [param text], each a [Found], in order, none overlapping (the rules are
## [method name_finder]'s). [member Found.start] and [member Found.end] count code points. Each call answers a new
## Array, the caller's own. [param markdown] true says the text is Markdown: its code, HTML and reference definitions are
## passed over too (the TypeScript SDK's [code]find(text, { markdown: true })[/code], 4.208.0); false, the default,
## keeps a rich-text node's literal backticks as prose.
func find(text: String, markdown: bool = false) -> Array:
	var found := []
	if _hits.is_empty():
		return found
	var spans := _passed_over(text, markdown)
	var length := text.length()
	# Where a whole name starts and the longest one that does, as the backward pass meets them: last place first.
	var starts := PackedInt32Array()
	var longest := PackedInt32Array()
	var from := 0
	for span in spans.size() + 1:
		var to: int = spans[span][0] if span < spans.size() else length
		if to > from:
			starts.clear()
			longest.clear()
			var state := 0
			var k := to
			# Whether a name may end at k: the text ends there, or the character at k is not a word character.
			var may_end := k >= length or not is_word(text.unicode_at(k))
			# The steps are written out here (a call is dear in GDScript): the state's own next first, then _step's
			# walk down the failure links; an ASCII character's kind from a table, any other from is_word.
			while k > from:
				if may_end:
					var to_end: int = _next[state].get(_END, -1)
					state = to_end if to_end != -1 else _step(state, _END)
				k -= 1
				var c := text.unicode_at(k)
				may_end = _ascii_word[c] == 0 if c < 0x80 else not is_word(c)
				if state != 0:
					var token := OWUnicode.fold_code_point(c) if _folded else c
					var to_char: int = _next[state].get(token, -1)
					state = to_char if to_char != -1 else _step(state, token)
				var h := _longest[state]
				if h != -1 and (k == 0 or not is_word(text.unicode_at(k - 1))):
					starts.append(k)
					longest.append(h)
			# Forwards over what was met: the first place a name starts takes its longest name, and the next name
			# starts at or after that one's end.
			var free := from
			for r in range(starts.size() - 1, -1, -1):
				var start := starts[r]
				if start < free:
					continue
				var hit: _Hit = _hits[longest[r]]
				var end := start + hit.length
				if hit.elements.size() == 1:
					var one := Found.new()
					one.start = start
					one.end = end
					one.element = hit.elements[0]
					found.append(one)
				free = end
		if span < spans.size():
			from = spans[span][1]
	return found

## Whether [param c] puts a name beside it inside a word: a letter of any script, a combining mark, a decimal digit
## (general categories L, M and Nd, Unicode 15.1) or an underscore.
static func is_word(c: int) -> bool:
	if c < 0x80:
		return (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A) or c == 0x5F
	return OWUnicode.is_letter_or_mark(c) or OWUnicode.is_decimal_digit(c)

static func _ascii_table() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(0x80)
	for c in 0x80:
		t[c] = 1 if is_word(c) else 0
	return t

func _step(from: int, token: int) -> int:
	var state := from
	while state != -1:
		var to: int = _next[state].get(token, -1)
		if to != -1:
			return to
		state = _fail[state]
	return 0

func _mistake(message: String) -> OWNameFinder:
	error = "name_finder: " + message
	return self

static func _string_of(points: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for p in points:
		parts.append(String.chr(p))
	return "".join(parts)

## Every Markdown link [code][label](target)[/code] in a text as [code][start, end][/code]: a [code][[/code], a label
## up to the first [code]][/code], a [code]([/code] right after it, a target up to the first [code])[/code]. One pass:
## each bracket and parenthesis is searched for once.
static func _markdown_links(text: String) -> Array:
	var spans := []
	var close := -2
	var paren := -2
	var open := text.find("[")
	while open != -1:
		if close <= open:
			close = text.find("]", open + 1)
		if close == -1:
			break
		if close + 1 >= text.length() or text.unicode_at(close + 1) != 0x28:
			open = text.find("[", open + 1)
			continue
		if paren < close + 2:
			paren = text.find(")", close + 2)
		if paren == -1:
			break
		spans.append([open, paren + 1])
		open = text.find("[", paren + 1)
	return spans

## Unicode's White_Space code points: the end of a bare web address and of an autolink.
static func _is_white_space(c: int) -> bool:
	return (c >= 0x09 and c <= 0x0d) or c == 0x20 or c == 0x85 or c == 0xa0 or c == 0x1680 \
		or (c >= 0x2000 and c <= 0x200a) or c == 0x2028 or c == 0x2029 or c == 0x202f or c == 0x205f or c == 0x3000

static func _is_ascii_letter(c: int) -> bool:
	return (c >= 0x41 and c <= 0x5a) or (c >= 0x61 and c <= 0x7a)

static func _is_scheme_char(c: int) -> bool:
	return _is_ascii_letter(c) or (c >= 0x30 and c <= 0x39) or c == 0x2b or c == 0x2e or c == 0x2d

## The code point at [param i], or -1 outside the text.
static func _at(text: String, i: int) -> int:
	return text.unicode_at(i) if i >= 0 and i < text.length() else -1

## [param text].find, -1 when [param from] is past the end.
static func _find_from(text: String, what: String, from: int) -> int:
	return -1 if from > text.length() else text.find(what, from)

## True when the four or five code points before [param at] spell [code]http[/code] (or [code]https[/code] when
## [param s]), in ASCII case alone.
static func _scheme_before(text: String, at: int, s: bool) -> bool:
	var word := "https" if s else "http"
	for k in word.length():
		if (_at(text, at + k) | 0x20) != word.unicode_at(k):
			return false
	return true

## Every bare web address and every autolink, in any text. A bare address starts at [code]http://[/code] or
## [code]https://[/code] (the scheme in any ASCII case) and runs to just before the first white space or [code]<[/code].
## An autolink is [code]<[/code], a scheme (an ASCII letter, then 1 to 31 of letters, digits, [code]+[/code],
## [code].[/code] or [code]-[/code]), [code]:[/code], then anything but white space, a control character, [code]<[/code]
## or [code]>[/code], up to the closing [code]>[/code]. The TypeScript SDK's webAddresses (4.208.0).
static func _web_addresses(text: String) -> Array:
	var spans := []
	var n_text := text.length()
	var floor_at := 0
	var p := text.find("://")
	while p != -1:
		var at := -1
		if p - 5 >= floor_at and _scheme_before(text, p - 5, true):
			at = p - 5
		elif p - 4 >= floor_at and _scheme_before(text, p - 4, false):
			at = p - 4
		if at == -1:
			p = _find_from(text, "://", p + 1)
			continue
		var end := p + 3
		while end < n_text:
			var c := text.unicode_at(end)
			if _is_white_space(c) or c == 0x3c:
				break
			end += 1
		spans.append([at, end])
		floor_at = end
		p = _find_from(text, "://", end)
	var open := text.find("<")
	while open != -1:
		var i := open + 1
		if _is_ascii_letter(_at(text, i)):
			var n := 1
			i += 1
			while i < n_text and n < 32 and _is_scheme_char(text.unicode_at(i)):
				i += 1
				n += 1
			if n >= 2 and _at(text, i) == 0x3a:
				i += 1
				var c := _at(text, i)
				while i < n_text and c != 0x3e and c != 0x3c and c >= 0x20 and c != 0x7f and not _is_white_space(c):
					i += 1
					c = _at(text, i)
				if i < n_text and c == 0x3e:
					spans.append([open, i + 1])
					open = _find_from(text, "<", i + 1)
					continue
		open = _find_from(text, "<", open + 1)
	return spans

## A line's fence, after at most three spaces: [char, length, after] for a run of three or more backticks or tildes,
## or an empty Array.
static func _fence_of(text: String, start: int, end: int) -> Array:
	var i := start
	while i < end and i - start < 3 and text.unicode_at(i) == 0x20:
		i += 1
	var ch := _at(text, i)
	if ch != 0x60 and ch != 0x7e:
		return []
	var j := i
	while j < end and text.unicode_at(j) == ch:
		j += 1
	return [ch, j - i, j] if j - i >= 3 else []

## The Markdown stretches no name is read in ([code]markdown[/code] true). Fenced code blocks first: a line whose fence
## opens one (a backtick fence holds no backtick in the rest of its line) runs to a later line holding only a fence of
## the same character, at least as long, and spaces or tabs after it, or to the end of the text. Outside them: an inline
## code span (a run of backticks to the next run of exactly as many; a run with none is prose), an HTML comment
## ([code]<!--[/code] to the first [code]-->[/code]), an HTML tag ([code]<[/code], an optional [code]/[/code], an ASCII
## letter, to the first [code]>[/code]), and a reference definition's line (after at most three spaces, [code][[/code],
## a label, and the line's first [code]][/code] followed by [code]:[/code]). The TypeScript SDK's markdownStretches.
static func _markdown_stretches(text: String) -> Array:
	var spans := []
	var n_text := text.length()
	var lines := []
	var start := 0
	while true:
		var nl := _find_from(text, "\n", start)
		if nl == -1:
			lines.append([start, n_text])
			break
		lines.append([start, nl])
		start = nl + 1
	var outside := []
	var seg_start := 0
	var bracket := -2 # the next ] at or after the place last asked about, searched for once per place passed
	var k := 0
	while k < lines.size():
		var ls: int = lines[k][0]
		var le: int = lines[k][1]
		var open := _fence_of(text, ls, le)
		var tick := -1
		if not open.is_empty() and open[0] == 0x60:
			tick = _find_from(text, "`", open[2])
		if open.is_empty() or (tick != -1 and tick < le):
			var i := ls
			while i < le and i - ls < 3 and text.unicode_at(i) == 0x20:
				i += 1
			if _at(text, i) == 0x5b:
				if bracket != -1 and bracket < i + 1:
					bracket = _find_from(text, "]", i + 1)
				var close := bracket
				if close != -1 and close < le and close > i + 1 and _at(text, close + 1) == 0x3a:
					spans.append([ls, le])
			k += 1
			continue
		var m := k + 1
		while m < lines.size():
			var cs: int = lines[m][0]
			var ce: int = lines[m][1]
			var shut := _fence_of(text, cs, ce)
			if not shut.is_empty() and shut[0] == open[0] and shut[1] >= open[1]:
				var j: int = shut[2]
				while j < ce and (text.unicode_at(j) == 0x20 or text.unicode_at(j) == 0x09 or text.unicode_at(j) == 0x0d):
					j += 1
				if j == ce:
					break
			m += 1
		var block_end: int = lines[m][1] if m < lines.size() else n_text
		if ls > seg_start:
			outside.append([seg_start, ls])
		spans.append([ls, block_end])
		seg_start = block_end
		k = m + 1
	if seg_start < n_text:
		outside.append([seg_start, n_text])
	for seg in outside:
		var s: int = seg[0]
		var e: int = seg[1]
		# Inline code spans: every maximal backtick run, then each opening run to the next run of its length.
		var run_at := PackedInt32Array()
		var run_n := PackedInt32Array()
		var t := _find_from(text, "`", s)
		while t != -1 and t < e:
			var j := t
			while j < e and text.unicode_at(j) == 0x60:
				j += 1
			run_at.append(t)
			run_n.append(j - t)
			t = _find_from(text, "`", j)
		var by_length := {}
		for idx in run_at.size():
			if not by_length.has(run_n[idx]):
				by_length[run_n[idx]] = []
			by_length[run_n[idx]].append(idx)
		var cursor := {}
		var r := 0
		while r < run_at.size():
			var n := run_n[r]
			var list: Array = by_length[n]
			var c: int = cursor.get(n, 0)
			while c < list.size() and list[c] <= r:
				c += 1
			cursor[n] = c
			if c < list.size():
				spans.append([run_at[r], run_at[list[c]] + n])
				r = list[c] + 1
			else:
				r += 1
		# HTML comments and tags.
		var gt := -2
		var comment_end := -2
		var lt := _find_from(text, "<", s)
		while lt != -1 and lt < e:
			if text.substr(lt, 4) == "<!--":
				if comment_end != -1 and comment_end < lt + 4:
					comment_end = _find_from(text, "-->", lt + 4)
				if comment_end != -1 and comment_end + 3 <= e:
					spans.append([lt, comment_end + 3])
					lt = _find_from(text, "<", comment_end + 3)
					continue
			else:
				var name := lt + 2 if _at(text, lt + 1) == 0x2f else lt + 1
				if _is_ascii_letter(_at(text, name)):
					if gt != -1 and gt < name:
						gt = _find_from(text, ">", name)
					if gt != -1 and gt < e:
						spans.append([lt, gt + 1])
						lt = _find_from(text, "<", gt + 1)
						continue
			lt = _find_from(text, "<", lt + 1)
	return spans

## The stretches no name is read in, in order, none overlapping: every address, every Markdown link, every bare web
## address and autolink, and with [param markdown] the Markdown stretches too.
static func _passed_over(text: String, markdown: bool = false) -> Array:
	var spans := _markdown_links(text)
	for a in OWAddress.find_links(text):
		spans.append([a.start, a.end])
	spans.append_array(_web_addresses(text))
	if markdown:
		spans.append_array(_markdown_stretches(text))
	spans.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := []
	for s in spans:
		if not out.is_empty() and s[0] < out[-1][1]:
			if s[1] > out[-1][1]:
				out[-1][1] = s[1]
		else:
			out.append([s[0], s[1]])
	return out
