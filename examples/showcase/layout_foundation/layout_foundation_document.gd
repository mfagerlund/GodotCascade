extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Interactive data source for the layout-foundation showcase page.


func _ready() -> void:
	binding_context = {"ui": {"status": "Phase 1 · Layout foundation"}}
	event_context = self
	super()


func _on_inspect_layout() -> void:
	binding_context["ui"]["status"] = "Layout inspection requested"
	refresh_bindings()
