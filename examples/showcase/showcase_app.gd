extends Control

## Runnable manifest-driven shell for manually exercising every native showcase page.

signal page_changed(index: int, demo_id: String, scene: Control)

const MANIFEST_PATH := "res://examples/showcase/manifest.json"

var _demos: Array = []
var _current_index := -1
var _current_scene: Control
var _page_selector: OptionButton
var _page_title: Label
var _status: Label
var _previous_button: Button
var _next_button: Button
var _viewport_container: SubViewportContainer
var _showcase_viewport: SubViewport


func _ready() -> void:
	_build_shell()
	if not _load_manifest():
		return
	_populate_selector()
	var initial_index := _requested_page_index()
	await show_page(initial_index)


func page_count() -> int:
	return _demos.size()


func current_page_index() -> int:
	return _current_index


func current_page_id() -> String:
	return str(_demos[_current_index].get("id", "")) if _current_index >= 0 and _current_index < _demos.size() else ""


func current_showcase_scene() -> Control:
	return _current_scene


func current_status() -> String:
	return _status.text if _status != null else ""


func show_page(index: int) -> bool:
	if index < 0 or index >= _demos.size():
		_set_status("Page %s is outside the showcase manifest." % index, true)
		return false
	var demo: Dictionary = _demos[index]
	var scene_path := "res://" + str(demo.get("godot_scene", ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_set_status("Could not load %s" % scene_path, true)
		return false
	if _current_scene != null:
		_showcase_viewport.remove_child(_current_scene)
		_current_scene.free()
		_current_scene = null
	var authored_viewport: Array = demo.get("viewport", [960, 540])
	var viewport_size := Vector2i(int(authored_viewport[0]), int(authored_viewport[1]))
	_showcase_viewport.size = viewport_size
	_viewport_container.custom_minimum_size = Vector2(viewport_size)
	_current_scene = packed.instantiate() as Control
	if _current_scene == null:
		_set_status("%s did not instantiate a Control root." % scene_path, true)
		return false
	_showcase_viewport.add_child(_current_scene)
	_current_scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_current_index = index
	_page_selector.select(index)
	_page_title.text = str(demo.get("title", demo.get("id", "Showcase")))
	_previous_button.disabled = index == 0
	_next_button.disabled = index == _demos.size() - 1
	if _current_scene.has_signal("diagnostics_changed"):
		_current_scene.connect("diagnostics_changed", _on_page_diagnostics_changed)
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_status()
	page_changed.emit(index, str(demo.get("id", index)), _current_scene)
	return true


func next_page() -> bool:
	return await show_page(mini(_current_index + 1, _demos.size() - 1))


func previous_page() -> bool:
	return await show_page(maxi(_current_index - 1, 0))


func reload_current_page() -> bool:
	if _current_scene == null:
		return false
	if _current_scene.has_method("reload_document"):
		var reloaded := bool(_current_scene.call("reload_document"))
		await get_tree().process_frame
		_refresh_status()
		return reloaded
	return await show_page(_current_index)


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("080b12")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root_column := VBoxContainer.new()
	root_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_column.add_theme_constant_override("separation", 0)
	add_child(root_column)

	var toolbar_panel := PanelContainer.new()
	toolbar_panel.custom_minimum_size.y = 58.0
	var toolbar_style := StyleBoxFlat.new()
	toolbar_style.bg_color = Color("101828")
	toolbar_style.border_color = Color("2c3c5d")
	toolbar_style.border_width_bottom = 1
	toolbar_style.content_margin_left = 18.0
	toolbar_style.content_margin_right = 18.0
	toolbar_style.content_margin_top = 9.0
	toolbar_style.content_margin_bottom = 9.0
	toolbar_panel.add_theme_stylebox_override("panel", toolbar_style)
	root_column.add_child(toolbar_panel)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	toolbar_panel.add_child(toolbar)

	var brand := Label.new()
	brand.text = "GodotCascade"
	brand.add_theme_color_override("font_color", Color("82b7ff"))
	brand.add_theme_font_size_override("font_size", 18)
	toolbar.add_child(brand)

	var separator := VSeparator.new()
	toolbar.add_child(separator)

	_previous_button = Button.new()
	_previous_button.text = "Previous"
	_previous_button.pressed.connect(_on_previous_pressed)
	toolbar.add_child(_previous_button)

	_page_selector = OptionButton.new()
	_page_selector.custom_minimum_size.x = 220.0
	_page_selector.item_selected.connect(_on_page_selected)
	toolbar.add_child(_page_selector)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.pressed.connect(_on_next_pressed)
	toolbar.add_child(_next_button)

	var reload_button := Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_reload_pressed)
	toolbar.add_child(reload_button)

	_page_title = Label.new()
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_title.add_theme_color_override("font_color", Color("dce6fa"))
	toolbar.add_child(_page_title)

	_status = Label.new()
	_status.custom_minimum_size.x = 190.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toolbar.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_column.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(960.0, 660.0)
	scroll.add_child(center)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = false
	center.add_child(_viewport_container)
	_showcase_viewport = SubViewport.new()
	_showcase_viewport.disable_3d = true
	_showcase_viewport.gui_embed_subwindows = true
	_showcase_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_showcase_viewport)


func _load_manifest() -> bool:
	var source := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary or not parsed.get("demos", []) is Array:
		_set_status("Could not parse showcase manifest.", true)
		return false
	_demos = parsed["demos"]
	if _demos.is_empty():
		_set_status("Showcase manifest contains no pages.", true)
		return false
	return true


func _populate_selector() -> void:
	_page_selector.clear()
	for demo in _demos:
		_page_selector.add_item(str(demo.get("title", demo.get("id", "Showcase"))))


func _requested_page_index() -> int:
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--showcase-page="):
			continue
		var requested := argument.trim_prefix("--showcase-page=")
		for index in _demos.size():
			if str(_demos[index].get("id", "")) == requested:
				return index
	return 0


func _refresh_status() -> void:
	if _current_scene == null:
		_set_status("No page loaded", true)
		return
	var page_diagnostics: Array = _current_scene.get("diagnostics") if _has_property(_current_scene, "diagnostics") else []
	var errors := page_diagnostics.filter(func(item): return item.get("severity", "error") == "error").size()
	var warnings := page_diagnostics.size() - errors
	if errors > 0:
		_set_status("%s errors · %s warnings" % [errors, warnings], true)
	else:
		_set_status("Connected · %s warnings" % warnings, false)


func _set_status(message: String, error: bool) -> void:
	if _status == null:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", Color("f97066") if error else Color("75e0a7"))


func _on_page_diagnostics_changed(_diagnostics: Array[Dictionary]) -> void:
	_refresh_status()


func _on_previous_pressed() -> void:
	await previous_page()


func _on_next_pressed() -> void:
	await next_page()


func _on_reload_pressed() -> void:
	await reload_current_page()


func _on_page_selected(index: int) -> void:
	await show_page(index)


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
