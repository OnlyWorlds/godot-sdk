class_name OWZip
extends RefCounted
## The zip layer under [OWWorldArchive]: a walk of the archive's own central directory, entry inflation through
## Godot's zlib, and a writer that lays down its own bytes.
##
## Why not [ZIPReader] / [ZIPPacker] (measured on Godot 4.7): ZIPReader exposes no flags, method,
## Unix mode, declared size or raw name bytes, so 8 of the fixture set's verdicts cannot be told from it; ZIPPacker
## deflates the marker and stamps entries in local time. Here every field comes from the directory as written.

const SIG_LOCAL := 0x04034b50
const SIG_CENTRAL := 0x02014b50
const SIG_END := 0x06054b50
const SIG_END64 := 0x06064b50
const SIG_LOC64 := 0x07064b50
const MAX32 := 0xFFFFFFFF

const FLAG_ENCRYPTED := 0x0001
const FLAG_STRONG := 0x0040
const FLAG_UTF8 := 0x0800

const DOS_TIME := 0                          # 00:00:00
const DOS_DATE := (0 << 9) | (1 << 5) | 1    # 1980-01-01: fixed numbers, so no time zone can shift them

## One directory record, as the archive holds it.
class Entry:
	var raw_name: PackedByteArray
	var name: String           # decoded; "" when the bytes could not be (see [member name_ok])
	var name_ok := true
	var flags := 0
	var method := 0
	var crc := 0
	var csize := 0
	var usize := 0
	var external := 0
	var offset := 0
	var extra: PackedByteArray

	func unix_type() -> int:
		return (external >> 16) & 0xF000   # S_IFMT

	func is_dir() -> bool:
		return name.ends_with("/")

## What a walk found: [member error] is "" when the directory was read, else a refusal reason.
class Walk:
	var error := ""
	var message := ""
	var entries: Array[Entry] = []
	var zip64 := false

# -- reading ----------------------------------------------------------------------------------------------------------

## Walk [param b]'s central directory. Never inflates anything.
static func walk(b: PackedByteArray) -> Walk:
	var w := Walk.new()
	var n := b.size()
	var eocd := -1
	var i := n - 22
	var floor_at := maxi(0, n - 65557)
	while i >= floor_at:
		if b[i] == 0x50 and b[i + 1] == 0x4b and b[i + 2] == 0x05 and b[i + 3] == 0x06:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		return _fail(w, "not_openable", "not a zip: no end of central directory record")
	var this_disk := b.decode_u16(eocd + 4)
	var cd_disk := b.decode_u16(eocd + 6)
	var cd_size: int = b.decode_u32(eocd + 12)
	var cd_offset: int = b.decode_u32(eocd + 16)
	var end_at := eocd
	if eocd >= 20 and b.decode_u32(eocd - 20) == SIG_LOC64:
		var loc := eocd - 20
		var disk64: int = b.decode_u32(loc + 4)
		var disks: int = b.decode_u32(loc + 16)
		if disk64 != 0 or disks > 1:
			return _fail(w, "not_openable", "a zip64 archive spanning several disks")
		var rec := loc - 56
		if rec < 0 or b.decode_u32(rec) != SIG_END64:
			return _fail(w, "not_openable", "a zip64 locator without its end record")
		w.zip64 = true
		this_disk = b.decode_u32(rec + 16)
		cd_disk = b.decode_u32(rec + 20)
		cd_size = b.decode_u64(rec + 40)
		cd_offset = b.decode_u64(rec + 48)
		end_at = rec
	if not ((this_disk == 0 and cd_disk == 0) or (this_disk == 0xFFFF and cd_disk == 0xFFFF)):
		return _fail(w, "not_openable", "its end record says disk %d, the directory on disk %d: a spanned archive" % [this_disk, cd_disk])
	var concat := end_at - cd_size - cd_offset   # bytes before the archive (a stub); 0 for a plain zip
	if concat < 0 or cd_offset + concat < 0:
		return _fail(w, "not_openable", "the central directory's size and offset do not fit the file")
	var p := cd_offset + concat
	var stop := p + cd_size
	if stop > n:
		return _fail(w, "not_openable", "the central directory runs past the end of the file")
	while p < stop:
		if p + 46 > n or b.decode_u32(p) != SIG_CENTRAL:
			return _fail(w, "not_openable", "a bad record in the central directory at byte %d" % p)
		var e := Entry.new()
		e.flags = b.decode_u16(p + 8)
		e.method = b.decode_u16(p + 10)
		e.crc = b.decode_u32(p + 16)
		e.csize = b.decode_u32(p + 20)
		e.usize = b.decode_u32(p + 24)
		var nlen := b.decode_u16(p + 28)
		var xlen := b.decode_u16(p + 30)
		var clen := b.decode_u16(p + 32)
		e.external = b.decode_u32(p + 38)
		e.offset = b.decode_u32(p + 42)
		if p + 46 + nlen + xlen + clen > n:
			return _fail(w, "not_openable", "a directory record runs past the end of the file")
		e.raw_name = b.slice(p + 46, p + 46 + nlen)
		e.extra = b.slice(p + 46 + nlen, p + 46 + nlen + xlen)
		if e.flags & FLAG_UTF8:
			var s = OWUnicode.decode_utf8(e.raw_name)
			if s == null:
				return _fail(w, "name", "an entry flagged UTF-8 is not UTF-8 (bytes %s)" % e.raw_name.hex_encode())
			e.name = s
		else:
			e.name = _cp437(e.raw_name)
		var err := _zip64_extra(e)
		if err != "":
			return _fail(w, "not_openable", err)
		e.offset += concat
		w.entries.append(e)
		p += 46 + nlen + xlen + clen
	return w

static func _fail(w: Walk, reason: String, message: String) -> Walk:
	w.error = reason
	w.message = message
	return w

## The zip64 extended information extra field: the true sizes and offset where the record says 0xFFFFFFFF.
static func _zip64_extra(e: Entry) -> String:
	var x := e.extra
	var q := 0
	while q + 4 <= x.size():
		var tag := x.decode_u16(q)
		var ln := x.decode_u16(q + 2)
		if q + 4 + ln > x.size():
			return "a corrupt extra field on %s" % e.name
		if tag == 0x0001:
			var r := q + 4
			if e.usize == MAX32:
				if r + 8 > q + 4 + ln: return "a corrupt zip64 field on %s" % e.name
				e.usize = x.decode_u64(r); r += 8
			if e.csize == MAX32:
				if r + 8 > q + 4 + ln: return "a corrupt zip64 field on %s" % e.name
				e.csize = x.decode_u64(r); r += 8
			if e.offset == MAX32:
				if r + 8 > q + 4 + ln: return "a corrupt zip64 field on %s" % e.name
				e.offset = x.decode_u64(r); r += 8
		q += 4 + ln
	return ""

## A name without the UTF-8 flag is code page 437 by the zip format; its ASCII half is all a world name may use.
static func _cp437(raw: PackedByteArray) -> String:
	var ascii := true
	for x in raw:
		if x > 0x7F:
			ascii = false
			break
	if ascii:
		return raw.get_string_from_ascii()
	var parts := PackedStringArray()
	for x in raw:
		parts.append(String.chr(x) if x < 0x80 else String.chr(_CP437_HIGH.unicode_at(x - 0x80)))
	return "".join(parts)

const _CP437_HIGH := "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ "

## An entry's stored bytes, located through its local header. Sets [param out] ["error"] on failure.
static func payload(b: PackedByteArray, e: Entry, out: Dictionary) -> PackedByteArray:
	var off := e.offset
	if off < 0 or off + 30 > b.size() or b.decode_u32(off) != SIG_LOCAL:
		out["error"] = "not_openable"
		out["message"] = "%s: no local header at its offset" % e.name
		return PackedByteArray()
	var start := off + 30 + b.decode_u16(off + 26) + b.decode_u16(off + 28)
	return b.slice(start, mini(start + e.csize, b.size()))

## The entry's bytes, checked: never more than its declared size, its CRC-32 and its length both right. On a
## refusal, [param out] gets ["error"] (too_big or not_openable) and ["message"], and the result is empty.
static func inflate(b: PackedByteArray, e: Entry, out: Dictionary) -> PackedByteArray:
	var data := payload(b, e, out)
	if out.has("error"):
		return PackedByteArray()
	var declared := e.usize
	if e.method == 0:
		if data.size() > declared:
			return _refuse(out, "too_big", "%s holds %d bytes, past the %d it declares" % [e.name, data.size(), declared])
		if data.size() != declared:
			return _refuse(out, "not_openable", "%s holds %d bytes, declares %d" % [e.name, data.size(), declared])
		if OWCrc32.of(data) != e.crc:
			return _refuse(out, "not_openable", "%s fails its CRC" % e.name)
		return data
	# Deflate: the entry's raw stream in a gzip frame whose trailer is the directory's CRC and size, so zlib checks
	# both. decompress() is one inflate call into a buffer of exactly the declared size: it succeeds only when the
	# stream ends, the trailer matches, and nothing spilled past the size. (decompress_dynamic is not used: measured,
	# it never returns on bytes after a gzip trailer.)
	if declared == 0:
		return _inflate_empty(data, e, out)
	var got := _frame(data, e.crc, declared).decompress(declared, FileAccess.COMPRESSION_GZIP)
	if got.size() == declared:
		return got
	# It failed: tell a size that lies (more bytes than declared) from a broken or mismatched stream.
	var count := _count_inflated(data, declared + 1)
	if count > declared:
		return _refuse(out, "too_big", "%s inflates past the %d bytes it declares" % [e.name, declared])
	return _refuse(out, "not_openable", "%s: its deflate stream is broken, or fails its CRC or size" % e.name)

static func _refuse(out: Dictionary, reason: String, message: String) -> PackedByteArray:
	out["error"] = reason
	out["message"] = message
	return PackedByteArray()

static func _frame(raw: PackedByteArray, crc: int, size: int, prefix := PackedByteArray()) -> PackedByteArray:
	var g := PackedByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
	g.append_array(prefix)
	g.append_array(raw)
	var t := PackedByteArray()
	t.resize(8)
	t.encode_u32(0, crc & MAX32)
	t.encode_u32(4, size & MAX32)
	g.append_array(t)
	return g

## A deflated entry that declares 0 bytes. decompress() cannot take a 0-byte buffer, so a stored block holding one
## byte ("A") goes before the entry's stream (blocks are byte-aligned there) and the frame expects exactly "A".
static func _inflate_empty(data: PackedByteArray, e: Entry, out: Dictionary) -> PackedByteArray:
	if e.crc != 0:
		return _refuse(out, "not_openable", "%s declares 0 bytes and a CRC that is not the empty one" % e.name)
	var one := PackedByteArray([0x00, 0x01, 0x00, 0xFE, 0xFF, 0x41])   # BFINAL=0, stored, LEN 1, NLEN, 'A'
	var got := _frame(data, 0xD3D99E8B, 1, one).decompress(1, FileAccess.COMPRESSION_GZIP)  # CRC-32("A")
	if got.size() == 1:
		return PackedByteArray()
	if _count_inflated(data, 1) > 0:
		return _refuse(out, "too_big", "%s inflates past the 0 bytes it declares" % e.name)
	return _refuse(out, "not_openable", "%s: its deflate stream is broken" % e.name)

## How many bytes a raw deflate stream yields, stopping once past [param cap] (so a bomb is never inflated whole).
static func _count_inflated(raw: PackedByteArray, cap: int) -> int:
	var s := StreamPeerGZIP.new()
	s.start_decompression(false, 65536)
	var body := _frame(raw, 0, 0)
	body = body.slice(0, body.size() - 8)          # the trailer is never fed: only the count matters here
	var total := 0
	var off := 0
	while off < body.size() and total <= cap:
		var r := s.put_partial_data(body.slice(off, mini(off + 16384, body.size())))
		if r[0] != OK or r[1] == 0:
			break
		off += r[1]
		while s.get_available_bytes() > 0 and total <= cap:
			var got := s.get_partial_data(s.get_available_bytes())
			if got[0] != OK:
				break
			total += got[1].size()
	return total

# -- writing ----------------------------------------------------------------------------------------------------------

## A zip writer: each entry whole, so its sizes and CRC-32 go in its local header (no data descriptor); every entry
## stamped 1980-01-01 00:00 by fixed numbers; method 0 or 8; the UTF-8 flag on a non-ASCII name; made by MS-DOS, so
## no Unix mode is claimed. The zip64 end record when the entries reach 65,535 or an offset reaches 4 GiB.
class Writer:
	var _chunks: Array[PackedByteArray] = []
	var _central: Array[PackedByteArray] = []
	var _offset := 0

	## Add one entry. [param deflate] is ignored for an empty file, which is stored.
	func add(name: String, bytes: PackedByteArray, deflate: bool) -> Error:
		var raw_name := name.to_utf8_buffer()
		var flags := FLAG_UTF8 if raw_name.size() != name.length() else 0
		var method := 0
		var data := bytes
		var crc := 0
		if deflate and bytes.size() > 0:
			var gz := bytes.compress(FileAccess.COMPRESSION_GZIP)
			if gz.size() < 18 or gz[0] != 0x1f or gz[1] != 0x8b or gz[2] != 8 or gz[3] != 0:
				push_error("OnlyWorlds: zlib's gzip header is not the 10-byte one this writer reads past")
				return ERR_BUG
			data = gz.slice(10, gz.size() - 8)
			crc = gz.decode_u32(gz.size() - 8)
			method = 8
		else:
			crc = OWCrc32.of(bytes)
		var big := _offset >= MAX32
		var local := PackedByteArray()
		local.resize(30)
		local.encode_u32(0, SIG_LOCAL)
		local.encode_u16(4, 20)
		local.encode_u16(6, flags)
		local.encode_u16(8, method)
		local.encode_u16(10, DOS_TIME)
		local.encode_u16(12, DOS_DATE)
		local.encode_u32(14, crc)
		local.encode_u32(18, data.size())
		local.encode_u32(22, bytes.size())
		local.encode_u16(26, raw_name.size())
		local.encode_u16(28, 0)
		local.append_array(raw_name)
		var cd := PackedByteArray()
		cd.resize(46)
		cd.encode_u32(0, SIG_CENTRAL)
		cd.encode_u16(4, 45 if big else 20)     # made by: MS-DOS host
		cd.encode_u16(6, 45 if big else 20)
		cd.encode_u16(8, flags)
		cd.encode_u16(10, method)
		cd.encode_u16(12, DOS_TIME)
		cd.encode_u16(14, DOS_DATE)
		cd.encode_u32(16, crc)
		cd.encode_u32(20, data.size())
		cd.encode_u32(24, bytes.size())
		cd.encode_u16(28, raw_name.size())
		cd.encode_u16(30, 12 if big else 0)
		cd.encode_u16(32, 0)
		cd.encode_u16(34, 0)
		cd.encode_u16(36, 0)
		cd.encode_u32(38, 0)
		cd.encode_u32(42, MAX32 if big else _offset)
		cd.append_array(raw_name)
		if big:
			var x := PackedByteArray()
			x.resize(12)
			x.encode_u16(0, 0x0001)
			x.encode_u16(2, 8)
			x.encode_u64(4, _offset)
			cd.append_array(x)
		_chunks.append(local)
		_chunks.append(data)
		_offset += local.size() + data.size()
		_central.append(cd)
		return OK

	## The archive's bytes, after the last [method add].
	func finish() -> PackedByteArray:
		var start := _offset
		var size := 0
		for cd in _central:
			_chunks.append(cd)
			size += cd.size()
		var count := _central.size()
		var end_at := start + size
		var zip64 := count >= 0xFFFF or start >= MAX32 or size >= MAX32 or end_at >= MAX32
		if zip64:
			var r := PackedByteArray()
			r.resize(56 + 20)
			r.encode_u32(0, SIG_END64)
			r.encode_u64(4, 44)
			r.encode_u16(12, 45)
			r.encode_u16(14, 45)
			r.encode_u32(16, 0)
			r.encode_u32(20, 0)
			r.encode_u64(24, count)
			r.encode_u64(32, count)
			r.encode_u64(40, size)
			r.encode_u64(48, start)
			r.encode_u32(56, SIG_LOC64)
			r.encode_u32(60, 0)
			r.encode_u64(64, end_at)
			r.encode_u32(72, 1)
			_chunks.append(r)
		var e := PackedByteArray()
		e.resize(22)
		e.encode_u32(0, SIG_END)
		e.encode_u16(4, 0)
		e.encode_u16(6, 0)
		e.encode_u16(8, mini(count, 0xFFFF))
		e.encode_u16(10, mini(count, 0xFFFF))
		e.encode_u32(12, mini(size, MAX32))
		e.encode_u32(16, mini(start, MAX32))
		e.encode_u16(20, 0)
		_chunks.append(e)
		var out := PackedByteArray()
		for c in _chunks:
			out.append_array(c)
		return out
