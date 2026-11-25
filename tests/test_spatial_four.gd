extends RefCounted
## Under the legacy spatial/ a reader reads map, pin, zone and marker, and only those four, lower case as under elements/
## (the folder format's section 4.8, ruled 2026-11-25): spatial/character/ holds no Character, and spatial/Pin/ no Pin.
## Each door: a world folder, OWWorld.from_files, an .owworld read back, and the fixture set's two OW-24 cases where the
## set holds them (a draft set, OW_OWWORLD_FIXTURES, before the serial that publishes them).

const P = preload("res://tests/paths.gd")

const WORLD := "{\n  \"id\": \"019a9400-0000-7000-8000-000000000001\",\n  \"name\": \"W\"\n}\n"
const ID_A := "019a9400-0000-7000-8000-00000000000a"
const ID_CLERIC := "019a9400-0000-7000-8000-00000000000c"
const ID_WELL := "019a9400-0000-7000-8000-00000000000d"
const ID_PIN := "019a9400-0000-7000-8000-00000000000e"

static func _body(id: String, name := "A") -> String:
	return "{\n  \"id\": \"%s\",\n  \"name\": \"%s\"\n}\n" % [id, name]

static func _as_bytes(files: Dictionary) -> Dictionary:
	var out := {}
	for rel: String in files:
		out[rel] = String(files[rel]).to_utf8_buffer()
	return out

static func _worlds(files: Dictionary) -> Array:
	var root := ProjectSettings.globalize_path(P.TMP + "/spatial-four")
	P.remove_tree(root)
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(String(files[rel]).to_utf8_buffer())
		f.close()
	var r := OWWorldArchive.read(OWWorldArchive.pack_files(_as_bytes(files), "w").bytes)
	return [["folder", OWWorld.read_folder(root)], ["files", OWWorld.from_files(_as_bytes(files))],
		["archive", r.to_world() if r.ok else null]]

## One world per spelling of pin's folder: on a disk that ignores case spatial/Pin/ and spatial/pin/ are one folder, and
## in an .owworld the two side by side are OW-18's collision.
func test_spatial_reads_the_four_and_only_the_four(t) -> void:
	var cases := [
		[{"world.json": WORLD, "elements/character/a.json": _body(ID_A),
			"spatial/character/cleric.json": _body(ID_CLERIC, "Cleric"), "spatial/pin/p.json": _body(ID_PIN, "P")},
			"spatial/character/cleric.json", ID_CLERIC, 2],
		[{"world.json": WORLD, "elements/character/a.json": _body(ID_A), "spatial/Pin/well.json": _body(ID_WELL, "Well")},
			"spatial/Pin/well.json", ID_WELL, 1],
	]
	for c in cases:
		var files: Dictionary = c[0]
		var rel: String = c[1]
		for pair in _worlds(files):
			var how: String = "%s, %s" % [pair[0], rel]
			var w: OWWorld = pair[1]
			if w == null:
				t.fail(how + ": the world did not read")
				continue
			t.ok(w.get_element(c[2]) == null, how + ": not served (spatial/ holds map, pin, zone, marker as written)")
			t.eq(w.elements.size(), c[3], how + ": nothing else is lost or added")
			if files.has("spatial/pin/p.json"):
				t.ok(w.get_element(ID_PIN) != null and w.get_element(ID_PIN).get_type() == &"pin", how + ": spatial/pin/ is read")
			var said := ""
			for line in w.errors:
				if line.begins_with(rel + ": "):
					said = line
			t.ok(said.contains("map, pin, zone, marker"), "%s: skipped with its reason (%s)" % [how, said])
			t.eq(w.other_files.get(rel), String(files[rel]).to_utf8_buffer(), how + ": kept as its bytes")
	P.remove_tree(ProjectSettings.globalize_path(P.TMP))
	t.done()

func test_the_sets_two_cases_serve_nothing_from_spatial(t) -> void:
	var ran := 0
	for file in ["pass-OW-24-spatial-untyped.owworld", "pass-OW-24-spatial-type-case.owworld"]:
		var path: String = P.FIXTURES + "/" + file
		if not FileAccess.file_exists(path):
			continue
		ran += 1
		var r := OWWorldArchive.read_file(path)
		t.ok(r.ok, file + ": accepted (%s)" % r.message)
		var w := r.to_world() if r.ok else null
		if w == null:
			continue
		t.eq(w.elements.size(), 3, file + ": the base world's three elements")
		for e in w.elements:
			t.ok(e.source_path.begins_with("elements/"), "%s: %s is not served" % [file, e.source_path])
	if ran == 0:
		t.skip("this set has no OW-24 case (it comes after serial 145): set OW_OWWORLD_FIXTURES to a draft set")
		return
	t.done()
