extends RefCounted
## OWWorldCache: the held world OWSync fills. Ported test by test from the Unity SDK's OWWorldCacheTests, each named
## as it is there; Unity's serialization tests are round trips through the cache's own file here.

static func _cache() -> OWWorldCache:
	return OWWorldCache.new("w-1", "Test World")

static func _add(cache: OWWorldCache, id: String, type: String, name: String) -> void:
	cache.upsert(OWTypes.make(type, {"id": id, "type": type, "name": name}))

## A path in the user folder for one test's file, removed first.
static func _path(name: String) -> String:
	var path := "user://test-world-cache-%s.json" % name
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path

func test_get_by_id_returns_typed_element(t) -> void:
	var cache := _cache()
	_add(cache, "c1", "character", "Quillon")
	var c := cache.get_element("c1")
	t.ok(c is OWCharacter, "typed")
	t.eq(c.name, "Quillon", "")
	t.done()

func test_a_known_of_stub_says_so_by_id_and_on_its_typed_model(t) -> void:
	# Folder format section 4.4: a stub's unset fields read "" or null on the model, as a whole element with nothing
	# filled in would; the flag is what tells the two apart.
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "c1", "type": "character", "name": "Dev", "supertype": "Ferryman", "known_of": true}))
	_add(cache, "c2", "character", "Mara")
	cache.upsert(OWTypes.make("character", {"id": "c3", "type": "character", "name": "Oz", "known_of": false}))
	t.ok(cache.is_known_of("c1"), "")
	t.eq(cache.get_element("c1").get_value("known_of"), true, "on the model")
	t.eq(cache.get_element("c1").supertype, "Ferryman", "")
	t.ok(not cache.is_known_of("c2"), "")
	t.eq(cache.get_element("c2").get_value("known_of"), null, "")
	t.ok(not cache.is_known_of("c3"), "only true marks a stub")
	t.ok(not cache.is_known_of("nope"), "")
	t.ok(not cache.is_known_of(""), "")
	t.done()

func test_missing_id_returns_null_not_an_exception(t) -> void:
	var cache := _cache()
	t.eq(cache.get_element("nope"), null, "")
	t.eq(cache.get_element(""), null, "")
	t.ok(not cache.has("nope"), "")
	t.done()

func test_upsert_replaces_rather_than_duplicates(t) -> void:
	var cache := _cache()
	_add(cache, "c1", "character", "First")
	_add(cache, "c1", "character", "Second")
	t.eq(cache.count(), 1, "")
	t.eq(cache.get_element("c1").name, "Second", "")
	t.ok(not cache.upsert(OWTypes.make("character", {"name": "No id"})), "an element needs an id")
	t.eq(cache.count(), 1, "")
	t.done()

func test_upsert_moves_an_element_when_its_type_changes(t) -> void:
	var cache := _cache()
	_add(cache, "x1", "character", "Was a character")
	t.eq(cache.of_type("character").size(), 1, "")
	_add(cache, "x1", "location", "Now a location")
	t.eq(cache.count(), 1, "it is still one element, not two")
	t.eq(cache.of_type("character").size(), 0, "the old type lets go of it")
	t.eq(cache.of_type("location").size(), 1, "the new type picks it up")
	t.ok(cache.get_element("x1") is OWLocation, "")
	t.done()

func test_all_filters_by_type(t) -> void:
	var cache := _cache()
	_add(cache, "c1", "character", "A")
	_add(cache, "c2", "character", "B")
	_add(cache, "p1", "pin", "P")
	t.eq(cache.of_type("character").size(), 2, "")
	t.eq(cache.of_type("pin").size(), 1, "")
	t.eq(cache.of_type("location").size(), 0, "")
	t.eq(cache.elements().size(), 3, "")
	t.done()

func test_resolve_skips_dangling_links(t) -> void:
	var cache := _cache()
	_add(cache, "c1", "character", "A")
	_add(cache, "c2", "character", "B")
	t.eq(cache.resolve(["c1", "missing", "c2"]).size(), 2, "a dangling link is normal, not an error")
	t.eq(cache.resolve(PackedStringArray(["c2"])).size(), 1, "a link field's own list")
	t.eq(cache.resolve(null).size(), 0, "")
	t.done()

func test_remove_rebuilds_the_index_correctly(t) -> void:
	var cache := _cache()
	_add(cache, "c1", "character", "A")
	_add(cache, "c2", "character", "B")
	_add(cache, "c3", "character", "C")
	t.ok(cache.remove("c2"), "")
	t.ok(not cache.remove("c2"), "not held any more")
	t.eq(cache.count(), 2, "")
	t.ok(not cache.has("c2"), "")
	t.eq(cache.get_element("c1").name, "A", "")
	t.eq(cache.get_element("c3").name, "C", "")
	t.eq(cache.of_type("character").size(), 2, "")
	t.done()

func test_extension_fields_survive_caching(t) -> void:
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "c1", "name": "K", "x_atlas_pinned": true}))
	t.ok(OWJson.stringify(cache.get_element("c1").to_dict()).contains("x_atlas_pinned"), "")
	t.done()

func test_nullable_state_survives_caching(t) -> void:
	var cache := _cache()
	cache.upsert(OWTypes.make("character", JSON.parse_string("{\"id\":\"c1\",\"name\":\"K\",\"level\":0,\"charisma\":null}")))
	var path := _path("nullable")
	t.eq(cache.write_file(path), OK, "")
	var c := OWWorldCache.read_file(path).get_element("c1")
	t.eq(c.level, 0, "a deliberate zero survived")
	t.eq(c.charisma, null, "an unset field stayed unset")
	DirAccess.remove_absolute(path)
	t.done()

func test_index_rebuilds_after_deserialization(t) -> void:
	# Unity's domain reload: here the cache is written to its file and read back, and its index answers.
	var cache := _cache()
	_add(cache, "c1", "character", "A")
	_add(cache, "p1", "pin", "P")
	var path := _path("index")
	t.eq(cache.write_file(path), OK, "")
	var back := OWWorldCache.read_file(path)
	t.ok(back.has("c1"), "")
	t.ok(back.get_element("c1") is OWCharacter, "typed again")
	t.eq(back.get_element("c1").name, "A", "")
	t.eq(back.of_type("pin").size(), 1, "")
	t.eq([back.world_id, back.world_name], ["w-1", "Test World"], "")
	DirAccess.remove_absolute(path)
	t.done()

func test_read_only_flag_is_carried(t) -> void:
	var snapshot := OWWorldCache.new("w-1", "Chapter 1", true)
	t.ok(snapshot.read_only, "a frozen snapshot must say so: consumers MUST honour it")
	var path := _path("frozen")
	t.eq(snapshot.write_file(path), OK, "")
	t.ok(OWWorldCache.read_file(path).read_only, "and through the file")
	DirAccess.remove_absolute(path)
	t.done()

func test_all_raw_returns_wire_bodies_including_unmodeled_fields(t) -> void:
	var cache := _cache()
	cache.upsert(OWTypes.make("character", {"id": "c1", "name": "K", "x_atlas_pinned": true}))
	_add(cache, "c2", "character", "B")
	_add(cache, "p1", "pin", "P")
	var raw := cache.of_type("character").map(func(e): return e.to_dict())
	t.eq(raw.size(), 2, "")
	t.ok(raw.any(func(d): return d.has("x_atlas_pinned")), "the body whole, through to_dict")
	t.eq(cache.of_type("location").size(), 0, "")
	t.done()

func test_cursor_round_trips(t) -> void:
	var cache := _cache()
	cache.set_cursor(202, "", null, "2026-07-28T18:00:00Z")
	t.eq(cache.cursor, 202, "")
	t.eq(cache.synced_at, "2026-07-28T18:00:00Z", "")
	t.done()

func test_cursor_token_and_epoch_are_kept_and_a_bare_seq_drops_them(t) -> void:
	var cache := _cache()
	cache.set_cursor(202, "202:ffffffff-ffff-ffff-ffff-ffffffffffff:4", 4, "t")
	t.eq(cache.cursor_token, "202:ffffffff-ffff-ffff-ffff-ffffffffffff:4", "")
	t.eq(cache.epoch, 4, "")
	# A token beside a seq someone set by hand would resume from the wrong place.
	cache.set_cursor(150)
	t.eq(cache.cursor_token, "", "")
	t.eq(cache.epoch, null, "")
	cache.set_cursor(202, "202:x", 0, "t")
	t.eq(cache.epoch, 0, "epoch 0 is a value, not its absence")
	cache.clear()
	t.eq(cache.cursor, 0, "")
	t.eq(cache.cursor_token, "", "")
	t.eq(cache.epoch, null, "")
	t.done()

func test_cursor_token_survives_unity_serialization_and_an_old_cache_has_none(t) -> void:
	# Here: the cache's own file. A file holding only the seq reads with no token, and the sync resumes from the seq.
	var cache := _cache()
	cache.set_cursor(202, "202:abc", 4, "t")
	var path := _path("token")
	t.eq(cache.write_file(path), OK, "")
	var back := OWWorldCache.read_file(path)
	t.eq(back.cursor, 202, "an int again")
	t.eq(back.cursor_token, "202:abc", "")
	t.eq(back.epoch, 4, "an int again")
	t.eq(back.synced_at, "t", "")
	var old := FileAccess.open(path, FileAccess.WRITE)
	old.store_string("{\"format\":\"onlyworlds-godot-cache\",\"version\":1,\"cursor\":77,\"synced_at\":\"t\"}")
	old.close()
	var seq_only := OWWorldCache.read_file(path)
	t.eq(seq_only.cursor, 77, "")
	t.eq(seq_only.cursor_token, "", "no token: the sync resumes from the bare seq")
	t.eq(seq_only.epoch, null, "")
	t.eq(seq_only.count(), 0, "")
	DirAccess.remove_absolute(path)
	t.ok(OWWorldCache.read_file(path) != null and OWWorldCache.read_file(path).count() == 0, "no file: an empty cache")
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("{\"format\":\"something else\"}")
	bad.close()
	t.eq(OWWorldCache.read_file(path), null, "a file that is not a cache's: null")
	DirAccess.remove_absolute(path)
	t.done()
