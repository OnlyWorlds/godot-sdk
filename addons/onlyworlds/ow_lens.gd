class_name OWLens
extends RefCounted
## The lens profile (schema-dist [code]profiles/lens.md[/code], serial 82, its graph section serial 81): a saved way of
## reading a world. A lens is a Construct with supertype [code]Lens[/code]; its links are its anchors, and
## [code]x_lens[/code] is the recipe (how far, which types, how far back, how recently changed, how much).
##
## [method is_lens], [method is_template], [method check_keys] (the legal values of [code]x_lens[/code]),
## [method lenses_in_use] (where a seat's choice lives), [method resolve] (the one resolution every reader agrees on),
## [method date_of] (an element's date by the profile's table) and [method is_charter_element] (the room profile's
## reading aids). The npm and Python packages' [code]isLens[/code], [code]isTemplate[/code], [code]lensesInUse[/code],
## [code]resolveLens[/code], [code]dateOf[/code] and [code]isCharterElement[/code], ported from npm 4.98.0, with keel's
## reader where it reads otherwise; the fixture beside the profile is this file's test, and [OWGraph] reads the graph
## section through it.
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
## The room profile's mark: a room element carries it beside its pair.
const ROOM_MARK := "x_room_of"
## The reading aids' pairs (the room profile: the world's charter, its guide, its domains), written as
## [code]types[/code] names them, beside the room pairs.
const READING_AID_PAIRS := ["law/charter", "construct/guide", "construct/domain"]
## The reading aid's mark: the id of the world the aid belongs to.
const READING_AID_MARK := "x_charter_of"

## Why an element was left out: the profile's one closed list, in its order.
const CUT_REASONS := ["budget", "types", "window", "stale", "undated", "after_as_of", "anchor_not_visible",
	"not_visible", "hops_not_served"]
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

## The date table: each dated type's date field. The ten types not in it are timeless and never fenced. The fence,
## [code]undated[/code], [code]window[/code], [code]from[/code] and [code]to[/code] all read it, and so does
## [method date_of]. A constant Dictionary: read-only.
const DATE_FIELD := {
	"character": "birth_date", "creature": "birth_date", "institution": "founding_date", "location": "founding_date",
	"collective": "formation_date", "law": "date", "title": "grant_date", "construct": "start_date",
	"event": "start_date", "narrative": "start_date", "relation": "start_date", "zone": "start_date",
}

## What a known-of stub serves beside its type's public fields (never a link, never a date).
const STUB_FIELDS := ["id", "type", "name", "description", "supertype", "subtype", "image_url", "created_at", "updated_at"]
## The fields the platform shows on a stub beside those (schema-dist presentation.json [code]types.<type>.public[/code];
## held equal to it by the tests). A type not named here has none.
const PUBLIC_FIELDS := {"character": ["physicality", "height", "weight", "species", "reputation"]}

## The readers' four rungs.
const RUNGS := ["owner", "contributor", "guest", "public"]

const _MAIL_MICROS := 30 * 86400 * 1000000
const _OPTION_KEYS := ["as_of", "clock"]

static var _link_table := {}
static var _rank := {}
static var _date_time: RegEx

## What [method resolve] answers. [member error] is "" unless the call itself was a mistake (a world without an
## elements list, a rung outside the four, an option it does not know): then it names the mistake and nothing is read.
class Reading:
	## The kept elements' ids, in the profile's order: anchors first in the lens's link order, then what the hop reached.
	var kept := PackedStringArray()
	## The kept elements as [code]show[/code] makes them, in the same order; an anchor's row carries its [code]note[/code].
	var rows := []
	## The cut, counted by reason in the profile's order; a reason with no count is absent, and a reader that is not
	## the owner never carries the owner's two.
	var cut := {}
	## Notes on ids that are not anchors of the lens read, counted only where the reader sees the id.
	var notes_ignored := 0
	## The mail part when the lens names a mail rule ({unread, read, rows, cut, totals}); null otherwise.
	var mail: Variant = null
	## The first x_lens key outside the profile's table (x_lens itself when it is not an object): nothing resolved.
	var unreadable: Variant = null
	var error := ""

	## The reading in the fixture's shape.
	func to_dict() -> Dictionary:
		return {"kept": Array(kept), "rows": rows, "cut": cut, "notes_ignored": notes_ignored, "mail": mail,
			"unreadable": unreadable}

## Resolve [param lens] for one [param reader] over a world snapshot (the profile's [code]resolveLens[/code]): the kept
## elements in the profile's order, the cut counted by reason, and, when the lens names a mail rule, the mail part.
## Pure: it never writes, and nothing in the world moves.
##
## [param world] is a Dictionary: [code]elements[/code] (the bodies as the owner is served them), and optionally
## [code]hidden[/code] (ids the hidden mark keeps, beside each element's own [code]hidden[/code]),
## [code]members[/code] (the members list, which proves a message's sender) and the world's now ([code]now[/code], else
## [code]time_current[/code] as a folder spells it, else [code]time_range_current[/code] as the API serves it).
## [param lens] is a lens body or the id of a lens the reader is served whole. [param reader] is a Dictionary:
## [code]rung[/code] (owner, contributor, guest or public), [code]character[/code] (for the mail rule), a guest's
## [code]whole[/code] and [code]known_of[/code], and on an owner [code]as[/code] (another reader: its view, the
## owner's two counts). [param options]: [code]as_of[/code] (the reading's date, a whole number in the world's unit;
## absent: the world's now; none: no fence and the window cuts nothing) and [code]clock[/code] (the reading's wall
## clock, a date-time, for the mail rule's thirty days and [code]changed_within[/code]; absent: the machine's time).
static func resolve(world: Variant, lens: Variant, reader: Variant, options: Variant = null) -> Reading:
	var out := Reading.new()
	if options == null:
		options = {}
	if not (options is Dictionary):
		return _mistake(out, "resolve: options is a Dictionary, such as {\"as_of\": 1200}")
	for k in options:
		if not _OPTION_KEYS.has(k):
			return _mistake(out, "resolve: options holds as_of and clock; got %s" % k)
	if not (world is Dictionary and world.get("elements") is Array):
		return _mistake(out, "resolve: world is a Dictionary with an elements Array")
	var bad := _check_reader(reader, "resolve: reader")
	if bad != "":
		return _mistake(out, bad)
	var as_of_v: Variant = options.get("as_of")
	if as_of_v != null and whole(as_of_v) == null:
		return _mistake(out, "resolve: as_of is a whole number; got %s" % var_to_str(as_of_v))
	var clock_v: Variant = options.get("clock")
	if clock_v != null and time_key(clock_v) == null:
		return _mistake(out, "resolve: clock is a date-time; got %s" % var_to_str(clock_v))
	if not (lens is String or lens is Dictionary):
		return _mistake(out, "resolve: lens is a lens body or its id")
	var as_of: Variant = whole(as_of_v) if as_of_v != null else _world_now(world)
	return _lens_reading(View.new(world, reader, as_of), lens, clock_v)[0]

## The world's now: [code]now[/code], else [code]time_current[/code], else [code]time_range_current[/code], each read
## only when it is a whole number; null when none is.
static func _world_now(world: Dictionary) -> Variant:
	for key in ["now", "time_current", "time_range_current"]:
		var n: Variant = whole(world.get(key))
		if n != null:
			return n
	return null

static func _check_reader(reader: Variant, where: String) -> String:
	if not (reader is Dictionary and RUNGS.has(reader.get("rung"))):
		return "%s: a reader is a Dictionary whose rung is owner, contributor, guest or public; got %s" % [where, var_to_str(reader)]
	if reader.get("as") != null:
		return _check_reader(reader["as"], where + ".as")
	return ""

static func _mistake(out: Reading, message: String) -> Reading:
	out.error = message
	return out

## A lens read over one reader's view: [the Reading, each cut id's reason before the counts drop the owner's two].
static func _lens_reading(r: View, lens: Variant, clock_v: Variant) -> Array:
	var reading := Reading.new()
	var body: Variant = null
	# A lens named by id is read from the body this reader is served: a stub serves no links and no recipe.
	if lens is String:
		body = r.by_id[lens] if r.view.has(lens) and not r.stubs.has(lens) else null
	else:
		body = lens
	if body == null or not is_lens(body):
		return [reading, {}]
	var read := _read_recipe(body.get(FIELD))
	if not read.has("recipe"):
		reading.unreadable = read["bad"]
		return [reading, {}]
	if is_template(body):
		return [reading, {}]
	var recipe: Dictionary = read["recipe"]

	# The reading's wall clock, read once: the mail rule's thirty days and changed_within both measure from it.
	var wall: int = time_key(clock_v if clock_v != null else Time.get_datetime_string_from_system(true))
	var visited := {}
	if body.get("id") is String:
		visited[body["id"]] = true
	var resolved := _resolve_one(body, recipe, r, visited, wall)
	if recipe["mail"] != "none":
		reading.mail = _mail_part(r, recipe["mail"], recipe["budget"], wall)
	var in_mail := {}
	if reading.mail != null:
		for id in reading.mail["unread"] + reading.mail["read"]:
			in_mail[id] = true

	var seen := {}
	var union := []
	for e in resolved["list"]:
		if seen.has(e[0]) or visited.has(e[0]) or in_mail.has(e[0]):
			continue
		seen[e[0]] = true
		union.append(e)
	var budget: int = recipe["budget"]
	var keep := union.slice(0, budget)
	var cut: Dictionary = resolved["cut"]
	for e in union.slice(budget):
		cut[e[0]] = "budget"
	for e in keep:
		cut.erase(e[0])
	for id in visited:
		cut.erase(id)
	for why in CUT_REASONS:
		if OWNER_ONLY.has(why) and not r.owner:
			continue
		var n := 0
		for id in cut:
			if cut[id] == why:
				n += 1
		if n > 0:
			reading.cut[why] = n
	# A note on an id that is not an anchor is counted only where the reader sees that id: a note keyed to an element
	# it cannot see, or to no element, is no note of its, and counting it would tell a guest it exists.
	var anchors: Array = _anchors_of(body, r)["anchors"]
	for k in recipe["notes"]:
		if not anchors.has(k) and r.view.has(k):
			reading.notes_ignored += 1
	for e in keep:
		reading.kept.append(e[0])
		reading.rows.append(e[1])
	return [reading, cut]

## The anchors and the umbrella's children of a lens in its link order, and whether it names any (an anchor field with
## an entry, or x_served_trimmed naming one: such a lens is never read as a filter). A child is a lens in
## [code]constructs[/code] the reader is served whole; one it knows only as a stub serves no recipe and no links, so it
## is an anchor the reader cannot see ([code]unseen[/code]), never entered.
static func _anchors_of(lens: Dictionary, r: View) -> Dictionary:
	var anchors := []
	var children := []
	var unseen := {}
	var seen := {}
	for field in ANCHOR_FIELDS:
		var v: Variant = lens.get(field)
		if not (v is Array):
			continue
		for id in v:
			if not (id is String) or id == "" or seen.has(id):
				continue
			seen[id] = true
			if field == "constructs" and r.view.has(id) and is_lens(r.by_id[id]):
				if not r.stubs.has(id):
					children.append(id)
					continue
				unseen[id] = true
			anchors.append(id)
	var trimmed := false
	var mark: Variant = lens.get("x_served_trimmed")
	if mark is Array:
		for f in mark:
			if f is String and ANCHOR_FIELDS.has(f):
				trimmed = true
	return {"anchors": anchors, "children": children, "unseen": unseen, "anchored": not seen.is_empty() or trimmed}

## One lens by its own recipe, its children entered once each through the shared visited set: {list: [[id, row]...],
## cut: id -> its first reason}. An anchor is kept and followed whatever types, window and changed_within say (a
## reading aid too; a room element is kept and not followed); what a hop or a filter reaches is cut by the fence, then
## types, then the window, then changed_within, against [param wall], the reading's wall clock.
static func _resolve_one(lens: Dictionary, recipe: Dictionary, r: View, visited: Dictionary, wall: int) -> Dictionary:
	var cut := {}
	var a := _anchors_of(lens, r)
	var anchor_set := {}
	for id in a["anchors"]:
		anchor_set[id] = true
	var child_set := {}
	for id in a["children"]:
		child_set[id] = true
	var list := []
	var frontier := []
	for id in a["anchors"]:
		if visited.has(id) or not r.by_id.has(id):
			continue
		if not r.view.has(id) or a["unseen"].has(id):
			_add_cut(cut, id, "anchor_not_visible")
			continue
		var why: Variant = r.fence_cut(id, recipe)
		# Nothing past the reading's date leads anywhere: an anchor cut after_as_of is not hopped out of.
		if not r.after_as_of(id):
			frontier.append(id)
		if why != null:
			_add_cut(cut, id, why)
		else:
			list.append(id)
	var passes := func(id: String) -> bool:
		var why: Variant = r.fence_cut(id, recipe)
		if why == null and not r.keeps(id, recipe):
			why = "types"
		if why == null:
			why = r.window_cut(id, recipe)
		if why == null:
			why = r.stale_cut(id, recipe, wall)
		if why != null:
			_add_cut(cut, id, why)
		return why == null
	if not a["anchored"]:
		# A filter: every element of its types the reader can see; others are not selected and not counted.
		var selected := []
		for id in r.order:
			if r.view.has(id) and not visited.has(id) and r.keeps(id, recipe):
				selected.append(id)
		list.append_array(r.sort(selected.filter(passes)))
	elif recipe["depth"] >= 1:
		var excluded := func(id: String) -> bool: return anchor_set.has(id) or child_set.has(id) or visited.has(id)
		var reach := r.reach(frontier, excluded)
		var hop: Dictionary = reach[0]
		list.append_array(r.sort(hop.keys().filter(passes)))
		if r.owner:
			for id in r.unseen(frontier, reach[1], excluded):
				_add_cut(cut, id, "not_visible")
		if recipe["depth"] == 2:
			var past := func(id: String) -> bool: return excluded.call(id) or hop.has(id)
			var stops := func(id: String) -> bool: return r.stops_at(id, recipe) or r.after_as_of(id)
			# A room element or a reading aid that types would not keep is no hop the lens would serve: never counted.
			for id in r.reach(hop.keys(), past, stops)[0]:
				if not (r.room.has(id) or r.aid.has(id)) or r.keeps(id, recipe):
					_add_cut(cut, id, "hops_not_served")
	var out := []
	for id in list:
		out.append([id, r.row(id, recipe["show"], recipe["notes"] if anchor_set.has(id) else null)])
	for child in a["children"]:
		if visited.has(child):
			continue
		visited[child] = true
		var body: Dictionary = r.by_id[child]
		var read := _read_recipe(body.get(FIELD))
		if not read.has("recipe") or is_template(body):
			continue
		var sub := _resolve_one(body, read["recipe"], r, visited, wall)
		out.append_array(sub["list"])
		for id in sub["cut"]:
			_add_cut(cut, id, sub["cut"][id])
	return {"list": out, "cut": cut}

static func _add_cut(cut: Dictionary, id: String, why: String) -> void:
	if not cut.has(id):
		cut[id] = why

## The mail rule, through the message profile's readers over the reader's view: the messages addressed to its Character
## and not its own, thirty days on created_at before the clock, the newest kept up to the budget.
static func _mail_part(r: View, mode: String, budget: int, clock: int) -> Dictionary:
	var part := {"unread": [], "read": [], "rows": [], "cut": {}, "totals": {"unread": 0, "read": 0}}
	if r.character == null:
		return part
	var messages := []
	var relations := []
	for id in r.order:
		if not r.view.has(id):
			continue
		var b := r.body(id)
		# Whole bodies only: a known-of stub serves no characters, so its recipients are unknown, never everyone.
		if _is_message(b) and not r.stubs.has(id):
			messages.append(b)
		if r.type_of[id] == "relation":
			relations.append(b)
	var mark: Variant = _read_mark_of(relations, r.character, r.members)
	var mine := _unread_for(messages, r.character, null, r.members)
	var unread := {}
	for m in _unread_for(messages, r.character, mark, r.members):
		unread[m.get("id")] = true
	var lower := clock - _MAIL_MICROS
	var in_window := []
	for m in mine:
		var at: Variant = time_key(m.get("created_at"))
		if at != null and at >= lower:
			in_window.append(m)
	var kept := in_window.slice(maxi(0, in_window.size() - budget))
	if in_window.size() > kept.size():
		part["cut"]["budget"] = in_window.size() - kept.size()
	if mine.size() > in_window.size():
		part["cut"]["window"] = mine.size() - in_window.size()
	for m in kept:
		var is_unread := unread.has(m.get("id"))
		part["unread" if is_unread else "read"].append(m.get("id"))
		if mode == "all" or is_unread:
			part["rows"].append(m.duplicate(true))
		else:
			part["rows"].append({"id": m.get("id"), "name": m.get("name"), "narrator": m.get("narrator"),
				"created_at": m.get("created_at")})
	part["totals"] = {"unread": unread.size(), "read": mine.size() - unread.size()}
	return part

# -- the message profile's readers the mail rule reads (the npm SDK's message.ts, ported for the lens alone) -----------

static func _matches_pair(el: Variant, type: String, supertype: String) -> bool:
	if not (el is Dictionary and el.get("type") is String and el.get("supertype") is String):
		return false
	return OWUnicode.profile_fold(el["type"]) == type and OWUnicode.profile_fold(el["supertype"]) == OWUnicode.profile_fold(supertype)

static func _is_message(el: Variant) -> bool:
	return _matches_pair(el, "narrative", "Message")

static func _is_note(el: Variant) -> bool:
	return _matches_pair(el, "narrative", "Note")

## Two JSON values the same: the same type and equal (a membership id is a string, or null for the owner).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

## The Character a membership plays on the members list (its row by id, null the owner's), or null.
static func _character_of(membership: Variant, members: Variant) -> Variant:
	if not (members is Array):
		return null
	for row in members:
		if row is Dictionary and row.has("id") and _same(row["id"], membership):
			var c: Variant = row.get("character")
			return c if c is String and c != "" else null
	return null

## The Character of the hand that wrote a body: its created_by on the members list; null with no created_by key.
static func _hand_of(body: Dictionary, members: Variant) -> Variant:
	return _character_of(body["created_by"], members) if body.has("created_by") else null

static func _has_unseen_recipients(m: Dictionary) -> bool:
	if _is_note(m):
		return false
	var mark: Variant = m.get("x_served_trimmed")
	return mark is Array and mark.has("characters")

static func _is_to_everyone(m: Dictionary) -> bool:
	if _is_note(m) or _has_unseen_recipients(m):
		return false
	var list: Variant = m.get("characters")
	return list == null or (list is Array and list.is_empty())

static func _is_addressed_to(m: Variant, character: String) -> bool:
	if not (m is Dictionary) or _is_note(m) or character == "":
		return false
	if _is_to_everyone(m):
		return true
	var list: Variant = m.get("characters")
	return list is Array and list.has(character)

## The message's sender is the Character, proved: no created_by key trusts the narrator (a folder, an export); with
## one, the author's Character on the members list must be the narrator and the Character.
static func _is_own_hand(m: Dictionary, character: String, members: Variant) -> bool:
	var narrator: Variant = m.get("narrator")
	if not m.has("created_by"):
		return narrator is String and narrator == character
	if not (narrator is String) or narrator == "":
		return false
	var hand: Variant = _hand_of(m, members)
	return hand != null and hand == narrator and narrator == character

## The reader's read mark among the Relations: a Relation with supertype Read whose actor is the reader, in its own hand
## (created_by its Character; changed_by, when carried, equal to created_by); the newest updated_at of those that count.
static func _read_mark_of(relations: Array, character: String, members: Variant) -> Variant:
	var mark: Variant = null
	var mark_key: Variant = null
	for rel in relations:
		if not _matches_pair(rel, "relation", "Read") or not (rel.get("actor") is String and rel["actor"] == character):
			continue
		var has_author: bool = rel.has("created_by")
		if rel.has("changed_by") and (not has_author or not _same(rel["changed_by"], rel["created_by"])):
			continue
		if has_author and _hand_of(rel, members) != character:
			continue
		var key: Variant = time_key(rel.get("updated_at"))
		if mark == null or (key != null and (mark_key == null or key > mark_key)):
			mark = rel
			mark_key = key
	return mark

## The messages addressed to the Character, not its own, not on its read mark, in created_at order.
static func _unread_for(messages: Array, character: String, read_mark: Variant, members: Variant) -> Array:
	var read := {}
	if read_mark is Dictionary and read_mark.get("narratives") is Array:
		for id in read_mark["narratives"]:
			if id is String:
				read[id] = true
	var out := []
	for m in messages:
		if m is Dictionary and _is_addressed_to(m, character) and not _is_own_hand(m, character, members) \
				and not read.has(m.get("id")):
			out.append(m)
	return _in_created_order(out)

## By created_at; equal times keep the input's order; unreadable times last, in the input's order. Never by id.
static func _in_created_order(items: Array) -> Array:
	var keyed := []
	for i in items.size():
		keyed.append([items[i], i, time_key(items[i].get("created_at"))])
	keyed.sort_custom(func(a, b) -> bool:
		if a[2] != null and b[2] != null:
			return a[2] < b[2] if a[2] != b[2] else a[1] < b[1]
		if a[2] != null:
			return true
		if b[2] != null:
			return false
		return a[1] < b[1])
	return keyed.map(func(e): return e[0])

## A time as microseconds since 1970-01-01 UTC, or null when unreadable: the profiles' RFC 3339 rule
## ([code]YYYY-MM-DDTHH:MM:SS[/code], an optional fraction (microseconds kept), then [code]Z[/code],
## [code]+HH:MM[/code], [code]-HH:MM[/code] or nothing, read as UTC; [code]T[/code] and [code]Z[/code] in either case;
## the date must exist; ASCII digits only, the whole string, nothing trimmed), as the npm and Python packages read it.
static func time_key(value: Variant) -> Variant:
	if not (value is String):
		return null
	if _date_time == null:
		_date_time = RegEx.create_from_string("^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.([0-9]+))?(?:[Zz]|([+-])([0-9]{2}):([0-9]{2}))?\\z")
	var m := _date_time.search(value)
	if m == null:
		return null
	var y := m.get_string(1).to_int()
	var mo := m.get_string(2).to_int()
	var d := m.get_string(3).to_int()
	var h := m.get_string(4).to_int()
	var mi := m.get_string(5).to_int()
	var s := m.get_string(6).to_int()
	var leap := y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
	var days_in := [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if mo < 1 or mo > 12 or d < 1 or d > days_in[mo - 1] or h > 23 or mi > 59 or s > 59:
		return null
	var offset := 0
	if m.get_start(8) >= 0:
		var oh := m.get_string(9).to_int()
		var om := m.get_string(10).to_int()
		if oh > 23 or om > 59:
			return null
		offset = (oh * 3600 + om * 60) * (-1 if m.get_string(8) == "-" else 1)
	var micros := (m.get_string(7) + "000000").substr(0, 6).to_int() if m.get_start(7) >= 0 else 0
	return (_days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + s - offset) * 1000000 + micros

## When an element last changed, as changed_within reads it: the newer of a folder element's server_updated_at and
## local_updated_at where either reads as a time, else its updated_at; null when none reads as one.
static func _changed_at(el: Dictionary) -> Variant:
	var at: Variant = null
	for key in ["server_updated_at", "local_updated_at"]:
		var k: Variant = time_key(el.get(key))
		if k != null and (at == null or k > at):
			at = k
	return at if at != null else time_key(el.get("updated_at"))

## Days from 1970-01-01 to a proleptic Gregorian date (exact integer arithmetic, years 0000-9999).
static func _days_from_civil(y: int, m: int, d: int) -> int:
	var yy := y - 1 if m <= 2 else y
	var era := _floor_div(yy, 400)
	var yoe := yy - era * 400
	var doy := _floor_div(153 * (m + (-3 if m > 2 else 9)) + 2, 5) + d - 1
	var doe := yoe * 365 + _floor_div(yoe, 4) - _floor_div(yoe, 100) + doy
	return era * 146097 + doe - 719468

static func _floor_div(a: int, b: int) -> int:
	var q := a / b
	return q - 1 if (a % b != 0) and ((a < 0) != (b < 0)) else q

# -- the room profile's matcher and the schema's links ------------------------------------------------------------------

## A room element: its type and supertype, trimmed and folded, one of the room profile's pairs, and the mark
## [code]x_room_of[/code], counted by presence as the reading aid's is ([method _has_mark]). Both, always.
static func _is_room_element(el: Dictionary) -> bool:
	var type: Variant = el.get("type")
	var supertype: Variant = el.get("supertype")
	if not (type is String and supertype is String) or not _has_mark(el, ROOM_MARK):
		return false
	return ROOM_PAIRS.has(OWUnicode.profile_fold(type) + "/" + OWUnicode.profile_fold(supertype))

## The reading aid's pair word ([code]law/charter[/code], [code]construct/guide[/code] or
## [code]construct/domain[/code], folded) when [param element] is one, else "" (the lens and graph readers read it).
static func _reading_aid_key(element: Variant) -> String:
	if not (element is Dictionary and element.get("type") is String and element.get("supertype") is String):
		return ""
	var key := OWUnicode.profile_fold(element["type"]) + "/" + OWUnicode.profile_fold(element["supertype"])
	return key if READING_AID_PAIRS.has(key) and _has_mark(element, READING_AID_MARK) else ""

## A mark counts by presence: any value but null, and a string only when something is left after trimming Unicode's
## White_Space. The value is never compared.
static func _has_mark(el: Dictionary, field: String) -> bool:
	if not el.has(field) or el[field] == null:
		return false
	var v: Variant = el[field]
	return not (v is String) or OWUnicode.trim_white_space(v) != ""

## True when [param element] is a reading aid (schema-dist [code]profiles/room.md[/code], [code]profiles/lens.md[/code]
## rule 4): the world's charter ([code]law[/code], supertype [code]Charter[/code]), its guide ([code]construct[/code],
## supertype [code]Guide[/code]) or one of its domains ([code]construct[/code], supertype [code]Domain[/code]), the type
## and supertype each trimmed and folded, the whole word, AND the mark [code]x_charter_of[/code] (the id of the world the
## aid belongs to). The mark counts when present and not null; a string mark only when something is left after
## trimming. Both, always: the pair without the mark is lore (a kingdom's Charter in a novel's world is a Law like any
## other). A reading aid is not a room element. A lore view leaves it out by default; in a lens, one a hop reaches is
## kept only when [code]types[/code] names its pair, and one the lens names as an anchor is kept and followed. The npm
## SDK's [code]isCharterElement[/code], the Python package's [code]is_charter_element[/code].
static func is_charter_element(element: Variant) -> bool:
	return _reading_aid_key(element) != ""

## A type's link fields in the schema's order, each [field, is_list], from the generated models (a generic link's id
## key is a single link, its type key text).
static func link_fields_of(type: String) -> Array:
	if _link_table.is_empty():
		for slug in OWTypes.SCRIPTS:
			var fields: Dictionary = OWTypes.SCRIPTS[slug].get_script_constant_map()["FIELDS"]
			var out := []
			for name in fields:
				var kind: String = fields[name][0]
				if kind == "multi":
					out.append([name, true])
				elif kind == "single" or (kind == "generic" and name.ends_with("_id")):
					out.append([name, false])
			_link_table[slug] = out
	return _link_table.get(type, [])

static func _type_rank(type: String) -> int:
	if _rank.is_empty():
		var slugs := OWTypes.slugs()
		for i in slugs.size():
			_rank[slugs[i]] = i
	return _rank[type]

## What one reader is served of a world: every element by id, what it sees, the bodies it is served, and the hop.
class View:
	var by_id := {}
	var type_of := {}
	var order := PackedStringArray()
	var view := {}
	var stubs := {}
	var room := {}
	## The reading aids (the charter, its guide, its domains: the pair and the mark), each id to its pair word.
	var aid := {}
	## The ids under the hidden mark: the world's hidden list and each element's own hidden.
	var hidden := {}
	## The ids written as proposed, which no reader's view holds.
	var proposed := {}
	## The rung whose view is read: the reader's own, or on an owner the rung of the reader it reads as.
	var seen_rung := ""
	var owner := false
	var character: Variant = null
	var members: Variant = null
	var as_of: Variant = null
	var _served := {}
	var _full := {}
	var _in_view := {}
	var _in_full := {}

	func _init(world: Dictionary, reader: Dictionary, p_as_of: Variant) -> void:
		var listed_hidden: Variant = world.get("hidden")
		if listed_hidden is Array:
			for id in listed_hidden:
				if id is String:
					hidden[id] = true
		for el in world["elements"]:
			if not (el is Dictionary) or not (el.get("id") is String) or el["id"] == "" or by_id.has(el["id"]):
				continue
			var type: String = OWUnicode.profile_fold(el["type"]) if el.get("type") is String else ""
			if not OWTypes.SCRIPTS.has(type):
				continue
			var id: String = el["id"]
			by_id[id] = el
			type_of[id] = type
			order.append(id)
			var mark: Variant = el.get("hidden")
			if mark != null and not (mark is bool and mark == false):
				hidden[id] = true
			if OWLens._is_room_element(el):
				room[id] = true
			var aid_key := OWLens._reading_aid_key(el)
			if aid_key != "":
				aid[id] = aid_key
		owner = reader["rung"] == "owner"
		var seen: Dictionary = reader["as"] if owner and reader.get("as") != null else reader
		seen_rung = seen["rung"]
		var c: Variant = seen.get("character")
		character = c if c is String and c != "" else null
		var whole_ids := _listed(seen.get("whole"))
		var known_of := _listed(seen.get("known_of"))
		for id in order:
			if by_id[id].get("x_review_proposed") != null:
				proposed[id] = true
				continue
			var sees := false
			match seen_rung:
				"owner":
					sees = true
				"contributor":
					sees = not hidden.has(id)
				"public":
					sees = not hidden.has(id) and not room.has(id)
				_:
					sees = whole_ids.has(id) or known_of.has(id)
					if not whole_ids.has(id) and known_of.has(id):
						stubs[id] = true
			if sees:
				view[id] = true
		members = world["members"] if world.get("members") is Array else null
		as_of = p_as_of
		for id in order:
			for t in full_links(id):
				if by_id.has(t):
					if not _in_full.has(t):
						_in_full[t] = []
					_in_full[t].append(id)
			if not view.has(id):
				continue
			for t in links(id):
				if not _in_view.has(t):
					_in_view[t] = []
				_in_view[t].append(id)

	static func _listed(v: Variant) -> Dictionary:
		var out := {}
		if v is Array or v is PackedStringArray:
			for i in v:
				if i is String:
					out[i] = true
		return out

	## The ids the element's owner-served body links to, in the schema's field order, each once.
	func full_links(id: String) -> PackedStringArray:
		if _full.has(id):
			return _full[id]
		var el: Dictionary = by_id[id]
		var out := PackedStringArray()
		for lf in OWLens.link_fields_of(type_of[id]):
			var v: Variant = el.get(lf[0])
			for t in (v if v is Array else []) if lf[1] else [v]:
				if t is String and t != "" and not out.has(t):
					out.append(t)
		_full[id] = out
		return out

	## The ids the element's served body links to: its links inside the view; a stub carries none.
	func links(id: String) -> PackedStringArray:
		var out := PackedStringArray()
		if stubs.has(id):
			return out
		for t in full_links(id):
			if view.has(t):
				out.append(t)
		return out

	## The body this reader is served, a copy: a stub for a known-of element, the links outside the view left out (and
	## named in x_served_trimmed on a message or a lens).
	func body(id: String) -> Dictionary:
		if _served.has(id):
			return _served[id]
		var el: Dictionary = by_id[id]
		var type: String = type_of[id]
		var b := {}
		if stubs.has(id):
			var link_names := {}
			for lf in OWLens.link_fields_of(type):
				link_names[lf[0]] = true
			var keep := {}
			for f in OWLens.STUB_FIELDS:
				keep[f] = true
			for f in OWLens.PUBLIC_FIELDS.get(type, []):
				if not link_names.has(f):
					keep[f] = true
			for k in el:
				if keep.has(k):
					b[k] = el[k].duplicate(true) if el[k] is Dictionary or el[k] is Array else el[k]
			b["known_of"] = true
		else:
			b = el.duplicate(true)
			var trimmed := []
			for lf in OWLens.link_fields_of(type):
				var field: String = lf[0]
				if not b.has(field):
					continue
				var v: Variant = b[field]
				if lf[1]:
					if not (v is Array):
						continue
					var kept := []
					for t in v:
						if t is String:
							if view.has(t):
								kept.append(t)
							elif not trimmed.has(field):
								trimmed.append(field)
					b[field] = kept
				elif v is String and not view.has(v):
					b[field] = null
					trimmed.append(field)
			if not trimmed.is_empty() and (OWLens._is_message(b) or OWLens.is_lens(b)):
				var mark: Array = b["x_served_trimmed"].duplicate() if b.get("x_served_trimmed") is Array else []
				for f in trimmed:
					if not mark.has(f):
						mark.append(f)
				b["x_served_trimmed"] = mark
		_served[id] = b
		return b

	## One hop from each element of [param from], both ways, and on through each Relation it lands on to that
	## Relation's parties: [reached (an ordered set), the Relations crossed]. Nothing hops out of a stub or a room
	## element, nor out of an element [param stops] names.
	func reach(from: Array, excluded: Callable, stops: Callable = Callable()) -> Array:
		var landed := {}
		for f in from:
			if stubs.has(f) or room.has(f) or (stops.is_valid() and stops.call(f)):
				continue
			for t in links(f):
				if not excluded.call(t):
					landed[t] = true
			for t in _in_view.get(f, []):
				if not excluded.call(t):
					landed[t] = true
		var reached := landed.duplicate()
		var edges := []
		for r in landed:
			if type_of[r] != "relation" or stubs.has(r) or room.has(r):
				continue
			edges.append(r)
			for t in links(r):
				if not excluded.call(t):
					reached[t] = true
		return [reached, edges]

	## What one hop from [param from] would reach in the owner's world that this reader's view leaves out.
	func unseen(from: Array, landed_relations: Array, excluded: Callable) -> Array:
		var out := {}
		for f in from:
			if stubs.has(f) or room.has(f):
				continue
			for t in full_links(f):
				_consider(t, excluded, out)
			for t in _in_full.get(f, []):
				_consider(t, excluded, out)
		for r in landed_relations:
			for t in full_links(r):
				_consider(t, excluded, out)
		return out.keys()

	func _consider(t: String, excluded: Callable, out: Dictionary) -> void:
		if by_id.has(t) and not view.has(t) and not excluded.call(t):
			out[t] = true

	## The fence (keel's as_of, on the element's own date) and undated.
	func fence_cut(id: String, recipe: Dictionary) -> Variant:
		var field: Variant = OWLens.DATE_FIELD.get(type_of[id])
		if field == null:
			return null
		var d: Variant = OWLens.whole(by_id[id].get(field))
		if d == null:
			return "undated" if recipe["undated"] == "exclude" else null
		return "after_as_of" if as_of != null and d > as_of else null

	## Whether the element is dated after the reading's as_of: the fence cuts it, and nothing hops out of it (keel's
	## reader builds its frontier without it).
	func after_as_of(id: String) -> bool:
		var why: Variant = fence_cut(id, {"undated": OWLens.DEFAULT_UNDATED})
		return why is String and why == "after_as_of"

	## window, or from and to (closed-open). A to after as_of is clipped: the fence stays the upper edge.
	func window_cut(id: String, recipe: Dictionary) -> Variant:
		var field: Variant = OWLens.DATE_FIELD.get(type_of[id])
		if field == null:
			return null
		var d: Variant = OWLens.whole(by_id[id].get(field))
		if d == null:
			return null
		if recipe["window"] != null and as_of != null and d < as_of - recipe["window"]:
			return "window"
		if recipe["from"] != null and d < recipe["from"]:
			return "window"
		if recipe["to"] != null and d >= recipe["to"]:
			return "window"
		return null

	## changed_within: changed longer ago than that many days before the reading's wall clock. The time read is the
	## element's updated_at, or for a folder element (one carrying server_updated_at or local_updated_at) the newer of
	## those two; an element with no readable time is never cut.
	func stale_cut(id: String, recipe: Dictionary, wall: int) -> Variant:
		if recipe["changed_within"] == null:
			return null
		var at: Variant = OWLens._changed_at(by_id[id])
		if at == null:
			return null
		return "stale" if at < wall - recipe["changed_within"] * 86400 * 1000000 else null

	## Whether types keeps the element: a room element or a reading aid only when its pair is named, any other by its
	## type (or any type when types is empty).
	func keeps(id: String, recipe: Dictionary) -> bool:
		var types: Dictionary = recipe["types"]
		if room.has(id):
			var el: Dictionary = by_id[id]
			return types.has(OWUnicode.profile_fold(el["type"]) + "/" + OWUnicode.profile_fold(el["supertype"]))
		if aid.has(id):
			return types.has(aid[id])
		return types.is_empty() or types.has(type_of[id])

	## Rule 4: a reading aid a hop reached is not hopped out of unless types names its pair.
	func stops_at(id: String, recipe: Dictionary) -> bool:
		return aid.has(id) and not recipe["types"].has(aid[id])

	## Rule 5's order past the anchors: the schema's type order, newest updated_at first (an unreadable time last),
	## then by id by code point.
	func sort(ids: Array) -> Array:
		var keyed := []
		for id in ids:
			keyed.append([id, OWLens._type_rank(type_of[id]), OWLens.time_key(by_id[id].get("updated_at"))])
		keyed.sort_custom(func(a, b) -> bool:
			if a[1] != b[1]:
				return a[1] < b[1]
			if a[2] != null and b[2] != null:
				if a[2] != b[2]:
					return a[2] > b[2]
			elif a[2] != null:
				return true
			elif b[2] != null:
				return false
			return a[0] < b[0])
		return keyed.map(func(e): return e[0])

	func row(id: String, show: String, notes: Variant) -> Dictionary:
		var b := body(id)
		var out: Dictionary
		if show == "full":
			out = b.duplicate(true)
		else:
			out = {"id": b.get("id"), "type": b.get("type"), "name": b.get("name")}
			if show == "first_line" and b.get("description") is String:
				var text: String = b["description"]
				var cut := -1
				for i in text.length():
					var c := text.unicode_at(i)
					if c == 0x0A or c == 0x0D:
						cut = i
						break
				out["description"] = text if cut < 0 else text.substr(0, cut)
		if notes != null and notes.has(id):
			out["note"] = notes[id]
		return out

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

## An element's date as the lens profile reads it: the whole number ([method whole]) in its type's date field
## ([constant DATE_FIELD]), in the world's own time unit, as an int. Null for a timeless type, a body with no known
## [code]type[/code] (trimmed and folded), a date field that is absent, null or not a whole number, and anything that is
## not an element body. It reads the body it is given: a known-of stub serves no date, so it reads null. A timeline or
## a horizon can date elements by this exactly as the reader's fence does (the npm SDK's [code]dateOf[/code], the
## Python package's [code]date_of[/code]).
static func date_of(element: Variant) -> Variant:
	if not (element is Dictionary) or not (element.get("type") is String):
		return null
	var field: Variant = DATE_FIELD.get(OWUnicode.profile_fold(element["type"]))
	return null if field == null else whole(element.get(field))

# -- the recipe ---------------------------------------------------------------------------------------------------------

## Null when [param x_lens] is legal, else the first key refused in the profile's table order ([code]depth[/code],
## [code]types[/code], [code]window[/code], [code]from[/code], [code]to[/code], [code]undated[/code],
## [code]changed_within[/code], [code]show[/code], [code]budget[/code], [code]mail[/code], [code]notes[/code]), or
## [code]x_lens[/code] itself when
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
			if not (ROOM_PAIRS.has(w) or READING_AID_PAIRS.has(w) if w.contains("/") else OWTypes.SCRIPTS.has(w)):
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
	var changed_v: Variant = x.get("changed_within")
	var changed_within: Variant = null if changed_v == null else whole(changed_v)
	if changed_v != null and (changed_within == null or changed_within < 1):
		return {"bad": "changed_within"}
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
		"changed_within": changed_within,
		"show": DEFAULT_SHOW if show_v == null else show_v,
		"budget": budget,
		"mail": DEFAULT_MAIL if mail_v == null else mail_v,
		"notes": {} if notes_v == null else notes_v,
	}}

static func _is_list(v: Variant) -> bool:
	return v is Array or v is PackedStringArray

static func _is_one_of(v: Variant, words: Array) -> bool:
	return v is String and words.has(v)
