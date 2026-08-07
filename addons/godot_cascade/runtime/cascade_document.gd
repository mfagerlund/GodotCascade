@tool
extends Control

## Loads paired GXML/GCSS files and builds a native Godot Control tree.

signal diagnostics_changed(diagnostics: Array[Dictionary])
signal binding_value_changed(path: String, value: Variant, control: Control)
signal binding_trace_changed(trace: Dictionary)
signal validation_changed(valid: bool, diagnostics: Array[Dictionary])
signal document_reloaded(root: Control)

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeReconciler := preload("res://addons/godot_cascade/runtime/cascade_reconciler.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")
const ObservableBindingContext := preload("res://addons/godot_cascade/runtime/observable_binding_context.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")
const AccessibilityAudit := preload("res://addons/godot_cascade/runtime/accessibility_audit.gd")
const FocusManager := preload("res://addons/godot_cascade/runtime/focus_manager.gd")
const BindingTrace := preload("res://addons/godot_cascade/runtime/binding_trace.gd")

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
		_disconnect_binding_observable()
		binding_context = value
		_connect_binding_observable()
		if _generated_root != null:
			_refresh_all_bindings("context_changed")
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
var _binding_trace_sequence := 0
var _last_binding_trace: Dictionary = {}
var _active_focus_trap: Control
var _focus_before_trap: WeakRef
var _focus_redirecting := false
var _suppress_focus_contract_refresh := false


func _ready() -> void:
	set_process(watch_sources)
	resized.connect(_on_document_resized)
	if not get_viewport().gui_focus_changed.is_connected(_on_viewport_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_viewport_focus_changed)
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
	var build_result := CascadeBuilder.build(markup_result["root"], style_result["rules"], _binding_root_context(), size)
	_append_diagnostics(build_result["diagnostics"], "builder")
	if _has_errors() or build_result["root"] == null:
		if build_result["root"] != null:
			build_result["root"].free()
		_publish_diagnostics()
		return false

	var desired_root: Control = build_result["root"]
	var initial_mount := _generated_root == null
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
	BindingTrace.clear(_generated_root)
	_last_binding_trace = {}
	_suppress_focus_contract_refresh = true
	_refresh_bindings(false)
	_applying_bindings = was_applying_bindings
	_refresh_writable_bindings(false)
	_refresh_events(false)
	_suppress_focus_contract_refresh = false
	_refresh_focus_contracts(initial_mount)
	if audit_accessibility:
		for diagnostic in AccessibilityAudit.audit(_generated_root):
			var stamped: Dictionary = diagnostic.duplicate()
			stamped["path"] = markup_path
			diagnostics.append(stamped)
	document_reloaded.emit(_generated_root)
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


## Latest named/full binding refresh trace for runtime and editor tooling.
## Only the most recent trace is retained.
func last_binding_trace() -> Dictionary:
	return _last_binding_trace.duplicate(true)


## Returns the uniquely matching authored id, or null when it is absent or
## appears in more than one reusable-component scope.
func get_element_by_id(element_id: String) -> Control:
	var matches: Array[Control] = []
	_collect_elements_by_metadata(_generated_root, "cascade_id", element_id, matches)
	return matches[0] if matches.size() == 1 else null


## Returns an element by its component-qualified id, such as `audio/title`.
func get_element_by_scoped_id(scoped_id: String) -> Control:
	var matches: Array[Control] = []
	_collect_elements_by_metadata(_generated_root, "cascade_scoped_id", scoped_id, matches)
	return matches[0] if matches.size() == 1 else null


func _refresh_focus_contracts(initial_mount: bool) -> void:
	if _generated_root == null:
		return
	var previous_trap := _active_focus_trap
	var next_trap := FocusManager.active_trap(_generated_root)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if previous_trap == null and next_trap != null and focus_owner is Control and not FocusManager.contains(next_trap, focus_owner):
		_focus_before_trap = weakref(focus_owner)
	_active_focus_trap = next_trap
	FocusManager.apply_navigation(_generated_root, wrap_focus_navigation)

	if previous_trap != null and next_trap == null:
		_restore_focus_before_trap()
		return
	var newly_activated := next_trap != null and previous_trap != next_trap
	if initial_mount or newly_activated:
		var scope := next_trap if next_trap != null else _generated_root
		var target := FocusManager.autofocus_target(scope)
		if target == null and newly_activated:
			target = FocusManager.first_focusable(scope)
		if target != null:
			target.call_deferred("grab_focus")
	elif next_trap != null and (not focus_owner is Control or not FocusManager.contains(next_trap, focus_owner)):
		_redirect_focus_to_trap.call_deferred()


func _on_viewport_focus_changed(control: Control) -> void:
	if _focus_redirecting or _active_focus_trap == null or control == null:
		return
	if not FocusManager.contains(_active_focus_trap, control):
		_redirect_focus_to_trap.call_deferred()


func _redirect_focus_to_trap() -> void:
	if _active_focus_trap == null or not is_instance_valid(_active_focus_trap):
		return
	var target := FocusManager.autofocus_target(_active_focus_trap)
	if target == null:
		target = FocusManager.first_focusable(_active_focus_trap)
	if target == null:
		return
	_focus_redirecting = true
	target.grab_focus()
	_focus_redirecting = false


func _restore_focus_before_trap() -> void:
	if _focus_before_trap == null:
		return
	var target = _focus_before_trap.get_ref()
	_focus_before_trap = null
	if target is Control and is_instance_valid(target) and target.is_inside_tree() and target.visible and target.focus_mode != Control.FOCUS_NONE:
		target.call_deferred("grab_focus")


## Reapplies every {dot.separated.path} binding to the existing native tree.
## Call this after mutating binding_context; compatible controls keep identity.
func refresh_bindings() -> bool:
	return _refresh_all_bindings("manual")


## Reapplies only bindings that overlap one of the named paths.
## Parent and child paths overlap: invalidating `settings` refreshes
## `settings.profile`, and invalidating `settings.profile.name` also refreshes
## a control bound to `settings.profile`.
func refresh_binding_paths(paths: PackedStringArray) -> bool:
	return _refresh_named_bindings(paths, "manual")


func _refresh_all_bindings(trigger: String, publish: bool = true) -> bool:
	var strategy := "targeted"
	var reason := "property"
	var success: bool
	if _generated_root != null and (_contains_element(_generated_root, "repeat") or _tree_has_rebuild_binding(_generated_root)):
		strategy = "reconcile"
		reason = "collection" if _contains_element(_generated_root, "repeat") else "rebuild_dependency"
		success = reload_document()
	else:
		success = _refresh_bindings(publish)
	_record_binding_trace(PackedStringArray(["*"]), trigger, strategy, reason, success)
	return success


func _refresh_named_bindings(paths: PackedStringArray, trigger: String, publish: bool = true, reconcile_collections: bool = true) -> bool:
	var normalized := _normalized_binding_paths(paths)
	if normalized.is_empty():
		return false
	if "*" in normalized:
		return _refresh_all_bindings(trigger, publish)
	var strategy := "targeted"
	var reason := "property"
	var success: bool
	if _generated_root != null and ((reconcile_collections and _contains_element(_generated_root, "repeat")) or _tree_has_matching_rebuild_binding(_generated_root, normalized)):
		strategy = "reconcile"
		reason = "collection" if reconcile_collections and _contains_element(_generated_root, "repeat") else "rebuild_dependency"
		success = reload_document()
	else:
		success = _refresh_binding_paths(normalized, publish)
	_record_binding_trace(normalized, trigger, strategy, reason, success)
	return success


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
	if _generated_root == null or _binding_root_context() == null:
		if publish:
			_publish_diagnostics()
		return _generated_root != null
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	_apply_bindings(_generated_root)
	_applying_bindings = was_applying_bindings
	if not _suppress_focus_contract_refresh:
		_refresh_focus_contracts(false)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _refresh_binding_paths(paths: PackedStringArray, publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic):
		return diagnostic.get("path", "") != "binding" or not _binding_path_matches(str(diagnostic.get("binding_path", "")), paths)
	)
	if _generated_root == null or _binding_root_context() == null:
		if publish:
			_publish_diagnostics()
		return _generated_root != null
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	_apply_bindings(_generated_root, paths)
	_applying_bindings = was_applying_bindings
	if not _suppress_focus_contract_refresh:
		_refresh_focus_contracts(false)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_bindings(node: Node, paths: PackedStringArray = PackedStringArray()) -> void:
	if node is Control:
		var control := node as Control
		var bindings: Dictionary = control.get_meta("cascade_bindings", {})
		var range_values := {}
		var range_touched := false
		if control.has_method("set_range_values"):
			range_values = {
				"min_value": control.get("min_value"),
				"max_value": control.get("max_value"),
				"value": control.get("value"),
			}
		for property_name in bindings:
			var property_key := str(property_name)
			var binding_path := str(bindings[property_name])
			if not paths.is_empty() and not _binding_path_matches(binding_path, paths):
				continue
			if not range_values.is_empty() and property_key in ["min_value", "max_value", "value"]:
				range_touched = true
				var numeric := _resolve_numeric_binding(control, property_key, binding_path)
				if numeric["found"]:
					range_values[property_key] = numeric["value"]
			else:
				_apply_binding(control, property_key, binding_path)
		if not range_values.is_empty() and range_touched:
			control.call("set_range_values", range_values["min_value"], range_values["max_value"], range_values["value"])
	for child in node.get_children():
		_apply_bindings(child, paths)


func _apply_binding(control: Control, property_name: String, path: String) -> void:
	var result := BindingResolver.resolve(_binding_context_for(control, path), path)
	if not result["found"]:
		_append_binding_warning(control, property_name, path, result["message"])
		return
	var value: Variant = result["value"]
	if property_name in ["visible", "disabled", "button_pressed"]:
		if not value is bool:
			_append_binding_warning(control, property_name, path, "Requires a boolean value.")
			return
		control.set(property_name, value)
		return
	if property_name == "image_source" and control.has_method("set_source"):
		var error_message := str(control.call("set_source", value))
		if not error_message.is_empty():
			_append_binding_warning(control, property_name, path, error_message)
		return
	if property_name == "selected_value" and control.has_method("select_value"):
		if not control.call("select_value", value):
			_append_binding_warning(control, property_name, path, "No option '%s'." % value)
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
	var changed_paths := PackedStringArray([path])
	_refresh_named_bindings(changed_paths, "write_back", false, false)
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
		_append_binding_warning(control, property_name, path, result["message"])
		return {"found": false, "value": 0.0}
	var value: Variant = result["value"]
	if value is int or value is float:
		return {"found": true, "value": float(value)}
	var rendered := str(value)
	if rendered.is_valid_float():
		return {"found": true, "value": rendered.to_float()}
	_append_binding_warning(control, property_name, path, "Requires a number, got '%s'." % rendered)
	return {"found": false, "value": 0.0}


func _binding_context_for(control: Control, path: String) -> Variant:
	var scope: Dictionary = control.get_meta("cascade_binding_scope", {})
	var first_segment := path.get_slice(".", 0)
	return scope if scope.has(first_segment) else _binding_root_context()


func _binding_root_context() -> Variant:
	return binding_context.value if binding_context is ObservableBindingContext else binding_context


func _connect_binding_observable() -> void:
	if binding_context is ObservableBindingContext and not binding_context.paths_invalidated.is_connected(_on_binding_paths_invalidated):
		binding_context.paths_invalidated.connect(_on_binding_paths_invalidated)


func _disconnect_binding_observable() -> void:
	if binding_context is ObservableBindingContext and binding_context.paths_invalidated.is_connected(_on_binding_paths_invalidated):
		binding_context.paths_invalidated.disconnect(_on_binding_paths_invalidated)


func _on_binding_paths_invalidated(paths: PackedStringArray) -> void:
	_refresh_named_bindings(paths, "observable")


func _record_binding_trace(paths: PackedStringArray, trigger: String, strategy: String, reason: String, success: bool) -> void:
	_binding_trace_sequence += 1
	var stats := last_reconcile_stats if strategy == "reconcile" else {}
	_last_binding_trace = BindingTrace.record(
		_generated_root,
		paths,
		trigger,
		strategy,
		reason,
		_binding_trace_sequence,
		success,
		stats
	)
	binding_trace_changed.emit(_last_binding_trace.duplicate(true))


func _normalized_binding_paths(paths: PackedStringArray) -> PackedStringArray:
	var normalized := PackedStringArray()
	for path in paths:
		var candidate := path.strip_edges()
		if candidate == "*":
			return PackedStringArray(["*"])
		if not ObservableBindingContext.is_valid_path(candidate):
			continue
		if candidate not in normalized:
			normalized.append(candidate)
	return normalized


func _binding_path_matches(binding_path: String, invalidated_paths: PackedStringArray) -> bool:
	if binding_path.is_empty():
		return false
	for invalidated_path in invalidated_paths:
		if invalidated_path == "*" or binding_path == invalidated_path:
			return true
		if binding_path.begins_with(invalidated_path + ".") or invalidated_path.begins_with(binding_path + "."):
			return true
	return false


func _tree_has_rebuild_binding(node: Node) -> bool:
	if node is Control:
		var control := node as Control
		if not control.get_meta("cascade_rebuild_bindings", PackedStringArray()).is_empty():
			return true
		if not control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()).is_empty():
			return true
	for child in node.get_children():
		if _tree_has_rebuild_binding(child):
			return true
	return false


func _tree_has_matching_rebuild_binding(node: Node, paths: PackedStringArray) -> bool:
	if node is Control:
		var control := node as Control
		var rebuild_paths: PackedStringArray = control.get_meta("cascade_rebuild_bindings", PackedStringArray())
		rebuild_paths.append_array(control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()))
		for binding_path in rebuild_paths:
			if _binding_path_matches(str(binding_path), paths):
				return true
	for child in node.get_children():
		if _tree_has_matching_rebuild_binding(child, paths):
			return true
	return false


func _append_binding_warning(control: Control, property_name: String, binding_path: String, message: String) -> void:
	diagnostics.append({
		"severity": "warning",
		"path": "binding",
		"binding_path": binding_path,
		"message": "%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), message],
	})


func _refresh_events(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "event")
	if _generated_root == null:
		if publish:
			_publish_diagnostics()
		return false
	var target: Object = event_context
	if target == null and _binding_root_context() is Object:
		target = _binding_root_context()
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


func _collect_elements_by_metadata(node: Node, metadata_name: String, value: String, matches: Array[Control]) -> void:
	if node == null:
		return
	if node is Control and str(node.get_meta(metadata_name, "")) == value:
		matches.append(node)
	for child in node.get_children():
		_collect_elements_by_metadata(child, metadata_name, value, matches)


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
