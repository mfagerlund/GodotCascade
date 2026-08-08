@tool
extends RefCounted

## Editor-neutral focused language features for GXML and GCSS.

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const GxmlSchema := preload("res://addons/godot_cascade/runtime/gxml_schema.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")

const ELEMENTS := {
	"Page": "Root flex column and document surface.",
	"Row": "Native horizontal CascadeBox.",
	"Column": "Native vertical CascadeBox.",
	"Panel": "Semantic styled flex container.",
	"Stack": "Overlay and absolute-position container.",
	"Grid": "Native fixed/content/fraction track grid.",
	"Label": "Owned text and box-model control.",
	"Button": "Owned native BaseButton control.",
	"Checkbox": "Toggle button with checkbox indicator.",
	"RadioButton": "Grouped exclusive toggle control.",
	"Switch": "Checkbox semantics with switch drawing.",
	"Select": "Owned select with native popup.",
	"Option": "Select option declaration.",
	"Slider": "Native Range with owned track/thumb.",
	"Progress": "Owned range display.",
	"TextInput": "Native single- or multiline text editor adapter.",
	"Image": "Godot Texture2D, including imported SVG.",
	"Scroll": "Native ScrollContainer viewport.",
	"Table": "Semantic table with shared tracks.",
	"TableHeader": "Semantic table header group.",
	"TableBody": "Semantic table body group.",
	"TableRow": "Semantic shared-track row.",
	"TableHeaderCell": "Semantic column-header cell.",
	"TableCell": "Owned table cell.",
	"Repeat": "Keyed repeated child template.",
	"Component": "Reusable source-level component definition.",
	"Param": "Typed component parameter declaration.",
	"Slot": "Default or named component insertion point.",
	"Bindings": "Non-visual typed C# binding contract.",
	"Binding": "Typed C# getter/setter declaration.",
	"Formatter": "Verbatim C# output formatter body.",
	"Parser": "Verbatim C# input parser body.",
	"Using": "Generated C# using namespace.",
}
const ELEMENT_ALIASES := GxmlSchema.ALIASES

const GLOBAL_ATTRIBUTES := {
	"id": "Stable scoped identity and #selector target.",
	"class": "Whitespace-separated selector classes or an exact bound class path.",
	"visible": "Literal or one-way boolean visibility.",
	"accessible-label": "Native accessibility name.",
	"accessible-description": "Native accessibility description.",
	"if": "Exact boolean path controlling conditional construction.",
	"tab-index": "Sequential focus order: positive first, 0/source order, -1 excluded.",
	"autofocus": "Focus on initial mount or newly activated trap.",
	"focus-trap": "Modal focus scope on an authored control subtree.",
	"slot": "Named insertion target on component-instance children.",
}

const ELEMENT_ATTRIBUTES := GxmlSchema.ELEMENT_ATTRIBUTES
const GENERATED_BINDING_ATTRIBUTES := GxmlSchema.GENERATED_BINDING_ATTRIBUTES

const PROPERTIES := {
	"display": "Focused flex display; only `flex` is accepted.",
	"flex-direction": "Main axis: row or column.", "flex-wrap": "wrap or nowrap.",
	"flex-grow": "Non-negative positive free-space factor.", "flex-shrink": "Explicit weighted negative free-space factor.",
	"flex-basis": "Main-axis base length or auto.", "justify-content": "Main-axis distribution.",
	"align-items": "Cross-axis alignment.", "align-self": "Per-item cross-axis override.",
	"gap": "Row and optional column gap.", "row-gap": "Row/line gap.", "column-gap": "Column/main gap.",
	"padding": "One-to-four non-negative lengths.", "padding-left": "Left padding.", "padding-top": "Top padding.", "padding-right": "Right padding.", "padding-bottom": "Bottom padding.",
	"margin": "One-to-four non-negative lengths.", "margin-left": "Left margin.", "margin-top": "Top margin.", "margin-right": "Right margin.", "margin-bottom": "Bottom margin.",
	"width": "Preferred width.", "height": "Preferred height.", "min-width": "Minimum width.", "min-height": "Minimum height.", "max-width": "Maximum width.", "max-height": "Maximum height.",
	"background": "Solid color or focused two-stop linear-gradient().", "background-color": "Solid box background.",
	"border": "<length> solid <color>.", "border-color": "Box border color.", "border-width": "Box border width.", "border-radius": "Uniform corner radius.",
	"overflow": "visible, clip, or hidden.", "opacity": "Descendant modulation from 0 to 1.",
	"transform": "Focused translate/rotate/scale using Godot offset transforms.", "transform-origin": "center or horizontal/vertical keyword pair.",
	"color": "Text color; inherited.", "font-size": "Text size; inherited.", "font-source": "Inherited project-local Godot Font resource.",
	"fill-color": "Progress/slider fill color.", "object-fit": "contain, cover, fill, or none.",
	"position": "relative or absolute within Stack.", "left": "Absolute left inset.", "top": "Absolute top inset.", "right": "Absolute right inset.", "bottom": "Absolute bottom inset.",
	"grid-template-columns": "Fixed/content/fr/minmax columns.", "grid-template-rows": "Fixed/content/fr/minmax rows.", "grid-column": "One-based start and optional span.", "grid-row": "One-based start and optional span.",
	"transition": "Property and time.", "transition-property": "Comma-separated supported property names.", "transition-duration": "Time in ms or s.",
}

const PSEUDO_STATES := ["hover", "pressed", "checked", "focused", "focus-visible", "disabled", "selected", "open", "invalid"]


static func completions(source: String, offset: int, extension: String) -> Array[Dictionary]:
	return _gcss_completions(source, offset) if extension.to_lower().ends_with("gcss") else _gxml_completions(source, offset)


static func hover(source: String, offset: int, extension: String) -> Dictionary:
	var word := word_at(source, offset)
	if extension.to_lower().ends_with("gcss"):
		var normalized := word.trim_prefix(":")
		if PROPERTIES.has(normalized): return {"symbol": normalized, "documentation": PROPERTIES[normalized]}
		if normalized in PSEUDO_STATES: return {"symbol": ":" + normalized, "documentation": "Supported native pseudo state resolved during build."}
		if normalized.begins_with("--"): return {"symbol": normalized, "documentation": "Case-sensitive cascading custom property."}
	else:
		if ELEMENTS.has(word): return {"symbol": word, "documentation": ELEMENTS[word]}
		if GLOBAL_ATTRIBUTES.has(word): return {"symbol": word, "documentation": GLOBAL_ATTRIBUTES[word]}
		for values in ELEMENT_ATTRIBUTES.values():
			if word in values: return {"symbol": word, "documentation": "Supported `%s` attribute." % word}
	return {}


static func diagnostics(source: String, extension: String) -> Array[Dictionary]:
	return _gcss_diagnostics(source) if extension.to_lower().ends_with("gcss") else _gxml_diagnostics(source)


static func format(source: String, extension: String) -> String:
	if "<![CDATA[" in source:
		return source
	return _format_gcss(source) if extension.to_lower().ends_with("gcss") else _format_gxml(source)


static func definition(source: String, offset: int, extension: String, path: String = "") -> Dictionary:
	var word := word_at(source, offset)
	if word.is_empty(): return {}
	var target_offset := -1
	if extension.to_lower().ends_with("gcss") and word.begins_with("--"):
		target_offset = source.find(word + ":")
	elif extension.to_lower().ends_with("gxml"):
		var parsed := GxmlParser.parse(source)
		var declaration = _find_component_declaration(parsed.get("root"), word)
		if declaration != null:
			target_offset = declaration.source_offset
	if target_offset < 0: return {}
	var location := _location(source, target_offset)
	location["path"] = path
	return location


static func rename(source: String, offset: int, new_name: String, extension: String) -> Array[Dictionary]:
	var old_name := word_at(source, offset)
	if old_name.is_empty() or new_name.is_empty(): return []
	var safe := RegEx.new()
	if old_name.begins_with("--"):
		if not new_name.begins_with("--"): return []
		safe.compile("(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-])" % _regex_escape(old_name))
	elif extension.to_lower().ends_with("gxml"):
		return _component_rename_edits(source, offset, old_name, new_name)
	else:
		return []
	var edits: Array[Dictionary] = []
	var searchable := _mask_gcss_comments_and_strings(source) if old_name.begins_with("--") else source
	for match in safe.search_all(searchable):
		edits.append({"start": match.get_start(), "end": match.get_end(), "new_text": new_name})
	return edits


static func apply_edits(source: String, edits: Array[Dictionary]) -> String:
	var ordered := edits.duplicate(true)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary): return int(left["start"]) > int(right["start"]))
	var result := source
	for edit in ordered:
		result = result.substr(0, int(edit["start"])) + str(edit["new_text"]) + result.substr(int(edit["end"]))
	return result


static func word_at(source: String, offset: int) -> String:
	if source.is_empty(): return ""
	var cursor := clampi(offset, 0, source.length() - 1)
	if not _word_character(source[cursor]) and cursor > 0: cursor -= 1
	var start := cursor
	var end := cursor + 1
	while start > 0 and _word_character(source[start - 1]): start -= 1
	while end < source.length() and _word_character(source[end]): end += 1
	return source.substr(start, end - start)


static func _gxml_completions(source: String, offset: int) -> Array[Dictionary]:
	var before := source.substr(0, clampi(offset, 0, source.length()))
	var last_open := _open_gxml_tag_start(before)
	var result: Array[Dictionary] = []
	if last_open < 0 or before.ends_with("<") or before.substr(last_open + 1).find(" ") < 0:
		for name in ELEMENTS:
			result.append({"label": name, "insert": name, "documentation": ELEMENTS[name], "kind": "element"})
		return result
	var tag_fragment := before.substr(last_open + 1)
	var tag := tag_fragment.get_slice(" ", 0).strip_edges().trim_prefix("/")
	for name in GxmlSchema.attributes_for(tag):
		if name == "focus-trap" and GxmlSchema.is_builtin(tag) and not GxmlSchema.supports_focus_trap(tag):
			continue
		var documentation := GLOBAL_ATTRIBUTES.get(name, "Supported %s attribute." % tag)
		result.append({"label": name, "insert": name + "=\"\"", "documentation": documentation, "kind": "attribute"})
	if GxmlSchema.supports_generated_bindings(tag):
		for name in GENERATED_BINDING_ATTRIBUTES:
			result.append({"label": name, "insert": name + "=\"\"", "documentation": "Named generated-binding formatter or parser.", "kind": "attribute"})
	return result


static func _gcss_completions(source: String, offset: int) -> Array[Dictionary]:
	var before := source.substr(0, clampi(offset, 0, source.length()))
	var brace := before.rfind("{")
	var close := before.rfind("}")
	var result: Array[Dictionary] = []
	if brace > close:
		var colon := before.rfind(":")
		var semicolon := before.rfind(";")
		if colon > maxi(brace, semicolon):
			for value in ["inherit", "auto", "none", "row", "column", "center", "start", "end", "stretch", "visible", "clip"]:
				result.append({"label": value, "insert": value, "documentation": "Supported focused GCSS value.", "kind": "value"})
		else:
			for name in PROPERTIES:
				result.append({"label": name, "insert": name + ": ", "documentation": PROPERTIES[name], "kind": "property"})
	else:
		for state in PSEUDO_STATES:
			result.append({"label": ":" + state, "insert": ":" + state, "documentation": "Supported native pseudo state.", "kind": "pseudo"})
	return result


static func _gxml_diagnostics(source: String) -> Array[Dictionary]:
	var parsed := GxmlParser.parse(source)
	var result: Array[Dictionary] = parsed["diagnostics"].duplicate(true)
	var custom := {}
	var document_root = parsed.get("root")
	_collect_component_names(document_root, custom)
	_validate_document_root(document_root, result)
	_validate_element(document_root, custom, result)
	return result


static func _collect_component_names(element, result: Dictionary) -> void:
	if element == null: return
	if element.tag_name.to_lower() == "component": result[str(element.attributes.get("name", "")).to_lower()] = true
	for child in element.children: _collect_component_names(child, result)


static func _validate_element(element, custom: Dictionary, result: Array[Dictionary]) -> void:
	if element == null: return
	var normalized: String = str(element.tag_name).to_lower()
	if not _is_known_element(normalized) and not custom.has(normalized) and not ComponentRegistry.has(normalized):
		result.append({"severity": "error", "message": "Unknown GXML element <%s>." % element.tag_name, "line": element.source_line, "column": element.source_column})
	for attribute_name_value in element.attributes:
		var attribute_name := str(attribute_name_value)
		if attribute_name.begins_with("__") or (GxmlSchema.is_builtin(element.tag_name) and not GxmlSchema.is_attribute_allowed(element.tag_name, attribute_name)):
			result.append({"severity": "error", "message": "Unknown attribute '%s' on <%s>." % [attribute_name, element.tag_name], "line": element.source_line, "column": element.source_column})
	if _attribute_is_true(element, "focus-trap") and GxmlSchema.is_builtin(element.tag_name) and not GxmlSchema.supports_focus_trap(element.tag_name):
		result.append({"severity": "error", "message": "Attribute 'focus-trap' requires an element backed by a native Container.", "line": element.source_line, "column": element.source_column})
	if normalized == "repeat" and _attribute_is_true(element, "virtual") and not element.children.is_empty():
		var item_root = element.children[0]
		if item_root.attributes.has("if"):
			result.append({"severity": "error", "message": "Virtual Repeat item roots cannot use 'if'; filter the collection model instead.", "line": item_root.source_line, "column": item_root.source_column})
		if item_root.attributes.has("visible") and not _literal_is_true(str(item_root.attributes["visible"])):
			result.append({"severity": "error", "message": "Virtual Repeat item roots cannot use conditional 'visible'; filter the collection model instead.", "line": item_root.source_line, "column": item_root.source_column})
	for child in element.children: _validate_element(child, custom, result)


static func _validate_document_root(element, result: Array[Dictionary]) -> void:
	if element == null:
		return
	var canonical := GxmlSchema.canonical_element(element.tag_name)
	if canonical in GxmlSchema.NON_VISUAL_ELEMENTS:
		result.append({"severity": "error", "message": "The document root must be visual; <%s> is a non-visual declaration element." % element.tag_name, "line": element.source_line, "column": element.source_column})
	if element.attributes.has("if"):
		result.append({"severity": "error", "message": "The document root cannot use 'if'; bind 'visible' or put the conditional on a child element.", "line": element.source_line, "column": element.source_column})


static func _attribute_is_true(element, attribute_name: String) -> bool:
	if not element.attributes.has(attribute_name):
		return false
	return str(element.attributes[attribute_name]).strip_edges().to_lower() in ["true", "1", "yes", "on", attribute_name]


static func _literal_is_true(value: String) -> bool:
	return value.strip_edges().to_lower() in ["true", "1", "yes", "on", "visible"]


static func _gcss_diagnostics(source: String) -> Array[Dictionary]:
	var parsed := GcssParser.parse(source)
	var result: Array[Dictionary] = parsed["diagnostics"].duplicate(true)
	for rule in parsed["rules"]:
		for property_name in rule.declarations:
			if not str(property_name).begins_with("--") and not PROPERTIES.has(property_name):
				var location: Dictionary = rule.declaration_locations.get(property_name, {"line": rule.line, "column": 1})
				result.append({"severity": "warning", "message": "Unsupported GCSS property '%s'." % property_name, "line": location.get("line", 1), "column": location.get("column", 1)})
	return result


static func _format_gxml(source: String) -> String:
	var tokens := _gxml_tokens(source)
	if tokens.is_empty() and not source.strip_edges().is_empty():
		return source
	var lines := PackedStringArray()
	var depth := 0
	for raw_token in tokens:
		var token := str(raw_token).strip_edges()
		if token.is_empty(): continue
		if token.begins_with("</"): depth = maxi(depth - 1, 0)
		lines.append("    ".repeat(depth) + token)
		if token.begins_with("<") and not token.begins_with("</") and not token.begins_with("<!--") and not token.begins_with("<?") and not token.ends_with("/>") and not ("</" in token): depth += 1
	return "\n".join(lines) + ("\n" if source.ends_with("\n") else "")


static func _format_gcss(source: String) -> String:
	if "@media" in source.to_lower() or "/*" in source:
		return source
	var parsed := GcssParser.parse(source)
	if parsed["diagnostics"].any(func(entry): return entry.get("severity", "error") == "error"):
		return source
	var blocks := PackedStringArray()
	for rule in parsed["rules"]:
		var lines := PackedStringArray([str(rule.selector) + " {"])
		for property_name in rule.declarations:
			lines.append("    %s: %s;" % [property_name, rule.declarations[property_name]])
		lines.append("}")
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks) + ("\n" if source.ends_with("\n") else "")


static func _location(source: String, offset: int) -> Dictionary:
	var prefix := source.substr(0, offset)
	var line := prefix.count("\n") + 1
	var newline := prefix.rfind("\n")
	return {"offset": offset, "line": line, "column": offset - newline}


static func _regex_escape(value: String) -> String:
	var result := value
	for character in ["\\", ".", "+", "*", "?", "^", "$", "(", ")", "[", "]", "{", "}", "|"]:
		result = result.replace(character, "\\" + character)
	return result


static func _component_rename_edits(source: String, target_offset: int, old_name: String, new_name: String) -> Array[Dictionary]:
	if GxmlSchema.is_builtin(old_name) or GxmlSchema.is_builtin(new_name):
		return []
	if not new_name.is_valid_identifier() or new_name.left(1).to_upper() != new_name.left(1):
		return []
	var parsed := GxmlParser.parse(source)
	var declaration = _find_component_declaration(parsed.get("root"), old_name)
	if declaration == null:
		return []
	var declaration_offset := int(declaration.source_offset)
	var edits: Array[Dictionary] = []
	var declaration_edit_added := false
	var target_is_component := false
	var tag_pattern := RegEx.new()
	tag_pattern.compile("(?i)^</?%s(?=[\\s>/])" % _regex_escape(old_name))
	for token_entry in _gxml_token_ranges(source):
		var tag := str(token_entry["text"])
		var match := tag_pattern.search(tag)
		if match != null:
			var start := int(token_entry["start"]) + match.get_start() + (2 if match.get_string().begins_with("</") else 1)
			edits.append({"start": start, "end": start + old_name.length(), "new_text": new_name})
			if target_offset >= start and target_offset <= start + old_name.length():
				target_is_component = true
		if int(token_entry["start"]) == declaration_offset:
			var value_range := _tag_attribute_value_range(tag, "name")
			if value_range.is_empty():
				return []
			var value_start := declaration_offset + int(value_range["start"])
			var value_end := declaration_offset + int(value_range["end"])
			edits.append({"start": value_start, "end": value_end, "new_text": new_name})
			if target_offset >= value_start and target_offset <= value_end:
				target_is_component = true
			declaration_edit_added = true
	return edits if declaration_edit_added and target_is_component else []


static func _tag_attribute_value_range(tag: String, wanted_name: String) -> Dictionary:
	var cursor := 1
	if cursor < tag.length() and tag[cursor] == "/":
		cursor += 1
	while cursor < tag.length() and tag[cursor] not in [" ", "\t", "\r", "\n", "/", ">"]:
		cursor += 1
	while cursor < tag.length():
		while cursor < tag.length() and tag[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
		if cursor >= tag.length() or tag[cursor] in ["/", ">"]:
			break
		var name_start := cursor
		while cursor < tag.length() and tag[cursor] not in [" ", "\t", "\r", "\n", "=", "/", ">"]:
			cursor += 1
		var attribute_name := tag.substr(name_start, cursor - name_start)
		while cursor < tag.length() and tag[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
		if cursor >= tag.length() or tag[cursor] != "=":
			continue
		cursor += 1
		while cursor < tag.length() and tag[cursor] in [" ", "\t", "\r", "\n"]:
			cursor += 1
		if cursor >= tag.length() or tag[cursor] not in ["\"", "'"]:
			continue
		var quote := tag[cursor]
		var value_start := cursor + 1
		var value_end := tag.find(quote, value_start)
		if value_end < 0:
			return {}
		cursor = value_end + 1
		if attribute_name.to_lower() == wanted_name.to_lower():
			return {"start": value_start, "end": value_end}
	return {}


static func _find_component_declaration(element, component_name: String):
	if element == null:
		return null
	if element.tag_name.to_lower() == "component" and str(element.attributes.get("name", "")).to_lower() == component_name.to_lower():
		return element
	for child in element.children:
		var found = _find_component_declaration(child, component_name)
		if found != null:
			return found
	return null


static func _is_known_element(normalized: String) -> bool:
	if ELEMENT_ALIASES.has(normalized):
		return true
	for name in ELEMENTS:
		if str(name).to_lower() == normalized:
			return true
	return false


static func _gxml_tokens(source: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	for entry in _gxml_token_ranges(source):
		tokens.append(str(entry["text"]))
	return tokens


static func _gxml_token_ranges(source: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var cursor := 0
	while cursor < source.length():
		var opening := source.find("<", cursor)
		if opening < 0:
			tokens.append({"text": source.substr(cursor), "start": cursor, "end": source.length()})
			break
		if opening > cursor:
			tokens.append({"text": source.substr(cursor, opening - cursor), "start": cursor, "end": opening})
		var ending := -1
		if source.substr(opening, 9) == "<![CDATA[":
			var cdata_end := source.find("]]>", opening + 9)
			if cdata_end >= 0:
				ending = cdata_end + 3
		elif source.substr(opening, 4) == "<!--":
			var comment_end := source.find("-->", opening + 4)
			if comment_end >= 0:
				ending = comment_end + 3
		else:
			var quote := ""
			var index := opening + 1
			while index < source.length():
				var character := source[index]
				if not quote.is_empty():
					if character == quote:
						quote = ""
				elif character in ["\"", "'"]:
					quote = character
				elif character == ">":
					ending = index + 1
					break
				index += 1
		if ending < 0:
			return []
		tokens.append({"text": source.substr(opening, ending - opening), "start": opening, "end": ending})
		cursor = ending
	return tokens


static func _open_gxml_tag_start(source: String) -> int:
	var tag_start := -1
	var quote := ""
	var in_comment := false
	var index := 0
	while index < source.length():
		if in_comment:
			var comment_end := source.find("-->", index)
			if comment_end < 0:
				return -1
			index = comment_end + 3
			in_comment = false
			continue
		if tag_start < 0 and source.substr(index, 4) == "<!--":
			in_comment = true
			index += 4
			continue
		var character := source[index]
		if tag_start < 0:
			if character == "<":
				tag_start = index
		elif not quote.is_empty():
			if character == quote:
				quote = ""
		elif character in ["\"", "'"]:
			quote = character
		elif character == ">":
			tag_start = -1
		index += 1
	return tag_start


static func _mask_gcss_comments_and_strings(source: String) -> String:
	var masked := source
	var index := 0
	var quote := ""
	var in_comment := false
	while index < masked.length():
		var character := masked[index]
		var next := masked[index + 1] if index + 1 < masked.length() else ""
		if in_comment:
			if character == "*" and next == "/":
				masked[index] = " "
				masked[index + 1] = " "
				index += 2
				in_comment = false
				continue
			if character != "\n":
				masked[index] = " "
		elif not quote.is_empty():
			if character == "\\":
				masked[index] = " "
				if index + 1 < masked.length() and masked[index + 1] != "\n":
					masked[index + 1] = " "
				index += 2
				continue
			if character == quote:
				quote = ""
			if character != "\n":
				masked[index] = " "
		elif character == "/" and next == "*":
			masked[index] = " "
			masked[index + 1] = " "
			index += 2
			in_comment = true
			continue
		elif character in ["\"", "'"]:
			quote = character
			masked[index] = " "
		index += 1
	return masked


static func _word_character(character: String) -> bool:
	return character.to_lower() != character.to_upper() or character.is_valid_int() or character in ["_", "-"]
