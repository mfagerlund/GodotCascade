@tool
extends Control

## GodotCascade-owned horizontal progress control with an exact box model.
## The value surface follows Godot's Range naming without inheriting themed drawing.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

@export_group("Value")
@export var min_value := 0.0:
	set(next):
		min_value = next
		if max_value < min_value:
			max_value = min_value
		value = clampf(value, min_value, max_value)
		queue_redraw()
@export var max_value := 100.0:
	set(next):
		max_value = maxf(next, min_value)
		value = clampf(value, min_value, max_value)
		queue_redraw()
@export var value := 0.0:
	set(next):
		value = clampf(next, min_value, max_value)
		queue_redraw()

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(next):
		var resolved := next if next != null else CascadeStyle.new()
		if cascade_style == resolved:
			return
		_disconnect_style()
		cascade_style = resolved
		_connect_style()
		_on_style_invalidated(CascadeStyle.Invalidation.ALL)

@export_group("Appearance")
@export var fill_color := Color("53b1fd"):
	set(next):
		fill_color = next
		queue_redraw()
@export_range(0.0, 512.0, 1.0, "or_greater") var fill_border_radius := 999.0:
	set(next):
		fill_border_radius = maxf(next, 0.0)
		queue_redraw()


func _init() -> void:
	cascade_style.preferred_height = 14.0
	cascade_style.background_color = Color("273142")
	cascade_style.border_radius = 999.0
	cascade_style.overflow = CascadeStyle.Overflow.CLIP


func _ready() -> void:
	_connect_style()
	_apply_overflow()


func ratio() -> float:
	var span := max_value - min_value
	if span <= 0.0:
		return 0.0
	return clampf((value - min_value) / span, 0.0, 1.0)


## Updates the complete range in a defined min/max/value order.
func set_range_values(next_min: float, next_max: float, next_value: float) -> void:
	var resolved_max := maxf(next_max, next_min)
	min_value = next_min
	max_value = resolved_max
	value = clampf(next_value, next_min, resolved_max)


func _get_minimum_size() -> Vector2:
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(
		Vector2.ZERO,
		cascade_style.padding(),
		cascade_style.border_width
	))


func _draw() -> void:
	var box_rect := Rect2(Vector2.ZERO, size)
	BoxPainter.draw_box(
		self,
		box_rect,
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius
	)
	var fill_rect := BoxPainter.content_rect(
		box_rect,
		cascade_style.padding(),
		cascade_style.border_width
	)
	fill_rect.size.x *= ratio()
	if fill_rect.size.x <= 0.0 or fill_rect.size.y <= 0.0:
		return
	BoxPainter.draw_box(
		self,
		fill_rect,
		fill_color,
		Color.TRANSPARENT,
		0.0,
		minf(fill_border_radius, minf(fill_rect.size.x, fill_rect.size.y) * 0.5)
	)


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
	if flags & CascadeStyle.Invalidation.MEASURE and is_inside_tree():
		update_minimum_size()
	if flags & CascadeStyle.Invalidation.ARRANGE:
		_notify_parent_layout_changed()


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP


func _notify_parent_layout_changed() -> void:
	if is_inside_tree() and get_parent() is Container:
		get_parent().queue_sort()
