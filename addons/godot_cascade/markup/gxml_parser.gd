extends RefCounted

## Focused XML parser for GodotCascade markup.


class Element:
	extends RefCounted

	var tag_name := ""
	var attributes: Dictionary = {}
	var text := ""
	var raw_text := ""
	var children: Array[Element] = []
	var source_offset := 0
	var source_line := 1
	var source_column := 1
	var _parent_ref: WeakRef


	func _init(element_tag := "", element_parent: Element = null) -> void:
		tag_name = element_tag
		if element_parent != null:
			_parent_ref = weakref(element_parent)


	func element_id() -> String:
		return str(attributes.get("id", ""))


	func classes() -> PackedStringArray:
		var value := str(attributes.get("class", "")).replace("\t", " ").replace("\r", " ").replace("\n", " ").strip_edges()
		return PackedStringArray() if value.is_empty() else value.split(" ", false)


	func parent_element() -> Element:
		return null if _parent_ref == null else _parent_ref.get_ref()


static func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var line_starts := _line_starts(source)
	var byte_to_character := _utf8_byte_to_character_offsets(source)
	var xml := XMLParser.new()
	var open_error := xml.open_buffer(source.to_utf8_buffer())
	if open_error != OK:
		return {
			"root": null,
			"diagnostics": [_diagnostic(source, 0, "Could not open GXML source.", line_starts)],
		}

	var root_element: Element
	var stack: Array[Element] = []
	var read_error := xml.read()
	while read_error == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var parent: Element = stack.back() if not stack.is_empty() else null
				var element := Element.new(xml.get_node_name(), parent)
				element.source_offset = _character_offset(byte_to_character, xml.get_node_offset())
				var location := _diagnostic(source, element.source_offset, "", line_starts)
				element.source_line = location["line"]
				element.source_column = location["column"]
				for index in xml.get_attribute_count():
					element.attributes[xml.get_attribute_name(index)] = xml.get_attribute_value(index)

				if parent != null:
					parent.children.append(element)
				elif root_element == null:
					root_element = element
				else:
					diagnostics.append(_diagnostic(
						source,
						_character_offset(byte_to_character, xml.get_node_offset()),
						"GXML documents must contain exactly one root element.",
						line_starts
					))

				if not xml.is_empty():
					stack.append(element)

			XMLParser.NODE_ELEMENT_END:
				var closing_name := xml.get_node_name()
				if stack.is_empty():
					diagnostics.append(_diagnostic(
						source,
						_character_offset(byte_to_character, xml.get_node_offset()),
						"Unexpected closing tag </%s>." % closing_name,
						line_starts
					))
				elif stack.back().tag_name != closing_name:
					diagnostics.append(_diagnostic(
						source,
						_character_offset(byte_to_character, xml.get_node_offset()),
						"Expected </%s> before </%s>." % [stack.back().tag_name, closing_name],
						line_starts
					))
					while not stack.is_empty() and stack.back().tag_name != closing_name:
						stack.pop_back()
					if not stack.is_empty():
						stack.pop_back()
				else:
					stack.pop_back()

			XMLParser.NODE_TEXT:
				if not stack.is_empty():
					var node_text := xml.get_node_data()
					stack.back().text += node_text
					stack.back().raw_text += node_text

			XMLParser.NODE_CDATA:
				if not stack.is_empty():
					var cdata_text := _cdata_content(source, _character_offset(byte_to_character, xml.get_node_offset()))
					stack.back().text += cdata_text
					stack.back().raw_text += cdata_text

		read_error = xml.read()

	if read_error != ERR_FILE_EOF:
		diagnostics.append(_diagnostic(
			source,
			_character_offset(byte_to_character, xml.get_node_offset()),
			"Malformed GXML near byte %s (error %s)." % [xml.get_node_offset(), read_error],
			line_starts
		))
	if not stack.is_empty():
		diagnostics.append(_diagnostic(
			source,
			source.length(),
			"Unclosed element <%s>." % stack.back().tag_name,
			line_starts
		))
	if root_element == null:
		diagnostics.append(_diagnostic(source, 0, "GXML document contains no root element.", line_starts))

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


static func _utf8_byte_to_character_offsets(source: String) -> PackedInt32Array:
	var source_bytes := source.to_utf8_buffer()
	var offsets := PackedInt32Array()
	offsets.resize(source_bytes.size() + 1)
	var byte_offset := 0
	var character_offset := 0
	for character in source:
		var character_bytes := character.to_utf8_buffer().size()
		for index in character_bytes:
			offsets[byte_offset + index] = character_offset
		byte_offset += character_bytes
		character_offset += 1
		offsets[byte_offset] = character_offset
	return offsets


static func _character_offset(byte_to_character: PackedInt32Array, byte_offset: int) -> int:
	return byte_to_character[clampi(byte_offset, 0, byte_to_character.size() - 1)]


static func _cdata_content(source: String, offset: int) -> String:
	var opening := source.rfind("<![CDATA[", clampi(offset, 0, source.length()))
	if opening < 0:
		return ""
	var content_start := opening + 9
	var closing := source.find("]]>", content_start)
	if closing < 0:
		return source.substr(content_start)
	return source.substr(content_start, closing - content_start)


static func _line_starts(source: String) -> PackedInt32Array:
	var result := PackedInt32Array([0])
	var cursor := source.find("\n")
	while cursor >= 0:
		result.append(cursor + 1)
		cursor = source.find("\n", cursor + 1)
	return result


static func _diagnostic(source: String, offset: int, message: String, line_starts: PackedInt32Array = PackedInt32Array()) -> Dictionary:
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
		"severity": "error",
		"line": line_index + 1,
		"column": safe_offset - starts[line_index] + 1,
		"message": message,
	}
