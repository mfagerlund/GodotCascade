@tool
extends RefCounted

## Editor-neutral focused language features for GXML and GCSS.

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")

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

const GLOBAL_ATTRIBUTES := {
	"id": "Stable scoped identity and #selector target.",
	"class": "Whitespace-separated selector classes or an exact bound class path.",
	"visible": "Literal or one-way boolean visibility.",
	"disabled": "Literal or one-way disabled state.",
	"accessible-label": "Native accessibility name.",
	"accessible-description": "Native accessibility description.",
	"if": "Exact boolean path controlling conditional construction.",
	"tab-index": "Sequential focus order: positive first, 0/source order, -1 excluded.",
	"autofocus": "Focus on initial mount or newly activated trap.",
	"focus-trap": "Modal focus scope on a container.",
}

const ELEMENT_ATTRIBUTES := {
	"Button": ["on-pressed"], "Checkbox": ["checked", "bind-checked", "on-toggled"],
	"RadioButton": ["checked", "bind-checked", "group", "on-toggled"],
	"Switch": ["checked", "bind-checked", "on-toggled"],
	"Select": ["selected", "bind-selected", "on-selection-changed"],
	"Option": ["value", "disabled"], "Slider": ["min", "max", "value", "step", "bind-value"],
	"Progress": ["min", "max", "value"], "TextInput": ["text", "bind-text", "placeholder", "multiline", "read-only", "secret", "required", "pattern", "error-message", "max-length"],
	"Image": ["src"], "Repeat": ["items", "key"],
	"Component": ["name"], "Param": ["name", "type", "required", "default"], "Slot": ["name"],
	"Bindings": ["class", "namespace", "document", "output"], "Binding": ["name", "type", "get", "set", "format", "parse"],
	"Formatter": ["name", "input", "output"], "Parser": ["name", "input", "output"], "Using": ["namespace"],
}

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
		var component_pattern := RegEx.new()
		component_pattern.compile("<Component\\s+[^>]*name=[\\\"']%s[\\\"']" % _regex_escape(word))
		var match := component_pattern.search(source)
		if match != null: target_offset = match.get_start()
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
	elif extension.to_lower().ends_with("gxml") and old_name.left(1).to_upper() == old_name.left(1):
		return _component_rename_edits(source, old_name, new_name)
	else:
		return []
	var edits: Array[Dictionary] = []
	for match in safe.search_all(source):
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
	var last_open := before.rfind("<")
	var last_close := before.rfind(">")
	var result: Array[Dictionary] = []
	if last_open <= last_close or before.ends_with("<") or before.substr(last_open + 1).find(" ") < 0:
		for name in ELEMENTS:
			result.append({"label": name, "insert": name, "documentation": ELEMENTS[name], "kind": "element"})
		return result
	var tag_fragment := before.substr(last_open + 1)
	var tag := tag_fragment.get_slice(" ", 0).strip_edges().trim_prefix("/")
	for name in GLOBAL_ATTRIBUTES:
		result.append({"label": name, "insert": name + "=\"\"", "documentation": GLOBAL_ATTRIBUTES[name], "kind": "attribute"})
	for name in ELEMENT_ATTRIBUTES.get(tag, []):
		result.append({"label": name, "insert": name + "=\"\"", "documentation": "Supported %s attribute." % tag, "kind": "attribute"})
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
	_collect_component_names(parsed.get("root"), custom)
	_validate_element(parsed.get("root"), custom, result)
	return result


static func _collect_component_names(element, result: Dictionary) -> void:
	if element == null: return
	if element.tag_name.to_lower() == "component": result[str(element.attributes.get("name", ""))] = true
	for child in element.children: _collect_component_names(child, result)


static func _validate_element(element, custom: Dictionary, result: Array[Dictionary]) -> void:
	if element == null: return
	if not ELEMENTS.has(element.tag_name) and not custom.has(element.tag_name):
		result.append({"severity": "error", "message": "Unknown GXML element <%s>." % element.tag_name, "line": element.source_line, "column": element.source_column})
	for child in element.children: _validate_element(child, custom, result)


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
	var token_pattern := RegEx.new()
	token_pattern.compile("<!--[\\s\\S]*?-->|<[^>]+>|[^<]+")
	var lines := PackedStringArray()
	var depth := 0
	for match in token_pattern.search_all(source):
		var token := match.get_string().strip_edges()
		if token.is_empty(): continue
		if token.begins_with("</"): depth = maxi(depth - 1, 0)
		lines.append("    ".repeat(depth) + token)
		if token.begins_with("<") and not token.begins_with("</") and not token.begins_with("<!--") and not token.begins_with("<?") and not token.ends_with("/>") and not ("</" in token): depth += 1
	return "\n".join(lines) + ("\n" if source.ends_with("\n") else "")


static func _format_gcss(source: String) -> String:
	if "@media" in source.to_lower():
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


static func _component_rename_edits(source: String, old_name: String, new_name: String) -> Array[Dictionary]:
	if not new_name.is_valid_identifier() or new_name.left(1).to_upper() != new_name.left(1):
		return []
	var edits: Array[Dictionary] = []
	var tag_pattern := RegEx.new()
	tag_pattern.compile("</?%s(?=[\\s>/])" % _regex_escape(old_name))
	for match in tag_pattern.search_all(source):
		var start := match.get_start() + (2 if match.get_string().begins_with("</") else 1)
		edits.append({"start": start, "end": start + old_name.length(), "new_text": new_name})
	var component_pattern := RegEx.new()
	component_pattern.compile("<Component\\s+[^>]*>")
	for component_match in component_pattern.search_all(source):
		var tag := component_match.get_string()
		var name_pattern := RegEx.new()
		name_pattern.compile("name=[\\\"']%s[\\\"']" % _regex_escape(old_name))
		var name_match := name_pattern.search(tag)
		if name_match != null:
			var value_start := component_match.get_start() + name_match.get_start() + "name=\"".length()
			edits.append({"start": value_start, "end": value_start + old_name.length(), "new_text": new_name})
	return edits


static func _word_character(character: String) -> bool:
	return character.to_lower() != character.to_upper() or character.is_valid_int() or character in ["_", "-"]
