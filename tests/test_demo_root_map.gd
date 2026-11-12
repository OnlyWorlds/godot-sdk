extends RefCounted
## The Moppetopia demo's root Map (demo/moppetopia_map.gd, root_map_of): a Map with no parent_map that is not a layout
## map. The map space profile's rule 8 marks a layout map by x_layout alone, a Dictionary whose method is a non-empty
## String; its Pins are placed by a method, so drawing them as the world's ground shows an arrangement as geography.
## Each case below names a layout map so it sorts first by name, the demo's last tie-break, or carries the world's
## image, its first: before the skip, each picked the layout.

const DEMO := preload("res://demo/moppetopia_map.gd")

static func _world(image_url: String, maps: Array) -> OWWorld:
	var w := OWWorld.new()
	w.info = OWWorldInfo.new({"id": "w", "name": "w", "image_url": image_url})
	for m in maps:
		w.add_element(OWTypes.make("map", m))
	return w

static func _map(id: String, name: String, x_layout: Variant = null, has_layout := false, image_url := "") -> Dictionary:
	var m := {"id": id, "name": name, "parent_map": null, "image_url": image_url}
	if has_layout:
		m["x_layout"] = x_layout
	return m

static func _picked(w: OWWorld) -> String:
	var m: OWMap = DEMO.root_map_of(w)
	return m.id if m != null else "<null>"

func test_a_layout_map_first_by_name_is_not_the_root(t) -> void:
	var w := _world("", [_map("ground", "Sikelia"), _map("layout", "A layout", {"method": "hand"}, true)])
	t.eq(_picked(w), "ground", "a parentless layout map sorting first by name")
	t.done()

func test_a_layout_map_with_the_worlds_image_is_not_the_root(t) -> void:
	var img := "https://example.org/island.webp"
	var w := _world(img, [_map("ground", "A ground"), _map("layout", "Sikelia: layout", {"method": "grid"}, true, img)])
	t.eq(_picked(w), "ground", "a parentless layout map carrying the world's image")
	t.done()

func test_a_world_whose_only_map_is_a_layout_map_has_no_root(t) -> void:
	var w := _world("", [_map("layout", "A layout", {"method": "hand"}, true)])
	t.eq(_picked(w), "<null>", "a layout map is no ground, so there is no root Map")
	t.done()

func test_an_x_layout_that_is_no_mark_stays_a_candidate(t) -> void:
	var not_marks := [
		["no method", {}],
		["an empty method", {"method": ""}],
		["a null method", {"method": null}],
		["a number method", {"method": 3}],
		["a string", "hand"],
		["an array", ["hand"]],
		["null", null],
	]
	for c in not_marks:
		var w := _world("", [_map("ground", "Sikelia"), _map("other", "A map", c[1], true)])
		t.eq(_picked(w), "other", "x_layout as %s is no layout mark" % c[0])
	t.done()
