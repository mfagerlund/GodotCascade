extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Interactive data source for the layout-foundation showcase page.

var state := {"ui": {"status": "Phase 1 · Layout foundation"}}


func _ready() -> void:
	binding_context = ObservableBindingContext.new(state)
	event_context = self
	super()


func _on_inspect_layout() -> void:
	state["ui"]["status"] = "Layout inspection requested"
	binding_context.invalidate("ui.status")
