@tool
extends Control

## Loads paired GXML/GCSS files and builds a native Godot Control tree.

signal diagnostics_changed(diagnostics: Array[Dictionary])

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")

@export_file("*.gxml") var markup_path := "":
	set(value):
		markup_path = value
		_request_reload()
@export_file("*.gcss") var stylesheet_path := "":
	set(value):
		stylesheet_path = value
		_request_reload()
@export var load_on_ready := true

var diagnostics: Array[Dictionary] = []
var _generated_root: Control
var _reload_queued := false


func _ready() -> void:
	if load_on_ready:
		reload_document()


func reload_document() -> bool:
	_reload_queued = false
	diagnostics = []
	_clear_generated_root()
	var markup_source := _read_source(markup_path, "GXML")
	var stylesheet_source := _read_source(stylesheet_path, "GCSS")
	if markup_source.is_empty() or stylesheet_source.is_empty():
		_publish_diagnostics()
		return false

	var markup_result := GxmlParser.parse(markup_source)
	_append_diagnostics(markup_result["diagnostics"], markup_path)
	var style_result := GcssParser.parse(stylesheet_source)
	_append_diagnostics(style_result["diagnostics"], stylesheet_path)
	if _has_errors() or markup_result["root"] == null:
		_publish_diagnostics()
		return false

	var build_result := CascadeBuilder.build(markup_result["root"], style_result["rules"])
	_append_diagnostics(build_result["diagnostics"], "builder")
	if build_result["root"] == null:
		_publish_diagnostics()
		return false

	_generated_root = build_result["root"]
	add_child(_generated_root)
	_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_publish_diagnostics()
	return not _has_errors()


func generated_root() -> Control:
	return _generated_root


func _read_source(path: String, source_kind: String) -> String:
	if path.is_empty():
		diagnostics.append(_diagnostic("error", path, "%s path is empty." % source_kind))
		return ""
	if not FileAccess.file_exists(path):
		diagnostics.append(_diagnostic("error", path, "%s file does not exist." % source_kind))
		return ""
	return FileAccess.get_file_as_string(path)


func _append_diagnostics(source_diagnostics: Array, path: String) -> void:
	for source_diagnostic in source_diagnostics:
		var diagnostic: Dictionary = source_diagnostic.duplicate()
		diagnostic["path"] = path
		diagnostics.append(diagnostic)


func _has_errors() -> bool:
	for diagnostic in diagnostics:
		if diagnostic.get("severity", "error") == "error":
			return true
	return false


func _publish_diagnostics() -> void:
	for diagnostic in diagnostics:
		var location := str(diagnostic.get("path", ""))
		if diagnostic.has("line"):
			location += ":%s:%s" % [diagnostic["line"], diagnostic.get("column", 1)]
		var rendered := "%s: %s" % [location, diagnostic.get("message", "Unknown diagnostic")]
		if diagnostic.get("severity", "error") == "warning":
			push_warning(rendered)
		else:
			push_error(rendered)
	diagnostics_changed.emit(diagnostics)


func _clear_generated_root() -> void:
	if _generated_root == null:
		return
	remove_child(_generated_root)
	_generated_root.queue_free()
	_generated_root = null


func _request_reload() -> void:
	if not is_inside_tree() or not load_on_ready or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


func _diagnostic(severity: String, path: String, message: String) -> Dictionary:
	return {"severity": severity, "path": path, "message": message}
