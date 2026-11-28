extends RefCounted
## OWFolderExport: an account world read over the API and written as a world folder, against the onlyworlds Python
## package it follows. The expected bytes are the Unity SDK's OWFolderExportTests (Testmoor) and OWKnownOfTests, which
## are what the package's write_folder, world_for_disk and known_of_for_disk wrote for the same wire bodies; the
## provenance cases are its OWFolderExportProvenanceTests, the package's tests/test_export.py case for case. Every
## request goes through a transport that answers by route: no test touches the network.

const P = preload("res://tests/paths.gd")

const KEY := "ow_w_s3cr3tkeyvalue"
const PIN := "4242"
const BASE := "https://example.test/api/v2"
const EMPTY_PAGE := "{\"data\":[],\"has_more\":false,\"next_cursor\":null}"
## 2026-10-19T21:00:00.005Z, Testmoor's clock.
const TESTMOOR_AT := 1792443600.005
## 2026-10-19T21:30:00.250Z, the provenance cases' clock.
const MOOR_AT := 1792445400.25

## Answers each request by its route under /v2/: the world, /me, a type's pages in turn (then an empty page), one
## element by type/id, or a refusal. Records every request.
class Routes extends OWTransport:
	var calls: Array = []
	var world := "{}"
	var pages := {}
	var refusals := {}
	## Called with the route before each answer (a test fills the folder mid-walk with it).
	var on_route := Callable()

	func serve(route: String, answers: Array) -> Routes:
		pages[route] = answers.duplicate()
		return self

	func send(request: OWTransport.Request) -> OWTransport.Response:
		calls.append(request)
		var path := request.url.get_slice("?", 0)
		var route := path.substr(path.find("/v2/") + 4).trim_suffix("/")
		if on_route.is_valid():
			on_route.call(route)
		var r := OWTransport.Response.new()
		if refusals.has(route):
			r.status = refusals[route][0]
			r.body = refusals[route][1]
			return r
		r.status = 200
		if route == "world":
			r.body = world
		elif pages.has(route) and not pages[route].is_empty():
			r.body = pages[route].pop_front()
		else:
			r.body = EMPTY_PAGE
		return r

	func routes() -> PackedStringArray:
		var out := PackedStringArray()
		for c: OWTransport.Request in calls:
			out.append(c.url.get_slice("?", 0).trim_prefix(BASE))
		return out

static func _page(bodies: Array, more := false, next: Variant = null) -> String:
	return "{\"data\":[" + ",".join(bodies) + "],\"has_more\":" + ("true" if more else "false") + ",\"next_cursor\":" \
		+ ("null" if next == null else "\"" + next + "\"") + "}"

static func _client(t: Routes, key := KEY, pin := PIN, world := "", base := BASE) -> OWClient:
	var config := {"api_key": key, "api_pin": pin, "base_url": base, "transport": t}
	if world != "":
		config["world"] = world
	return OWClient.new(config)

## A fresh parent folder for one test, and the world folder inside it (not made).
static func _parent() -> String:
	var parent := ProjectSettings.globalize_path(P.TMP + "/folder-export")
	P.remove_tree(parent)
	DirAccess.make_dir_recursive_absolute(parent)
	return parent

static func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

static func _keys(d: Dictionary) -> Array:
	return d.keys()

## Everything in a folder, hidden entries too, sorted.
static func _entries(path: String) -> Array:
	var d := DirAccess.open(path)
	if d == null:
		return []
	d.include_hidden = true
	var out := Array(d.get_files()) + Array(d.get_directories())
	out.sort()
	return out

static func _world_json(folder: String) -> Dictionary:
	return JSON.parse_string(_text(folder + "/world.json"))

static func _export(client: OWClient, folder: String, options := {}) -> OWFolderExport.Report:
	return await OWFolderExport.export(client, folder, options)

# -- world_for_disk: the package's world_for_disk, case for case ---------------------------------------------------------

func test_world_for_disk_renames_the_now_in_place_and_stamps_the_version_last(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string("{\"id\":\"w\",\"name\":\"n\",\"time_range_current\":3,\"x\":1}"))
	# package: {'id': 'w', 'name': 'n', 'time_current': 3, 'x': 1, 'format_version': '0.3.25'}
	t.eq(_keys(disk), ["id", "name", "time_current", "x", "format_version"], "the now renamed in place, the version last")
	t.eq(disk["time_current"], 3.0, "")
	t.eq(disk["format_version"], "0.3.25", "")
	t.done()

func test_world_for_disk_keeps_both_spellings_when_both_come(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string(
		"{\"id\":\"w\",\"name\":\"\",\"time_range_current\":3,\"time_current\":4}"))
	t.eq(_keys(disk), ["id", "name", "time_range_current", "time_current", "format_version"], "both kept")
	t.eq(disk["time_range_current"], 3.0, "")
	t.eq(disk["time_current"], 4.0, "")
	t.done()

func test_world_for_disk_keeps_a_carried_format_version_even_null(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string("{\"id\":\"w\",\"name\":\"n\",\"format_version\":null}"))
	t.ok(disk.has("format_version") and disk["format_version"] == null, "a null version is kept")
	t.done()

func test_world_for_disk_drops_snapshot_counts_without_snapshot_of(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string(
		"{\"id\":\"w\",\"name\":\"n\",\"snapshot_counts\":{\"a\":1}}"), {"character": 2})
	t.ok(not disk.has("snapshot_counts"), "a count belongs to a snapshot alone")
	t.done()

func test_world_for_disk_recounts_a_snapshots_counts_in_place_zeros_left_out(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string(
		"{\"id\":\"w\",\"name\":\"n\",\"snapshot_of\":\"o\",\"snapshot_counts\":{\"a\":9}}"), {"character": 2, "map": 0})
	t.eq(_keys(disk), ["id", "name", "snapshot_of", "snapshot_counts", "format_version"], "")
	t.eq(disk["snapshot_counts"], {"character": 2}, "recounted from what was written")
	t.done()

func test_world_for_disk_drops_a_snapshots_counts_when_none_are_given(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string(
		"{\"id\":\"w\",\"name\":\"n\",\"snapshot_of\":\"o\",\"snapshot_counts\":{\"a\":9}}"))
	t.ok(not disk.has("snapshot_counts"), "")
	t.done()

func test_world_for_disk_leaves_its_input_alone(t) -> void:
	var wire: Dictionary = JSON.parse_string("{\"id\":\"w\",\"name\":\"n\",\"time_range_current\":3,\"x\":{\"deep\":[1]}}")
	var before := JSON.stringify(wire)
	var disk: Dictionary = OWFolderExport.world_for_disk(wire)
	(disk["x"]["deep"] as Array).append(2)
	t.eq(JSON.stringify(wire), before, "the wire body is not changed")
	t.done()

func test_world_for_disk_refuses_a_world_without_its_two_required_keys(t) -> void:
	for wire in ["{\"name\":\"n\"}", "{\"id\":\"\",\"name\":\"n\"}", "{\"id\":7,\"name\":\"n\"}", "{\"id\":\"w\"}",
			"{\"id\":\"w\",\"name\":null}"]:
		var body: Dictionary = JSON.parse_string(wire)
		t.eq(OWFolderExport.world_for_disk(body), null, wire)
		t.ok(OWFolderExport.world_refusal(body).begins_with("world.json requires"), wire)
	t.done()

const FIRST_IMPORT := "{\"source\":{\"server\":\"https://www.onlyworlds.com\",\"world\":\"w0\",\"at\":\"2026-10-01T09:00:00Z\"},\"producer\":{\"tool\":\"atlas\",\"version\":\"1.82.0\",\"input\":\"bare\"}}"
const THIS_FOLDERS_SOURCE := "{\"server\":\"https://www.onlyworlds.com\",\"world\":\"w\",\"at\":\"2026-10-19T21:00:00Z\"}"

func test_world_for_disk_carries_origin_as_given_beside_the_folders_own_source(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string(
		"{\"id\":\"w\",\"name\":\"n\",\"origin\":" + FIRST_IMPORT + ",\"source\":" + THIS_FOLDERS_SOURCE + "}"))
	t.eq(_keys(disk), ["id", "name", "origin", "source", "format_version"], "")
	t.eq(disk["origin"], JSON.parse_string(FIRST_IMPORT), "the first import, as given")
	t.eq(disk["source"], JSON.parse_string(THIS_FOLDERS_SOURCE), "beside this folder's own line")
	t.done()

func test_world_for_disk_derives_no_origin_from_source_or_producer(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string("{\"id\":\"w\",\"name\":\"n\",\"source\":"
		+ THIS_FOLDERS_SOURCE + ",\"producer\":{\"tool\":\"atlas\",\"version\":\"1.82.0\",\"input\":\"bare\"}}"))
	t.eq(_keys(disk), ["id", "name", "source", "producer", "format_version"], "no origin made up")
	t.done()

func test_world_for_disk_keeps_the_worlds_extension_keys_and_an_origin_of_nulls(t) -> void:
	var disk: Dictionary = OWFolderExport.world_for_disk(JSON.parse_string("{\"id\":\"w\",\"name\":\"n\","
		+ "\"origin\":{\"source\":null,\"producer\":null},\"x_names\":{\"version\":1},\"atlas_c\":1,\"shadow_s\":[1]}"))
	t.eq(_keys(disk), ["id", "name", "origin", "x_names", "atlas_c", "shadow_s", "format_version"], "")
	t.eq(OWJson.stringify(disk["origin"]), "{\n  \"source\": null,\n  \"producer\": null\n}\n", "an origin of nulls is a served value")
	t.done()

# -- The folder, in the package's bytes ----------------------------------------------------------------------------------

const WIRE_WORLD := "{\"id\":\"0695db52-0000-7000-8000-000000000001\",\"name\":\"Testmoor\",\"description\":\"A moor, Jos\\u00e9's.\",\"time_range_min\":0,\"time_range_current\":453,\"length_unit\":\"\",\"public_read\":true,\"owner_character\":null,\"created_at\":\"2026-01-07T01:21:41.262478+00:00\",\"updated_at\":\"2026-10-11T11:53:28.489198+00:00\"}"
const WIRE_CHARACTER := "{\"id\":\"01a1206b-0000-7000-8000-00000000c001\",\"type\":\"character\",\"name\":\"Ann \\u00c1\",\"level\":2.50,\"weight\":1.0,\"big\":1e21,\"tiny\":0.000001,\"tags\":[],\"x_tool\":{\"b\":1,\"a\":[]},\"location\":null,\"created_at\":\"2026-01-07T01:21:41.262478+00:00\"}"
const WIRE_MAP := "{\"id\":\"069620b8-0000-7000-8000-00000000a001\",\"type\":\"map\",\"name\":\"The Moor\",\"image_url\":\"https://media.example.test/w/maps/the%20moor.webp?v=2\"}"

static func _testmoor() -> Routes:
	var t := Routes.new()
	t.world = WIRE_WORLD
	return t.serve("character", [_page([WIRE_CHARACTER])]).serve("map", [_page([WIRE_MAP])])

static func _pinned() -> Dictionary:
	return {"clock": func(): return TESTMOOR_AT}

func test_export_writes_the_packages_bytes(t) -> void:
	var parent := _parent()
	var folder := parent + "/world"
	var report := await _export(_client(_testmoor()), folder, _pinned())
	t.ok(report.ok, report.message)

	t.eq(_text(folder + "/world.json"),
		"{\n  \"id\": \"0695db52-0000-7000-8000-000000000001\",\n  \"name\": \"Testmoor\",\n"
		+ "  \"description\": \"A moor, Jos\u00e9's.\",\n  \"time_range_min\": 0,\n  \"time_current\": 453,\n"
		+ "  \"length_unit\": \"\",\n  \"public_read\": true,\n  \"owner_character\": null,\n"
		+ "  \"created_at\": \"2026-01-07T01:21:41.262478+00:00\",\n"
		+ "  \"updated_at\": \"2026-10-11T11:53:28.489198+00:00\",\n"
		+ "  \"source\": {\n    \"server\": \"https://example.test\",\n"
		+ "    \"world\": \"0695db52-0000-7000-8000-000000000001\",\n    \"at\": \"2026-10-19T21:00:00.005Z\"\n  },\n"
		+ "  \"producer\": {\n    \"tool\": \"onlyworlds-godot\",\n    \"version\": \"" + OWFolderExport.PRODUCER_VERSION + "\",\n"
		+ "    \"input\": \"server\"\n  },\n"
		+ "  \"format_version\": \"0.3.25\"\n}\n", "world.json")
	t.eq(_text(folder + "/elements/character/ann-a--0000c001.json"),
		"{\n  \"id\": \"01a1206b-0000-7000-8000-00000000c001\",\n  \"type\": \"character\",\n"
		+ "  \"name\": \"Ann \u00c1\",\n  \"level\": 2.5,\n  \"weight\": 1,\n  \"big\": 1e+21,\n  \"tiny\": 0.000001,\n"
		+ "  \"tags\": [],\n  \"x_tool\": {\n    \"b\": 1,\n    \"a\": []\n  },\n  \"location\": null,\n"
		+ "  \"created_at\": \"2026-01-07T01:21:41.262478+00:00\"\n}\n", "the character")
	t.eq(_text(folder + "/elements/map/the-moor--0000a001.json"),
		"{\n  \"id\": \"069620b8-0000-7000-8000-00000000a001\",\n  \"type\": \"map\",\n  \"name\": \"The Moor\",\n"
		+ "  \"image_url\": \"https://media.example.test/w/maps/the%20moor.webp?v=2\"\n}\n", "the map")

	# No BOM, and nothing else in the tree: two type folders, no media, no temp beside it.
	t.eq(FileAccess.get_file_as_bytes(folder + "/world.json")[0], 0x7B, "no byte order mark")
	t.eq(_entries(folder), ["elements", "world.json"], "world.json and elements/ only")
	t.eq(_entries(folder + "/elements"), ["character", "map"], "a folder per type with elements")
	t.eq(_entries(parent), ["world"], "no temp left beside it")
	t.done()

func test_export_keeps_the_served_trimmed_mark_as_served_and_the_folder_reads_it_back(t) -> void:
	var folder := _parent() + "/world"
	var trimmed := "{\"id\":\"019a3b10-0000-7000-8000-000000000c01\",\"type\":\"narrative\",\"name\":\"Hello\",\"supertype\":\"Message\",\"narrator\":null,\"characters\":[],\"x_served_trimmed\":[\"characters\",\"narrator\"]}"
	var report := await _export(_client(_testmoor().serve("narrative", [_page([trimmed])])), folder)
	t.ok(report.ok, report.message)
	var file := _text(folder + "/elements/narrative/hello--00000c01.json")
	t.ok(file.contains("  \"x_served_trimmed\": [\n    \"characters\",\n    \"narrator\"\n  ]\n"), "kept as served: " + file)
	var body := OWWorld.read_folder(folder).of_type("narrative")[0].to_dict()
	t.eq(body["x_served_trimmed"], ["characters", "narrator"], "read back")
	t.eq(OWMessage.has_unseen_recipients(body), true, "a field the mark names reads as trimmed, never as empty")
	t.done()

func test_export_keeps_the_served_doors_on_a_whole_element_and_on_a_stub_that_holds_them(t) -> void:
	var folder := _parent() + "/world"
	var whole := "{\"id\":\"01a1206b-0000-7000-8000-00000000c003\",\"type\":\"character\",\"name\":\"Cy\",\"changed_via\":\"mcp\",\"changed_client\":\"atlas\",\"doors\":{\"atlas\":\"2026-10-29T10:00:00+00:00\",\"mcp\":\"2026-10-28T09:00:00+00:00\"}}"
	var stub := "{\"id\":\"01a1206b-0000-7000-8000-00000000c004\",\"type\":\"character\",\"name\":\"Di\",\"known_of\":true,\"doors\":{\"atlas\":\"2026-10-29T10:00:00+00:00\"},\"physicality\":\"\"}"
	var report := await _export(_client(_testmoor().serve("character", [_page([whole, stub])])), folder)
	t.ok(report.ok, report.message)
	var doors := "  \"doors\": {\n    \"atlas\": \"2026-10-29T10:00:00+00:00\",\n"
	t.ok(_text(folder + "/elements/character/cy--0000c003.json").contains(doors + "    \"mcp\": \"2026-10-28T09:00:00+00:00\"\n  }\n"), "the whole element's doors")
	var stub_file := _text(folder + "/elements/character/di--0000c004.json")
	t.ok(stub_file.contains("  \"doors\": {\n    \"atlas\": \"2026-10-29T10:00:00+00:00\"\n  },\n  \"known_of\": true\n}\n"), "the stub's: " + stub_file)
	t.ok(not stub_file.contains("physicality"), "a stub's unset field is left out")
	t.done()

func test_export_reports_what_it_wrote(t) -> void:
	var folder := _parent() + "/world"
	var report := await _export(_client(_testmoor()), folder)
	t.ok(report.ok, report.message)
	t.eq(report.message, "", "no message on a write")
	t.eq(report.folder, folder, "the folder, absolute")
	t.eq(report.world_id, "0695db52-0000-7000-8000-000000000001", "")
	t.eq(report.world_name, "Testmoor", "")
	t.eq(report.counts, {"character": 1, "map": 1}, "types with none left out")
	t.eq(report.total(), 2, "")
	t.done()

func test_export_reads_all_22_types_with_gets_only(t) -> void:
	var transport := _testmoor()
	var report := await _export(_client(transport), _parent() + "/world")
	t.ok(report.ok, report.message)
	t.ok(transport.calls.all(func(c): return c.method == "GET"), "GETs only")
	var want := PackedStringArray(["/world/", "/me/"])
	for type in OWTypes.slugs():
		want.append("/%s/" % type)
	t.eq(transport.routes(), want, "the world, who the key is, then the 22 types in the standard's order")
	t.done()

func test_export_tells_its_progress_after_each_type(t) -> void:
	var told := []
	var report := await _export(_client(_testmoor()), _parent() + "/world",
		{"on_progress": func(type, done, total): told.append([type, done, total])})
	t.ok(report.ok, report.message)
	t.eq(told.size(), 22, "once per type")
	t.eq(told[0], ["ability", 1, 22], "")
	t.eq(told[21], ["zone", 22, 22], "")
	t.done()

func test_export_refuses_an_option_it_does_not_know(t) -> void:
	var transport := _testmoor()
	var report := await _export(_client(transport), _parent() + "/world", {"media": true})
	t.ok(not report.ok, "refused")
	t.ok(report.message.contains("'media' is not an option"), report.message)
	t.eq(transport.calls.size(), 0, "nothing read")
	t.done()

func test_export_collision_rule_id_ascending_case_folded_whatever_the_order(t) -> void:
	# Arrival order is the reverse of id order, so a writer that settles by arrival names them wrong.
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [_page([
		"{\"id\":\"44444444-0000-7000-8000-000000000002\",\"name\":\"\u682a\u5f0f\"}",
		"{\"id\":\"33333333-0000-7000-8000-000000000001\"}",
		"{\"id\":\"22222222-0000-7000-8000-00000000ABCD\",\"name\":\"ann\"}",
		"{\"id\":\"11111111-0000-7000-8000-00000000abcd\",\"name\":\"Ann\"}",
		"{\"id\":\"00000000-0000-7000-8000-00000000abcd\",\"name\":\"Ann\"}"])])
	var folder := _parent() + "/world"
	var report := await _export(_client(transport), folder)
	t.ok(report.ok, report.message)
	# package resolve_filenames, the same five:
	t.eq(_entries(folder + "/elements/character"), [
		"33333333-0000-7000-8000-000000000001.json",
		"44444444-0000-7000-8000-000000000002.json",
		"ann--0000abcd.json",
		"ann--11111111-0000-7000-8000-00000000abcd.json",
		"ann--22222222-0000-7000-8000-00000000ABCD.json"], "the lowest id keeps the short name")
	t.eq(JSON.parse_string(_text(folder + "/elements/character/ann--0000abcd.json"))["id"], "00000000-0000-7000-8000-00000000abcd", "")
	t.done()

func test_export_collision_rule_by_code_point_above_the_basic_plane(t) -> void:
	# U+1F600 sorts below U+E000 by UTF-16 units and above it by code point: the private-use id is the lowest, and
	# arrives second.
	var astral := String.chr(0x1F600) + "-0000-7000-8000-00000000abcd"
	var private_use := String.chr(0xE000) + "-0000-7000-8000-00000000abcd"
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [_page([JSON.stringify({"id": astral, "name": "Ann"}), JSON.stringify({"id": private_use, "name": "Ann"})])])
	var folder := _parent() + "/world"
	var report := await _export(_client(transport), folder)
	t.ok(report.ok, report.message)
	t.eq(JSON.parse_string(_text(folder + "/elements/character/ann--0000abcd.json"))["id"], private_use, "by code point")
	t.ok(FileAccess.file_exists(folder + "/elements/character/ann--" + astral + ".json"), "the other takes its full id")
	t.done()

func test_export_an_id_served_twice_keeps_its_last_body(t) -> void:
	# A page walk that met a write serves the element again on a later page, newer.
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [
		_page(["{\"id\":\"a-1\",\"name\":\"Old\"}", "{\"id\":\"b-2\",\"name\":\"Bea\"}"], true, "c2"),
		_page(["{\"id\":\"a-1\",\"name\":\"New\"}"])])
	var folder := _parent() + "/world"
	var report := await _export(_client(transport), folder)
	t.ok(report.ok, report.message)
	t.eq(_entries(folder + "/elements/character"), ["bea--b-2.json", "new--a-1.json"], "the later copy, once")
	t.eq(report.counts["character"], 2, "")
	t.done()

func test_export_a_stub_that_later_arrives_whole_is_written_whole(t) -> void:
	var transport := Routes.new()
	transport.world = WORLD_W
	transport.serve("character", [_page([STUB_DEV], true, "c2"), _page([WHOLE_DEV])])
	var folder := _parent() + "/world"
	var report := await _export(_client(transport), folder)
	t.ok(report.ok, report.message)
	t.eq(_text(folder + "/elements/character/dev--0000000d.json"), WHOLE_DEV_ON_DISK, "whole, and known_of gone")
	t.done()

func test_export_refuses_one_id_under_two_types_and_leaves_nothing(t) -> void:
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [_page(["{\"id\":\"same\",\"name\":\"A\"}"])]).serve("location", [_page(["{\"id\":\"same\",\"name\":\"B\"}"])])
	var parent := _parent()
	var report := await _export(_client(transport), parent + "/world")
	t.ok(not report.ok, "refused")
	t.eq(report.message, "Element id same came back under both character and location; nothing was written.", "")
	t.eq(report.counts, {}, "no counts on a refusal")
	t.eq(_entries(parent), [], "nothing left")
	t.done()

func test_export_refuses_an_element_without_an_id(t) -> void:
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [_page(["{\"name\":\"Nobody\"}"])])
	var parent := _parent()
	var report := await _export(_client(transport), parent + "/world")
	t.ok(not report.ok, "refused")
	t.eq(report.message, "A character element came back without a non-empty string id; nothing was written.", "")
	t.eq(_entries(parent), [], "nothing left")
	t.done()

func test_export_refuses_an_id_that_cannot_be_a_file_name_and_writes_nothing(t) -> void:
	var transport := Routes.new()
	transport.world = "{\"id\":\"w\",\"name\":\"n\"}"
	transport.serve("character", [_page(["{\"id\":\"c-1\",\"name\":\"Fine\"}", "{\"id\":\"../x\",\"name\":\"\"}"])])
	var parent := _parent()
	var report := await _export(_client(transport), parent + "/box/world")
	t.ok(not report.ok, "refused")
	t.eq(report.message, "character element id \"../x\" cannot be a file name: it holds a path separator, / or \\. Nothing was written.", "the writer's words")
	t.eq(_entries(parent), [], "nothing written, inside the folder or beside it")
	t.done()

# -- A folder's birth --------------------------------------------------------------------------------------------------

func test_export_refuses_a_folder_that_holds_anything_and_touches_it_not(t) -> void:
	var parent := _parent()
	var folder := parent + "/world"
	DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open(folder + "/notes.txt", FileAccess.WRITE)
	f.store_string("mine")
	f.close()
	var transport := _testmoor()
	var report := await _export(_client(transport), folder)
	t.ok(not report.ok, "refused")
	t.eq(report.message, "'%s' exists and is not an empty directory; a world folder is written whole, once. Nothing was read." % folder, "")
	t.eq(transport.calls.size(), 0, "refused before the first read")
	t.eq(_entries(folder), ["notes.txt"], "the folder as it was")
	t.eq(_entries(parent), ["world"], "no temp beside it")
	t.done()

func test_export_refuses_a_folder_holding_only_a_hidden_file(t) -> void:
	var folder := _parent() + "/world"
	DirAccess.make_dir_recursive_absolute(folder + "/.git")
	var report := await _export(_client(_testmoor()), folder)
	t.ok(not report.ok, "a dot-folder is something")
	t.eq(_entries(folder), [".git"], "")
	t.done()

func test_export_refuses_a_path_that_is_a_file(t) -> void:
	var folder := _parent() + "/world"
	var f := FileAccess.open(folder, FileAccess.WRITE)
	f.store_string("a file")
	f.close()
	var report := await _export(_client(_testmoor()), folder)
	t.ok(not report.ok, "refused")
	t.eq(_text(folder), "a file", "the file as it was")
	t.done()

func test_export_into_an_empty_directory_works(t) -> void:
	var parent := _parent()
	DirAccess.make_dir_recursive_absolute(parent + "/world")
	var report := await _export(_client(_testmoor()), parent + "/world")
	t.ok(report.ok, report.message)
	t.ok(FileAccess.file_exists(parent + "/world/world.json"), "")
	t.eq(_entries(parent), ["world"], "")
	t.done()

func test_export_into_a_folder_whose_parent_is_missing_makes_the_parent(t) -> void:
	var parent := _parent()
	var report := await _export(_client(_testmoor()), parent + "/a/b/world")
	t.ok(report.ok, report.message)
	t.ok(FileAccess.file_exists(parent + "/a/b/world/world.json"), "")
	t.eq(_entries(parent + "/a/b"), ["world"], "no temp beside it")
	t.done()

func test_export_takes_a_user_path(t) -> void:
	_parent()
	var report := await _export(_client(_testmoor()), P.TMP + "/folder-export/world/")
	t.ok(report.ok, report.message)
	t.eq(report.folder, ProjectSettings.globalize_path(P.TMP + "/folder-export/world"), "absolute, no trailing slash")
	t.ok(FileAccess.file_exists(report.folder + "/world.json"), "")
	t.done()

func test_export_a_world_that_cannot_be_written_leaves_nothing(t) -> void:
	var transport := _testmoor()
	transport.world = "{\"name\":\"no id\"}"
	var parent := _parent()
	var report := await _export(_client(transport), parent + "/world")
	t.ok(not report.ok, "refused")
	t.eq(report.message, "world.json requires a non-empty string id (folder spec section 4.1); nothing was written.", "")
	t.eq(_entries(parent), [], "nothing left")
	t.done()

func test_export_a_folder_filled_while_the_world_was_read_is_left_alone_and_the_build_removed(t) -> void:
	# The cleanup on an error after the build: the folder is checked again before the move.
	var parent := _parent()
	var folder := parent + "/world"
	var transport := _testmoor()
	transport.on_route = func(route):
		if route == "zone":
			DirAccess.make_dir_recursive_absolute(folder)
			var f := FileAccess.open(folder + "/someone-elses.txt", FileAccess.WRITE)
			f.store_string("theirs")
			f.close()
	var report := await _export(_client(transport), folder)
	t.ok(not report.ok, "refused at the move")
	t.ok(report.message.ends_with("a world folder is written whole, once. Nothing was written."), report.message)
	t.eq(_entries(parent), ["world"], "the build beside it is gone")
	t.eq(_entries(folder), ["someone-elses.txt"], "the folder as its other writer left it")
	t.done()

# -- Errors and secrets --------------------------------------------------------------------------------------------------

func test_export_a_refused_read_answers_the_clients_error_with_no_key_or_pin(t) -> void:
	var transport := _testmoor()
	transport.refusals["location"] = [401, "{\"error\":{\"type\":\"authentication_error\",\"code\":\"invalid_credentials\",\"message\":\"Invalid API key or PIN.\"}}"]
	var parent := _parent()
	var report := await _export(_client(transport), parent + "/world")
	t.ok(not report.ok, "refused")
	t.ok(report.error != null and report.error.is_auth_error(), "the client's error, an auth error")
	t.ok(not report.message.contains(KEY) and not report.message.contains(PIN), "no key or PIN in the words: " + report.message)
	t.ok(not str(report.error).contains(KEY), "")
	t.eq(_entries(parent), [], "nothing left")
	t.done()

func test_export_no_file_carries_the_key_or_the_pin(t) -> void:
	var parent := _parent()
	var report := await _export(_client(_testmoor()), parent + "/world")
	t.ok(report.ok, report.message)
	var files := ["world/world.json", "world/elements/character/ann-a--0000c001.json", "world/elements/map/the-moor--0000a001.json"]
	for rel in files:
		var text := _text(parent + "/" + rel)
		t.ok(text != "" and not text.contains(KEY) and not text.contains(PIN), rel)
	t.done()

# -- Known-of stubs: the package's known_of_for_disk -------------------------------------------------------------------

const WORLD_W := "{\"id\":\"w0000000-0000-7000-8000-000000000000\",\"name\":\"W\"}"
const WHOLE_DEV := "{\"id\":\"c0000000-0000-7000-8000-00000000000d\",\"type\":\"character\",\"name\":\"Dev\",\"description\":\"Dev desc\",\"supertype\":\"Ferryman\",\"subtype\":\"\",\"image_url\":null,\"physicality\":\"zzphys\",\"location\":\"l1\",\"friends\":[\"c0000000-0000-7000-8000-00000000000a\"],\"STR\":14,\"created_at\":\"2026-10-20T00:00:00Z\",\"updated_at\":\"2026-10-20T01:00:00Z\",\"change_seq\":9,\"created_by\":\"m-1\",\"changed_by\":\"m-1\",\"changed_via\":\"api\",\"x_secret\":\"zzext\"}"
const STUB_DEV := "{\"id\":\"c0000000-0000-7000-8000-00000000000d\",\"type\":\"character\",\"name\":\"Dev\",\"description\":\"Dev desc\",\"supertype\":\"Ferryman\",\"subtype\":\"\",\"image_url\":null,\"physicality\":\"\",\"location\":null,\"friends\":[],\"STR\":null,\"created_at\":\"2026-10-20T00:00:00Z\",\"updated_at\":\"2026-10-20T01:00:00Z\",\"change_seq\":9,\"created_by\":null,\"changed_by\":null,\"changed_via\":null,\"known_of\":true}"
## Dev as keel serves him since PR 117: the public fields in their wire place.
const PUBLIC_STUB_DEV := "{\"id\":\"c0000000-0000-7000-8000-00000000000d\",\"type\":\"character\",\"name\":\"Dev\",\"description\":\"Dev desc\",\"supertype\":\"Ferryman\",\"subtype\":\"\",\"image_url\":null,\"physicality\":\"Tall\",\"location\":null,\"friends\":[],\"STR\":null,\"created_at\":\"2026-10-20T00:00:00Z\",\"updated_at\":\"2026-10-20T01:00:00Z\",\"change_seq\":9,\"created_by\":null,\"changed_by\":null,\"changed_via\":null,\"height\":180,\"weight\":null,\"species\":[\"s0000000-0000-7000-8000-000000000001\"],\"reputation\":\"\",\"known_of\":true}"
const STUB_DEV_ON_DISK := "{\n  \"id\": \"c0000000-0000-7000-8000-00000000000d\",\n  \"type\": \"character\",\n  \"name\": \"Dev\",\n  \"description\": \"Dev desc\",\n  \"supertype\": \"Ferryman\",\n  \"subtype\": \"\",\n  \"image_url\": null,\n  \"created_at\": \"2026-10-20T00:00:00Z\",\n  \"updated_at\": \"2026-10-20T01:00:00Z\",\n  \"change_seq\": 9,\n  \"known_of\": true\n}\n"
const PUBLIC_STUB_DEV_ON_DISK := "{\n  \"id\": \"c0000000-0000-7000-8000-00000000000d\",\n  \"type\": \"character\",\n  \"name\": \"Dev\",\n  \"description\": \"Dev desc\",\n  \"supertype\": \"Ferryman\",\n  \"subtype\": \"\",\n  \"image_url\": null,\n  \"physicality\": \"Tall\",\n  \"created_at\": \"2026-10-20T00:00:00Z\",\n  \"updated_at\": \"2026-10-20T01:00:00Z\",\n  \"change_seq\": 9,\n  \"height\": 180,\n  \"species\": [\n    \"s0000000-0000-7000-8000-000000000001\"\n  ],\n  \"known_of\": true\n}\n"
const WHOLE_DEV_ON_DISK := "{\n  \"id\": \"c0000000-0000-7000-8000-00000000000d\",\n  \"type\": \"character\",\n  \"name\": \"Dev\",\n  \"description\": \"Dev desc\",\n  \"supertype\": \"Ferryman\",\n  \"subtype\": \"\",\n  \"image_url\": null,\n  \"physicality\": \"zzphys\",\n  \"location\": \"l1\",\n  \"friends\": [\n    \"c0000000-0000-7000-8000-00000000000a\"\n  ],\n  \"STR\": 14,\n  \"created_at\": \"2026-10-20T00:00:00Z\",\n  \"updated_at\": \"2026-10-20T01:00:00Z\",\n  \"change_seq\": 9,\n  \"created_by\": \"m-1\",\n  \"changed_by\": \"m-1\",\n  \"changed_via\": \"api\",\n  \"x_secret\": \"zzext\"\n}\n"

func test_export_writes_a_stub_without_its_unset_fields_and_a_whole_element_as_served(t) -> void:
	var transport := Routes.new()
	transport.world = WORLD_W
	var mara := "{\"id\":\"c0000000-0000-7000-8000-00000000000a\",\"type\":\"character\",\"name\":\"Mara\",\"description\":\"\",\"friends\":[\"c0000000-0000-7000-8000-00000000000d\"]}"
	transport.serve("character", [_page([STUB_DEV, mara])])
	var folder := _parent() + "/world"
	var report := await _export(_client(transport), folder)
	t.ok(report.ok, report.message)
	t.eq(_text(folder + "/elements/character/dev--0000000d.json"), STUB_DEV_ON_DISK, "the package's known_of_for_disk bytes")
	t.eq(JSON.parse_string(_text(folder + "/elements/character/mara--0000000a.json")), JSON.parse_string(mara), "a whole element as served")
	t.done()

func test_known_of_for_disk_keeps_a_stubs_public_fields_in_their_wire_place(t) -> void:
	t.eq(OWJson.stringify(OWFolderExport.known_of_for_disk(JSON.parse_string(PUBLIC_STUB_DEV))), PUBLIC_STUB_DEV_ON_DISK, "")
	t.done()

func test_known_of_for_disk_keeps_zero_and_false_and_leaves_its_input_alone(t) -> void:
	var stub: Dictionary = JSON.parse_string("{\"id\":\"c1\",\"name\":\"\",\"level\":0,\"dead\":false,\"tags\":[],\"x\":{\"a\":[1]},\"known_of\":true}")
	var before := JSON.stringify(stub)
	var disk := OWFolderExport.known_of_for_disk(stub)
	t.eq(_keys(disk), ["id", "name", "level", "dead", "x", "known_of"], "a kept key even empty, 0 and false are values")
	(disk["x"]["a"] as Array).append(2)
	t.eq(JSON.stringify(stub), before, "the input is not changed")
	t.ok(OWFolderExport.is_known_of(stub), "")
	t.ok(not OWFolderExport.is_known_of({"known_of": 1}), "only the JSON true marks a stub")
	t.ok(not OWFolderExport.is_known_of({"known_of": "true"}), "")
	t.eq(OWFolderExport.KNOWN_OF_KEEPS, ["id", "type", "name", "description", "supertype", "subtype", "image_url", "created_at", "updated_at", "change_seq"], "keel's KNOWN_OF_BASE")
	t.done()

# -- Provenance: source, exported_as, producer, origin (the package's tests/test_export.py) ------------------------------

const MOOR := "{\"id\":\"w-1\",\"name\":\"Moor\"}"

static func _moor(me: Variant = null) -> Routes:
	var t := Routes.new()
	t.world = MOOR
	if me != null:
		t.serve("me", [me])
	return t

func _provenance(transport: Routes) -> Dictionary:
	var folder := _parent() + "/world"
	var report := await _export(_client(transport, "ow_r_test", "", "", "https://www.onlyworlds.com/api/v2"), folder,
		{"clock": func(): return MOOR_AT})
	if not report.ok:
		return {"failed": report.message}
	return _world_json(folder)

func test_world_json_says_where_it_came_from_after_the_wires_keys(t) -> void:
	var world := await _provenance(_moor())
	t.eq(world["source"], {"server": "https://www.onlyworlds.com", "world": "w-1", "at": "2026-10-19T21:30:00.250Z"},
		"the API's origin, not its path; toISOString's shape")
	t.eq(_keys(world), ["id", "name", "source", "producer", "format_version"], "")
	t.done()

func test_the_clock_is_read_before_the_world(t) -> void:
	var transport := _moor()
	var read := [-1]
	var report := await _export(_client(transport, "ow_r_test", ""), _parent() + "/world",
		{"clock": func(): read[0] = transport.calls.size(); return MOOR_AT})
	t.ok(report.ok, report.message)
	t.eq(read[0], 0, "source.at is when the export began")
	t.done()

func test_an_owner_key_exports_the_owners_slice(t) -> void:
	var world := await _provenance(_moor("{\"kind\":\"owner\",\"role\":\"owner\",\"character\":\"c-own\"}"))
	t.eq(world["exported_as"], {"kind": "owner", "role": "owner", "character": null}, "the whole world, even with an owner_character")
	t.eq(_keys(world), ["id", "name", "source", "exported_as", "producer", "format_version"], "")
	t.done()

func test_a_members_key_exports_the_roles_slice_no_character(t) -> void:
	for role in ["contributor", "co_builder"]:
		var world := await _provenance(_moor("{\"kind\":\"person\",\"role\":\"" + role + "\",\"character\":\"c-9\"}"))
		t.eq(world["exported_as"], {"kind": "member", "role": role, "character": null}, role)
	t.done()

func test_a_guests_key_exports_its_characters_slice_the_name_read_from_the_character(t) -> void:
	var transport := _moor("{\"kind\":\"player\",\"role\":\"guest\",\"character\":\"c-pip\"}")
	transport.serve("character/c-pip", ["{\"id\":\"c-pip\",\"type\":\"character\",\"name\":\"Pip\"}"])
	var world := await _provenance(transport)
	t.eq(world["exported_as"], {"kind": "character", "role": "guest", "character": {"id": "c-pip", "name": "Pip"}}, "")
	t.done()

func test_no_me_writes_no_exported_as_and_the_export_stands(t) -> void:
	var transport := _moor()
	transport.refusals["me"] = [404, "{\"error\":{\"code\":\"not_found\",\"message\":\"no\"}}"]
	var world := await _provenance(transport)
	t.ok(not world.has("exported_as"), "absent, never guessed")
	t.ok(world.has("source"), "the export stands")
	t.eq(world["producer"], OWFolderExport.producer(), "the slice can be unknown; who made the folder never is")
	t.done()

func test_a_reader_that_names_its_world_asks_no_me(t) -> void:
	for key in ["ow_a_test", ""]:
		var transport := _moor("{\"kind\":\"owner\",\"role\":\"owner\",\"character\":null}")
		var folder := _parent() + "/world"
		var report := await _export(_client(transport, key, "", "w-1"), folder)
		t.ok(report.ok, report.message)
		var world := _world_json(folder)
		t.ok(not world.has("exported_as"), "an account token or no key has no /me: the slice is unknown (%s)" % key)
		t.eq(world["source"]["world"], "w-1", "")
		t.ok(not transport.routes().has("/me/"), "no /me was asked")
	t.done()

func test_a_guest_whose_character_cannot_be_read_writes_no_exported_as(t) -> void:
	var transport := _moor("{\"kind\":\"person\",\"role\":\"guest\",\"character\":\"c-x\"}")
	transport.refusals["character/c-x"] = [403, "{\"error\":{\"code\":\"forbidden\",\"message\":\"no\"}}"]
	var world := await _provenance(transport)
	t.ok(world.has("source") and not world.has("exported_as"), "")
	t.done()

func test_a_fresh_export_writes_the_producer_line_in_the_specs_key_order(t) -> void:
	var world := await _provenance(_moor("{\"kind\":\"owner\",\"role\":\"owner\",\"character\":null}"))
	t.eq(_keys(world["producer"]), ["tool", "version", "input"], "the spec's key order")
	t.eq(world["producer"], {"tool": "onlyworlds-godot", "version": OWFolderExport.PRODUCER_VERSION, "input": "server"}, "")
	t.done()

func test_an_export_is_a_birth_so_its_lines_are_its_own_where_the_body_had_them(t) -> void:
	var transport := Routes.new()
	transport.world = "{\"id\":\"w-1\",\"name\":\"Moor\",\"source\":{\"server\":null,\"world\":\"w0\",\"at\":\"2026-10-01T00:00:00.000Z\"},\"producer\":{\"tool\":\"azgaar-converter\",\"version\":\"0.4.0\",\"input\":\"azgaar-map\"}}"
	var world := await _provenance(transport)
	t.eq(world["producer"], OWFolderExport.producer(), "")
	t.eq(world["source"]["world"], "w-1", "")
	t.eq(_keys(world), ["id", "name", "source", "producer", "format_version"], "replaced where they stood")
	t.done()

func test_an_export_carries_the_servers_origin_beside_its_own_lines(t) -> void:
	var first := "{\"source\":null,\"producer\":{\"tool\":\"lantern\",\"version\":\"0.9.0\",\"input\":\"bare\"}}"
	var transport := Routes.new()
	transport.world = "{\"id\":\"w-1\",\"name\":\"W\",\"public_read\":false,\"origin\":" + first + "}"
	var world := await _provenance(transport)
	t.eq(world["origin"], JSON.parse_string(first), "as served")
	t.eq(world["source"]["world"], "w-1", "this export's own line, fresh")
	t.eq(_keys(world), ["id", "name", "public_read", "origin", "source", "producer", "format_version"], "")
	t.done()

func test_an_export_of_a_world_serving_no_origin_writes_none(t) -> void:
	var world := await _provenance(_moor("{\"kind\":\"owner\",\"role\":\"owner\",\"character\":null}"))
	t.ok(world.has("source") and not world.has("origin"), "")
	t.done()

func test_the_producers_version_is_the_addons_version(t) -> void:
	var cfg := ConfigFile.new()
	t.eq(cfg.load("res://addons/onlyworlds/plugin.cfg"), OK, "plugin.cfg read")
	t.eq(OWFolderExport.PRODUCER_VERSION, cfg.get_value("plugin", "version", ""), "PRODUCER_VERSION moves with plugin.cfg's version: a release changes both")
	t.eq(OWFolderExport.PRODUCER_TOOL, "onlyworlds-godot", "the name the release zips publish under")
	t.eq(OWFolderExport.producer(), {"tool": "onlyworlds-godot", "version": cfg.get_value("plugin", "version", ""), "input": "server"}, "")
	t.done()

func test_the_mapping_names_only_what_it_knows(t) -> void:
	var pip := func(_id): return "Pip"
	t.eq(OWFolderExport.exported_as(null, pip), null, "no /me")
	t.eq(OWFolderExport.exported_as({}, pip), null, "an answer with no kind or role")
	t.eq(OWFolderExport.exported_as({"kind": "person", "role": "viewer"}, pip), null, "a role the table does not name")
	t.eq(OWFolderExport.exported_as({"kind": "player", "role": "guest", "character": null}, pip), null, "a guest with no Character")
	t.eq(OWFolderExport.exported_as({"kind": "player", "role": "guest", "character": "c1"}, func(_id): return null), null, "a name that cannot be read")
	t.eq(OWFolderExport.exported_as({"kind": "player", "role": "guest", "character": "c1"}, func(_id): return ""),
		{"kind": "character", "role": "guest", "character": {"id": "c1", "name": ""}}, "an empty name is a name served")
	t.eq(OWFolderExport.exported_as({"kind": "owner", "role": "guest", "character": "c1"}, pip),
		{"kind": "owner", "role": "owner", "character": null}, "kind owner decides first")
	t.done()
