extends Node2D
## A world in a scene: reads a world folder, draws its root Map's image, and each Pin on that map at its position
## (x, y from the map's bottom-left, per the schema) with its name (the pinned element's, when the pin has none).
##
## The world: [code]-- --world=<folder | file.owworld>[/code] on the command line, else the folder OW_WORLD names,
## else the example world vendored with the schema (Hyperion: one Map, one Pin; its map image is a web link, so the
## Pin is drawn on a plain ground). [code]-- --capture=<file.png>[/code] saves the third frame and quits.

const DEFAULT_WORLD := "res://codegen/schema-dist/example/hyperion"
const IMAGE_EXTENSIONS := ["webp", "png", "jpg", "jpeg"]

var world: OWWorld
var map: OWMap
var texture: Texture2D
var image_note := ""
var pins: Array = []      # [position in map units (bottom-left origin), label]
var _capture := ""
var _frames := 0

func _ready() -> void:
	var folder := OS.get_environment("OW_WORLD")
	if folder == "":
		folder = DEFAULT_WORLD
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--world="):
			folder = a.substr(8)
		elif a.begins_with("--capture="):
			_capture = a.substr(10)
	var archive: OWWorldArchive.Result = null
	if folder.get_extension().to_lower() == "owworld":
		archive = OWWorldArchive.read_file(folder)
		if not archive.ok:
			push_error("%s refused: %s (%s)" % [folder, archive.reason, archive.message])
			return
		world = archive.to_world()
	else:
		world = OWWorld.read_folder(folder)
	if world == null:
		push_error("no world at %s" % folder)
		return
	map = root_map_of(world)
	if map == null:
		push_error("%s has no map without a parent that is not a layout map" % folder)
		return
	texture = _map_texture_in(archive.files) if archive != null else _map_texture(folder)
	for p: OWPin in world.of_type("pin"):
		if p.map != map.id or p.x == null or p.y == null:
			continue
		var label := p.name
		if label == "" and p.element_id != "":
			var target := world.get_element(p.element_id)
			label = target.name if target != null else ""
		pins.append([Vector2(p.x, p.y), label])
	print("world %s: %d elements; root map %s (%dx%d), %d pins on it; image: %s" % [world.info.name, world.elements.size(), map.name, _map_size().x, _map_size().y, pins.size(), image_note])
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _process(_delta: float) -> void:
	if _capture == "":
		return
	_frames += 1
	if _frames == 3:
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_capture)
		print("captured %dx%d to %s (error %d)" % [img.get_width(), img.get_height(), _capture, err])
		get_tree().quit(0 if err == OK else 1)

## The map nothing contains: no parent_map, and not a layout map (the map space profile's rule 8: an x_layout whose
## method is a non-empty String places its Pins by a method, so it is no ground to draw them on). Several: the one
## whose image is the world's, else the first by name. Null when no Map qualifies.
static func root_map_of(w: OWWorld) -> OWMap:
	var roots: Array[OWMap] = []
	for m: OWMap in w.of_type("map"):
		if m.parent_map == "" and OWMapSpace.layout_of(m.to_dict(), [], []).layout == null:
			roots.append(m)
	if roots.is_empty():
		return null
	var world_image: String = w.info.image_url if w.info != null else ""
	for m in roots:
		if m.image_url != "" and m.image_url == world_image:
			return m
	roots.sort_custom(func(a, b): return a.name < b.name)
	return roots[0]

## The map's image from the world's own media/<map id>/: the file its image_url names, else the first image there.
func _map_texture(folder: String) -> Texture2D:
	var files := _images_under(folder + "/media/" + map.id)
	var wanted := map.image_url.get_file()
	files.sort_custom(func(a, b): return (a.get_file() == wanted) and not (b.get_file() == wanted))
	for path in files:
		var img := Image.new()
		var err := img.load(path)
		if err == OK:
			image_note = "%s (%s, %dx%d)" % [path.get_file(), path.get_extension(), img.get_width(), img.get_height()]
			return ImageTexture.create_from_image(img)
		image_note += "%s did not load (error %d); " % [path.get_file(), err]
	image_note += "no image loaded"
	return null

## The same choice from an archive's files (path inside the world -> bytes): nothing touches the disk.
func _map_texture_in(files: Dictionary) -> Texture2D:
	var under := "media/" + map.id + "/"
	var paths := []
	for p in files:
		if p.begins_with(under) and p.get_extension().to_lower() in IMAGE_EXTENSIONS:
			paths.append(p)
	var wanted := map.image_url.get_file()
	paths.sort_custom(func(a, b): return (a.get_file() == wanted) and not (b.get_file() == wanted))
	for path in paths:
		var img := Image.new()
		var bytes: PackedByteArray = files[path]
		var err := ERR_FILE_UNRECOGNIZED
		match path.get_extension().to_lower():
			"webp": err = img.load_webp_from_buffer(bytes)
			"png": err = img.load_png_from_buffer(bytes)
			_: err = img.load_jpg_from_buffer(bytes)
		if err == OK:
			image_note = "%s (%s, %dx%d, from the archive)" % [path.get_file(), path.get_extension(), img.get_width(), img.get_height()]
			return ImageTexture.create_from_image(img)
		image_note += "%s did not load (error %d); " % [path.get_file(), err]
	image_note += "no image loaded"
	return null

func _images_under(dir: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in IMAGE_EXTENSIONS:
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_images_under(dir + "/" + d))
	return out

func _map_size() -> Vector2:
	var w = map.width
	var h = map.height
	if w == null or h == null or w <= 0 or h <= 0:
		return texture.get_size() if texture != null else Vector2(1000, 1000)
	return Vector2(w, h)

func _draw() -> void:
	if map == null:
		return
	var view := get_viewport_rect().size
	var size := _map_size()
	var s := minf(view.x / size.x, view.y / size.y)
	var origin := (view - size * s) / 2.0
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.06, 0.07, 0.1))
	if texture != null:
		draw_texture_rect(texture, Rect2(origin, size * s), false)
	var font := ThemeDB.fallback_font
	for p in pins:
		var at: Vector2 = origin + Vector2(p[0].x, size.y - p[0].y) * s   # the schema's origin is bottom-left
		draw_circle(at, 7.0, Color(0.05, 0.05, 0.08))
		draw_circle(at, 5.0, Color(1.0, 0.78, 0.25))
		var label: String = p[1]
		if label != "":
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			var to := at + Vector2(10, 6)
			if to.x + width > view.x - 4:
				to.x = at.x - 10 - width     # past the right edge: the name goes on the pin's left
			draw_string_outline(font, to, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, 0.85))
			draw_string(font, to, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	var title := "%s · %s · %d pins" % [world.info.name, map.name, pins.size()]
	draw_string_outline(font, Vector2(14, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(14, 28), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
