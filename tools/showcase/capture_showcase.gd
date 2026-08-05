extends SceneTree

const MANIFEST_PATH := "res://examples/showcase/manifest.json"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_position(Vector2i(-10000, -10000))
	var manifest_source := FileAccess.get_file_as_string(MANIFEST_PATH)
	var manifest = JSON.parse_string(manifest_source)
	if not manifest is Dictionary:
		push_error("Could not parse showcase manifest: %s" % MANIFEST_PATH)
		quit(1)
		return

	for demo in manifest.get("demos", []):
		var error := await _capture_demo(demo)
		if error != OK:
			quit(1)
			return
	quit(0)


func _capture_demo(demo: Dictionary) -> Error:
	var viewport: Array = demo["viewport"]
	root.size = Vector2i(int(viewport[0]), int(viewport[1]))
	var scene_path := "res://" + str(demo["godot_scene"])
	var output_path := "res://" + str(demo["godot_screenshot"])
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load showcase scene: %s" % scene_path)
		return ERR_CANT_OPEN

	var instance := packed_scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	await process_frame

	var texture := root.get_texture()
	if texture == null:
		push_error("The active display driver does not expose a viewport texture.")
		return ERR_UNAVAILABLE
	var image := texture.get_image()
	if image == null or image.is_empty():
		push_error("Godot returned an empty showcase capture for %s." % scene_path)
		return ERR_CANT_CREATE

	var absolute_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	var save_error := image.save_png(absolute_output)
	if save_error != OK:
		push_error("Could not save showcase capture: error %s" % save_error)
		return save_error

	print("Captured %s at %s×%s." % [output_path, image.get_width(), image.get_height()])
	instance.queue_free()
	await process_frame
	return OK
