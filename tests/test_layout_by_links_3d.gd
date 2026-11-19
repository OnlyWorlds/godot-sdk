extends RefCounted
## OWLayout's by-links-3d on its own fixture: the pinned dist's profiles/layout-by-links-3d.fixture.json (the default
## layouts page, profiles/layout.md, serial 137 on), read from the vendored folder, with the directions table beside it.
## Its unplaced suite (9 cases) is read whole here: one case each, the list equal exactly and in its order.

const FIXTURE := "res://codegen/schema-dist/profiles/layout-by-links-3d.fixture.json"
const FIXTURE_SHA256 := "acd6da7252493485cafc24356a84c53656d078872a28c695c0f7554009b6fb2a"
const TABLE := "res://codegen/schema-dist/profiles/layout-by-links-3d.directions.json"
const TABLE_SHA256 := "37dc2bbb4a1769e4ddafc2d0a27c9889229c3ef483e8f7cd6c9ba66a0d1afb87"

var _doc: Dictionary

func _fixture() -> Dictionary:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return _doc

func get_cases() -> Array:
	var out := []
	for c in _fixture()["unplaced"]:
		out.append(["layout-by-links-3d-unplaced:" + c["name"], _unplaced.bind(c["name"])])
	return out

func _unplaced(t, name: String) -> void:
	var c := {}
	for u in _fixture()["unplaced"]:
		if u["name"] == name:
			c = u
	var got := OWLayout.unplaced_by_links_3d(c["graph"].duplicate(true), c["placed"].duplicate(true))
	t.eq(got.get("error", ""), "", name + ": an answer")
	t.eq(got.get("method", ""), "by-links-3d", name + ": the method")
	t.eq(got.get("unplaced", null), c["want"], name + ": the ids, in the one order")
	t.done()

func test_the_fixture_and_its_table_are_the_pinned_dists_bytes(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://codegen/schema-dist/MANIFEST.json"))["files"]
	t.eq(FileAccess.get_sha256(FIXTURE), FIXTURE_SHA256, "the fixture's bytes are the ones this test pins")
	t.eq(manifest["profiles/layout-by-links-3d.fixture.json"], FIXTURE_SHA256, "the fixture's bytes are the pinned dist's")
	t.eq(FileAccess.get_sha256(TABLE), TABLE_SHA256, "the table's bytes are the ones this test pins")
	t.eq(manifest["profiles/layout-by-links-3d.directions.json"], TABLE_SHA256, "the table's bytes are the pinned dist's")
	t.eq(_fixture()["table_sha256"], TABLE_SHA256, "the fixture names the table by its sha256")
	t.eq(_fixture()["method"], "by-links-3d", "the method word")
	t.eq(_fixture()["cases"].size(), 116, "116 cases")
	t.eq(_fixture()["unplaced"].size(), 9, "nine unplaced cases")
	t.done()

func test_unplaced_by_links_3d_refuses_a_graph_it_cannot_count(t) -> void:
	t.ok(String(OWLayout.unplaced_by_links_3d(null, []).get("error", "")).contains("the graph is { nodes, edges }"), "no graph")
	t.ok(String(OWLayout.unplaced_by_links_3d({"nodes": [{"type": "pin"}], "edges": []}, []).get("error", "")).contains("node 0 has no id"), "no id")
	t.ok(String(OWLayout.unplaced_by_links_3d({"nodes": [{"id": "a"}, {"id": "a"}], "edges": []}, []).get("error", "")).contains("two nodes share the id a"), "an id twice")
	t.eq(OWLayout.unplaced_by_links_3d({"nodes": [{"id": "b", "type": "pin"}, {"id": "a", "type": "map"}], "edges": []}, ["b"]).get("unplaced"), ["a"], "any type counts")
	t.done()
