@tool
extends Container

## Overlay container. Normal children fill the content box; absolute children use inset metadata.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(next):
		cascade_style = next if next != null else CascadeStyle.new()
		queue_sort()
		queue_redraw()
		update_minimum_size()
@export_group("State Appearance")
@export var hover_background_color := Color.TRANSPARENT:
	set(next):
		hover_background_color = next
		queue_redraw()
@export var hover_style_enabled := false:
	set(next):
		hover_style_enabled = next
		queue_redraw()

var _mouse_inside := false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_arrange_children()


func _get_minimum_size() -> Vector2:
	var content_minimum := Vector2.ZERO
	for child in get_children():
		if child is Control and child.visible and str(child.get_meta("cascade_position", "relative")) != "absolute":
			content_minimum = content_minimum.max(child.get_combined_minimum_size())
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(
		content_minimum,
		cascade_style.padding(),
		cascade_style.border_width
	))


func _draw() -> void:
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


func _arrange_children() -> void:
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	for child in get_children():
		if not child is Control or not child.visible:
			continue
		if str(child.get_meta("cascade_position", "relative")) == "absolute":
			fit_child_in_rect(child, _absolute_rect(child, content))
		else:
			fit_child_in_rect(child, content)


func _absolute_rect(child: Control, content: Rect2) -> Rect2:
	var left := float(child.get_meta("cascade_left", NAN))
	var top := float(child.get_meta("cascade_top", NAN))
	var right := float(child.get_meta("cascade_right", NAN))
	var bottom := float(child.get_meta("cascade_bottom", NAN))
	var minimum := child.get_combined_minimum_size()
	var child_style: CascadeStyle = child.get("cascade_style") if _has_property(child, "cascade_style") else null
	var desired := minimum
	if child_style != null:
		desired = child_style.constrain_minimum(minimum)
	var position := content.position + Vector2(0.0 if is_nan(left) else left, 0.0 if is_nan(top) else top)
	var resolved_size := desired
	if not is_nan(left) and not is_nan(right):
		resolved_size.x = maxf(content.size.x - left - right, 0.0)
	elif is_nan(left) and not is_nan(right):
		position.x = content.end.x - right - desired.x
	if not is_nan(top) and not is_nan(bottom):
		resolved_size.y = maxf(content.size.y - top - bottom, 0.0)
	elif is_nan(top) and not is_nan(bottom):
		position.y = content.end.y - bottom - desired.y
	return Rect2(position, resolved_size)


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
