extends RefCounted
## OWHttpTransport against a real socket on 127.0.0.1 (tests/cut_server.gd), for what goes on the wire: an upload's
## bytes (a PackedByteArray body) arrive byte for byte, NUL and 0xFF included, with their Content-Length and no
## Content-Type; a JSON body (a String) as before; and a POST, PUT or PATCH with no body says so with
## Content-Length: 0, as fetch does, on every call that sends one (accept_proposal, decline_proposal with no reason,
## create_media_ticket, and remove_image's send to the host). A read or a DELETE declares no length.

const Srv := preload("res://tests/cut_server.gd")
const ANSWER := "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"

## [server, port]: a server answering [constant ANSWER] once.
static func _listen(answer := ANSWER) -> Array:
	var srv = Srv.new()
	return [srv, srv.start(answer)]

static func _lines(head: String) -> PackedStringArray:
	return head.split("\r\n")

static func _header(head: String, name: String) -> Variant:
	for line in _lines(head).slice(1):
		if line.to_lower().begins_with(name.to_lower() + ":"):
			return line.get_slice(":", 1).strip_edges()
	return null

func test_an_uploads_bytes_arrive_byte_for_byte_with_no_media_type(t) -> void:
	var bytes := PackedByteArray([0x89, 0x50, 0x00, 0xff, 0x0a, 0x00, 0x80, 0xc3])
	var s := _listen()
	var r: OWTransport.Response = await OWHttpTransport.new().send(OWTransport.Request.make("POST",
		"http://127.0.0.1:%d/v1/upload" % s[1], {"Authorization": "Bearer t.sig"}, bytes))
	s[0].stop()
	t.eq(r.status, 201, "answered (%s)" % r.failure)
	t.eq(s[0].request_body, bytes, "the bytes as given")
	t.eq(_header(s[0].request_head, "Content-Length"), "8", "")
	t.eq(_header(s[0].request_head, "Content-Type"), null, "no media type: the host reads it from the bytes")
	t.eq(_header(s[0].request_head, "Authorization"), "Bearer t.sig", "")
	t.ok(_lines(s[0].request_head)[0] == "POST /v1/upload HTTP/1.1", s[0].request_head)
	t.done()

func test_a_json_body_goes_as_before(t) -> void:
	var text := "{\"name\":\"Ané\"}"
	var s := _listen()
	var r: OWTransport.Response = await OWHttpTransport.new().send(OWTransport.Request.make("POST",
		"http://127.0.0.1:%d/api/v2/character/" % s[1], {"Content-Type": "application/json"}, text))
	s[0].stop()
	t.eq(r.status, 201, "answered (%s)" % r.failure)
	t.eq(s[0].request_body, text.to_utf8_buffer(), "its UTF-8 bytes")
	t.eq(_header(s[0].request_head, "Content-Length"), str(text.to_utf8_buffer().size()), "")
	t.done()

func test_an_empty_upload_is_a_length_of_zero(t) -> void:
	var s := _listen()
	await OWHttpTransport.new().send(OWTransport.Request.make("POST", "http://127.0.0.1:%d/v1/file" % s[1], {}, PackedByteArray()))
	s[0].stop()
	t.eq(_header(s[0].request_head, "Content-Length"), "0", s[0].request_head)
	t.done()

## The head [param call] sent, on a client whose base_url is a server on 127.0.0.1.
static func _head_of(call: Callable) -> String:
	var s := _listen()
	var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "1234", "base_url": "http://127.0.0.1:%d/api/v2" % s[1]})
	await call.call(c, s[1])
	s[0].stop()
	return s[0].request_head

func test_every_bodiless_post_says_content_length_zero(t) -> void:
	var calls := [
		["accept_proposal", func(c, _p): await c.accept_proposal("character", "c1", "p1")],
		["decline_proposal with no reason", func(c, _p): await c.decline_proposal("character", "c1", "p1")],
		["create_media_ticket", func(c, _p): await c.create_media_ticket()],
		["remove_image's send to the host", func(c, p): await c.remove_image("u/w1/x.png", {"ticket": {"ticket": "d1.sig",
			"remove_url": "http://127.0.0.1:%d/v1/remove" % p}})],
	]
	for k in calls:
		var head := await _head_of(k[1])
		t.ok(head.begins_with("POST "), "%s: a POST (%s)" % [k[0], head.get_slice("\r\n", 0)])
		t.eq(_header(head, "Content-Length"), "0", "%s: Content-Length: 0" % k[0])
		t.eq(_header(head, "Content-Type"), null, "%s: no body, no media type" % k[0])
	t.done()

func test_a_read_and_a_delete_declare_no_length(t) -> void:
	var get_head := await _head_of(func(c, _p): await c.get_element("character", "c1"))
	t.eq(_header(get_head, "Content-Length"), null, "a GET")
	var delete_head := await _head_of(func(c, _p): await c.delete("character", "c1"))
	t.eq(_header(delete_head, "Content-Length"), null, "a DELETE")
	t.done()
