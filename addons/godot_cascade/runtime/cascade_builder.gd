extends RefCounted

## Converts parsed GodotCascade elements and rules into native Control nodes.

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CascadeLabel := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CascadeCheckbox := preload("res://addons/godot_cascade/components/cascade_checkbox.gd")
const CascadeRadioButton := preload("res://addons/godot_cascade/components/cascade_radio_button.gd")
const CascadeSwitch := preload("res://addons/godot_cascade/components/cascade_switch.gd")
const CascadeProgress := preload("res://addons/godot_cascade/components/cascade_progress.gd")


static func build(root_element, rules: Array) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var button_groups: Dictionary = {}
	var root_control := _build_element(root_element, rules, diagnostics, "0", button_groups)
	return {"root": root_control, "diagnostics": diagnostics}


static func _build_element(
	element,
	rules: Array,
	diagnostics: Array[Dictionary],
	key_path: String,
	button_groups: Dictionary
) -> Control:
	var control := _create_control(element.tag_name, diagnostics)
	if control == null:
		return null

	control.name = element.element_id() if not element.element_id().is_empty() else element.tag_name
	control.set_meta("cascade_element_type", element.tag_name)
	control.set_meta("cascade_id", element.element_id())
	control.set_meta("cascade_classes", element.classes())
	control.set_meta("cascade_key", "#" + element.element_id() if not element.element_id().is_empty() else key_path)
	control.set_meta("cascade_bindings", {})

	_apply_attributes(control, element.attributes, element.text, diagnostics, button_groups)
	if element.tag_name.to_lower() == "row":
		control.direction = CascadeBox.FlowDirection.ROW

	var computed := _compute_declarations(element, rules)
	_apply_declarations(control, computed, diagnostics)

	for index in element.children.size():
		var child_element = element.children[index]
		var child_key := "%s/%s:%s" % [key_path, index, child_element.tag_name]
		var child_control := _build_element(child_element, rules, diagnostics, child_key, button_groups)
		if child_control != null:
			control.add_child(child_control)
	return control


static func _create_control(tag_name: String, diagnostics: Array[Dictionary]) -> Control:
	match tag_name.to_lower():
		"page", "row", "column":
			return CascadeBox.new()
		"panel":
			return CascadePanel.new()
		"label":
			return CascadeLabel.new()
		"button":
			return CascadeButton.new()
		"checkbox":
			return CascadeCheckbox.new()
		"radiobutton", "radio":
			return CascadeRadioButton.new()
		"switch":
			return CascadeSwitch.new()
		"progress":
			return CascadeProgress.new()
		_:
			diagnostics.append(_diagnostic(
				"error",
				"Unknown GXML element <%s>. Register a native control factory before using it." % tag_name
			))
			return null


static func _compute_declarations(element, rules: Array) -> Dictionary:
	var winners := {}
	for rule in rules:
		if not rule.matches(element):
			continue
		var state: String = rule.pseudo_state
		if not winners.has(state):
			winners[state] = {}
		var declarations := _expand_shorthands(rule.declarations)
		for property_name in declarations:
			var existing: Dictionary = winners[state].get(property_name, {})
			if existing.is_empty() or rule.specificity > existing["specificity"] or (
				rule.specificity == existing["specificity"] and rule.order >= existing["order"]
			):
				winners[state][property_name] = {
					"value": declarations[property_name],
					"specificity": rule.specificity,
					"order": rule.order,
					"line": rule.line,
				}
	return winners


static func _expand_shorthands(declarations: Dictionary) -> Dictionary:
	var expanded := {}
	for property_name in declarations:
		var value: String = str(declarations[property_name])
		if property_name in ["padding", "margin"]:
			var tokens := _split_whitespace(value)
			var valid_lengths := tokens.size() >= 1 and tokens.size() <= 4
			for token in tokens:
				var parsed := _parse_length(token)
				valid_lengths = valid_lengths and not is_nan(parsed) and parsed >= 0.0
			if not valid_lengths:
				expanded[property_name] = value
				continue
			var top := tokens[0]
			var right := tokens[0] if tokens.size() == 1 else tokens[1]
			var bottom := tokens[0] if tokens.size() < 3 else tokens[2]
			var left := right if tokens.size() < 4 else tokens[3]
			expanded["%s-top" % property_name] = top
			expanded["%s-right" % property_name] = right
			expanded["%s-bottom" % property_name] = bottom
			expanded["%s-left" % property_name] = left
		elif property_name == "border":
			var tokens := _split_whitespace(value)
			if tokens.size() == 3 and tokens[1].to_lower() == "solid":
				expanded["border-width"] = tokens[0]
				expanded["border-color"] = tokens[2]
			else:
				expanded[property_name] = value
		else:
			expanded[property_name] = value
	return expanded


static func _apply_declarations(control: Control, computed: Dictionary, diagnostics: Array[Dictionary]) -> void:
	for state in computed:
		for property_name in computed[state]:
			var declaration: Dictionary = computed[state][property_name]
			_apply_declaration(
				control,
				property_name,
				str(declaration["value"]),
				state,
				int(declaration["line"]),
				diagnostics
			)


static func _apply_declaration(
	control: Control,
	property_name: String,
	value: String,
	state: String,
	line: int,
	diagnostics: Array[Dictionary]
) -> void:
	if not state.is_empty():
		_apply_state_declaration(control, property_name, value, state, line, diagnostics)
		return

	var style: CascadeStyle = control.get("cascade_style")
	match property_name:
		"display":
			if value.to_lower() != "flex":
				_diagnostic_bad_value(diagnostics, line, property_name, value)
		"flex-direction":
			if not _has_property(control, "direction"):
				_diagnostic_not_applicable(diagnostics, line, property_name, control)
			elif value.to_lower() == "row":
				control.set("direction", CascadeBox.FlowDirection.ROW)
			elif value.to_lower() == "column":
				control.set("direction", CascadeBox.FlowDirection.COLUMN)
			else:
				_diagnostic_bad_value(diagnostics, line, property_name, value)
		"flex-wrap":
			if not _has_property(control, "wrap"):
				_diagnostic_not_applicable(diagnostics, line, property_name, control)
			elif value.to_lower() in ["wrap", "nowrap"]:
				control.set("wrap", value.to_lower() == "wrap")
			else:
				_diagnostic_bad_value(diagnostics, line, property_name, value)
		"justify-content":
			_apply_enum(control, "justify_content", value, {
				"start": CascadeBox.MainAlignment.START,
				"center": CascadeBox.MainAlignment.CENTER,
				"end": CascadeBox.MainAlignment.END,
				"space-between": CascadeBox.MainAlignment.SPACE_BETWEEN,
				"space-around": CascadeBox.MainAlignment.SPACE_AROUND,
				"space-evenly": CascadeBox.MainAlignment.SPACE_EVENLY,
			}, line, diagnostics)
		"align-items":
			_apply_enum(control, "align_items", value, {
				"start": CascadeBox.CrossAlignment.START,
				"center": CascadeBox.CrossAlignment.CENTER,
				"end": CascadeBox.CrossAlignment.END,
				"stretch": CascadeBox.CrossAlignment.STRETCH,
			}, line, diagnostics)
		"gap":
			_set_length_property(control, "gap", value, line, diagnostics)
		"padding":
			_apply_edges(style, "padding", value, line, diagnostics)
		"margin":
			_apply_edges(style, "margin", value, line, diagnostics)
		"padding-left", "padding-top", "padding-right", "padding-bottom", "margin-left", "margin-top", "margin-right", "margin-bottom":
			_set_length_property(style, property_name.replace("-", "_"), value, line, diagnostics)
		"width":
			_set_length_property(style, "preferred_width", value, line, diagnostics)
		"height":
			_set_length_property(style, "preferred_height", value, line, diagnostics)
		"min-width":
			_set_length_property(style, "min_width", value, line, diagnostics)
		"min-height":
			_set_length_property(style, "min_height", value, line, diagnostics)
		"max-width":
			_set_length_property(style, "max_width", value, line, diagnostics)
		"max-height":
			_set_length_property(style, "max_height", value, line, diagnostics)
		"flex-grow":
			_set_number_property(style, "flex_grow", value, line, diagnostics)
		"align-self":
			_apply_enum(style, "align_self", value, {
				"auto": CascadeStyle.SelfAlignment.AUTO,
				"start": CascadeStyle.SelfAlignment.START,
				"center": CascadeStyle.SelfAlignment.CENTER,
				"end": CascadeStyle.SelfAlignment.END,
				"stretch": CascadeStyle.SelfAlignment.STRETCH,
			}, line, diagnostics)
		"overflow":
			_apply_enum(style, "overflow", value, {
				"visible": CascadeStyle.Overflow.VISIBLE,
				"clip": CascadeStyle.Overflow.CLIP,
				"hidden": CascadeStyle.Overflow.CLIP,
			}, line, diagnostics)
		"background", "background-color":
			style.background_color = _parse_color(value, line, diagnostics)
		"border-color":
			style.border_color = _parse_color(value, line, diagnostics)
		"border-width":
			_set_length_property(style, "border_width", value, line, diagnostics)
		"border-radius":
			_set_length_property(style, "border_radius", value, line, diagnostics)
		"border":
			_apply_border(style, value, line, diagnostics)
		"color":
			if _has_property(control, "text_color"):
				control.set("text_color", _parse_color(value, line, diagnostics))
			else:
				_diagnostic_not_applicable(diagnostics, line, property_name, control)
		"font-size":
			_set_length_property(control, "font_size", value, line, diagnostics)
		"fill-color":
			if control is CascadeProgress:
				control.fill_color = _parse_color(value, line, diagnostics)
			else:
				_diagnostic_not_applicable(diagnostics, line, property_name, control)
		_:
			diagnostics.append(_diagnostic("warning", "Line %s: unsupported property '%s'." % [line, property_name]))


static func _apply_state_declaration(
	control: Control,
	property_name: String,
	value: String,
	state: String,
	line: int,
	diagnostics: Array[Dictionary]
) -> void:
	if not control is BaseButton:
		diagnostics.append(_diagnostic("warning", "Line %s: :%s styles require an interactive control." % [line, state]))
		return

	var normalized_state := "checked" if state == "selected" else state
	if property_name in ["background", "background-color"]:
		var background_property := "%s_background_color" % normalized_state
		if _has_property(control, background_property):
			control.set(background_property, _parse_color(value, line, diagnostics))
		else:
			_diagnostic_unsupported_state(diagnostics, line, state, property_name)
	elif property_name == "color":
		var color_property := "%s_text_color" % normalized_state
		if _has_property(control, color_property):
			control.set(color_property, _parse_color(value, line, diagnostics))
		else:
			_diagnostic_unsupported_state(diagnostics, line, state, property_name)
	elif state == "focused" and property_name == "border-color":
		control.focus_ring_color = _parse_color(value, line, diagnostics)
	elif state == "focused" and property_name == "border-width":
		_set_length_property(control, "focus_ring_width", value, line, diagnostics)
	else:
		_diagnostic_unsupported_state(diagnostics, line, state, property_name)


static func _apply_attributes(
	control: Control,
	attributes: Dictionary,
	element_text: String,
	diagnostics: Array[Dictionary],
	button_groups: Dictionary
) -> void:
	if control is CascadeLabel or control is CascadeButton:
		var raw_text := str(attributes.get("text", element_text))
		if not _record_binding(control, "text", raw_text):
			control.set("text", raw_text)
	if attributes.has("accessible-label"):
		if _has_property(control, "accessibility_name"):
			control.set("accessibility_name", str(attributes["accessible-label"]))
		else:
			control.set_meta("cascade_accessible_label", str(attributes["accessible-label"]))
	if control is BaseButton:
		_apply_button_attributes(control, attributes, diagnostics, button_groups)
	if not control is CascadeProgress:
		return
	for attribute_name in ["min", "max", "value"]:
		if not attributes.has(attribute_name):
			continue
		var raw_value := str(attributes[attribute_name])
		var property_name := "%s_value" % attribute_name if attribute_name != "value" else "value"
		if _record_binding(control, property_name, raw_value):
			continue
		if not raw_value.is_valid_float():
			diagnostics.append(_diagnostic("error", "Progress attribute '%s' requires a number, got '%s'." % [attribute_name, raw_value]))
			continue
		control.set(property_name, raw_value.to_float())


static func _apply_button_attributes(
	control: BaseButton,
	attributes: Dictionary,
	diagnostics: Array[Dictionary],
	button_groups: Dictionary
) -> void:
	for attribute_name in ["disabled", "checked"]:
		if not attributes.has(attribute_name):
			continue
		var parsed: Variant = _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
		if parsed == null:
			continue
		if attribute_name == "disabled":
			control.disabled = parsed
		elif not control.toggle_mode:
			diagnostics.append(_diagnostic("error", "Attribute 'checked' requires a toggle control."))
		else:
			control.button_pressed = parsed

	if not control is CascadeRadioButton:
		return
	var group_name := str(attributes.get("group", "default")).strip_edges()
	if group_name.is_empty():
		diagnostics.append(_diagnostic("error", "RadioButton attribute 'group' cannot be empty."))
		return
	if not button_groups.has(group_name):
		button_groups[group_name] = ButtonGroup.new()
	control.button_group = button_groups[group_name]


static func _parse_bool_attribute(attribute_name: String, value: String, diagnostics: Array[Dictionary]) -> Variant:
	var normalized := value.strip_edges().to_lower()
	if normalized in ["true", "1", "yes", "on", attribute_name]:
		return true
	if normalized in ["false", "0", "no", "off"]:
		return false
	diagnostics.append(_diagnostic(
		"error",
		"Attribute '%s' requires a boolean, got '%s'." % [attribute_name, value]
	))
	return null


static func _record_binding(control: Control, property_name: String, raw_value: String) -> bool:
	var normalized := raw_value.strip_edges()
	if normalized.length() < 3 or not normalized.begins_with("{") or not normalized.ends_with("}"):
		return false
	var path := normalized.substr(1, normalized.length() - 2).strip_edges()
	if path.is_empty():
		return false
	var bindings: Dictionary = control.get_meta("cascade_bindings", {})
	bindings[property_name] = path
	control.set_meta("cascade_bindings", bindings)
	return true


static func _apply_edges(
	style: CascadeStyle,
	prefix: String,
	value: String,
	line: int,
	diagnostics: Array[Dictionary]
) -> void:
	var tokens := _split_whitespace(value)
	if tokens.size() < 1 or tokens.size() > 4:
		_diagnostic_bad_value(diagnostics, line, prefix, value)
		return
	var values: Array[float] = []
	for token in tokens:
		var parsed := _parse_length(token)
		if is_nan(parsed) or parsed < 0.0:
			_diagnostic_bad_value(diagnostics, line, prefix, value)
			return
		values.append(parsed)

	var top := values[0]
	var right := values[0] if values.size() == 1 else values[1]
	var bottom := values[0] if values.size() < 3 else values[2]
	var left := right if values.size() < 4 else values[3]
	style.set(prefix + "_top", top)
	style.set(prefix + "_right", right)
	style.set(prefix + "_bottom", bottom)
	style.set(prefix + "_left", left)


static func _apply_border(style: CascadeStyle, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	var tokens := _split_whitespace(value)
	if tokens.size() != 3 or tokens[1].to_lower() != "solid":
		_diagnostic_bad_value(diagnostics, line, "border", value)
		return
	var width := _parse_length(tokens[0])
	if is_nan(width) or width < 0.0:
		_diagnostic_bad_value(diagnostics, line, "border", value)
		return
	style.border_width = width
	style.border_color = _parse_color(tokens[2], line, diagnostics)


static func _apply_enum(target: Object, property_name: String, value: String, values: Dictionary, line: int, diagnostics: Array[Dictionary]) -> void:
	var normalized := value.to_lower()
	if not _has_property(target, property_name):
		_diagnostic_not_applicable(diagnostics, line, property_name.replace("_", "-"), target)
		return
	if not values.has(normalized):
		_diagnostic_bad_value(diagnostics, line, property_name.replace("_", "-"), value)
		return
	target.set(property_name, values[normalized])


static func _set_length_property(target: Object, property_name: String, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	var parsed := _parse_length(value)
	if is_nan(parsed) or parsed < 0.0:
		_diagnostic_bad_value(diagnostics, line, property_name.replace("_", "-"), value)
		return
	if not _has_property(target, property_name):
		_diagnostic_not_applicable(diagnostics, line, property_name.replace("_", "-"), target)
		return
	target.set(property_name, parsed)


static func _set_number_property(target: Object, property_name: String, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	if not value.is_valid_float():
		_diagnostic_bad_value(diagnostics, line, property_name.replace("_", "-"), value)
		return
	if not _has_property(target, property_name):
		_diagnostic_not_applicable(diagnostics, line, property_name.replace("_", "-"), target)
		return
	target.set(property_name, value.to_float())


static func _parse_length(value: String) -> float:
	var normalized := value.strip_edges().to_lower()
	if normalized.ends_with("px"):
		normalized = normalized.trim_suffix("px").strip_edges()
	if not normalized.is_valid_float():
		return NAN
	return normalized.to_float()


static func _parse_color(value: String, line: int, diagnostics: Array[Dictionary]) -> Color:
	var normalized := value.strip_edges()
	var black_probe := Color.from_string(normalized, Color.BLACK)
	var white_probe := Color.from_string(normalized, Color.WHITE)
	if black_probe != white_probe:
		diagnostics.append(_diagnostic("error", "Line %s: invalid color '%s'." % [line, value]))
		return Color.TRANSPARENT
	return black_probe


static func _split_whitespace(value: String) -> PackedStringArray:
	return value.replace("\t", " ").replace("\r", " ").replace("\n", " ").split(" ", false)


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false


static func _diagnostic_bad_value(diagnostics: Array[Dictionary], line: int, property_name: String, value: String) -> void:
	diagnostics.append(_diagnostic("error", "Line %s: unsupported %s value '%s'." % [line, property_name, value]))


static func _diagnostic_not_applicable(
	diagnostics: Array[Dictionary],
	line: int,
	property_name: String,
	target: Object
) -> void:
	var target_name := target.get_class()
	if target.has_meta("cascade_element_type"):
		target_name = "<%s>" % target.get_meta("cascade_element_type")
	diagnostics.append(_diagnostic(
		"warning",
		"Line %s: '%s' is not supported on %s." % [line, property_name, target_name]
	))


static func _diagnostic_unsupported_state(
	diagnostics: Array[Dictionary],
	line: int,
	state: String,
	property_name: String
) -> void:
	diagnostics.append(_diagnostic("warning", "Line %s: unsupported :%s property '%s'." % [line, state, property_name]))


static func _diagnostic(severity: String, message: String) -> Dictionary:
	return {"severity": severity, "message": message}
