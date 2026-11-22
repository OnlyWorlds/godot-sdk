extends RefCounted
## OWApiError.fields_refusal through a fake transport (tests/fake_transport.gd): a read whose fields list names fields
## its type does not have, refused in one 422 with every unknown name beside it. The TypeScript SDK's three tests
## (test/v2-client.test.mjs, 4.179.0), ported: the body is the server's answer to fields=name,story,hidden,narrator,
## nonsuch on a Character list, its allowed list cut to four names.

const Fake := preload("res://tests/fake_transport.gd")
const BASE := "https://example.test/api/v2"
const LIST_FIELDS := ["name", "story", "hidden", "narrator", "nonsuch"]

static func _refused() -> Dictionary:
	return {"error": {"type": "invalid_request", "code": "invalid_request",
		"message": "Unknown fields in ?fields: story, hidden, narrator, nonsuch", "param": "fields",
		"doc_url": "https://onlyworlds.github.io/api/errors/#invalid_request",
		"unknown_fields": ["story", "hidden", "narrator", "nonsuch"],
		"types_with_field": {"story": ["narrative"], "narrator": ["narrative"]},
		"allowed_fields": ["id", "name", "description", "supertype"]}}

## The error a list with a fields list answers when keel says [param answer_status] with [param body].
func _list_with_fields(answer_status: int, body: Dictionary) -> OWApiError:
	var fake = Fake.new()
	fake.then(answer_status, JSON.stringify(body, "", false))
	var c := OWClient.new({"api_key": "ow_r_test", "base_url": BASE, "transport": fake})
	var r: OWClient.Reply = await c.list("character", {"fields": LIST_FIELDS})
	return r.error

func test_fields_refusal_reads_the_three_keys_of_a_422_on_fields_as_served(t) -> void:
	var e: OWApiError = await _list_with_fields(422, _refused())
	t.ok(e != null, "the 422 is an error")
	t.eq(e.param, "fields", "its param")
	var r: OWApiError.FieldsRefusal = e.fields_refusal()
	t.ok(r != null, "a refusal")
	if r != null:
		t.eq(r.unknown_fields, ["story", "hidden", "narrator", "nonsuch"], "unknown_fields, in the order sent")
		t.eq(r.types_with_field, {"story": ["narrative"], "narrator": ["narrative"]}, "types_with_field")
		t.eq(r.types_with_field.keys(), ["story", "narrator"], "types_with_field as served, its order kept")
		t.eq(r.allowed_fields, ["id", "name", "description", "supertype"], "allowed_fields")
		t.eq(r.to_dict().keys(), ["unknown_fields", "types_with_field", "allowed_fields"], "the TypeScript SDK's shape")
	t.done()

func test_fields_refusal_is_null_on_any_other_error_each_condition_alone(t) -> void:
	# no unknown_fields: a server from before the keys, or another refusal that names fields
	var bare := _refused()
	bare["error"].erase("unknown_fields")
	t.eq((await _list_with_fields(422, bare)).fields_refusal(), null, "no unknown_fields")
	# the three keys under another param
	var other_param := _refused()
	other_param["error"]["param"] = "expand"
	t.eq((await _list_with_fields(422, other_param)).fields_refusal(), null, "another param")
	# the three keys under another status
	t.eq((await _list_with_fields(400, _refused())).fields_refusal(), null, "another status")
	# unknown_fields that is no list
	var not_list := _refused()
	not_list["error"]["unknown_fields"] = "story"
	t.eq((await _list_with_fields(422, not_list)).fields_refusal(), null, "unknown_fields no list")
	# beside the three: a body that is not JSON, and the client's own refusal, which sends nothing
	t.eq(OWApiError.from_response(422, "<html>fields</html>", {}).fields_refusal(), null, "a body that is not JSON")
	var mine := OWApiError.of(OWApiError.REFUSED, "list: fields is a list of names")
	mine.param = "fields"
	t.eq(mine.fields_refusal(), null, "the client's own refusal")
	t.done()

func test_fields_refusal_leaves_out_what_is_not_in_shape_and_answers_empty_for_a_key_left_out(t) -> void:
	var odd := _refused()
	odd["error"]["unknown_fields"] = ["story", 7, null]
	odd["error"]["types_with_field"] = {"story": ["narrative", 3], "narrator": "narrative"}
	odd["error"]["allowed_fields"] = ["id", {}, "name"]
	var r: OWApiError.FieldsRefusal = (await _list_with_fields(422, odd)).fields_refusal()
	t.ok(r != null, "a refusal")
	if r != null:
		t.eq(r.to_dict(), {"unknown_fields": ["story"], "types_with_field": {"story": ["narrative"]},
			"allowed_fields": ["id", "name"]}, "only the strings, and only the lists")
	var thin := _refused()
	thin["error"].erase("types_with_field")
	thin["error"].erase("allowed_fields")
	r = (await _list_with_fields(422, thin)).fields_refusal()
	t.ok(r != null, "a refusal")
	if r != null:
		t.eq(r.to_dict(), {"unknown_fields": ["story", "hidden", "narrator", "nonsuch"], "types_with_field": {},
			"allowed_fields": []}, "a key left out reads empty")
	var listed := _refused()
	listed["error"]["types_with_field"] = [["story", ["narrative"]]]
	r = (await _list_with_fields(422, listed)).fields_refusal()
	t.eq(r.types_with_field if r != null else null, {}, "a types_with_field that is a list reads empty")
	t.done()
