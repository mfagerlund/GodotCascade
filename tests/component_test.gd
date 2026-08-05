extends SceneTree

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CascadeCheckbox := preload("res://addons/godot_cascade/components/cascade_checkbox.gd")
const CascadeRadioButton := preload("res://addons/godot_cascade/components/cascade_radio_button.gd")
const CascadeSwitch := preload("res://addons/godot_cascade/components/cascade_switch.gd")
const CascadeSelect := preload("res://addons/godot_cascade/components/cascade_select.gd")
const CascadeSlider := preload("res://addons/godot_cascade/components/cascade_slider.gd")
const InteractiveStateAdapter := preload("res://addons/godot_cascade/components/interactive_state_adapter.gd")
const CascadeLabel := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CascadeProgress := preload("res://addons/godot_cascade/components/cascade_progress.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_box_geometry()
	await _test_button_measurement()
	await _test_button_in_flex_layout()
	await _test_shared_style_invalidation()
	await _test_overflow_and_align_self()
	await _test_owned_label_box()
	await _test_wrapped_label_row_minimum()
	await _test_panel_layout()
	await _test_owned_progress()
	_test_interactive_state_precedence()
	await _test_owned_checkbox()
	await _test_native_radio_group()
	await _test_owned_switch()
	await _test_owned_select()
	await _test_owned_slider()
	await _test_native_input_matrix()

	if _failures.is_empty():
		print("GodotCascade component tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_box_geometry() -> void:
	_expect_vector(
		"outer box minimum",
		BoxPainter.outer_minimum_size(Vector2(20.0, 10.0), Vector4(10.0, 5.0, 20.0, 7.0), 2.0),
		Vector2(54.0, 26.0)
	)
	_expect_rect(
		"content rectangle",
		BoxPainter.content_rect(Rect2(0.0, 0.0, 100.0, 50.0), Vector4(10.0, 5.0, 20.0, 7.0), 2.0),
		Rect2(12.0, 7.0, 66.0, 34.0)
	)


func _test_button_measurement() -> void:
	var button := CascadeButton.new()
	button.text = "Cascade"
	button.cascade_style.padding_left = 10.0
	button.cascade_style.padding_right = 10.0
	button.cascade_style.padding_top = 5.0
	button.cascade_style.padding_bottom = 5.0
	button.cascade_style.border_width = 2.0
	root.add_child(button)
	await process_frame

	_expect_true("CascadeButton keeps BaseButton behavior", button is BaseButton)
	var initial_minimum := button.get_combined_minimum_size()
	button.cascade_style.padding_left += 7.0
	await process_frame
	var expanded_minimum := button.get_combined_minimum_size()
	_expect_float("button padding affects intrinsic width", expanded_minimum.x - initial_minimum.x, 7.0)
	button.queue_free()


func _test_button_in_flex_layout() -> void:
	var box := CascadeBox.new()
	box.direction = CascadeBox.FlowDirection.ROW
	box.cascade_style.padding_left = 10.0
	box.cascade_style.padding_top = 10.0
	box.cascade_style.padding_right = 10.0
	box.cascade_style.padding_bottom = 10.0
	box.gap = 5.0
	box.size = Vector2(200.0, 60.0)
	root.add_child(box)

	var button := CascadeButton.new()
	button.text = ""
	button.cascade_style.preferred_width = 50.0
	button.cascade_style.preferred_height = 30.0
	button.cascade_style.flex_grow = 1.0
	box.add_child(button)

	var fixed := Control.new()
	fixed.custom_minimum_size = Vector2(20.0, 10.0)
	box.add_child(fixed)
	await process_frame
	await process_frame

	_expect_rect("owned button flex rectangle", Rect2(button.position, button.size), Rect2(10.0, 10.0, 155.0, 40.0))
	_expect_rect("owned button sibling rectangle", Rect2(fixed.position, fixed.size), Rect2(170.0, 10.0, 20.0, 40.0))
	box.queue_free()


func _test_shared_style_invalidation() -> void:
	var shared_style := CascadeStyle.new()
	shared_style.padding_left = 5.0
	shared_style.padding_right = 5.0
	var first := CascadeButton.new()
	var second := CascadeButton.new()
	first.text = ""
	second.text = ""
	first.cascade_style = shared_style
	second.cascade_style = shared_style
	root.add_child(first)
	root.add_child(second)
	await process_frame
	var first_width := first.get_combined_minimum_size().x
	var second_width := second.get_combined_minimum_size().x

	shared_style.padding_left += 11.0
	await process_frame
	_expect_float("shared style invalidates first consumer", first.get_combined_minimum_size().x - first_width, 11.0)
	_expect_float("shared style invalidates second consumer", second.get_combined_minimum_size().x - second_width, 11.0)
	first.queue_free()
	second.queue_free()


func _test_overflow_and_align_self() -> void:
	var box := CascadeBox.new()
	box.size = Vector2(100.0, 40.0)
	root.add_child(box)
	box.cascade_style.overflow = CascadeStyle.Overflow.CLIP
	await process_frame
	_expect_true("overflow clip reaches native Control", box.clip_contents)

	var button := CascadeButton.new()
	button.text = ""
	button.cascade_style.preferred_width = 20.0
	button.cascade_style.preferred_height = 10.0
	button.cascade_style.align_self = CascadeStyle.SelfAlignment.CENTER
	box.direction = CascadeBox.FlowDirection.ROW
	box.add_child(button)
	await process_frame
	await process_frame
	_expect_rect("CascadeStyle align-self bridge", Rect2(button.position, button.size), Rect2(0.0, 10.0, 30.0, 20.0))
	box.queue_free()


func _test_owned_label_box() -> void:
	var label := CascadeLabel.new()
	label.text = "Cascade"
	label.cascade_style.padding_left = 4.0
	label.cascade_style.padding_top = 3.0
	label.cascade_style.padding_right = 6.0
	label.cascade_style.padding_bottom = 5.0
	label.cascade_style.border_width = 2.0
	label.size = Vector2(120.0, 40.0)
	root.add_child(label)
	await process_frame

	var initial_width := label.get_combined_minimum_size().x
	label.cascade_style.padding_left += 9.0
	await process_frame
	_expect_float("CascadeLabel shares box measurement", label.get_combined_minimum_size().x - initial_width, 9.0)
	var internal_label := label.get_node("_Text") as Label
	_expect_rect("CascadeLabel native text content box", Rect2(internal_label.position, internal_label.size), Rect2(15.0, 5.0, 97.0, 28.0))
	label.queue_free()


func _test_wrapped_label_row_minimum() -> void:
	var box := CascadeBox.new()
	box.direction = CascadeBox.FlowDirection.ROW
	box.size = Vector2(400.0, 100.0)
	root.add_child(box)
	var label := CascadeLabel.new()
	label.text = "A visible wrapped label"
	box.add_child(label)
	await process_frame
	await process_frame
	_expect_true("wrapped label keeps non-zero row width", label.size.x > 0.0)
	_expect_true("wrapped label fits row cross axis", label.size.y <= box.size.y)
	box.queue_free()


func _test_panel_layout() -> void:
	var panel := CascadePanel.new()
	panel.size = Vector2(100.0, 50.0)
	panel.cascade_style.padding_left = 10.0
	panel.cascade_style.padding_top = 5.0
	panel.cascade_style.padding_right = 10.0
	panel.cascade_style.padding_bottom = 5.0
	root.add_child(panel)
	var child := Control.new()
	child.custom_minimum_size = Vector2(20.0, 10.0)
	panel.add_child(child)
	await process_frame
	await process_frame
	_expect_true("CascadePanel remains a native Container", panel is Container)
	_expect_rect("CascadePanel shares CascadeBox layout", Rect2(child.position, child.size), Rect2(10.0, 5.0, 80.0, 10.0))
	panel.queue_free()


func _test_owned_progress() -> void:
	var progress := CascadeProgress.new()
	progress.min_value = 20.0
	progress.max_value = 120.0
	progress.value = 70.0
	progress.cascade_style.padding_left = 2.0
	progress.cascade_style.padding_right = 2.0
	root.add_child(progress)
	await process_frame
	_expect_float("CascadeProgress normalized ratio", progress.ratio(), 0.5)
	_expect_float("CascadeProgress honors preferred height", progress.get_combined_minimum_size().y, 14.0)
	progress.value = 200.0
	_expect_float("CascadeProgress clamps value", progress.value, 120.0)
	progress.set_range_values(50.0, 200.0, 175.0)
	_expect_float("CascadeProgress atomic minimum", progress.min_value, 50.0)
	_expect_float("CascadeProgress atomic maximum", progress.max_value, 200.0)
	_expect_float("CascadeProgress atomic value", progress.value, 175.0)
	progress.queue_free()


func _test_interactive_state_precedence() -> void:
	_expect_true("base interactive state", InteractiveStateAdapter.resolve(false, false, false, false, false).is_empty())
	_expect_true("focus interactive state", InteractiveStateAdapter.resolve(false, false, false, false, true) == "focused")
	_expect_true("hover wins over focus", InteractiveStateAdapter.resolve(false, false, false, true, true) == "hover")
	_expect_true("checked wins over hover", InteractiveStateAdapter.resolve(false, false, true, true, true) == "checked")
	_expect_true("pressed wins over checked", InteractiveStateAdapter.resolve(false, true, true, true, true) == "pressed")
	_expect_true("disabled wins over pressed", InteractiveStateAdapter.resolve(true, true, true, true, true) == "disabled")


func _test_owned_checkbox() -> void:
	var checkbox := CascadeCheckbox.new()
	checkbox.text = "Enable shadows"
	root.add_child(checkbox)
	await process_frame
	_expect_true("CascadeCheckbox keeps BaseButton behavior", checkbox is BaseButton)
	_expect_true("CascadeCheckbox enables toggle mode", checkbox.toggle_mode)
	_expect_true("CascadeCheckbox includes indicator in minimum size", checkbox.get_combined_minimum_size().x > checkbox.indicator_size)
	checkbox.button_pressed = true
	await process_frame
	_expect_true("CascadeCheckbox reports checked native state", checkbox.cascade_visual_state() == "checked")
	checkbox.disabled = true
	await process_frame
	_expect_true("CascadeCheckbox disabled state has precedence", checkbox.cascade_visual_state() == "disabled")
	checkbox.queue_free()


func _test_native_radio_group() -> void:
	var group := ButtonGroup.new()
	var first := CascadeRadioButton.new()
	var second := CascadeRadioButton.new()
	first.button_group = group
	second.button_group = group
	root.add_child(first)
	root.add_child(second)
	await process_frame
	first.button_pressed = true
	second.button_pressed = true
	_expect_true("native radio group selects latest button", second.button_pressed)
	_expect_true("native radio group unchecks previous button", not first.button_pressed)
	first.queue_free()
	second.queue_free()


func _test_owned_switch() -> void:
	var toggle := CascadeSwitch.new()
	toggle.text = "Vertical sync"
	root.add_child(toggle)
	await process_frame
	_expect_true("CascadeSwitch keeps checkbox semantics", toggle.toggle_mode)
	_expect_true("CascadeSwitch uses wide track geometry", toggle.track_width > toggle.track_height)
	_expect_true("CascadeSwitch minimum includes track", toggle.get_combined_minimum_size().x > toggle.track_width)
	toggle.button_pressed = true
	await process_frame
	_expect_true("CascadeSwitch reports checked state", toggle.cascade_visual_state() == "checked")
	toggle.queue_free()


func _test_owned_select() -> void:
	var select := CascadeSelect.new()
	select.options = [
		{"label": "Low", "value": "low"},
		{"label": "Medium", "value": "medium"},
		{"label": "Unavailable", "value": "disabled", "disabled": true},
		{"label": "High", "value": "high"},
	]
	select.selected_index = 0
	select.size = Vector2(180.0, 42.0)
	root.add_child(select)
	await process_frame
	_expect_true("CascadeSelect displays selected label", select.text == "Low")
	_expect_true("CascadeSelect exposes selected value", select.selected_value() == "low")
	select.open_popup()
	await process_frame
	_expect_true("CascadeSelect opens native popup", select.is_open())
	_expect_true("open select reports open state", select.cascade_visual_state() == "open")
	_send_action("ui_down", true)
	_send_action("ui_down", false)
	_send_action("ui_accept", true)
	_send_action("ui_accept", false)
	await process_frame
	_expect_true("select keyboard navigation chooses next option", select.selected_value() == "medium")
	_expect_true("select closes after keyboard selection", not select.is_open())
	select.open_popup()
	_send_action("ui_down", true)
	_send_action("ui_down", false)
	_send_action("ui_accept", true)
	_send_action("ui_accept", false)
	await process_frame
	_expect_true("select navigation skips disabled option", select.selected_value() == "high")
	select.queue_free()


func _test_owned_slider() -> void:
	var slider := CascadeSlider.new()
	slider.set_range_values(0.0, 100.0, 25.0)
	slider.step = 5.0
	slider.size = Vector2(200.0, 30.0)
	root.add_child(slider)
	await process_frame
	_expect_float("CascadeSlider native ratio", slider.ratio, 0.25)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100.0, 15.0)
	slider.call("_gui_input", click)
	_expect_float("CascadeSlider pointer updates value", slider.value, 50.0)
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	slider.call("_gui_input", right)
	_expect_float("CascadeSlider keyboard increments by step", slider.value, 55.0)
	slider.disabled = true
	slider.call("_gui_input", right)
	_expect_float("disabled CascadeSlider ignores input", slider.value, 55.0)
	slider.queue_free()


func _test_native_input_matrix() -> void:
	root.size = Vector2i(480, 240)
	var checkbox := CascadeCheckbox.new()
	checkbox.position = Vector2(40.0, 40.0)
	checkbox.size = Vector2(180.0, 44.0)
	root.add_child(checkbox)
	await process_frame

	checkbox.grab_focus()
	await process_frame
	_expect_true("checkbox accepts native focus", checkbox.has_focus())
	_expect_true("focused checkbox reports focus state", checkbox.cascade_visual_state() == "focused")

	_send_action("ui_accept", true)
	await process_frame
	_expect_true("keyboard press reports pressed state", checkbox.cascade_visual_state() == "pressed")
	_send_action("ui_accept", false)
	await process_frame
	_expect_true("keyboard release toggles checkbox", checkbox.button_pressed)

	checkbox.button_pressed = false
	var joypad_mapping := InputEventJoypadButton.new()
	joypad_mapping.button_index = JOY_BUTTON_A
	InputMap.action_add_event("ui_accept", joypad_mapping)
	_send_joypad_accept(true)
	await process_frame
	_expect_true("controller press reports pressed state", checkbox.cascade_visual_state() == "pressed")
	_send_joypad_accept(false)
	await process_frame
	_expect_true("controller release toggles checkbox", checkbox.button_pressed)

	checkbox.button_pressed = false
	checkbox.release_focus()
	_send_mouse_motion(Vector2(80.0, 60.0))
	await process_frame
	_expect_true("pointer motion enters checkbox", checkbox.is_hovered())
	_expect_true("hovered checkbox reports hover state", checkbox.cascade_visual_state() == "hover")
	_send_mouse_button(Vector2(80.0, 60.0), true)
	await process_frame
	_expect_true("pointer down reports pressed state", checkbox.cascade_visual_state() == "pressed")
	_send_mouse_button(Vector2(80.0, 60.0), false)
	await process_frame
	_expect_true("pointer release toggles checkbox", checkbox.button_pressed)

	checkbox.disabled = true
	_send_action("ui_accept", true)
	_send_action("ui_accept", false)
	await process_frame
	_expect_true("disabled checkbox keeps disabled state", checkbox.cascade_visual_state() == "disabled")
	_expect_true("disabled checkbox ignores activation", checkbox.button_pressed)
	InputMap.action_erase_event("ui_accept", joypad_mapping)
	checkbox.queue_free()


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	root.push_input(event, true)


func _send_joypad_accept(pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = pressed
	event.pressure = 1.0 if pressed else 0.0
	root.push_input(event, true)


func _send_mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _send_mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _expect_true(label: String, actual: bool) -> void:
	if not actual:
		_failures.append("%s: expected true" % label)


func _expect_float(label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_rect(label: String, actual: Rect2, expected: Rect2) -> void:
	if not actual.position.is_equal_approx(expected.position) or not actual.size.is_equal_approx(expected.size):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_vector(label: String, actual: Vector2, expected: Vector2) -> void:
	if not actual.is_equal_approx(expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
