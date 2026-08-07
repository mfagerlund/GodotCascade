extends SceneTree

const ArrayItemModel := preload("res://addons/godot_cascade/runtime/array_item_model.gd")
const CollectionChange := preload("res://addons/godot_cascade/runtime/collection_change.gd")
const VirtualWindow := preload("res://addons/godot_cascade/runtime/virtual_window.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_array_item_model()
	_test_empty_virtual_window()
	_test_large_virtual_window()
	if _failures.is_empty():
		print("GodotCascade item model tests passed.")
		quit(0)
	else:
		for failure in _failures: push_error(failure)
		quit(1)


func _test_array_item_model() -> void:
	var model := ArrayItemModel.new(
		[{"id": "a", "value": 1}, {"id": "b", "value": 2}, {"id": "c", "value": 3}],
		func(item: Dictionary): return item["id"]
	)
	var changes: Array = []
	model.changed.connect(func(change: CollectionChange): changes.append(change))
	_expect("initial count", model.item_count() == 3)
	_expect("typed key selector", model.key_at(1) == "b")
	_expect("out-of-range item is null", model.item_at(99) == null)

	_expect("insert succeeds", model.insert(1, {"id": "x", "value": 9}))
	_expect_change("insert change", changes[-1], CollectionChange.Kind.INSERT, 1, 1, -1)
	_expect("insert mutates items", model.key_at(1) == "x")

	_expect("bulk insert succeeds", model.insert_many(2, [{"id": "y"}, {"id": "z"}]))
	_expect_change("bulk insert change", changes[-1], CollectionChange.Kind.INSERT, 2, 2, -1)
	_expect("remove range succeeds", model.remove_range(2, 2))
	_expect_change("remove change", changes[-1], CollectionChange.Kind.REMOVE, 2, 2, -1)

	_expect("move succeeds", model.move_items(0, 2))
	_expect_change("move change", changes[-1], CollectionChange.Kind.MOVE, 0, 1, 2)
	_expect("move uses resulting index", model.key_at(2) == "a")

	_expect("update succeeds", model.update(1, {"id": "updated", "value": 7}))
	_expect_change("update change", changes[-1], CollectionChange.Kind.UPDATE, 1, 1, -1)
	_expect("updated item available", model.item_at(1)["value"] == 7)

	var notification_count := changes.size()
	_expect("invalid removal rejected", not model.remove_range(99, 1))
	_expect("invalid mutation is silent", changes.size() == notification_count)
	model.reset([{"id": "r"}])
	_expect_change("reset change", changes[-1], CollectionChange.Kind.RESET, 0, 1, -1)
	_expect("reset replaces contents", model.item_count() == 1 and model.key_at(0) == "r")


func _test_empty_virtual_window() -> void:
	var window := VirtualWindow.new(0, 44.0, 400.0, 3)
	_expect("empty range", window.first_index == 0 and window.end_index == 0)
	_expect("empty realized count", window.realized_count() == 0)
	_expect("empty content extent", is_equal_approx(window.content_extent, 0.0))
	window.set_scroll_offset(900.0)
	_expect("empty offset clamps", is_equal_approx(window.scroll_offset, 0.0))
	_expect("invalid item extent rejected", not window.configure(10, 0.0, 100.0, 1))


func _test_large_virtual_window() -> void:
	var window := VirtualWindow.new(10_000, 20.0, 100.0, 2)
	var ranges: Array[Vector2i] = []
	window.range_changed.connect(func(first: int, last: int): ranges.append(Vector2i(first, last)))
	_expect("top range includes trailing overscan", window.first_index == 0 and window.end_index == 7)
	_expect("large content extent", is_equal_approx(window.content_extent, 200_000.0))
	_expect("top spacer is zero", is_equal_approx(window.top_spacer_extent, 0.0))
	window.set_scroll_offset(10_000.0)
	_expect("middle range bounded", window.first_index == 498 and window.end_index == 507)
	_expect("middle realized count bounded", window.realized_count() == 9)
	_expect("scroll event emits range", ranges == [Vector2i(498, 507)])
	window.set_scroll_offset(10_001.0)
	_expect("partial next row expands range", ranges[-1] == Vector2i(498, 508))
	_expect("partial-row range remains bounded", window.realized_count() <= 10)
	var range_count := ranges.size()
	window.set_scroll_offset(10_002.0)
	_expect("same range does not emit", ranges.size() == range_count)
	window.set_scroll_offset(INF)
	_expect("bottom offset clamps", is_equal_approx(window.scroll_offset, 199_900.0))
	_expect("bottom range bounded", window.first_index == 9993 and window.end_index == 10_000)
	_expect("spacers preserve total extent", is_equal_approx(
		window.top_spacer_extent + float(window.realized_count()) * window.item_extent + window.bottom_spacer_extent,
		window.content_extent
	))
	_expect("10k model never realizes whole list", window.realized_count() <= 9)


func _expect_change(label: String, change: CollectionChange, kind: CollectionChange.Kind, index: int, count: int, to_index: int) -> void:
	_expect(label, change.kind == kind and change.index == index and change.count == count and change.to_index == to_index)


func _expect(label: String, condition: bool) -> void:
	if not condition: _failures.append(label)
