class_name OWNames
extends RefCounted
## The names profile (schema-dist [code]profiles/names.md[/code], serial 92): a world's own words for the 22 types,
## [code]x_names[/code] on the World. A display lookup only: the API, the folder, the schema and every id keep the
## standard's names, and a folder's [code]elements/<type>/[/code] directories are never translated.
##
## [method type_word] is the npm SDK's [code]typeWord[/code] and the Python package's [code]type_word[/code]; the
## fixture beside the profile is this file's test, as it is theirs: every reader refuses and ignores the same things,
## or one tool shows Employee where another shows Character. Trimming and folding are the room profile's
## ([method OWUnicode.trim_white_space], [method OWUnicode.profile_fold]).

## The World's field that holds the names map.
const FIELD := "x_names"

## The world's own word for a type, or null for the standard's name (print your usual label). [param world] is a
## [code]GET /world[/code] body or a folder's [code]world.json[/code] as a Dictionary ([member OWWorld.info]'s
## [method OWElementCore.to_dict]); its [code]x_names[/code] is read. [param type] is a type slug, lowercase as the
## schema spells it; [param supertype] the element's, when there is one; [param many] true for a plural (a list's
## heading, a count). A type or supertype that is not a String or StringName is none.
##
## The order: the supertype's entry, its key matched trimmed and without regard to case; then the type's entry; then
## null. An entry with no string [code]one[/code] left after trimming is ignored, and the lookup goes on. For a
## plural, a [code]many[/code] that is absent, not a string or blank prints [code]one[/code]. Both are trimmed. A
## value that is not a names map is null everywhere: not an object, [code]version[/code] not the number 1
## ([code]true[/code] included; Godot's JSON reads 1 as 1.0, which is the number 1), [code]types[/code] or
## [code]supertypes[/code] present and not objects (null included), or a [code]supertypes[/code] value that is not an
## object. A bad entry or a key that is not one of the 22 slugs is ignored. The word is printed as written, never
## re-cased. Never errors.
static func type_word(world: Variant, type: Variant, supertype: Variant = null, many: bool = false) -> Variant:
	if not (world is Dictionary) or not (type is String or type is StringName):
		return null
	var slug := str(type)
	var map: Variant = world.get(FIELD)
	if not (map is Dictionary) or not _is_version_one(map.get("version")):
		return null
	var types: Variant = map.get("types")
	if map.has("types") and not (types is Dictionary):
		return null
	var supertypes: Variant = map.get("supertypes")
	if map.has("supertypes"):
		if not (supertypes is Dictionary):
			return null
		for inner in supertypes.values():
			if not (inner is Dictionary):
				return null
	if not OWTypes.SCRIPTS.has(slug):
		return null
	var wanted := OWUnicode.profile_fold(str(supertype)) if (supertype is String or supertype is StringName) else ""
	if wanted != "" and supertypes is Dictionary and supertypes.get(slug) is Dictionary:
		var entries: Dictionary = supertypes[slug]
		for key in entries:
			if not (key is String) or OWUnicode.profile_fold(key) != wanted:
				continue
			var w: Variant = _word(entries[key], many)
			if w != null:
				return w
	return _word(types.get(slug), many) if types is Dictionary else null

## The word a pair prints, or null when the entry is ignored (no string [code]one[/code] left after trimming).
static func _word(pair: Variant, many: bool) -> Variant:
	if not (pair is Dictionary) or not (pair.get("one") is String):
		return null
	var one := OWUnicode.trim_white_space(pair["one"])
	if one == "":
		return null
	if not many:
		return one
	var plural := OWUnicode.trim_white_space(pair["many"]) if pair.get("many") is String else ""
	return one if plural == "" else plural

## The number 1, as JavaScript's [code]=== 1[/code] reads it: an int or a float (Godot's JSON gives 1.0), never a
## boolean or text.
static func _is_version_one(version: Variant) -> bool:
	return (version is int or version is float) and version == 1
