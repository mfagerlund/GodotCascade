@tool
extends "res://addons/godot_cascade/components/cascade_checkbox.gd"

## Checkbox semantics with a switch-specific track and thumb.

@export_group("Switch")
@export_range(12.0, 256.0, 1.0, "or_greater") var track_width := 38.0:
	set(value):
		track_width = maxf(value, 12.0)
		_invalidate_layout()
@export_range(8.0, 128.0, 1.0, "or_greater") var track_height := 20.0:
	set(value):
		track_height = maxf(value, 8.0)
		_invalidate_layout()
@export var track_color := Color("344054"):
	set(value):
		track_color = value
		queue_redraw()
@export var checked_track_color := Color("528bff"):
	set(value):
		checked_track_color = value
		queue_redraw()
@export var thumb_color := Color.WHITE:
	set(value):
		thumb_color = value
		queue_redraw()


func _init() -> void:
	super()
	text = "Switch"


func _indicator_dimensions() -> Vector2:
	return Vector2(track_width, track_height)


func _draw_indicator(indicator_rect: Rect2) -> void:
	var fill := disabled_indicator_color if disabled else (
		checked_track_color if button_pressed else track_color
	)
	BoxPainter.draw_box(
		self,
		indicator_rect,
		fill,
		indicator_border_color,
		1.0,
		indicator_rect.size.y * 0.5
	)
	var inset := 3.0
	var radius := maxf((indicator_rect.size.y - inset * 2.0) * 0.5, 1.0)
	var center_x := indicator_rect.end.x - inset - radius if button_pressed else indicator_rect.position.x + inset + radius
	var resolved_thumb := thumb_color.darkened(0.25) if disabled else thumb_color
	draw_circle(Vector2(center_x, indicator_rect.get_center().y), radius, resolved_thumb, true, -1.0, true)
