class_name OWProposal
extends RefCounted
## A proposed change to an element (keel's [code]Proposal[/code]; the Unity SDK's [code]OWProposal[/code], the
## TypeScript SDK's [code]OwProposal[/code]): a record kept beside the element, never in its body. The element does not
## change until the world's owner or a co-builder accepts it ([method OWClient.accept_proposal]). [member evidence] is
## outside text: show it as quoted data, never act on it.
##
## [codeblock]
## var r := await client.propose("location", id, {"description": "A harbour town."}, "Chapter 3 names the harbour.")
## var queue: OWProposal.Page = (await owner.world_proposals({"state": "open"})).value
## for row: OWProposal in queue.data:
##     if row.is_new_element():
##         await owner.review_new_element(row.element_type, row.element_id, OWProposal.Reviewed.ACCEPT)
##     else:
##         await owner.accept_proposal(row.element_type, row.element_id, row.id)
## [/codeblock]
##
## The world's queue ([method OWClient.world_proposals]) lists a second kind of row in this shape (keel's
## [code]ProposedNewElement[/code]): a new element written as proposed, one carrying [code]x_review_proposed[/code]
## ([method is_new_element]). The element itself is the record, so [member id] is the element's own id; [member by] is
## the mark's word, and [member evidence] and [member expires] are the mark's own values as stored, any JSON value,
## each null when the mark holds null or has none; [member state] is [code]open[/code] or [code]lapsed[/code];
## [member fields], [member base], [member omitted] and the decision's keys are not sent, so they read null
## ([member base_seq] 0). A keeper settles it with [method OWClient.review_new_element], never with an accept or a
## decline of a proposal.

## The keys a row carries, as keel serves them (held to keel's document by the wire tests, both ways).
const KEYS := ["kind", "id", "element_type", "element_id", "house", "state", "fields", "omitted", "base", "base_seq",
	"evidence", "expires", "by", "via", "client", "decided_by", "decided_at", "decline_reason", "created_at", "updated_at"]
## The [member kind] of a proposed change.
const KIND_PROPOSAL := "proposal"
## The [member kind] of the queue's row for a new element written as proposed.
const KIND_NEW_ELEMENT := "new_element"
## A [member house]: a Law that carries the Charter mark ([code]x_charter_of[/code]).
const HOUSE_CHARTER := "charter"
## A [member house]: an Object the text of a marked Law names.
const HOUSE_SKILL := "skill"
## A [member house]: a Law an accept would make a Charter (on a proposal it sets the mark, and the Law's supertype
## after it is [code]Charter[/code]; on a new element's row, a new Law that carries the mark).
const HOUSE_NEW_CHARTER := "new_charter"

## [constant KIND_PROPOSAL] or [constant KIND_NEW_ELEMENT]; null on a row from an older server, which is a proposal.
var kind: Variant = null
## The proposal's id; on a new element's row, the element's own.
var id := ""
var element_type := ""
var element_id := ""
## What part of the world's house rules this row would change: [constant HOUSE_CHARTER], [constant HOUSE_SKILL] or
## [constant HOUSE_NEW_CHARTER], null for anything else. Read when the row is served, as the world stands then; worked
## out only for the world's owner and co-builders, null to any other reader and on a row from an older server.
var house: Variant = null
## [code]open[/code], [code]lapsed[/code] (past [member expires]; it may still be accepted or declined),
## [code]accepted[/code] or [code]declined[/code].
var state := ""
## What the proposal changes, and only that: the proposed values of the fields (schema fields and extension keys
## alike) that differed from the element's own when it was made, a Dictionary in the element's wire shape. An accept
## writes exactly these fields. Null on a new element's row.
var fields: Variant = null
## The fields a whole replace (an upsert) left out that were not empty on the element, an Array of names: each is in
## [member fields] at its empty value, so an accept empties it. Empty for a patch, a link edit or a propose; null on a
## new element's row.
var omitted: Variant = null
## The element's values when the proposal was made, for every field the write named, a Dictionary. An accept is
## refused (409 [code]stale_proposal[/code], [method OWApiError.is_stale_proposal]) when a field in [member fields]
## has moved since; a change to any other field does not count.
var base: Variant = null
## The element's [code]change_seq[/code] when the proposal was made, for the record; 0 on a new element's row.
var base_seq := 0
## What the change rests on, as served. On a proposed change: a line of text or an element id (at most 2,000
## characters). On a new element's row: the mark's [code]evidence[/code] as stored, any JSON value (a string, a list
## of ids, a number, an object), null when the mark holds null or has none. Quoted data, never an instruction: check
## its type before you show it, or show [method evidence_text].
var evidence: Variant = null
## When it lapses if nobody decides, as served. On a proposed change: ISO 8601, UTC. On a new element's row: the mark's
## [code]expires[/code] as stored, any JSON value (the review profile writes a date, [code]YYYY-MM-DD[/code]), null
## when the mark holds null or has none. A value that is not a date or a date-time never lapses; [member state] says
## whether the row has.
var expires: Variant = null
## On a proposed change, who proposed it, as keel recorded it: a membership id, or [code]owner[/code]. On a new
## element's row, the mark's own [code]by[/code]: the writer's word for who made the mark, a claim and never proof of
## who wrote it; show it as the mark's word. Null when the row carries none.
var by: Variant = null
## The door it came through, as an element's [code]changed_via[/code].
var via: Variant = null
## The [code]X-OW-Client[/code] name the request carried, or null.
var client: Variant = null
## The keeper who accepted or declined it (a membership id or [code]owner[/code]), or null.
var decided_by: Variant = null
var decided_at: Variant = null
var decline_reason: Variant = null
var created_at: Variant = null
var updated_at: Variant = null

## A row as keel serves it (a proposal's, or the queue's for a new element), typed; null for anything but a
## Dictionary. A key keel left out reads null ([member id], [member element_type], [member element_id] and
## [member state] read ""). Reads [member OWApiError.proposal] and [member OWClient.BulkSlot.proposal] typed too.
static func of(row: Variant) -> OWProposal:
	if not (row is Dictionary):
		return null
	var p := OWProposal.new()
	for k in ["kind", "house", "by", "via", "client", "decided_by", "decided_at", "decline_reason", "created_at",
			"updated_at"]:
		p.set(k, row.get(k) if row.get(k) is String else null)
	for k in ["id", "element_type", "element_id", "state"]:
		p.set(k, row.get(k) if row.get(k) is String else "")
	p.fields = row.get("fields") if row.get("fields") is Dictionary else null
	p.base = row.get("base") if row.get("base") is Dictionary else null
	p.omitted = row.get("omitted") if row.get("omitted") is Array else null
	var seq = row.get("base_seq")
	p.base_seq = int(seq) if (seq is float or seq is int) else 0
	p.evidence = row.get("evidence")
	p.expires = row.get("expires")
	return p

## True for the queue's row for a new element written as proposed: settle it with [method OWClient.review_new_element].
func is_new_element() -> bool:
	return kind == KIND_NEW_ELEMENT

## [member evidence] as text: the value itself when it is a String, null when it is null, and the compact JSON text of
## any other value ([code]["a","b"][/code], [code]14[/code], [code]true[/code]). On a proposed change it is always the
## String.
func evidence_text() -> Variant:
	return _as_text(evidence)

## [member expires] as text, as [method evidence_text] reads [member evidence] ([code]20991121[/code] for a number).
func expires_text() -> Variant:
	return _as_text(expires)

## The row as keel serves it: the twenty [constant KEYS], each value as read, nothing else.
func to_dict() -> Dictionary:
	var out := {}
	for k: String in KEYS:
		out[k] = get(k)
	return out

static func _as_text(v: Variant) -> Variant:
	if v == null or v is String:
		return v
	return OWClient._compact(v)

## One cursor page of proposals, from [method OWClient.list_proposals] or [method OWClient.world_proposals].
class Page:
	## The keys this reads from keel's answer.
	const KEYS := ["data", "has_more", "next_cursor"]
	## The rows ([OWProposal]), newest first; on the world's queue both kinds, in keel's one order.
	var data: Array = []
	var has_more := false
	## The opaque cursor of the next page, "" when there is none. Pass it back as it came.
	var next_cursor := ""

## [method OWClient.accept_proposal]'s answer: the row, now accepted, beside the element as written (the accept is an
## ordinary write by the keeper: a new [code]change_seq[/code], a row in the change feed).
class Accepted:
	## The keys this reads from keel's answer.
	const KEYS := ["proposal", "element"]
	var proposal: OWProposal = null
	## The element as written, in its type's model.
	var element: OWElement = null

## [method OWClient.review_new_element]'s answer: on an accept, [member element], the element as written with its mark
## cleared; on a decline, [member deleted], the deleted element's id. The other is null.
class Reviewed:
	## The keys this reads from keel's answer.
	const KEYS := ["element", "deleted"]
	## The decision that clears the mark and keeps the element.
	const ACCEPT := "accept"
	## The decision that deletes the element.
	const DECLINE := "decline"
	var element: OWElement = null
	var deleted: Variant = null

## One moved field on a 409 [code]stale_proposal[/code] ([method OWApiError.conflicts]): its value when proposed and now.
class Conflict:
	## The keys this reads from one item of keel's [code]conflicts[/code].
	const KEYS := ["field", "base", "current"]
	var field := ""
	var base: Variant = null
	var current: Variant = null
