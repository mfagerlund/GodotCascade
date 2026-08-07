extends RefCounted

## Expands reusable source-level GXML components before native construction.

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const BindingCompiler := preload("res://addons/godot_cascade/runtime/binding_compiler.gd")

const PARAM_TYPES: PackedStringArray = ["string", "bool", "int", "float", "variant"]
const FORWARDED_ATTRIBUTES: PackedStringArray = ["id", "class", "if"]
const RESERVED_TAGS: PackedStringArray = [
	"page", "row", "column", "grid", "stack", "panel", "label", "button", "checkbox", "radiobutton", "radio",
	"switch", "select", "option", "slider", "textinput", "input", "progress", "image", "repeat", "scroll", "table",
	"tableheader", "tablebody", "tablerow", "tableheadercell", "tablecell", "bindings", "component", "param", "slot",
]


static func expand(root_element) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var definitions := _collect_definitions(root_element, diagnostics)
	if root_element == null:
		return {"root": null, "diagnostics": diagnostics}
	var roots := _expand_node(root_element, null, definitions, [], diagnostics, "")
	return {
		"root": roots[0] if roots.size() == 1 else null,
		"diagnostics": diagnostics,
	}


static func _collect_definitions(root_element, diagnostics: Array[Dictionary]) -> Dictionary:
	var definitions := {}
	if root_element == null:
		return definitions
	for child in root_element.children:
		if child.tag_name.to_lower() != "component":
			_diagnose_nested_definitions(child, diagnostics)
			continue
		var name := str(child.attributes.get("name", "")).strip_edges()
		if not _valid_identifier(name):
			_append_diagnostic(diagnostics, child, "Component 'name' must be a non-empty identifier.")
			continue
		var normalized := name.to_lower()
		if normalized in RESERVED_TAGS:
			_append_diagnostic(diagnostics, child, "Component name '%s' conflicts with a built-in GXML element." % name)
			continue
		if definitions.has(normalized):
			_append_diagnostic(diagnostics, child, "Duplicate component definition <%s>." % name)
			continue
		var definition := _parse_definition(child, diagnostics)
		if not definition.is_empty():
			definitions[normalized] = definition
	return definitions


static func _diagnose_nested_definitions(element, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() == "component":
		_append_diagnostic(diagnostics, element, "Component definitions must be direct children of the document root.")
		return
	for child in element.children:
		_diagnose_nested_definitions(child, diagnostics)


static func _parse_definition(element, diagnostics: Array[Dictionary]) -> Dictionary:
	var params := {}
	var template_nodes: Array = []
	for child in element.children:
		if child.tag_name.to_lower() == "param":
			var param := _parse_param(child, diagnostics)
			if param.is_empty():
				continue
			var param_name: String = param["name"]
			if params.has(param_name):
				_append_diagnostic(diagnostics, child, "Duplicate parameter '%s'." % param_name)
			else:
				params[param_name] = param
		else:
			template_nodes.append(child)
	if template_nodes.size() != 1:
		_append_diagnostic(diagnostics, element, "Component <%s> requires exactly one visual template root; found %s." % [element.attributes.get("name", ""), template_nodes.size()])
		return {}
	if template_nodes[0].tag_name.to_lower() == "slot":
		_append_diagnostic(diagnostics, template_nodes[0], "A component template root cannot be <Slot>.")
		return {}
	_diagnose_nested_definitions(template_nodes[0], diagnostics)
	var slot_names := {}
	_collect_slots(template_nodes[0], slot_names, diagnostics)
	return {
		"name": str(element.attributes["name"]),
		"params": params,
		"template": template_nodes[0],
		"slots": slot_names,
		"element": element,
	}


static func _parse_param(element, diagnostics: Array[Dictionary]) -> Dictionary:
	var name := str(element.attributes.get("name", "")).strip_edges()
	if not _valid_identifier(name):
		_append_diagnostic(diagnostics, element, "Param 'name' must be a non-empty identifier.")
		return {}
	var type_name := str(element.attributes.get("type", "String")).strip_edges().to_lower()
	if type_name not in PARAM_TYPES:
		_append_diagnostic(diagnostics, element, "Param '%s' has unsupported type '%s'; expected String, bool, int, float, or Variant." % [name, element.attributes.get("type", "")])
		return {}
	var required := _literal_bool(str(element.attributes.get("required", "false")))
	if required == null:
		_append_diagnostic(diagnostics, element, "Param '%s' requires a boolean 'required' value." % name)
		return {}
	if required and element.attributes.has("default"):
		_append_diagnostic(diagnostics, element, "Param '%s' cannot be required and declare a default." % name)
		return {}
	if element.attributes.has("default") and not _valid_literal(str(element.attributes["default"]), type_name):
		_append_diagnostic(diagnostics, element, "Default for Param '%s' is not a valid %s." % [name, type_name])
		return {}
	return {
		"name": name,
		"type": type_name,
		"required": required,
		"has_default": element.attributes.has("default"),
		"default": str(element.attributes.get("default", "")),
		"element": element,
	}


static func _collect_slots(element, slots: Dictionary, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() == "slot":
		var name := str(element.attributes.get("name", "")).strip_edges()
		if not name.is_empty() and not _valid_identifier(name):
			_append_diagnostic(diagnostics, element, "Slot 'name' must be an identifier.")
			return
		if slots.has(name):
			_append_diagnostic(diagnostics, element, "Duplicate %s slot in component template." % ("default" if name.is_empty() else "'%s'" % name))
		else:
			slots[name] = element
		return
	for child in element.children:
		_collect_slots(child, slots, diagnostics)


static func _expand_node(
	element,
	parent,
	definitions: Dictionary,
	stack: Array,
	diagnostics: Array[Dictionary],
	inherited_scope: String
) -> Array:
	if element.tag_name.to_lower() == "component":
		return []
	var normalized: String = str(element.tag_name).to_lower()
	if definitions.has(normalized):
		return _instantiate(element, parent, definitions[normalized], definitions, stack, diagnostics, inherited_scope)
	var clone: Variant = _clone_shallow(element, parent)
	var own_scope := str(element.attributes.get("__component_scope", inherited_scope))
	if not own_scope.is_empty():
		clone.attributes["__component_scope"] = own_scope
	for child in element.children:
		for expanded_child in _expand_node(child, clone, definitions, stack, diagnostics, own_scope):
			clone.children.append(expanded_child)
	return [clone]


static func _instantiate(
	invocation,
	parent,
	definition: Dictionary,
	definitions: Dictionary,
	stack: Array,
	diagnostics: Array[Dictionary],
	inherited_scope: String
) -> Array:
	var component_name: String = definition["name"]
	var normalized := component_name.to_lower()
	if normalized in stack:
		_append_diagnostic(diagnostics, invocation, "Recursive component expansion detected: %s -> %s." % [" -> ".join(stack), component_name])
		return []
	var values := {}
	var params: Dictionary = definition["params"]
	for attribute_name in invocation.attributes:
		if str(attribute_name) in FORWARDED_ATTRIBUTES or str(attribute_name).begins_with("__"):
			continue
		if not params.has(attribute_name):
			_append_diagnostic(diagnostics, invocation, "Component <%s> has no parameter '%s'." % [component_name, attribute_name])
	for param_name in params:
		var param: Dictionary = params[param_name]
		if invocation.attributes.has(param_name):
			var raw_value := str(invocation.attributes[param_name])
			if BindingCompiler.binding_path(raw_value).is_empty() and not _valid_literal(raw_value, param["type"]):
				_append_diagnostic(diagnostics, invocation, "Parameter '%s' on <%s> requires %s, got '%s'." % [param_name, component_name, param["type"], raw_value])
			values[param_name] = raw_value
		elif param["has_default"]:
			values[param_name] = param["default"]
		elif param["required"]:
			_append_diagnostic(diagnostics, invocation, "Component <%s> requires parameter '%s'." % [component_name, param_name])
		else:
			values[param_name] = ""

	var slots := _invocation_slots(invocation, definition, diagnostics)
	var scope_leaf := str(invocation.attributes.get("id", "")).strip_edges()
	if scope_leaf.is_empty():
		scope_leaf = "%s@%s:%s" % [component_name, invocation.source_line, invocation.source_column]
	var scope := "%s/%s" % [inherited_scope, scope_leaf] if not inherited_scope.is_empty() else scope_leaf
	var substituted: Variant = _substitute_tree(definition["template"], null, values, component_name, diagnostics)
	if substituted == null:
		return []
	_apply_invocation_surface(substituted, invocation)
	_stamp_scope(substituted, scope)
	var expanded := _expand_template_node(substituted, parent, slots, definitions, stack + [normalized], diagnostics, scope)
	for root in expanded:
		root.attributes["__component_name"] = component_name
		root.attributes["__component_invocation_line"] = invocation.source_line
		root.attributes["__component_invocation_column"] = invocation.source_column
	return expanded


static func _invocation_slots(invocation, definition: Dictionary, diagnostics: Array[Dictionary]) -> Dictionary:
	var slots := {}
	for child in invocation.children:
		var slot_name := str(child.attributes.get("slot", "")).strip_edges()
		if not definition["slots"].has(slot_name):
			_append_diagnostic(diagnostics, child, "Component <%s> has no %s slot." % [definition["name"], "default" if slot_name.is_empty() else "'%s'" % slot_name])
			continue
		if not slots.has(slot_name):
			slots[slot_name] = []
		slots[slot_name].append(child)
	return slots


static func _expand_template_node(
	element,
	parent,
	slots: Dictionary,
	definitions: Dictionary,
	stack: Array,
	diagnostics: Array[Dictionary],
	scope: String
) -> Array:
	if element.tag_name.to_lower() == "slot":
		var slot_name := str(element.attributes.get("name", "")).strip_edges()
		var content: Array = slots.get(slot_name, element.children)
		var inserted: Array = []
		for child in content:
			var authored: Variant = _clone_tree_without_slot_attribute(child, null)
			_stamp_scope(authored, scope)
			for expanded_child in _expand_node(authored, parent, definitions, stack, diagnostics, scope):
				inserted.append(expanded_child)
		return inserted
	if definitions.has(element.tag_name.to_lower()):
		return _instantiate(element, parent, definitions[element.tag_name.to_lower()], definitions, stack, diagnostics, scope)
	var clone: Variant = _clone_shallow(element, parent)
	clone.attributes["__component_scope"] = scope
	for child in element.children:
		for expanded_child in _expand_template_node(child, clone, slots, definitions, stack, diagnostics, scope):
			clone.children.append(expanded_child)
	return [clone]


static func _substitute_tree(element, parent, values: Dictionary, component_name: String, diagnostics: Array[Dictionary]):
	var clone: Variant = _clone_shallow(element, parent)
	for attribute_name in clone.attributes.keys():
		clone.attributes[attribute_name] = _substitute_value(str(clone.attributes[attribute_name]), values, element, component_name, diagnostics)
	clone.text = _substitute_value(clone.text, values, element, component_name, diagnostics)
	clone.raw_text = _substitute_value(clone.raw_text, values, element, component_name, diagnostics)
	for child in element.children:
		clone.children.append(_substitute_tree(child, clone, values, component_name, diagnostics))
	return clone


static func _substitute_value(raw_value: String, values: Dictionary, element, component_name: String, diagnostics: Array[Dictionary]) -> String:
	var trimmed := raw_value.strip_edges()
	if not trimmed.begins_with("{params.") or not trimmed.ends_with("}"):
		return raw_value
	var param_name := trimmed.substr(8, trimmed.length() - 9)
	if not values.has(param_name):
		_append_diagnostic(diagnostics, element, "Component <%s> template references undeclared parameter '%s'." % [component_name, param_name])
		return ""
	return str(values[param_name])


static func _apply_invocation_surface(template_root, invocation) -> void:
	if invocation.attributes.has("id"):
		template_root.attributes["id"] = invocation.attributes["id"]
	if invocation.attributes.has("class"):
		var template_classes := str(template_root.attributes.get("class", "")).strip_edges()
		var invocation_classes := str(invocation.attributes["class"]).strip_edges()
		template_root.attributes["class"] = "%s %s" % [template_classes, invocation_classes] if not template_classes.is_empty() else invocation_classes
	if invocation.attributes.has("if"):
		template_root.attributes["if"] = invocation.attributes["if"]


static func _stamp_scope(element, scope: String) -> void:
	element.attributes["__component_scope"] = scope
	for child in element.children:
		_stamp_scope(child, scope)


static func _clone_shallow(element, parent):
	var clone := GxmlParser.Element.new(element.tag_name, parent)
	clone.attributes = element.attributes.duplicate(true)
	clone.text = element.text
	clone.raw_text = element.raw_text
	clone.source_offset = element.source_offset
	clone.source_line = element.source_line
	clone.source_column = element.source_column
	return clone


static func _clone_tree_without_slot_attribute(element, parent):
	var clone: Variant = _clone_shallow(element, parent)
	clone.attributes.erase("slot")
	for child in element.children:
		clone.children.append(_clone_tree_without_slot_attribute(child, clone))
	return clone


static func _valid_identifier(value: String) -> bool:
	if value.is_empty() or not (value[0] == "_" or value[0].to_lower() != value[0].to_upper()):
		return false
	for character in value:
		if character != "_" and not character.is_valid_int() and character.to_lower() == character.to_upper():
			return false
	return true


static func _literal_bool(value: String) -> Variant:
	match value.strip_edges().to_lower():
		"true", "1", "yes", "on":
			return true
		"false", "0", "no", "off":
			return false
	return null


static func _valid_literal(value: String, type_name: String) -> bool:
	match type_name:
		"string", "variant":
			return true
		"bool":
			return _literal_bool(value) != null
		"int":
			return value.strip_edges().is_valid_int()
		"float":
			return value.strip_edges().is_valid_float()
	return false


static func _append_diagnostic(diagnostics: Array[Dictionary], element, message: String) -> void:
	diagnostics.append({
		"severity": "error",
		"line": element.source_line,
		"column": element.source_column,
		"message": message,
	})
