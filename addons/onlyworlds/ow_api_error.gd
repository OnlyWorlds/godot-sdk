class_name OWApiError
extends RefCounted
## Why an [OWClient] call has no value: keel's error envelope, typed, or the client's own word when no answer came or
## nothing was sent. GDScript has no exceptions, so a call answers an [OWClient.Reply] whose [member OWClient.Reply.error]
## is one of these, or null.
##
## [member kind] says which of five it is, since each has another remedy: [constant API] (keel answered and said no:
## branch on [member code], point a person at [member doc_url]), [constant TRANSPORT] (no answer came: offline, a
## timeout), [constant REFUSED] (the client refused the call before sending anything: a caller's mistake, the message
## names it), [constant ANSWER] (a 2xx whose body is not the answer the route documents) and [constant PROPOSED] (a
## write became a proposal: nothing was written, [member proposal] is the row a person decides). keel's envelope is
## [code]{"error": {type, code, message, param, doc_url}}[/code]; a body without the wrapper is read as the envelope
## itself, and the upload host's [code]{"error": "<code>"}[/code] as its code, as the Unity and TypeScript SDKs read
## them. Mirrors the TypeScript SDK's [code]OwApiError[/code].

## keel (or a proxy in front of it) answered with a status that is not a 2xx.
const API := "api"
## No answer came: [member status] is 0.
const TRANSPORT := "transport"
## Nothing was sent: the call or the client's configuration is a caller's mistake.
const REFUSED := "refused"
## A 2xx whose body is not what the route answers (not JSON, or not the documented shape).
const ANSWER := "answer"
## keel answered 202 with [code]{proposal}[/code] to a write that may become one (an upsert, a patch, a link edit by
## an agent seat in a world that takes its writes as proposals): the element did not change. Not a failure to retry:
## the write waits for a person.
const PROPOSED := "proposed"

var kind := API
## The HTTP status; 0 when no answer came or nothing was sent.
var status := 0
## The broad class, such as [code]invalid_request[/code]; "" when the answer carried none.
var type := ""
## keel's machine-readable code, such as [code]not_found[/code]; "" when the answer carried none.
var code := ""
## keel's message, the body's start when it was not the envelope, or the client's own words.
var message := ""
## The field the error is about, or "".
var param := ""
## The documentation link for [member code], or "".
var doc_url := ""
## The response body as received, for what the envelope does not model.
var raw_body := ""
## Seconds to wait before a retry, from [code]Retry-After[/code] (whole seconds, or an HTTP date read against the
## clock); null when it was absent or unreadable.
var retry_after: Variant = null
## On [constant PROPOSED]: the proposal row keel answered (a Dictionary, as served); null otherwise.
var proposal: Variant = null

## keel's answer as an error: the envelope read defensively (a gateway's HTML page is a message, never a parse
## error), [code]Retry-After[/code] read from [param headers] by any case. Mirrors the TypeScript SDK's
## [code]errorFromResponse[/code], with the Unity SDK's reading where the two differ (the wrapper's keys before the
## top level's; a body that is not JSON its first 200 characters as the message).
static func from_response(answer_status: int, body: String, headers: Dictionary) -> OWApiError:
	var e := OWApiError.new()
	e.kind = API
	e.status = answer_status
	e.raw_body = body
	for k: String in headers:
		if k.nocasecmp_to("Retry-After") == 0:
			e.retry_after = parse_retry_after(headers[k], int(Time.get_unix_time_from_system()))
	var json := JSON.new()
	var envelope = {} if body.strip_edges() == "" else (json.data if json.parse(body) == OK else null)
	if not (envelope is Dictionary):
		e.message = body if body.length() <= 200 else body.substr(0, 200) + "..."
		return e
	var inner = envelope.get("error")
	var error: Dictionary = inner if inner is Dictionary else envelope
	e.code = _text(error.get("code"))
	if e.code == "" and inner is String:
		e.code = inner
	e.type = _text(error.get("type"))
	e.message = _text(error.get("message"))
	e.param = _text(error.get("param"))
	e.doc_url = _text(error.get("doc_url"))
	return e

## The client's own error: [param what] is [constant TRANSPORT], [constant REFUSED] or [constant ANSWER]. Mirrors the
## TypeScript SDK's [code]OwNetworkError[/code] (no answer) and the [code]TypeError[/code] it throws before sending.
static func of(what: String, text: String, answer_status := 0, body := "") -> OWApiError:
	var e := OWApiError.new()
	e.kind = what
	e.status = answer_status
	e.message = text
	e.raw_body = body
	return e

## [code]Retry-After[/code] as seconds: whole seconds as given (past 32 bits, the largest), or an HTTP date
## ([code]Wed, 21 Oct 2026 07:28:00 GMT[/code]) as the seconds from [param now] (Unix seconds) to it, 0 when it has
## passed. Null for anything else, a negative number included. Mirrors the TypeScript SDK's [code]parseRetryAfter[/code].
static func parse_retry_after(value: Variant, now: int) -> Variant:
	if not (value is String):
		return null
	var v: String = value.strip_edges()
	if v == "":
		return null
	if v.is_valid_int() and not v.begins_with("-") and not v.begins_with("+"):
		return mini(v.to_int(), 2147483647) if v.length() < 19 else 2147483647
	var when = _http_date(v)
	if when == null:
		return null
	return maxi(0, when - now)

## An IMF-fixdate ([code]Sun, 06 Nov 1994 08:49:37 GMT[/code]) as Unix seconds, or null.
static func _http_date(v: String) -> Variant:
	var parts := v.split(" ", false)
	if parts.size() != 6 or parts[5] != "GMT" or not parts[0].ends_with(","):
		return null
	var month := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].find(parts[2]) + 1
	var hms := parts[4].split(":")
	if month == 0 or not parts[1].is_valid_int() or not parts[3].is_valid_int() or hms.size() != 3:
		return null
	for x in hms:
		if not x.is_valid_int():
			return null
	return Time.get_unix_time_from_datetime_dict({"year": parts[3].to_int(), "month": month, "day": parts[1].to_int(),
		"hour": hms[0].to_int(), "minute": hms[1].to_int(), "second": hms[2].to_int()})

static func _text(v: Variant) -> String:
	if v == null:
		return ""
	return v if v is String else str(v)

## The line it prints: [code]OnlyWorlds API 404 [not_found] (field: id): No such character.[/code]
func _to_string() -> String:
	var text := "OnlyWorlds API %d" % status if kind == API else "OnlyWorlds %s" % kind
	if code != "":
		text += " [%s]" % code
	if param != "":
		text += " (field: %s)" % param
	if message != "":
		text += ": " + message
	return text

## The key or PIN is wrong, unknown or revoked ([code]world_gone[/code] is reserved). By code: a 403 such as
## [code]owner_only[/code] comes with a valid key. Mirrors the TypeScript SDK's [code]isAuthError[/code].
func is_auth_error() -> bool:
	return code == "invalid_credentials" or code == "key_revoked" or code == "world_gone"

## 404 [code]not_found[/code]: no such element or route. A 404 without the code (a proxy's) is not this. Mirrors the
## TypeScript SDK's [code]isNotFound[/code].
func is_not_found() -> bool:
	return status == 404 and code == "not_found"

## A 422 or a 400: the request was read and refused as it stands. Mirrors the TypeScript SDK's
## [code]isValidationError[/code].
func is_validation_error() -> bool:
	return status == 422 or status == 400

## A member key tried what only the world's owner may do (403 [code]owner_only[/code]). Mirrors the TypeScript SDK's
## [code]isOwnerOnly[/code].
func is_owner_only() -> bool:
	return status == 403 and code == "owner_only"

## A list or get sent [code]view_as[/code] with a key that is not the owner's (403 [code]view_as_owner_only[/code]).
## Mirrors the TypeScript SDK's [code]isViewAsOwnerOnly[/code].
func is_view_as_owner_only() -> bool:
	return status == 403 and code == "view_as_owner_only"

## The change feed's position is no longer valid for this key (409 [code]resync_required[/code]): walk again from
## the start. [method resync_reason] says what the local copy keeps. Mirrors the TypeScript SDK's
## [code]isResyncRequired[/code].
func is_resync_required() -> bool:
	return status == 409 and code == "resync_required"

## With [method is_resync_required], why: [code]role[/code] (this key's role or membership moved: keep what the copy
## holds that a walk from the start no longer names) or [code]view[/code] (something left its view: drop it); null
## otherwise. Never empty a copy on your own. Mirrors the TypeScript SDK's [code]resyncReason[/code].
func resync_reason() -> Variant:
	if not is_resync_required():
		return null
	var json := JSON.new()
	var body = json.data if raw_body != "" and json.parse(raw_body) == OK else null
	var inner = body.get("error") if body is Dictionary else null
	var reason = inner.get("reason") if inner is Dictionary else null
	return reason if reason is String and (reason == "role" or reason == "view") else null

## A write became a proposal (202, kind [constant PROPOSED]): [member proposal] is the row; the element did not
## change. Mirrors the TypeScript SDK's [code]isProposed[/code].
func is_proposed() -> bool:
	return kind == PROPOSED

## A conditional write's [code]If-Match[/code] was stale (412 [code]precondition_failed[/code]: a patch, a link edit
## or a delete): the element changed since the [code]change_seq[/code] sent, and nothing was written. [method current]
## is the element as it is now; decide from it, then send again with its [code]change_seq[/code]. Mirrors the
## TypeScript SDK's [code]isPreconditionFailed[/code].
func is_precondition_failed() -> bool:
	return status == 412 and code == "precondition_failed"

## On a 412: the [code]current[/code] object keel sends beside the envelope, the element as it is now (a
## Dictionary, as served); null on any other answer, when keel sent none, or when the body is not JSON. Mirrors the
## Unity SDK's [code]Current[/code].
func current() -> Variant:
	if status != 412 or raw_body == "":
		return null
	var json := JSON.new()
	var body = json.data if json.parse(raw_body) == OK else null
	var now = body.get("current") if body is Dictionary else null
	return now if now is Dictionary else null

## The id is taken (409 [code]id_conflict[/code]): a create whose element carried its id and already landed, so the
## element is there. Mirrors the TypeScript SDK's [code]isIdConflict[/code].
func is_id_conflict() -> bool:
	return status == 409 and code == "id_conflict"

## The same [code]Idempotency-Key[/code] came with another body (409 [code]idempotency_error[/code]): a key is for
## one write and its retries only. Mirrors the TypeScript SDK's [code]isIdempotencyConflict[/code].
func is_idempotency_conflict() -> bool:
	return status == 409 and code == "idempotency_error"

## keel refused a known-of stub's key on a write (422 [code]known_of_not_writable[/code]). This client refuses a stub
## before sending and leaves the key out of every other body, so keel should not answer it this. Mirrors the
## TypeScript SDK's [code]isKnownOfNotWritable[/code].
func is_known_of_not_writable() -> bool:
	return status == 422 and code == "known_of_not_writable"

## Worth sending again later: a 429 or a 5xx, and the three 409s that clear by themselves; never a used-up allowance
## or a service turned off. Mirrors the Unity SDK's [code]IsRetryable[/code] (the TypeScript SDK has none: it names
## each code, [code]isBusy[/code], [code]isRateLimited[/code], [code]isIdempotencyInFlight[/code]).
func is_retryable() -> bool:
	match code:
		"idempotency_in_flight", "upload_pending", "removal_in_flight":
			return status == 409
		"quota_exceeded", "ask_unavailable", "media_unavailable":
			return false
	return status == 429 or status >= 500
