class_name OWMapSpace
extends RefCounted
## The map space profile (schema-dist [code]profiles/map-space.md[/code], serial 105). Not read yet: the replay first.

class MapSpace:
	var maps := []
	var zones := []
	var pins := []
	var out := {}
	var error := ""

	func to_dict() -> Dictionary:
		return {"maps": maps, "zones": zones, "pins": pins, "out": out}

static func map_space(elements: Variant) -> MapSpace:
	return MapSpace.new()
