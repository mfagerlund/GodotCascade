@tool
extends Control

## GodotCascade-owned text component.
##
## GodotCascade owns the outer box. An internal native Label performs text shaping,
## wrapping, localization, bidi layout, and glyph drawing inside the content box.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

@export_group("Content")
@export_multiline var text := "":
	set(value):
		text = value
		_sync_label()
		_invalidate_measure()
@export var font: Font:
	set(value):
		font = value
		_sync_label()
		_invalidate_measure()
@export_range(1, 256, 1, "or_greater") var font_size := 16:
	set(value):
		font_size = maxi(value, 1)
		_sync_label()
		_invalidate_measure()
@export var text_color := Color("d0d5dd"):
	set(value):
		text_color = value
		_sync_label()
@export var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT:
	set(value):
		horizontal_alignment = value
		_sync_label()
@export var vertical_alignment: VerticalAlignment = VERTICAL_ALIGNMENT_TOP:
	set(value):
		vertical_alignment = value
		_sync_label()
@export var autowrap_mode: TextServer.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART:
	set(value):
		autowrap_mode = value
		_sync_label()
		_invalidate_measure()
@export var text_overrun_behavior: TextServer.OverrunBehavior = TextServer.OVERRUN_NO_TRIMMING:
	set(value):
		text_overrun_behavior = value
		_sync_label()
@export_range(-1, 1024, 1) var max_lines_visible := -1:
	set(value):
		max_lines_visible = maxi(value, -1)
		_sync_label()
		_invalidate_measure()

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

var _label: Label


func _ready() -> void:
	_connect_style()
	_ensure_label()
	_apply_overflow()
	resized.connect(_on_resized)
	_sync_label()
	_update_label_rect()


func _get_minimum_size() -> Vector2:
	var content_minimum := Vector2.ZERO
	if _label != null:
		content_minimum = _label.get_combined_minimum_size()
	else:
		var resolved_font := _resolved_font()
		if resolved_font != null and not text.is_empty():
			content_minimum = resolved_font.get_multiline_string_size(
				text,
				horizontal_alignment,
				-1.0,
				font_size
			)
	if autowrap_mode != TextServer.AUTOWRAP_OFF:
		# Wrapped text accepts the containing block's width instead of forcing its
		# unwrapped line width into the parent's intrinsic minimum.
		content_minimum.x = 0.0
	var outer := BoxPainter.outer_minimum_size(
		content_minimum,
		cascade_style.padding(),
		cascade_style.border_width
	)
	return cascade_style.constrain_minimum(outer)


func _draw() -> void:
	BoxPainter.draw_box(
		self,
		Rect2(Vector2.ZERO, size),
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius
	)


func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.name = "_Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label, false, Node.INTERNAL_MODE_BACK)


func _sync_label() -> void:
	if _label == null:
		return
	_label.text = text
	_label.horizontal_alignment = horizontal_alignment
	_label.vertical_alignment = vertical_alignment
	_label.autowrap_mode = autowrap_mode
	_label.text_overrun_behavior = text_overrun_behavior
	_label.max_lines_visible = max_lines_visible
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	if font != null:
		_label.add_theme_font_override("font", font)
	else:
		_label.remove_theme_font_override("font")
	_update_label_rect()


func _update_label_rect() -> void:
	if _label == null:
		return
	var content := BoxPainter.content_rect(
		Rect2(Vector2.ZERO, size),
		cascade_style.padding(),
		cascade_style.border_width
	)
	_label.position = content.position
	_label.size = content.size


func _resolved_font() -> Font:
	if font != null:
		return font
	return get_theme_default_font()


func _invalidate_measure() -> void:
	queue_redraw()
	if not is_inside_tree():
		return
	update_minimum_size()
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
		if is_inside_tree():
			update_minimum_size()
		_update_label_rect()
	if flags & CascadeStyle.Invalidation.ARRANGE:
		_notify_parent_layout_changed()


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_resized() -> void:
	_update_label_rect()
	if autowrap_mode != TextServer.AUTOWRAP_OFF:
		update_minimum_size()


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP
