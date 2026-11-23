extends RefCounted
## The addon folder as a download hands it over: its copy of the licence is the repository's LICENSE byte for byte (a
## commit's zip carries the folder alone, so the copy is the licence a developer keeps).

func test_the_licence_copy_is_the_root_licence(t) -> void:
	var root := FileAccess.get_file_as_bytes("res://LICENSE")
	var copy := FileAccess.get_file_as_bytes("res://addons/onlyworlds/LICENSE")
	t.ok(not root.is_empty(), "the root LICENSE is read")
	t.ok(not copy.is_empty(), "addons/onlyworlds/LICENSE is read")
	t.ok(root == copy, "addons/onlyworlds/LICENSE is the root LICENSE byte for byte")
	t.done()
