@tool
extends Container

## Native row/column layout implementing GodotCascade's first box-model slice.

const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")

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
const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

var _cached_minimum_size := Vector2.ZERO
var _measure_dirty := true
var _arrange_dirty := true

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
@export var pixel_snap := true:
	set(value):
		pixel_snap = value
		_mark_arrange_dirty()

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		var next := value if value != null else CascadeStyle.new()
		if cascade_style == next:
			return
		_disconnect_style()
		cascade_style = next
		_connect_style()
		_on_style_invalidated(CascadeStyle.Invalidation.ALL)

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
	_connect_style()
	_apply_overflow()
	resized.connect(_on_resized)
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	for child in get_children():
		_track_child(child)
	queue_sort()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			if _arrange_dirty:
				_arrange_children()
		NOTIFICATION_DRAW:
			_draw_box()


func _get_minimum_size() -> Vector2:
	if not _measure_dirty:
		return _cached_minimum_size
	var children := _layout_children()
	var content_minimum := FlexLayoutEngine.measure(_layout_items(children), _layout_request())
	_cached_minimum_size = cascade_style.constrain_minimum(content_minimum)
	_measure_dirty = false
	return _cached_minimum_size


func _arrange_children() -> void:
	var children := _layout_children()
	if children.is_empty():
		_arrange_dirty = false
		return
	var rectangles := FlexLayoutEngine.arrange(_layout_items(children), _layout_request())
	for index in children.size():
		fit_child_in_rect(children[index], rectangles[index])
	_arrange_dirty = false


func _layout_items(children: Array[Control]) -> Array[FlexLayoutEngine.LayoutItem]:
	var items: Array[FlexLayoutEngine.LayoutItem] = []
	for child in children:
		items.append(FlexLayoutEngine.LayoutItem.new(
			_child_constrained_size(child),
			_child_margins(child),
			_child_value(child, "flex_grow", 0.0),
			_child_maximum_size(child),
			int(_child_value(child, "align_self", 0.0)) - 1,
			_child_value(child, "flex_shrink", 0.0),
			_child_flex_basis(child),
			_child_shrink_minimum_size(child)
		))
	return items


func _layout_request() -> FlexLayoutEngine.LayoutRequest:
	var request := FlexLayoutEngine.LayoutRequest.new()
	request.size = size
	request.padding = cascade_style.padding()
	request.gap = gap
	request.line_gap = line_gap
	request.direction = direction
	request.wrap = wrap
	request.justify_content = justify_content
	request.align_items = align_items
	request.pixel_snap = pixel_snap
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


func _child_shrink_minimum_size(child: Control) -> Vector2:
	var intrinsic := child.get_combined_minimum_size()
	return Vector2(
		maxf(intrinsic.x, _child_value(child, "min_width", 0.0)),
		maxf(intrinsic.y, _child_value(child, "min_height", 0.0))
	)


func _child_flex_basis(child: Control) -> float:
	if child.has_meta("cascade_flex_basis"):
		return float(child.get_meta("cascade_flex_basis"))
	if _has_property(child, "cascade_style"):
		var child_style: CascadeStyle = child.get("cascade_style")
		if child_style != null:
			return child_style.flex_basis
	return -1.0


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

	if _has_property(child, "cascade_style"):
		var child_style: CascadeStyle = child.get("cascade_style")
		if child_style != null and _has_property(child_style, property_name):
			return maxf(float(child_style.get(property_name)), 0.0)
	if _has_property(child, property_name):
		return maxf(float(child.get(property_name)), 0.0)
	return fallback


func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)


func _layout_children() -> Array[Control]:
	var result: Array[Control] = []
	for node in get_children():
		if node is Control and node.visible and not node.top_level:
			result.append(node)
	return result

func _invalidate_layout() -> void:
	_measure_dirty = true
	_arrange_dirty = true
	if is_inside_tree():
		update_minimum_size()
		queue_sort()
		queue_redraw()
		_notify_parent_layout_changed()


func _mark_arrange_dirty() -> void:
	_arrange_dirty = true
	if is_inside_tree():
		queue_sort()
		_notify_parent_layout_changed()


func _mark_measure_dirty() -> void:
	_measure_dirty = true
	_arrange_dirty = true
	if is_inside_tree():
		update_minimum_size()
		queue_sort()
		_notify_parent_layout_changed()


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _disconnect_style() -> void:
	if cascade_style == null:
		return
	if cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.disconnect(_on_style_invalidated)


func _on_style_invalidated(flags: int) -> void:
	if flags & CascadeStyle.Invalidation.DRAW:
		_apply_overflow()
		if is_inside_tree():
			queue_redraw()
	if flags & CascadeStyle.Invalidation.MEASURE:
		_mark_measure_dirty()
	elif flags & CascadeStyle.Invalidation.ARRANGE:
		_mark_arrange_dirty()


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_resized() -> void:
	_mark_arrange_dirty()
	queue_redraw()


func _on_child_entered(child: Node) -> void:
	_track_child(child)
	_mark_measure_dirty()


func _on_child_exiting(child: Node) -> void:
	_untrack_child(child)
	_mark_measure_dirty()


func _track_child(child: Node) -> void:
	if not child is Control:
		return
	var control := child as Control
	if not control.minimum_size_changed.is_connected(_on_child_minimum_size_changed):
		control.minimum_size_changed.connect(_on_child_minimum_size_changed)
	if not control.visibility_changed.is_connected(_on_child_visibility_changed):
		control.visibility_changed.connect(_on_child_visibility_changed)


func _untrack_child(child: Node) -> void:
	if not child is Control:
		return
	var control := child as Control
	if control.minimum_size_changed.is_connected(_on_child_minimum_size_changed):
		control.minimum_size_changed.disconnect(_on_child_minimum_size_changed)
	if control.visibility_changed.is_connected(_on_child_visibility_changed):
		control.visibility_changed.disconnect(_on_child_visibility_changed)


func _on_child_minimum_size_changed() -> void:
	_mark_measure_dirty()


func _on_child_visibility_changed() -> void:
	_mark_measure_dirty()


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP


func _draw_box() -> void:
	BoxPainter.draw_box(
		self,
		Rect2(Vector2.ZERO, size),
		cascade_background_color(),
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius,
		cascade_style.background_gradient
	)


func cascade_background_color() -> Color:
	return hover_background_color if hover_style_enabled and _mouse_inside else cascade_style.background_color


func _on_mouse_entered() -> void:
	_mouse_inside = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_mouse_inside = false
	queue_redraw()
