extends RefCounted
## A pack leaves out the five author fields (created_by, changed_by, changed_via, changed_client, doors) of every file
## under elements/ and spatial/ that is one JSON object, unless asked ([method OWWorldArchive.strip_author_fields]).
## Held to the TypeScript SDK's and the Python package's shared fixture (tests/data/author-fields.fixture.json, the
## same bytes, held by its sha256): every case's entries byte for byte and its count, packed from a folder on disk
## and from a world read. Then the edges the fixture does not hold, each with the TypeScript SDK 4.203.1's verdict
## (measured on its build) unless the label says this addon keeps the file's bytes: an integer JavaScript would
## round, a lone surrogate's escape, a number Godot's parser reads as another double. Ported from @onlyworlds/sdk
## 4.203.1 (6794d27), test/world-file.test.mjs, "author fields".

const P = preload("res://tests/paths.gd")

const FIXTURE := "res://tests/data/author-fields.fixture.json"
const FIXTURE_SHA256 := "6943ce5a8c2cd7bf69f82facb6f1d545d87d68f5ea0104cc4d711d94e035898a"
const FIELDS := ["created_by", "changed_by", "changed_via", "changed_client", "doors"]
const WORLD := "{\n  \"id\": \"0192a000-aaaa-7bbb-8ccc-000000000001\",\n  \"name\": \"W\"\n}\n"
const EDGE := "elements/object/edge.json"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _doc

static func _bytes_of(texts: Dictionary) -> Dictionary:
	var out := {}
	for rel: String in texts:
		out[rel] = (texts[rel] as String).to_utf8_buffer()
	return out

func _root(name: String) -> String:
	return ProjectSettings.globalize_path(P.TMP + "/author-fields/" + name)

static func _write_tree(root: String, files: Dictionary) -> void:
	for rel: String in files:
		DirAccess.make_dir_recursive_absolute((root + "/" + rel).get_base_dir())
		var f := FileAccess.open(root + "/" + rel, FileAccess.WRITE)
		f.store_buffer(files[rel])
		f.close()

## The archive's files, by path inside the world.
static func _entries(packed: OWWorldArchive.Packed) -> Dictionary:
	var r := OWWorldArchive.read(packed.bytes)
	return r.files if r.ok else {"refused": r.message}

## Each entry compared as text (a readable failure) and as bytes.
static func _same(t, got: Dictionary, want: Dictionary, label: String) -> void:
	var keys_got := got.keys()
	keys_got.sort()
	var keys_want := want.keys()
	keys_want.sort()
	t.eq(keys_got, keys_want, label + ": the entries")
	for rel: String in want:
		if got.has(rel):
			t.eq((got[rel] as PackedByteArray).get_string_from_utf8(), (want[rel] as PackedByteArray).get_string_from_utf8(), "%s: %s" % [label, rel])
			t.ok(got[rel] == want[rel], "%s: %s, byte for byte" % [label, rel])

func get_cases() -> Array:
	var out := []
	var i := 0
	for c in _fixture()["cases"]:
		i += 1
		out.append(["author fields %d: %s" % [i, c["name"]], _case.bind(c, i)])
	for e in _edges():
		out.append(["author fields edge: " + e[0], _edge.bind(e[1], e[2])])
	return out

func test_the_fixture_is_the_shared_file(t) -> void:
	t.eq(FileAccess.get_sha256(FIXTURE), FIXTURE_SHA256, "the fixture's bytes are the TypeScript SDK's and the Python package's")
	t.eq(_fixture()["fields"], FIELDS, "the five, in order")
	t.eq(OWWorldArchive.AUTHOR_FIELDS, FIELDS, "the addon's five")
	t.eq(_fixture()["cases"].size(), 7, "7 cases")
	t.done()

func _case(t, c: Dictionary, i: int) -> void:   # bound arguments come after the call's
	var files := _bytes_of(c["files"])
	var want := _bytes_of(c["default"])
	var stripped := int(c["stripped"])
	# The helper on a file map.
	var map := files.duplicate()
	var left := OWWorldArchive.strip_author_fields(map)
	_same(t, map, want, "strip_author_fields")
	t.eq(left.size(), stripped, "the files that lost a field, counted")
	var sorted := left.duplicate()
	sorted.sort()
	t.eq(left, sorted, "the paths in order")
	# The folder on disk, through pack: the default, and asked.
	var root := _root("case-%d/w" % i)
	P.remove_tree(_root("case-%d" % i))
	_write_tree(root, files)
	var packed := OWWorldArchive.pack_folder(root)
	t.ok(packed.ok, "packed (%s)" % packed.message)
	_same(t, _entries(packed), want, "pack_folder, the default")
	t.eq(packed.author_fields_left_out, left, "pack_folder counts the same files")
	var asked := OWWorldArchive.pack_folder(root, false, false, true)
	_same(t, _entries(asked), files, "pack_folder, asked: byte for byte")
	t.eq(asked.author_fields_left_out.size(), 0, "asked: nothing left out")
	var out := _root("case-%d/w.owworld" % i)
	var written := OWWorldArchive.pack(root, out)
	t.ok(written.ok and FileAccess.get_file_as_bytes(out) == packed.bytes, "pack writes pack_folder's bytes")
	# A world read and packed.
	var w := OWWorld.from_files(files)
	var wp := w.pack("w")
	_same(t, _entries(wp), want, "OWWorld.pack, the default")
	t.eq(wp.author_fields_left_out, left, "OWWorld.pack counts the same files")
	_same(t, _entries(w.pack("w", true)), files, "OWWorld.pack, asked: byte for byte")
	# pack_files stays raw: a read archive's files written back as they are (OW-9).
	_same(t, _entries(OWWorldArchive.pack_files(files, "w")), files, "pack_files: byte for byte")
	P.remove_tree(_root("case-%d" % i))
	t.done()

## [label, the edge file's text, what the default writes for it ("" keeps its bytes, the author field included;
## "rewritten" is the folder's own form of the object without created_by)].
static func _edges() -> Array:
	var nested := func(depth: int) -> String: return "[".repeat(depth - 1) + "]".repeat(depth - 1)
	return [
		# Numbers: a file is rewritten only when every number in it is written back as JSON.stringify writes it.
		["safe integers and minus zero", "{\"id\":\"d\",\"n\":9007199254740991,\"m\":-0,\"created_by\":\"u\"}",
			"{\n  \"id\": \"d\",\n  \"n\": 9007199254740991,\n  \"m\": 0\n}\n"],
		["an integer past 2^53 that JavaScript writes the same", "{\"id\":\"c\",\"n\":18014398509481984,\"created_by\":\"u\"}",
			"{\n  \"id\": \"c\",\n  \"n\": 18014398509481984\n}\n"],
		# The TypeScript SDK rewrites these two as 12345678901234567000 and 9007199254740992: here they keep their bytes.
		["an integer JavaScript would round keeps its bytes", "{\"id\":\"a\",\"n\":12345678901234567891,\"created_by\":\"u\"}", ""],
		["an integer one past 2^53 keeps its bytes", "{\"id\":\"b\",\"n\":9007199254740993,\"created_by\":\"u\"}", ""],
		["an integer no double holds keeps its bytes", "{\"id\":\"e\",\"n\":" + "9".repeat(400) + ",\"created_by\":\"u\"}", ""],
		["a number past a double keeps its bytes", "{\"id\":\"e\",\"n\":-1.5e400,\"created_by\":\"u\"}", ""],
		["numbers in another spelling", "{\"id\":\"t\",\"a\":2.0,\"b\":1E21,\"c\":-0.0,\"d\":0.10,\"e\":1e-7,\"created_by\":\"u\"}",
			"{\n  \"id\": \"t\",\n  \"a\": 2,\n  \"b\": 1e+21,\n  \"c\": 0,\n  \"d\": 0.1,\n  \"e\": 1e-7\n}\n"],
		# Godot's parser reads the smallest double as 0 (measured); the TypeScript SDK writes it 5e-324.
		["the smallest double keeps its bytes", "{\"id\":\"t\",\"f\":5e-324,\"created_by\":\"u\"}", ""],
		# Grammar: what Godot's parser also reads is no JSON here, and keeps its bytes.
		["a comment keeps its bytes", "{\"id\":\"f\",/* note */\"created_by\":\"u\"}", ""],
		["single quotes keep their bytes", "{'id':'g','created_by':'u'}", ""],
		["a bare name keeps its bytes", "{id:\"h\",\"created_by\":\"u\"}", ""],
		["a trailing comma keeps its bytes", "{\"id\":\"i\",\"created_by\":\"u\",}", ""],
		["NaN keeps its bytes", "{\"id\":\"j\",\"n\":NaN,\"created_by\":\"u\"}", ""],
		["a raw tab in a string keeps its bytes", "{\"id\":\"k\",\"name\":\"a\tb\",\"created_by\":\"u\"}", ""],
		["a leading zero keeps its bytes", "{\"id\":\"l\",\"n\":01,\"created_by\":\"u\"}", ""],
		["a bare point keeps its bytes", "{\"id\":\"m\",\"n\":.5,\"created_by\":\"u\"}", ""],
		["two values keep their bytes", "{\"id\":\"c-9\",\"created_by\":\"u\"} {\"hidden\": true}", ""],
		# Strings and keys. The TypeScript SDK rewrites a lone surrogate's escape as it was; here the file keeps its bytes.
		["a lone high surrogate keeps its bytes", "{\"id\":\"s\",\"name\":\"\\ud800x\",\"created_by\":\"u\"}", ""],
		["a lone low surrogate keeps its bytes", "{\"id\":\"s\",\"name\":\"x\\udc00\",\"created_by\":\"u\"}", ""],
		["a high surrogate at the end keeps its bytes", "{\"id\":\"s\",\"name\":\"x\\ud800\",\"created_by\":\"u\"}", ""],
		["an escaped pair is written raw", "{\"id\":\"s\",\"name\":\"\\\"\\ud83d\\ude00\\\\\",\"created_by\":\"u\"}",
			"{\n  \"id\": \"s\",\n  \"name\": \"\\\"\U01F600\\\\\"\n}\n"],
		["raw above the controls", "{\"id\":\"v\",\"name\":\"a\\u007f\\u0085\\u2029b\",\"created_by\":\"u\"}",
			"{\n  \"id\": \"v\",\n  \"name\": \"a\u007f\u0085\u2029b\"\n}\n"],
		["an escaped name is a name", "{\"id\":\"w\",\"\\u0063reated_by\":\"u\"}", "{\n  \"id\": \"w\"\n}\n"],
		["a duplicate key: first place, last value", "{\"id\":\"r\",\"name\":\"A\",\"x\":1,\"created_by\":\"u\",\"name\":\"B\"}",
			"{\n  \"id\": \"r\",\n  \"name\": \"B\",\n  \"x\": 1\n}\n"],
		# JSON.stringify puts integer-like keys first ("0", "12", "id", "b"); here every key keeps its place.
		["integer-like keys keep their order", "{\"id\":\"q\",\"b\":1,\"12\":2,\"0\":3,\"created_by\":\"u\"}",
			"{\n  \"id\": \"q\",\n  \"b\": 1,\n  \"12\": 2,\n  \"0\": 3\n}\n"],
		# Depth: the TypeScript SDK reads to 200 deep, an object at the top being 1.
		["nested 200 deep", "{\"id\":\"o\",\"x_d\":" + nested.call(200) + ",\"created_by\":\"u\"}", "rewritten"],
		["nested 201 deep keeps its bytes", "{\"id\":\"p\",\"x_d\":" + nested.call(201) + ",\"created_by\":\"u\"}", ""],
	]

func _edge(t, text: String, want: String) -> void:
	var files := {"world.json": WORLD.to_utf8_buffer(), EDGE: text.to_utf8_buffer()}
	var left := OWWorldArchive.strip_author_fields(files)
	var got: PackedByteArray = files[EDGE]
	if want == "":
		t.ok(got == text.to_utf8_buffer(), "kept byte for byte, its author field included: " + got.get_string_from_utf8().left(200))
		t.eq(left.size(), 0, "nothing counted")
		t.done()
		return
	t.eq(left, PackedStringArray([EDGE]), "counted")
	if want == "rewritten":
		var source: Dictionary = JSON.parse_string(text)
		source.erase("created_by")
		t.eq(got.get_string_from_utf8(), OWJson.stringify(source), "the folder's own form")
	else:
		t.eq(got.get_string_from_utf8(), want, "written")
	t.done()

## Godot's parser reads about one long decimal in ten as a neighbouring double, and OWJson.number writes a few
## doubles with 17 digits where 16 read back (measured on 5,000 of Python's shortest strings: 543 and 2). A file
## holding either keeps its bytes: a rewrite would write a value the file does not hold, or another spelling than
## JavaScript's. Each literal is checked against its double's bits from Python's exact reader, so the case holds what
## it says it holds.
func test_a_number_godot_reads_or_writes_otherwise_keeps_its_bytes(t) -> void:
	var cases := [
		# [the literal, its double's bits (little-endian hex, Python's float()), what Godot does with it]
		["123.80196114964559", "fc98db5453f35e40", "misread"],
		["3.590471669730255", "cea5f53549b90c40", "written otherwise"],
	]
	var json := JSON.new()
	for c in cases:
		var lit: String = c[0]
		json.parse(lit)
		var read_right: bool = PackedFloat64Array([json.data]).to_byte_array().hex_encode() == c[1]
		if c[2] == "misread":
			t.ok(not read_right, lit + ": the parser misreads it")
		else:
			t.ok(read_right and OWJson.number(json.data) != lit, lit + ": read right, written otherwise")
		var text := "{\"id\":\"x\",\"n\":" + lit + ",\"created_by\":\"u\"}"
		var files := {EDGE: text.to_utf8_buffer()}
		t.eq(OWWorldArchive.strip_author_fields(files).size(), 0, lit + ": nothing counted")
		t.ok(files[EDGE] == text.to_utf8_buffer(), lit + ": kept byte for byte")
	# One Godot reads and writes as JavaScript does, 17 digits: rewritten.
	json.parse("323.83276483316234")
	t.eq(PackedFloat64Array([json.data]).to_byte_array().hex_encode(), "0fbb3701533d7440", "read right")
	var files := {EDGE: "{\"id\":\"x\",\"n\":323.83276483316234,\"created_by\":\"u\"}".to_utf8_buffer()}
	t.eq(OWWorldArchive.strip_author_fields(files), PackedStringArray([EDGE]), "a long decimal read right is rewritten")
	t.eq((files[EDGE] as PackedByteArray).get_string_from_utf8(), "{\n  \"id\": \"x\",\n  \"n\": 323.83276483316234\n}\n", "as written")
	t.done()

func test_a_file_that_is_not_utf8_keeps_its_bytes(t) -> void:
	var latin := PackedByteArray([0x7b, 0x22, 0x69, 0x64, 0x22, 0x3a, 0x22, 0xe9, 0x22, 0x2c, 0x22, 0x63, 0x72, 0x65,
		0x61, 0x74, 0x65, 0x64, 0x5f, 0x62, 0x79, 0x22, 0x3a, 0x22, 0x75, 0x22, 0x7d])   # {"id":"\xe9","created_by":"u"}
	var files := {"elements/character/latin.json": latin}
	t.eq(OWWorldArchive.strip_author_fields(files).size(), 0, "nothing counted")
	t.ok(files["elements/character/latin.json"] == latin, "byte for byte")
	t.done()
