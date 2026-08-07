extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Interactive data source for the layout-foundation showcase page.

var state := {"ui": {
	"status": "Phase 1 · Layout foundation",
	"inspected": false,
	"action_classes": PackedStringArray(["actions"]),
}}


func _ready() -> void:
	binding_context = ObservableBindingContext.new(state)
	event_context = self
	super()


func _on_inspect_layout() -> void:
	state["ui"]["status"] = "Layout inspection requested"
	state["ui"]["inspected"] = true
	state["ui"]["action_classes"] = PackedStringArray(["actions", "inspected"])
	binding_context.invalidate_many(PackedStringArray([
		"ui.status",
		"ui.inspected",
		"ui.action_classes",
	]))
