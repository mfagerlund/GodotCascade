extends RefCounted

## Authored focus ordering, autofocus selection, and modal focus-scope helpers.

const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")


static func validate(root: Control, defer_bound_state: bool = false) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_validate_scope(root, diagnostics, defer_bound_state, root)
	_validate_visible_sibling_traps(root, diagnostics, defer_bound_state)
	_validate_repeat_descendant_traps(root, diagnostics)
	return diagnostics


static func apply_navigation(root: Control, wrap_document: bool = false) -> int:
	_clear_navigation(root)
	var trap := active_trap(root)
	var scope := trap if trap != null else root
	var controls := ordered_focusable(scope)
	_wire(controls, trap != null or wrap_document, trap != null)
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
	var authored: Array[Control] = []
	_collect_autofocus_in_scope(scope, scope, authored)
	for control in authored:
		# tab-index=-1 removes sequential navigation only; autofocus remains a
		# programmatic focus request.
		if _is_focus_eligible(control, scope):
			return control
	return null


static func first_focusable(scope: Control) -> Control:
	var controls := ordered_focusable(scope)
	return controls[0] if not controls.is_empty() else null


static func contains(scope: Control, control: Control) -> bool:
	return scope == control or scope.is_ancestor_of(control)


static func is_focusable_in_scope(control: Control, scope: Control) -> bool:
	return is_instance_valid(control) and contains(scope, control) and _is_focus_eligible(control, scope)


static func is_focusable_in_viewport(control: Control) -> bool:
	return is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not _is_disabled(control)


static func _validate_scope(scope: Control, diagnostics: Array[Dictionary], defer_bound_state: bool, document_root: Control) -> void:
	var autofocus_controls: Array[Control] = []
	_collect_autofocus_in_scope(scope, scope, autofocus_controls)
	if autofocus_controls.size() > 1:
		for duplicate in autofocus_controls.slice(1):
			diagnostics.append(_diagnostic(duplicate, "Only one autofocus target is allowed in a document or focus trap."))
	for target in autofocus_controls:
		var visibility_uncertain := defer_bound_state and _has_bound_visible_in_scope(target, document_root)
		var disabled_uncertain := defer_bound_state and _has_state_binding(target, "disabled")
		var dormant_trap_target := _has_inactive_focus_trap_ancestor(target, document_root)
		if target.focus_mode == Control.FOCUS_NONE or (not _is_effectively_visible_in_scope(target, document_root) and not visibility_uncertain and not dormant_trap_target) or (_is_disabled(target) and not disabled_uncertain):
			diagnostics.append(_diagnostic(target, "Autofocus requires an effectively visible, enabled, focusable native control."))
	if bool(scope.get_meta("cascade_focus_trap", false)) and _is_effectively_visible_in_scope(scope, document_root) and ordered_focusable(scope).is_empty() and not (defer_bound_state and (_scope_has_bound_focus_state(scope) or _has_bound_visible_in_scope(scope, document_root))):
		diagnostics.append(_diagnostic(scope, "A visible focus trap requires at least one focusable native control."))
	for child in scope.get_children():
		if child is Control:
			_validate_nested_traps(child, diagnostics, defer_bound_state, document_root)


static func _validate_nested_traps(control: Control, diagnostics: Array[Dictionary], defer_bound_state: bool, document_root: Control) -> void:
	if bool(control.get_meta("cascade_focus_trap", false)):
		_validate_scope(control, diagnostics, defer_bound_state, document_root)
		return
	for child in control.get_children():
		if child is Control:
			_validate_nested_traps(child, diagnostics, defer_bound_state, document_root)


static func _collect_autofocus_in_scope(control: Control, scope: Control, result: Array[Control]) -> void:
	if control != scope and bool(control.get_meta("cascade_focus_trap", false)):
		return
	if bool(control.get_meta("cascade_autofocus", false)):
		result.append(control)
	for child in control.get_children():
		if child is Control:
			_collect_autofocus_in_scope(child, scope, result)


static func _validate_visible_sibling_traps(root: Control, diagnostics: Array[Dictionary], defer_bound_state: bool) -> void:
	var traps: Array[Dictionary] = []
	_collect_visible_traps(root, traps, 0, true, defer_bound_state)
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


static func _validate_repeat_descendant_traps(control: Control, diagnostics: Array[Dictionary], inside_repeat: bool = false) -> void:
	var is_repeat := str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat"
	if inside_repeat and bool(control.get_meta("cascade_focus_trap", false)):
		diagnostics.append(_diagnostic(control, "Repeat templates cannot introduce a focus trap; put one stable trap on the Repeat or outside the collection."))
	for child in control.get_children():
		if child is Control:
			_validate_repeat_descendant_traps(child, diagnostics, inside_repeat or is_repeat)


static func _collect_visible_traps(control: Control, result: Array[Dictionary], depth: int, ancestors_visible: bool, defer_bound_state: bool = false, uncertain_visibility: bool = false) -> void:
	var effective_visible := ancestors_visible and control.visible
	var next_uncertain := uncertain_visibility or (defer_bound_state and _has_state_binding(control, "visible"))
	if effective_visible and bool(control.get_meta("cascade_focus_trap", false)) and not next_uncertain:
		result.append({"control": control, "depth": depth})
	for child in control.get_children():
		if child is Control:
			_collect_visible_traps(child, result, depth + 1, effective_visible, defer_bound_state, next_uncertain)


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
	if bool(control.get_meta("cascade_directional_navigation_owned", false)):
		var authored: Dictionary = control.get_meta("cascade_authored_directional_navigation", {})
		control.focus_neighbor_left = authored.get("left", NodePath())
		control.focus_neighbor_top = authored.get("top", NodePath())
		control.focus_neighbor_right = authored.get("right", NodePath())
		control.focus_neighbor_bottom = authored.get("bottom", NodePath())
		control.remove_meta("cascade_directional_navigation_owned")
		control.remove_meta("cascade_authored_directional_navigation")
	for child in control.get_children():
		if child is Control:
			_clear_navigation(child)


static func _wire(controls: Array[Control], wrap: bool, wire_directional_neighbors: bool) -> void:
	for index in controls.size():
		var previous := controls[index - 1] if index > 0 else (controls[-1] if wrap else null)
		var next := controls[index + 1] if index + 1 < controls.size() else (controls[0] if wrap else null)
		controls[index].focus_previous = controls[index].get_path_to(previous) if previous != null else NodePath()
		controls[index].focus_next = controls[index].get_path_to(next) if next != null else NodePath()
		if wire_directional_neighbors:
			_own_directional_navigation(controls[index])
			controls[index].focus_neighbor_left = controls[index].get_path_to(previous) if previous != null else NodePath()
			controls[index].focus_neighbor_top = controls[index].focus_neighbor_left
			controls[index].focus_neighbor_right = controls[index].get_path_to(next) if next != null else NodePath()
			controls[index].focus_neighbor_bottom = controls[index].focus_neighbor_right


static func _own_directional_navigation(control: Control) -> void:
	if bool(control.get_meta("cascade_directional_navigation_owned", false)):
		return
	control.set_meta("cascade_authored_directional_navigation", {
		"left": control.focus_neighbor_left,
		"top": control.focus_neighbor_top,
		"right": control.focus_neighbor_right,
		"bottom": control.focus_neighbor_bottom,
	})
	control.set_meta("cascade_directional_navigation_owned", true)


static func _diagnostic(control: Control, message: String) -> Dictionary:
	return {
		"severity": "error",
		"message": message,
		"line": int(control.get_meta("cascade_source_line", 1)),
		"column": int(control.get_meta("cascade_source_column", 1)),
	}


static func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)


static func _is_disabled(control: Control) -> bool:
	return (control is BaseButton and (control as BaseButton).disabled) or bool(control.get("disabled") if _has_property(control, "disabled") else false)


static func _has_state_binding(control: Control, property_name: String) -> bool:
	var bindings: Dictionary = control.get_meta("cascade_bindings", {})
	return bindings.has(property_name)


static func _scope_has_bound_focus_state(control: Control) -> bool:
	if _has_state_binding(control, "visible") or _has_state_binding(control, "disabled"):
		return true
	for child in control.get_children():
		if child is Control and _scope_has_bound_focus_state(child):
			return true
	return false


static func _is_focus_eligible(control: Control, scope: Control) -> bool:
	return control.focus_mode != Control.FOCUS_NONE and not _is_disabled(control) and _is_effectively_visible_in_scope(control, scope)


static func _is_effectively_visible_in_scope(control: Control, scope: Control) -> bool:
	var current: Node = control
	while current is Control:
		if not current.visible:
			return false
		if current == scope:
			return true
		current = current.get_parent()
	return false


static func _has_bound_visible_in_scope(control: Control, scope: Control) -> bool:
	var current: Node = control
	while current is Control:
		if _has_state_binding(current, "visible"):
			return true
		if current == scope:
			break
		current = current.get_parent()
	return false


static func _has_inactive_focus_trap_ancestor(control: Control, scope: Control) -> bool:
	var current := control.get_parent()
	while current is Control:
		if bool(current.get_meta("cascade_focus_trap", false)) and not _is_effectively_visible_in_scope(current, scope):
			return true
		if current == scope:
			break
		current = current.get_parent()
	return false
