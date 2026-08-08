extends RefCounted

## Structural document validation kept separate from native-control construction.

const GxmlSchema := preload("res://addons/godot_cascade/runtime/gxml_schema.gd")


static func validate(root_element, allow_internal_attributes: bool = false) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_validate_document_root(root_element, diagnostics)
	var first_occurrences: Dictionary = {}
	_validate_element(root_element, first_occurrences, diagnostics, allow_internal_attributes)
	return diagnostics


static func validate_authored_root(root_element) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_validate_visual_document_root(root_element, diagnostics)
	return diagnostics


static func validate_reserved_attributes(root_element) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	_validate_reserved_attributes(root_element, diagnostics)
	return diagnostics


static func _validate_element(element, first_occurrences: Dictionary, diagnostics: Array[Dictionary], allow_internal_attributes: bool) -> void:
	if element == null:
		return
	_validate_attributes(element, diagnostics, allow_internal_attributes)
	_validate_focus_trap_owner(element, diagnostics)
	_validate_unique_id(element, first_occurrences, diagnostics)
	_validate_table_relation(element, diagnostics)
	_validate_scroll_relation(element, diagnostics)
	_validate_repeat_focus_contract(element, diagnostics)
	_validate_virtual_repeat_nesting(element, diagnostics)
	_validate_virtual_item_root_visibility(element, diagnostics)
	for child in element.children:
		_validate_element(child, first_occurrences, diagnostics, allow_internal_attributes)


static func _validate_document_root(root_element, diagnostics: Array[Dictionary]) -> void:
	if root_element == null:
		return
	_validate_visual_document_root(root_element, diagnostics)
	if root_element.attributes.has("if"):
		_append_element_error(diagnostics, root_element, "The document root cannot use 'if'; bind 'visible' or put the conditional on a child element.")


static func _validate_visual_document_root(root_element, diagnostics: Array[Dictionary]) -> void:
	if root_element == null:
		return
	var canonical := GxmlSchema.canonical_element(root_element.tag_name)
	if canonical in GxmlSchema.NON_VISUAL_ELEMENTS:
		_append_element_error(diagnostics, root_element, "The document root must be visual; <%s> is a non-visual declaration element." % root_element.tag_name)


static func _validate_focus_trap_owner(element, diagnostics: Array[Dictionary]) -> void:
	if not _attribute_is_true(element, "focus-trap"):
		return
	if GxmlSchema.is_builtin(element.tag_name) and not GxmlSchema.supports_focus_trap(element.tag_name):
		_append_element_error(diagnostics, element, "Attribute 'focus-trap' requires an element backed by a native Container.")


static func _validate_attributes(element, diagnostics: Array[Dictionary], allow_internal_attributes: bool) -> void:
	if not GxmlSchema.is_builtin(element.tag_name):
		return
	for attribute_name_value in element.attributes:
		var attribute_name := str(attribute_name_value)
		if allow_internal_attributes and attribute_name.begins_with("__"):
			continue
		if not GxmlSchema.is_attribute_allowed(element.tag_name, attribute_name):
			diagnostics.append({
				"severity": "error",
				"line": element.source_line,
				"column": element.source_column,
				"message": "Unknown attribute '%s' on <%s>." % [attribute_name, element.tag_name],
			})


static func _validate_reserved_attributes(element, diagnostics: Array[Dictionary]) -> void:
	for attribute_name_value in element.attributes:
		var attribute_name := str(attribute_name_value)
		if attribute_name.begins_with("__"):
			diagnostics.append({
				"severity": "error",
				"line": element.source_line,
				"column": element.source_column,
				"message": "Attribute '%s' is reserved for GodotCascade internals." % attribute_name,
			})
	for child in element.children:
		_validate_reserved_attributes(child, diagnostics)


static func _validate_unique_id(element, first_occurrences: Dictionary, diagnostics: Array[Dictionary]) -> void:
	var element_id: String = element.element_id()
	if element_id.is_empty():
		return
	var scope := str(element.attributes.get("__component_scope", ""))
	var scoped_id := "%s/%s" % [scope, element_id] if not scope.is_empty() else element_id
	if first_occurrences.has(scoped_id):
		var first: Dictionary = first_occurrences[scoped_id]
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
	first_occurrences[scoped_id] = {
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


static func _validate_repeat_focus_contract(element, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() != "repeat" or element.children.is_empty():
		return
	var offenders: Array = []
	_collect_repeat_focus_offenders(element.children[0], offenders)
	for offender in offenders:
		diagnostics.append({
			"severity": "error",
			"line": offender.source_line,
			"column": offender.source_column,
			"message": "Repeat templates cannot author autofocus or focus-trap; focus one stable control outside the collection and manage row focus from application code.",
		})


static func _collect_repeat_focus_offenders(element, result: Array) -> void:
	for attribute_name in ["autofocus", "focus-trap"]:
		if _attribute_is_true(element, attribute_name):
			result.append(element)
			break
	for child in element.children:
		_collect_repeat_focus_offenders(child, result)


static func _validate_virtual_repeat_nesting(element, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() != "repeat" or not _attribute_is_true(element, "virtual"):
		return
	var ancestor = element.parent_element()
	while ancestor != null:
		if ancestor.tag_name.to_lower() == "repeat":
			diagnostics.append({
				"severity": "error",
				"line": element.source_line,
				"column": element.source_column,
				"message": "Virtual Repeat cannot be nested inside another Repeat.",
			})
			return
		ancestor = ancestor.parent_element()


static func _validate_virtual_item_root_visibility(element, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() != "repeat" or not _attribute_is_true(element, "virtual") or element.children.is_empty():
		return
	var item_root = element.children[0]
	if not item_root.attributes.has("visible"):
		return
	var raw_visible := str(item_root.attributes["visible"]).strip_edges().to_lower()
	if raw_visible in ["true", "1", "yes", "on", "visible"]:
		return
	_append_element_error(diagnostics, item_root, "Virtual Repeat item roots cannot use conditional 'visible'; filter the collection model instead. Literal visible=true is harmless, and descendants may still bind visibility.")


static func _attribute_is_true(element, attribute_name: String) -> bool:
	if not element.attributes.has(attribute_name):
		return false
	return str(element.attributes[attribute_name]).strip_edges().to_lower() in ["true", "1", "yes", "on", attribute_name]


static func _append_error(diagnostics: Array[Dictionary], message: String) -> void:
	diagnostics.append({"severity": "error", "message": message})


static func _append_element_error(diagnostics: Array[Dictionary], element, message: String) -> void:
	diagnostics.append({
		"severity": "error",
		"line": element.source_line,
		"column": element.source_column,
		"message": message,
	})
