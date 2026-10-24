extends RefCounted
## OWWorldArchive.read on every .owworld in the conformance set (schema-dist fixtures/owworld/, the pinned copy): the
## reader verdict, the reason where the set gives one, OW-10's strip, and OW-9's round trip (read, pack, read again).

const P = preload("res://tests/paths.gd")

var _doc: Dictionary

func _verdicts() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(P.FIXTURES + "/verdicts.json"))
	return _doc

func get_cases() -> Array:
	var out := []
	for v in _verdicts()["fixtures"]:
		out.append([v["file"], _case.bind(v)])
	return out

func _case(t, v: Dictionary) -> void:   # bound arguments come after the call's
	if v.get("status") == "not_generated":
		t.skip("not generated: %s" % v.get("why", "").substr(0, 80))
		return
	var path: String = P.FIXTURES + "/" + v["file"]
	t.eq(FileAccess.get_sha256(path), v["sha256"], "the fixture's bytes are the set's")
	var r := OWWorldArchive.read_file(path)
	var got := "accept" if r.ok else "refuse"
	t.eq(got, v["reader"], "reader verdict (%s %s)" % [r.reason, r.message])
	if v["reader"] == "refuse":
		t.eq(r.reason, v["reason"], "reason (%s)" % r.message)
	if r.ok and v.has("strips"):
		var key: String = v["strips"]
		t.ok(not r.world.has(key), "%s stripped from the world" % key)
		t.ok(not (JSON.parse_string(r.files["world.json"].get_string_from_utf8()) as Dictionary).has(key), "%s not in the returned world.json" % key)
	if r.ok and v.get("roundtrip", false):
		var top := r.prefix.trim_suffix("/")
		var packed := OWWorldArchive.pack_files(r.files, top)
		t.ok(packed.ok, "repacked")
		var again := OWWorldArchive.read(packed.bytes)
		t.ok(again.ok, "the repacked file reads (%s)" % again.message)
		t.eq(again.files, r.files, "round trip: every entry byte-equal")
	t.done()

func test_the_set_is_the_pinned_one(t) -> void:
	var doc := _verdicts()
	var on_disk := 0
	for f in DirAccess.get_files_at(P.FIXTURES):
		if f.ends_with(".owworld") or f.ends_with(".zip"):
			on_disk += 1
	var generated := 0
	for v in doc["fixtures"]:
		if v.get("status") != "not_generated":
			generated += 1
	t.eq(on_disk, generated, "every generated fixture is on disk, and nothing else")
	print("       the set: %d fixtures in verdicts.json, %d on disk" % [doc["fixtures"].size(), on_disk])
	t.done()
