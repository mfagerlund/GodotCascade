extends RefCounted

## Tracks whether focus was reached through keyboard/controller navigation.

signal changed

static var _keyboard_navigation := true

var _control: Control


func attach(control: Control) -> void:
	_control = control
	control.gui_input.connect(_on_gui_input)
	control.focus_entered.connect(_on_focus_changed)
	control.focus_exited.connect(_on_focus_changed)


func is_focus_visible() -> bool:
	return _control != null and _control.has_focus() and _keyboard_navigation


static func set_keyboard_navigation(enabled: bool) -> void:
	_keyboard_navigation = enabled


func _on_gui_input(event: InputEvent) -> void:
	var previous := _keyboard_navigation
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_keyboard_navigation = false
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_keyboard_navigation = true
	if previous != _keyboard_navigation:
		changed.emit()


func _on_focus_changed() -> void:
	changed.emit()
