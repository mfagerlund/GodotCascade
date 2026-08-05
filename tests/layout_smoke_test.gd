extends SceneTree

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const EPSILON := 0.01

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var box := CascadeBox.new()
	box.direction = CascadeBox.FlowDirection.ROW
	box.cascade_style.padding_left = 10.0
	box.cascade_style.padding_top = 10.0
	box.cascade_style.padding_right = 10.0
	box.cascade_style.padding_bottom = 10.0
	box.gap = 5.0
	box.size = Vector2(100.0, 50.0)
	root.add_child(box)

	var fixed := Control.new()
	fixed.custom_minimum_size = Vector2(20.0, 10.0)
	box.add_child(fixed)

	var growing := Control.new()
	growing.custom_minimum_size = Vector2(30.0, 10.0)
	growing.set_meta("cascade_flex_grow", 1.0)
	box.add_child(growing)

	await process_frame
	await process_frame

	_expect_vector("fixed position", fixed.position, Vector2(10.0, 10.0))
	_expect_vector("fixed size", fixed.size, Vector2(20.0, 30.0))
	_expect_vector("growing position", growing.position, Vector2(35.0, 10.0))
	_expect_vector("growing size", growing.size, Vector2(55.0, 30.0))

	if _failures.is_empty():
		print("GodotCascade layout smoke test passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect_vector(label: String, actual: Vector2, expected: Vector2) -> void:
	if not actual.is_equal_approx(expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
