@tool
extends "res://addons/godot_cascade/components/cascade_button.gd"

const AccessibilitySemantics := preload("res://addons/godot_cascade/runtime/accessibility_semantics.gd")

## GodotCascade-owned checkbox using native BaseButton toggle behavior.

@export_group("Indicator")
@export_range(4.0, 128.0, 1.0, "or_greater") var indicator_size := 18.0:
	set(value):
		indicator_size = maxf(value, 4.0)
		_invalidate_layout()
@export_range(0.0, 128.0, 1.0, "or_greater") var indicator_gap := 10.0:
	set(value):
		indicator_gap = maxf(value, 0.0)
		_invalidate_layout()
@export var indicator_background_color := Color("101828"):
	set(value):
		indicator_background_color = value
		queue_redraw()
@export var indicator_border_color := Color("667085"):
	set(value):
		indicator_border_color = value
		queue_redraw()
@export var checked_indicator_color := Color("528bff"):
	set(value):
		checked_indicator_color = value
		queue_redraw()
@export var checkmark_color := Color.WHITE:
	set(value):
		checkmark_color = value
		queue_redraw()
@export var disabled_indicator_color := Color("344054"):
	set(value):
		disabled_indicator_color = value
		queue_redraw()


func _init() -> void:
	super()
	text = "Checkbox"
	toggle_mode = true
	cascade_style.padding_left = 4.0
	cascade_style.padding_top = 4.0
	cascade_style.padding_right = 4.0
	cascade_style.padding_bottom = 4.0
	cascade_style.background_color = Color.TRANSPARENT
	cascade_style.border_color = Color.TRANSPARENT
	cascade_style.border_width = 0.0
	hover_background_color = Color("1d2939")
	pressed_background_color = Color("253b61")
	checked_background_color = Color.TRANSPARENT
	disabled_background_color = Color.TRANSPARENT


func _get_minimum_size() -> Vector2:
	var resolved_font := _resolved_font()
	var label_size := Vector2.ZERO
	if resolved_font != null and not text.is_empty():
		label_size = resolved_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		label_size.y = resolved_font.get_height(font_size)
	var indicator_dimensions := _indicator_dimensions()
	var content_width := indicator_dimensions.x
	if label_size.x > 0.0:
		content_width += indicator_gap + label_size.x
	var content_size := Vector2(content_width, maxf(indicator_dimensions.y, label_size.y))
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(
		content_size,
		cascade_style.padding(),
		cascade_style.border_width
	))


func _draw() -> void:
	var box_rect := Rect2(Vector2.ZERO, size)
	BoxPainter.draw_box(
		self,
		box_rect,
		_current_background_color(),
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius,
		cascade_style.background_gradient
	)
	if has_focus() and focus_ring_width > 0.0:
		BoxPainter.draw_box(
			self,
			box_rect,
			Color.TRANSPARENT,
			focus_ring_color,
			focus_ring_width,
			cascade_style.border_radius
		)

	var content := BoxPainter.content_rect(box_rect, cascade_style.padding(), cascade_style.border_width)
	var indicator_dimensions := _indicator_dimensions()
	var indicator_rect := Rect2(
		content.position.x,
		content.position.y + (content.size.y - indicator_dimensions.y) * 0.5,
		indicator_dimensions.x,
		indicator_dimensions.y
	)
	_draw_indicator(indicator_rect)
	_draw_checkbox_text(Rect2(
		Vector2(indicator_rect.end.x + indicator_gap, content.position.y),
		Vector2(maxf(content.end.x - indicator_rect.end.x - indicator_gap, 0.0), content.size.y)
	))


func _indicator_dimensions() -> Vector2:
	return Vector2(indicator_size, indicator_size)


func _draw_indicator(indicator_rect: Rect2) -> void:
	var fill := disabled_indicator_color if disabled else (
		checked_indicator_color if button_pressed else indicator_background_color
	)
	BoxPainter.draw_box(self, indicator_rect, fill, indicator_border_color, 1.0, 4.0)
	if not button_pressed:
		return
	var left := indicator_rect.position + indicator_rect.size * Vector2(0.22, 0.52)
	var middle := indicator_rect.position + indicator_rect.size * Vector2(0.43, 0.72)
	var right := indicator_rect.position + indicator_rect.size * Vector2(0.80, 0.30)
	draw_line(left, middle, checkmark_color, 2.0, true)
	draw_line(middle, right, checkmark_color, 2.0, true)


func _draw_checkbox_text(content: Rect2) -> void:
	var resolved_font := _resolved_font()
	if resolved_font == null or text.is_empty() or content.size.x <= 0.0 or content.size.y <= 0.0:
		return
	var baseline := content.position.y
	baseline += (content.size.y - resolved_font.get_height(font_size)) * 0.5
	baseline += resolved_font.get_ascent(font_size)
	draw_string(
		resolved_font,
		Vector2(content.position.x, baseline),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		content.size.x,
		font_size,
		_current_text_color()
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilitySemantics.set_role(self, AccessibilityServer.ROLE_CHECK_BOX)
