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


	func matches(element) -> bool:
		if element == null or compounds.is_empty():
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
	var cursor := 0

	while cursor < cleaned.length():
		cursor = _skip_whitespace(cleaned, cursor)
		if cursor >= cleaned.length():
			break
		var selector_start := cursor
		var open_brace := cleaned.find("{", cursor)
		if open_brace < 0:
			diagnostics.append(_diagnostic(cleaned, cursor, "Expected '{' after selector."))
			break
		var selector := cleaned.substr(cursor, open_brace - cursor).strip_edges()
		var close_brace := cleaned.find("}", open_brace + 1)
		if close_brace < 0:
			diagnostics.append(_diagnostic(cleaned, open_brace, "Unclosed declaration block."))
			break

		if selector.is_empty():
			diagnostics.append(_diagnostic(cleaned, selector_start, "Empty selector."))
		elif selector.contains(","):
			diagnostics.append(_diagnostic(cleaned, selector_start, "Selector lists are not supported yet."))
		else:
			var rule := _parse_rule(
				selector,
				cleaned.substr(open_brace + 1, close_brace - open_brace - 1),
				rules.size(),
				cleaned,
				selector_start,
				open_brace + 1,
				diagnostics
			)
			if rule != null:
				rules.append(rule)
		cursor = close_brace + 1

	return {"rules": rules, "diagnostics": diagnostics, "tokens": tokenized["tokens"]}


static func _parse_rule(
	selector: String,
	body: String,
	order: int,
	source: String,
	offset: int,
	body_offset: int,
	diagnostics: Array[Dictionary]
) -> Rule:
	var rule := Rule.new()
	rule.selector = selector
	rule.order = order
	rule.line = _diagnostic(source, offset, "")["line"]
	var selector_without_pseudo := selector
	var colon := selector.rfind(":")
	if colon >= 0:
		rule.pseudo_state = selector.substr(colon + 1).strip_edges().to_lower()
		selector_without_pseudo = selector.substr(0, colon).strip_edges()
		if rule.pseudo_state not in ["hover", "pressed", "checked", "focused", "disabled", "selected", "open"]:
			diagnostics.append(_diagnostic(source, offset + colon, "Unsupported pseudo state :%s; declarations apply to the base selector." % rule.pseudo_state, "warning"))
			rule.pseudo_state = ""

	var parsed_selector := _parse_selector(selector_without_pseudo, source, offset, diagnostics)
	rule.compounds = parsed_selector["compounds"]
	rule.combinators = parsed_selector["combinators"]
	if rule.compounds.is_empty():
		diagnostics.append(_diagnostic(source, offset, "Selector contains no matchable compound."))
		return null
	rule.specificity = _specificity(rule.compounds, rule.pseudo_state)

	var body_cursor := 0
	for raw_declaration in body.split(";"):
		var declaration := raw_declaration.strip_edges()
		var declaration_start := body_cursor
		while declaration_start < body_cursor + raw_declaration.length() and source[body_offset + declaration_start] in [" ", "\t", "\r", "\n"]:
			declaration_start += 1
		body_cursor += raw_declaration.length() + 1
		if declaration.is_empty():
			continue
		var separator := declaration.find(":")
		if separator < 1:
			diagnostics.append(_diagnostic(source, offset, "Invalid declaration '%s'." % declaration))
			continue
		var property_name := declaration.substr(0, separator).strip_edges().to_lower()
		var value := declaration.substr(separator + 1).strip_edges()
		if value.is_empty():
			diagnostics.append(_diagnostic(source, offset, "Property '%s' has no value." % property_name))
			continue
		rule.declarations[property_name] = value
		var location := _diagnostic(source, body_offset + declaration_start, "")
		rule.declaration_locations[property_name] = {
			"line": location["line"],
			"column": location["column"],
		}
	return rule


static func _specificity(compounds: PackedStringArray, pseudo_state: String) -> int:
	var selector := " ".join(compounds)
	var ids := selector.count("#")
	var classes := selector.count(".") + (0 if pseudo_state.is_empty() else 1)
	var types := 0
	for compound in compounds:
		if not compound.begins_with(".") and not compound.begins_with("#"):
			types += 1
	return ids * 100 + classes * 10 + types


static func _parse_selector(selector: String, source: String, offset: int, diagnostics: Array[Dictionary]) -> Dictionary:
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
				diagnostics.append(_diagnostic(source, offset + index, "Direct-child combinator requires a selector on its left."))
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
		diagnostics.append(_diagnostic(source, offset, "Selector ends with a combinator."))
		return {"compounds": PackedStringArray(), "combinators": PackedStringArray()}
	return {"compounds": compounds, "combinators": combinators}


static func _strip_comments(source: String) -> String:
	var result := PackedStringArray()
	var cursor := 0
	while cursor < source.length():
		if cursor + 1 >= source.length() or source.substr(cursor, 2) != "/*":
			result.append(source[cursor])
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


static func _diagnostic(source: String, offset: int, message: String, severity: String = "error") -> Dictionary:
	var safe_offset := clampi(offset, 0, source.length())
	var prefix := source.substr(0, safe_offset)
	var last_newline := prefix.rfind("\n")
	return {
		"severity": severity,
		"line": prefix.count("\n") + 1,
		"column": safe_offset + 1 if last_newline < 0 else safe_offset - last_newline,
		"message": message,
	}
