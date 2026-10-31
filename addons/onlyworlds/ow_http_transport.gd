class_name OWHttpTransport
extends OWTransport
## [OWClient]'s default transport: Godot's own [HTTPClient], one connection a request, polled until the answer is in.
##
## [HTTPClient], not [HTTPRequest] (measured headless on 4.7.2, one GET to production's [code]/health/[/code] each):
## [HTTPRequest] is a Node and sends only from inside the scene tree ([method HTTPRequest.request] answers
## [code]ERR_UNCONFIGURED[/code] from a [SceneTree]'s [code]_init[/code], before its first frame), so a client that is
## a [RefCounted] would have to parent a node somewhere and could not send from a tool script or a test runner.
## [HTTPClient] needs no tree: it answered both polled between frames ([code]await process_frame[/code], 25 frames,
## 175 ms) and polled with no frame at all ([member blocking], 141 ms). What [HTTPRequest] adds is not wanted here: it
## follows redirects (a credential header would follow to another host) and asks for gzip; this sends no
## [code]Accept-Encoding[/code] and answers a redirect as it came.
##
## By default it waits a frame between polls ([code]await[/code] on the [SceneTree]'s [signal SceneTree.process_frame]),
## so a game keeps drawing while a request is out. With [member blocking] it polls without yielding, for a tool script
## or a runner that cannot wait a frame; it then holds the thread until the answer is in. With no running
## [SceneTree] it polls the same way. One limit, measured: inside a [SceneTree] script's [code]_init[/code], before its
## first frame, [method Engine.get_main_loop] is null and TLS does not start ([code]SSL module failed to
## initialize[/code]), so an [code]https[/code] request there answers no answer; await one
## [signal SceneTree.process_frame] first. Mirrors the TypeScript SDK's default [code]fetch[/code].

## Seconds from the start of a request to its whole answer; past it the request answers no answer.
var timeout_sec := 30.0
## Poll without yielding to the frame loop (see the class description).
var blocking := false
## The TLS options for [code]https[/code], or null for [method TLSOptions.client] (the system's certificates).
var tls_options: TLSOptions = null

const _METHODS := {
	"GET": HTTPClient.METHOD_GET, "POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH, "DELETE": HTTPClient.METHOD_DELETE, "HEAD": HTTPClient.METHOD_HEAD,
}

## [param url] as [code][scheme, host, port, path and query][/code], or an empty array when it is not an
## [code]http[/code] or [code]https[/code] URL with a host. The path is [code]/[/code] when the URL names none.
static func split_url(url: String) -> Array:
	var scheme := ""
	for s in ["https", "http"]:
		if url.begins_with(s + "://"):
			scheme = s
			break
	if scheme == "":
		return []
	var rest := url.substr(scheme.length() + 3)
	var cut := rest.length()
	for ch in ["/", "?"]:
		var i := rest.find(ch)
		if i != -1 and i < cut:
			cut = i
	var authority := rest.substr(0, cut)
	var path := rest.substr(cut)
	if path == "" or path.begins_with("?"):
		path = "/" + path
	var host := authority
	var port := 443 if scheme == "https" else 80
	var colon := authority.rfind(":")
	if colon != -1 and not authority.ends_with("]"):
		var p := authority.substr(colon + 1)
		if not p.is_valid_int():
			return []
		port = p.to_int()
		host = authority.substr(0, colon)
	if host == "":
		return []
	return [scheme, host, port, path]

## Send [param request] over a fresh connection and answer the status, headers and body; a request that gets no
## answer answers status 0 and why. Mirrors the TypeScript SDK's [code]fetch[/code] call in [code]request()[/code].
func send(request: OWTransport.Request) -> OWTransport.Response:
	var out := OWTransport.Response.new()
	var parts := split_url(request.url)
	if parts.is_empty():
		out.failure = "not an http or https URL with a host: %s" % request.url
		return out
	if not _METHODS.has(request.method):
		out.failure = "no such method for HTTPClient: %s" % request.method
		return out
	var tls: TLSOptions = null
	if parts[0] == "https":
		tls = tls_options if tls_options != null else TLSOptions.client()
	var c := HTTPClient.new()
	var started := Time.get_ticks_msec()
	var err := c.connect_to_host(parts[1], parts[2], tls)
	if err != OK:
		out.failure = "could not start a connection to %s:%d (%s)" % [parts[1], parts[2], error_string(err)]
		return out
	while c.get_status() == HTTPClient.STATUS_RESOLVING or c.get_status() == HTTPClient.STATUS_CONNECTING:
		c.poll()
		if _late(started):
			return _gave_up(c, out, "connecting to %s" % parts[1])
		await _pause()
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		out.failure = "could not connect to %s:%d (%s)" % [parts[1], parts[2], _status_word(c.get_status())]
		c.close()
		return out
	var lines := PackedStringArray()
	for name: String in request.headers:
		lines.append("%s: %s" % [name, request.headers[name]])
	err = c.request(_METHODS[request.method], parts[3], lines, request.body if request.body is String else "")
	if err != OK:
		out.failure = "could not send %s %s (%s)" % [request.method, request.url, error_string(err)]
		c.close()
		return out
	while c.get_status() == HTTPClient.STATUS_REQUESTING:
		c.poll()
		if _late(started):
			return _gave_up(c, out, "waiting for %s's answer" % parts[1])
		await _pause()
	if c.get_status() != HTTPClient.STATUS_BODY and c.get_status() != HTTPClient.STATUS_CONNECTED:
		out.failure = "no answer from %s (%s)" % [parts[1], _status_word(c.get_status())]
		c.close()
		return out
	var code := c.get_response_code()
	var headers := c.get_response_headers_as_dictionary()
	var body := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk := c.read_response_body_chunk()
		if chunk.is_empty():
			if _late(started):
				return _gave_up(c, out, "reading %s's answer" % parts[1])
			await _pause()
		else:
			body.append_array(chunk)
	c.close()
	out.status = code
	out.headers = headers
	out.body = body.get_string_from_utf8()
	return out

func _late(started: int) -> bool:
	return Time.get_ticks_msec() - started > int(timeout_sec * 1000.0)

func _gave_up(c: HTTPClient, out: OWTransport.Response, doing: String) -> OWTransport.Response:
	c.close()
	out.failure = "timed out after %s s %s" % [timeout_sec, doing]
	return out

## A frame when there is a running tree to wait on, else a millisecond on this thread.
func _pause() -> void:
	var loop := Engine.get_main_loop()
	if blocking or not (loop is SceneTree):
		OS.delay_msec(1)
		return
	await (loop as SceneTree).process_frame

static func _status_word(s: int) -> String:
	match s:
		HTTPClient.STATUS_DISCONNECTED: return "disconnected"
		HTTPClient.STATUS_CANT_RESOLVE: return "cannot resolve the host"
		HTTPClient.STATUS_CANT_CONNECT: return "cannot connect"
		HTTPClient.STATUS_CONNECTION_ERROR: return "connection error"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return "TLS handshake error"
	return "status %d" % s
