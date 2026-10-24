extends RefCounted
## The pin and the generated models: the vendored dist is the one the pin names, and every type has its class.

const P = preload("res://tests/paths.gd")

func test_manifest_matches_the_pin(t) -> void:
	t.eq(FileAccess.get_sha256("res://codegen/schema-dist/MANIFEST.json"), OWSchemaPin.MANIFEST_SHA256, "MANIFEST.json sha256")
	var version := FileAccess.get_file_as_string("res://codegen/schema-dist/VERSION")
	t.ok(version.contains("serial: %d" % OWSchemaPin.SERIAL), "VERSION's serial is the pin's")
	t.ok(OWSchemaPin.TAG.ends_with("dist.%d" % OWSchemaPin.SERIAL), "the tag names the serial")
	t.done()

func test_every_vendored_file_matches_the_manifest(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	var bad := 0
	for rel in manifest:
		if FileAccess.get_sha256("res://codegen/schema-dist/" + rel) != manifest[rel]:
			bad += 1
			t.fail("%s does not match its manifest entry" % rel)
	t.ok(manifest.size() > 100, "the manifest lists the dist (%d files)" % manifest.size())
	t.eq(bad, 0, "files off their manifest hash")
	t.done()

func test_twenty_two_types_each_with_its_class(t) -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/schema.json"))
	t.eq(OWTypes.slugs().size(), 22, "the registry holds 22 types")
	t.eq(Array(OWTypes.slugs()), schema["types"].keys(), "in the schema's order")
	for slug in schema["types"]:
		var e := OWTypes.make(slug, {"id": "x", "name": slug})
		t.eq(String(e.get_type()), slug, "%s model's type" % slug)
		t.eq(String(e.get_script().get_global_name()), "OW" + slug.to_pascal_case(), "%s class name" % slug)
		var own: Dictionary = e.FIELDS
		var expect := 0
		for f in schema["types"][slug]:
			expect += 2 if f["kind"] == "generic" else 1
		t.eq(own.size(), expect, "%s field count" % slug)
	t.eq(OWElement.BASE_FIELDS.keys(), schema["base"].map(func(f): return f["name"]), "base fields")
	t.done()

func test_unknown_type_is_kept_as_a_plain_element(t) -> void:
	var e := OWTypes.make("spaceship", {"id": "1", "name": "Fuzzball", "x_hull": 3.0})
	t.eq(String(e.get_type()), "spaceship", "type kept")
	t.eq(e.get_script().get_global_name(), &"OWElement", "a plain OWElement")
	t.eq(e.name, "Fuzzball", "base field readable")
	t.done()
