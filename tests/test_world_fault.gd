extends RefCounted
## A world file refused not_a_world for a world.json that is there but cannot be read says what is wrong with it, in
## the folder read report's words: the TypeScript SDK's OwWorldFileError.worldFault (4.212.0), [member
## OWWorldArchive.Result.world_fault] here.

const WID := "019a9200-0000-7000-8000-000000000001"

static func _fault(t, files: Dictionary, label: String) -> String:
	var r := OWWorldArchive.read(OWWorldArchive.pack_files(files, "w").bytes)
	t.ok(not r.ok and r.reason == "not_a_world", "%s: not_a_world (%s: %s)" % [label, r.reason, r.message])
	return r.world_fault

func test_a_world_json_that_cannot_be_read_says_why_any_other_not_a_world_has_none(t) -> void:
	# npm's five vectors: too_deep (nested past 200), not_json, and "" on a missing world.json, one with no id, and one
	# that is JSON but no object. Kills: the fault left unset, set on a refusal that has none, or the words swapped.
	var deep := "{\"id\":\"%s\",\"name\":\"Deep\",\"x\":%s%s}" % [WID, "[".repeat(200), "]".repeat(200)]
	t.eq(_fault(t, {"world.json": deep.to_utf8_buffer()}, "deep"), "too_deep", "nested past 200")
	t.eq(_fault(t, {"world.json": "{nope".to_utf8_buffer()}, "broken"), "not_json", "not JSON")
	t.eq(_fault(t, {"elements/a.json": "{}".to_utf8_buffer()}, "none"), "", "no world.json")
	t.eq(_fault(t, {"world.json": "{\"name\":\"no id\"}".to_utf8_buffer()}, "no id"), "", "a world.json with no id")
	t.eq(_fault(t, {"world.json": ("[\"%s\"]" % WID).to_utf8_buffer()}, "array"), "", "JSON, but no object")
	t.eq(_fault(t, {"world.json": "null".to_utf8_buffer()}, "null"), "", "JSON null, no object")
	# Causes this reader refuses that JSON.parse in the TypeScript reader does not meet: a value after the object and
	# a raw control character in a string are no JSON, and a number past a double is the report's third word.
	t.eq(_fault(t, {"world.json": ("{\"id\":\"%s\"} x" % WID).to_utf8_buffer()}, "after"), "not_json", "a value after the object")
	t.eq(_fault(t, {"world.json": ("{\"id\":\"%s\",\"n\":\"a\tb\"}" % WID).to_utf8_buffer()}, "control"), "not_json",
		"a raw tab in a string")
	t.eq(_fault(t, {"world.json": ("{\"id\":\"%s\",\"x\":1e400}" % WID).to_utf8_buffer()}, "range"), "number_out_of_range",
		"a number past a double")
	# Any other refusal has none.
	var two := OWWorldArchive.read(OWWorldArchive.pack_files({
		"a/world.json": ("{\"id\":\"%s\",\"name\":\"A\"}" % WID).to_utf8_buffer(),
		"b/world.json": ("{\"id\":\"%s\",\"name\":\"B\"}" % WID).to_utf8_buffer()}, "").bytes)
	t.ok(not two.ok and two.reason == "more_than_one" and two.world_fault == "", "more_than_one has none (%s)" % two.reason)
	t.done()

func test_a_world_json_past_200_says_it_in_words_the_code_the_field(t) -> void:
	# The TypeScript SDK 4.212.3: a world file's refusal for a world.json nested past 200 says it in words alone; the
	# code is world_fault. npm's vector, '[' 201 deep inside the object.
	var deep := "{\"id\": \"%s\", \"x\": %s%s}" % [WID, "[".repeat(201), "]".repeat(201)]
	var r := OWWorldArchive.read(OWWorldArchive.pack_files({"world.json": deep.to_utf8_buffer()}, "w").bytes)
	t.ok(not r.ok and r.reason == "not_a_world", "not_a_world (%s)" % r.reason)
	t.eq(r.world_fault, "too_deep", "the code is the field")
	t.ok(not r.message.contains("too_deep"), "no code mark in the words: " + r.message)
	t.ok(r.message.ends_with("nested more than 200 deep"), "the words: " + r.message)
	t.done()
