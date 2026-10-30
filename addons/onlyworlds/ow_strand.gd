class_name OWStrand
extends RefCounted
## The strand profile (schema-dist [code]profiles/strand.md[/code], serial 98): a world in miniature, one story read
## off four links the standard already has. The World's mark [code]x_strand[/code] names the story (a Narrative), one
## of its [code]events[/code] and one of that Event's [code]locations[/code]; the hero is the story's
## [code]protagonist[/code] and where the hero is now is the hero's [code]location[/code].
##
## [method strand_of] answers the six slots as one reader sees the world: keel's [code]elements/strand.py[/code]
## ([code]strand_of[/code]) is the reading this follows, the npm SDK's [code]strandOf[/code] and the Python package's
## [code]strand_of[/code] the same. The world and the reader are [method OWLens.resolve]'s, read through the same
## [OWLens.View], never a second copy of who sees what. The fixture beside the profile is this file's test.

## The World's field that carries the mark.
const MARK := "x_strand"
## The mark's three members, in the profile's order.
const MEMBERS := ["narrative", "event", "location"]

## What [method strand_of] answers. Each filled slot is [code]{id, name}[/code], an empty one null. [member error] is
## "" unless the call itself was a mistake (a world without an elements list, a rung outside the four): then it names
## the mistake and nothing is read.
class Strand:
	## The story: the Narrative the mark names.
	var narrative: Variant = null
	## The happening: the Event the mark names, when it is in the story's [code]events[/code].
	var event: Variant = null
	## The place, then: the Location the mark names, when it is in the event's [code]locations[/code].
	var location: Variant = null
	## The hero: the story's [code]protagonist[/code].
	var character: Variant = null
	## The place, now: the hero's [code]location[/code].
	var now: Variant = null
	## True when [member now] and [member location] are both filled with one id, false when with two, null otherwise.
	var same: Variant = null
	var error := ""

	## The strand in the profile's shape.
	func to_dict() -> Dictionary:
		return {"narrative": narrative, "event": event, "location": location, "character": character, "now": now,
			"same": same}

## The world's strand as [param reader] sees it (the profile's [code]strandOf[/code]). Pure: nothing is stored or
## written.
##
## [param world] is what [method OWLens.resolve] takes, with the World's [code]x_strand[/code] beside it:
## [code]elements[/code] (the bodies as the owner is served them), [code]hidden[/code] (the ids the hidden mark keeps),
## [code]open[/code]: true for a world open to anyone, and the mark. [param reader] is a lens reader ([code]rung[/code]
## owner, contributor, guest with its [code]whole[/code] and [code]known_of[/code], or public; on an owner,
## [code]as[/code]). A public reader of a world not open to anyone reads nothing.
##
## [code]narrative[/code] is the element the mark names when it is a Narrative in the reader's view; with none, every
## slot is empty, since a strand hangs off its story. [code]event[/code] is the element the mark names when it is an
## Event in the reader's view and in the story's [code]events[/code] as the reader is served them;
## [code]location[/code] the element the mark names when it is a Location in the reader's view and in that event's
## [code]locations[/code], empty when the event is. [code]character[/code] is the story's [code]protagonist[/code] when
## it is a Character in the reader's view; [code]now[/code] the hero's [code]location[/code] when it is a Location in
## the reader's view, empty when the hero is. A slot holds only its own kind, a list is read for membership and never
## its order, and no slot is filled from another: not the hero from the event's [code]characters[/code], not
## [code]location[/code] from [code]now[/code], nor the reverse. Each slot's links are read from the body the reader is
## served, so a story known only as a stub fills its own slot and nothing past it.
##
## The mark is a Dictionary whose three members are each a String; any other shape (a bare string, a member missing,
## null or not a String) is no mark, and the strand is empty. An id that names no element in the reader's view, an
## empty string included, is an empty slot: there is no id-format test here (a malformed id is the doctor's to name).
static func strand_of(world: Variant, reader: Variant) -> Strand:
	var out := Strand.new()
	if not (world is Dictionary and world.get("elements") is Array):
		out.error = "strand_of: world is a Dictionary with an elements Array"
		return out
	var bad := OWLens._check_reader(reader, "strand_of: reader")
	if bad != "":
		out.error = bad
		return out
	var mark: Variant = world.get(MARK)
	if not (mark is Dictionary):
		return out
	for m in MEMBERS:
		if not (mark.get(m) is String):
			return out
	var r := OWLens.View.new(world, reader, null)
	if r.seen_rung == "public" and world.get("open") != true:
		return out
	var story: String = mark["narrative"]
	var happening: String = mark["event"]
	var then: String = mark["location"]
	if not _seen(r, story, "narrative"):
		return out
	out.narrative = _slot(r, story)
	if _seen(r, happening, "event") and _listed(r, story, "events", happening):
		out.event = _slot(r, happening)
		if _seen(r, then, "location") and _listed(r, happening, "locations", then):
			out.location = _slot(r, then)
	var hero: Variant = r.body(story).get("protagonist")
	if _seen(r, hero, "character"):
		out.character = _slot(r, hero)
		var where: Variant = r.body(hero).get("location")
		if _seen(r, where, "location"):
			out.now = _slot(r, where)
	if out.now != null and out.location != null:
		out.same = out.now["id"] == out.location["id"]
	return out

## True when [param id] is an element of [param kind] in the reader's view: a slot holds only its own kind.
static func _seen(r: OWLens.View, id: Variant, kind: String) -> bool:
	return id is String and r.view.has(id) and r.type_of.get(id) == kind

## A filled slot, its name as the reader is served it ("" when it has none).
static func _slot(r: OWLens.View, id: String) -> Dictionary:
	var name: Variant = r.body(id).get("name")
	return {"id": id, "name": name if name is String else ""}

## True when the body [param holder] is served lists [param id] in [param field]: membership, never position.
static func _listed(r: OWLens.View, holder: String, field: String, id: String) -> bool:
	var v: Variant = r.body(holder).get(field)
	return v is Array and v.has(id)
