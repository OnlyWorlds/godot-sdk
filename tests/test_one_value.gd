extends RefCounted
## A file's text is one JSON value and nothing after it but whitespace: an element file holding an object and then more
## is unread, whatever follows (a second object that would mark it hidden, a word, a comma). Godot's own parser holds
## this (it asks for the end of the text after the first value); these cases keep it held at every reader door.

const P = preload("res://tests/paths.gd")
const Fake := preload("res://tests/fake_transport.gd")

const ID := "019a9200-0000-7000-8000-0000000000c9"
const WORLD_ID := "019a9200-0000-7000-8000-000000000001"
const REL := "elements/character/nine--000000c9.json"

## [label, what follows the object, whether it reads].
static func _cases() -> Array:
	return [["a second object", " {\"hidden\": true}", false], ["a word", " x", false], ["a comma", ",", false],
		["two newlines and a tab", "\n\n\t", true]]

func test_one_value_and_only_whitespace_after_it(t) -> void:
	for c in _cases():
		var label: String = c[0]
		var reads: bool = c[2]
		var text := "{\"id\": \"%s\", \"name\": \"Nine\"}%s" % [ID, c[1]]
		var files := {"world.json": ("{\"id\": \"%s\", \"name\": \"W\"}" % WORLD_ID).to_utf8_buffer(), REL: text.to_utf8_buffer()}
		for source in ["folder", "owworld"]:
			var w := OWWorld.from_files(files) if source == "folder" else \
				OWWorldArchive.read(OWWorldArchive.pack_files(files, "w").bytes).to_world()
			t.eq(w.elements.size(), 1 if reads else 0, "%s, %s: read %s" % [label, source, reads])
			if not reads:
				t.ok(w.errors.size() == 1 and w.errors[0].begins_with(REL + ": not JSON"), "%s, %s: by name (%s)" % [label, source, str(w.errors)])
				t.eq(w.other_files.get(REL), files[REL], "%s, %s: its bytes kept" % [label, source])

		var wtext := "{\"id\": \"%s\", \"name\": \"W\"}%s" % [WORLD_ID, c[1]]
		t.eq(OWWorld.from_files({"world.json": wtext.to_utf8_buffer()}).get_id(), WORLD_ID if reads else "", "%s: world.json in a folder" % label)
		t.eq(OWWorldArchive.read(OWWorldArchive.pack_files({"world.json": wtext.to_utf8_buffer()}, "w").bytes).ok, reads, "%s: world.json in an .owworld" % label)

		var fake = Fake.new()
		fake.body = "{\"element_type\": \"character\", \"id\": \"%s\", \"name\": \"Nine\"}%s" % [ID, c[1]]
		var client := OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": "https://example.test/api/v2", "transport": fake})
		var r: OWClient.Reply = await client.get_element("character", "c9")
		t.eq(r.ok, reads, "%s: a client answer" % label)
	t.done()
