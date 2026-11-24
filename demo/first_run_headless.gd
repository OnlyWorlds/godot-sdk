extends SceneTree

func _init() -> void:
	await process_frame   # TLS starts with the first frame: an https request before it gets no answer
	var client := OWClient.new({"api_key": "0000000001"})   # demo key: Moppetopia, read-only
	var world := await client.get_world()
	if not world.ok:
		print(world.error)
		quit(1)
		return
	print(world.value["name"])
	var found := await client.list("character", {"name_contains": "fluffington"})
	print(found.value.data[0].name)
	quit()
