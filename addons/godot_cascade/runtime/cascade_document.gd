@tool
extends Control

## Loads paired GXML/GCSS files and builds a native Godot Control tree.

signal diagnostics_changed(diagnostics: Array[Dictionary])

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeReconciler := preload("res://addons/godot_cascade/runtime/cascade_reconciler.gd")

@export_file("*.gxml") var markup_path := "":
	set(value):
		markup_path = value
		_request_reload()
@export_file("*.gcss") var stylesheet_path := "":
	set(value):
		stylesheet_path = value
		_request_reload()
@export var load_on_ready := true
@export var log_diagnostics_to_console := true
@export var watch_sources := true:
	set(value):
		watch_sources = value
		if is_inside_tree():
			set_process(watch_sources)
@export_range(0.05, 5.0, 0.05) var watch_interval := 0.25

var diagnostics: Array[Dictionary] = []
var last_reconcile_stats := {"reused": 0, "created": 0, "replaced": 0, "removed": 0}
var _generated_root: Control
var _reload_queued := false
var _watch_elapsed := 0.0
var _source_signatures := {}


func _ready() -> void:
	set_process(watch_sources)
	if load_on_ready:
		reload_document()
	else:
		_capture_source_signatures()


func _process(delta: float) -> void:
	_watch_elapsed += delta
	if _watch_elapsed < watch_interval:
		return
	_watch_elapsed = 0.0
	poll_sources()


func reload_document() -> bool:
	_reload_queued = false
	diagnostics = []
	_capture_source_signatures()
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
	if _has_errors() or build_result["root"] == null:
		_publish_diagnostics()
		return false

	var desired_root: Control = build_result["root"]
	if _generated_root == null:
		_generated_root = desired_root
		add_child(_generated_root)
		_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		last_reconcile_stats = {"reused": 0, "created": 1, "replaced": 0, "removed": 0}
	else:
		var result := CascadeReconciler.reconcile(_generated_root, desired_root)
		last_reconcile_stats = result["stats"]
		if not result["reused_root"]:
			remove_child(_generated_root)
			_generated_root.queue_free()
			_generated_root = result["root"]
			add_child(_generated_root)
			_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_publish_diagnostics()
	return true


## Checks source contents immediately and reloads when either file changed.
## The regular watcher calls this on an interval; tooling and tests may call it directly.
func poll_sources() -> bool:
	var current_signatures := _read_source_signatures()
	if current_signatures == _source_signatures:
		return false
	_source_signatures = current_signatures
	reload_document()
	return true


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
	if log_diagnostics_to_console:
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


func _request_reload() -> void:
	if not is_inside_tree() or not load_on_ready or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


func _diagnostic(severity: String, path: String, message: String) -> Dictionary:
	return {"severity": severity, "path": path, "message": message}


func _capture_source_signatures() -> void:
	_source_signatures = _read_source_signatures()


func _read_source_signatures() -> Dictionary:
	return {
		"markup": _source_signature(markup_path),
		"stylesheet": _source_signature(stylesheet_path),
	}


func _source_signature(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).hash()
