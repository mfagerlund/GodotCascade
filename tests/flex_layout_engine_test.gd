extends SceneTree

const LayoutEngine := preload("res://addons/godot_cascade/layout/flex_layout_engine.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_measurement()
	_test_flex_growth()
	_test_justification()
	_test_wrapping()
	_test_margins_and_column_flow()
	_test_growth_redistributes_after_maximum()

	if _failures.is_empty():
		print("GodotCascade flex layout engine tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_measurement() -> void:
	var request := LayoutEngine.LayoutRequest.new()
	request.direction = LayoutEngine.DIRECTION_ROW
	request.padding = Vector4(2.0, 3.0, 4.0, 5.0)
	request.gap = 5.0
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(20.0, 10.0), Vector4(1.0, 2.0, 3.0, 4.0)),
		LayoutEngine.LayoutItem.new(Vector2(10.0, 5.0)),
	]
	_expect_vector("measure row with box model", LayoutEngine.measure(items, request), Vector2(45.0, 24.0))


func _test_flex_growth() -> void:
	var request := _request(Vector2(100.0, 50.0), LayoutEngine.DIRECTION_ROW)
	request.padding = Vector4(10.0, 10.0, 10.0, 10.0)
	request.gap = 5.0
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(20.0, 10.0)),
		LayoutEngine.LayoutItem.new(Vector2(30.0, 10.0), Vector4.ZERO, 1.0),
	]
	var result := LayoutEngine.arrange(items, request)
	_expect_rect("fixed flex sibling", result[0], Rect2(10.0, 10.0, 20.0, 30.0))
	_expect_rect("growing flex sibling", result[1], Rect2(35.0, 10.0, 55.0, 30.0))


func _test_justification() -> void:
	var request := _request(Vector2(100.0, 20.0), LayoutEngine.DIRECTION_ROW)
	request.justify_content = LayoutEngine.JUSTIFY_SPACE_BETWEEN
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(10.0, 10.0)),
		LayoutEngine.LayoutItem.new(Vector2(10.0, 10.0)),
	]
	var result := LayoutEngine.arrange(items, request)
	_expect_rect("space-between first", result[0], Rect2(0.0, 0.0, 10.0, 20.0))
	_expect_rect("space-between second", result[1], Rect2(90.0, 0.0, 10.0, 20.0))


func _test_wrapping() -> void:
	var request := _request(Vector2(100.0, 100.0), LayoutEngine.DIRECTION_ROW)
	request.wrap = true
	request.gap = 10.0
	request.line_gap = 5.0
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(45.0, 10.0)),
		LayoutEngine.LayoutItem.new(Vector2(45.0, 10.0)),
		LayoutEngine.LayoutItem.new(Vector2(45.0, 10.0)),
	]
	var result := LayoutEngine.arrange(items, request)
	_expect_rect("wrap first", result[0], Rect2(0.0, 0.0, 45.0, 10.0))
	_expect_rect("wrap second", result[1], Rect2(55.0, 0.0, 45.0, 10.0))
	_expect_rect("wrap next line", result[2], Rect2(0.0, 15.0, 45.0, 10.0))


func _test_margins_and_column_flow() -> void:
	var request := _request(Vector2(50.0, 100.0), LayoutEngine.DIRECTION_COLUMN)
	request.padding = Vector4(5.0, 5.0, 5.0, 5.0)
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(10.0, 10.0), Vector4(2.0, 3.0, 4.0, 5.0)),
	]
	var result := LayoutEngine.arrange(items, request)
	_expect_rect("column margins", result[0], Rect2(7.0, 8.0, 34.0, 10.0))


func _test_growth_redistributes_after_maximum() -> void:
	var request := _request(Vector2(100.0, 20.0), LayoutEngine.DIRECTION_ROW)
	var items: Array[LayoutEngine.LayoutItem] = [
		LayoutEngine.LayoutItem.new(Vector2(20.0, 10.0), Vector4.ZERO, 1.0, Vector2(30.0, INF)),
		LayoutEngine.LayoutItem.new(Vector2(20.0, 10.0), Vector4.ZERO, 1.0),
	]
	var result := LayoutEngine.arrange(items, request)
	_expect_rect("max-limited grow item", result[0], Rect2(0.0, 0.0, 30.0, 20.0))
	_expect_rect("redistributed grow item", result[1], Rect2(30.0, 0.0, 70.0, 20.0))


func _request(request_size: Vector2, request_direction: int) -> LayoutEngine.LayoutRequest:
	var request := LayoutEngine.LayoutRequest.new()
	request.size = request_size
	request.direction = request_direction
	return request


func _expect_rect(label: String, actual: Rect2, expected: Rect2) -> void:
	if not actual.position.is_equal_approx(expected.position) or not actual.size.is_equal_approx(expected.size):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_vector(label: String, actual: Vector2, expected: Vector2) -> void:
	if not actual.is_equal_approx(expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
