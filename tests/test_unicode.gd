extends RefCounted
## NFC and OW-18's fold against what Python's unicodedata and the reference checker give (tests/data/unicode_vectors.txt,
## generated with the tables), strict UTF-8, and the white space a world id is trimmed of.

func _hex(s: String) -> String:
	var parts := PackedStringArray()
	for i in s.length():
		parts.append("%X" % s.unicode_at(i))
	return " ".join(parts)

func _str(hex: String) -> String:
	var out := ""
	for h in hex.split(" ", false):
		out += String.chr(h.hex_to_int())
	return out

func test_nfc_and_fold_match_python(t) -> void:
	var lines := FileAccess.get_file_as_string("res://tests/data/unicode_vectors.txt").split("\n", false)
	var n := 0
	var nfc_bad := 0
	var fold_bad := 0
	for line in lines:
		if line.begins_with("#"):
			continue
		var cols := line.split(";")
		var s := _str(cols[0])
		n += 1
		var got := _hex(OWUnicode.nfc(s))
		if got != cols[1]:
			nfc_bad += 1
			if nfc_bad <= 5:
				t.fail("NFC of [%s]: Python %s, got %s" % [cols[0], cols[1], got])
		got = _hex(OWUnicode.fold(s))
		if got != cols[2]:
			fold_bad += 1
			if fold_bad <= 5:
				t.fail("fold of [%s]: Python %s, got %s" % [cols[0], cols[2], got])
	t.eq(n, int(lines[1].get_slice(", ", 1).get_slice(" ", 0)), "every vector read (%d)" % n)
	t.eq(nfc_bad, 0, "NFC disagreements with Python")
	t.eq(fold_bad, 0, "fold disagreements with the reference checker")
	t.eq(OWUnicode.D.UNICODE_VERSION, "15.1.0", "the tables' Unicode version")
	t.done()

func test_the_fixture_set_pairs(t) -> void:
	t.eq(OWUnicode.fold("café"), OWUnicode.fold("café"), "NFC and NFD one name")
	t.eq(OWUnicode.fold("Café"), OWUnicode.fold("café"), "NFC then fold")
	t.eq(OWUnicode.fold("σ"), OWUnicode.fold("ς"), "final sigma folds")
	t.eq(OWUnicode.fold("ﬅ"), OWUnicode.fold("ﬆ"), "the S row: long s t")
	t.eq(OWUnicode.fold("ΐ"), OWUnicode.fold("ΐ"), "iota with dialytika and oxia: NFC singleton")
	t.ok(OWUnicode.fold("straße") != OWUnicode.fold("strasse"), "simple folding leaves sharp s alone")
	t.eq(OWUnicode.fold("abbey/Elements"), "abbey/elements", "ASCII")
	t.done()

func test_strict_utf8(t) -> void:
	t.ok(OWUnicode.is_utf8("café 😀".to_utf8_buffer()), "well-formed")
	t.ok(not OWUnicode.is_utf8(PackedByteArray([0x63, 0x61, 0x66, 0xE9])), "Latin-1 e acute")
	t.ok(not OWUnicode.is_utf8(PackedByteArray([0xC0, 0xAF])), "overlong")
	t.ok(not OWUnicode.is_utf8(PackedByteArray([0xED, 0xA0, 0x80])), "a surrogate")
	t.ok(not OWUnicode.is_utf8(PackedByteArray([0xF4, 0x90, 0x80, 0x80])), "past U+10FFFF")
	t.ok(not OWUnicode.is_utf8(PackedByteArray([0xE2, 0x82])), "cut short")
	t.eq(OWUnicode.decode_utf8(PackedByteArray([0xE9])), null, "never a U+FFFD guess")
	t.done()

func test_strip_white_space_as_python(t) -> void:
	t.eq(OWUnicode.strip_ws("  \t\nabc　 "), "abc", "ASCII and Unicode white space")
	t.eq(OWUnicode.strip_ws("　 "), "", "only white space")
	t.eq(OWUnicode.strip_ws("​x"), "​x", "a zero-width space is not white space to Python")
	t.done()
