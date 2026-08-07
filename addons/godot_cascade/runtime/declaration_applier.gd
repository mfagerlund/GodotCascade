extends RefCounted

## Applies computed GCSS declarations to native controls independently of tree construction.

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeGrid := preload("res://addons/godot_cascade/layout/cascade_grid.gd")
const CascadeTable := preload("res://addons/godot_cascade/components/cascade_table.gd")
const CascadeTablePart := preload("res://addons/godot_cascade/components/cascade_table_part.gd")
const CascadeImage := preload("res://addons/godot_cascade/components/cascade_image.gd")
const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")
const GcssValue := preload("res://addons/godot_cascade/style/gcss_value.gd")
const TransitionManager := preload("res://addons/godot_cascade/runtime/transition_manager.gd")
const GcssExpression := preload("res://addons/godot_cascade/style/gcss_expression.gd")

static var _active_viewport_size := Vector2.ZERO
const INVALID_RESOLVED_VALUE := "__godot_cascade_invalid_resolved_value__"


static func begin_build(viewport_size: Vector2) -> void:
	_active_viewport_size = viewport_size


static func expand_shorthands(declarations: Dictionary) -> Dictionary:
	return _expand_shorthands(declarations)


static func apply(control: Control, computed: Dictionary, diagnostics: Array[Dictionary]) -> void:
	_apply_declarations(control, computed, diagnostics)


static func apply_select_option_styles(option: Dictionary, computed: Dictionary, diagnostics: Array[Dictionary]) -> void:
	_apply_select_option_styles(option, computed, diagnostics)

static func _expand_shorthands(declarations: Dictionary) -> Dictionary:
	var expanded := {}
	var origins := {}
	var errors := {}
	for property_name in declarations:
		var value: String = str(declarations[property_name])
		if value == INVALID_RESOLVED_VALUE:
			_expand_invalid_shorthand(property_name, expanded, origins)
			continue
		if property_name in ["padding", "margin"]:
			var tokens := _split_whitespace(value)
			var valid_lengths := tokens.size() >= 1 and tokens.size() <= 4
			for token in tokens:
				var parsed := _parse_length(token)
				valid_lengths = valid_lengths and not is_nan(parsed) and parsed >= 0.0
			if not valid_lengths:
				_expand_invalid_shorthand(property_name, expanded, origins)
				errors[property_name] = "Unsupported shorthand value '%s'." % value
				continue
			var top := tokens[0]
			var right := tokens[0] if tokens.size() == 1 else tokens[1]
			var bottom := tokens[0] if tokens.size() < 3 else tokens[2]
			var left := right if tokens.size() < 4 else tokens[3]
			expanded["%s-top" % property_name] = top
			expanded["%s-right" % property_name] = right
			expanded["%s-bottom" % property_name] = bottom
			expanded["%s-left" % property_name] = left
			for edge in ["top", "right", "bottom", "left"]:
				origins["%s-%s" % [property_name, edge]] = property_name
		elif property_name == "border":
			var tokens := _split_whitespace(value)
			if tokens.size() == 3 and tokens[1].to_lower() == "solid":
				expanded["border-width"] = tokens[0]
				expanded["border-color"] = tokens[2]
				origins["border-width"] = property_name
				origins["border-color"] = property_name
			else:
				_expand_invalid_shorthand(property_name, expanded, origins)
				errors[property_name] = "Unsupported shorthand value '%s'." % value
		elif property_name == "gap":
			var tokens := _split_whitespace(value)
			var valid_gaps := tokens.size() >= 1 and tokens.size() <= 2
			for token in tokens:
				var parsed := _parse_length(token)
				valid_gaps = valid_gaps and not is_nan(parsed) and parsed >= 0.0
			if valid_gaps:
				expanded["row-gap"] = tokens[0]
				expanded["column-gap"] = tokens[0] if tokens.size() == 1 else tokens[1]
				origins["row-gap"] = property_name
				origins["column-gap"] = property_name
			else:
				_expand_invalid_shorthand(property_name, expanded, origins)
				errors[property_name] = "Unsupported shorthand value '%s'." % value
		elif property_name == "transition":
			var tokens := _split_whitespace(value)
			if tokens.size() == 2:
				var first = GcssValue.parse(tokens[0])
				var second = GcssValue.parse(tokens[1])
				var first_is_time: bool = first.kind == GcssValue.Kind.TIME or not is_nan(_parse_time_ms(tokens[0]))
				var second_is_time: bool = second.kind == GcssValue.Kind.TIME or not is_nan(_parse_time_ms(tokens[1]))
				var duration_index := 0 if first_is_time else 1
				var transition_property := tokens[1 - duration_index]
				if first_is_time != second_is_time:
					expanded["transition-property"] = transition_property
					expanded["transition-duration"] = tokens[duration_index]
					origins["transition-property"] = property_name
					origins["transition-duration"] = property_name
				else:
					_expand_invalid_shorthand(property_name, expanded, origins)
					errors[property_name] = "Unsupported shorthand value '%s'." % value
			else:
				_expand_invalid_shorthand(property_name, expanded, origins)
				errors[property_name] = "Unsupported shorthand value '%s'." % value
		else:
			expanded[property_name] = value
			origins[property_name] = property_name
	return {"values": expanded, "origins": origins, "errors": errors}


static func _expand_invalid_shorthand(property_name: String, expanded: Dictionary, origins: Dictionary) -> void:
	var invalid_targets := PackedStringArray([property_name])
	if property_name in ["padding", "margin"]:
		invalid_targets = PackedStringArray([
			"%s-top" % property_name, "%s-right" % property_name,
			"%s-bottom" % property_name, "%s-left" % property_name,
		])
	elif property_name == "gap":
		invalid_targets = PackedStringArray(["row-gap", "column-gap"])
	elif property_name == "border":
		invalid_targets = PackedStringArray(["border-width", "border-color"])
	elif property_name == "transition":
		invalid_targets = PackedStringArray(["transition-property", "transition-duration"])
	for target in invalid_targets:
		expanded[target] = INVALID_RESOLVED_VALUE
		origins[target] = property_name


static func _apply_declarations(control: Control, computed: Dictionary, diagnostics: Array[Dictionary]) -> void:
	diagnostics.append_array(computed.get("__diagnostics", []))
	for state in computed:
		if str(state).begins_with("__"):
			continue
		for property_name in computed[state]:
			var declaration: Dictionary = computed[state][property_name]
			if bool(declaration.get("invalid", false)):
				continue
			var diagnostic_start := diagnostics.size()
			_apply_declaration(
				control,
				property_name,
				str(declaration["value"]),
				state,
				int(declaration["line"]),
				diagnostics
			)
			_stamp_diagnostics(diagnostics, diagnostic_start, int(declaration["line"]), int(declaration.get("column", 1)))
	if control is CascadeBox:
		_resolve_flex_gaps(control)


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
	if control is CascadeTablePart:
		if property_name in ["color", "font-size"]:
			return
		if property_name not in ["background", "background-color", "border", "border-color", "border-width", "border-radius", "transition-property", "transition-duration"]:
			_diagnostic_not_applicable(diagnostics, line, property_name, control)
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
			if control is CascadeGrid or control is CascadeTable:
				var gaps := _split_whitespace(value)
				if gaps.size() < 1 or gaps.size() > 2:
					_diagnostic_bad_value(diagnostics, line, property_name, value)
				else:
					_set_length_property(control, "row_gap", gaps[0], line, diagnostics)
					_set_length_property(control, "column_gap", gaps[0] if gaps.size() == 1 else gaps[1], line, diagnostics)
			else:
				_set_length_property(control, "gap", value, line, diagnostics)
		"column-gap", "row-gap":
			if control is CascadeBox:
				var parsed_gap := _parse_length(value)
				if is_nan(parsed_gap) or parsed_gap < 0.0:
					_diagnostic_bad_value(diagnostics, line, property_name, value)
				else:
					control.set_meta("cascade_%s" % property_name.replace("-", "_"), parsed_gap)
			else:
				_set_length_property(control, property_name.replace("-", "_"), value, line, diagnostics)
		"grid-template-columns", "grid-template-rows":
			if property_name == "grid-template-rows" and control is CascadeTable:
				_diagnostic_not_applicable(diagnostics, line, property_name, control)
				return
			var tracks := _parse_grid_tracks(value, line, diagnostics)
			if not tracks.is_empty():
				control.set("column_tracks" if property_name.ends_with("columns") else "row_tracks", tracks)
		"grid-column", "grid-row":
			_apply_grid_placement(control, property_name, value, line, diagnostics)
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
		"object-fit":
			_apply_enum(control, "fit", value, {
				"contain": CascadeImage.FitMode.CONTAIN,
				"cover": CascadeImage.FitMode.COVER,
				"fill": CascadeImage.FitMode.FILL,
				"none": CascadeImage.FitMode.NONE,
			}, line, diagnostics)
		"transition-property":
			var transition_properties := PackedStringArray()
			for authored_name in value.split(",", false):
				var normalized_name := str(authored_name).strip_edges().to_lower()
				if normalized_name == "all":
					transition_properties.append("all")
					continue
				var mapped := TransitionManager.mapped_property(normalized_name)
				if mapped.is_empty():
					_diagnostic_bad_value(diagnostics, line, property_name, normalized_name)
					continue
				transition_properties.append(mapped)
			control.set_meta("cascade_transition_properties", transition_properties)
		"transition-duration":
			var duration_ms := _parse_time_ms(value)
			if is_nan(duration_ms) or duration_ms < 0.0:
				_diagnostic_bad_value(diagnostics, line, property_name, value)
			else:
				control.set_meta("cascade_transition_duration", duration_ms / 1000.0)
		"position":
			if value.to_lower() in ["relative", "absolute"]:
				control.set_meta("cascade_position", value.to_lower())
			else:
				_diagnostic_bad_value(diagnostics, line, property_name, value)
		"left", "top", "right", "bottom":
			var inset := _parse_length(value)
			if is_nan(inset):
				_diagnostic_bad_value(diagnostics, line, property_name, value)
			else:
				control.set_meta("cascade_%s" % property_name, inset)
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
			if _has_property(control, "fill_color"):
				control.set("fill_color", _parse_color(value, line, diagnostics))
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
	var normalized_state := "checked" if state == "selected" else state
	if normalized_state == "focus-visible" and property_name in ["border-color", "border-width"]:
		if not _has_property(control, "focus_visible_style_enabled"):
			_diagnostic_unsupported_state(diagnostics, line, state, property_name)
			return
		control.set("focus_visible_style_enabled", true)
		if property_name == "border-color":
			control.set("focus_visible_ring_color", _parse_color(value, line, diagnostics))
		else:
			_set_length_property(control, "focus_visible_ring_width", value, line, diagnostics)
		return
	if normalized_state == "invalid" and property_name == "border-color" and _has_property(control, "invalid_border_color"):
		control.set("invalid_border_color", _parse_color(value, line, diagnostics))
		return
	if property_name in ["background", "background-color"]:
		var background_property := "%s_background_color" % normalized_state
		if _has_property(control, background_property):
			control.set(background_property, _parse_color(value, line, diagnostics))
			var enabled_property := "%s_style_enabled" % normalized_state
			if _has_property(control, enabled_property):
				control.set(enabled_property, true)
		else:
			_diagnostic_unsupported_state(diagnostics, line, state, property_name)
	elif property_name == "color":
		var color_property := "%s_text_color" % normalized_state
		if _has_property(control, color_property):
			control.set(color_property, _parse_color(value, line, diagnostics))
		else:
			_diagnostic_unsupported_state(diagnostics, line, state, property_name)
	elif state == "focused" and property_name == "border-color" and _has_property(control, "focus_ring_color"):
		control.set("focus_ring_color", _parse_color(value, line, diagnostics))
	elif state == "focused" and property_name == "border-width" and _has_property(control, "focus_ring_width"):
		_set_length_property(control, "focus_ring_width", value, line, diagnostics)
	else:
		_diagnostic_unsupported_state(diagnostics, line, state, property_name)


static func _apply_select_option_styles(
	option: Dictionary,
	computed: Dictionary,
	diagnostics: Array[Dictionary]
) -> void:
	diagnostics.append_array(computed.get("__diagnostics", []))
	for state in computed:
		if str(state).begins_with("__"):
			continue
		for property_name in computed[state]:
			var declaration: Dictionary = computed[state][property_name]
			if bool(declaration.get("invalid", false)):
				continue
			var line := int(declaration["line"])
			var diagnostic_start := diagnostics.size()
			var value := str(declaration["value"])
			var style_key := ""
			if property_name in ["background", "background-color"]:
				style_key = "%sbackground_color" % ("" if state.is_empty() else "%s_" % state)
			elif property_name == "color":
				style_key = "%stext_color" % ("" if state.is_empty() else "%s_" % state)
			else:
				_diagnostic_unsupported_state(diagnostics, line, state, property_name)
				continue
			if state not in ["", "hover", "selected", "disabled"]:
				_diagnostic_unsupported_state(diagnostics, line, state, property_name)
				continue
			option[style_key] = _parse_color(value, line, diagnostics)
			_stamp_diagnostics(diagnostics, diagnostic_start, line, int(declaration.get("column", 1)))


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
	var parsed := NAN
	if value.strip_edges().to_lower().begins_with("calc("):
		var evaluated := GcssExpression.evaluate(value, _active_viewport_size)
		if bool(evaluated.get("ok", false)) and evaluated.get("kind", "") == "number":
			parsed = float(evaluated["value"])
	elif value.is_valid_float():
		parsed = value.to_float()
	if is_nan(parsed):
		_diagnostic_bad_value(diagnostics, line, property_name.replace("_", "-"), value)
		return
	if not _has_property(target, property_name):
		_diagnostic_not_applicable(diagnostics, line, property_name.replace("_", "-"), target)
		return
	target.set(property_name, parsed)


static func _parse_length(value: String) -> float:
	var normalized := value.strip_edges().to_lower()
	if normalized.begins_with("calc("):
		var evaluated := GcssExpression.evaluate(normalized, _active_viewport_size)
		if not bool(evaluated.get("ok", false)) or evaluated.get("kind", "") not in ["length", "number"]:
			return NAN
		return float(evaluated["value"])
	if normalized.ends_with("vw") or normalized.ends_with("vh"):
		var axis := "vw" if normalized.ends_with("vw") else "vh"
		var magnitude := normalized.trim_suffix(axis).strip_edges()
		if not magnitude.is_valid_float():
			return NAN
		var reference := _active_viewport_size.x if axis == "vw" else _active_viewport_size.y
		return NAN if reference <= 0.0 else magnitude.to_float() * reference / 100.0
	if normalized.ends_with("px"):
		normalized = normalized.trim_suffix("px").strip_edges()
	if not normalized.is_valid_float():
		return NAN
	return normalized.to_float()


static func _parse_time_ms(value: String) -> float:
	var normalized := value.strip_edges().to_lower()
	if normalized.begins_with("calc("):
		var evaluated := GcssExpression.evaluate(normalized, _active_viewport_size)
		return float(evaluated["value"]) if bool(evaluated.get("ok", false)) and evaluated.get("kind", "") == "time" else NAN
	var parsed = GcssValue.parse(normalized)
	return parsed.milliseconds() if parsed.kind == GcssValue.Kind.TIME else NAN


static func _resolve_flex_gaps(control: Control) -> void:
	var row_gap := float(control.get_meta("cascade_row_gap", 0.0))
	var column_gap := float(control.get_meta("cascade_column_gap", 0.0))
	if int(control.get("direction")) == CascadeBox.FlowDirection.ROW:
		control.set("gap", column_gap)
		control.set("line_gap", row_gap)
	else:
		control.set("gap", row_gap)
		control.set("line_gap", column_gap)


static func _parse_grid_tracks(value: String, line: int, diagnostics: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for token in _split_grid_tracks(value):
		var normalized := token.to_lower()
		if normalized in ["auto", "content"]:
			result.append({"kind": "content"})
		elif normalized.ends_with("fr"):
			var weight := normalized.trim_suffix("fr")
			if not weight.is_valid_float() or weight.to_float() <= 0.0:
				_diagnostic_bad_value(diagnostics, line, "grid-track", token)
				return []
			result.append({"kind": "fraction", "value": weight.to_float()})
		elif normalized.begins_with("minmax(") and normalized.ends_with(")"):
			var parts := normalized.trim_prefix("minmax(").trim_suffix(")").split(",", false)
			if parts.size() != 2:
				_diagnostic_bad_value(diagnostics, line, "grid-track", token)
				return []
			var minimum := _parse_length(parts[0])
			if is_nan(minimum) or minimum < 0.0:
				_diagnostic_bad_value(diagnostics, line, "grid-track", token)
				return []
			var maximum := str(parts[1]).strip_edges()
			if maximum.ends_with("fr"):
				var fraction := maximum.trim_suffix("fr")
				if not fraction.is_valid_float() or fraction.to_float() <= 0.0:
					_diagnostic_bad_value(diagnostics, line, "grid-track", token)
					return []
				result.append({"kind": "minmax", "min": minimum, "fraction": fraction.to_float()})
			else:
				var parsed_max := _parse_length(maximum)
				if is_nan(parsed_max) or parsed_max < minimum:
					_diagnostic_bad_value(diagnostics, line, "grid-track", token)
					return []
				result.append({"kind": "minmax", "min": minimum, "max": parsed_max})
		else:
			var fixed := _parse_length(normalized)
			if is_nan(fixed) or fixed < 0.0:
				_diagnostic_bad_value(diagnostics, line, "grid-track", token)
				return []
			result.append({"kind": "fixed", "value": fixed})
	return result


static func _split_grid_tracks(value: String) -> PackedStringArray:
	var result := PackedStringArray()
	var token := ""
	var depth := 0
	for character in value:
		if character == "(":
			depth += 1
		elif character == ")":
			depth = maxi(depth - 1, 0)
		if character in [" ", "\t", "\r", "\n"] and depth == 0:
			if not token.is_empty():
				result.append(token)
				token = ""
		else:
			token += character
	if not token.is_empty():
		result.append(token)
	return result


static func _apply_grid_placement(control: Control, property_name: String, value: String, line: int, diagnostics: Array[Dictionary]) -> void:
	var parts := value.split("/", false)
	var start := str(parts[0]).strip_edges()
	if not start.is_valid_int() or start.to_int() < 1:
		_diagnostic_bad_value(diagnostics, line, property_name, value)
		return
	var axis := "column" if property_name.ends_with("column") else "row"
	control.set_meta("cascade_grid_%s" % axis, start.to_int() - 1)
	if parts.size() == 2:
		var span := str(parts[1]).strip_edges().trim_prefix("span ")
		if not span.is_valid_int() or span.to_int() < 1:
			_diagnostic_bad_value(diagnostics, line, property_name, value)
			return
		control.set_meta("cascade_grid_%s_span" % axis, span.to_int())


static func _parse_color(value: String, line: int, diagnostics: Array[Dictionary]) -> Color:
	var normalized := value.strip_edges()
	var black_probe := Color.from_string(normalized, Color.BLACK)
	var white_probe := Color.from_string(normalized, Color.WHITE)
	if black_probe != white_probe:
		diagnostics.append(_diagnostic("error", "Line %s: invalid color '%s'." % [line, value]))
		return Color.TRANSPARENT
	return black_probe


static func _split_whitespace(value: String) -> PackedStringArray:
	return _split_grid_tracks(value)


static func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)


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


static func _stamp_diagnostics(diagnostics: Array[Dictionary], start: int, line: int, column: int) -> void:
	for index in range(start, diagnostics.size()):
		diagnostics[index]["line"] = line
		diagnostics[index]["column"] = column


static func _diagnostic(severity: String, message: String) -> Dictionary:
	return {"severity": severity, "message": message}
