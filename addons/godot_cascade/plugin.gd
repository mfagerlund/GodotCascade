@tool
extends EditorPlugin

const CASCADE_BOX_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CASCADE_BUTTON_SCRIPT := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CASCADE_LABEL_SCRIPT := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CASCADE_PANEL_SCRIPT := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CASCADE_PROGRESS_SCRIPT := preload("res://addons/godot_cascade/components/cascade_progress.gd")
const CASCADE_DOCUMENT_SCRIPT := preload("res://addons/godot_cascade/runtime/cascade_document.gd")


func _enter_tree() -> void:
	add_custom_type("CascadeBox", "Container", CASCADE_BOX_SCRIPT, null)
	add_custom_type("CascadeButton", "BaseButton", CASCADE_BUTTON_SCRIPT, null)
	add_custom_type("CascadeLabel", "Control", CASCADE_LABEL_SCRIPT, null)
	add_custom_type("CascadePanel", "Container", CASCADE_PANEL_SCRIPT, null)
	add_custom_type("CascadeProgress", "Control", CASCADE_PROGRESS_SCRIPT, null)
	add_custom_type("CascadeDocument", "Control", CASCADE_DOCUMENT_SCRIPT, null)


func _exit_tree() -> void:
	remove_custom_type("CascadeDocument")
	remove_custom_type("CascadeProgress")
	remove_custom_type("CascadePanel")
	remove_custom_type("CascadeLabel")
	remove_custom_type("CascadeButton")
	remove_custom_type("CascadeBox")
