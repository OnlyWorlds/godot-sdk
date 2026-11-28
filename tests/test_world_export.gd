extends RefCounted
## The one-file world export an owner downloads from their world's page on onlyworlds.com
## ([code]format: onlyworlds-world-export[/code], keel's API spec section 8c). The fixture is keel's own: the emitter's
## output for one fixed world, pinned by a keel test and published in schema-dist as [code]example/world-export.json[/code],
## vendored with the dist; its sha256 is the dist's MANIFEST entry. Edge cases are inline. The Unity SDK's
## OWEnvelopeReaderTests are the sibling.

const Fake := preload("res://tests/fake_transport.gd")
const FIXTURE := "res://codegen/schema-dist/example/world-export.json"

const WORLD_ID := "01999999-0000-7000-8000-000000000420"
const KEEP := "01999999-0000-7000-8000-000000000001"
const MILL := "01999999-0000-7000-8000-000000000002"
const PIP := "01999999-0000-7000-8000-000000000003"
const MARA := "01999999-0000-7000-8000-000000000004"
const BRAVE := "01999999-0000-7000-8000-000000000005"

static func _envelope(elements: String, world := "{\"id\":\"w1\",\"name\":\"W\"}") -> String:
	return "{\"format\":\"onlyworlds-world-export\",\"world\":" + world + ",\"elements\":" + elements + "}"

static func _read(text: String, source := "") -> OWWorldExport.Result:
	return OWWorldExport.read(text.to_utf8_buffer(), source)

static func _fixture() -> OWWorldExport.Result:
	return OWWorldExport.read_file(FIXTURE)

# -- The file -----------------------------------------------------------------------------------------------------------

func test_the_fixture_is_the_dists_bytes(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(FIXTURE), manifest["example/world-export.json"], "the export's bytes are the dist's")
	t.done()

func test_the_fixture_reads_whole(t) -> void:
	var r := _fixture()
	t.ok(r.ok, "read (%s %s)" % [r.reason, r.message])
	t.eq(r.reason, "", "no reason on a read")
	t.eq(r.world_id, WORLD_ID, "the world's id")
	t.eq(r.world_name, "Fixture World", "the world's name")
	t.eq(r.format, "onlyworlds-world-export", "the format")
	t.eq(r.schema_version, "00.34.01", "the standard's version the elements follow (dist.149's file)")
	t.eq(r.exported_at, "2026-10-19T12:30:00+00:00", "when it was downloaded")

	var w := r.to_world()
	t.eq(w.elements.size(), 5, "five elements")
	t.eq(w.errors, PackedStringArray(), "nothing skipped")
	t.eq(w.of_type("character").size(), 2, "two characters")
	t.eq(w.of_type("location").size(), 2, "two locations")
	t.eq(w.of_type("trait").size(), 1, "one trait")
	t.eq(w.get_id(), WORLD_ID, "the world's info is the block")
	t.eq(w.info.name, "Fixture World", "")
	t.eq(w.root, "", "no folder")
	for e in w.elements:
		t.eq(e.to_dict()["type"], String(e.get_type()),"each body declares its own type (%s)" % e.id)

	# Keel's download says where it came from and as whom (folder spec section 4.2), and the world keeps both.
	t.eq(r.world["source"]["server"], "https://www.onlyworlds.com", "source.server")
	t.eq(r.world["source"]["world"], WORLD_ID, "source.world")
	t.eq(r.world["exported_as"]["kind"], "owner", "exported_as.kind")
	t.eq(r.world["exported_as"]["character"], null, "exported_as.character")
	# The world block is the World whole, its first import and its extension store at the top level: kept as given.
	t.eq(r.world["origin"]["producer"]["tool"], "atlas", "origin.producer.tool")
	t.eq(r.world["origin"]["source"]["world"], "01999999-0000-7000-8000-000000000419", "origin.source.world")
	t.eq(r.world["x_names"]["types"]["character"]["one"], "Villager", "x_names")
	t.eq(typeof(r.world["public_read"]), TYPE_BOOL, "public_read a bool")
	t.ok(not r.world.has("api"), "no api block: nothing to sync against")
	t.done()

func test_a_body_is_kept_whole_extensions_and_timestamps_included(t) -> void:
	var mara := _fixture().to_world().get_element(MARA)
	t.ok(mara is OWCharacter, "a Character, in its class")
	if mara == null:
		t.done()
		return
	var body := mara.to_dict()
	t.eq(body["atlas_color"], "#8b0000", "an extension field rides along")
	t.eq(body["created_at"], "2026-10-19T12:05:00+00:00", "a timestamp as written")
	t.eq(body.keys()[0], "type", "the file's key order: type first")
	t.eq(body.keys()[-1], "atlas_color", "the extension last, as the file has it")
	t.eq(mara.source_path, "", "no file inside a world: a write names it by section 3.2")
	t.ok(not mara.edited, "unedited")
	t.done()

func test_the_world_blocks_now_is_the_wires_key(t) -> void:
	# The download's world block uses the API's name for the now, time_range_current; the standard's time_current is
	# not in it, so the typed view reads null and the key is read as served.
	var r := _read(_envelope("{}", "{\"id\":\"w1\",\"name\":\"W\",\"time_range_current\":12}"))
	var w := r.to_world()
	t.eq(w.info.time_current, null, "the typed now reads null on a download")
	t.eq(w.info.get_value("time_range_current"), 12.0, "the wire's key, as given")
	t.ok(not r.world.has("time_current"), "no rename")
	t.done()

func test_an_export_is_a_frozen_cache_that_no_sync_touches(t) -> void:
	var cache := _fixture().to_cache()
	t.ok(cache.read_only, "read-only")
	t.eq(cache.world_id, WORLD_ID, "the world's id")
	t.eq(cache.world_name, "Fixture World", "the world's name")
	t.eq(cache.cursor, 0, "no cursor: a download has none")
	var fake = Fake.new()
	var client := OWClient.new({"api_key": "ow_r_test", "base_url": "https://example.test/api/v2", "transport": fake})
	var reply: OWClient.Reply = await OWSync.incremental(client, cache)
	t.ok(reply.error != null and reply.error.kind == OWApiError.REFUSED, "a sync refuses it")
	t.eq(fake.calls.size(), 0, "nothing sent")
	t.done()

func test_loads_into_a_cache_and_a_world_and_decodes(t) -> void:
	var r := _fixture()
	var cache := r.to_cache()
	var world := r.to_world()
	t.eq(cache.count(), 5, "every element held")
	for source in [cache, world]:
		var pip: OWCharacter = source.get_element(PIP)
		var mill: OWLocation = source.get_element(MILL)
		var mara: OWCharacter = source.get_element(MARA)
		t.ok(pip != null and mill != null and mara != null, "found by id")
		if pip == null or mill == null or mara == null:
			continue
		# A single link, a multi-link, and a link between two of one type.
		t.eq(pip.location, MILL, "Pip is at the Mill")
		t.eq(pip.traits, PackedStringArray([BRAVE]), "Pip is Brave")
		t.eq(mill.parent_location, KEEP, "the Mill is under the Keep")
		t.eq(mara.location, KEEP, "Mara is at the Keep")
		t.eq(pip.to_dict()["change_seq"], 4.0, "a number as Godot reads one")
	t.done()

func test_a_world_and_a_cache_from_one_read_share_nothing(t) -> void:
	var r := _fixture()
	var a := r.to_world()
	var b := r.to_world()
	var c := r.to_cache()
	a.get_element(PIP).name = "Edited"
	t.eq(b.get_element(PIP).name, "Pip", "a second world is its own")
	t.eq(c.get_element(PIP).name, "Pip", "the cache is its own")
	a.info.name = "Edited"
	t.eq(r.world["name"], "Fixture World", "the result's world block is its own")
	t.done()

func test_a_downloaded_world_writes_out_as_a_folder(t) -> void:
	var w := _fixture().to_world()
	t.eq(w.write_refusal(), "", "nothing refuses the write")
	var files := w.to_files()
	t.eq(files.size(), 6, "world.json and five element files")
	t.ok(files.has("world.json"), "world.json")
	t.ok(files.has("elements/character/mara--00000004.json"), "a section 3.2 name (%s)" % str(files.keys()))
	t.eq(OWJson.parse_bytes(files["world.json"])["exported_as"]["kind"], "owner", "the provenance lines carried as they are")
	t.done()

# -- What degrades, and what refuses -------------------------------------------------------------------------------------

func test_an_element_with_no_id_is_skipped_and_said_so(t) -> void:
	var w := _read(_envelope("{\"character\":[{\"name\":\"Nobody\"},{\"id\":\"c1\",\"name\":\"A\"}]}"), "x.json").to_world()
	t.eq(w.elements.size(), 1, "the one with an id")
	t.eq(w.errors, PackedStringArray(["x.json#elements/character/0: no id in body"]), "the skip, named")
	t.done()

func test_an_id_that_is_no_string_or_is_empty_is_no_id(t) -> void:
	var w := _read(_envelope("{\"character\":[{\"id\":7},{\"id\":\"\"},{\"id\":null},{\"id\":\"c1\"}]}")).to_world()
	t.eq(w.elements.size(), 1, "only the String id")
	t.eq(w.errors, PackedStringArray(["the export#elements/character/0: no id in body",
		"the export#elements/character/1: no id in body", "the export#elements/character/2: no id in body"]), "")
	t.done()

func test_the_bodys_type_beats_its_group_and_a_missing_one_comes_from_it(t) -> void:
	var w := _read(_envelope("{\"character\":[{\"id\":\"a\",\"type\":\"creature\"},{\"id\":\"b\"},{\"id\":\"c\",\"type\":\"Location\"}]}")).to_world()
	t.eq(w.get_element("a").get_type(), &"creature", "the body's own type")
	t.ok(w.get_element("a") is OWCreature, "in its class")
	t.eq(w.get_element("b").get_type(), &"character", "the group's, when the body declares none")
	t.eq(w.get_element("c").get_type(), &"character", "a type in another case declares nothing")
	t.done()

func test_a_group_that_is_no_type_is_not_read(t) -> void:
	var w := _read(_envelope("{\"vessel\":[{\"id\":\"v1\",\"type\":\"object\"}],\"Character\":[{\"id\":\"c1\"}],\"trait\":[{\"id\":\"t1\"}]}")).to_world()
	t.eq(w.elements.size(), 1, "only the trait")
	t.eq(w.errors.size(), 2, "two groups skipped")
	t.ok(w.errors[0].begins_with("the export#elements/vessel: not read: vessel is no type"), w.errors[0])
	t.ok(w.errors[1].begins_with("the export#elements/Character: not read: Character is no type"), w.errors[1])
	t.done()

func test_a_repeated_id_serves_the_first_and_names_the_second(t) -> void:
	var w := _read(_envelope("{\"character\":[{\"id\":\"a\",\"name\":\"First\"}],\"location\":[{\"id\":\"a\",\"name\":\"Second\"}]}")).to_world()
	t.eq(w.get_element("a").name, "First", "the first body")
	t.eq(w.errors, PackedStringArray(["the export#elements/location/0: id a is also the export#elements/character/0"]), "")
	t.eq(_read(_envelope("{\"character\":[{\"id\":\"a\"},{\"id\":\"a\"}]}")).to_cache().count(), 1, "the cache holds one")
	t.done()

func test_not_a_list_or_not_an_object_is_skipped_not_fatal(t) -> void:
	var w := _read(_envelope("{\"character\":{\"id\":\"a\"},\"event\":[7,{\"id\":\"e1\"}]}")).to_world()
	t.eq(w.elements.size(), 1, "the event")
	t.eq(w.errors, PackedStringArray(["the export#elements/character: not a list", "the export#elements/event/0: not an object"]), "")
	t.done()

func test_an_empty_world_has_no_elements_and_no_skips(t) -> void:
	for text in [_envelope("{}"), "{\"format\":\"onlyworlds-world-export\",\"world\":{\"id\":\"w1\"}}"]:
		var r := _read(text)
		t.ok(r.ok, r.message)
		t.eq(r.to_world().elements.size(), 0, "no elements")
		t.eq(r.to_world().errors, PackedStringArray(), "no skips")
		t.eq(r.to_cache().count(), 0, "an empty cache")
	t.done()

func test_unknown_keys_are_ignored(t) -> void:
	var r := _read("{\"format\":\"onlyworlds-world-export\",\"future\":{\"x\":1},\n\t\"world\":{\"id\":\"w1\",\"name\":\"W\",\"calendar\":{}},\"elements\":{}}")
	t.ok(r.ok, r.message)
	t.eq(r.world_id, "w1", "")
	t.done()

func test_the_world_block_keeps_origin_and_the_extension_store_as_given(t) -> void:
	var world := "{\"id\":\"w1\",\"name\":\"W\",\"origin\":{\"source\":null,\"producer\":{\"tool\":\"atlas\",\"version\":\"1.19.0\",\"input\":\"server\"}},\"x_names\":{\"types\":{\"character\":{\"one\":\"Villager\"}},\"version\":1},\"atlas_color\":\"#8b0000\",\"shadow_seen\":[]}"
	var r := _read(_envelope("{}", world))
	t.eq(r.world_id, "w1", "")
	t.eq(r.world, JSON.parse_string(world), "every key as the file gives it")
	t.eq(r.world.keys(), ["id", "name", "origin", "x_names", "atlas_color", "shadow_seen"], "in its order")
	t.done()

func test_the_source_names_the_file(t) -> void:
	var r := OWWorldExport.read_file(FIXTURE)
	t.eq(r.source, FIXTURE, "read_file's source is its path")
	t.eq(_read(_envelope("{}")).source, "", "read with none")
	t.done()

# Each refusal: [label, the file's text, its reason, a word its message holds].
const REFUSALS := [
	["no format", "{\"world\":{\"id\":\"w1\"},\"elements\":{}}", "not_an_export", "'missing'"],
	["another format", "{\"format\":\"onlyworlds-world\",\"world\":{\"id\":\"w1\"}}", "not_an_export", "'onlyworlds-world'"],
	["a format that is no string", "{\"format\":1,\"world\":{\"id\":\"w1\"}}", "not_an_export", "'missing'"],
	["no world", "{\"format\":\"onlyworlds-world-export\",\"elements\":{}}", "no_world_id", "world id"],
	["a world with no id", "{\"format\":\"onlyworlds-world-export\",\"world\":{\"name\":\"W\"}}", "no_world_id", "world id"],
	["a world that is a list", "{\"format\":\"onlyworlds-world-export\",\"world\":[]}", "no_world_id", "world id"],
	["a blank world id", "{\"format\":\"onlyworlds-world-export\",\"world\":{\"id\":\" \\t\"}}", "no_world_id", "world id"],
	["a number world id", "{\"format\":\"onlyworlds-world-export\",\"world\":{\"id\":7}}", "no_world_id", "world id"],
	["empty", "", "not_json", "not JSON"],
	["not json", "not json", "not_json", "not JSON"],
	["content after the value", "{\"format\":\"onlyworlds-world-export\",\"world\":{\"id\":\"w1\"}} x", "not_json", "not JSON"],
	["a list", "[1,2]", "not_an_export", "not a JSON object"],
	["a number too large for a double", "{\"format\":\"onlyworlds-world-export\",\"world\":{\"id\":\"w1\"},\"elements\":{\"character\":[{\"id\":\"c\",\"height\":1e400}]}}", "number_out_of_range", "number_out_of_range"],
]

func get_cases() -> Array:
	var out := []
	for c in REFUSALS:
		out.append(["refuses " + c[0], _refusal.bind(c[1], c[2], c[3])])
	return out

func _refusal(t, text: String, reason: String, word: String) -> void:
	var r := _read(text, "f.json")
	t.ok(not r.ok, "refused")
	t.eq(r.reason, reason, "the reason (%s)" % r.message)
	t.ok(OWWorldExport.REASONS.has(r.reason), "one of the list")
	t.ok(r.message.contains(word), "the message says %s: %s" % [word, r.message])
	t.ok(r.message.begins_with("f.json"), "the message names the file: " + r.message)
	t.eq(r.to_world(), null, "no world from a refusal")
	t.eq(r.to_cache(), null, "no cache from a refusal")
	t.done()

func test_bytes_that_are_not_utf8_are_refused(t) -> void:
	var bytes := _envelope("{\"character\":[{\"id\":\"c\",\"name\":\"X\"}]}").to_utf8_buffer()
	var at := bytes.find("X".unicode_at(0))
	bytes[at] = 0xFF
	var r := OWWorldExport.read(bytes)
	t.eq(r.reason, "not_json", r.message)
	t.ok(r.message.contains("UTF-8"), r.message)
	t.done()

func test_a_byte_order_mark_is_read_past(t) -> void:
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF])
	bytes.append_array(_envelope("{}").to_utf8_buffer())
	t.ok(OWWorldExport.read(bytes).ok, "read")
	t.done()

func test_a_file_nested_past_200_is_refused_too_deep(t) -> void:
	# The file is one JSON text and is counted whole, as the Unity SDK counts it: a body sits at level 4 (the envelope,
	# elements, its list, the body), so a body whose own nesting is 197 fits and 198 does not.
	var fits := _envelope("{\"character\":[{\"id\":\"c\",\"x_deep\":" + "[".repeat(196) + "]".repeat(196) + "}]}")
	t.ok(_read(fits).ok, "200 levels in all are read")
	var deep := _envelope("{\"character\":[{\"id\":\"c\",\"x_deep\":" + "[".repeat(197) + "]".repeat(197) + "}]}")
	var r := _read(deep)
	t.eq(r.reason, "too_deep", r.message)
	t.ok(r.message.contains(OWJson.TOO_DEEP_WORDS), r.message)
	t.done()

func test_no_file_is_not_openable(t) -> void:
	var r := OWWorldExport.read_file("user://no-such-export.json")
	t.eq(r.reason, "not_openable", r.message)
	t.ok(r.message.contains("no-such-export.json"), r.message)
	t.done()
