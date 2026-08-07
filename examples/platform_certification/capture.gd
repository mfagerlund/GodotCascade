extends SceneTree

const SCENE_PATH := "res://examples/platform_certification/platform_certification.tscn"
const VIEWPORT_SIZE := Vector2i(1200, 760)


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DisplayServer.window_set_position(Vector2i(-10000, -10000))
	var output := _output_path()
	if output.is_empty():
		push_error("Capture requires --output=<absolute-png-path>")
		quit(2)
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	root.add_child(viewport)
	var instance := packed.instantiate()
	viewport.add_child(instance)
	for _frame in 8:
		await process_frame
	var document: Control = instance.cascade_document()
	if document == null or document.diagnostics.any(func(item): return item.get("severity", "error") == "error"):
		push_error("Platform certification fixture did not build cleanly: %s" % [document.diagnostics if document != null else []])
		quit(2)
		return
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Godot returned an empty platform certification capture")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := image.save_png(output)
	if error != OK:
		push_error("Could not save platform certification capture: %s" % error)
		quit(2)
		return
	print("CAPTURE_RESULT=%s:%dx%d" % [output, image.get_width(), image.get_height()])
	quit(0)


func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""
