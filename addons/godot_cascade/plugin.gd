@tool
extends EditorPlugin

const CASCADE_BOX_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_box.gd")


func _enter_tree() -> void:
	add_custom_type("CascadeBox", "Container", CASCADE_BOX_SCRIPT, null)


func _exit_tree() -> void:
	remove_custom_type("CascadeBox")
