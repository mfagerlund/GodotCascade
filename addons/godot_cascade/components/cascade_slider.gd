@tool
extends Range

## Native Range semantics with GodotCascade-owned track, fill, and thumb drawing.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const FocusVisibilityTracker := preload("res://addons/godot_cascade/components/focus_visibility_tracker.gd")

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(next):
		cascade_style = next if next != null else CascadeStyle.new()
		queue_redraw()
		update_minimum_size()

@export_group("Appearance")
@export var fill_color := Color("528bff"):
	set(next):
		fill_color = next
		queue_redraw()
@export var hover_fill_color := Color("75a5ff"):
	set(next):
		hover_fill_color = next
		queue_redraw()
@export var hover_background_color := Color("475467"):
	set(next):
		hover_background_color = next
		queue_redraw()
@export var thumb_color := Color.WHITE:
	set(next):
		thumb_color = next
		queue_redraw()
@export var hover_thumb_color := Color("dbeafe"):
	set(next):
		hover_thumb_color = next
		queue_redraw()
@export var disabled_thumb_color := Color("98a2b3"):
	set(next):
		disabled_thumb_color = next
		queue_redraw()
@export var focus_ring_color := Color("84adff"):
	set(next):
		focus_ring_color = next
		queue_redraw()
@export var focus_visible_ring_color := Color("84adff"):
	set(next):
		focus_visible_ring_color = next
		queue_redraw()
@export var focus_visible_ring_width := 2.0:
	set(next):
		focus_visible_ring_width = maxf(next, 0.0)
		queue_redraw()
@export var focus_visible_style_enabled := false:
	set(next):
		focus_visible_style_enabled = next
		queue_redraw()
@export_range(2.0, 64.0, 1.0, "or_greater") var track_height := 6.0:
	set(next):
		track_height = maxf(next, 2.0)
		queue_redraw()
		update_minimum_size()
@export_range(4.0, 128.0, 1.0, "or_greater") var thumb_size := 18.0:
	set(next):
		thumb_size = maxf(next, 4.0)
		queue_redraw()
		update_minimum_size()

var disabled := false:
	set(next):
		disabled = next
		mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_STOP
		queue_redraw()
var _dragging := false
var _hovered := false
var _focus_tracker: RefCounted


func _init() -> void:
	allow_greater = false
	allow_lesser = false
	step = 1.0
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cascade_style.preferred_width = 160.0
	cascade_style.preferred_height = 24.0
	cascade_style.background_color = Color("344054")


func _ready() -> void:
	value_changed.connect(_on_value_changed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_focus_tracker = FocusVisibilityTracker.new()
	_focus_tracker.attach(self)
	_focus_tracker.changed.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(
		Vector2(thumb_size, maxf(thumb_size, track_height)),
		cascade_style.padding(),
		cascade_style.border_width
	))


func _draw() -> void:
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	var track := Rect2(
		content.position.x + thumb_size * 0.5,
		content.get_center().y - track_height * 0.5,
		maxf(content.size.x - thumb_size, 0.0),
		track_height
	)
	BoxPainter.draw_box(self, track, cascade_track_color(), cascade_style.border_color, cascade_style.border_width, track_height * 0.5)
	var fill := track
	fill.size.x *= ratio
	BoxPainter.draw_box(self, fill, cascade_fill_color(), Color.TRANSPARENT, 0.0, track_height * 0.5)
	var thumb_center := Vector2(track.position.x + track.size.x * ratio, content.get_center().y)
	draw_circle(thumb_center, thumb_size * 0.5, cascade_thumb_color(), true, -1.0, true)
	var show_ring: bool = has_focus() and (not focus_visible_style_enabled or _focus_tracker == null or bool(_focus_tracker.is_focus_visible()))
	if show_ring:
		var ring_color := focus_visible_ring_color if focus_visible_style_enabled else focus_ring_color
		var ring_width := focus_visible_ring_width if focus_visible_style_enabled else 2.0
		draw_arc(thumb_center, thumb_size * 0.5 + 2.0, 0.0, TAU, 32, ring_color, ring_width, true)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			_set_value_from_position(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_value_from_position(event.position.x)
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_down"):
		value -= step if step > 0.0 else 1.0
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up"):
		value += step if step > 0.0 else 1.0
		accept_event()


func set_range_values(next_min: float, next_max: float, next_value: float) -> void:
	min_value = next_min
	max_value = maxf(next_max, next_min)
	value = clampf(next_value, min_value, max_value)


func cascade_track_color() -> Color:
	return hover_background_color if _hovered and not disabled else cascade_style.background_color


func cascade_fill_color() -> Color:
	return hover_fill_color if _hovered and not disabled else fill_color


func cascade_thumb_color() -> Color:
	if disabled:
		return disabled_thumb_color
	return hover_thumb_color if _hovered else thumb_color


func _set_value_from_position(local_x: float) -> void:
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	var usable_width := maxf(content.size.x - thumb_size, 1.0)
	var normalized := clampf((local_x - content.position.x - thumb_size * 0.5) / usable_width, 0.0, 1.0)
	value = lerpf(min_value, max_value, normalized)


func _on_value_changed(_value: float) -> void:
	queue_redraw()


func _on_mouse_entered() -> void:
	_hovered = true
	queue_redraw()


func _on_mouse_exited() -> void:
	_hovered = false
	queue_redraw()
