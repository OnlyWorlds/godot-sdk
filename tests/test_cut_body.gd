extends RefCounted
## OWHttpTransport against a real socket on 127.0.0.1 (tests/cut_server.gd): an answer cut off while its body is read
## (a body shorter than its Content-Length, a chunked body with no last chunk) is kind TRANSPORT, never a value or an
## ANSWER; a whole answer, read to the end of the connection or to its length or its last chunk, is the value. Mirrors
## the TypeScript SDK's 4.223.1 test of the same name.

const Srv := preload("res://tests/cut_server.gd")
const HEAD := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
const LOST := "the answer was lost while it was read"

## Sends [param call] ("get" or "delete") to a server answering [param answer]; answers the Reply.
static func _send(answer: String, call: String) -> OWClient.Reply:
	var srv = Srv.new()
	var port: int = srv.start(answer)
	var c := OWClient.new({"api_key": "ow_w_test", "api_pin": "1234", "base_url": "http://127.0.0.1:%d/api/v2" % port})
	var r: OWClient.Reply
	if call == "delete":
		r = await c.delete("character", "x")
	else:
		r = await c.get_element("character", "x")
	srv.stop()
	return r

static func _lost(t, r: OWClient.Reply, method: String, label: String) -> void:
	t.ok(not r.ok, "%s: not a value" % label)
	if r.ok:
		return
	t.eq([r.error.kind, r.error.status], [OWApiError.TRANSPORT, 0], "%s: kind (%s)" % [label, r.error.message])
	t.ok(r.error.message.begins_with("OnlyWorlds request failed: %s /character/x/: " % method)
		and r.error.message.contains(LOST), "%s: %s" % [label, r.error.message])

func test_a_body_shorter_than_its_length_is_a_transport_failure(t) -> void:
	_lost(t, await _send(HEAD + "Content-Length: 100\r\n\r\n{\"id\":\"x\"}", "get"), "GET", "cut, parses")
	_lost(t, await _send(HEAD + "Content-Length: 100\r\n\r\n{\"id\":\"x\",\"na", "get"), "GET", "cut, broken")
	_lost(t, await _send(HEAD + "Content-Length: 100\r\n\r\n", "delete"), "DELETE", "no bytes, DELETE")
	t.done()

func test_a_chunked_body_cut_before_its_last_chunk_is_a_transport_failure(t) -> void:
	_lost(t, await _send(HEAD + "Transfer-Encoding: chunked\r\n\r\na\r\n{\"id\":\"x\"}\r\n", "get"), "GET", "after a chunk")
	_lost(t, await _send(HEAD + "Transfer-Encoding: chunked\r\n\r\n14\r\n{\"id\":\"x\"}", "get"), "GET", "inside a chunk")
	t.done()

func test_a_whole_answer_is_the_value(t) -> void:
	for k in [
		["read to the end of the connection", HEAD + "Connection: close\r\n\r\n{\"id\":\"x\",\"name\":\"whole\"}"],
		["its length", HEAD + "Content-Length: 25\r\n\r\n{\"id\":\"x\",\"name\":\"whole\"}"],
		["its last chunk", HEAD + "Transfer-Encoding: chunked\r\n\r\n19\r\n{\"id\":\"x\",\"name\":\"whole\"}\r\n0\r\n\r\n"],
	]:
		var r := await _send(k[1], "get")
		t.ok(r.ok, "%s: %s" % [k[0], r.error])
		t.eq(r.value.get("name") if r.ok else null, "whole", k[0])
	var d := await _send("HTTP/1.1 204 No Content\r\n\r\n", "delete")
	t.ok(d.ok, "a 204 with no body: %s" % d.error)
	# A 204 has no body, whatever its headers say: one that declares a length and closes is still whole.
	d = await _send("HTTP/1.1 204 No Content\r\nContent-Length: 5\r\n\r\n", "delete")
	t.ok(d.ok, "a 204 that declares a length: %s" % d.error)
	t.done()

func test_a_whole_body_that_is_not_json_is_still_kind_answer(t) -> void:
	var r := await _send(HEAD + "Content-Length: 5\r\n\r\n<html", "get")
	t.eq(r.error.kind if not r.ok else null, OWApiError.ANSWER, "the body came whole: the answer's fault, not the line's")
	t.done()
