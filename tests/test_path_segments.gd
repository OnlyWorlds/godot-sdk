extends RefCounted
## A caller's string never changes which route is asked: every type, id, link field and proposal id in a request path is checked as
## one segment (refused before sending when it is not one) and sent escaped. keel decodes an escaped slash before it
## routes (measured on production 2026-10-31: /character/abc%2Fhidden/ answers 405 as /character/abc/hidden/ does), so
## the escape alone cannot hold a slash. keel's document declares each element id a UUID, so the check and the escape
## change nothing on a real id. The rule is the TypeScript SDK's 4.123.3 (its test/path-segments.test.mjs), in the two
## halves it has:
##  - the source scan reads ow_client.gd, finds every request path it builds and fails on a value put in without the
##    checking helper _seg (an escape alone no longer passes), and on a path built some way the scan cannot read (a
##    concatenation, a variable, an unknown helper); it also asserts it found a plausible number of paths, so a scan
##    that lost its shape fails instead of passing empty;
##  - the wire: calls with a value that is not one segment, each refused with nothing sent and the value named, and
##    calls with one-segment values that go out as given.

const Fake := preload("res://tests/fake_transport.gd")
const CLIENT := "res://addons/onlyworlds/ow_client.gd"
const BASE := "https://example.test/api/v2"
const UUID := "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e0f"
const ID := UUID + "/hidden"

## The scan: each problem as a line, [] when every path is read and every substituted value goes through _seg. [param src] is
## the client's source; [param stats] (a Dictionary) gets "paths", the request calls read.
static func scan(src: String, stats: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var paths := 0
	var literal_sites := 0
	var helpers := {}
	var calls := 0
	for raw_line in src.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("#") or line.begins_with("func _request("):
			continue
		var from := 0
		while true:
			var at := line.find("_request(", from)
			if at < 0:
				break
			from = at + 9
			calls += 1
			var rest := line.substr(from)
			var head := RegEx.create_from_string('^"[A-Z]+",\\s*').search(rest)
			if head == null:
				problems.append("a request call whose method is not a literal: " + line)
				continue
			rest = rest.substr(head.get_end())
			var arg := _path_arg(rest)
			if arg.is_empty():
				problems.append("a request path the scan cannot read: " + line)
				continue
			paths += 1
			if arg.has("helper"):
				helpers[arg["helper"]] = true
				continue
			literal_sites += 1
			problems.append_array(_judge(arg["literal"], arg["values"], line))
	# Each helper that builds a path is judged on its own return.
	for h in helpers:
		var m := RegEx.create_from_string("func " + h + "\\([^)]*\\)[^\\n]*:\\s*\\n\\s*return ([^\\n]*)").search(src)
		if m == null:
			problems.append("a path helper whose return the scan cannot find: " + h)
			continue
		var ret := m.get_string(1).strip_edges()
		var arg := _path_arg(ret + ",")
		if arg.is_empty() or arg.has("helper"):
			problems.append("a path helper built some way the scan cannot read: " + ret)
			continue
		paths += 1
		problems.append_array(_judge(arg["literal"], arg["values"], ret))
	stats["paths"] = paths
	stats["calls"] = calls
	stats["helpers"] = helpers.keys()
	return problems

## What one path argument is, or {} when unreadable: {"literal", "values"} for "..." or "..." % [a, b] or "..." % a
## (each followed by the comma that ends the argument), {"helper"} for a call of a function named in _helper().
static func _path_arg(rest: String) -> Dictionary:
	var lit := RegEx.create_from_string('^"((?:[^"\\\\]|\\\\.)*)"').search(rest)
	if lit != null:
		var after := rest.substr(lit.get_end()).strip_edges()
		if after.begins_with(","):
			return {"literal": lit.get_string(1), "values": PackedStringArray()}
		if after.begins_with("%"):
			after = after.substr(1).strip_edges()
			if after.begins_with("["):
				var end := _close(after)
				if end < 0 or not after.substr(end + 1).strip_edges().begins_with(","):
					return {}
				return {"literal": lit.get_string(1), "values": _split(after.substr(1, end - 1))}
			var comma := after.find(",")
			if comma < 0:
				return {}
			return {"literal": lit.get_string(1), "values": PackedStringArray([_split(after)[0]])}   # the one value, a call such as _seg("type", type) whole
		return {}
	var h := RegEx.create_from_string("^(_element_path)\\([^()]*\\)\\s*,").search(rest)
	if h != null:
		return {"helper": h.get_string(1)}
	return {}

## The index of the bracket that closes the one opening [param s].
static func _close(s: String) -> int:
	var depth := 0
	var quoted := false
	for i in s.length():
		var ch := s[i]
		if ch == '"' and (i == 0 or s[i - 1] != "\\"):
			quoted = not quoted
		elif not quoted:
			if ch == "[" or ch == "(" or ch == "{":
				depth += 1
			elif ch == "]" or ch == ")" or ch == "}":
				depth -= 1
				if depth == 0:
					return i
	return -1

## [param s] split at its top-level commas.
static func _split(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var quoted := false
	var start := 0
	for i in s.length():
		var ch := s[i]
		if ch == '"' and (i == 0 or s[i - 1] != "\\"):
			quoted = not quoted
		elif not quoted:
			if ch == "[" or ch == "(" or ch == "{":
				depth += 1
			elif ch == "]" or ch == ")" or ch == "}":
				depth -= 1
			elif ch == "," and depth == 0:
				out.append(s.substr(start, i - start).strip_edges())
				start = i + 1
	out.append(s.substr(start).strip_edges())
	return out

## The problems of one path template: a format with a count that does not match its values, a value not escaped.
static func _judge(literal: String, values: PackedStringArray, where: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var slots := literal.count("%s")
	if literal.count("%") != slots:
		problems.append("a path format other than %s: " + where)
	if slots != values.size():
		problems.append("a path with %d slots and %d values: %s" % [slots, values.size(), where])
	# _seg("id", id): the checking helper, named for the value it checks (type, id, field, a proposal's pid or a file's file_id).
	var checked := RegEx.create_from_string('^_seg\\("(type|id|field|pid|file_id)", \\1\\)$')
	for v in values:
		if checked.search(v) == null:
			problems.append("a value not checked by _seg (%s) in a request path: %s" % [v, where])
	return problems

func test_source_every_value_in_a_request_path_goes_through_seg(t) -> void:
	var src := FileAccess.get_file_as_string(CLIENT)
	t.ok(src != "", "the client's source was read")
	var stats := {}
	var problems := scan(src, stats)
	for p in problems:
		t.fail(p)
	# The shape guard: a scan that found few paths lost its shape. The client builds 28 call sites and one helper.
	t.ok(stats["paths"] >= 19, "the scan found %d request paths; it lost its shape" % stats["paths"])
	t.eq(stats["helpers"], ["_element_path"], "the path helpers the scan reads")
	t.done()

func test_source_no_other_file_makes_a_request(t) -> void:
	var offenders := PackedStringArray()
	for file in _gd_files("res://addons"):
		if file == CLIENT:
			continue
		var s := FileAccess.get_file_as_string(file)
		for line in s.split("\n"):
			var l := line.strip_edges()
			if not l.begins_with("#") and l.contains("_request("):
				offenders.append(file)
				break
	t.eq(offenders, PackedStringArray(), "a file other than the client that calls _request, which the scan does not read")
	t.done()

func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out

## The scan itself, on sources it must refuse: a raw value on one route, a path built by concatenation on another,
## a variable, an unknown helper, a count that does not match.
func test_the_scan_refuses_what_it_should(t) -> void:
	var good := 'func f():\n\tawait _request("GET", "/%s/%s/" % [_seg("type", type), _seg("id", id)], q)\n'
	t.eq(scan(good, {}), PackedStringArray(), "a checked route passes")
	var cases := {
		"a raw type": 'await _request("GET", "/%s/" % type, q)',
		"a raw id in a list": 'await _request("GET", "/%s/%s/" % [_seg("type", type), id], q)',
		"a raw field": 'await _request("POST", "/%s/%s/links/%s" % [_seg("type", type), _seg("id", id), field], q)',
		"a raw pid": 'await _request("POST", "/%s/%s/proposals/%s/accept" % [_seg("type", type), _seg("id", id), pid], q)',
		"an escape without the check on the type": 'await _request("GET", "/%s/" % type.uri_encode(), q)',
		"an escape without the check on the id": 'await _request("GET", "/%s/%s/" % [_seg("type", type), id.uri_encode()], q)',
		"a check named for another value": 'await _request("GET", "/%s/%s/" % [_seg("type", type), _seg("type", id)], q)',
		"a concatenation": 'await _request("GET", "/" + type + "/", q)',
		"a variable": 'await _request("GET", path, q)',
		"an unknown helper": 'await _request("GET", _other_path(type, id), q)',
		"a method that is not a literal": 'await _request(verb, "/x/", q)',
		"a count that does not match": 'await _request("GET", "/%s/%s/" % [_seg("type", type)], q)',
		"a format that is not %s": 'await _request("GET", "/%d/" % [n], q)',
	}
	for label in cases:
		var problems := scan("func f():\n\t" + cases[label] + "\n", {})
		t.ok(not problems.is_empty(), "the scan refuses " + label)
	# A helper whose return is raw is refused through its call site.
	var helper := 'await _request("PUT", _element_path(type, id), [])\nstatic func _element_path(type: String, id: String) -> String:\n\treturn "/%s/%s/" % [type, _seg("id", id)]\n'
	t.ok(not scan(helper, {}).is_empty(), "the scan refuses a raw value in the path helper")
	var escaped_only := 'await _request("PUT", _element_path(type, id), [])\nstatic func _element_path(type: String, id: String) -> String:\n\treturn "/%s/%s/" % [type.uri_encode(), id.uri_encode()]\n'
	t.ok(not scan(escaped_only, {}).is_empty(), "the scan refuses a helper that only escapes")
	t.done()

## [name, what, call]: each route that takes a caller's string, with a value that is not one segment; what is named.
func _refused() -> Array:
	return [
		["get_element", "id", func(c): return await c.get_element("character", ID)],
		["upsert", "id", func(c): return await c.upsert("character", ID, {"name": "x"})],
		["patch", "id", func(c): return await c.patch("character", ID, {"name": "x"})],
		["delete", "id", func(c): return await c.delete("character", ID)],
		["edit_links (id)", "id", func(c): return await c.edit_links("character", ID, "friends", {"add": []})],
		["edit_links (field)", "field", func(c): return await c.edit_links("character", UUID, "friends/x", {"add": []})],
		["list (type)", "type", func(c): return await c.list("character/x")],
		["list_all (type)", "type", func(c): return await c.list_all("character/x")],
		["get_element (type)", "type", func(c): return await c.get_element("Character", UUID)],
		["create (type)", "type", func(c): return await c.create("character/x", {"name": "x"})],
		["upsert (type)", "type", func(c): return await c.upsert("character/x", UUID, {"name": "x"})],
		["patch (type)", "type", func(c): return await c.patch("character/x", UUID, {"name": "x"})],
		["delete (type)", "type", func(c): return await c.delete("character/x", UUID)],
		["edit_links (type)", "type", func(c): return await c.edit_links("character/x", UUID, "friends", {"add": []})],
		["get_element (escaped slash)", "id", func(c): return await c.get_element("character", UUID + "%2Fhidden")],
		["get_element (dot segment)", "id", func(c): return await c.get_element("character", "..")],
		["get_element (empty id)", "id", func(c): return await c.get_element("character", "")],
		["list (empty type)", "type", func(c): return await c.list("")],
		["get_element (query and fragment)", "id", func(c): return await c.get_element("character", "abc?x=1#y")],
		["get_element (a trailing newline)", "id", func(c): return await c.get_element("character", UUID + "\n")],
		["get_element (a space)", "id", func(c): return await c.get_element("character", "a b")],
		["get_element (a leading dash)", "id", func(c): return await c.get_element("character", "-a")],
		["get_element (a leading dot)", "id", func(c): return await c.get_element("character", ".a")],
		["get_element (a non-ASCII letter)", "id", func(c): return await c.get_element("character", "caf\u00e9")],
		["get_element (a type with a trailing newline)", "type", func(c): return await c.get_element("character\n", UUID)],
	]

func get_cases() -> Array:
	var out := []
	for k in _refused():
		var name: String = k[0]
		var what: String = k[1]
		var fn: Callable = k[2]
		out.append(["wire: %s, a value that is not one segment is refused before sending" % name, func(t) -> void:
			var fake = Fake.new()
			fake.body = "{\"id\":\"x\",\"name\":\"x\",\"data\":[],\"has_more\":false}"
			var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})
			var r: OWClient.Reply = await fn.call(c)
			t.ok(not r.ok, "%s: refused" % name)
			if not r.ok:
				t.eq(r.error.kind, OWApiError.REFUSED, name + ": a refusal, not an answer")
				t.ok(r.error.message.begins_with(what + " \""), "%s: names the %s: %s" % [name, what, r.error.message])
				t.ok(r.error.message.ends_with(" is not one path segment. Nothing was sent."), "%s: says why: %s" % [name, r.error.message])
			t.eq(fake.calls.size(), 0, name + ": nothing was sent")
			t.done()])
	out.append(["wire: the refusal names the value as JSON", func(t) -> void:
		var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": Fake.new()})
		var r: OWClient.Reply = await c.get_element("character", ID)
		t.eq(r.error.message, "id \"%s/hidden\" is not one path segment. Nothing was sent." % UUID, "the message")
		t.done()])
	out.append(["wire: a value that is one segment goes out as given", func(t) -> void:
		var fake = Fake.new()
		fake.body = "{\"id\":\"x\",\"name\":\"x\",\"data\":[],\"has_more\":false}"
		var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "0000", "base_url": BASE, "transport": fake})
		await c.get_element("character", UUID)
		await c.get_element("character", "a.b_c-D9")
		await c.edit_links("character", UUID, "friends", {"add": []})
		await c.get_element("pin_x2", "9")
		t.eq(fake.calls.map(func(q): return String(q.url).split("?")[0].trim_prefix(BASE)),
			["/character/%s/" % UUID, "/character/a.b_c-D9/", "/character/%s/links/friends" % UUID, "/pin_x2/9/"], "the paths")
		t.done()])
	return out
