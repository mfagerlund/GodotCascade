@tool
extends BaseButton

## GodotCascade-owned button with exact box-model measurement and drawing.
## Interaction, focus, shortcuts, toggle state, and signals remain Godot-native.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const InteractiveStateAdapter := preload("res://addons/godot_cascade/components/interactive_state_adapter.gd")
const FocusVisibilityTracker := preload("res://addons/godot_cascade/components/focus_visibility_tracker.gd")

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

@export_group("Appearance")
@export var hover_background_color := Color("475467"):
	set(value):
		hover_background_color = value
		queue_redraw()
@export var pressed_background_color := Color("1d2939"):
	set(value):
		pressed_background_color = value
		queue_redraw()
@export var checked_background_color := Color("1d2939"):
	set(value):
		checked_background_color = value
		queue_redraw()
@export var open_background_color := Color("1d2939"):
	set(value):
		open_background_color = value
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
@export var checked_text_color := Color("f2f4f7"):
	set(value):
		checked_text_color = value
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
@export var focus_visible_ring_color := Color("84adff"):
	set(value):
		focus_visible_ring_color = value
		queue_redraw()
@export_range(0.0, 32.0, 1.0, "or_greater") var focus_visible_ring_width := 2.0:
	set(value):
		focus_visible_ring_width = maxf(value, 0.0)
		queue_redraw()
@export var focus_visible_style_enabled := false:
	set(value):
		focus_visible_style_enabled = value
		queue_redraw()

var _state_adapter: RefCounted
var _focus_tracker: RefCounted


func _init() -> void:
	cascade_style.padding_left = 14.0
	cascade_style.padding_top = 9.0
	cascade_style.padding_right = 14.0
	cascade_style.padding_bottom = 9.0
	cascade_style.background_color = Color("344054")
	cascade_style.border_color = Color("667085")
	cascade_style.border_width = 1.0
	cascade_style.border_radius = 7.0
	cascade_style.overflow = CascadeStyle.Overflow.CLIP


func _ready() -> void:
	_connect_style()
	_apply_overflow()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_state_adapter = InteractiveStateAdapter.new()
	_state_adapter.attach(self)
	_state_adapter.changed.connect(queue_redraw)
	_focus_tracker = FocusVisibilityTracker.new()
	_focus_tracker.attach(self)
	_focus_tracker.changed.connect(queue_redraw)
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

	var result := BoxPainter.outer_minimum_size(
		content_size,
		cascade_style.padding(),
		cascade_style.border_width
	)
	return cascade_style.constrain_minimum(result)


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

	var ring_width := focus_visible_ring_width if focus_visible_style_enabled else focus_ring_width
	var ring_color := focus_visible_ring_color if focus_visible_style_enabled else focus_ring_color
	var show_ring: bool = has_focus() and (not focus_visible_style_enabled or _focus_tracker == null or bool(_focus_tracker.is_focus_visible()))
	if show_ring and ring_width > 0.0:
		BoxPainter.draw_box(
			self,
			box_rect,
			Color.TRANSPARENT,
			ring_color,
			ring_width,
			cascade_style.border_radius
		)

	_draw_text(BoxPainter.content_rect(
		box_rect,
		cascade_style.padding(),
		cascade_style.border_width
	))


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
		_current_text_color()
	)


func _current_background_color() -> Color:
	match cascade_visual_state():
		InteractiveStateAdapter.DISABLED:
			return disabled_background_color
		InteractiveStateAdapter.PRESSED:
			return pressed_background_color
		InteractiveStateAdapter.CHECKED:
			return checked_background_color
		InteractiveStateAdapter.OPEN:
			return open_background_color
		InteractiveStateAdapter.HOVER:
			return hover_background_color
		_:
			return cascade_style.background_color


func _current_text_color() -> Color:
	match cascade_visual_state():
		InteractiveStateAdapter.DISABLED:
			return disabled_text_color
		InteractiveStateAdapter.CHECKED:
			return checked_text_color
		_:
			return text_color


## Returns the normalized native state used for pseudo-state drawing.
func cascade_visual_state() -> String:
	return InteractiveStateAdapter.BASE if _state_adapter == null else _state_adapter.current_state()


func _resolved_font() -> Font:
	if font != null:
		return font
	return get_theme_default_font()


func _invalidate_layout() -> void:
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
	if flags & CascadeStyle.Invalidation.ARRANGE:
		_notify_parent_layout_changed()


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_visual_state_changed() -> void:
	queue_redraw()
