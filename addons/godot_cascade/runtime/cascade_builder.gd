extends RefCounted

## Converts parsed GodotCascade elements and rules into native Control nodes.

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CascadeLabel := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")


static func build(root_element, rules: Array) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var root_control := _build_element(root_element, rules, diagnostics, "0")
	return {"root": root_control, "diagnostics": diagnostics}


static func _build_element(element, rules: Array, diagnostics: Array[Dictionary], key_path: String) -> Control:
	var control := _create_control(element.tag_name, diagnostics)
	if control == null:
		return null

	control.name = element.element_id() if not element.element_id().is_empty() else element.tag_name
	control.set_meta("cascade_element_type", element.tag_name)
	control.set_meta("cascade_id", element.element_id())
	control.set_meta("cascade_classes", element.classes())
	control.set_meta("cascade_key", "#" + element.element_id() if not element.element_id().is_empty() else key_path)

	if control is CascadeLabel or control is CascadeButton:
		control.set("text", str(element.attributes.get("text", element.text)))
	if element.tag_name.to_lower() == "row":
		control.direction = CascadeBox.FlowDirection.ROW

	var computed := _compute_declarations(element, rules)
	_apply_declarations(control, computed, diagnostics)

	for index in element.children.size():
		var child_element = element.children[index]
		var child_key := "%s/%s:%s" % [key_path, index, child_element.tag_name]
		var child_control := _build_element(child_element, rules, diagnostics, child_key)
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
		for property_name in rule.declarations:
			var existing: Dictionary = winners[state].get(property_name, {})
			if existing.is_empty() or rule.specificity > existing["specificity"] or (
				rule.specificity == existing["specificity"] and rule.order >= existing["order"]
			):
				winners[state][property_name] = {
					"value": rule.declarations[property_name],
					"specificity": rule.specificity,
					"order": rule.order,
					"line": rule.line,
				}
	return winners


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
				_diagnostic_unsupported(diagnostics, line, property_name, value)
		"flex-direction":
			if not _has_property(control, "direction"):
				_diagnostic_unsupported(diagnostics, line, property_name, value)
			elif value.to_lower() == "row":
				control.set("direction", CascadeBox.FlowDirection.ROW)
			elif value.to_lower() == "column":
				control.set("direction", CascadeBox.FlowDirection.COLUMN)
			else:
				_diagnostic_unsupported(diagnostics, line, property_name, value)
		"flex-wrap":
			if _has_property(control, "wrap"):
				control.set("wrap", value.to_lower() == "wrap")
			else:
				_diagnostic_unsupported(diagnostics, line, property_name, value)
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
				_diagnostic_unsupported(diagnostics, line, property_name, value)
		"font-size":
			_set_length_property(control, "font_size", value, line, diagnostics)
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
	if not control is CascadeButton:
		diagnostics.append(_diagnostic("warning", "Line %s: :%s styles currently require CascadeButton." % [line, state]))
		return

	match [state, property_name]:
		["hover", "background"], ["hover", "background-color"]:
			control.hover_background_color = _parse_color(value, line, diagnostics)
		["pressed", "background"], ["pressed", "background-color"]:
			control.pressed_background_color = _parse_color(value, line, diagnostics)
		["disabled", "background"], ["disabled", "background-color"]:
			control.disabled_background_color = _parse_color(value, line, diagnostics)
		["disabled", "color"]:
			control.disabled_text_color = _parse_color(value, line, diagnostics)
		["focused", "border-color"]:
			control.focus_ring_color = _parse_color(value, line, diagnostics)
		["focused", "border-width"]:
			_set_length_property(control, "focus_ring_width", value, line, diagnostics)
		_:
			diagnostics.append(_diagnostic("warning", "Line %s: unsupported :%s property '%s'." % [line, state, property_name]))


static func _apply_edges(
	style: CascadeStyle,
	prefix: String,
	value: String,
	line: int,
	diagnostics: Array[Dictionary]
) -> void:
	var tokens := value.split(" ", false)
	if tokens.size() < 1 or tokens.size() > 4:
		_diagnostic_unsupported(diagnostics, line, prefix, value)
		return
	var values: Array[float] = []
	for token in tokens:
		var parsed := _parse_length(token)
		if is_nan(parsed):
			_diagnostic_unsupported(diagnostics, line, prefix, value)
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
	var tokens := value.split(" ", false)
	if tokens.size() != 3 or tokens[1].to_lower() != "solid":
		_diagnostic_unsupported(diagnostics, line, "border", value)
		return
	var width := _parse_length(tokens[0])
	if is_nan(width):
		_diagnostic_unsupported(diagnostics, line, "border", value)
		return
	style.border_width = width
	style.border_color = _parse_color(tokens[2], line, diagnostics)


static func _apply_enum(target: Object, property_name: String, value: String, values: Dictionary, line: int, diagnostics: Array[Dictionary]) -> void:
	var normalized := value.to_lower()
	if not values.has(normalized) or not _has_property(target, property_name):
		_diagnostic_unsupported(diagnostics, line, property_name.replace("_", "-"), value)
		return
	target.set(property_name, values[normalized])


static func _set_length_property(target: Object, property_name: String, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	var parsed := _parse_length(value)
	if is_nan(parsed) or not _has_property(target, property_name):
		_diagnostic_unsupported(diagnostics, line, property_name.replace("_", "-"), value)
		return
	target.set(property_name, parsed)


static func _set_number_property(target: Object, property_name: String, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	if not value.is_valid_float() or not _has_property(target, property_name):
		_diagnostic_unsupported(diagnostics, line, property_name.replace("_", "-"), value)
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
	var parsed := Color.from_string(normalized, Color(1.0, 0.0, 1.0, 1.0))
	if parsed == Color(1.0, 0.0, 1.0, 1.0) and normalized.to_lower() not in ["magenta", "#ff00ff", "#ff00ffff"]:
		diagnostics.append(_diagnostic("error", "Line %s: invalid color '%s'." % [line, value]))
	return parsed


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false


static func _diagnostic_unsupported(diagnostics: Array[Dictionary], line: int, property_name: String, value: String) -> void:
	diagnostics.append(_diagnostic("error", "Line %s: unsupported %s value '%s'." % [line, property_name, value]))


static func _diagnostic(severity: String, message: String) -> Dictionary:
	return {"severity": severity, "message": message}
