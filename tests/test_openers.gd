extends RefCounted
## OWOpeners.openers_for on every case of the npm SDK's and the Python package's shared fixture
## (tests/data/openers.fixture.json, the same bytes, held by its sha256): each expected row compared whole, each
## refusal by the address refusal's reason or by the key its message names. Then OWTools.ALL, the baked tools list,
## through the same function.

const P = preload("res://tests/paths.gd")

const FIXTURE_SHA256 := "0cbd1de0daa3535fbf36dcd502a611c6d960db827cfe88f5045f0a1a49d65ea0"
const CASES := 61

const WORLD := "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e0f"
const ELEMENT := "0199c3a1-7b2e-7c3d-8e4f-5a6b7c8d9e1a"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(P.OPENERS))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["cases"]:
		out.append(["openers:" + c["name"], _case.bind(c)])
	return out

func _case(t, c: Dictionary) -> void:   # bound arguments come after the call's
	t.ok(_fixture()["lists"].has(c["tools"]), "no list %s" % c["tools"])
	t.eq(_answer(c), _want(c), "the rows")
	t.done()

func _want(c: Dictionary) -> Dictionary:
	return {"refuse": c["refuse"]} if c.has("refuse") else {"expect": c["expect"]}

## One case's answer in the fixture's own shape: {expect} or {refuse}.
func _answer(c: Dictionary) -> Dictionary:
	var r := OWOpeners.openers_for(_fixture()["lists"][c["tools"]], c["kind"], c["address"], c["surface"])
	if r.ok:
		return {"expect": r.rows}
	if r.reason != "":
		return {"refuse": {"error": "address", "reason": r.reason}}
	var refuse: Variant = c.get("refuse")
	if refuse is Dictionary and refuse["error"] == "type" and r.message.contains(refuse["names"]):
		return {"refuse": refuse}
	return {"refuse": {"error": "type", "message": r.message}}

func test_the_fixture_is_the_shared_bytes(t) -> void:
	t.eq(FileAccess.get_sha256(P.OPENERS), FIXTURE_SHA256, "the fixture's bytes are the packages'")
	t.done()

func test_every_case_is_answered_and_none_is_dropped(t) -> void:
	var cases: Array = _fixture()["cases"]
	t.eq(cases.size(), CASES, "%d cases" % CASES)
	var names := {}
	var answered := 0
	for c in cases:
		names[c["name"]] = true
		t.eq(_answer(c), _want(c), c["name"])
		answered += 1
	t.eq(names.size(), CASES, "every case's name is its own")
	t.eq(answered, CASES, "every case answered")
	t.done()

func test_a_reading_from_parse_link_gives_the_same_rows(t) -> void:
	var link := "https://www.onlyworlds.com/w/%s/character/%s@3?lens=%s" % [WORLD, ELEMENT, ELEMENT]
	var plain := {"form": "text", "world": WORLD, "type": "character", "id": ELEMENT}
	var surface := {"audience": "member", "signed_in": false}
	var read := OWOpeners.openers_for(OWTools.ALL, "element", OWAddress.parse_link(link), surface)
	var want := OWOpeners.openers_for(OWTools.ALL, "element", plain, surface)
	t.ok(read.ok and want.ok, "both read")
	t.eq(read.rows, want.rows, "the same rows")
	t.done()

func test_a_reading_by_slug_is_bad_world(t) -> void:
	var r := OWOpeners.openers_for(OWTools.ALL, "world", OWAddress.parse_link("https://www.onlyworlds.com/w/old-harbour"), {"audience": "member"})
	t.ok(not r.ok, "refused")
	t.eq(r.reason, "bad_world", "the reason")
	t.eq(r.rows, [], "no rows")
	t.done()

func test_the_baked_list_gives_the_sites_row_then_each_listed_tool_with_a_door(t) -> void:
	t.ok(OWTools.ALL.size() >= 1, "a row at least")
	var member := OWOpeners.openers_for(OWTools.ALL, "world", {"form": "human", "world": WORLD}, {"audience": "member", "signed_in": true})
	t.ok(member.ok, "read")
	var offered := OWTools.ALL.filter(func(x): return x["rung"] == "listed" and x["open"] != null and x["open"]["world"] != null)
	var ids := ["onlyworlds"]
	ids.append_array(offered.map(func(x): return x["id"]))
	t.eq(member.rows.map(func(x): return x["id"]), ids, "the site, then the list's order")
	t.eq(member.rows[0]["href"], "https://www.onlyworlds.com/w/" + WORLD, "the site's row")
	for row in member.rows.slice(1):
		var href: String = row["href"]
		t.ok(href.begins_with("https://") and href.contains(WORLD) and not href.contains("{"), href)
	var open := OWOpeners.openers_for(OWTools.ALL, "world", {"form": "human", "world": WORLD}, {"audience": "public"})
	var public_ids := ["onlyworlds"]
	public_ids.append_array(offered.filter(func(x): return x["open"]["needs"] == null).map(func(x): return x["id"]))
	t.eq(open.rows.map(func(x): return x["id"]), public_ids, "the public's rows")
	t.eq(OWTools.COMMIT.length(), 40, "the pinned commit")
	t.eq(OWTools.SHA256.length(), 64, "the list's sha256")
	t.done()

func test_a_game_outside_a_browser_says_opens_in_your_browser(t) -> void:
	var tools := [{"id": "zephyr", "name": "Zephyr", "url": "https://zephyr.example", "client": "zephyr", "rung": "listed",
		"open": {"world": "https://zephyr.example/{world}", "element": null, "needs": "account"}}]
	var r := OWOpeners.openers_for(tools, "element", {"world": WORLD, "type": "character", "id": ELEMENT, "form": "human"},
		{"audience": "member", "signed_in": false, "browser": false})
	t.ok(r.ok, "read: " + r.message)
	t.eq(r.rows.size(), 2, "two rows")
	t.eq(r.rows[1]["state"], OWOpeners.OPENS_IN_YOUR_BROWSER, "the word")
	t.eq(r.rows[1]["href"], "https://zephyr.example/" + WORLD, "the world door")
	t.done()

func test_an_online_that_is_not_a_boolean_is_refused_by_name(t) -> void:
	for value in ["no", null, 0, 1, "false"]:
		var r := OWOpeners.openers_for(OWTools.ALL, "world", {"form": "human", "world": WORLD}, {"audience": "member", "online": value})
		t.ok(not r.ok and r.reason == "", "refused as a mistake: %s" % value)
		t.ok(r.message.contains("surface online is a boolean"), "named: %s gave %s" % [value, r.message])
	t.done()

func test_offline_the_baked_list_keeps_every_href_and_online_is_the_default(t) -> void:
	var address := {"form": "human", "world": WORLD}
	var online := OWOpeners.openers_for(OWTools.ALL, "world", address, {"audience": "member", "signed_in": true})
	var also := OWOpeners.openers_for(OWTools.ALL, "world", address, {"audience": "member", "signed_in": true, "online": true})
	var offline := OWOpeners.openers_for(OWTools.ALL, "world", address, {"audience": "member", "signed_in": true, "online": false})
	t.ok(online.ok and also.ok and offline.ok, "all read")
	t.eq(also.rows, online.rows, "online true is the default")
	t.eq(offline.rows.map(func(x): return x["href"]), online.rows.map(func(x): return x["href"]), "every href stays")
	for row in offline.rows:
		var href: String = row["href"]
		var web := href.to_lower().begins_with("http:") or href.to_lower().begins_with("https:")
		t.eq(row["state"], OWOpeners.NEEDS_A_CONNECTION if web else null, href)
	t.done()

func test_offline_the_scheme_is_read_in_any_case_and_a_link_with_no_scheme_is_no_web_address(t) -> void:
	var tools := []
	for door in ["HTTPS://loud.example/{world}", "Http://plain.example/{world}", "app://open/{world}"]:
		tools.append({"id": "t%d" % tools.size(), "name": "T", "url": "https://t.example", "client": null, "rung": "listed",
			"open": {"world": door, "element": null, "needs": null}})
	var r := OWOpeners.openers_for(tools, "world", {"form": "human", "world": WORLD}, {"audience": "member", "online": false})
	t.ok(r.ok, "read: " + r.message)
	var c := OWOpeners.NEEDS_A_CONNECTION
	t.eq(r.rows.map(func(x): return x["state"]), [c, c, c, null], "the site, HTTPS:, Http: say it; app:// does not")
	t.done()

func test_every_scheme_that_opens_no_app_is_refused_in_either_door_and_any_case(t) -> void:
	for scheme in ["javascript", "data", "vbscript", "file", "blob", "about"]:
		for spelled in [scheme, scheme.to_upper(), scheme.capitalize()]:
			for key in ["world", "element"]:
				var open := {"world": "https://skiff.example/{world}", "element": null, "needs": null}
				open[key] = "%s:x/{world}" % spelled
				var tools := [{"id": "skiff", "name": "Skiff", "url": "https://skiff.example", "client": "skiff", "rung": "listed", "open": open}]
				var r := OWOpeners.openers_for(tools, "world", {"form": "human", "world": WORLD}, {"audience": "member"})
				t.ok(not r.ok and r.reason == "", "refused as a mistake: %s open.%s" % [spelled, key])
				t.ok(r.message.contains("tool skiff: open.%s is a %s: link, which opens no app" % [key, scheme]), "named: " + r.message)
	t.done()

func test_a_template_must_begin_with_its_scheme_and_a_null_one_is_still_null(t) -> void:
	for bad in ["", "//bare.example/{world}", " https://skiff.example/{world}", "1app://x", "{world}"]:
		var open := {"world": bad, "element": null, "needs": null}
		var tools := [{"id": "skiff", "name": "Skiff", "url": "https://skiff.example", "client": "skiff", "rung": "listed", "open": open}]
		var r := OWOpeners.openers_for(tools, "world", {"form": "human", "world": WORLD}, {"audience": "member"})
		t.ok(not r.ok and r.reason == "" and r.message.contains("tool skiff: open.world begins with its scheme"), "refused: '%s' gave %s" % [bad, r.message])
	var none := [{"id": "skiff", "name": "Skiff", "url": "https://skiff.example", "client": "skiff", "rung": "listed",
		"open": {"world": "https://skiff.example/{world}", "element": null, "needs": null}}]
	var ok := OWOpeners.openers_for(none, "world", {"form": "human", "world": WORLD}, {"audience": "member"})
	t.ok(ok.ok and ok.rows.size() == 2, "a null element template is still null")
	t.done()
