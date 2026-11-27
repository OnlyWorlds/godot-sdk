class_name OWSync
extends RefCounted
## Fills an [OWWorldCache] from the API and keeps it current from keel's change feed. Separate from the client and
## the cache on purpose: the client knows the wire, the cache holds the world, and the policy between them (when to walk
## again, what a rewound cursor means, what a reset keeps) belongs to neither. The feed's rules are keel's changes page
## (https://onlyworlds.github.io/docs/development/api/changes). Mirrors the Unity SDK's [code]OWSync[/code].
##
## [codeblock]
## var r := await OWSync.incremental(client, world)   # the first call walks the whole world
## if (await OWSync.has_changes(client, world)).value:
##     await OWSync.incremental(client, world)
## [/codeblock]
##
## Every call answers an [OWClient.Reply], never a throw: [member OWClient.Reply.value] a [OWSync.Result] (a bool for
## [method has_changes]), else [member OWClient.Reply.error], the failing request's own. A read-only cache
## ([member OWWorldCache.read_only]) is refused, nothing sent. World-settings edits are not in the feed: poll
## [method OWClient.get_world] for them.

## What a sync did.
class Result:
	## Elements written into the cache.
	var fetched := 0
	## Elements the feed deleted (or hid) that the cache held.
	var removed := 0
	## The [code]change_seq[/code] the cache stands at after the sync.
	var cursor := 0
	## True when the cache was walked again from the start rather than updated.
	var was_rebaselined := false
	## Why it was walked again, in words; [code]""[/code] when it was not.
	var rebaseline_reason := ""
	## On a walk the server asked for (409 [code]resync_required[/code]): its reason, [code]role[/code] or
	## [code]view[/code] ([method OWApiError.resync_reason]); [code]null[/code] when it sent none or asked for nothing.
	var resync_reason: Variant = null
	## On such a walk for [code]role[/code] or no reason, and on one for a cursor ahead of the server's head: how many
	## elements the cache held that the new walk did not name, and kept (out of view or rewound, not gone). 0 on
	## [code]view[/code], which drops them.
	var kept := 0
	## True when the sync changed the cache.
	var changed_anything: bool:
		get: return fetched > 0 or removed > 0 or was_rebaselined

## Walk every element type into [param cache], replacing what it held, through the list routes after a tip read: the
## tip is read first, and its head, cursor and epoch are what the cache records, so a change landing during the walk is
## above the recorded cursor and the next sync applies it. [param on_type], when valid, is called after each type with
## the type and how many elements it held. A walk that fails leaves the cache as it was, its elements and its cursor,
## and answers that failure: a baseline never empties a copy on its own.
static func baseline(client: OWClient, cache: OWWorldCache, on_type := Callable()) -> OWClient.Reply:
	var refused := _refusal(client, cache)
	if refused != null:
		return refused
	var tip_r := await client.changes_head()
	if not tip_r.ok:
		return tip_r
	var tip: OWClient.ChangesPage = tip_r.value
	var held := _Held.of(cache)
	cache.clear()
	var fetched := 0
	for type in OWTypes.slugs():
		var r := await client.list_all(type)
		if not r.ok:
			held.put_back(cache)
			return r
		for e: OWElement in r.value:
			if cache.upsert(e):
				fetched += 1
		if on_type.is_valid():
			on_type.call(type, r.value.size())
	cache.set_cursor(tip.head, tip.cursor, tip.epoch, _now())
	var result := Result.new()
	result.fetched = fetched
	result.cursor = tip.head
	result.was_rebaselined = true
	result.rebaseline_reason = "Full baseline requested."
	return OWClient.Reply.of(result, tip_r.response)

## Apply everything that changed since the cache's cursor. Resumes from the server's own cursor
## ([member OWWorldCache.cursor_token]), passed back as is, never one built from a number (a guest's feed answers a bare
## number above 0 with 409 [code]resync_required[/code]); a cache with no token resumes from its bare
## [member OWWorldCache.cursor]. Walks again from the start instead of updating ([method baseline]) when the cache has
## no cursor; when its cursor is ahead of the server's head (the server was restored from a backup: walked again,
## and what the cache held that the restored server no longer names is kept, [member Result.kept]); and when the feed
## answers 409 [code]resync_required[/code], where what the new walk does not name follows the 409's reason:
## [code]view[/code] drops it, [code]role[/code] or no reason keeps it. A reset whose walk fails puts the cache and its
## cursor back as they were. Current, one tip read and nothing else, only when head and epoch both stand. An upsert
## carries its element; one that does not is read by id. Deletes remove the element whatever their reason
## ([code]hidden[/code] too). The seq is claimed only when a page said there is no more: a feed that says more but
## gives no cursor leaves the seq where it was and the token at the last cursor given. A request that fails mid-walk
## answers its error with the cursor unmoved, so the next sync replays from where this one began.
static func incremental(client: OWClient, cache: OWWorldCache) -> OWClient.Reply:
	var refused := _refusal(client, cache)
	if refused != null:
		return refused
	if cache.cursor <= 0 and cache.cursor_token == "":
		return await baseline(client, cache)
	var tip_r := await client.changes_head()
	if not tip_r.ok:
		return tip_r
	var tip: OWClient.ChangesPage = tip_r.value
	if cache.cursor > tip.head:
		# Captured before the walk, which moves the cache's cursor to the new tip.
		var stale := cache.cursor
		var walked := await _rewalk(client, cache, true)
		if walked.ok:
			var result: Result = walked.value
			result.rebaseline_reason = ("Cursor %d was ahead of server head %d -- the server was likely restored from a "
				+ "backup. Walked again rather than trusting the cursor, and kept %d element(s) the new walk no longer "
				+ "names.") % [stale, tip.head, result.kept]
		return walked
	# Current only when the epoch stands too: a guest's view can change with head unmoved.
	if cache.cursor == tip.head and _same(cache.epoch, tip.epoch):
		var none := Result.new()
		none.cursor = cache.cursor
		return OWClient.Reply.of(none, tip_r.response)
	var fetched := 0
	var removed := 0
	var since := cache.cursor_token if cache.cursor_token != "" else str(cache.cursor)
	var highest := cache.cursor
	var epoch: Variant = tip.epoch
	var to_the_end := false
	var last: OWClient.Reply = tip_r
	while true:
		var page_r := await client.changes({"since": since})
		if not page_r.ok:
			if page_r.error.is_resync_required():
				return await _reset(client, cache, page_r.error.resync_reason())
			return page_r
		last = page_r
		var page: OWClient.ChangesPage = page_r.value
		# A page that says "no more" is the only honest end of the feed.
		if not page.has_more:
			to_the_end = true
		epoch = page.epoch
		for c: OWClient.Change in page.changes:
			# A watermark only, never an identity: a bulk import stamps many elements with one seq.
			if c.change_seq > highest:
				highest = c.change_seq
			if _is_delete(c.op):
				if cache.remove(c.id):
					removed += 1
				continue
			var e: OWElement = c.element
			if e == null:
				var got := await client.get_element(c.type, c.id)
				if not got.ok:
					return got
				e = got.value
			if e == null:
				continue
			if e.id == "":
				e.id = c.id
			if cache.upsert(e):
				fetched += 1
		# The server's cursor is the resume point, as is; keep the last one it gave.
		if page.cursor != "":
			since = page.cursor
		if not page.has_more or page.cursor == "":
			break
	cache.set_cursor(maxi(highest, tip.head) if to_the_end else cache.cursor, since, epoch, _now())
	var result := Result.new()
	result.fetched = fetched
	result.removed = removed
	result.cursor = cache.cursor
	return OWClient.Reply.of(result, last.response)

## Whether a sync would do anything, from one tip read and no element: true when the head is not the cache's cursor
## (either way: a head below it means the server was restored, and [method incremental] walks again) or the epoch
## moved (a guest's view changed). True means a sync is not a no-op, not that new content exists. Each tip read sends
## the last one's ETag, so while nothing moves keel answers 304, refunded against the request budget.
static func has_changes(client: OWClient, cache: OWWorldCache) -> OWClient.Reply:
	if client == null or cache == null:
		return _refused("OWSync.has_changes: a client and a cache are needed. Nothing was sent.")
	var r := await client.changes_head()
	if r.ok:
		var tip: OWClient.ChangesPage = r.value
		r.value = tip.head != cache.cursor or not _same(tip.epoch, cache.epoch)
	return r

## The answer to a 409 [code]resync_required[/code]: walk again from the start, then settle what the cache held that
## the new walk does not name by the server's reason (keel's changes page, "What a reset keeps").
static func _reset(client: OWClient, cache: OWWorldCache, reason: Variant) -> OWClient.Reply:
	var keep: bool = reason != "view"
	var walked := await _rewalk(client, cache, keep)
	if not walked.ok:
		return walked
	var result: Result = walked.value
	result.resync_reason = reason
	if keep:
		result.rebaseline_reason = ("The server asked for a full resync (409 resync_required, %s). Walked again from "
			+ "the start and kept %d element(s) the new walk no longer names: out of view now, not gone.") % [
			"no reason given, kept as for role" if reason == null else "reason role: this key's role or membership moved",
			result.kept]
	else:
		result.rebaseline_reason = ("The server asked for a full resync (409 resync_required, reason view): something "
			+ "left this key's view. Walked again from the start and dropped what the new walk no longer names.")
	return walked

## A baseline that puts back, when [param keep], every element the cache held that the new walk does not name.
static func _rewalk(client: OWClient, cache: OWWorldCache, keep: bool) -> OWClient.Reply:
	var held := _Held.of(cache)
	var walked := await baseline(client, cache)   # one that fails has put the cache back itself
	if walked.ok and keep:
		var result: Result = walked.value
		for e: OWElement in held.elements:
			if not cache.has(e.id):
				cache.upsert(e)
				result.kept += 1
	return walked

## What a cache held before a walk: its elements and where its last sync stopped, to put back.
class _Held:
	var elements: Array[OWElement] = []
	var cursor := 0
	var token := ""
	var epoch: Variant = null
	var at := ""

	static func of(cache: OWWorldCache) -> _Held:
		var h := _Held.new()
		h.elements = cache.elements()
		h.cursor = cache.cursor
		h.token = cache.cursor_token
		h.epoch = cache.epoch
		h.at = cache.synced_at
		return h

	func put_back(cache: OWWorldCache) -> void:
		cache.clear()
		for e in elements:
			cache.upsert(e)
		cache.set_cursor(cursor, token, epoch, at)

static func _refusal(client: OWClient, cache: OWWorldCache) -> OWClient.Reply:
	if client == null or cache == null:
		return _refused("OWSync: a client and a cache are needed. Nothing was sent.")
	# A snapshot exists to stay what it was; syncing live data into one destroys what it was made to keep.
	if cache.read_only:
		return _refused(("OWSync: the cache '%s' is read-only (a frozen snapshot). Syncing would overwrite the capture "
			+ "it exists to preserve. Nothing was sent.") % cache.world_id)
	return null

static func _refused(why: String) -> OWClient.Reply:
	return OWClient.Reply.failed(OWApiError.of(OWApiError.REFUSED, why))

## [code]delete[/code], and [code]remove[/code] as the Unity SDK reads it (keel sends only [code]delete[/code]).
static func _is_delete(op: String) -> bool:
	var o := op.to_lower()
	return o == "delete" or o == "remove"

## Two epochs are one when both are null or both the same int.
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b

static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
