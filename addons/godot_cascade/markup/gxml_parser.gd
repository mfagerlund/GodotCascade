extends RefCounted

## Focused XML parser for GodotCascade markup.


class Element:
	extends RefCounted

	var tag_name := ""
	var attributes: Dictionary = {}
	var text := ""
	var children: Array[Element] = []
	var _parent_ref: WeakRef


	func _init(element_tag := "", element_parent: Element = null) -> void:
		tag_name = element_tag
		if element_parent != null:
			_parent_ref = weakref(element_parent)


	func element_id() -> String:
		return str(attributes.get("id", ""))


	func classes() -> PackedStringArray:
		var value := str(attributes.get("class", "")).strip_edges()
		return PackedStringArray() if value.is_empty() else value.split(" ", false)


	func parent_element() -> Element:
		return null if _parent_ref == null else _parent_ref.get_ref()


static func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var xml := XMLParser.new()
	var open_error := xml.open_buffer(source.to_utf8_buffer())
	if open_error != OK:
		return {
			"root": null,
			"diagnostics": [_diagnostic(source, 0, "Could not open GXML source.")],
		}

	var root_element: Element
	var stack: Array[Element] = []
	var read_error := xml.read()
	while read_error == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var parent: Element = stack.back() if not stack.is_empty() else null
				var element := Element.new(xml.get_node_name(), parent)
				for index in xml.get_attribute_count():
					element.attributes[xml.get_attribute_name(index)] = xml.get_attribute_value(index)

				if parent != null:
					parent.children.append(element)
				elif root_element == null:
					root_element = element
				else:
					diagnostics.append(_diagnostic(
						source,
						xml.get_node_offset(),
						"GXML documents must contain exactly one root element."
					))

				if not xml.is_empty():
					stack.append(element)

			XMLParser.NODE_ELEMENT_END:
				var closing_name := xml.get_node_name()
				if stack.is_empty():
					diagnostics.append(_diagnostic(
						source,
						xml.get_node_offset(),
						"Unexpected closing tag </%s>." % closing_name
					))
				elif stack.back().tag_name != closing_name:
					diagnostics.append(_diagnostic(
						source,
						xml.get_node_offset(),
						"Expected </%s> before </%s>." % [stack.back().tag_name, closing_name]
					))
					while not stack.is_empty() and stack.back().tag_name != closing_name:
						stack.pop_back()
					if not stack.is_empty():
						stack.pop_back()
				else:
					stack.pop_back()

			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if not stack.is_empty():
					stack.back().text += xml.get_node_data()

		read_error = xml.read()

	if read_error != ERR_FILE_EOF:
		diagnostics.append(_diagnostic(
			source,
			xml.get_node_offset(),
			"Malformed GXML near byte %s (error %s)." % [xml.get_node_offset(), read_error]
		))
	if not stack.is_empty():
		diagnostics.append(_diagnostic(
			source,
			source.length(),
			"Unclosed element <%s>." % stack.back().tag_name
		))
	if root_element == null:
		diagnostics.append(_diagnostic(source, 0, "GXML document contains no root element."))

	_normalize_text(root_element)
	return {"root": root_element, "diagnostics": diagnostics}


static func _normalize_text(element: Element) -> void:
	if element == null:
		return
	var lines := element.text.replace("\r", "").split("\n")
	var normalized: PackedStringArray = []
	for line in lines:
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			normalized.append(trimmed)
	element.text = " ".join(normalized)
	for child in element.children:
		_normalize_text(child)


static func _diagnostic(source: String, offset: int, message: String) -> Dictionary:
	var safe_offset := clampi(offset, 0, source.length())
	var prefix := source.substr(0, safe_offset)
	var last_newline := prefix.rfind("\n")
	return {
		"severity": "error",
		"line": prefix.count("\n") + 1,
		"column": safe_offset + 1 if last_newline < 0 else safe_offset - last_newline,
		"message": message,
	}
