extends RefCounted
## The generated models as typed views onto an element's data.

const P = preload("res://tests/paths.gd")

const CHARACTER := "elements/character/aballon-of-thapsos--08c98bff.json"

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func test_character_reads_typed(t) -> void:
	var path := P.sikelia() + "/" + CHARACTER
	if not FileAccess.file_exists(path):
		t.skip("no Sikelia at %s" % P.sikelia())
		return
	var c := OWCharacter.new(_read(path))
	t.eq(c.name, "Aballon of Thapsos", "name")
	t.eq(c.id, "5433eed1-b5c7-41e4-a81f-4f9008c98bff", "id")
	t.eq(c.height, null, "an unset int is null")
	t.eq(c.birthplace, "141592f7-4466-4c95-b720-e07df8302417", "a single link is a bare id")
	t.eq(c.species, PackedStringArray(["f457a834-6e59-494a-ae0f-b8a2f3ffda82"]), "a multi link is ids")
	t.eq(c.traits, PackedStringArray(), "an empty multi link")
	t.eq(OWCharacter.FIELDS["birthplace"], ["single", "location"], "the link's target from the schema")
	t.ok(c is OWElement, "inherits OWElement")
	t.ok(not c.edited, "reading edits nothing")
	t.done()

func test_set_int_keeps_order_and_unknown_keys(t) -> void:
	var path := P.sikelia() + "/" + CHARACTER
	if not FileAccess.file_exists(path):
		t.skip("no Sikelia at %s" % P.sikelia())
		return
	var d := _read(path)
	var keys_before := d.keys()
	var c := OWCharacter.new(d)
	c.height = 180
	c.STR = 12
	t.eq(c.height, 180, "an int set")
	t.eq(typeof(c.height), TYPE_INT, "comes back an int")
	t.ok(c.edited, "a set marks the element edited")
	t.eq(c.to_dict().keys(), keys_before, "key order as read, nothing added or dropped")
	t.ok(c.to_dict().has("created_at"), "a key the schema does not name travels")
	var text := OWJson.stringify(c.to_dict())
	t.ok(text.contains("\"height\": 180,"), "written as an integer")
	t.ok(text.contains("\"change_seq\": "), "change_seq kept")
	t.ok(not text.contains(".0,"), "no integer written as a float")
	t.done()

func test_pin_generic_link_and_coordinates(t) -> void:
	var root := P.moppetopia()
	var path := root + "/elements/pin/01a1206c-e7c5-76c7-9ab5-d83743b47c02.json"
	if not FileAccess.file_exists(path):
		t.skip("no Moppetopia at %s" % root)
		return
	var p := OWPin.new(_read(path))
	t.eq(p.map, "01a1206b-efde-7a5c-8956-d0b871776154", "pin.map")
	t.eq(typeof(p.x), TYPE_INT, "x is an int")
	t.ok(p.element_type != "" and p.element_id != "", "the generic link's two keys")
	p.element_id = ""
	t.eq(p.to_dict()["element_id"], null, "an emptied link writes null")
	t.done()

func test_unset_shapes_fold(t) -> void:
	var e := OWLocation.new({"id": "1", "name": "x", "subtype": null, "parent_location": null})
	t.eq(e.subtype, "", "null string reads as unset")
	t.eq(e.description, "", "absent string reads as unset")
	t.eq(e.parent_location, "", "null link reads as unset")
	t.eq(e.populations, PackedStringArray(), "absent multi reads empty")
	t.eq(e.elevation, null, "absent int is null")
	e.elevation = 12
	t.eq(e.to_dict().keys(), ["id", "name", "subtype", "parent_location", "elevation"], "a new key is appended")
	t.done()
