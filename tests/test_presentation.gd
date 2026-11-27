extends RefCounted
## OWPresentation.group_of, npm 5.0's name (the TypeScript SDK's groupOf): each type's colour group, the word the
## deprecated family_of answered under its old name.

func test_group_of_answers_each_types_colour_group(t) -> void:
	for type in OWTypes.slugs():
		t.eq(OWPresentation.group_of(type), OWPresentation.TYPES[type]["family"], type)
		t.ok(OWPresentation.ORDER.has(OWPresentation.group_of(type)), type + ": one of the colour words")
	t.eq(OWPresentation.group_of("character"), "blue", "character is blue")
	t.eq(OWPresentation.group_of("event"), "amber", "event is amber")
	t.done()

func test_group_of_reads_the_table_in_use(t) -> void:
	var table: Dictionary = OWPresentation.TYPES.duplicate(true)
	table["character"]["family"] = "pink"
	t.eq(OWPresentation.use(table), "", "the table taken")
	t.eq(OWPresentation.group_of("character"), "pink", "the tool's group")
	OWPresentation.reset()
	t.eq(OWPresentation.group_of("character"), "blue", "back to the defaults")
	t.done()

func test_family_of_answers_as_group_of(t) -> void:
	for type in OWTypes.slugs():
		t.eq(OWPresentation.family_of(type), OWPresentation.group_of(type), type)
	t.done()
