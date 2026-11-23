extends RefCounted
## The addon folder as a download hands it over: its copy of the licence is the repository's LICENSE byte for byte (a
## commit's zip carries the folder alone, so the copy is the licence a developer keeps), and the listing's icon is a
## square PNG of at least 128 by 128 pixels (the Asset Library's rule for an icon).

const ICON := "res://media/icon.png"

func test_the_licence_copy_is_the_root_licence(t) -> void:
	var root := FileAccess.get_file_as_bytes("res://LICENSE")
	var copy := FileAccess.get_file_as_bytes("res://addons/onlyworlds/LICENSE")
	t.ok(not root.is_empty(), "the root LICENSE is read")
	t.ok(not copy.is_empty(), "addons/onlyworlds/LICENSE is read")
	t.ok(root == copy, "addons/onlyworlds/LICENSE is the root LICENSE byte for byte")
	t.done()

func test_the_icon_is_a_square_png_of_128_or_more(t) -> void:
	# Read as bytes: media/ holds a .gdignore, so Godot never imports the icon into this project.
	var b := FileAccess.get_file_as_bytes(ICON)
	t.ok(b.size() > 24, "the icon is read")
	if b.size() <= 24:
		t.done()
		return
	t.eq(b.slice(0, 8), PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "a PNG signature")
	t.eq(b.slice(12, 16).get_string_from_ascii(), "IHDR", "its first chunk is the header")
	var w := (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19]
	var h := (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23]
	t.eq(w, h, "square")
	t.ok(w >= 128, "at least 128 pixels wide, got %d" % w)
	t.done()
