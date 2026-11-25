extends RefCounted
## A dot-folder is never a world, wherever it sits (the folder format's section 4.7, OW-5, ruled 2026-11-24): the
## second-world check does not look under a folder whose name starts with a dot, so a tool's world.json there does not
## refuse the archive. Only that check skips them; every other check still reads their entries.

const WORLD := "{\n  \"id\": \"019a9400-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const OTHER := "{\n  \"id\": \"019a9400-0000-7000-8000-0000000000ff\",\n  \"name\": \"A tool's\"\n}\n"
const ELEMENT := "{\n  \"id\": \"019a9400-0000-7000-8000-00000000000a\",\n  \"name\": \"A\"\n}\n"

static func _read(files: Dictionary) -> OWWorldArchive.Result:
	var bytes := {}
	for rel: String in files:
		bytes[rel] = String(files[rel]).to_utf8_buffer()
	return OWWorldArchive.read(OWWorldArchive.pack_files(bytes, "").bytes)

func test_a_world_json_under_a_dot_folder_is_a_tools_not_a_second_world(t) -> void:
	var r := _read({"abbey/world.json": WORLD, "abbey/elements/character/a.json": ELEMENT,
		"abbey/.atlas/world.json": OTHER, "abbey/..atlas/world.json": OTHER,
		"abbey/elements/character/.trash/world.json": OTHER})
	t.ok(r.ok, "accepted (%s %s)" % [r.reason, r.message])
	if r.ok:
		t.eq(r.world_id, "019a9400-0000-7000-8000-000000000001", "the world's own id")
		t.eq(r.to_world().elements.size(), 1, "nothing under a dot-folder is an element")
	t.done()

func test_a_world_json_under_a_folder_that_only_holds_a_dot_is_a_second_world(t) -> void:
	var r := _read({"abbey/world.json": WORLD, "abbey/a.b/world.json": OTHER})
	t.eq(r.reason, "more_than_one", "a.b/ is a folder like any other (%s)" % r.message)
	t.done()
