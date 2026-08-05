extends SceneTree

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_box_geometry()
	await _test_button_measurement()
	await _test_button_in_flex_layout()

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
	button.padding_left = 10.0
	button.padding_right = 10.0
	button.padding_top = 5.0
	button.padding_bottom = 5.0
	button.border_width = 2.0
	root.add_child(button)
	await process_frame

	_expect_true("CascadeButton keeps BaseButton behavior", button is BaseButton)
	var initial_minimum := button.get_combined_minimum_size()
	button.padding_left += 7.0
	await process_frame
	var expanded_minimum := button.get_combined_minimum_size()
	_expect_float("button padding affects intrinsic width", expanded_minimum.x - initial_minimum.x, 7.0)
	button.queue_free()


func _test_button_in_flex_layout() -> void:
	var box := CascadeBox.new()
	box.direction = CascadeBox.FlowDirection.ROW
	box.padding_left = 10.0
	box.padding_top = 10.0
	box.padding_right = 10.0
	box.padding_bottom = 10.0
	box.gap = 5.0
	box.size = Vector2(200.0, 60.0)
	root.add_child(box)

	var button := CascadeButton.new()
	button.text = ""
	button.preferred_width = 50.0
	button.preferred_height = 30.0
	button.flex_grow = 1.0
	box.add_child(button)

	var fixed := Control.new()
	fixed.custom_minimum_size = Vector2(20.0, 10.0)
	box.add_child(fixed)
	await process_frame
	await process_frame

	_expect_rect("owned button flex rectangle", Rect2(button.position, button.size), Rect2(10.0, 10.0, 155.0, 40.0))
	_expect_rect("owned button sibling rectangle", Rect2(fixed.position, fixed.size), Rect2(170.0, 10.0, 20.0, 40.0))
	box.queue_free()


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
