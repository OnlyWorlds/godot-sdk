extends RefCounted
## A one-answer HTTP server on 127.0.0.1 for the transport's own tests: it listens on a port the system picks, takes
## one connection on a thread of its own, reads the request's head and its body, writes the bytes it was given as they
## are, and closes. So a test can answer what no real server would answer on purpose: a body shorter than its
## Content-Length, a chunked body with no last chunk; and can read what was sent, byte for byte. [method stop] joins
## the thread and closes the listener; a test calls it before it ends.

var _server := TCPServer.new()
var _thread := Thread.new()
var _answer := PackedByteArray()
## The request's head as it arrived, without the blank line that ends it (for a test that checks what was sent).
var request_head := ""
## The request's body as it arrived, read to the head's [code]Content-Length[/code] (none declared: no body).
var request_body := PackedByteArray()
var _stopping := false

## Listens and starts serving [param answer]; answers the port, or 0 when nothing could listen.
func start(answer: String) -> int:
	_answer = answer.to_utf8_buffer()
	if _server.listen(0, "127.0.0.1") != OK:
		return 0
	_thread.start(_serve)
	return _server.get_local_port()

func _serve() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not _server.is_connection_available():
		if _stopping or Time.get_ticks_msec() > deadline:
			return
		OS.delay_msec(1)
	var peer := _server.take_connection()
	var got := PackedByteArray()
	var end := -1
	var want := -1
	while Time.get_ticks_msec() < deadline and (end < 0 or got.size() < want):
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		else:
			OS.delay_msec(1)
		if end < 0:
			end = _head_end(got)
			if end >= 0:
				request_head = got.slice(0, end).get_string_from_utf8()
				want = end + 4 + _content_length(request_head)
	if end >= 0:
		request_body = got.slice(end + 4)
	peer.put_data(_answer)
	peer.disconnect_from_host()

## Where the blank line that ends the head starts in [param got], or -1 before it has arrived.
static func _head_end(got: PackedByteArray) -> int:
	for i in range(got.size() - 3):
		if got[i] == 13 and got[i + 1] == 10 and got[i + 2] == 13 and got[i + 3] == 10:
			return i
	return -1

## The [code]Content-Length[/code] a head declares, 0 when it declares none.
static func _content_length(head: String) -> int:
	for line in head.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return line.get_slice(":", 1).strip_edges().to_int()
	return 0

## Joins the serving thread and closes the listener.
func stop() -> void:
	_stopping = true
	if _thread.is_started():
		_thread.wait_to_finish()
	_server.stop()
