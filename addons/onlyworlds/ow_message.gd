class_name OWMessage
extends RefCounted
## The message profile (schema-dist [code]profiles/message.md[/code], serial 79): a message between the members of a
## world, a Narrative with supertype [code]Message[/code], and the Note beside it, which is not one. To whom it is
## addressed, whether its sender is proved, who edited it, which messages a reader has read (the read mark), a
## thread, and a Character's line. The npm SDK's [code]message.ts[/code] and the Python package's
## [code]message.py[/code], read against the profile's text, which wins; keel's mail rule
## ([code]elements/lens.py[/code] [code]_mail[/code], [code]elements/read_mark.py[/code]) reads the same rules on the
## server. The fixture beside the profile is this file's test, and [OWLens] reads its mail rule through it.
##
## Bodies are Dictionaries as the API or a world folder gives them. A members list is the world's
## [code]GET members[/code] rows (only [code]id[/code] and [code]character[/code] are read; the owner's row has
## [code]id[/code] null, matching a [code]created_by[/code] of null), or null for a reader that cannot read one.
## Messages are ordered by [code]created_at[/code] as [method OWLens.time_key] reads it (the profiles' one time rule):
## equal times keep the list's order, and a time that cannot be read comes after every one that can, in the list's
## order. Godot's JSON reads every number as a float; nothing here compares a number (a numeric
## [code]parent_narrative[/code] is not a string id, and a numeric [code]hidden[/code] is a mark either way).

## The pair a message is, each word trimmed and folded as the room profile reads its pairs, the whole word.
const PAIR_TYPE := "narrative"
const PAIR_SUPERTYPE := "Message"
## A Note is the same type with this supertype: a member's own line in the world, never a message.
const NOTE_SUPERTYPE := "Note"
## The read mark: one Relation per reader, supertype [code]Read[/code], named [code]Read: <the reader's name>[/code],
## its [code]actor[/code] the reader's Character and its [code]narratives[/code] the ids it has read.
const READ_MARK_TYPE := "relation"
const READ_MARK_SUPERTYPE := "Read"
const READ_MARK_NAME_PREFIX := "Read: "
const READ_MARK_READER_FIELD := "actor"
const READ_MARK_MESSAGES_FIELD := "narratives"
## keel's mark on a body served to a key that may not see every link: the names of the fields that lost an id.
const SERVED_TRIMMED := "x_served_trimmed"

## What [method sender_status] answers.
const VERIFIED := "verified"
const MISMATCH := "mismatch"
const UNVERIFIABLE := "unverifiable"
const UNSEEN := "unseen"

## [method sender_status]'s answer.
class Sender:
	## [constant VERIFIED], [constant MISMATCH], [constant UNVERIFIABLE] or [constant UNSEEN].
	var status := ""
	## The message's [code]narrator[/code], the Character it claims as its sender, or null (shown as from nobody, or
	## from someone you cannot see when [member status] is [constant UNSEEN]).
	var claimed: Variant = null
	## On a mismatch, the Character of the membership that wrote it (from [code]created_by[/code]); null otherwise.
	var written_by: Variant = null

	func _init(p_status: String, p_claimed: Variant, p_written_by: Variant = null) -> void:
		status = p_status
		claimed = p_claimed
		written_by = p_written_by

	func to_dict() -> Dictionary:
		return {"status": status, "claimed": claimed, "written_by": written_by}

## [method edited_by]'s answer.
class Edit:
	## True when a later hand changed the message: it carries [code]changed_by[/code] and that is not its
	## [code]created_by[/code].
	var edited := false
	## The Character the editing membership plays, or null: not edited, or the editor plays none, is off the members
	## list, or there is no list (shown as "edited by another hand").
	var by: Variant = null

	func _init(p_edited: bool = false, p_by: Variant = null) -> void:
		edited = p_edited
		by = p_by

	func to_dict() -> Dictionary:
		return {"edited": edited, "by": by}

## True when [param element] is a message: a Narrative with supertype [code]Message[/code], the type and the
## supertype each trimmed (Unicode White_Space) and folded, the whole word ([code]Messages[/code] is not one). A
## parlor's line (one carrying [code]x_room_of[/code]) is a message too. npm [code]isMessage[/code].
static func is_message(element: Variant) -> bool:
	return _matches(element, PAIR_TYPE, PAIR_SUPERTYPE)

## True when [param element] is a Note: a Narrative with supertype [code]Note[/code], matched as [method is_message]
## matches. Addressed to nobody, never unread, in no thread, whatever its [code]characters[/code] holds.
static func is_note(element: Variant) -> bool:
	return _matches(element, PAIR_TYPE, NOTE_SUPERTYPE)

## The Character ids in the message's [code]characters[/code], in the field's order, entries that are not ids left
## out. Empty (absent, null or [code][][/code]) is addressed to every member unless keel trimmed it; ask
## [method is_addressed_to] for "is it for X". A Note has none. npm [code]recipientsOf[/code].
static func recipients_of(message: Variant) -> Array:
	if not (message is Dictionary) or is_note(message) or not (message.get("characters") is Array):
		return []
	return message["characters"].filter(func(c): return c is String and c != "")

## True when the message is addressed to [param character_id]: its id is in [code]characters[/code], or
## [code]characters[/code] is empty and keel did not trim it for this reader ([method is_to_everyone]). Nothing else
## addresses a message: not [code]narrator[/code], not a name or an id in [code]story[/code], no other link. An empty
## id ([code]""[/code]) is no Character, not even for a message to everyone. A Note is addressed to nobody.
static func is_addressed_to(message: Variant, character_id: Variant) -> bool:
	if not (message is Dictionary) or is_note(message) or not (character_id is String) or character_id == "":
		return false
	if is_to_everyone(message):
		return true
	var list: Variant = message.get("characters")
	return list is Array and list.has(character_id)

## True when the message is addressed to every member: its [code]characters[/code] absent, null or
## [code][][/code], and its [code]x_served_trimmed[/code] not naming [code]characters[/code] (then it is to someone the
## reader cannot see). A list that names no valid id ([code][""][/code]) or a value that is not a list is to nobody.
## [param keyless] true for a body read with no credential: keel serves it no mark, so it is never asserted to
## everyone. A Note is to nobody. npm [code]isToEveryone(message, {keyless})[/code].
static func is_to_everyone(message: Variant, keyless: bool = false) -> bool:
	if keyless or not (message is Dictionary) or is_note(message) or has_unseen_recipients(message) == true:
		return false
	var list: Variant = message.get("characters")
	return list == null or (list is Array and list.is_empty())

## True when someone this reader cannot see is a recipient: the body's [code]x_served_trimmed[/code] names
## [code]characters[/code], whatever is left in the list; never who or how many. Null (unknown) for a body read
## [param keyless], which keel serves no mark. False for a Note, keyless or not. npm [code]hasUnseenRecipients[/code].
static func has_unseen_recipients(message: Variant, keyless: bool = false) -> Variant:
	if not (message is Dictionary) or is_note(message):
		return false
	if keyless:
		return null
	var mark: Variant = message.get(SERVED_TRIMMED)
	return mark is Array and mark.has("characters")

## True when the message's [code]narrator[/code] is [param character_id]: the claim, whether or not
## [method sender_status] proves it. A message with no narrator is sent by nobody; an empty id sent nothing.
static func is_sent_by(message: Variant, character_id: Variant) -> bool:
	if not (message is Dictionary) or not (character_id is String) or character_id == "":
		return false
	var narrator: Variant = message.get("narrator")
	return narrator is String and narrator == character_id

## Whether the message's sender is proved. The claim is [code]narrator[/code]; the author is the membership in
## [code]created_by[/code], its Character that row's [code]character[/code] on [param members].
## [constant VERIFIED]: the author's Character is the narrator (a removed member's kept row still proves it; a
## Character a new member took verifies that member's messages). [constant MISMATCH]: another Character wrote it,
## named in [member Sender.written_by]. [constant UNVERIFIABLE]: no narrator, no [code]created_by[/code] key (a
## folder, an export; null is the owner), no members list, the author not on it, or its row naming no Character.
## [constant UNSEEN]: no narrator and [code]x_served_trimmed[/code] names [code]narrator[/code], decided before the
## hand is checked. An edit never changes the answer ([method edited_by]). npm [code]senderStatus[/code].
static func sender_status(message: Variant, members: Variant) -> Sender:
	if not (message is Dictionary):
		return Sender.new(UNVERIFIABLE, null)
	var narrator: Variant = message.get("narrator")
	var claimed: Variant = narrator if narrator is String and narrator != "" else null
	var mark: Variant = message.get(SERVED_TRIMMED)
	if claimed == null and mark is Array and mark.has("narrator"):
		return Sender.new(UNSEEN, null)
	if claimed == null:
		return Sender.new(UNVERIFIABLE, null)
	var hand: Variant = _hand_of(message, members)
	if hand == null:
		return Sender.new(UNVERIFIABLE, claimed)
	if hand == claimed:
		return Sender.new(VERIFIED, claimed)
	return Sender.new(MISMATCH, claimed, hand)

## Whether a later hand changed the message, and whose: [member Edit.edited] when it carries [code]changed_by[/code]
## (null for the owner, as [code]created_by[/code] is) and that is not its [code]created_by[/code] (an absent
## [code]created_by[/code] is never equal); [member Edit.by] that membership's Character on [param members], or null.
## A message with no [code]changed_by[/code] (a folder, an export) says nothing of edits. npm [code]editedBy[/code].
static func edited_by(message: Variant, members: Variant) -> Edit:
	if not (message is Dictionary) or not message.has("changed_by"):
		return Edit.new()
	if message.has("created_by") and _same(message["changed_by"], message["created_by"]):
		return Edit.new()
	return Edit.new(true, _character_of(message["changed_by"], members))

## The reader's read mark among [param relations] (the Relation itself), or null when it has none (always null for an
## empty id). A mark is a Relation with supertype [code]Read[/code] (trimmed and folded) whose [code]actor[/code] is
## the reader, and it counts only when every write on it was the reader's own hand: where it carries
## [code]created_by[/code], that membership on [param members] plays the reader's Character (null is the owner's
## hand); where it carries [code]changed_by[/code], that equals its [code]created_by[/code] (a writer with no creator
## beside it is no hand, and is ignored). A mark with neither key (a folder, an export) counts. Of several that count,
## the newest [code]updated_at[/code] wherever it stands (a readable time beats an unreadable one; a tie keeps the
## first); a newer mark in another's hand is ignored and the reader's own stands. [param keyless] true for bodies read
## with no credential, as [method is_to_everyone] takes it: the keyless public reader is served no
## [code]created_by[/code] or [code]changed_by[/code] on any body, so no mark counts there and the answer is null. npm
## [code]readMarkOf[/code].
static func read_mark_of(relations: Variant, character_id: Variant, members: Variant, keyless: bool = false) -> Variant:
	if keyless or not (relations is Array) or not (character_id is String) or character_id == "":
		return null
	var mark: Variant = null
	var mark_key: Variant = null
	for rel in relations:
		if not _matches(rel, READ_MARK_TYPE, READ_MARK_SUPERTYPE):
			continue
		var actor: Variant = rel.get(READ_MARK_READER_FIELD)
		if not (actor is String and actor == character_id):
			continue
		var has_author: bool = rel.has("created_by")
		if rel.has("changed_by") and (not has_author or not _same(rel["changed_by"], rel["created_by"])):
			continue
		if has_author and _hand_of(rel, members) != character_id:
			continue
		var key: Variant = OWLens.time_key(rel.get("updated_at"))
		if mark == null or (key != null and (mark_key == null or key > mark_key)):
			mark = rel
			mark_key = key
	return mark

## The messages unread for [param character_id], in [code]created_at[/code] order: addressed to it
## ([method is_addressed_to]; a Note never), not its own, and not on [param read_mark]'s [code]narratives[/code]
## ([method read_mark_of]'s answer; null is no mark, so everything addressed is unread). Its own: a message with no
## [code]created_by[/code] key (a folder, an export) whose narrator is the reader; on the wire only a verified sender
## ([method sender_status] against [param members]), so a mismatch, an author off the list or playing none, and every
## wire message when there is no members list, stays unread for the Character it claims. npm [code]unreadFor[/code].
static func unread_for(messages: Variant, character_id: Variant, read_mark: Variant, members: Variant = null) -> Array:
	if not (messages is Array):
		return []
	var read := {}
	if read_mark is Dictionary and read_mark.get(READ_MARK_MESSAGES_FIELD) is Array:
		for id in read_mark[READ_MARK_MESSAGES_FIELD]:
			if id is String:
				read[id] = true
	var out := []
	for m in messages:
		if is_addressed_to(m, character_id) and not _is_own_hand(m, character_id, members) and not read.has(m.get("id")):
			out.append(m)
	return _in_created_order(out)

## The thread of [param root_id]: every message whose chain of [code]parent_narrative[/code] reaches the root, the
## root included, in [code]created_at[/code] order. A walk stops at an id it has already visited (a loop ends it) and
## at a [code]parent_narrative[/code] that is not a string id (a number, null, an object); a parent not in the list
## ends the chain unless it is the root. A Note is never listed, though a chain walks through its parent like any
## other. npm [code]threadOf[/code].
static func thread_of(messages: Variant, root_id: Variant) -> Array:
	if not (messages is Array) or not (root_id is String) or root_id == "":
		return []
	var by_id := {}
	for m in messages:
		if m is Dictionary and m.get("id") is String and not by_id.has(m["id"]):
			by_id[m["id"]] = m
	var out := []
	for m in messages:
		if m is Dictionary and not is_note(m) and _reaches(m, root_id, by_id):
			out.append(m)
	return _in_created_order(out)

## A Character's line: the id of its newest own-hand Note among [param narratives], or null (always null for an empty
## id). A Note counts when its narrator is the Character, it is in its author's hand (no [code]created_by[/code] key,
## a folder: the narrator is trusted; with one, [method sender_status] verified), it is not hidden (any
## [code]hidden[/code] but absent, null or false) and not proposed ([code]x_review_proposed[/code] an object, as the
## profile says and the packages' [code]proposedMarkOf[/code] read it: [method OWLens.is_proposed] for presence and the
## empty mark, and a Dictionary; a doubt that is not an object leaves the Note shown, as a reader that shows a world
## shows it), and its id is a string. Of those, the newest by [code]created_at[/code] (a readable time beats an
## unreadable one; equal times, the later in the list), or the last in the list when none can be read.
## npm [code]noteOf[/code].
static func note_of(narratives: Variant, character_id: Variant, members: Variant) -> Variant:
	if not (narratives is Array) or not (character_id is String) or character_id == "":
		return null
	var line: Variant = null
	var line_key: Variant = null
	for note in narratives:
		if not is_note(note):
			continue
		var id: Variant = note.get("id")
		if not (id is String) or id == "" or not is_sent_by(note, character_id):
			continue
		if _hidden(note) or _proposed(note) or not _is_own_hand(note, character_id, members):
			continue
		var key: Variant = OWLens.time_key(note.get("created_at"))
		if line == null or (key >= line_key if key != null and line_key != null else line_key == null):
			line = id
			line_key = key
	return line

## By [code]created_at[/code] ([method OWLens.time_key]); equal times keep the input's order; unreadable times last,
## in the input's order. Never by id. The order [method unread_for] and [method thread_of] answer in.
static func _in_created_order(items: Array) -> Array:
	var keyed := []
	for i in items.size():
		var at: Variant = items[i].get("created_at") if items[i] is Dictionary else null
		keyed.append([items[i], i, OWLens.time_key(at)])
	keyed.sort_custom(func(a, b) -> bool:
		if a[2] != null and b[2] != null:
			return a[2] < b[2] if a[2] != b[2] else a[1] < b[1]
		if a[2] != null:
			return true
		if b[2] != null:
			return false
		return a[1] < b[1])
	return keyed.map(func(e): return e[0])

# -- the hand: who wrote a body, by the members list -------------------------------------------------------------------

static func _matches(el: Variant, type: String, supertype: String) -> bool:
	if not (el is Dictionary and el.get("type") is String and el.get("supertype") is String):
		return false
	return OWUnicode.profile_fold(el["type"]) == OWUnicode.profile_fold(type) \
		and OWUnicode.profile_fold(el["supertype"]) == OWUnicode.profile_fold(supertype)

## Two JSON values the same: the same type and equal (a membership id is a string, or null for the owner).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

## The Character a membership plays on the members list (its row by id, null the owner's), or null when there is no
## list, no such row, or the row names no Character.
static func _character_of(membership: Variant, members: Variant) -> Variant:
	if not (members is Array):
		return null
	for row in members:
		if row is Dictionary and row.has("id") and _same(row["id"], membership):
			var c: Variant = row.get("character")
			return c if c is String and c != "" else null
	return null

## The Character of the hand that wrote a body: its [code]created_by[/code] on the members list; null with no
## [code]created_by[/code] key (a folder, an export), no list, an author off it, or a row naming no Character.
static func _hand_of(body: Dictionary, members: Variant) -> Variant:
	return _character_of(body["created_by"], members) if body.has("created_by") else null

## The body is the Character's own, in its hand: its narrator is the Character, and with a [code]created_by[/code] key
## (the wire) the sender is verified; with none (a folder, an export) the narrator is trusted.
static func _is_own_hand(body: Dictionary, character_id: Variant, members: Variant) -> bool:
	if not is_sent_by(body, character_id):
		return false
	return not body.has("created_by") or sender_status(body, members).status == VERIFIED

static func _reaches(start: Dictionary, root_id: String, by_id: Dictionary) -> bool:
	var seen := {}
	var at: Variant = start
	while at != null:
		var id: Variant = at.get("id")
		if id is String and id == root_id:
			return true
		if not (id is String) or seen.has(id):
			return false
		seen[id] = true
		var parent: Variant = at.get("parent_narrative")
		if not (parent is String):
			return false
		if parent == root_id:
			return true
		at = by_id.get(parent)
	return false

## The platform's hidden mark: any value but absent, null and false, so a doubt is left out.
static func _hidden(el: Dictionary) -> bool:
	var v: Variant = el.get("hidden")
	return v != null and not (v is bool and v == false)

## Proposed as a reader that shows a world reads it: the review mark present and not empty, and an object.
static func _proposed(el: Dictionary) -> bool:
	return OWLens.is_proposed(el) and el[OWLens.PROPOSED_MARK] is Dictionary
