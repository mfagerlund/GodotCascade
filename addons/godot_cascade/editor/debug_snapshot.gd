extends RefCounted

## Read-only resolved tree snapshot shared by the editor dock and tests.

const BindingTrace := preload("res://addons/godot_cascade/runtime/binding_trace.gd")


static func capture(root: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if root != null:
		_capture_node(root, 0, result)
	return result


static func _capture_node(control: Control, depth: int, result: Array[Dictionary]) -> void:
	var style_values := {}
	if _has_property(control, "cascade_style"):
		var style: CascadeStyle = control.get("cascade_style")
		style_values = {
			"background": style.background_color.to_html(true),
			"border": style.border_color.to_html(true),
			"padding": style.padding(),
			"margin": style.margins(),
		}
	var collection := {}
	if str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		var model: Variant = control.get_meta("cascade_collection_model") if control.has_meta("cascade_collection_model") else null
		collection = {
			"model": model.get_class() if model is Object else "Array",
			"count": int(control.get_meta("cascade_virtual_model_count", control.get_meta("cascade_repeat_keys", PackedStringArray()).size())),
			"virtual": bool(control.get_meta("cascade_virtual", false)),
			"first": int(control.get_meta("cascade_virtual_first_index", 0)),
			"end": int(control.get_meta("cascade_virtual_end_index", control.get_meta("cascade_repeat_keys", PackedStringArray()).size())),
			"realized": int(control.get_meta("cascade_virtual_realized_count", control.get_meta("cascade_repeat_keys", PackedStringArray()).size())),
			"overscan": int(control.get_meta("cascade_virtual_overscan", 0)),
		}
	result.append({
		"depth": depth,
		"element": str(control.get_meta("cascade_element_type", control.get_class())),
		"id": str(control.get_meta("cascade_id", "")),
		"classes": control.get_meta("cascade_classes", PackedStringArray()),
		"key": str(control.get_meta("cascade_key", "")),
		"rect": Rect2(control.position, control.size),
		"style": style_values,
		"binding_dependencies": BindingTrace.dependencies(control),
		"binding_trace": control.get_meta(BindingTrace.TRACE_META, {}).duplicate(true),
		"document_binding_trace": control.get_meta(BindingTrace.DOCUMENT_TRACE_META, {}).duplicate(true),
		"collection": collection,
		"source_path": str(control.get_meta("cascade_source_path", "")),
		"source_line": int(control.get_meta("cascade_source_line", 1)),
		"source_column": int(control.get_meta("cascade_source_column", 1)),
	})
	for child in control.get_children():
		if child is Control:
			_capture_node(child, depth + 1, result)


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
