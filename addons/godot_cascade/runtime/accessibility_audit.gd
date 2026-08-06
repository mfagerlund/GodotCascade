extends RefCounted

## Accessibility validation and deterministic linear focus-neighbor wiring.


static func audit(root: Control) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_audit_node(root, diagnostics)
	return diagnostics


static func apply_linear_navigation(root: Control, wrap: bool = false) -> int:
	var focusable: Array[Control] = []
	_collect_focusable(root, focusable)
	for index in focusable.size():
		var control := focusable[index]
		var previous_index := index - 1
		var next_index := index + 1
		control.focus_previous = control.get_path_to(focusable[previous_index]) if previous_index >= 0 else (control.get_path_to(focusable[-1]) if wrap and focusable.size() > 1 else NodePath())
		control.focus_next = control.get_path_to(focusable[next_index]) if next_index < focusable.size() else (control.get_path_to(focusable[0]) if wrap and focusable.size() > 1 else NodePath())
	return focusable.size()


static func _audit_node(control: Control, diagnostics: Array[Dictionary]) -> void:
	if _requires_accessible_name(control) and str(control.get("accessibility_name")).strip_edges().is_empty():
		diagnostics.append({
			"severity": "warning",
			"message": "%s requires visible text or accessible-label." % control.get_meta("cascade_key", control.name),
			"line": int(control.get_meta("cascade_source_line", 1)),
			"column": int(control.get_meta("cascade_source_column", 1)),
		})
	if str(control.get_meta("cascade_element_type", "")).to_lower() == "image" and not control.get_meta("cascade_explicit_accessible_label", false):
		diagnostics.append({
			"severity": "warning",
			"message": "%s should provide accessible-label describing the image." % control.get_meta("cascade_key", control.name),
			"line": int(control.get_meta("cascade_source_line", 1)),
			"column": int(control.get_meta("cascade_source_column", 1)),
		})
	for child in control.get_children():
		if child is Control:
			_audit_node(child, diagnostics)


static func _requires_accessible_name(control: Control) -> bool:
	return (control is BaseButton or control is Range or control is LineEdit) and _has_property(control, "accessibility_name")


static func _collect_focusable(control: Control, result: Array[Control]) -> void:
	var disabled := (control is BaseButton and (control as BaseButton).disabled) or bool(control.get("disabled") if _has_property(control, "disabled") else false)
	if control.visible and control.focus_mode != Control.FOCUS_NONE and not disabled:
		result.append(control)
	for child in control.get_children():
		if child is Control:
			_collect_focusable(child, result)


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
