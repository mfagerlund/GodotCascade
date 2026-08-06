@tool
extends Control

## Loads paired GXML/GCSS files and builds a native Godot Control tree.

signal diagnostics_changed(diagnostics: Array[Dictionary])
signal binding_value_changed(path: String, value: Variant, control: Control)
signal validation_changed(valid: bool, diagnostics: Array[Dictionary])

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeReconciler := preload("res://addons/godot_cascade/runtime/cascade_reconciler.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")
const AccessibilityAudit := preload("res://addons/godot_cascade/runtime/accessibility_audit.gd")

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
@export var audit_accessibility := true
@export var wrap_focus_navigation := false

var diagnostics: Array[Dictionary] = []
var last_reconcile_stats := {"reused": 0, "created": 0, "replaced": 0, "removed": 0}
var binding_context: Variant:
	set(value):
		binding_context = value
		if _generated_root != null:
			refresh_bindings()
var event_context: Object:
	set(value):
		event_context = value
		if _generated_root != null:
			refresh_events()
var _generated_root: Control
var _reload_queued := false
var _watch_elapsed := 0.0
var _source_signatures := {}
var _published_diagnostic_keys := {}
var _last_build_size := Vector2.ZERO
var _applying_bindings := false


func _ready() -> void:
	set_process(watch_sources)
	resized.connect(_on_document_resized)
	if load_on_ready:
		reload_document()
	else:
		_capture_source_signatures()


func _exit_tree() -> void:
	if _generated_root != null:
		ComponentRegistry.unmount_tree(_generated_root)


func _process(delta: float) -> void:
	_watch_elapsed += delta
	if _watch_elapsed < watch_interval:
		return
	_watch_elapsed = 0.0
	poll_sources()


func _on_document_resized() -> void:
	if _generated_root == null or size.x <= 0.0 or size.is_equal_approx(_last_build_size) or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


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

	_last_build_size = size
	var build_result := CascadeBuilder.build(markup_result["root"], style_result["rules"], binding_context, size)
	_append_diagnostics(build_result["diagnostics"], "builder")
	if _has_errors() or build_result["root"] == null:
		_publish_diagnostics()
		return false

	var desired_root: Control = build_result["root"]
	_stamp_source_path(desired_root)
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	if _generated_root == null:
		_generated_root = desired_root
		add_child(_generated_root)
		_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ComponentRegistry.mount_tree(_generated_root)
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
			ComponentRegistry.mount_tree(_generated_root)
	_refresh_bindings(false)
	_applying_bindings = was_applying_bindings
	_refresh_writable_bindings(false)
	_refresh_events(false)
	AccessibilityAudit.apply_linear_navigation(_generated_root, wrap_focus_navigation)
	if audit_accessibility:
		for diagnostic in AccessibilityAudit.audit(_generated_root):
			var stamped: Dictionary = diagnostic.duplicate()
			stamped["path"] = markup_path
			diagnostics.append(stamped)
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


## Reapplies every {dot.separated.path} binding to the existing native tree.
## Call this after mutating binding_context; compatible controls keep identity.
func refresh_bindings() -> bool:
	if _generated_root != null and _contains_element(_generated_root, "repeat"):
		return reload_document()
	return _refresh_bindings(true)


## Reconnects authored on-* signal bindings without disturbing user connections.
func refresh_events() -> bool:
	return _refresh_events(true)


## Validates generated controls and publishes source-aware validation diagnostics.
func validate() -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "validation")
	if _generated_root != null:
		_validate_node(_generated_root)
	var valid := not diagnostics.any(func(diagnostic): return diagnostic.get("path", "") == "validation")
	validation_changed.emit(valid, diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") == "validation"))
	_publish_diagnostics()
	return valid


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
	var current_keys := {}
	if log_diagnostics_to_console:
		for diagnostic in diagnostics:
			var diagnostic_key := JSON.stringify(diagnostic)
			current_keys[diagnostic_key] = true
			if _published_diagnostic_keys.has(diagnostic_key):
				continue
			var location := str(diagnostic.get("path", ""))
			if diagnostic.has("line"):
				location += ":%s:%s" % [diagnostic["line"], diagnostic.get("column", 1)]
			var rendered := "%s: %s" % [location, diagnostic.get("message", "Unknown diagnostic")]
			if diagnostic.get("severity", "error") == "warning":
				push_warning(rendered)
			else:
				push_error(rendered)
	_published_diagnostic_keys = current_keys
	diagnostics_changed.emit(diagnostics)


func _request_reload() -> void:
	if not is_inside_tree() or not load_on_ready or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


func _diagnostic(severity: String, path: String, message: String) -> Dictionary:
	return {"severity": severity, "path": path, "message": message}


func _refresh_bindings(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "binding")
	if _generated_root == null or binding_context == null:
		if publish:
			_publish_diagnostics()
		return _generated_root != null
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	_apply_bindings(_generated_root)
	_applying_bindings = was_applying_bindings
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_bindings(node: Node) -> void:
	if node is Control:
		var control := node as Control
		var bindings: Dictionary = control.get_meta("cascade_bindings", {})
		var range_values := {}
		if control.has_method("set_range_values"):
			range_values = {
				"min_value": control.get("min_value"),
				"max_value": control.get("max_value"),
				"value": control.get("value"),
			}
		for property_name in bindings:
			var property_key := str(property_name)
			if not range_values.is_empty() and property_key in ["min_value", "max_value", "value"]:
				var numeric := _resolve_numeric_binding(control, property_key, str(bindings[property_name]))
				if numeric["found"]:
					range_values[property_key] = numeric["value"]
			else:
				_apply_binding(control, property_key, str(bindings[property_name]))
		if not range_values.is_empty():
			control.call("set_range_values", range_values["min_value"], range_values["max_value"], range_values["value"])
	for child in node.get_children():
		_apply_bindings(child)


func _apply_binding(control: Control, property_name: String, path: String) -> void:
	var result := BindingResolver.resolve(_binding_context_for(control, path), path)
	if not result["found"]:
		diagnostics.append(_diagnostic(
			"warning",
			"binding",
			"%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), result["message"]]
		))
		return
	var value: Variant = result["value"]
	if property_name == "selected_value" and control.has_method("select_value"):
		if not control.call("select_value", value):
			diagnostics.append(_diagnostic("warning", "binding", "selected_value on %s has no option '%s'." % [control.get_meta("cascade_key", control.name), value]))
		return
	if property_name == "text":
		var rendered := str(value)
		if str(control.get(property_name)) != rendered:
			control.set(property_name, rendered)
		if control.has_method("validate"):
			control.call("validate")
		return
	if property_name in ["min_value", "max_value", "value"]:
		var numeric := _resolve_numeric_binding(control, property_name, path)
		if numeric["found"]:
			control.set(property_name, numeric["value"])
		return
	control.set(property_name, value)


func _refresh_writable_bindings(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "writable-binding")
	if _generated_root == null:
		if publish:
			_publish_diagnostics()
		return false
	_apply_writable_bindings(_generated_root)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_writable_bindings(node: Node) -> void:
	if node is Control:
		var control := node as Control
		var previous: Array = control.get_meta("cascade_writable_connections", [])
		for connection in previous:
			var signal_name := StringName(connection["signal"])
			var callback: Callable = connection["callable"]
			if control.has_signal(signal_name) and control.is_connected(signal_name, callback):
				control.disconnect(signal_name, callback)
		var connected: Array[Dictionary] = []
		var bindings: Dictionary = control.get_meta("cascade_writable_bindings", {})
		for property_name in bindings:
			var definition: Dictionary = bindings[property_name]
			var signal_name := StringName(definition["signal"])
			var path := str(definition["path"])
			var callback: Callable
			if signal_name == &"selection_changed":
				callback = _on_writable_selection_changed.bind(control, path)
			elif bool(definition.get("read_property", false)):
				callback = _on_writable_property_changed.bind(control, str(property_name), path)
			else:
				callback = _on_writable_value_changed.bind(control, str(property_name), path)
			var error := control.connect(signal_name, callback)
			if error != OK:
				diagnostics.append(_diagnostic("warning", "writable-binding", "%s on %s could not observe native changes (error %s)." % [property_name, control.get_meta("cascade_key", control.name), error]))
				continue
			connected.append({"signal": signal_name, "callable": callback})
		control.set_meta("cascade_writable_connections", connected)
	for child in node.get_children():
		_apply_writable_bindings(child)


func _on_writable_value_changed(value: Variant, control: Control, property_name: String, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, property_name, path, value)


func _on_writable_property_changed(control: Control, property_name: String, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, property_name, path, control.get(property_name))


func _on_writable_selection_changed(value: String, _index: int, control: Control, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, "selected_value", path, value)


func _write_binding(control: Control, property_name: String, path: String, value: Variant) -> void:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "writable-binding")
	var result := BindingResolver.assign(_binding_context_for(control, path), path, value)
	if not result["written"]:
		diagnostics.append(_diagnostic("warning", "writable-binding", "%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), result["message"]]))
		_publish_diagnostics()
		return
	binding_value_changed.emit(path, value, control)
	_refresh_bindings(false)
	_publish_diagnostics()


func _validate_node(control: Control) -> void:
	if control.has_method("validate") and not control.call("validate"):
		diagnostics.append({
			"severity": "warning",
			"path": "validation",
			"message": "%s: %s" % [control.get_meta("cascade_key", control.name), control.call("current_validation_message")],
			"line": int(control.get_meta("cascade_source_line", 1)),
			"column": int(control.get_meta("cascade_source_column", 1)),
		})
	for child in control.get_children():
		if child is Control:
			_validate_node(child)


func _resolve_numeric_binding(control: Control, property_name: String, path: String) -> Dictionary:
	var result := BindingResolver.resolve(_binding_context_for(control, path), path)
	if not result["found"]:
		diagnostics.append(_diagnostic(
			"warning",
			"binding",
			"%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), result["message"]]
		))
		return {"found": false, "value": 0.0}
	var value: Variant = result["value"]
	if value is int or value is float:
		return {"found": true, "value": float(value)}
	var rendered := str(value)
	if rendered.is_valid_float():
		return {"found": true, "value": rendered.to_float()}
	diagnostics.append(_diagnostic(
		"warning",
		"binding",
		"%s on %s requires a number, got '%s'." % [property_name, control.get_meta("cascade_key", control.name), rendered]
	))
	return {"found": false, "value": 0.0}


func _binding_context_for(control: Control, path: String) -> Variant:
	var scope: Dictionary = control.get_meta("cascade_binding_scope", {})
	var first_segment := path.get_slice(".", 0)
	return scope if scope.has(first_segment) else binding_context


func _refresh_events(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "event")
	if _generated_root == null:
		if publish:
			_publish_diagnostics()
		return false
	var target: Object = event_context
	if target == null and binding_context is Object:
		target = binding_context
	if target == null:
		target = self
	_apply_events(_generated_root, target)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_events(node: Node, target: Object) -> void:
	if node is Control:
		var control := node as Control
		var previous: Array = control.get_meta("cascade_event_connections", [])
		for connection in previous:
			var signal_name := StringName(connection["signal"])
			var callback: Callable = connection["callable"]
			if control.has_signal(signal_name) and control.is_connected(signal_name, callback):
				control.disconnect(signal_name, callback)
		var connected: Array[Dictionary] = []
		var events: Dictionary = control.get_meta("cascade_events", {})
		for signal_value in events:
			var method_name := str(events[signal_value])
			if not target.has_method(method_name):
				diagnostics.append(_diagnostic("warning", "event", "%s on %s: target has no method '%s'." % [signal_value, control.get_meta("cascade_key", control.name), method_name]))
				continue
			var signal_name := StringName(signal_value)
			var callback := Callable(target, method_name)
			var error := control.connect(signal_name, callback)
			if error != OK:
				diagnostics.append(_diagnostic("warning", "event", "%s on %s could not connect method '%s' (error %s)." % [signal_value, control.get_meta("cascade_key", control.name), method_name, error]))
				continue
			connected.append({"signal": signal_name, "callable": callback})
		control.set_meta("cascade_event_connections", connected)
	for child in node.get_children():
		_apply_events(child, target)


func _contains_element(node: Node, element_type: String) -> bool:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == element_type:
		return true
	for child in node.get_children():
		if _contains_element(child, element_type):
			return true
	return false


func _stamp_source_path(node: Node) -> void:
	if node is Control:
		node.set_meta("cascade_source_path", markup_path)
	for child in node.get_children():
		_stamp_source_path(child)


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
