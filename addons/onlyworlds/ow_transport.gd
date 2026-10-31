class_name OWTransport
extends RefCounted
## The seam between [OWClient]'s wire logic and however bytes move: one request in, one response out. [OWClient]
## builds every request (the URL, its query, the credential headers) and reads every answer; a transport only sends.
##
## It exists so the client is tested without a network (a fake records each request and answers from a script: the
## tests assert on what the client would have sent), and so a game can move bytes its own way (a proxy, a cache, a
## platform's own HTTP). [OWHttpTransport] is the default, on Godot's [HTTPClient]. A transport subclasses this and
## overrides [method send], awaiting whatever it needs; the client always calls it with [code]await[/code].
##
## A transport never raises: a request that got no answer (no connection, a timeout, a URL it cannot read) answers
## status 0 with [member Response.failure] saying why, which the client turns into an [OWApiError] of kind
## [constant OWApiError.TRANSPORT].

## A request the client wants sent.
class Request:
	## [code]GET[/code], [code]POST[/code], [code]PUT[/code], [code]PATCH[/code] or [code]DELETE[/code].
	var method := "GET"
	## The whole URL, its query escaped.
	var url := ""
	## Header name -> value, as the client names them ([code]API-Key[/code], [code]If-None-Match[/code]).
	var headers := {}
	## The serialized JSON body, or null for a bodiless request (every read).
	var body: Variant = null

	static func make(m: String, u: String, h: Dictionary, b: Variant = null) -> Request:
		var r := Request.new()
		r.method = m
		r.url = u
		r.headers = h
		r.body = b
		return r

## What came back.
class Response:
	## The HTTP status, or 0 when no answer came ([member failure] says why).
	var status := 0
	## Header name -> value, as received (keel sends them lowercase); read them with [method header].
	var headers := {}
	## The body as text (UTF-8), "" for none.
	var body := ""
	## Why no answer came, or "" when one did.
	var failure := ""

	## True for a 2xx.
	func is_success() -> bool:
		return status >= 200 and status < 300

	## A header's value by name, ignoring case (HTTP names are case-insensitive, and keel sends them lowercase), or
	## null when it is absent.
	func header(name: String) -> Variant:
		for k: String in headers:
			if k.nocasecmp_to(name) == 0:
				return headers[k]
		return null

## Send [param request] and answer what came back. Overridden by every transport; the client awaits it. This base
## answers no request.
func send(request: Request) -> Response:
	var r := Response.new()
	r.failure = "OWTransport.send is not overridden: this transport sends nothing (%s %s)" % [request.method, request.url]
	return r
