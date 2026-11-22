class_name OWJoin
extends RefCounted
## Joining a world by link, with no account: a player's code (a friend reading as one Character, a table's seat
## included) or an AI agent's, read with [method preview] and redeemed with [method redeem]. Neither sends a credential.
## A person's link is accepted signed in instead, [method OWClient.accept_join] on an account token.
##
## [codeblock]
## var code := OWJoin.parse_link(pasted)                         # "" when the text holds none
## var seen := await OWJoin.preview(code)
## if seen.ok and seen.value.reader == "player":
##     var joined := await OWJoin.redeem(code, {"name": "Ana"})
##     if joined.ok:
##         var reader := OWClient.new({"api_key": joined.value.key})   # a read key, no PIN: keep it, it is shown once
## [/codeblock]
##
## Static, beside [OWClient] rather than on it, as the Unity SDK's [code]OWJoin[/code] is: a client is built with a key,
## and joining is how a program gets one. The TypeScript SDK puts the same two calls on its client
## ([code]previewJoin[/code], [code]redeemJoin[/code]) and sends them with no credential whatever key it holds; the wire
## is the same. Each answers an [OWClient.Reply]: keel's refusals as an [OWApiError] of kind [constant OWApiError.API],
## a caller's mistake as one of kind [constant OWApiError.REFUSED] with nothing sent.
##
## A link is [code]<site>/join#<code>[/code], or [code]<site>/join/<world_id>#<code>[/code] when its owner turned the
## preview on: the code sits after [code]#[/code], so it never reaches a server log. Every bad code (unknown, used,
## revoked, expired, or for another reader) is the same 404 [code]not_found[/code], byte for byte:
## [method OWApiError.is_not_found]. A refusal never spends the code.

## Every join code starts with this.
const CODE_PREFIX := "ow_j_"
const DEFAULT_BASE_URL := OWClient.DEFAULT_BASE_URL
## Where the request goes, on both calls: [code]transport[/code] (an [OWTransport]; an [OWHttpTransport] when absent)
## and [code]base_url[/code] (keel's API root; [constant DEFAULT_BASE_URL] when absent).
const _WHERE_KEYS := ["transport", "base_url"]
## What [method redeem] sends beside the code, in the order keel's tests and the TypeScript SDK send it.
const _REDEEM_KEYS := ["name", "agent_name", "character"]

## A world, as a join code's answers name it.
class World:
	const KEYS := ["id", "name", "description"]
	## Null in a preview: the code is not spent, so the world's id is not handed out.
	var id: Variant = null
	var name := ""
	## Null when keel sends none.
	var description: Variant = null

	static func of(v: Variant) -> World:
		if not (v is Dictionary):
			return null
		var w := World.new()
		w.id = OWJoin._maybe(v, "id")
		w.name = OWJoin._string(v, "name")
		w.description = OWJoin._maybe(v, "description")
		return w

## A Character, by id and name, as a join answer names it.
class Character:
	const KEYS := ["id", "name"]
	var id := ""
	var name := ""

	static func of(v: Variant) -> Character:
		if not (v is Dictionary):
			return null
		var c := Character.new()
		c.id = OWJoin._string(v, "id")
		c.name = OWJoin._string(v, "name")
		return c

## One Character a party link offers, from its preview's [member Preview.characters]: the player picks one not
## [member taken] and sends its id to [method OWJoin.redeem] as [code]character[/code].
class Pick:
	const KEYS := ["id", "name", "image_url", "taken"]
	var id := ""
	var name := ""
	## The Character's picture, or null.
	var image_url: Variant = null
	## A live seat in the world plays it already, a person's included. keel's order puts these last.
	var taken := false

	static func of(v: Dictionary) -> Pick:
		var p := Pick.new()
		p.id = OWJoin._string(v, "id")
		p.name = OWJoin._string(v, "name")
		p.image_url = OWJoin._maybe(v, "image_url")
		p.taken = v.get("taken") == true
		return p

## An agent's seat in the world, from an agent code's answer.
class Seat:
	const KEYS := ["id", "role", "agent_name"]
	var id := ""
	var role := ""
	var agent_name := ""

	static func of(v: Variant) -> Seat:
		if not (v is Dictionary):
			return null
		var s := Seat.new()
		s.id = OWJoin._string(v, "id")
		s.role = OWJoin._string(v, "role")
		s.agent_name = OWJoin._string(v, "agent_name")
		return s

## One thing in a join preview's glimpse: its name and its element type ([code]character[/code],
## [code]location[/code], ...). It carries no id.
class GlimpseThing:
	const KEYS := ["name", "type"]
	var name := ""
	var type := ""

	func to_dict() -> Dictionary:
		return {"name": name, "type": type}

## One link in a join preview's glimpse, between two of its [member Glimpse.things].
class GlimpseLink:
	const KEYS := ["from", "to", "field", "label"]
	## The place in [member Glimpse.things], from 0, of the thing whose field holds the link; -1 when keel sent no whole
	## number.
	var from := -1
	## The place in [member Glimpse.things], from 0, of the thing linked to; -1 when keel sent no whole number.
	var to := -1
	## The name of the field that holds the link.
	var field := ""
	## The words to show for the link.
	var label := ""

	func to_dict() -> Dictionary:
		return {"from": from, "to": to, "field": field, "label": label}

## A join preview's [member Preview.glimpse] (the TypeScript SDK's [code]OwJoinGlimpse[/code]): up to five things of
## the world by name, and the links among them, read as a visitor with no account would read the world if it were
## public (nothing hidden, nothing proposed). It names no id.
class Glimpse:
	const KEYS := ["picked_by", "things", "links"]
	## How the things were chosen: [code]strand[/code], the world's chosen story (its happening, where it happened, its
	## hero and where the hero is now), or [code]links[/code], the most linked thing and the most linked of its
	## neighbours.
	var picked_by := ""
	## At most five [OWJoin.GlimpseThing], in the order [member picked_by] gives.
	var things: Array = []
	## The [OWJoin.GlimpseLink] among them.
	var links: Array = []

	static func of(v: Variant) -> Glimpse:
		if not (v is Dictionary):
			return null
		var g := Glimpse.new()
		g.picked_by = OWJoin._string(v, "picked_by")
		for x in OWJoin._rows(v, "things"):
			var thing := GlimpseThing.new()
			thing.name = OWJoin._string(x, "name")
			thing.type = OWJoin._string(x, "type")
			g.things.append(thing)
		for x in OWJoin._rows(v, "links"):
			var link := GlimpseLink.new()
			link.from = OWJoin._index(x.get("from"))
			link.to = OWJoin._index(x.get("to"))
			link.field = OWJoin._string(x, "field")
			link.label = OWJoin._string(x, "label")
			g.links.append(link)
		return g

	## The things are the world's chosen story.
	func is_strand() -> bool:
		return picked_by == "strand"

	## The things are the most linked thing and its most linked neighbours.
	func is_links() -> bool:
		return picked_by == "links"

	## The glimpse in keel's shape, key for key: [code]{picked_by, things, links}[/code].
	func to_dict() -> Dictionary:
		return {"picked_by": picked_by, "things": things.map(func(x): return x.to_dict()),
			"links": links.map(func(x): return x.to_dict())}

## [code]POST /join/preview[/code]'s answer: what a join code holds, without using it (keel's
## [code]preview_join[/code]; the TypeScript SDK's [code]OwJoinPreview[/code]).
class Preview:
	const KEYS := ["reader", "world", "invited_by", "owner_character", "role", "with_character", "expires_at", "note",
		"glimpse", "max_uses", "uses_left", "name_required", "characters"]
	## Who the code is for: [code]player[/code] (a friend with no account; [method OWJoin.redeem] gives a read key),
	## [code]agent[/code] (an AI agent; the same call gives a seat's write key and secret), or [code]person[/code] (a
	## signed-in account accepts it with [method OWClient.accept_join], not here).
	var reader := ""
	## Its [member World.id] is null: the code is not spent.
	var world: World = null
	## The name the inviter signed the link with, unchecked, or null.
	var invited_by: Variant = null
	## The owner's chosen Character's name, never a username; null when none is set.
	var owner_character: Variant = null
	## The role joining gives; always [code]guest[/code] for a player.
	var role := ""
	## Whether joining gives a Character: always true for a player, false for a person.
	var with_character := false
	## ISO 8601, UTC, as sent.
	var expires_at := ""
	## The note the inviter wrote on a person link, plain text with its line breaks: show it as text, never as markup.
	## Null when there is none, and always on an agent's or a player's link.
	var note: Variant = null
	## A glimpse of the world ([OWJoin.Glimpse]), for a link whose role reads it ([code]contributor[/code] or
	## [code]co_builder[/code]): up to five things by name and type and the links among them. Null for a guest's link,
	## and so for every player's, and when no two things a visitor could see are linked.
	var glimpse: Glimpse = null
	# A party link (a table: one link, up to 50 players) adds the four below; a link for one sends none of them.
	## How many players the link seats, 2 to 50 (an int); null on a link for one.
	var max_uses: Variant = null
	## How many places are left at the table (an int); null on a link for one.
	var uses_left: Variant = null
	## True when the table lists no Characters: redeem with a [code]name[/code] and no [code]character[/code], and the
	## player gets a fresh Character. Null on a link for one.
	var name_required: Variant = null
	## The [OWJoin.Pick]s, in the owner's order; empty when [member name_required], null on a link for one.
	var characters: Variant = null

	static func of(v: Dictionary) -> Preview:
		var p := Preview.new()
		p.reader = OWJoin._string(v, "reader")
		p.world = World.of(v.get("world"))
		p.invited_by = OWJoin._maybe(v, "invited_by")
		p.owner_character = OWJoin._maybe(v, "owner_character")
		p.role = OWJoin._string(v, "role")
		p.with_character = v.get("with_character") == true
		p.expires_at = OWJoin._string(v, "expires_at")
		p.note = OWJoin._maybe(v, "note")
		p.glimpse = Glimpse.of(v.get("glimpse"))
		p.max_uses = OWJoin._whole(v.get("max_uses"))
		p.uses_left = OWJoin._whole(v.get("uses_left"))
		p.name_required = v.get("name_required") if v.get("name_required") is bool else null
		if v.get("characters") is Array:
			p.characters = OWJoin._rows(v, "characters").map(func(x): return Pick.of(x))
		return p

	## A party link: more than one player joins by it, each as a picked or a fresh Character.
	func is_table() -> bool:
		return max_uses is int and max_uses > 1

## [code]POST /join[/code]'s answer, a player's or an agent's, told apart by [member kind] (the TypeScript SDK's
## [code]OwJoined[/code], one class here as in the Unity SDK). Shown once: the code is spent and a lost answer cannot be
## replayed, so keep [member key] (and an agent's [member pin]).
class Joined:
	const KEYS := ["kind", "key", "pin", "world", "character", "role", "seat", "base_url", "env", "front_door",
		"reading_aids"]
	## [code]player[/code] or [code]agent[/code].
	var kind := ""
	## A player's read key ([code]ow_r_[/code], no PIN), or an agent seat's write key.
	var key := ""
	## An agent seat's secret ([code]ow_s_[/code]), sent as [code]API-Pin[/code]; null for a player.
	var pin: Variant = null
	var world: World = null
	## The Character a player reads as; an agent's when its link gave one, else null.
	var character: Character = null
	## A player's role ([code]guest[/code]); null for an agent, whose role is on its [member seat]: read
	## [method role_in_world].
	var role: Variant = null
	## An agent's seat; null for a player.
	var seat: Seat = null
	## An agent's: the API's base URL its key is for; null for a player.
	var base_url: Variant = null
	## An agent's: the lines of a [code].env[/code] file; null for a player.
	var env: Variant = null
	## An agent's: the world's front door for the new seat (its sponsor, its Character, the Charter to read first), a
	## Dictionary as served, as [method OWClient.me] serves it; null for a player.
	var front_door: Variant = null
	## An agent's: the world's reading aids as the new seat reads them, the Charter, the Guide, the Domains and the
	## strand ([method OWCharter.served] of the answer, the same packet as [code]GET /me[/code]'s); null for a player or
	## an older keel.
	var reading_aids: OWCharter.Packet = null
	## The answer as served, for what is not modelled here (an agent's [code]next[/code], [code]members[/code],
	## [code]with_character[/code]).
	var served := {}

	static func of(v: Dictionary) -> Joined:
		var j := Joined.new()
		j.kind = OWJoin._string(v, "kind")
		j.key = OWJoin._string(v, "key")
		j.pin = OWJoin._maybe(v, "pin")
		j.world = World.of(v.get("world"))
		j.character = Character.of(v.get("character"))
		j.role = OWJoin._maybe(v, "role")
		j.seat = Seat.of(v.get("seat"))
		j.base_url = OWJoin._maybe(v, "base_url")
		j.env = OWJoin._maybe(v, "env")
		j.front_door = v["front_door"].duplicate(true) if v.get("front_door") is Dictionary else null
		j.reading_aids = OWCharter.served(v)
		j.served = v
		return j

	func is_player() -> bool:
		return kind == "player"

	func is_agent() -> bool:
		return kind == "agent"

	## The role in the world, wherever this kind of answer carries it: a player's on the answer, an agent's on its seat.
	func role_in_world() -> Variant:
		if role != null:
			return role
		return seat.role if seat != null else null

## [method OWClient.accept_join]'s 201 ([code]POST /account/join[/code]; the TypeScript SDK's
## [code]OwJoinedMembership[/code]): the account's new membership, the same row as accepting an email invite.
class JoinedMembership:
	const KEYS := ["id", "world_id", "world_name", "role", "joined_at", "roster_character"]
	## The membership's id, as [method OWClient.members] and an element's [code]created_by[/code] name it.
	var id := ""
	var world_id := ""
	var world_name := ""
	## The role the link gave: [code]co_builder[/code], [code]contributor[/code] or [code]guest[/code].
	var role := ""
	## When it joined, ISO 8601 as served, or null.
	var joined_at: Variant = null
	## The id of the joiner's roster Character, or null.
	var roster_character: Variant = null

	static func of(v: Dictionary) -> JoinedMembership:
		var m := JoinedMembership.new()
		m.id = OWJoin._string(v, "id")
		m.world_id = OWJoin._string(v, "world_id")
		m.world_name = OWJoin._string(v, "world_name")
		m.role = OWJoin._string(v, "role")
		m.joined_at = OWJoin._maybe(v, "joined_at")
		m.roster_character = OWJoin._maybe(v, "roster_character")
		return m

## The join code in a pasted link ([code]https://www.onlyworlds.com/join#ow_j_...[/code] or
## [code].../join/<world_id>#ow_j_...[/code], any host) or a bare code, or "" when the text holds none (or is no
## String). The text is trimmed of Unicode's White_Space, the code read after the last [code]#[/code] and trimmed
## again; a code holds no white space and something after [constant CODE_PREFIX]. Only the shape is checked: the server
## is the only judge of whether a code is good. Mirrors the Unity SDK's [code]OWJoin.ParseLink[/code].
static func parse_link(text: Variant) -> String:
	if not (text is String):
		return ""
	var s := OWUnicode.trim_white_space(text)
	var hash := s.rfind("#")
	if hash >= 0:
		s = OWUnicode.trim_white_space(s.substr(hash + 1))
	if not s.begins_with(CODE_PREFIX) or s.length() == CODE_PREFIX.length():
		return ""
	for i in s.length():
		if OWUnicode._is_white_space(s.unicode_at(i)):
			return ""
	return s

## [code]POST /join/preview[/code]: who invites, to which world, in what role, and for which
## [member Preview.reader]; the code stays unused. Answers an [OWJoin.Preview]. [param options]: [code]transport[/code]
## and [code]base_url[/code], each optional. Refused, nothing sent: an empty code, an unknown option, a value of the
## wrong type. Mirrors the TypeScript SDK's [code]previewJoin[/code] and the Unity SDK's [code]OWJoin.PreviewAsync[/code].
static func preview(code: String, options := {}) -> OWClient.Reply:
	var why := _check("OWJoin.preview", code, options, [])
	if why != "":
		return _refused(why)
	var r := await _post("/join/preview", {"code": code}, options)
	if r.ok:
		r.value = Preview.of(r.value)
	return r

## [code]POST /join[/code]: redeem a player's or an agent's code, 201 with an [OWJoin.Joined] whose
## [member Joined.kind] tells the answers apart. [param options], each optional: [code]name[/code] (a player's: the
## Character's name, or "Player", when left out), [code]agent_name[/code] (an agent's, required for an agent code: a 422
## on [code]agent_name[/code] without it), [code]character[/code] (a party link's pick, an id from the preview's
## [member Preview.characters]; a table that lists none wants [code]name[/code] instead, and a link for one ignores
## it), [code]transport[/code] and [code]base_url[/code]. Each sent only when given and not null, in keel's spelling, in
## that order. keel's refusals: every bad code, and a person's, is the one 404 ([method OWApiError.is_not_found]); a
## taken pick [method OWApiError.is_character_taken], one off the list [method OWApiError.is_character_invalid], a
## world with its 50 players [method OWApiError.is_world_full]. None spends the code. Refused, nothing sent: an empty
## code, an unknown option, a value of the wrong type. Mirrors the TypeScript SDK's [code]redeemJoin[/code] and the
## Unity SDK's [code]OWJoin.RedeemAsync[/code].
static func redeem(code: String, options := {}) -> OWClient.Reply:
	var why := _check("OWJoin.redeem", code, options, _REDEEM_KEYS)
	if why != "":
		return _refused(why)
	var body := {"code": code}
	for k in _REDEEM_KEYS:
		if options.get(k) != null:
			body[k] = options[k]
	var r := await _post("/join", body, options)
	if r.ok:
		r.value = Joined.of(r.value)
	return r

## "" when the call may be sent; else the refusal.
static func _check(call: String, code: String, options: Dictionary, sends: Array) -> String:
	if code == "":
		return ("%s: a join code is required (the part of the link after #: OWJoin.parse_link reads it out of a pasted "
			+ "link). Nothing was sent.") % call
	var keys := _WHERE_KEYS + sends
	for k in options:
		if not (k is String and keys.has(k)):
			return "%s: unknown option '%s'; the options are %s. Nothing was sent." % [call, k, ", ".join(keys)]
	for k: String in options:
		var v = options[k]
		if v == null:
			continue
		if k == "transport":
			if not (v is OWTransport):
				return "%s: transport is an OWTransport. Nothing was sent." % call
		elif not (v is String):
			return "%s: %s is a String; got %s. Nothing was sent." % [call, k, type_string(typeof(v))]
	return ""

## The one keyless request: no [code]API-Key[/code], no [code]API-Pin[/code], no Bearer (keel declares no security on
## either route), the body as compact JSON; keel's envelope on a non-2xx, and a 2xx whose body is no JSON object an
## [constant OWApiError.ANSWER].
static func _post(path: String, body: Dictionary, options: Dictionary) -> OWClient.Reply:
	var transport: OWTransport = options["transport"] if options.get("transport") != null else OWHttpTransport.new()
	var base: String = options["base_url"] if options.get("base_url") != null and options["base_url"] != "" else DEFAULT_BASE_URL
	while base.ends_with("/"):
		base = base.trim_suffix("/")
	var response: OWTransport.Response = await transport.send(OWTransport.Request.make("POST", base + path,
		{"Content-Type": "application/json"}, OWClient._compact(body)))
	if response == null or response.failure != "":
		var why := "no response" if response == null else response.failure
		return OWClient.Reply.failed(OWApiError.of(OWApiError.TRANSPORT, "OnlyWorlds request failed: POST %s: %s" % [path, why]),
			response)
	if not response.is_success():
		return OWClient.Reply.failed(OWApiError.from_response(response.status, response.body, response.headers), response)
	var json := JSON.new()
	if response.body.strip_edges() == "" or json.parse(response.body) != OK or not (json.data is Dictionary):
		return OWClient.Reply.failed(OWApiError.of(OWApiError.ANSWER, "POST %s answered %d with a body that is not a JSON object"
			% [path, response.status], response.status, response.body), response)
	return OWClient.Reply.of(json.data, response)

static func _refused(why: String) -> OWClient.Reply:
	return OWClient.Reply.failed(OWApiError.of(OWApiError.REFUSED, why))

static func _string(v: Dictionary, k: String) -> String:
	var x = v.get(k)
	return x if x is String else ""

## A String as served, or null.
static func _maybe(v: Dictionary, k: String) -> Variant:
	var x = v.get(k)
	return x if x is String else null

## A whole number as an int (Godot's JSON reads every number as a float), or null.
static func _whole(x: Variant) -> Variant:
	if x is int:
		return x
	if x is float and x == floorf(x) and absf(x) < 9007199254740992.0:
		return int(x)
	return null

## A place in a list: a whole number not below 0, else -1.
static func _index(x: Variant) -> int:
	var n = _whole(x)
	return n if n != null and n >= 0 else -1

## The Dictionaries of the list under [param k], in order; anything else is left out.
static func _rows(v: Dictionary, k: String) -> Array:
	var list = v.get(k)
	return list.filter(func(x): return x is Dictionary) if list is Array else []
