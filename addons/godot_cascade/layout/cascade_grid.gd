@tool
extends Container

## Native adapter for the engine-only grid layout model.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const GridLayoutEngine := preload("res://addons/godot_cascade/layout/grid_layout_engine.gd")

@export var column_tracks: Array[Dictionary] = [{"kind": "fraction", "value": 1.0}]:
	set(value):
		column_tracks = value
		queue_sort()
		update_minimum_size()
@export var row_tracks: Array[Dictionary] = []:
	set(value):
		row_tracks = value
		queue_sort()
		update_minimum_size()
@export var column_gap := 0.0:
	set(value):
		column_gap = maxf(value, 0.0)
		queue_sort()
@export var row_gap := 0.0:
	set(value):
		row_gap = maxf(value, 0.0)
		queue_sort()
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		cascade_style = value if value != null else CascadeStyle.new()
		queue_sort()
		queue_redraw()
		update_minimum_size()
@export_group("State Appearance")
@export var hover_background_color := Color.TRANSPARENT:
	set(value):
		hover_background_color = value
		queue_redraw()
@export var hover_style_enabled := false:
	set(value):
		hover_style_enabled = value
		queue_redraw()

var _mouse_inside := false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_arrange_children()


func _get_minimum_size() -> Vector2:
	var children := _layout_children()
	var items := _items(children)
	var result := GridLayoutEngine.arrange(Vector2.ZERO, column_tracks, row_tracks, items, column_gap, row_gap)
	var content := Vector2(_sum(result["column_sizes"]), _sum(result["row_sizes"]))
	content.x += column_gap * maxf(result["column_sizes"].size() - 1, 0)
	content.y += row_gap * maxf(result["row_sizes"].size() - 1, 0)
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(content, cascade_style.padding(), cascade_style.border_width))


func _draw() -> void:
	BoxPainter.draw_box(self, Rect2(Vector2.ZERO, size), cascade_background_color(), cascade_style.border_color, cascade_style.border_width, cascade_style.border_radius)


func cascade_background_color() -> Color:
	return hover_background_color if hover_style_enabled and _mouse_inside else cascade_style.background_color


func _on_mouse_entered() -> void:
	_mouse_inside = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_mouse_inside = false
	queue_redraw()


func _arrange_children() -> void:
	var children := _layout_children()
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	var result := GridLayoutEngine.arrange(content.size, column_tracks, row_tracks, _items(children), column_gap, row_gap)
	var rects: Array = result["rects"]
	for index in children.size():
		var rect: Rect2 = rects[index]
		rect.position += content.position
		fit_child_in_rect(children[index], rect)


func _items(children: Array[Control]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child in children:
		result.append({
			"minimum": child.get_combined_minimum_size(),
			"column": int(child.get_meta("cascade_grid_column", -1)),
			"row": int(child.get_meta("cascade_grid_row", -1)),
			"column_span": int(child.get_meta("cascade_grid_column_span", 1)),
			"row_span": int(child.get_meta("cascade_grid_row_span", 1)),
		})
	return result


func _layout_children() -> Array[Control]:
	var result: Array[Control] = []
	for child in get_children():
		if child is Control and child.visible and not child.top_level:
			result.append(child)
	return result


func _sum(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result
