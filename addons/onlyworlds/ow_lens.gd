class_name OWLens
extends RefCounted
## The lens profile (schema-dist [code]profiles/lens.md[/code], serial 78, its graph section serial 81): a saved way of
## reading a world. A lens is a Construct with supertype [code]Lens[/code]; its links are its anchors, and
## [code]x_lens[/code] is the recipe (how far, which types, how far back, how much).
##
## [method is_lens], [method is_template], [method check_keys] (the legal values of [code]x_lens[/code]) and
## [method lenses_in_use] (where a seat's choice lives). The npm and Python packages' [code]isLens[/code],
## [code]isTemplate[/code] and [code]lensesInUse[/code]; the fixture beside the profile is this file's test.
##
## Element bodies are Dictionaries as the API or a world folder gives them. Godot's JSON reads every number as a
## float, so a whole number here is an int, or a float with no fraction inside the 64-bit range ([method whole]).

## The pair a lens is, each word trimmed and folded as the room profile reads its pairs.
const PAIR_TYPE := "construct"
const PAIR_SUPERTYPE := "Lens"
## The subtype a template carries: a lens with no anchors that resolves to nothing until copied and pointed.
const TEMPLATE_SUBTYPE := "Template"
## The extension field that holds the recipe, a JSON object; every key optional, null absent.
const FIELD := "x_lens"
## A folder Character's list of the lens ids it reads (a folder world has no membership).
const USES_FIELD := "x_lens_uses"

## The anchor fields: the Construct's Involves links in the schema's order, less [code]titles[/code].
const ANCHOR_FIELDS := ["characters", "objects", "locations", "species", "creatures", "institutions", "traits",
	"collectives", "zones", "abilities", "phenomena", "languages", "families", "relations", "constructs", "events",
	"narratives"]

## The room profile's nine pairs, type and supertype trimmed and folded, a slash between: the words [code]types[/code]
## may name beside the 22 slugs (the room profile's fixture order).
const ROOM_PAIRS := ["narrative/message", "narrative/board", "relation/work item", "construct/spec", "relation/heart",
	"relation/take", "relation/vote", "event/sitting", "character/member"]

## Why an element was left out: the profile's one closed list, in its order.
const CUT_REASONS := ["budget", "types", "window", "undated", "after_as_of", "anchor_not_visible", "not_visible",
	"hops_not_served"]
## The two counts only the owner is told (reading as itself, or as another reader).
const OWNER_ONLY := ["anchor_not_visible", "not_visible"]

const DEFAULT_DEPTH := 1
const DEFAULT_BUDGET := 50
const DEFAULT_UNDATED := "include"
const DEFAULT_SHOW := "full"
const DEFAULT_MAIL := "none"
## The mail rule's window, in days on [code]created_at[/code] before the reading's time.
const MAIL_DAYS := 30

const _UNDATED := ["include", "exclude"]
const _SHOW := ["full", "first_line", "name"]
const _MAIL := ["unread_full_read_titles", "all", "none"]
const _I64_EDGE := 9223372036854775808.0   # 2^63: a float at or past it (or below -2^63) is no 64-bit whole number

# -- the pair -----------------------------------------------------------------------------------------------------------

## True when [param element] is a lens: a Construct with supertype [code]Lens[/code], each word trimmed (Unicode
## White_Space at both ends) and folded, the whole word ([code]Lenses[/code] is not one).
static func is_lens(element: Variant) -> bool:
	if not (element is Dictionary):
		return false
	var type = element.get("type")
	var supertype = element.get("supertype")
	if not (type is String and supertype is String):
		return false
	return OWUnicode.profile_fold(type) == PAIR_TYPE and OWUnicode.profile_fold(supertype) == OWUnicode.profile_fold(PAIR_SUPERTYPE)

## True when [param element] is a template: a lens whose subtype, trimmed and folded, is [code]Template[/code]. It
## resolves to nothing, anchors or not. Another Construct with that subtype is no template.
static func is_template(element: Variant) -> bool:
	if not is_lens(element):
		return false
	var subtype = element.get("subtype")
	return subtype is String and OWUnicode.profile_fold(subtype) == OWUnicode.profile_fold(TEMPLATE_SUBTYPE)

# -- the recipe ---------------------------------------------------------------------------------------------------------

## Null when [param x_lens] is legal, else the first key refused in the profile's table order ([code]depth[/code],
## [code]types[/code], [code]window[/code], [code]from[/code], [code]to[/code], [code]undated[/code],
## [code]show[/code], [code]budget[/code], [code]mail[/code], [code]notes[/code]), or [code]x_lens[/code] itself when
## the value is not an object. Absent and null are legal, a key whose value is null is absent, a key the profile does
## not name is ignored, and an empty string is present (never absent) and outside every table.
static func check_keys(x_lens: Variant) -> Variant:
	var read := _read_recipe(x_lens)
	return read.get("bad")

## The lenses a seat reads, by id: its membership's choice when it has made one (a list; an empty list is a choice),
## else its Character's [code]x_lens_uses[/code], else none. Never both: the membership wins. Strings only, each once,
## in the order given; a value that is not a list is no choice.
static func lenses_in_use(membership: Variant, x_lens_uses: Variant) -> PackedStringArray:
	var list: Variant = membership if _is_list(membership) else x_lens_uses
	var out := PackedStringArray()
	if not _is_list(list):
		return out
	for id in list:
		if (id is String or id is StringName) and String(id) != "" and not out.has(String(id)):
			out.append(String(id))
	return out

## A whole number as an int, or null: an int, or a float with no fraction, not NaN or infinite, inside the 64-bit
## range (7.0 reads as 7, as JavaScript and Python read it). A boolean, a string or anything else is not.
static func whole(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			if is_nan(v) or is_inf(v) or floor(v) != v or v >= _I64_EDGE or v < -_I64_EDGE:
				return null
			return int(v)
	return null

## The recipe read with its defaults, {"recipe": {...}}, or {"bad": key}: the first key outside the table.
static func _read_recipe(raw: Variant) -> Dictionary:
	if raw == null:
		raw = {}
	if not (raw is Dictionary):
		return {"bad": FIELD}
	var x: Dictionary = raw
	var depth_v: Variant = x.get("depth")
	var depth: Variant = DEFAULT_DEPTH if depth_v == null else whole(depth_v)
	if depth == null or depth < 0 or depth > 2:
		return {"bad": "depth"}
	var types_v: Variant = x.get("types")
	var types := {}
	if types_v != null:
		if not _is_list(types_v):
			return {"bad": "types"}
		for word in types_v:
			if not (word is String):
				return {"bad": "types"}
			var w := OWUnicode.profile_fold(word)
			if not (ROOM_PAIRS.has(w) if w.contains("/") else OWTypes.SCRIPTS.has(w)):
				return {"bad": "types"}
			types[w] = true
	var window_v: Variant = x.get("window")
	var from_v: Variant = x.get("from")
	var to_v: Variant = x.get("to")
	var window: Variant = null if window_v == null else whole(window_v)
	if window_v != null and (window == null or window < 0 or from_v != null or to_v != null):
		return {"bad": "window"}
	var from: Variant = null if from_v == null else whole(from_v)
	if from_v != null and from == null:
		return {"bad": "from"}
	var to: Variant = null if to_v == null else whole(to_v)
	if to_v != null and (to == null or from == null or to <= from):
		return {"bad": "to"}
	var undated_v: Variant = x.get("undated")
	if undated_v != null and not _is_one_of(undated_v, _UNDATED):
		return {"bad": "undated"}
	var show_v: Variant = x.get("show")
	if show_v != null and not _is_one_of(show_v, _SHOW):
		return {"bad": "show"}
	var budget_v: Variant = x.get("budget")
	var budget: Variant = DEFAULT_BUDGET if budget_v == null else whole(budget_v)
	if budget == null or budget < 1 or budget > 1000:
		return {"bad": "budget"}
	var mail_v: Variant = x.get("mail")
	if mail_v != null and not _is_one_of(mail_v, _MAIL):
		return {"bad": "mail"}
	var notes_v: Variant = x.get("notes")
	if notes_v != null:
		if not (notes_v is Dictionary):
			return {"bad": "notes"}
		for k in notes_v:
			if not (notes_v[k] is String):
				return {"bad": "notes"}
	return {"recipe": {
		"depth": depth, "types": types, "window": window, "from": from, "to": to,
		"undated": DEFAULT_UNDATED if undated_v == null else undated_v,
		"show": DEFAULT_SHOW if show_v == null else show_v,
		"budget": budget,
		"mail": DEFAULT_MAIL if mail_v == null else mail_v,
		"notes": {} if notes_v == null else notes_v,
	}}

static func _is_list(v: Variant) -> bool:
	return v is Array or v is PackedStringArray

static func _is_one_of(v: Variant, words: Array) -> bool:
	return v is String and words.has(v)
