extends Node

func _ready() -> void:
	var client := OWClient.new({"api_key": "0000000001"})   # demo key: Moppetopia, read-only
	var world := await client.get_world()
	if not world.ok:
		print(world.error)   # no connection, or the server said why
		return
	print(world.value["name"])

	var found := await client.list("character", {"name_contains": "fluffington"})
	print(found.value.data[0].name)
