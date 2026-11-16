extends RefCounted
## The front door's packet as a server serves it (schema-dist profiles/strand.md rule 2, serial 100, and
## profiles/charter.md rule 2): GET /me and an agent's join reply carry [code]reading_aids[/code], the Charter, the
## Guide, the Domains, then [code]strand[/code], the six slots of the strand as that key reads the world, six null slots
## when the world has none or its story is out of the key's view. The bodies are keel's READING_AIDS_SCHEMA
## (accounts/front_door.py) field for field, the slots as keel's tests/test_strand_front_door.py serves them.

const FULL := {
	"narrative": {"id": "019a7f00-0000-7000-8000-000000000301", "type": "narrative", "name": "The Night the Lighthouse Went Dark"},
	"event": {"id": "019a7f00-0000-7000-8000-000000000311", "type": "event", "name": "The lamp fails"},
	"location": {"id": "019a7f00-0000-7000-8000-000000000321", "type": "location", "name": "The Lighthouse"},
	"character": {"id": "019a7f00-0000-7000-8000-000000000331", "type": "character", "name": "Ilse the Keeper"},
	"now": {"id": "019a7f00-0000-7000-8000-000000000322", "type": "location", "name": "The Docks"},
	"same": false,
}
const EMPTY := {"narrative": null, "event": null, "location": null, "character": null, "now": null, "same": null}

func _me(strand: Variant) -> Dictionary:
	var aids := {"charter": {"id": "law-1", "type": "law", "name": "House rules", "rules": [], "skill": []},
		"guide": {"id": "con-g", "type": "construct", "name": "Start here"}, "domains": []}
	if strand != null:
		aids["strand"] = strand
	return {"world": {"id": "w1", "name": "W"}, "kind": "owner", "front_door": {"charter": "law-1"},
		"reading_aids": aids}

func test_me_reads_the_served_strand_every_slot(t) -> void:
	var me := _me(FULL.duplicate(true))
	var aids := OWCharter.served(me)
	t.ok(aids != null, "the packet is read")
	t.ok(aids.strand is OWStrand.Strand, "a served strand is read as the engine's strand")
	if aids.strand is OWStrand.Strand:
		t.eq(aids.strand.narrative, FULL["narrative"], "the story")
		t.eq(aids.strand.event, FULL["event"], "the happening")
		t.eq(aids.strand.location, FULL["location"], "the place, then")
		t.eq(aids.strand.character, FULL["character"], "the hero")
		t.eq(aids.strand.now, FULL["now"], "the place, now")
		t.eq(aids.strand.same, false, "same, as served")
		t.eq(aids.strand.to_dict(), FULL, "the six slots as served")
	t.eq(aids.to_dict(), me["reading_aids"], "read back, the packet as served, the strand in it")
	t.done()

func test_six_null_slots_read_as_an_empty_strand_not_as_none(t) -> void:
	var aids := OWCharter.served(_me(EMPTY.duplicate(true)))
	t.ok(aids.strand is OWStrand.Strand, "six null slots are a strand served empty, not an absent key")
	if aids.strand is OWStrand.Strand:
		t.eq(aids.strand.to_dict(), EMPTY, "six nulls")
	t.eq(aids.to_dict().get("strand"), EMPTY, "six nulls written back")
	t.done()

func test_a_packet_without_the_key_has_no_strand(t) -> void:
	# A keel from before serial 100 serves {charter, guide, domains}.
	var aids := OWCharter.served(_me(null))
	t.eq(aids.strand, null, "an absent key reads as absent")
	t.eq(aids.to_dict().keys(), ["charter", "guide", "domains"], "and writes none")
	t.done()

func test_the_strand_comes_fourth(t) -> void:
	# The charter profile's rule 2: the Charter, the Guide, the Domains, then the strand.
	t.eq(OWCharter.served(_me(EMPTY.duplicate(true))).to_dict().keys(), ["charter", "guide", "domains", "strand"],
		"the order")
	t.done()

func test_a_served_slot_is_read_as_served(t) -> void:
	# Then and now one place: same as served. A slot served with no name reads "".
	var aids := OWCharter.served(_me({"narrative": {"id": "n-1", "name": "The Crossing"}, "event": null,
		"location": {"id": "loc-1", "name": null}, "character": {"id": "c-1", "name": "The Judge"},
		"now": {"id": "loc-1", "name": null}, "same": true}))
	t.eq(aids.strand.same, true, "same, as served")
	t.eq(aids.strand.event, null, "an empty slot")
	t.eq(aids.strand.location, {"id": "loc-1", "type": "location", "name": ""}, "a nameless slot reads an empty name")
	t.eq(aids.strand.now, {"id": "loc-1", "type": "location", "name": ""}, "the place, now")
	t.done()

func test_entries_served_without_a_type_read_their_fixed_type(t) -> void:
	# A keel from before serial 134 serves {id, name}: each aid's type is fixed by its pair, each slot's by its slot.
	var me := {"reading_aids": {"charter": {"id": "law-1", "name": "House rules", "rules": [], "skill": []},
		"guide": {"id": "con-g", "name": "Start here"},
		"domains": [{"id": "con-d1", "name": "The Harbour", "sentence": "", "hubs": []}],
		"strand": {"narrative": {"id": "n-1", "name": "N"}, "event": {"id": "e-1", "name": "E"},
			"location": {"id": "loc-1", "name": "L"}, "character": {"id": "c-1", "name": "C"},
			"now": {"id": "loc-2", "name": "M"}, "same": false}}}
	var before := me.duplicate(true)
	var aids := OWCharter.served(me)
	t.eq(aids.charter["type"], "law", "the Charter")
	t.eq(aids.guide["type"], "construct", "the Guide")
	t.eq(aids.domains[0]["type"], "construct", "a Domain")
	t.eq(aids.charter.keys(), ["id", "type", "name", "rules", "skill"], "the page's order")
	t.eq(aids.domains[0].keys(), ["id", "type", "name", "sentence", "hubs"], "the page's order")
	var s: OWStrand.Strand = aids.strand
	t.eq([s.narrative["type"], s.event["type"], s.location["type"], s.character["type"], s.now["type"]],
		["narrative", "event", "location", "character", "location"], "each slot's kind, now a location")
	t.eq(s.now.keys(), ["id", "type", "name"], "the page's order")
	t.eq(me, before, "the answer is as it was")
	t.done()

func test_an_agents_join_answer_carries_the_strand(t) -> void:
	# keel's test: the hero hidden from the new seat, so the hero's two slots and same are null.
	var partial := {"narrative": {"id": "n-1", "type": "narrative", "name": "The Gang"},
		"event": {"id": "e-1", "type": "event", "name": "The Crossing"},
		"location": {"id": "loc-1", "type": "location", "name": "The River"}, "character": null, "now": null, "same": null}
	var joined := {"kind": "agent", "key": "ow_w_seat", "front_door": {"charter": null},
		"reading_aids": {"charter": null, "guide": null, "domains": [], "strand": partial}}
	var aids := OWCharter.served(joined)
	t.eq(aids.charter, null, "no Charter")
	t.eq(aids.strand.to_dict(), partial, "the strand as the seat reads it")
	t.done()

func test_an_answer_without_the_packet_reads_none(t) -> void:
	# A player's join answer, an older keel: no reading_aids at all.
	t.eq(OWCharter.served({"kind": "player", "key": "ow_r_guest"}), null, "no packet")
	t.eq(OWCharter.served(null), null, "nothing")
	t.done()

func test_reading_never_moves_the_answer(t) -> void:
	var me := _me(FULL.duplicate(true))
	var before := me.duplicate(true)
	var aids := OWCharter.served(me)
	aids.strand.narrative["name"] = "changed"
	t.eq(me, before, "the answer is as it was")
	t.done()
