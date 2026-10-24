class_name OWCrc32
extends RefCounted
## CRC-32 (the zip and gzip polynomial, 0xEDB88320 reflected), in GDScript: Godot exposes no CRC to scripts.
## Used for stored entries; a deflated entry's CRC is checked by zlib itself through the gzip frame.

static var _table: PackedInt64Array

static func _build() -> void:
	_table.resize(256)
	for i in 256:
		var c := i
		for _k in 8:
			c = (0xEDB88320 ^ (c >> 1)) if (c & 1) else (c >> 1)
		_table[i] = c

## The CRC-32 of [param data].
static func of(data: PackedByteArray) -> int:
	if _table.is_empty():
		_build()
	var crc := 0xFFFFFFFF
	for x in data:
		crc = _table[(crc ^ x) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF
