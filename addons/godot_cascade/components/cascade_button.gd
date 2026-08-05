@tool
extends BaseButton

## GodotCascade-owned button with exact box-model measurement and drawing.
## Interaction, focus, shortcuts, toggle state, and signals remain Godot-native.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

@export_group("Content")
@export var text := "Button":
	set(value):
		text = value
		_invalidate_layout()
@export var font: Font:
	set(value):
		font = value
		_invalidate_layout()
@export_range(1, 256, 1, "or_greater") var font_size := 16:
	set(value):
		font_size = maxi(value, 1)
		_invalidate_layout()
@export var text_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER:
	set(value):
		text_alignment = value
		queue_redraw()

@export_group("Padding")
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_left := 14.0:
	set(value):
		padding_left = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_top := 9.0:
	set(value):
		padding_top = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_right := 14.0:
	set(value):
		padding_right = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_bottom := 9.0:
	set(value):
		padding_bottom = maxf(value, 0.0)
		_invalidate_layout()

@export_group("Margin")
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_left := 0.0:
	set(value):
		margin_left = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_top := 0.0:
	set(value):
		margin_top = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_right := 0.0:
	set(value):
		margin_right = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_bottom := 0.0:
	set(value):
		margin_bottom = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Size")
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_width := 0.0:
	set(value):
		preferred_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_height := 0.0:
	set(value):
		preferred_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_width := 0.0:
	set(value):
		min_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_height := 0.0:
	set(value):
		min_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_width := 0.0:
	set(value):
		max_width = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_height := 0.0:
	set(value):
		max_height = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 100.0, 0.05, "or_greater") var flex_grow := 0.0:
	set(value):
		flex_grow = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Appearance")
@export var background_color := Color("344054"):
	set(value):
		background_color = value
		queue_redraw()
@export var hover_background_color := Color("475467"):
	set(value):
		hover_background_color = value
		queue_redraw()
@export var pressed_background_color := Color("1d2939"):
	set(value):
		pressed_background_color = value
		queue_redraw()
@export var disabled_background_color := Color("1f2937"):
	set(value):
		disabled_background_color = value
		queue_redraw()
@export var text_color := Color("f2f4f7"):
	set(value):
		text_color = value
		queue_redraw()
@export var disabled_text_color := Color("98a2b3"):
	set(value):
		disabled_text_color = value
		queue_redraw()
@export var border_color := Color("667085"):
	set(value):
		border_color = value
		queue_redraw()
@export_range(0.0, 128.0, 1.0, "or_greater") var border_width := 1.0:
	set(value):
		border_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 512.0, 1.0, "or_greater") var border_radius := 7.0:
	set(value):
		border_radius = maxf(value, 0.0)
		queue_redraw()

@export_group("Focus")
@export var focus_ring_color := Color("84adff"):
	set(value):
		focus_ring_color = value
		queue_redraw()
@export_range(0.0, 32.0, 1.0, "or_greater") var focus_ring_width := 2.0:
	set(value):
		focus_ring_width = maxf(value, 0.0)
		queue_redraw()


func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_down.connect(_on_visual_state_changed)
	button_up.connect(_on_visual_state_changed)
	mouse_entered.connect(_on_visual_state_changed)
	mouse_exited.connect(_on_visual_state_changed)
	focus_entered.connect(_on_visual_state_changed)
	focus_exited.connect(_on_visual_state_changed)
	toggled.connect(_on_toggled)
	resized.connect(_on_visual_state_changed)


func _get_minimum_size() -> Vector2:
	var resolved_font := _resolved_font()
	var content_size := Vector2.ZERO
	if resolved_font != null and not text.is_empty():
		content_size = resolved_font.get_string_size(
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size
		)
		content_size.y = resolved_font.get_height(font_size)

	var result := BoxPainter.outer_minimum_size(content_size, _padding(), border_width)
	result.x = maxf(maxf(result.x, min_width), preferred_width)
	result.y = maxf(maxf(result.y, min_height), preferred_height)
	return result


func _draw() -> void:
	var box_rect := Rect2(Vector2.ZERO, size)
	BoxPainter.draw_box(
		self,
		box_rect,
		_current_background_color(),
		border_color,
		border_width,
		border_radius
	)

	if has_focus() and focus_ring_width > 0.0:
		BoxPainter.draw_box(
			self,
			box_rect,
			Color.TRANSPARENT,
			focus_ring_color,
			focus_ring_width,
			border_radius
		)

	_draw_text(BoxPainter.content_rect(box_rect, _padding(), border_width))


func _draw_text(content: Rect2) -> void:
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
		text_alignment,
		content.size.x,
		font_size,
		disabled_text_color if disabled else text_color
	)


func _current_background_color() -> Color:
	if disabled:
		return disabled_background_color
	if is_pressed() or button_pressed:
		return pressed_background_color
	if is_hovered():
		return hover_background_color
	return background_color


func _resolved_font() -> Font:
	if font != null:
		return font
	return get_theme_default_font()


func _padding() -> Vector4:
	return Vector4(padding_left, padding_top, padding_right, padding_bottom)


func _invalidate_layout() -> void:
	queue_redraw()
	if not is_inside_tree():
		return
	update_minimum_size()
	_notify_parent_layout_changed()


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_visual_state_changed() -> void:
	queue_redraw()


func _on_toggled(_is_pressed: bool) -> void:
	queue_redraw()
