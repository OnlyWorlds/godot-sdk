class_name OWId
extends RefCounted
## Element ids as the standard mints them: RFC 9562 UUIDv7 (48-bit Unix milliseconds, version 7, variant 10, 74 random
## bits), and under a caller's [code]Idempotency-Key[/code] a UUIDv5 derived from it ([method keyed]).
##
## The layout keel mints server-side ([code]core/ids.py[/code]), the Unity SDK's [code]OWId[/code], the TypeScript
## SDK's [code]mintUuid[/code] and the Python package's [code]uuid7[/code]. v7 is a default, never a requirement: ids
## minted earlier as v4 stay valid. Ids minted a millisecond or more apart sort by creation, while the clock does not
## step backwards; a world also holds v4 ids and the old server's seconds-first ids, so never order elements by id
## ([code]created_at[/code] is creation order). The random bits come from [Crypto], which answers before a SceneTree's
## first frame (measured on 4.7.2), unlike TLS.

## The Python package's [code]_KEYED_IDS[/code] ([code]onlyworlds/http.py[/code]), the TypeScript SDK's
## [code]KEYED_IDS[/code] and the Unity SDK's [code]OWId.KeyedNamespace[/code].
const KEYED_NAMESPACE := "0199b6a0-6f0e-7c2a-9d1e-3b5c7a8e4f21"

## A new UUIDv7 in its lowercase 8-4-4-4-12 form, carrying [param unix_ms] as its timestamp (now when negative).
static func new_id(unix_ms: int = -1) -> String:
	var ms := unix_ms if unix_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var b := Crypto.new().generate_random_bytes(16)
	for i in 6:
		b[i] = (ms >> (8 * (5 - i))) & 0xff
	b[6] = 0x70 | (b[6] & 0x0f)   # version 7
	b[8] = 0x80 | (b[8] & 0x3f)   # variant 10
	return _format(b)

## The id for an element with none, written at [param index] under the caller's [param idempotency_key]: the RFC 9562
## UUIDv5 of [code]key + "\n" + index[/code] (UTF-8) in [constant KEYED_NAMESPACE]. The same key with the same
## elements then sends the same body, so keel replays the first answer instead of refusing a second body (409
## [code]idempotency_error[/code]); the Python package, the TypeScript SDK and the Unity SDK derive the same id. A single
## create is index 0, a bulk item its position. "" for an empty key, which has no keyed id.
static func keyed(idempotency_key: String, index: int) -> String:
	if idempotency_key == "":
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(KEYED_NAMESPACE.replace("-", "").hex_decode())
	ctx.update((idempotency_key + "\n" + str(index)).to_utf8_buffer())
	var b := ctx.finish().slice(0, 16)
	b[6] = 0x50 | (b[6] & 0x0f)   # version 5
	b[8] = 0x80 | (b[8] & 0x3f)   # variant 10
	return _format(b)

## The id a write mints for an element with none: [method keyed] under a caller's key, else [method new_id].
static func mint(idempotency_key: String, index: int) -> String:
	return new_id() if idempotency_key == "" else keyed(idempotency_key, index)

static func _format(b: PackedByteArray) -> String:
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]
