extends RefCounted
## OWJson against JavaScript's JSON.stringify(value, null, 2): numbers, escapes, key order, empty containers; and
## the dist's example world, written by the reference implementation, rewritten byte for byte.

const P = preload("res://tests/paths.gd")

func test_numbers_as_javascript_writes_them(t) -> void:
	# Expected strings are what JavaScript's Number.prototype.toString gives.
	var cases := [[1.0, "1"], [-5.0, "-5"], [0.0, "0"], [-0.0, "0"], [4255.0, "4255"], [0.1, "0.1"], [1.5, "1.5"],
		[123.456, "123.456"], [0.30000000000000004, "0.30000000000000004"], [2.5e-5, "0.000025"], [1e-7, "1e-7"],
		[1.5e-7, "1.5e-7"], [1e21, "1e+21"], [1e20, "100000000000000000000"],
		[123456789012.25, "123456789012.25"], [12345678.9, "12345678.9"], [-0.001, "-0.001"],
		[1.7976931348623157e308, "1.7976931348623157e+308"], [9007199254740992.0, "9007199254740992"], [2966.215418, "2966.215418"]]
	for c in cases:
		t.eq(OWJson.number(c[0]), c[1], "number %s" % var_to_str(c[0]))
	t.eq(OWJson.number(NAN), "null", "NaN")
	t.eq(OWJson.number(INF), "null", "Infinity")
	t.eq(OWJson.stringify(7), "7\n", "an int")
	t.done()

func test_escapes_as_javascript(t) -> void:
	t.eq(OWJson.quote("a\"b\\c"), "\"a\\\"b\\\\c\"", "quote and backslash")
	t.eq(OWJson.quote("\b\f\n\r\t"), "\"\\b\\f\\n\\r\\t\"", "the short escapes")
	t.eq(OWJson.quote(String.chr(1) + String.chr(0x1f)), "\"\\u0001\\u001f\"", "other control characters, lowercase hex")
	t.eq(OWJson.quote("é😀/ \u007f"), "\"é😀/ \u007f\"", "everything else as itself")
	var back = JSON.parse_string(OWJson.stringify({"s": String.chr(1)}))
	t.eq(back["s"], String.chr(1), "an escaped control character reads back")
	t.done()

func test_layout_and_key_order(t) -> void:
	var d := {"z": 1.0, "a": [], "m": {}, "list": ["x", 2.0, null, true], "o": {"k": "v"}}
	var want := "{\n  \"z\": 1,\n  \"a\": [],\n  \"m\": {},\n  \"list\": [\n    \"x\",\n    2,\n    null,\n    true\n  ],\n  \"o\": {\n    \"k\": \"v\"\n  }\n}\n"
	t.eq(OWJson.stringify(d), want, "2-space indent, keys as given, integral floats as integers")
	t.done()

func test_example_world_rewrites_byte_for_byte(t) -> void:
	# Hyperion was written by the reference implementation, so parse-then-write must give its bytes back.
	var root := P.EXAMPLE
	var files := ["world.json"]
	for type in DirAccess.get_directories_at(root + "/elements"):
		for f in DirAccess.get_files_at(root + "/elements/" + type):
			files.append("elements/" + type + "/" + f)
	var same := 0
	for rel in files:
		var bytes := FileAccess.get_file_as_bytes(root + "/" + rel)
		var out := OWJson.to_bytes(OWJson.parse_bytes(bytes))
		if out == bytes:
			same += 1
		else:
			t.fail("%s differs after a rewrite" % rel)
	t.eq(same, files.size(), "byte-equal of %d" % files.size())
	t.done()
