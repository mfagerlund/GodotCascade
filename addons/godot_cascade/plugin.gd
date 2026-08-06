@tool
extends EditorPlugin

const CASCADE_BOX_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CASCADE_STACK_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_stack.gd")
const CASCADE_GRID_SCRIPT := preload("res://addons/godot_cascade/layout/cascade_grid.gd")
const CASCADE_BUTTON_SCRIPT := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CASCADE_CHECKBOX_SCRIPT := preload("res://addons/godot_cascade/components/cascade_checkbox.gd")
const CASCADE_RADIO_BUTTON_SCRIPT := preload("res://addons/godot_cascade/components/cascade_radio_button.gd")
const CASCADE_SWITCH_SCRIPT := preload("res://addons/godot_cascade/components/cascade_switch.gd")
const CASCADE_SELECT_SCRIPT := preload("res://addons/godot_cascade/components/cascade_select.gd")
const CASCADE_LABEL_SCRIPT := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CASCADE_PANEL_SCRIPT := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CASCADE_PROGRESS_SCRIPT := preload("res://addons/godot_cascade/components/cascade_progress.gd")
const CASCADE_SLIDER_SCRIPT := preload("res://addons/godot_cascade/components/cascade_slider.gd")
const CASCADE_TEXT_INPUT_SCRIPT := preload("res://addons/godot_cascade/components/cascade_text_input.gd")
const CASCADE_TEXT_AREA_SCRIPT := preload("res://addons/godot_cascade/components/cascade_text_area.gd")
const CASCADE_IMAGE_SCRIPT := preload("res://addons/godot_cascade/components/cascade_image.gd")
const CASCADE_DOCUMENT_SCRIPT := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const GXML_IMPORTER_SCRIPT := preload("res://addons/godot_cascade/editor/gxml_importer.gd")
const GCSS_IMPORTER_SCRIPT := preload("res://addons/godot_cascade/editor/gcss_importer.gd")
const PREVIEW_DOCK_SCRIPT := preload("res://addons/godot_cascade/editor/cascade_preview_dock.gd")
const INSPECTOR_PLUGIN_SCRIPT := preload("res://addons/godot_cascade/editor/cascade_inspector_plugin.gd")

var _gxml_importer: EditorImportPlugin
var _gcss_importer: EditorImportPlugin
var _preview_dock: Control
var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_gxml_importer = GXML_IMPORTER_SCRIPT.new()
	_gcss_importer = GCSS_IMPORTER_SCRIPT.new()
	add_import_plugin(_gxml_importer)
	add_import_plugin(_gcss_importer)
	_inspector_plugin = INSPECTOR_PLUGIN_SCRIPT.new()
	add_inspector_plugin(_inspector_plugin)
	_preview_dock = PREVIEW_DOCK_SCRIPT.new()
	_preview_dock.source_requested.connect(_on_source_requested)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _preview_dock)
	add_custom_type("CascadeBox", "Container", CASCADE_BOX_SCRIPT, null)
	add_custom_type("CascadeStack", "Container", CASCADE_STACK_SCRIPT, null)
	add_custom_type("CascadeGrid", "Container", CASCADE_GRID_SCRIPT, null)
	add_custom_type("CascadeButton", "BaseButton", CASCADE_BUTTON_SCRIPT, null)
	add_custom_type("CascadeCheckbox", "BaseButton", CASCADE_CHECKBOX_SCRIPT, null)
	add_custom_type("CascadeRadioButton", "BaseButton", CASCADE_RADIO_BUTTON_SCRIPT, null)
	add_custom_type("CascadeSwitch", "BaseButton", CASCADE_SWITCH_SCRIPT, null)
	add_custom_type("CascadeSelect", "BaseButton", CASCADE_SELECT_SCRIPT, null)
	add_custom_type("CascadeLabel", "Control", CASCADE_LABEL_SCRIPT, null)
	add_custom_type("CascadePanel", "Container", CASCADE_PANEL_SCRIPT, null)
	add_custom_type("CascadeProgress", "Control", CASCADE_PROGRESS_SCRIPT, null)
	add_custom_type("CascadeSlider", "Range", CASCADE_SLIDER_SCRIPT, null)
	add_custom_type("CascadeTextInput", "LineEdit", CASCADE_TEXT_INPUT_SCRIPT, null)
	add_custom_type("CascadeTextArea", "TextEdit", CASCADE_TEXT_AREA_SCRIPT, null)
	add_custom_type("CascadeImage", "Control", CASCADE_IMAGE_SCRIPT, null)
	add_custom_type("CascadeDocument", "Control", CASCADE_DOCUMENT_SCRIPT, null)


func _exit_tree() -> void:
	remove_custom_type("CascadeTextArea")
	remove_custom_type("CascadeTextInput")
	remove_custom_type("CascadeDocument")
	remove_custom_type("CascadeImage")
	remove_custom_type("CascadeSlider")
	remove_custom_type("CascadeProgress")
	remove_custom_type("CascadePanel")
	remove_custom_type("CascadeLabel")
	remove_custom_type("CascadeSelect")
	remove_custom_type("CascadeSwitch")
	remove_custom_type("CascadeRadioButton")
	remove_custom_type("CascadeCheckbox")
	remove_custom_type("CascadeButton")
	remove_custom_type("CascadeGrid")
	remove_custom_type("CascadeStack")
	remove_custom_type("CascadeBox")
	if _preview_dock != null:
		remove_control_from_docks(_preview_dock)
		_preview_dock.queue_free()
		_preview_dock = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	if _gcss_importer != null:
		remove_import_plugin(_gcss_importer)
		_gcss_importer = null
	if _gxml_importer != null:
		remove_import_plugin(_gxml_importer)
		_gxml_importer = null


func _on_source_requested(path: String, _line: int, _column: int) -> void:
	if path.is_empty():
		return
	get_editor_interface().get_file_system_dock().navigate_to_path(path)
