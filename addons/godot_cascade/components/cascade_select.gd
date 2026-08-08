@tool
extends "res://addons/godot_cascade/components/cascade_button.gd"

## Owned closed select control backed by a native PopupPanel and option buttons.

signal selection_changed(value: String, index: int)

const CascadeOptionButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
const AccessibilitySemantics := preload("res://addons/godot_cascade/runtime/accessibility_semantics.gd")

@export_group("Selection")
@export var placeholder := "Select an option":
	set(value):
		placeholder = value
		_update_closed_text()
@export var options: Array[Dictionary] = []:
	set(value):
		var retained_value := selected_value()
		options = _normalized_options(value)
		selected_index = _index_for_value(retained_value)
		if selected_index < 0 and not options.is_empty():
			selected_index = 0
		if options.is_empty():
			close_popup()
		_request_popup_rebuild()
		_update_closed_text()
@export var selected_index := -1:
	set(value):
		selected_index = clampi(value, -1, options.size() - 1)
		_update_popup_selection()
		_update_closed_text()

@export_group("Option Appearance")
@export var option_background_color := Color("101828"):
	set(value):
		option_background_color = value
		_request_popup_rebuild()
@export var option_hover_background_color := Color("1d2939"):
	set(value):
		option_hover_background_color = value
		_request_popup_rebuild()
@export var option_selected_background_color := Color("16233a"):
	set(value):
		option_selected_background_color = value
		_request_popup_rebuild()
@export var option_text_color := Color("d0d5dd"):
	set(value):
		option_text_color = value
		_request_popup_rebuild()
@export var option_selected_text_color := Color.WHITE:
	set(value):
		option_selected_text_color = value
		_request_popup_rebuild()
@export_range(24.0, 128.0, 1.0, "or_greater") var option_height := 32.0:
	set(value):
		option_height = maxf(value, 24.0)
		_request_popup_rebuild()

var _popup: PopupPanel
var _option_scroll: ScrollContainer
var _option_list: VBoxContainer
var _option_buttons: Array[BaseButton] = []
var _highlighted_index := -1
var _popup_rebuild_pending := true
var _popup_rebuild_queued := false


func _init() -> void:
	super()
	text = placeholder
	text_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cascade_style.padding_right = 34.0


func _draw() -> void:
	super()
	var center := Vector2(size.x - 17.0, size.y * 0.5)
	var direction := -1.0 if is_open() else 1.0
	var points := PackedVector2Array([
		center + Vector2(-4.0, -2.0 * direction),
		center + Vector2(0.0, 2.0 * direction),
		center + Vector2(4.0, -2.0 * direction),
	])
	draw_polyline(points, _current_text_color(), 2.0, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilitySemantics.set_select(self, _option_buttons, selected_index, _highlighted_index)


func _ready() -> void:
	super()
	_ensure_popup()
	pressed.connect(_toggle_popup)
	_rebuild_popup()


func _exit_tree() -> void:
	if _popup != null and _popup.visible:
		_popup.hide()


func _input(event: InputEvent) -> void:
	_handle_open_input(event, get_viewport())


func _handle_open_input(event: InputEvent, input_viewport: Viewport) -> void:
	if not is_open() or not event.is_pressed():
		return
	if event.is_action_pressed("ui_down"):
		_move_highlight(1)
		input_viewport.set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_highlight(-1)
		input_viewport.set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_select_index(_highlighted_index)
		input_viewport.set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_popup.hide()
		input_viewport.set_input_as_handled()


func cascade_visual_state() -> String:
	if _state_adapter == null:
		return InteractiveStateAdapter.BASE
	return _state_adapter.current_state(is_open())


## Returns the authored value for the current selection, or an empty string.
func selected_value() -> String:
	if selected_index < 0 or selected_index >= options.size():
		return ""
	return str(options[selected_index].get("value", ""))


## Selects an authored option value. Returns false when no option matches.
func select_value(value: Variant, notify: bool = false) -> bool:
	var index := _index_for_value(str(value))
	if index < 0:
		return false
	var changed := selected_index != index
	selected_index = index
	if changed and notify:
		selection_changed.emit(selected_value(), selected_index)
	return true


## Opens the native option popup below the closed control.
func open_popup() -> void:
	if disabled or options.is_empty():
		return
	_ensure_popup()
	if _popup_rebuild_pending:
		_rebuild_popup()
	_highlighted_index = selected_index if selected_index >= 0 else _next_enabled(-1, 1)
	_update_popup_selection()
	var viewport_rect := get_viewport().get_visible_rect()
	var content_height := ceili(option_height * options.size() + 8.0)
	var maximum_height := maxi(ceili(option_height + 8.0), mini(320, floori(viewport_rect.size.y * 0.5)))
	var popup_height := mini(content_height, maximum_height)
	var popup_width := mini(maxi(roundi(size.x), 160), floori(viewport_rect.size.x))
	var below := viewport_rect.end.y - (global_position.y + size.y + 2.0)
	var above := global_position.y - viewport_rect.position.y - 2.0
	var open_above := below < popup_height and above > below
	var popup_y := global_position.y - popup_height - 2.0 if open_above else global_position.y + size.y + 2.0
	popup_y = clampf(popup_y, viewport_rect.position.y, viewport_rect.end.y - popup_height)
	var popup_x := clampf(global_position.x, viewport_rect.position.x, viewport_rect.end.x - popup_width)
	_popup.popup(Rect2i(Vector2i(roundi(popup_x), roundi(popup_y)), Vector2i(popup_width, popup_height)))
	queue_redraw()


func close_popup() -> void:
	if _popup != null:
		_popup.hide()


func is_open() -> bool:
	return _popup != null and _popup.visible


func _toggle_popup() -> void:
	if is_open():
		close_popup()
	else:
		open_popup()


func _ensure_popup() -> void:
	if _popup != null:
		return
	_popup = PopupPanel.new()
	_popup.name = "_Popup"
	_popup.transparent_bg = true
	_popup.popup_hide.connect(_on_popup_hidden)
	_popup.window_input.connect(_on_popup_window_input)
	add_child(_popup, false, Node.INTERNAL_MODE_BACK)
	_option_scroll = ScrollContainer.new()
	_option_scroll.name = "_OptionsScroll"
	_option_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_popup.add_child(_option_scroll)
	_option_list = VBoxContainer.new()
	_option_list.name = "_Options"
	_option_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_list.add_theme_constant_override("separation", 2)
	_option_scroll.add_child(_option_list)


func _request_popup_rebuild() -> void:
	_popup_rebuild_pending = true
	if _option_list == null or _popup_rebuild_queued:
		return
	_popup_rebuild_queued = true
	_rebuild_popup.call_deferred()


func _rebuild_popup() -> void:
	_popup_rebuild_queued = false
	if _option_list == null or not _popup_rebuild_pending:
		return
	for child in _option_list.get_children():
		_option_list.remove_child(child)
		child.queue_free()
	_option_buttons.clear()
	for index in options.size():
		var option: Dictionary = options[index]
		var button := CascadeOptionButton.new()
		button.text = str(option["label"])
		button.text_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.font_size = font_size
		button.font = font
		button.custom_minimum_size = Vector2(0.0, option_height)
		button.cascade_style.padding_left = 12.0
		button.cascade_style.padding_top = 0.0
		button.cascade_style.padding_right = 12.0
		button.cascade_style.padding_bottom = 0.0
		button.cascade_style.border_color = Color.TRANSPARENT
		button.cascade_style.border_width = 0.0
		button.cascade_style.border_radius = 6.0
		button.toggle_mode = true
		button.disabled = bool(option.get("disabled", false))
		button.cascade_style.background_color = option.get("background_color", option_background_color)
		button.hover_background_color = option.get("hover_background_color", option_hover_background_color)
		button.checked_background_color = option.get("selected_background_color", option_selected_background_color)
		button.disabled_background_color = option.get("disabled_background_color", option_background_color)
		button.text_color = option.get("text_color", option_text_color)
		button.checked_text_color = option.get("selected_text_color", option_selected_text_color)
		button.disabled_text_color = option.get("disabled_text_color", option_text_color.darkened(0.35))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_index.bind(index))
		_option_list.add_child(button)
		_option_buttons.append(button)
	_popup_rebuild_pending = false
	_update_popup_selection()


func _update_popup_selection() -> void:
	for index in _option_buttons.size():
		if index >= options.size():
			_option_buttons[index].visible = false
			continue
		_option_buttons[index].visible = true
		_option_buttons[index].button_pressed = index == selected_index
		if index == _highlighted_index and index != selected_index:
			_option_buttons[index].cascade_style.background_color = options[index].get("hover_background_color", option_hover_background_color)
		else:
			_option_buttons[index].cascade_style.background_color = options[index].get("background_color", option_background_color)
	_request_option_accessibility_update()


func _request_option_accessibility_update() -> void:
	queue_accessibility_update()


func _select_index(index: int) -> void:
	if index < 0 or index >= options.size() or bool(options[index].get("disabled", false)):
		return
	var changed := selected_index != index
	selected_index = index
	close_popup()
	grab_focus()
	if changed:
		selection_changed.emit(selected_value(), selected_index)


func _move_highlight(direction: int) -> void:
	_highlighted_index = _next_enabled(_highlighted_index, direction)
	_update_popup_selection()
	if _highlighted_index >= 0 and _highlighted_index < _option_buttons.size() and _option_scroll != null:
		_option_scroll.ensure_control_visible.call_deferred(_option_buttons[_highlighted_index])


func _next_enabled(from_index: int, direction: int) -> int:
	if options.is_empty():
		return -1
	var candidate := from_index
	for _step in options.size():
		candidate = posmod(candidate + direction, options.size())
		if not bool(options[candidate].get("disabled", false)):
			return candidate
	return -1


func _index_for_value(value: String) -> int:
	if value.is_empty():
		return -1
	for index in options.size():
		if str(options[index].get("value", "")) == value:
			return index
	return -1


func _update_closed_text() -> void:
	if selected_index >= 0 and selected_index < options.size():
		text = str(options[selected_index].get("label", ""))
	else:
		text = placeholder
	if not bool(get_meta("cascade_explicit_accessible_label", false)):
		accessibility_name = text


func _on_popup_hidden() -> void:
	queue_redraw()


func _on_popup_window_input(event: InputEvent) -> void:
	_handle_open_input(event, _popup)


static func _normalized_options(raw_options: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option in raw_options:
		var label := str(option.get("label", option.get("value", "")))
		result.append({
			"label": label,
			"value": str(option.get("value", label)),
			"disabled": bool(option.get("disabled", false)),
		})
		for style_name in [
			"background_color", "hover_background_color", "selected_background_color",
			"disabled_background_color", "text_color", "selected_text_color", "disabled_text_color",
		]:
			if option.has(style_name):
				result[-1][style_name] = option[style_name]
	return result
