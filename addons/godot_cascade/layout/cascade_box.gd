@tool
extends Container

## Native row/column layout implementing GodotCascade's first box-model slice.

enum FlowDirection {
	ROW,
	COLUMN,
}

enum MainAlignment {
	START,
	CENTER,
	END,
	SPACE_BETWEEN,
	SPACE_AROUND,
	SPACE_EVENLY,
}

enum CrossAlignment {
	START,
	CENTER,
	END,
	STRETCH,
}

const META_PREFIX := "cascade_"
const FlexLayoutEngine := preload("res://addons/godot_cascade/layout/flex_layout_engine.gd")

@export_group("Layout")
@export var direction: FlowDirection = FlowDirection.COLUMN:
	set(value):
		direction = value
		_invalidate_layout()
@export var wrap: bool = false:
	set(value):
		wrap = value
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var gap: float = 0.0:
	set(value):
		gap = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var line_gap: float = 0.0:
	set(value):
		line_gap = maxf(value, 0.0)
		_invalidate_layout()
@export var justify_content: MainAlignment = MainAlignment.START:
	set(value):
		justify_content = value
		_invalidate_layout()
@export var align_items: CrossAlignment = CrossAlignment.STRETCH:
	set(value):
		align_items = value
		_invalidate_layout()

@export_group("Padding")
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_left: float = 0.0:
	set(value):
		padding_left = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_top: float = 0.0:
	set(value):
		padding_top = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_right: float = 0.0:
	set(value):
		padding_right = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_bottom: float = 0.0:
	set(value):
		padding_bottom = maxf(value, 0.0)
		_invalidate_layout()

@export_group("Margin")
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_left: float = 0.0:
	set(value):
		margin_left = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_top: float = 0.0:
	set(value):
		margin_top = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_right: float = 0.0:
	set(value):
		margin_right = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_bottom: float = 0.0:
	set(value):
		margin_bottom = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Size")
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_width: float = 0.0:
	set(value):
		preferred_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_height: float = 0.0:
	set(value):
		preferred_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_width: float = 0.0:
	set(value):
		min_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_height: float = 0.0:
	set(value):
		min_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_width: float = 0.0:
	set(value):
		max_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_height: float = 0.0:
	set(value):
		max_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 100.0, 0.05, "or_greater") var flex_grow: float = 0.0:
	set(value):
		flex_grow = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Appearance")
@export var background_color: Color = Color.TRANSPARENT:
	set(value):
		background_color = value
		queue_redraw()
@export var border_color: Color = Color.TRANSPARENT:
	set(value):
		border_color = value
		queue_redraw()
@export_range(0.0, 128.0, 1.0, "or_greater") var border_width: float = 0.0:
	set(value):
		border_width = maxf(value, 0.0)
		queue_redraw()
@export_range(0.0, 512.0, 1.0, "or_greater") var border_radius: float = 0.0:
	set(value):
		border_radius = maxf(value, 0.0)
		queue_redraw()


func _ready() -> void:
	resized.connect(_on_resized)
	queue_sort()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_arrange_children()
		NOTIFICATION_DRAW:
			_draw_box()


func _get_minimum_size() -> Vector2:
	var children := _layout_children()
	var content_minimum := FlexLayoutEngine.measure(_layout_items(children), _layout_request())
	content_minimum.x = maxf(maxf(content_minimum.x, min_width), preferred_width)
	content_minimum.y = maxf(maxf(content_minimum.y, min_height), preferred_height)
	return content_minimum


func _arrange_children() -> void:
	var children := _layout_children()
	if children.is_empty():
		return
	var rectangles := FlexLayoutEngine.arrange(_layout_items(children), _layout_request())
	for index in children.size():
		fit_child_in_rect(children[index], rectangles[index])


func _layout_items(children: Array[Control]) -> Array[FlexLayoutEngine.LayoutItem]:
	var items: Array[FlexLayoutEngine.LayoutItem] = []
	for child in children:
		items.append(FlexLayoutEngine.LayoutItem.new(
			_child_constrained_size(child),
			_child_margins(child),
			_child_value(child, "flex_grow", 0.0),
			_child_maximum_size(child)
		))
	return items


func _layout_request() -> FlexLayoutEngine.LayoutRequest:
	var request := FlexLayoutEngine.LayoutRequest.new()
	request.size = size
	request.padding = Vector4(padding_left, padding_top, padding_right, padding_bottom)
	request.gap = gap
	request.line_gap = line_gap
	request.direction = direction
	request.wrap = wrap
	request.justify_content = justify_content
	request.align_items = align_items
	return request


func _child_constrained_size(child: Control) -> Vector2:
	var intrinsic := child.get_combined_minimum_size()
	var result := intrinsic
	result.x = maxf(maxf(result.x, _child_value(child, "preferred_width", 0.0)), _child_value(child, "min_width", 0.0))
	result.y = maxf(maxf(result.y, _child_value(child, "preferred_height", 0.0)), _child_value(child, "min_height", 0.0))
	var child_max_width := _child_value(child, "max_width", 0.0)
	var child_max_height := _child_value(child, "max_height", 0.0)
	if child_max_width > 0.0:
		result.x = maxf(minf(result.x, child_max_width), intrinsic.x)
	if child_max_height > 0.0:
		result.y = maxf(minf(result.y, child_max_height), intrinsic.y)
	return result


func _child_maximum_size(child: Control) -> Vector2:
	var child_max_width := _child_value(child, "max_width", 0.0)
	var child_max_height := _child_value(child, "max_height", 0.0)
	return Vector2(
		child_max_width if child_max_width > 0.0 else INF,
		child_max_height if child_max_height > 0.0 else INF
	)


func _child_margins(child: Control) -> Vector4:
	return Vector4(
		_child_value(child, "margin_left", 0.0),
		_child_value(child, "margin_top", 0.0),
		_child_value(child, "margin_right", 0.0),
		_child_value(child, "margin_bottom", 0.0)
	)


func _child_value(child: Control, property_name: String, fallback: float) -> float:
	var metadata_name := StringName(META_PREFIX + property_name)
	if child.has_meta(metadata_name):
		return maxf(float(child.get_meta(metadata_name)), 0.0)

	for property in child.get_property_list():
		if property.name == property_name:
			return maxf(float(child.get(property_name)), 0.0)
	return fallback


func _layout_children() -> Array[Control]:
	var result: Array[Control] = []
	for node in get_children():
		if node is Control and node.visible and not node.top_level:
			result.append(node)
	return result

func _invalidate_layout() -> void:
	if not is_inside_tree():
		return
	update_minimum_size()
	queue_sort()
	queue_redraw()
	_notify_parent_layout_changed()


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_resized() -> void:
	queue_sort()
	queue_redraw()


func _draw_box() -> void:
	if background_color.a <= 0.0 and (border_color.a <= 0.0 or border_width <= 0.0):
		return

	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(roundi(border_width))
	style.set_corner_radius_all(roundi(border_radius))
	draw_style_box(style, Rect2(Vector2.ZERO, size))
