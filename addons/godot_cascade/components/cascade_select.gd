@tool
extends "res://addons/godot_cascade/components/cascade_button.gd"

## Owned closed select control backed by a native PopupPanel and option buttons.

signal selection_changed(value: String, index: int)

const CascadeOptionButton := preload("res://addons/godot_cascade/components/cascade_button.gd")

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
		_rebuild_popup()
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
		_rebuild_popup()
@export var option_hover_background_color := Color("1d2939"):
	set(value):
		option_hover_background_color = value
		_rebuild_popup()
@export var option_selected_background_color := Color("16233a"):
	set(value):
		option_selected_background_color = value
		_rebuild_popup()
@export var option_text_color := Color("d0d5dd"):
	set(value):
		option_text_color = value
		_rebuild_popup()
@export var option_selected_text_color := Color.WHITE:
	set(value):
		option_selected_text_color = value
		_rebuild_popup()
@export_range(24.0, 128.0, 1.0, "or_greater") var option_height := 36.0:
	set(value):
		option_height = maxf(value, 24.0)
		_rebuild_popup()

var _popup: PopupPanel
var _option_list: VBoxContainer
var _option_buttons: Array[BaseButton] = []
var _highlighted_index := -1


func _init() -> void:
	super()
	text = placeholder
	text_alignment = HORIZONTAL_ALIGNMENT_LEFT


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


## Opens the native option popup below the closed control.
func open_popup() -> void:
	if disabled or options.is_empty():
		return
	_ensure_popup()
	_highlighted_index = selected_index if selected_index >= 0 else _next_enabled(-1, 1)
	_update_popup_selection()
	var popup_height := ceili(option_height * options.size() + 8.0)
	var popup_position := Vector2i(roundi(global_position.x), roundi(global_position.y + size.y + 2.0))
	_popup.popup(Rect2i(popup_position, Vector2i(maxi(roundi(size.x), 160), popup_height)))
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
	_option_list = VBoxContainer.new()
	_option_list.name = "_Options"
	_option_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_option_list.add_theme_constant_override("separation", 2)
	_popup.add_child(_option_list)


func _rebuild_popup() -> void:
	if _option_list == null:
		return
	for child in _option_list.get_children():
		child.queue_free()
	_option_buttons.clear()
	for index in options.size():
		var option: Dictionary = options[index]
		var button := CascadeOptionButton.new()
		button.text = str(option["label"])
		button.text_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, option_height)
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
	_update_popup_selection()


func _update_popup_selection() -> void:
	for index in _option_buttons.size():
		_option_buttons[index].button_pressed = index == selected_index
		if index == _highlighted_index and index != selected_index:
			_option_buttons[index].cascade_style.background_color = options[index].get("hover_background_color", option_hover_background_color)
		else:
			_option_buttons[index].cascade_style.background_color = options[index].get("background_color", option_background_color)


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
	if not has_meta("cascade_explicit_accessible_label"):
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
