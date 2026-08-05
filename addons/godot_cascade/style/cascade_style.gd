@tool
class_name CascadeStyle
extends Resource

## Shared computed-style surface for box-model properties.
##
## Today this resource is editable and reusable. The future stylesheet engine will
## produce the same shape as immutable computed style, letting controls consume CSS
## values without separate property implementations.

signal invalidated(flags: int)

enum Invalidation {
	DRAW = 1,
	MEASURE = 2,
	ARRANGE = 4,
	ALL = DRAW | MEASURE | ARRANGE,
}

@export_group("Padding")
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_left := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(padding_left, next): return
		padding_left = next
		_emit_invalidation(Invalidation.ALL)
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_top := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(padding_top, next): return
		padding_top = next
		_emit_invalidation(Invalidation.ALL)
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_right := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(padding_right, next): return
		padding_right = next
		_emit_invalidation(Invalidation.ALL)
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_bottom := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(padding_bottom, next): return
		padding_bottom = next
		_emit_invalidation(Invalidation.ALL)

@export_group("Margin")
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_left := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(margin_left, next): return
		margin_left = next
		_emit_invalidation(Invalidation.ARRANGE)
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_top := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(margin_top, next): return
		margin_top = next
		_emit_invalidation(Invalidation.ARRANGE)
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_right := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(margin_right, next): return
		margin_right = next
		_emit_invalidation(Invalidation.ARRANGE)
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_bottom := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(margin_bottom, next): return
		margin_bottom = next
		_emit_invalidation(Invalidation.ARRANGE)

@export_group("Size")
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_width := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(preferred_width, next): return
		preferred_width = next
		_emit_invalidation(Invalidation.MEASURE | Invalidation.ARRANGE)
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_height := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(preferred_height, next): return
		preferred_height = next
		_emit_invalidation(Invalidation.MEASURE | Invalidation.ARRANGE)
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_width := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(min_width, next): return
		min_width = next
		_emit_invalidation(Invalidation.MEASURE | Invalidation.ARRANGE)
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_height := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(min_height, next): return
		min_height = next
		_emit_invalidation(Invalidation.MEASURE | Invalidation.ARRANGE)
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_width := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(max_width, next): return
		max_width = next
		_emit_invalidation(Invalidation.ARRANGE)
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_height := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(max_height, next): return
		max_height = next
		_emit_invalidation(Invalidation.ARRANGE)
@export_range(0.0, 100.0, 0.05, "or_greater") var flex_grow := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(flex_grow, next): return
		flex_grow = next
		_emit_invalidation(Invalidation.ARRANGE)

@export_group("Box Appearance")
@export var background_color := Color.TRANSPARENT:
	set(value):
		if background_color == value:
			return
		background_color = value
		_emit_invalidation(Invalidation.DRAW)
@export var border_color := Color.TRANSPARENT:
	set(value):
		if border_color == value:
			return
		border_color = value
		_emit_invalidation(Invalidation.DRAW)
@export_range(0.0, 128.0, 1.0, "or_greater") var border_width := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(border_width, next): return
		border_width = next
		_emit_invalidation(Invalidation.ALL)
@export_range(0.0, 512.0, 1.0, "or_greater") var border_radius := 0.0:
	set(value):
		var next := maxf(value, 0.0)
		if is_equal_approx(border_radius, next): return
		border_radius = next
		_emit_invalidation(Invalidation.DRAW)


func padding() -> Vector4:
	return Vector4(padding_left, padding_top, padding_right, padding_bottom)


func margins() -> Vector4:
	return Vector4(margin_left, margin_top, margin_right, margin_bottom)


func maximum_size() -> Vector2:
	return Vector2(
		max_width if max_width > 0.0 else INF,
		max_height if max_height > 0.0 else INF
	)


func constrain_minimum(content_minimum: Vector2) -> Vector2:
	return Vector2(
		maxf(maxf(content_minimum.x, min_width), preferred_width),
		maxf(maxf(content_minimum.y, min_height), preferred_height)
	)


func _emit_invalidation(flags: int) -> void:
	emit_changed()
	invalidated.emit(flags)
