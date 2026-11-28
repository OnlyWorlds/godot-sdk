extends RefCounted
## A one-answer HTTP server on 127.0.0.1 for the transport's own tests: it listens on a port the system picks, takes
## one connection on a thread of its own, reads the request's head, writes the bytes it was given as they are, and
## closes. So a test can answer what no real server would answer on purpose: a body shorter than its Content-Length,
## a chunked body with no last chunk. [method stop] joins the thread and closes the listener; a test calls it before
## it ends.

var _server := TCPServer.new()
var _thread := Thread.new()
var _answer := PackedByteArray()
## The request's head as it arrived (for a test that checks what was sent).
var request_head := ""
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
	while Time.get_ticks_msec() < deadline and not got.get_string_from_utf8().contains("\r\n\r\n"):
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		else:
			OS.delay_msec(1)
	request_head = got.get_string_from_utf8()
	peer.put_data(_answer)
	peer.disconnect_from_host()

## Joins the serving thread and closes the listener.
func stop() -> void:
	_stopping = true
	if _thread.is_started():
		_thread.wait_to_finish()
	_server.stop()
