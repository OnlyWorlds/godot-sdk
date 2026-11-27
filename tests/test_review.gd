extends RefCounted
## The review profile's rule 1 (schema-dist [code]profiles/review.md[/code], serial 87) as [method OWLens.is_proposed]
## reads it: the npm and Python packages' 24 shared cases (npm [code]test/review.test.mjs[/code] at 4.102.2, Python
## [code]tests/test_review.py[/code] at 0.84.1), same names, same order, and npm 4.151.0's two of rule 5 (serial 114:
## an object holding a key is a mark, whatever its keys) and npm 4.152.0's three doubts ([code]1[/code],
## [code]true[/code] and [code]["a"][/code]) in npm's places, and with serial 116 npm 4.155.0's renamed row and two new
## ones (a [code]by[/code] read as stored), 31 in all. Each case's answer is the packages'
## [code]handsOnAsProposed[/code] column: whether a reader leaves the element out as proposed, a doubt included. Their
## [code]proposedMarkOf[/code] column (the mark's by, expires and lapsed) has no reader here, so it is not ported.
## Characters past ASCII are built from code points.

const M := OWLens.PROPOSED_MARK

## [what, the element's mark field ({} for no key), is_proposed's answer, carries_proposed_mark's answer], in the
## packages' order. The last column is the packages' [code]proposedMarkOf[/code] column read as shown or not (the Unity
## SDK's [code]OWPayload.IsProposed[/code] in its 31 cases): a mark is an object with something in it.
static func _cases() -> Array:
	var fs := String.chr(0x1C)
	var bom := String.chr(0xFEFF)
	var arabic_day := String.chr(0x662) + String.chr(0x660) + String.chr(0x662) + String.chr(0x666) + "-10-01"
	return [
		["no key", {}, false, false],
		["null: settled", {M: null}, false, false],
		["a string: not a mark, a doubt", {M: "yes"}, true, false],
		["an empty string: an empty mark, settled", {M: ""}, false, false],
		["ASCII spaces only: an empty mark, settled", {M: "   "}, false, false],
		["an empty array: an empty mark, settled", {M: []}, false, false],
		["an array holding an empty array: present, not a mark, a doubt", {M: [[]]}, true, false],
		["false: a value, a doubt", {M: false}, true, false],
		["zero: a value, a doubt", {M: 0}, true, false],
		["one: a value, a doubt", {M: 1}, true, false],
		["true: a value, a doubt", {M: true}, true, false],
		["a list holding a string: present, not a mark, a doubt", {M: ["a"]}, true, false],
		["an empty object: an empty mark, settled", {M: {}}, false, false],
		["an object with no key the profile names: present, a mark", {M: {"x": null}}, true, true],
		["rule 5: only a key the table does not name ({\"note\": \"x\"}), a mark that never lapses", {M: {"note": "x"}}, true, true],
		["rule 5: a named key whose value is null ({\"by\": null}), a mark, no proposer named", {M: {"by": null}}, true, true],
		["a whole mark, open", {M: {"by": "m1", "evidence": "seen", "expires": "2026-11-01"}}, true, true],
		["a by read as stored, never trimmed; expires trimmed", {M: {"by": "  m1 ", "expires": " 2026-11-01 "}}, true, true],
		["a by of owner with White_Space around it is not the word owner", {M: {"by": " owner\n"}}, true, true],
		["lapses on its own day", {M: {"by": "m1", "expires": "2026-10-26"}}, true, true],
		["lapsed before today", {M: {"by": "m1", "expires": "2026-10-01"}}, true, true],
		["an expires not shaped as a day", {M: {"by": "m1", "expires": "2026-1-1"}}, true, true],
		["a blank or non-string by", {M: {"by": "   ", "expires": 7}}, true, true],
		["a by that is not a string names nobody", {M: {"by": 7, "expires": "2026-11-01"}}, true, true],
		["U+3000 only: White_Space, an empty mark, settled", {M: String.chr(0x3000)}, false, false],
		["U+001C only: not White_Space, present, a doubt", {M: fs}, true, false],
		["a byte order mark only: not White_Space, present, a doubt", {M: bom}, true, false],
		["a by wrapped in U+001C keeps it", {M: {"by": fs + "m1" + fs}}, true, true],
		["a by wrapped in a byte order mark keeps it", {M: {"by": bom + "m1"}}, true, true],
		["an expires in Arabic-Indic digits is no day", {M: {"by": "m1", "expires": arabic_day}}, true, true],
		["an expires wrapped in a no-break space is trimmed", {M: {"expires": String.chr(0xA0) + "2026-10-01"}}, true, true],
	]

func get_cases() -> Array:
	var out := []
	for c in _cases():
		out.append(["review:" + c[0], _case.bind(c[1], c[2], c[3])])
	return out

func _case(t, mark: Dictionary, proposed: bool, carries: bool) -> void:   # bound arguments come after the call's
	var el := {"id": "a", "name": "A"}
	el.merge(mark)
	t.eq(OWLens.is_proposed(el), proposed, "is_proposed")
	t.eq(OWLens.carries_proposed_mark(el), carries, "carries_proposed_mark")
	t.eq(OWCharacter.new(el).carries_proposed_mark(), carries, "a typed element: carries_proposed_mark")
	if mark.get(M) is int:
		# Godot's JSON reads every number as a float: the zero a parsed body carries is 0.0.
		t.eq(OWLens.is_proposed({"id": "a", "name": "A", M: float(mark[M])}), proposed, "is_proposed, as a float")
		t.eq(OWLens.carries_proposed_mark({"id": "a", "name": "A", M: float(mark[M])}), carries, "carries_proposed_mark, as a float")
	t.done()

func test_the_cases_are_the_packages_31(t) -> void:
	t.eq(_cases().size(), 31, "case count")
	t.eq(M, "x_review_proposed", "the mark key is the profile's")
	t.done()

## The packages' own extra case: what is not an element reads as settled.
func test_not_an_element_reads_as_settled(t) -> void:
	for v in [null, "x", 3, ["a"]]:
		t.eq(OWLens.is_proposed(v), false, var_to_str(v))
	t.done()

## What is not an element carries no mark.
func test_not_an_element_carries_no_mark(t) -> void:
	for v in [null, "x", 3, ["a"]]:
		t.eq(OWLens.carries_proposed_mark(v), false, var_to_str(v))
	t.done()

## The Unity SDK's typed-element test: a typed element reads the mark from the body it was made from, a doubt is
## in doubt and carries no mark, a settled one neither, and the mark is written back as it came.
func test_a_typed_element_reads_the_mark_and_keeps_it(t) -> void:
	var mark := {"by": "0d4e8a2c", "evidence": "the Harbour Ledger, entry 14", "expires": "2026-11-21"}
	var proposed := OWCharacter.new({"id": "c1", "name": "Pal", M: mark})
	t.ok(proposed.carries_proposed_mark(), "an object mark")
	t.eq(proposed.to_dict()[M], mark, "the mark is kept as it came")
	var doubted := OWCharacter.new({"id": "c1", "name": "Pal", M: "check this against the harbour ledger"})
	t.ok(not doubted.carries_proposed_mark(), "a doubt carries no mark")
	t.ok(OWLens.is_proposed(doubted.to_dict()), "a doubt is in doubt, for a reader that hands a world on")
	for body in [{"id": "c1", "name": "Pal", M: null}, {"id": "c1", "name": "Pal"}, {"id": "c1", "name": "Pal", M: {}},
			{"id": "c1", "name": "Pal", M: []}, {"id": "c1", "name": "Pal", M: " "}]:
		t.ok(not OWCharacter.new(body).carries_proposed_mark(), var_to_str(body))
	t.done()
