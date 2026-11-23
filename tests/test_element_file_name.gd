extends RefCounted
## A new element's file name is the folder format's (§3.2, the RECOMMENDED profile): [code]<slug>--<id tail>.json[/code],
## the slug the name's compatibility decomposition (NFKD) with U+0300 to U+036F dropped, lowercase ASCII letters and
## digits with every other run one hyphen, none at either end, cut to 40 and a hyphen the cut leaves stripped; the tail
## the id's last eight characters (the id without its hyphens when those would hold "--" or start with "-"); a name
## with no slug gives [code]<full id>.json[/code]. The expected names are what the TypeScript package's folder writer
## gives the same names (its folderFiles, run on Node), so two tools give one new element one name. An element the
## world read keeps the name it was read from, whatever this rule would give it now.

const P = preload("res://tests/paths.gd")

const WORLD := "{\n  \"id\": \"019a9200-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const A := "019a9300-0000-7000-8000-0000000000c9"
const B := "019a9400-0000-7000-8000-0000000000c9"     # the same eight-character tail as A, a higher id

## [what the row holds, the name, the id, the TypeScript package's file name for it]
const ROWS := [
	["plain ASCII", "Ana", "019a9300-0000-7000-8000-0000000000c9", "ana--000000c9.json"],
	["acute, precomposed", "Brother Tom\u00E1s", "019a9300-0000-7000-8000-0000000000c9", "brother-tomas--000000c9.json"],
	["acute, decomposed", "Jose\u0301", "019a9300-0000-7000-8000-0000000000c9", "jose--000000c9.json"],
	["caron and capitals", "\u017Di\u017Ekov", "019a9300-0000-7000-8000-0000000000c9", "zizkov--000000c9.json"],
	["ae and o-slash (no decomposition)", "\u00C6r\u00F8sk\u00F8bing", "019a9300-0000-7000-8000-0000000000c9", "r-sk-bing--000000c9.json"],
	["ligature fi", "\uFB01re", "019a9300-0000-7000-8000-0000000000c9", "fire--000000c9.json"],
	["sharp s", "Stra\u00DFe", "019a9300-0000-7000-8000-0000000000c9", "stra-e--000000c9.json"],
	["upper case", "\u00C9COLE NORMALE", "019a9300-0000-7000-8000-0000000000c9", "ecole-normale--000000c9.json"],
	["spaces and punctuation runs", "  --Hello__World!! ", "019a9300-0000-7000-8000-0000000000c9", "hello-world--000000c9.json"],
	["leading and trailing hyphens", "-lead and trail-", "019a9300-0000-7000-8000-0000000000c9", "lead-and-trail--000000c9.json"],
	["digits and hyphen", "R2-D2", "019a9300-0000-7000-8000-0000000000c9", "r2-d2--000000c9.json"],
	["tab and newline", "Line\tOne\nTwo", "019a9300-0000-7000-8000-0000000000c9", "line-one-two--000000c9.json"],
	["41 letters, cut lands on a hyphen", "aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaa b", "019a9300-0000-7000-8000-0000000000c9", "aaaaaaaaaa-aaaaaaaaaa-aaaaaaaaaa-aaaaaa--000000c9.json"],
	["43 letters, cut mid-word", "aaaaaaaaaa aaaaaaaaaa aaaaaaaaaa aaaaaaaa b", "019a9300-0000-7000-8000-0000000000c9", "aaaaaaaaaa-aaaaaaaaaa-aaaaaaaaaa-aaaaaaa--000000c9.json"],
	["14 ffi ligatures: 14 chars, 42 after folding", "\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03\uFB03", "019a9300-0000-7000-8000-0000000000c9", "ffiffiffiffiffiffiffiffiffiffiffiffiffif--000000c9.json"],
	["39 a + two math-bold capitals (surrogate pairs) at the cut", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\U01D400\U01D401", "019a9300-0000-7000-8000-0000000000c9", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa--000000c9.json"],
	["38 a + an emoji + bb at the cut", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\U01F600bb", "019a9300-0000-7000-8000-0000000000c9", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-b--000000c9.json"],
	["Greek", "\u1F08\u03B8\u1FC6\u03BD\u03B1\u03B9", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["Greek and a digit", "\u1F08\u03B8\u1FC6\u03BD\u03B1\u03B9 2", "019a9300-0000-7000-8000-0000000000c9", "2--000000c9.json"],
	["Cyrillic", "\u041C\u043E\u0441\u043A\u0432\u0430", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["CJK", "\u65E5\u672C", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["Hangul", "\uC11C\uC6B8", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["Arabic", "\u0627\u0644\u0642\u0627\u0647\u0631\u0629", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["a mark outside U+0300-036F between letters (Arabic fatha, Mn)", "a\u064Eb", "019a9300-0000-7000-8000-0000000000c9", "a-b--000000c9.json"],
	["a supplementary mark between letters (U+1D167, Mn)", "a\U01D167b", "019a9300-0000-7000-8000-0000000000c9", "a-b--000000c9.json"],
	["emoji and a word", "\U01F409 Dragon", "019a9300-0000-7000-8000-0000000000c9", "dragon--000000c9.json"],
	["only punctuation", "!!!", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["empty", "", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["only white space", "   ", "019a9300-0000-7000-8000-0000000000c9", "019a9300-0000-7000-8000-0000000000c9.json"],
	["Windows reserved: con", "con", "019a9300-0000-7000-8000-0000000000c9", "con--000000c9.json"],
	["Windows reserved: NUL", "NUL", "019a9300-0000-7000-8000-0000000000c9", "nul--000000c9.json"],
	["trailing dot", "Mr. Smith.", "019a9300-0000-7000-8000-0000000000c9", "mr-smith--000000c9.json"],
	["Roman numeral twelve", "\u216B Legion", "019a9300-0000-7000-8000-0000000000c9", "xii-legion--000000c9.json"],
	["vulgar fraction one half", "\u00BD moon", "019a9300-0000-7000-8000-0000000000c9", "1-2-moon--000000c9.json"],
	["full-width letters", "\uFF26\uFF55\uFF4C\uFF4C", "019a9300-0000-7000-8000-0000000000c9", "full--000000c9.json"],
	["dotted capital I", "\u0130stanbul", "019a9300-0000-7000-8000-0000000000c9", "istanbul--000000c9.json"],
	["Kelvin sign", "\u212A2", "019a9300-0000-7000-8000-0000000000c9", "k2--000000c9.json"],
	["an id whose last 8 hold '--'", "x", "abcdefgh--ijk", "x--defghijk.json"],
	["an id of 8 or fewer", "x", "c-9", "x--c-9.json"],
]

static func _world() -> OWWorld:
	return OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})

static func _element_paths(files: Dictionary) -> Array:
	var out := []
	for rel: String in files:
		if rel.begins_with("elements/"):
			out.append(rel)
	out.sort()
	return out

func test_a_new_elements_file_name_is_the_typescript_packages(t) -> void:
	for r in ROWS:
		var w := _world()
		w.add_element(OWCharacter.new({"id": r[2], "name": r[1]}))
		t.eq(_element_paths(w.to_files()), ["elements/character/" + r[3]], r[0])
	t.done()

## Two new elements whose names fold to one slug and whose ids share a tail: the lower id (by code point) keeps the
## short form, the other takes its full id, whatever order they were added in (the writer collision rule, on top of the
## new name; the TypeScript package gives the same two names for these pairs).
func test_names_that_fold_alike_part_by_id(t) -> void:
	var pairs := [["Jos\u00E9", "JOSE\u0301", "jose--"], ["\u00E9cole", "Ecole", "ecole--"]]
	for p in pairs:
		var w := _world()
		w.add_element(OWCharacter.new({"id": B, "name": p[1]}))
		w.add_element(OWCharacter.new({"id": A, "name": p[0]}))
		t.eq(_element_paths(w.to_files()), ["elements/character/%s000000c9.json" % p[2], "elements/character/%s%s.json" % [p[2], B]], str(p))
	var none := _world()
	none.add_element(OWCharacter.new({"id": B, "name": "!!!"}))
	none.add_element(OWCharacter.new({"id": A, "name": ""}))
	t.eq(_element_paths(none.to_files()), ["elements/character/%s.json" % A, "elements/character/%s.json" % B], "two names with no slug: each its full id")
	t.done()

## A name with no slug names its file by the full id; when a file of the world holds that path, there is no other name to
## take, and the write is refused (nothing is written over it).
func test_a_name_with_no_slug_whose_file_is_held_is_a_refusal(t) -> void:
	var held := "elements/character/%s.json" % A
	var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer(), held: "[1, 2]\n".to_utf8_buffer()})
	w.add_element(OWCharacter.new({"id": A, "name": "\u65E5\u672C"}))
	var why := w.write_refusal()
	t.ok(why.contains(held), "the refusal names the held path: " + why)
	t.eq(w.to_files().get(held), "[1, 2]\n".to_utf8_buffer(), "to_files keeps the held file's bytes")
	t.done()

## A read element keeps the file it was read from, edited or not, whole or in place: the rule names a new element only.
## The two files here are named as this rule would never name them (the addon's earlier name for "Brother Tomás", and
## a name made by hand).
func test_a_read_element_keeps_its_file_name(t) -> void:
	var old_name := "elements/character/brother-tom-s--000000c9.json"
	var by_hand := "elements/character/My Hero.json"
	var files := {
		"world.json": WORLD,
		old_name: "{\n  \"id\": \"%s\",\n  \"name\": \"Brother Tom\u00E1s\"\n}\n" % A,
		by_hand: "{\n  \"id\": \"%s\",\n  \"name\": \"Hero\"\n}\n" % B,
	}
	var root := ProjectSettings.globalize_path(P.TMP + "/read-name")
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(String(files[rel]).to_utf8_buffer())
		f.close()
	var w := OWWorld.read_folder(root)
	t.eq(w.elements.size(), 2, "both read")
	t.eq(_element_paths(w.to_files()), [by_hand, old_name], "unedited: the names read")
	for e in w.elements:
		e.set_value("supertype", "Monk")
	t.eq(_element_paths(w.to_files(true)), [by_hand, old_name], "edited: the names read")
	t.eq(w.write_folder(root, true), OK, "write_folder edited-only, in place")
	var on_disk := Array(DirAccess.get_files_at(root + "/elements/character"))
	on_disk.sort()
	t.eq(on_disk, ["My Hero.json", "brother-tom-s--000000c9.json"], "no file beside them under the new rule's names")
	t.ok(FileAccess.get_file_as_string(root + "/" + old_name).contains("Monk"), "the edit is in the file read")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()
