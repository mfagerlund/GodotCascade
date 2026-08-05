extends SceneTree

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
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
	await _test_panel_layout()
	await _test_owned_progress()

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
	progress.queue_free()


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
