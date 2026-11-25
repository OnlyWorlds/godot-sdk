extends RefCounted
## A new element's slug (folder spec section 3.2, "How the slug is made"): NFKD; U+0300 to U+036F dropped and no other
## mark; lowercased; every run outside a-z and 0-9 one hyphen; hyphens at both ends dropped; cut at 40 and the new end's
## hyphens dropped. A name that leaves no slug gives the full id.
##
## The cases (tests/data/file-names.fixture.json) are the shared file-name set, held by their sha256: 38 names, each
## slug the one the TypeScript package's folder writer and the Python package's slugify both give.

const SET := "res://tests/data/file-names.fixture.json"
const SET_SHA256 := "0da1846641e116b2ff39269261779854e794db117388bd912e5aff68a243a91d"
const WORLD := "{\n  \"id\": \"019a9200-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const ID := "019a9300-0000-7000-8000-0000000000c9"

func test_the_set_is_the_shared_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(SET), SET_SHA256, "the file-name set's sha256")
	t.done()

func test_every_case_is_the_sentences_file_name(t) -> void:
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(SET))["cases"]
	t.eq(cases.size(), 38, "38 cases")
	for c in cases:
		var w := OWWorld.from_files({"world.json": WORLD.to_utf8_buffer()})
		w.add_element(OWCharacter.new({"id": ID, "name": c["element_name"]}))
		var want: String = (ID + ".json") if String(c["slug"]) == "" else (String(c["slug"]) + "--000000c9.json")
		var paths := []
		for rel: String in w.to_files():
			if rel.begins_with("elements/"):
				paths.append(rel)
		t.eq(paths, ["elements/character/" + want], String(c["name"]))
	t.done()
