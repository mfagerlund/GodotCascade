@tool
extends "res://addons/godot_cascade/components/cascade_checkbox.gd"

## GodotCascade-owned radio button using native BaseButton and ButtonGroup behavior.


func _init() -> void:
	super()
	text = "Radio button"


func _draw_indicator(indicator_rect: Rect2) -> void:
	var center := indicator_rect.get_center()
	var radius := minf(indicator_rect.size.x, indicator_rect.size.y) * 0.5
	var fill := disabled_indicator_color if disabled else indicator_background_color
	draw_circle(center, radius, fill)
	draw_arc(center, radius - 0.5, 0.0, TAU, 32, indicator_border_color, 1.0, true)
	if button_pressed:
		var dot_color := disabled_indicator_color.lightened(0.25) if disabled else checked_indicator_color
		draw_circle(center, radius * 0.52, dot_color)
