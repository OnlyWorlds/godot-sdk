extends RefCounted
## The fault the folder format's doors share when world.json, elements/ or spatial/ sits in another case (section 4.8,
## ruled 2026-11-25): [method OWWorld.fixed_name_fault], whose words a folder's refusal prints and a pack's message
## carries. Its own file, since the doors' tests (test_fixed_names.gd) read every version of the addon.

## The fault the doors share names the cause's spellings, both of them.
func test_the_fault_names_both_spellings(t) -> void:
	var why := OWWorld.fixed_name_fault(PackedStringArray(["world.json", "Elements", "media"]))
	t.ok(why.contains("'Elements'") and why.contains("'elements'"), "both spellings named (%s)" % why)
	t.ok(why.contains("name_case"), "the cause named (%s)" % why)
	t.eq(OWWorld.fixed_name_fault(PackedStringArray(["world.json", "elements", "spatial", "Media"])), "",
		"the names as written: no fault (media/ is none of the three)")
	t.eq(OWWorld.fixed_name_fault(PackedStringArray(["world.json", "elements", "Elements"])), "",
		"both spellings (a disk that keeps case): the name as written is read, the other left unread")
	t.ok(OWWorld.fixed_name_fault(PackedStringArray(["world.json", "\u017Fpatial"])).contains("spatial"),
		"OW-18's fold: a long s is an s, so this is spatial in another case")
	t.ok(OWWorld.fixed_name_fault(PackedStringArray(["World.JSON", "elements"])).contains("'World.JSON'"),
		"world.json in another case")
	t.done()
