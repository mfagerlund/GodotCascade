extends RefCounted

## Structural document validation kept separate from native-control construction.


static func validate(root_element) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var first_occurrences: Dictionary = {}
	_validate_element(root_element, first_occurrences, diagnostics)
	return diagnostics


static func _validate_element(element, first_occurrences: Dictionary, diagnostics: Array[Dictionary]) -> void:
	_validate_unique_id(element, first_occurrences, diagnostics)
	_validate_table_relation(element, diagnostics)
	_validate_scroll_relation(element, diagnostics)
	for child in element.children:
		_validate_element(child, first_occurrences, diagnostics)


static func _validate_unique_id(element, first_occurrences: Dictionary, diagnostics: Array[Dictionary]) -> void:
	var element_id: String = element.element_id()
	if element_id.is_empty():
		return
	if first_occurrences.has(element_id):
		var first: Dictionary = first_occurrences[element_id]
		diagnostics.append({
			"severity": "error",
			"line": element.source_line,
			"column": element.source_column,
			"message": "Duplicate id '%s'; first declared at line %s, column %s." % [
				element_id,
				first["line"],
				first["column"],
			],
		})
		return
	first_occurrences[element_id] = {
		"line": element.source_line,
		"column": element.source_column,
	}


static func _validate_table_relation(element, diagnostics: Array[Dictionary]) -> void:
	var parent = element.parent_element()
	if parent == null:
		return
	var tag: String = element.tag_name.to_lower()
	var parent_tag: String = parent.tag_name.to_lower()
	if parent_tag == "table" and tag not in ["tableheader", "tablebody", "tablerow", "repeat", "bindings"]:
		_append_error(diagnostics, "<Table> accepts only TableHeader, TableBody, TableRow, or Repeat children; got <%s>." % element.tag_name)
	elif parent_tag in ["tableheader", "tablebody"] and tag not in ["tablerow", "repeat"]:
		_append_error(diagnostics, "<%s> accepts only TableRow or Repeat children; got <%s>." % [parent.tag_name, element.tag_name])
	elif parent_tag == "tablerow" and tag not in ["tableheadercell", "tablecell"]:
		_append_error(diagnostics, "<TableRow> accepts only TableHeaderCell or TableCell children; got <%s>." % element.tag_name)
	elif tag in ["tableheader", "tablebody"] and parent_tag != "table":
		_append_error(diagnostics, "<%s> must be a direct child of <Table>." % element.tag_name)
	elif tag == "tablerow" and parent_tag not in ["table", "tableheader", "tablebody", "repeat"]:
		_append_error(diagnostics, "<TableRow> must be inside Table, TableHeader, TableBody, or a repeated table group.")
	elif tag in ["tableheadercell", "tablecell"] and parent_tag != "tablerow":
		_append_error(diagnostics, "<%s> must be a direct child of <TableRow>." % element.tag_name)
	elif tag == "repeat" and parent_tag in ["table", "tableheader", "tablebody"] and (
		element.children.size() != 1 or element.children[0].tag_name.to_lower() != "tablerow"
	):
		_append_error(diagnostics, "Repeat inside table structure must contain exactly one TableRow template.")


static func _validate_scroll_relation(element, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() != "scroll":
		return
	var content_children: Array = element.children.filter(func(child): return child.tag_name.to_lower() != "bindings")
	if content_children.size() != 1:
		_append_error(diagnostics, "<Scroll> requires exactly one content child.")


static func _append_error(diagnostics: Array[Dictionary], message: String) -> void:
	diagnostics.append({"severity": "error", "message": message})
