extends RefCounted
## OWUnicode.trim_and_fold and OWUnicode.by_code_point: names compared as the profiles compare them (the room
## profile's "trimmed and without regard to case, defined once"; ordered by code point). The TypeScript SDK's
## test/names-compare.test.mjs (4.180.0), ported: each case a place where a language's own function answers
## differently (a trim that takes a byte order mark or U+001C, a lower-casing that leaves the long s, an order by
## UTF-16 unit). Its seventh, a value that is no string refused, is a typed parameter here and is not ported.

## The 25 code points of Unicode's White_Space property (PropList.txt).
const WHITE_SPACE := [
	0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x20, 0x85, 0xa0, 0x1680,
	0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
	0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
]

static func _cp(points: Array) -> String:
	var s := ""
	for p in points:
		s += String.chr(p)
	return s

static func _all_white() -> String:
	return _cp(WHITE_SPACE)

func test_trim_and_fold_trims_each_white_space_code_point_at_either_end_and_nothing_inside(t) -> void:
	for w in WHITE_SPACE:
		t.eq(OWUnicode.trim_and_fold(_cp([w]) + "in design" + _cp([w])), "in design", "U+%x" % w)
	t.eq(OWUnicode.trim_and_fold(_all_white() + "Locked" + _all_white()), "locked", "all 25 at both ends")
	t.eq(OWUnicode.trim_and_fold("in" + _cp([0x3000]) + "design"), "in" + _cp([0x3000]) + "design", "nothing inside")
	t.eq(OWUnicode.trim_and_fold(""), "", "the empty string")
	t.eq(OWUnicode.trim_and_fold(_all_white()), "", "white space alone")
	t.done()

func test_trim_and_fold_keeps_what_is_no_white_space_where_a_language_trim_takes_it(t) -> void:
	# JavaScript's trim() strips U+FEFF; Python's strip() strips U+001C to U+001F. None is White_Space.
	for keep in [0xfeff, 0x200b, 0x180e, 0x1c, 0x1d, 0x1e, 0x1f]:
		t.eq(OWUnicode.trim_and_fold(_cp([keep]) + "locked"), _cp([keep]) + "locked", "leading U+%x" % keep)
		t.eq(OWUnicode.trim_and_fold("locked" + _cp([keep])), "locked" + _cp([keep]), "trailing U+%x" % keep)
	# Godot's own strip_edges() takes every code point up to U+0020, U+001C included.
	t.ok(OWUnicode.trim_and_fold(_cp([0x1c]) + "in design") != (_cp([0x1c]) + "in design").strip_edges(),
		"strip_edges is not this trim")
	t.done()

func test_trim_and_fold_folds_by_the_simple_rows_only_never_by_lower_casing_or_full_folding(t) -> void:
	t.eq(OWUnicode.trim_and_fold("ME" + _cp([0x17f, 0x17f]) + "AGE"), "message", "the long s folds to s")
	t.eq(OWUnicode.trim_and_fold(_cp([0x212a]) + "ing"), "king", "the Kelvin sign folds to k")
	t.eq(OWUnicode.trim_and_fold("Me" + _cp([0xdf]) + "age"), "me" + _cp([0xdf]) + "age", "the sharp s has only a full folding")
	t.eq(OWUnicode.trim_and_fold(_cp([0x131])), _cp([0x131]), "the dotless i has no row")
	t.eq(OWUnicode.trim_and_fold(_cp([0x130])), _cp([0x130]), "the dotted capital I has only F and T rows")
	t.eq(OWUnicode.trim_and_fold("te" + _cp([0xfb06])), "te" + _cp([0xfb06]), "the st ligature: full folding only")
	t.eq(OWUnicode.trim_and_fold(_cp([0x10400])), _cp([0x10428]), "an astral letter folds by its row")
	t.eq(OWUnicode.trim_and_fold("LOCKED"), "locked", "ASCII")
	t.done()

func test_trim_and_fold_is_the_fold_the_room_reader_matches_pairs_by(t) -> void:
	var room := {"id": "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e01", "x_room_of": "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e0f"}
	t.eq(OWUnicode.trim_and_fold(_cp([0x85]) + "NARRATIVE" + _cp([0x3000])), "narrative", "the type folded")
	var line := room.duplicate()
	line["type"] = _cp([0x85]) + "NARRATIVE" + _cp([0x3000])
	line["supertype"] = "ME" + _cp([0x17f, 0x17f]) + "AGE"
	t.eq(OWLens._is_room_element(line), true, "a room element by the fold")
	var bom := room.duplicate()
	bom["type"] = _cp([0xfeff]) + "narrative"
	bom["supertype"] = "Message"
	t.eq(OWLens._is_room_element(bom), false, "a byte order mark is not trimmed")
	t.eq(OWUnicode.trim_and_fold(" Lens" + _cp([0x3000])), OWUnicode.profile_fold(" Lens" + _cp([0x3000])), "profile_fold's name")
	t.done()

func test_by_code_point_orders_by_code_point_where_utf16_units_part_from_it(t) -> void:
	var astral := _cp([0x10428])
	var full_width := _cp([0xff5a])
	t.ok(OWUnicode.by_code_point(full_width, astral) < 0, "U+FF5A before U+10428")
	t.ok(OWUnicode.by_code_point(astral, full_width) > 0, "U+10428 after U+FF5A")
	var sorted := [astral, full_width, "z", "Z"]
	sorted.sort_custom(func(x, y): return OWUnicode.by_code_point(x, y) < 0)
	t.eq(sorted, ["Z", "z", full_width, astral], "sort_custom by it")
	var plain := [astral, full_width, "z", "Z"]
	plain.sort()
	t.eq(plain, ["Z", "z", full_width, astral], "sort() on Strings is the same order")
	t.eq(OWUnicode.by_code_point("", ""), 0, "two empty strings")
	t.eq(OWUnicode.by_code_point("abc", "abc"), 0, "the same string")
	t.ok(OWUnicode.by_code_point("ab", "abc") < 0, "a prefix sorts first")
	t.ok(OWUnicode.by_code_point("abc", "ab") > 0, "and the longer after")
	t.ok(OWUnicode.by_code_point("Zebra", "apple") < 0, "by code point, never a collation")
	t.done()

func test_names_ordered_as_the_profiles_order_them_folds_by_code_point_ties_by_id(t) -> void:
	var rows := [
		{"id": "b2", "name": " apple"},
		{"id": "a1", "name": _cp([0x2003]) + "APPLE"},
		{"id": "c3", "name": _cp([0x10400])},
		{"id": "d4", "name": _cp([0xff3a])},
	]
	rows.sort_custom(func(x, y):
		var by_name := OWUnicode.by_code_point(OWUnicode.trim_and_fold(x["name"]), OWUnicode.trim_and_fold(y["name"]))
		return by_name < 0 if by_name != 0 else OWUnicode.by_code_point(x["id"], y["id"]) < 0)
	t.eq(rows.map(func(r): return r["id"]), ["a1", "b2", "d4", "c3"], "")
	t.done()
