extends RefCounted

## Normalizes native BaseButton state into the shared GodotCascade state order.
##
## Higher-priority states win: disabled, pressed, checked, hover, focus, base.

signal changed

const BASE := ""
const FOCUSED := "focused"
const HOVER := "hover"
const CHECKED := "checked"
const SELECTED := "selected"
const PRESSED := "pressed"
const DISABLED := "disabled"

var _control: BaseButton
var _interaction_pressed := false
var _last_state := BASE


func attach(control: BaseButton) -> void:
	_control = control
	control.button_down.connect(_on_button_down)
	control.button_up.connect(_on_button_up)
	control.mouse_entered.connect(_on_native_state_changed)
	control.mouse_exited.connect(_on_native_state_changed)
	control.focus_entered.connect(_on_native_state_changed)
	control.focus_exited.connect(_on_native_state_changed)
	control.toggled.connect(_on_toggled)
	_last_state = current_state()


func current_state() -> String:
	if _control == null:
		return BASE
	return resolve(
		_control.disabled,
		_interaction_pressed,
		_control.toggle_mode and _control.button_pressed,
		_control.is_hovered(),
		_control.has_focus()
	)


func sync() -> void:
	var state := current_state()
	if state == _last_state:
		return
	_last_state = state
	changed.emit()


static func resolve(
	disabled: bool,
	pressed: bool,
	checked: bool,
	hovered: bool,
	focused: bool
) -> String:
	if disabled:
		return DISABLED
	if pressed:
		return PRESSED
	if checked:
		return CHECKED
	if hovered:
		return HOVER
	if focused:
		return FOCUSED
	return BASE


static func normalize(state: String) -> String:
	return CHECKED if state == SELECTED else state


func _on_button_down() -> void:
	_interaction_pressed = true
	sync()


func _on_button_up() -> void:
	_interaction_pressed = false
	sync()


func _on_native_state_changed() -> void:
	sync()


func _on_toggled(_checked: bool) -> void:
	sync()
