extends RefCounted

## Authored focus ordering, autofocus selection, and modal focus-scope helpers.

const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")


static func validate(root: Control) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_validate_scope(root, diagnostics)
	_validate_visible_sibling_traps(root, diagnostics)
	return diagnostics


static func apply_navigation(root: Control, wrap_document: bool = false) -> int:
	_clear_navigation(root)
	var trap := active_trap(root)
	var scope := trap if trap != null else root
	var controls := ordered_focusable(scope)
	_wire(controls, trap != null or wrap_document)
	return controls.size()


static func ordered_focusable(scope: Control) -> Array[Control]:
	var entries: Array[Dictionary] = []
	var source_order := [0]
	_collect_focusable(scope, entries, source_order, true)
	entries.sort_custom(func(left: Dictionary, right: Dictionary):
		var left_index := int(left["tab_index"])
		var right_index := int(right["tab_index"])
		var left_group := 0 if left_index > 0 else 1
		var right_group := 0 if right_index > 0 else 1
		if left_group != right_group: return left_group < right_group
		if left_group == 0 and left_index != right_index: return left_index < right_index
		return int(left["order"]) < int(right["order"])
	)
	var result: Array[Control] = []
	for entry in entries:
		result.append(entry["control"])
	return result


static func active_trap(root: Control) -> Control:
	var traps: Array[Dictionary] = []
	_collect_visible_traps(root, traps, 0, true)
	if traps.is_empty():
		return null
	traps.sort_custom(func(left: Dictionary, right: Dictionary): return int(left["depth"]) > int(right["depth"]))
	return traps[0]["control"]


static func autofocus_target(scope: Control) -> Control:
	for control in ordered_focusable(scope):
		if bool(control.get_meta("cascade_autofocus", false)):
			return control
	return null


static func first_focusable(scope: Control) -> Control:
	var controls := ordered_focusable(scope)
	return controls[0] if not controls.is_empty() else null


static func contains(scope: Control, control: Control) -> bool:
	return scope == control or scope.is_ancestor_of(control)


static func _validate_scope(scope: Control, diagnostics: Array[Dictionary]) -> void:
	var autofocus_controls: Array[Control] = []
	_collect_autofocus_in_scope(scope, scope, autofocus_controls)
	if autofocus_controls.size() > 1:
		for duplicate in autofocus_controls.slice(1):
			diagnostics.append(_diagnostic(duplicate, "Only one autofocus target is allowed in a document or focus trap."))
	for target in autofocus_controls:
		if target.focus_mode == Control.FOCUS_NONE:
			diagnostics.append(_diagnostic(target, "Autofocus requires a focusable native control."))
	for child in scope.get_children():
		if child is Control:
			_validate_nested_traps(child, diagnostics)


static func _validate_nested_traps(control: Control, diagnostics: Array[Dictionary]) -> void:
	if bool(control.get_meta("cascade_focus_trap", false)):
		_validate_scope(control, diagnostics)
		return
	for child in control.get_children():
		if child is Control:
			_validate_nested_traps(child, diagnostics)


static func _collect_autofocus_in_scope(control: Control, scope: Control, result: Array[Control]) -> void:
	if control != scope and bool(control.get_meta("cascade_focus_trap", false)):
		return
	if bool(control.get_meta("cascade_autofocus", false)):
		result.append(control)
	for child in control.get_children():
		if child is Control:
			_collect_autofocus_in_scope(child, scope, result)


static func _validate_visible_sibling_traps(root: Control, diagnostics: Array[Dictionary]) -> void:
	var traps: Array[Dictionary] = []
	_collect_visible_traps(root, traps, 0, true)
	var by_parent := {}
	for entry in traps:
		var trap: Control = entry["control"]
		var parent_scope: Control = _nearest_parent_trap(trap, root)
		var key := parent_scope.get_instance_id()
		if not by_parent.has(key): by_parent[key] = []
		by_parent[key].append(trap)
	for siblings in by_parent.values():
		if siblings.size() > 1:
			for duplicate in siblings.slice(1):
				diagnostics.append(_diagnostic(duplicate, "Only one sibling focus trap may be visible at a time."))


static func _nearest_parent_trap(control: Control, root: Control) -> Control:
	var parent := control.get_parent()
	while parent is Control:
		if bool(parent.get_meta("cascade_focus_trap", false)):
			return parent
		parent = parent.get_parent()
	return root


static func _collect_visible_traps(control: Control, result: Array[Dictionary], depth: int, ancestors_visible: bool) -> void:
	var effective_visible := ancestors_visible and control.visible
	if effective_visible and bool(control.get_meta("cascade_focus_trap", false)):
		result.append({"control": control, "depth": depth})
	for child in control.get_children():
		if child is Control:
			_collect_visible_traps(child, result, depth + 1, effective_visible)


static func _collect_focusable(control: Control, result: Array[Dictionary], source_order: Array, ancestors_visible: bool) -> void:
	var effective_visible := ancestors_visible and control.visible
	var disabled := (control is BaseButton and (control as BaseButton).disabled) or bool(control.get("disabled") if _has_property(control, "disabled") else false)
	var tab_index := int(control.get_meta("cascade_tab_index", 0))
	if effective_visible and control.focus_mode != Control.FOCUS_NONE and not disabled and tab_index >= 0:
		result.append({"control": control, "tab_index": tab_index, "order": source_order[0]})
		source_order[0] = int(source_order[0]) + 1
	for child in control.get_children():
		if child is Control:
			_collect_focusable(child, result, source_order, effective_visible)


static func _clear_navigation(control: Control) -> void:
	control.focus_previous = NodePath()
	control.focus_next = NodePath()
	for child in control.get_children():
		if child is Control:
			_clear_navigation(child)


static func _wire(controls: Array[Control], wrap: bool) -> void:
	for index in controls.size():
		var previous := controls[index - 1] if index > 0 else (controls[-1] if wrap and controls.size() > 1 else null)
		var next := controls[index + 1] if index + 1 < controls.size() else (controls[0] if wrap and controls.size() > 1 else null)
		controls[index].focus_previous = controls[index].get_path_to(previous) if previous != null else NodePath()
		controls[index].focus_next = controls[index].get_path_to(next) if next != null else NodePath()


static func _diagnostic(control: Control, message: String) -> Dictionary:
	return {
		"severity": "error",
		"message": message,
		"line": int(control.get_meta("cascade_source_line", 1)),
		"column": int(control.get_meta("cascade_source_column", 1)),
	}


static func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)
