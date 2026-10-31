extends OWTransport
## Records what the client would have sent, and answers from a script: no network. Each answer scripted with
## [method then] (or [method fail]) is given once, in order; after them, [member status], [member body] and
## [member headers] answer every request.

## Every request sent, in order ([OWTransport.Request]).
var calls: Array = []
var status := 200
var body := "{}"
var headers := {}

var _script: Array = []

## Scripts one answer: its status, body and headers ([code]{"etag": ...}[/code] for a tip read's tag).
func then(answer_status: int, answer_body: String, answer_headers := {}) -> void:
	_script.append([answer_status, answer_body, answer_headers, ""])

## Scripts one request that gets no answer (a dropped connection), with the transport's reason.
func fail(reason: String) -> void:
	_script.append([0, "", {}, reason])

func send(request: OWTransport.Request) -> OWTransport.Response:
	calls.append(request)
	var a: Array = _script.pop_front() if not _script.is_empty() else [status, body, headers, ""]
	var r := OWTransport.Response.new()
	r.status = a[0]
	r.body = a[1]
	r.headers = a[2]
	r.failure = a[3]
	return r

## The last request sent.
func last() -> OWTransport.Request:
	return calls[-1]
