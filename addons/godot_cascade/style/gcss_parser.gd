extends RefCounted

## Small, recoverable stylesheet parser for the first GodotCascade vertical slice.

const GcssTokenizer := preload("res://addons/godot_cascade/style/gcss_tokenizer.gd")


class Rule:
	extends RefCounted

	var selector := ""
	var compounds: PackedStringArray = []
	var combinators: PackedStringArray = []
	var pseudo_state := ""
	var declarations: Dictionary = {}
	var declaration_locations: Dictionary = {}
	var specificity := 0
	var order := 0
	var line := 1
	var min_viewport_width := -INF
	var max_viewport_width := INF


	func matches(element, viewport_width: float = INF) -> bool:
		if element == null or compounds.is_empty():
			return false
		if viewport_width < min_viewport_width or viewport_width > max_viewport_width:
			return false
		var current = element
		var index := compounds.size() - 1
		if not _compound_matches(compounds[index], current):
			return false
		index -= 1

		while index >= 0:
			var relation := combinators[index]
			current = current.parent_element()
			if relation == ">":
				if current == null or not _compound_matches(compounds[index], current):
					return false
			else:
				while current != null and not _compound_matches(compounds[index], current):
					current = current.parent_element()
			if current == null:
				return false
			index -= 1
		return true


	func _compound_matches(compound: String, element) -> bool:
		var cursor := 0
		var type_name := ""
		while cursor < compound.length() and compound[cursor] not in [".", "#"]:
			type_name += compound[cursor]
			cursor += 1
		if not type_name.is_empty() and type_name.to_lower() != element.tag_name.to_lower():
			return false

		var element_classes: PackedStringArray = element.classes()
		while cursor < compound.length():
			var marker := compound[cursor]
			cursor += 1
			var value := ""
			while cursor < compound.length() and compound[cursor] not in [".", "#"]:
				value += compound[cursor]
				cursor += 1
			if marker == "." and not element_classes.has(value):
				return false
			if marker == "#" and element.element_id() != value:
				return false
		return true


static func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var rules: Array[Rule] = []
	var tokenized := GcssTokenizer.tokenize(source)
	diagnostics.append_array(tokenized["diagnostics"])
	var cleaned := _strip_comments(source)
	var line_starts := _line_starts(cleaned)
	var cursor := 0

	while cursor < cleaned.length():
		cursor = _skip_whitespace(cleaned, cursor)
		if cursor >= cleaned.length():
			break
		var selector_start := cursor
		var open_brace := cleaned.find("{", cursor)
		if open_brace < 0:
			diagnostics.append(_diagnostic(cleaned, cursor, "Expected '{' after selector.", "error", line_starts))
			break
		var selector := cleaned.substr(cursor, open_brace - cursor).strip_edges()
		var close_brace := _find_matching_brace(cleaned, open_brace)
		if close_brace < 0:
			diagnostics.append(_diagnostic(cleaned, open_brace, "Unclosed declaration block.", "error", line_starts))
			break

		if selector.to_lower().begins_with("@media"):
			var condition := _parse_media_condition(selector, cleaned, selector_start, diagnostics, line_starts)
			if condition["valid"]:
				var body_source := cleaned.substr(open_brace + 1, close_brace - open_brace - 1)
				var nested := parse(body_source)
				var body_location := _diagnostic(cleaned, open_brace + 1, "", "error", line_starts)
				var reported_empty_intersection := false
				for diagnostic in nested["diagnostics"]:
					var adjusted: Dictionary = diagnostic.duplicate()
					adjusted["line"] = int(adjusted.get("line", 1)) + int(body_location["line"]) - 1
					if int(diagnostic.get("line", 1)) == 1:
						adjusted["column"] = int(adjusted.get("column", 1)) + int(body_location["column"]) - 1
					diagnostics.append(adjusted)
				for nested_rule in nested["rules"]:
					var relative_rule_line: int = nested_rule.line
					nested_rule.line = relative_rule_line + int(body_location["line"]) - 1
					for property_name in nested_rule.declaration_locations:
						var relative_location: Dictionary = nested_rule.declaration_locations[property_name]
						var adjusted_location := {
							"line": int(relative_location.get("line", 1)) + int(body_location["line"]) - 1,
							"column": int(relative_location.get("column", 1)),
						}
						if int(relative_location.get("line", 1)) == 1:
							adjusted_location["column"] += int(body_location["column"]) - 1
						nested_rule.declaration_locations[property_name] = adjusted_location
					nested_rule.min_viewport_width = maxf(nested_rule.min_viewport_width, condition["min"])
					nested_rule.max_viewport_width = minf(nested_rule.max_viewport_width, condition["max"])
					if nested_rule.min_viewport_width > nested_rule.max_viewport_width:
						if not reported_empty_intersection:
							diagnostics.append(_diagnostic(cleaned, selector_start, "Nested responsive conditions have no overlapping viewport range.", "error", line_starts))
							reported_empty_intersection = true
						continue
					nested_rule.order = rules.size()
					rules.append(nested_rule)
		elif selector.is_empty():
			diagnostics.append(_diagnostic(cleaned, selector_start, "Empty selector.", "error", line_starts))
		elif selector.contains(","):
			diagnostics.append(_diagnostic(cleaned, selector_start, "Selector lists are not supported yet.", "error", line_starts))
		else:
			var rule := _parse_rule(
				selector,
				cleaned.substr(open_brace + 1, close_brace - open_brace - 1),
				rules.size(),
				cleaned,
				selector_start,
				open_brace + 1,
				diagnostics,
				line_starts
			)
			if rule != null:
				rules.append(rule)
		cursor = close_brace + 1

	return {"rules": rules, "diagnostics": diagnostics, "tokens": tokenized["tokens"]}


static func _find_matching_brace(source: String, open_brace: int) -> int:
	var depth := 0
	var parentheses := 0
	var quote := ""
	var escaped := false
	for cursor in range(open_brace, source.length()):
		var character := source[cursor]
		if escaped:
			escaped = false
			continue
		if character == "\\":
			escaped = true
			continue
		if not quote.is_empty():
			if character == quote:
				quote = ""
			continue
		if character in ["\"", "'"]:
			quote = character
			continue
		if character == "(":
			parentheses += 1
			continue
		if character == ")":
			parentheses = maxi(parentheses - 1, 0)
			continue
		if parentheses > 0:
			continue
		if character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return cursor
	return -1


static func _parse_media_condition(header: String, source: String, offset: int, diagnostics: Array[Dictionary], line_starts: PackedInt32Array) -> Dictionary:
	var condition := header.substr(6).strip_edges()
	if not condition.begins_with("(") or not condition.ends_with(")"):
		diagnostics.append(_diagnostic(source, offset, "Responsive condition must be @media (min-width: <length>) or @media (max-width: <length>).", "error", line_starts))
		return {"valid": false, "min": -INF, "max": INF}
	var parts := condition.trim_prefix("(").trim_suffix(")").split(":", false)
	if parts.size() != 2:
		diagnostics.append(_diagnostic(source, offset, "Responsive condition requires one width comparison.", "error", line_starts))
		return {"valid": false, "min": -INF, "max": INF}
	var comparison := str(parts[0]).strip_edges().to_lower()
	var raw_length := str(parts[1]).strip_edges().to_lower().trim_suffix("px").strip_edges()
	if comparison not in ["min-width", "max-width"] or not raw_length.is_valid_float() or raw_length.to_float() < 0.0:
		diagnostics.append(_diagnostic(source, offset, "Unsupported responsive condition '%s'." % condition, "error", line_starts))
		return {"valid": false, "min": -INF, "max": INF}
	var length := raw_length.to_float()
	return {
		"valid": true,
		"min": length if comparison == "min-width" else -INF,
		"max": length if comparison == "max-width" else INF,
	}


static func _parse_rule(
	selector: String,
	body: String,
	order: int,
	source: String,
	offset: int,
	body_offset: int,
	diagnostics: Array[Dictionary],
	line_starts: PackedInt32Array
) -> Rule:
	var rule := Rule.new()
	rule.selector = selector
	rule.order = order
	rule.line = _diagnostic(source, offset, "", "error", line_starts)["line"]
	var selector_without_pseudo := selector
	var colon := selector.rfind(":")
	if colon >= 0:
		rule.pseudo_state = selector.substr(colon + 1).strip_edges().to_lower()
		selector_without_pseudo = selector.substr(0, colon).strip_edges()
		if rule.pseudo_state not in ["hover", "pressed", "checked", "focused", "focus-visible", "disabled", "selected", "open", "invalid"]:
			diagnostics.append(_diagnostic(source, offset + colon, "Unsupported pseudo state :%s; declarations apply to the base selector." % rule.pseudo_state, "warning", line_starts))
			rule.pseudo_state = ""

	var parsed_selector := _parse_selector(selector_without_pseudo, source, offset, diagnostics, line_starts)
	rule.compounds = parsed_selector["compounds"]
	rule.combinators = parsed_selector["combinators"]
	if rule.compounds.is_empty():
		diagnostics.append(_diagnostic(source, offset, "Selector contains no matchable compound.", "error", line_starts))
		return null
	rule.specificity = _specificity(rule.compounds, rule.pseudo_state)

	for declaration_range in _declaration_ranges(body):
		var body_cursor := int(declaration_range["start"])
		var raw_declaration := body.substr(body_cursor, int(declaration_range["end"]) - body_cursor)
		var declaration := raw_declaration.strip_edges()
		var declaration_start := body_cursor
		while declaration_start < body_cursor + raw_declaration.length() and source[body_offset + declaration_start] in [" ", "\t", "\r", "\n"]:
			declaration_start += 1
		if declaration.is_empty():
			continue
		var separator := declaration.find(":")
		if separator < 1:
			diagnostics.append(_diagnostic(source, offset, "Invalid declaration '%s'." % declaration, "error", line_starts))
			continue
		var authored_property_name := declaration.substr(0, separator).strip_edges()
		var property_name := authored_property_name if authored_property_name.begins_with("--") else authored_property_name.to_lower()
		if property_name.begins_with("--") and not _valid_custom_property_name(property_name):
			diagnostics.append(_diagnostic(source, body_offset + declaration_start, "Invalid custom-property name '%s'." % property_name, "error", line_starts))
			continue
		var value := declaration.substr(separator + 1).strip_edges()
		if value.is_empty():
			diagnostics.append(_diagnostic(source, offset, "Property '%s' has no value." % property_name, "error", line_starts))
			continue
		rule.declarations[property_name] = value
		var location := _diagnostic(source, body_offset + declaration_start, "", "error", line_starts)
		rule.declaration_locations[property_name] = {
			"line": location["line"],
			"column": location["column"],
		}
	return rule


static func _declaration_ranges(body: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := 0
	var parentheses := 0
	var quote := ""
	var escaped := false
	for cursor in body.length():
		var character := body[cursor]
		if escaped:
			escaped = false
			continue
		if character == "\\":
			escaped = true
			continue
		if not quote.is_empty():
			if character == quote:
				quote = ""
			continue
		if character in ["\"", "'"]:
			quote = character
		elif character == "(":
			parentheses += 1
		elif character == ")":
			parentheses = maxi(parentheses - 1, 0)
		elif character == ";" and parentheses == 0:
			result.append({"start": start, "end": cursor})
			start = cursor + 1
	result.append({"start": start, "end": body.length()})
	return result


static func _valid_custom_property_name(value: String) -> bool:
	if value.length() < 3:
		return false
	for cursor in range(2, value.length()):
		var character := value[cursor]
		var lowered := character.to_lower()
		if character not in ["-", "_"] and not (lowered >= "a" and lowered <= "z") and not (character >= "0" and character <= "9"):
			return false
	return true


static func _specificity(compounds: PackedStringArray, pseudo_state: String) -> int:
	var selector := " ".join(compounds)
	var ids := selector.count("#")
	var classes := selector.count(".") + (0 if pseudo_state.is_empty() else 1)
	var types := 0
	for compound in compounds:
		if not compound.begins_with(".") and not compound.begins_with("#"):
			types += 1
	return ids * 100 + classes * 10 + types


static func _parse_selector(selector: String, source: String, offset: int, diagnostics: Array[Dictionary], line_starts: PackedInt32Array) -> Dictionary:
	var compounds := PackedStringArray()
	var combinators := PackedStringArray()
	var current := ""
	var pending_descendant := false
	for index in selector.length():
		var character := selector[index]
		if character in [" ", "\t", "\r", "\n"]:
			if not current.is_empty():
				compounds.append(current)
				current = ""
			pending_descendant = not compounds.is_empty()
		elif character == ">":
			if not current.is_empty():
				compounds.append(current)
				current = ""
			if compounds.is_empty() or combinators.size() >= compounds.size():
				diagnostics.append(_diagnostic(source, offset + index, "Direct-child combinator requires a selector on its left.", "error", line_starts))
				return {"compounds": PackedStringArray(), "combinators": PackedStringArray()}
			combinators.append(">")
			pending_descendant = false
		else:
			if pending_descendant and compounds.size() > combinators.size():
				combinators.append(" ")
			pending_descendant = false
			current += character
	if not current.is_empty():
		compounds.append(current)
	if compounds.size() > 0 and combinators.size() != compounds.size() - 1:
		diagnostics.append(_diagnostic(source, offset, "Selector ends with a combinator.", "error", line_starts))
		return {"compounds": PackedStringArray(), "combinators": PackedStringArray()}
	return {"compounds": compounds, "combinators": combinators}


static func _strip_comments(source: String) -> String:
	var result := PackedStringArray()
	var cursor := 0
	var quote := ""
	var escaped := false
	while cursor < source.length():
		var character := source[cursor]
		if escaped:
			result.append(character)
			escaped = false
			cursor += 1
			continue
		if character == "\\":
			result.append(character)
			escaped = true
			cursor += 1
			continue
		if not quote.is_empty():
			result.append(character)
			if character == quote:
				quote = ""
			cursor += 1
			continue
		if character in ["\"", "'"]:
			quote = character
			result.append(character)
			cursor += 1
			continue
		if cursor + 1 >= source.length() or source.substr(cursor, 2) != "/*":
			result.append(character)
			cursor += 1
			continue
		var close := source.find("*/", cursor + 2)
		if close < 0:
			close = source.length() - 2
		var end := mini(close + 2, source.length())
		while cursor < end:
			result.append("\n" if source[cursor] == "\n" else " ")
			cursor += 1
	return "".join(result)


static func _skip_whitespace(source: String, cursor: int) -> int:
	while cursor < source.length() and source[cursor] in [" ", "\t", "\r", "\n"]:
		cursor += 1
	return cursor


static func _line_starts(source: String) -> PackedInt32Array:
	var result := PackedInt32Array([0])
	var cursor := source.find("\n")
	while cursor >= 0:
		result.append(cursor + 1)
		cursor = source.find("\n", cursor + 1)
	return result


static func _diagnostic(source: String, offset: int, message: String, severity: String = "error", line_starts: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var safe_offset := clampi(offset, 0, source.length())
	var starts := line_starts if not line_starts.is_empty() else _line_starts(source)
	var low := 0
	var high := starts.size()
	while low < high:
		var middle := (low + high) >> 1
		if starts[middle] <= safe_offset:
			low = middle + 1
		else:
			high = middle
	var line_index := maxi(low - 1, 0)
	return {
		"severity": severity,
		"line": line_index + 1,
		"column": safe_offset - starts[line_index] + 1,
		"message": message,
	}
