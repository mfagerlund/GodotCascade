extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Interactive settings showcase backed by explicit writable bindings.

var state: ShowcaseSettingsMenuState


func _ready() -> void:
	state = ShowcaseSettingsMenuState.new()
	binding_context = state
	event_context = self
	binding_value_changed.connect(_on_binding_value_changed)
	super()


func _on_binding_value_changed(path: String, value: Variant, _control: Control) -> void:
	if path == "settings.ui_scale":
		state.ui.scale_label = "%d%%" % roundi(float(value))
	state.ui.status = "Unsaved changes"


func _on_apply_settings() -> void:
	if not validate():
		state.ui.status = "Fix the highlighted profile name"
		refresh_bindings()
		return
	state.ui.status = "Applied %s quality for %s" % [state.settings.quality, state.settings.profile]
	refresh_bindings()
