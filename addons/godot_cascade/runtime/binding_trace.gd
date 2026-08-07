extends RefCounted

## Builds read-only binding dependency and latest-invalidation trace data for tooling.

const TRACE_META := "cascade_binding_trace"
const DOCUMENT_TRACE_META := "cascade_document_binding_trace"


static func dependencies(control: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	var writable: Dictionary = control.get_meta("cascade_writable_bindings", {})
	var bindings: Dictionary = control.get_meta("cascade_bindings", {})
	var binding_properties: Array = bindings.keys()
	binding_properties.sort_custom(func(left, right): return str(left) < str(right))
	for property_name in binding_properties:
		var path := str(bindings[property_name])
		var mode := "two-way" if writable.has(property_name) else "one-way"
		_append_dependency(result, seen, str(property_name), path, mode)

	for path in control.get_meta("cascade_rebuild_bindings", PackedStringArray()):
		_append_dependency(result, seen, "class", str(path), "reconcile")
	var condition_path := str(control.get_meta("cascade_condition_binding", ""))
	if not condition_path.is_empty():
		_append_dependency(result, seen, "if", condition_path, "reconcile")
	var collection_path := str(control.get_meta("cascade_collection_binding", ""))
	if not collection_path.is_empty():
		_append_dependency(result, seen, "items", collection_path, "collection")
	for path in control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()):
		_append_dependency(result, seen, "branch", str(path), "reconcile")
	return result


static func record(
	root: Control,
	paths: PackedStringArray,
	trigger: String,
	strategy: String,
	reason: String,
	sequence: int,
	success: bool,
	reconcile_stats: Dictionary = {}
) -> Dictionary:
	var affected_controls: Array[String] = []
	var affected_bindings := 0
	if root != null:
		var totals := _record_node(root, paths, trigger, strategy, reason, sequence, affected_controls)
		affected_bindings = totals
	var trace := {
		"sequence": sequence,
		"trigger": trigger,
		"strategy": strategy,
		"reason": reason,
		"paths": paths,
		"affected_controls": affected_controls,
		"affected_bindings": affected_bindings,
		"success": success,
		"reconcile_stats": reconcile_stats.duplicate(true),
	}
	if root != null:
		root.set_meta(DOCUMENT_TRACE_META, trace)
	return trace


## Records a trace from a retained dependency index. The caller supplies the
## entries whose paths overlap this invalidation and the controls stamped by the
## previous trace, avoiding an otherwise complete native-tree traversal.
static func record_indexed(
	root: Control,
	paths: PackedStringArray,
	trigger: String,
	strategy: String,
	reason: String,
	sequence: int,
	success: bool,
	matching_entries: Array[Dictionary],
	previous_controls: Array[Control],
	reconcile_stats: Dictionary = {}
) -> Dictionary:
	for control in previous_controls:
		if is_instance_valid(control) and control.has_meta(TRACE_META):
			control.remove_meta(TRACE_META)

	var grouped: Dictionary = {}
	var ordered_controls: Array[Control] = []
	for entry in matching_entries:
		var control: Variant = entry.get("control")
		var dependency: Variant = entry.get("dependency")
		if not control is Control or not is_instance_valid(control) or not dependency is Dictionary:
			continue
		var instance_id: int = control.get_instance_id()
		if not grouped.has(instance_id):
			grouped[instance_id] = []
			ordered_controls.append(control)
		grouped[instance_id].append(dependency.duplicate(true))

	var affected_controls: Array[String] = []
	var affected_bindings := 0
	for control in ordered_controls:
		var matches: Array = grouped[control.get_instance_id()]
		control.set_meta(TRACE_META, {
			"sequence": sequence,
			"trigger": trigger,
			"strategy": strategy,
			"reason": reason,
			"paths": paths,
			"matches": matches,
		})
		affected_controls.append(_control_identity(control))
		affected_bindings += matches.size()

	var trace := {
		"sequence": sequence,
		"trigger": trigger,
		"strategy": strategy,
		"reason": reason,
		"paths": paths,
		"affected_controls": affected_controls,
		"affected_bindings": affected_bindings,
		"success": success,
		"reconcile_stats": reconcile_stats.duplicate(true),
	}
	if root != null:
		root.set_meta(DOCUMENT_TRACE_META, trace)
	return {"trace": trace, "controls": ordered_controls}


static func clear(root: Control) -> void:
	if root == null:
		return
	if root.has_meta(DOCUMENT_TRACE_META):
		root.remove_meta(DOCUMENT_TRACE_META)
	_clear_node(root)


static func _record_node(
	control: Control,
	paths: PackedStringArray,
	trigger: String,
	strategy: String,
	reason: String,
	sequence: int,
	affected_controls: Array[String]
) -> int:
	var matches: Array[Dictionary] = []
	for dependency in dependencies(control):
		if _path_matches(str(dependency["path"]), paths):
			matches.append(dependency.duplicate(true))
	if matches.is_empty():
		if control.has_meta(TRACE_META):
			control.remove_meta(TRACE_META)
	else:
		control.set_meta(TRACE_META, {
			"sequence": sequence,
			"trigger": trigger,
			"strategy": strategy,
			"reason": reason,
			"paths": paths,
			"matches": matches,
		})
		affected_controls.append(_control_identity(control))
	var total := matches.size()
	for child in control.get_children():
		if child is Control:
			total += _record_node(child, paths, trigger, strategy, reason, sequence, affected_controls)
	return total


static func _clear_node(control: Control) -> void:
	if control.has_meta(TRACE_META):
		control.remove_meta(TRACE_META)
	for child in control.get_children():
		if child is Control:
			_clear_node(child)


static func _append_dependency(result: Array[Dictionary], seen: Dictionary, property_name: String, path: String, mode: String) -> void:
	if path.is_empty():
		return
	var key := "%s|%s|%s" % [property_name, path, mode]
	if seen.has(key):
		return
	seen[key] = true
	result.append({"property": property_name, "path": path, "mode": mode})


static func _path_matches(binding_path: String, invalidated_paths: PackedStringArray) -> bool:
	for invalidated_path in invalidated_paths:
		if invalidated_path == "*" or binding_path == invalidated_path:
			return true
		if binding_path.begins_with(invalidated_path + ".") or invalidated_path.begins_with(binding_path + "."):
			return true
	return false


static func _control_identity(control: Control) -> String:
	var scoped_id := str(control.get_meta("cascade_scoped_id", ""))
	var key := str(control.get_meta("cascade_key", control.name))
	if "repeat:" in key:
		return key
	return scoped_id if not scoped_id.is_empty() else key
