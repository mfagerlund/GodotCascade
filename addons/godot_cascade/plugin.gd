@tool
extends EditorPlugin

const CASCADE_BOX_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CASCADE_BUTTON_SCRIPT := preload("res://addons/godot_cascade/components/cascade_button.gd")


func _enter_tree() -> void:
	add_custom_type("CascadeBox", "Container", CASCADE_BOX_SCRIPT, null)
	add_custom_type("CascadeButton", "BaseButton", CASCADE_BUTTON_SCRIPT, null)


func _exit_tree() -> void:
	remove_custom_type("CascadeButton")
	remove_custom_type("CascadeBox")
