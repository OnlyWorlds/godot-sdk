extends RefCounted
## OWId: the ids a create mints. RFC 9562 UUIDv7 (keel's core/ids.py layout, the Unity SDK's OWId.NewId, the
## TypeScript SDK's mintUuid), and under an Idempotency-Key the UUIDv5 of the key and the position in the keyed
## namespace, whose vectors are Python's uuid.uuid5 (the Python package's _minted_id), as the Unity SDK's OWIdTests
## hold them.

const V7 := "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

static func _ms_of(id: String) -> int:
	return id.replace("-", "").substr(0, 12).hex_to_int()

func test_keyed_is_pythons_uuid5_of_key_and_index(t) -> void:
	var cases := [
		["retry-1", 0, "1b88c4e4-831f-503c-8149-cece1519ca32"],
		["retry-1", 1, "2f7b4a01-0c9b-5b1e-8602-270abbee8184"],
		["retry-1", 3, "44bb129d-48b9-5fc2-b3c9-cc5f549e3e6e"],
		["Ærøskøbing", 0, "337e8ce1-5eb9-5373-96e9-9f67300da4ed"],
		["key \U01F5FA️", 2, "cb7502a0-06e3-5d4e-8adf-8f9c22ff46e7"],
	]
	for c in cases:
		t.eq(OWId.keyed(c[0], c[1]), c[2], "%s, %d" % [c[0], c[1]])
	t.eq(OWId.KEYED_NAMESPACE, "0199b6a0-6f0e-7c2a-9d1e-3b5c7a8e4f21", "the Python package's _KEYED_IDS")
	t.eq(OWId.keyed("", 0), "", "no key, no keyed id")
	t.done()

func test_mint_is_keyed_under_a_key_else_fresh(t) -> void:
	t.eq(OWId.mint("retry-1", 1), "2f7b4a01-0c9b-5b1e-8602-270abbee8184", "under a key: keyed")
	var a := OWId.mint("", 0)
	t.ok(RegEx.create_from_string(V7).search(a) != null, a)
	t.ok(OWId.mint("", 0) != a, "no key: fresh each time")
	t.done()

func test_new_id_is_a_version_7_variant_1_uuid(t) -> void:
	var re := RegEx.create_from_string(V7)
	for i in 200:
		var id := OWId.new_id()
		t.ok(re.search(id) != null, id)
	t.done()

func test_new_id_carries_the_clock_in_its_first_48_bits(t) -> void:
	var before := int(Time.get_unix_time_from_system() * 1000.0)
	var id := OWId.new_id()
	var after := int(Time.get_unix_time_from_system() * 1000.0)
	var ms := _ms_of(id)
	t.ok(ms >= before and ms <= after, "%d in [%d, %d]" % [ms, before, after])
	t.done()

func test_new_id_writes_every_48_bit_timestamp_big_endian(t) -> void:
	var re := RegEx.create_from_string(V7)
	for ms in [0, 1, 0xFFFFFFFF, 0x100000000, 1792108800000, 0xFFFFFFFFFFFF]:
		var id := OWId.new_id(ms)
		t.eq(_ms_of(id), ms, id)
		t.ok(re.search(id) != null, id)
	t.ok(OWId.new_id(1).replace("-", "").begins_with("0000000000017"), "")
	t.ok(OWId.new_id(1792108800000).begins_with("01a1"), "2026's ids read 019 or 01a, as keel's do")
	t.done()

func test_new_id_sorts_by_creation_and_differs_within_a_millisecond(t) -> void:
	t.ok(OWId.new_id(1792108800000) < OWId.new_id(1792108800001), "a millisecond apart: in order")
	var seen := {}
	for i in 1000:
		seen[OWId.new_id(1792108800000)] = true
	t.eq(seen.size(), 1000, "74 random bits do not repeat in 1000 ids")
	t.done()
