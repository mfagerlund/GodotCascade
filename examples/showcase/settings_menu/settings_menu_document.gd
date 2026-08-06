extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Interactive settings showcase backed by explicit writable bindings.


func _ready() -> void:
	binding_context = {
		"settings": {
			"profile": "Rhea",
			"shadows": true,
			"bloom": true,
			"vsync": true,
			"ui_scale": 100.0,
			"quality": "high",
			"notes": "Ready for the next match.",
			"hud_channels": [
				{"id": "damage", "label": "Damage numbers", "enabled": true},
				{"id": "team", "label": "Team markers", "enabled": false},
			],
		},
		"ui": {
			"scale_label": "100%",
			"status": "Change a setting, then apply",
		},
	}
	event_context = self
	binding_value_changed.connect(_on_binding_value_changed)
	super()


func _on_binding_value_changed(path: String, value: Variant, _control: Control) -> void:
	if path == "settings.ui_scale":
		binding_context["ui"]["scale_label"] = "%d%%" % roundi(float(value))
	binding_context["ui"]["status"] = "Unsaved changes"


func _on_apply_settings() -> void:
	if not validate():
		binding_context["ui"]["status"] = "Fix the highlighted profile name"
		refresh_bindings()
		return
	var settings: Dictionary = binding_context["settings"]
	binding_context["ui"]["status"] = "Applied %s quality for %s" % [settings["quality"], settings["profile"]]
	refresh_bindings()
