class_name OWCharter
extends RefCounted
## The charter profile (schema-dist [code]profiles/charter.md[/code], serial 83): a world's reading aids, what every
## front door shows first. The Charter (a Law with supertype [code]Charter[/code]: the rules here), the Guide (a
## Construct with supertype [code]Guide[/code]: start here) and the Domains (Constructs with supertype
## [code]Domain[/code]: the places in the world, each one sentence and the hub elements it links). An element is one
## when its pair, trimmed and folded as the room profile folds, AND the mark [code]x_charter_of[/code] both hold, the
## mark read by presence ([method is_charter_element]); the pair without the mark is lore.
##
## [method charter_of] is the packet [code]{charter, guide, domains}[/code] as one reader sees the world, and
## [method domains_of] the list alone: keel's [code]elements/charter.py[/code] ([code]reading_aids[/code], served beside
## [code]front_door[/code] on [code]GET /me[/code] and the join reply) is the reading this follows, the npm SDK's
## [code]charterOf[/code] and the Python package's [code]charter_of[/code] the same. The world and the reader are
## [method OWLens.resolve]'s, read through the same [OWLens.View], so a fixture reader means one thing in both. The
## fixture beside the profile is this file's test.

## The three pairs, type and supertype trimmed and folded, a slash between, as [OWLens] holds them.
const PAIRS := OWLens.READING_AID_PAIRS
## The mark every reading aid carries: the id of the world it was written for, read by presence.
const MARK := OWLens.READING_AID_MARK
## The Charter's rules a machine checks (the checks profile), served as stored.
const RULES_FIELD := "x_checks_rules"
## At most this many skill Objects on the Charter (keel's [code]charter_skill[/code], D152).
const SKILL_MAX := 5

static var _id_re: RegEx
static var _hub_fields := []

## What [method charter_of] answers. [member error] is "" unless the call itself was a mistake (a world without an
## elements list, a rung outside the four): then it names the mistake and nothing is read.
class Packet:
	## [code]{id, name, rules, skill}[/code], or null when the reader sees no marked Charter.
	var charter: Variant = null
	## [code]{id, name}[/code], or null when the reader sees no marked Guide.
	var guide: Variant = null
	## Each [code]{id, name, sentence, hubs}[/code], in the profile's order.
	var domains := []
	var error := ""

	## The packet in the profile's shape.
	func to_dict() -> Dictionary:
		return {"charter": charter, "guide": guide, "domains": domains}

## True when [param element] is a reading aid: [method OWLens.is_charter_element], the pair AND the mark.
static func is_charter_element(element: Variant) -> bool:
	return OWLens.is_charter_element(element)

## The world's reading aids as [param reader] sees them (the profile's [code]charterOf[/code]). Pure: nothing is
## stored or written.
##
## [param world] is what [method OWLens.resolve] takes: [code]elements[/code] (the bodies as the owner is served
## them), [code]hidden[/code] (the ids the hidden mark keeps), and [code]open[/code]: true for a world open to anyone.
## [param reader] is a lens reader ([code]rung[/code] owner, contributor, guest with its [code]whole[/code] and
## [code]known_of[/code], or public; on an owner, [code]as[/code]). A public reader of a world not open to anyone reads
## nothing.
##
## [code]charter[/code] is the newest marked Charter the reader sees (by [code]created_at[/code] as an instant, none
## or an unreadable one the oldest, then the higher id by code point): [code]rules[/code] its
## [code]x_checks_rules[/code] as stored ([code][][/code] when absent or null), [code]skill[/code] the ids its
## description names (any [code]ow://[/code] form, a site address or a bare id: every 8-4-4-4-12 hex run), lowercase,
## each once in the order written, kept when it is an Object of this world the reader sees, the first five kept. Its
## name, rules and text are read as stored: the Charter is every member rung's to read whole (D152), as keel reads its
## row. [code]guide[/code] the same among marked Guides, [code]{id, name}[/code]. [code]domains[/code] is every marked
## Domain the reader sees: first in the order of the Guide's [code]constructs[/code] as the reader is served them (an
## id named twice keeps its first place, an entry that is no marked Domain or one the reader cannot see is skipped),
## then the rest by folded name and then id. Each as the reader is served it: [code]sentence[/code] the description up
## to its first line break (a line feed or a carriage return), trimmed of White_Space; [code]hubs[/code] the distinct
## [code]{type, id}[/code] its link fields name, itself excluded, in the schema's field order; a stub serves no links,
## so a stub Domain has its name and sentence and no hubs. Whether an element is an aid is read from the element as
## the owner is served it, since a stub serves no mark.
static func charter_of(world: Variant, reader: Variant) -> Packet:
	var out := Packet.new()
	if not (world is Dictionary and world.get("elements") is Array):
		out.error = "charter_of: world is a Dictionary with an elements Array"
		return out
	var bad := OWLens._check_reader(reader, "charter_of: reader")
	if bad != "":
		out.error = bad
		return out
	var r := OWLens.View.new(world, reader, null)
	if r.seen_rung == "public" and world.get("open") != true:
		return out
	var law: Variant = _newest(r, _marked(r, "law/charter"))
	if law != null:
		var stored: Dictionary = r.by_id[law]
		var rules: Variant = stored.get(RULES_FIELD)
		out.charter = {"id": law, "name": _name(stored.get("name")),
			"rules": [] if rules == null else (rules.duplicate(true) if rules is Array or rules is Dictionary else rules),
			"skill": _skill(r, stored.get("description"))}
	var domains := _marked(r, "construct/domain")
	var order := []
	var guide: Variant = _newest(r, _marked(r, "construct/guide"))
	if guide != null:
		out.guide = {"id": guide, "name": _name(r.by_id[guide].get("name"))}
		var listed: Variant = r.body(guide).get("constructs")
		for i in (listed if listed is Array else []):
			if i is String and domains.has(i) and not order.has(i):
				order.append(i)
	var rest := domains.filter(func(d): return not order.has(d))
	rest.sort_custom(func(a: String, b: String) -> bool:
		var fa := OWUnicode.profile_fold(_name(r.by_id[a].get("name")))
		var fb := OWUnicode.profile_fold(_name(r.by_id[b].get("name")))
		return fa < fb if fa != fb else a < b)
	for d in order + rest:
		var body := r.body(d)
		out.domains.append({"id": d, "name": _name(body.get("name")), "sentence": first_line(body.get("description")),
			"hubs": [] if body.get("known_of") == true else _hubs(d, body)})
	return out

## The Domains alone, as [method charter_of] lists them for [param reader] (the profile's [code]domainsOf[/code]); an
## empty list on a caller's mistake.
static func domains_of(world: Variant, reader: Variant) -> Array:
	return charter_of(world, reader).domains

## A Domain's link fields in the schema's order, each [field, the type it links], from the generated Construct model.
static func hub_fields() -> Array:
	if _hub_fields.is_empty():
		var model: Script = OWTypes.SCRIPTS["construct"]
		var fields: Dictionary = model.get_script_constant_map()["FIELDS"]
		for name in fields:
			if fields[name][0] == "single" or fields[name][0] == "multi":
				_hub_fields.append([name, fields[name][1]])
	return _hub_fields

## The lens profile's first_line: the text trimmed of White_Space, up to its first line feed or carriage return,
## trimmed again; "" for anything that is not text.
static func first_line(text: Variant) -> String:
	if not (text is String):
		return ""
	var t := OWUnicode.trim_white_space(text)
	for i in t.length():
		var c := t.unicode_at(i)
		if c == 0x0A or c == 0x0D:
			return OWUnicode.trim_white_space(t.substr(0, i))
	return t

# -- the selection --------------------------------------------------------------------------------------------------

## The ids the reader sees whose owner-served body is the aid [param pair], in the world's order.
static func _marked(r: OWLens.View, pair: String) -> Array:
	var out := []
	for id in r.order:
		if r.view.has(id) and r.aid.get(id) == pair:
			out.append(id)
	return out

## The newest of [param ids] by created_at as an instant (none, or one that does not read as a time, sorts as the
## oldest), then the higher id by code point; null for none. So editing an aid never changes which one leads.
static func _newest(r: OWLens.View, ids: Array) -> Variant:
	var best: Variant = null
	var best_t: Variant = null
	for id in ids:
		var t: Variant = OWLens.time_key(r.by_id[id].get("created_at"))
		if best == null:
			best = id
			best_t = t
			continue
		var newer: bool
		if t != null and best_t != null:
			newer = t > best_t or (t == best_t and id > best)
		elif t != null:
			newer = true
		elif best_t != null:
			newer = false
		else:
			newer = id > best
		if newer:
			best = id
			best_t = t
	return best

## Keel's charter_skill: every id the text names, lowercase, each once in the order written, kept when it is an Object
## of this world the reader sees, the first SKILL_MAX of those kept.
static func _skill(r: OWLens.View, text: Variant) -> Array:
	if _id_re == null:
		_id_re = RegEx.create_from_string("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
	var objects := {}
	for id in r.order:
		if r.view.has(id) and r.type_of[id] == "object":
			objects[String(id).to_lower()] = true
	var found := []
	for m in _id_re.search_all(text if text is String else ""):
		var v := m.get_string().to_lower()
		if not found.has(v):
			found.append(v)
	return found.filter(func(i): return objects.has(i)).slice(0, SKILL_MAX)

## The distinct {type, id} a Domain's served body links, itself excluded, in the schema's field order and each list's
## own order.
static func _hubs(id: String, body: Dictionary) -> Array:
	var out := []
	var seen := {"construct/" + id: true}
	for hf in hub_fields():
		var v: Variant = body.get(hf[0])
		for t in (v if v is Array else [v]):
			if t is String and t != "" and not seen.has(hf[1] + "/" + t):
				seen[hf[1] + "/" + t] = true
				out.append({"type": hf[1], "id": t})
	return out

static func _name(v: Variant) -> String:
	return v if v is String else ""
