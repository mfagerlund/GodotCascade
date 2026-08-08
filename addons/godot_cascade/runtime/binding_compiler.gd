extends RefCounted

## Compiles declarative one-way, writable, and event bindings into control metadata.

const BindingPath := preload("res://addons/godot_cascade/runtime/binding_path.gd")

const WRITABLE_TARGETS := {
	"bind-text": {"property": "text", "signal": "text_changed", "types": ["textinput"]},
	"bind-checked": {"property": "button_pressed", "signal": "toggled", "types": ["checkbox", "switch", "radiobutton", "radio"]},
	"bind-value": {"property": "value", "signal": "value_changed", "types": ["slider"]},
	"bind-selected": {"property": "selected_value", "signal": "selection_changed", "types": ["select"]},
}


static func apply_writable_attributes(control: Control, attributes: Dictionary, diagnostics: Array[Dictionary]) -> void:
	var element_type := str(control.get_meta("cascade_element_type", "")).to_lower()
	for attribute_name in attributes:
		var normalized_name := str(attribute_name).to_lower()
		if not normalized_name.begins_with("bind-"):
			continue
		if not WRITABLE_TARGETS.has(normalized_name):
			_append_error(diagnostics, "Unsupported writable binding attribute '%s'." % attribute_name)
			continue
		var definition: Dictionary = WRITABLE_TARGETS[normalized_name]
		if element_type not in definition["types"]:
			_append_error(diagnostics, "Writable binding '%s' is not supported on <%s>." % [attribute_name, control.get_meta("cascade_element_type", control.get_class())])
			continue
		var raw_value := str(attributes[attribute_name])
		if raw_value.begins_with("@"):
			continue
		var path := binding_path(raw_value)
		if path.is_empty():
			_append_error(diagnostics, "Writable binding '%s' requires an exact {dot.separated.path}." % attribute_name)
			continue
		var binding_scope: Dictionary = control.get_meta("cascade_binding_scope", {})
		var first_segment := path.get_slice(".", 0)
		if binding_scope.has(first_segment) and (first_segment == "index" or path == "item"):
			_append_error(diagnostics, "Writable bindings in Repeat must target an existing item property through '{item.path}'; index and whole-item replacement are read-only.")
			continue
		var property_name := str(definition["property"])
		var bindings: Dictionary = control.get_meta("cascade_bindings", {})
		bindings[property_name] = path
		control.set_meta("cascade_bindings", bindings)
		var writable: Dictionary = control.get_meta("cascade_writable_bindings", {})
		writable[property_name] = {
			"path": path,
			"signal": definition["signal"],
			"read_property": control is TextEdit,
		}
		control.set_meta("cascade_writable_bindings", writable)


static func apply_event_attributes(control: Control, attributes: Dictionary, diagnostics: Array[Dictionary]) -> void:
	var events: Dictionary = control.get_meta("cascade_events", {})
	for attribute_name in attributes:
		var normalized_name := str(attribute_name).to_lower()
		if not normalized_name.begins_with("on-"):
			continue
		var signal_name := normalized_name.trim_prefix("on-").replace("-", "_")
		var method_name := str(attributes[attribute_name]).strip_edges()
		if signal_name.is_empty() or not control.has_signal(signal_name):
			_append_error(diagnostics, "Event attribute '%s' does not name a signal on <%s>." % [attribute_name, control.get_meta("cascade_element_type", control.get_class())])
			continue
		if not _is_method_name(method_name):
			_append_error(diagnostics, "Event attribute '%s' requires a method name, got '%s'." % [attribute_name, method_name])
			continue
		events[signal_name] = method_name
	control.set_meta("cascade_events", events)


static func record_one_way(control: Control, property_name: String, raw_value: String) -> bool:
	var path := binding_path(raw_value)
	if path.is_empty():
		return false
	var bindings: Dictionary = control.get_meta("cascade_bindings", {})
	bindings[property_name] = path
	control.set_meta("cascade_bindings", bindings)
	return true


static func binding_path(raw_value: String) -> String:
	var normalized := raw_value.strip_edges()
	if normalized.length() < 3 or not normalized.begins_with("{") or not normalized.ends_with("}"):
		return ""
	return BindingPath.normalize(normalized.substr(1, normalized.length() - 2))


static func has_binding_syntax(raw_value: String) -> bool:
	var normalized := raw_value.strip_edges()
	return normalized.begins_with("{") and normalized.ends_with("}")


static func has_invalid_binding_syntax(raw_value: String) -> bool:
	return has_binding_syntax(raw_value) and binding_path(raw_value).is_empty()


static func _is_method_name(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var character := value[index]
		var lowered := character.to_lower()
		var valid_letter := lowered >= "a" and lowered <= "z"
		var valid_digit := index > 0 and character >= "0" and character <= "9"
		if not valid_letter and not valid_digit and character != "_":
			return false
	return true


static func _append_error(diagnostics: Array[Dictionary], message: String) -> void:
	diagnostics.append({"severity": "error", "message": message})
