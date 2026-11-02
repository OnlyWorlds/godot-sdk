class_name OWLanding
extends RefCounted
## The landing profile (schema-dist [code]profiles/landing.md[/code], serial 103). Not read yet: the replay first.

class Landing:
	var mode := ""
	var size := 0
	var clusters := []
	var unclustered := []
	var gaps := []
	var refused := ""
	var error := ""

	func to_dict() -> Dictionary:
		if refused != "":
			return {"refused": refused}
		return {"mode": mode, "size": size, "clusters": clusters, "unclustered": unclustered, "gaps": gaps}

static func landing_of(graph: Variant, options: Variant = null) -> Landing:
	return Landing.new()
