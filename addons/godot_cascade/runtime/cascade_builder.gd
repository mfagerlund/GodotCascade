extends RefCounted

## Converts parsed GodotCascade elements and rules into native Control nodes.

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeStack := preload("res://addons/godot_cascade/layout/cascade_stack.gd")
const CascadeGrid := preload("res://addons/godot_cascade/layout/cascade_grid.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CascadeLabel := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CascadeCheckbox := preload("res://addons/godot_cascade/components/cascade_checkbox.gd")
const CascadeRadioButton := preload("res://addons/godot_cascade/components/cascade_radio_button.gd")
const CascadeSwitch := preload("res://addons/godot_cascade/components/cascade_switch.gd")
const CascadeSelect := preload("res://addons/godot_cascade/components/cascade_select.gd")
const CascadeProgress := preload("res://addons/godot_cascade/components/cascade_progress.gd")
const CascadeSlider := preload("res://addons/godot_cascade/components/cascade_slider.gd")
const CascadeTextInput := preload("res://addons/godot_cascade/components/cascade_text_input.gd")
const CascadeTextArea := preload("res://addons/godot_cascade/components/cascade_text_area.gd")
const CascadeImage := preload("res://addons/godot_cascade/components/cascade_image.gd")
const CascadeScroll := preload("res://addons/godot_cascade/components/cascade_scroll.gd")
const CascadeTable := preload("res://addons/godot_cascade/components/cascade_table.gd")
const CascadeTablePart := preload("res://addons/godot_cascade/components/cascade_table_part.gd")
const CascadeTableCell := preload("res://addons/godot_cascade/components/cascade_table_cell.gd")
const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")
const ComputedStyleCache := preload("res://addons/godot_cascade/style/computed_style_cache.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")
const DocumentValidator := preload("res://addons/godot_cascade/runtime/document_validator.gd")
const BindingCompiler := preload("res://addons/godot_cascade/runtime/binding_compiler.gd")
const DeclarationApplier := preload("res://addons/godot_cascade/runtime/declaration_applier.gd")

const INHERITED_PROPERTIES: PackedStringArray = ["color", "font-size"]


static func build(root_element, rules: Array, binding_context: Variant = null, viewport_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var diagnostics: Array[Dictionary] = DocumentValidator.validate(root_element)
	var button_groups: Dictionary = {}
	DeclarationApplier.begin_build(viewport_size)
	var rule_index := _index_rules(rules, viewport_size)
	var root_control := _build_element(root_element, rule_index, diagnostics, "0", button_groups, binding_context)
	return {"root": root_control, "diagnostics": diagnostics}


static func _build_element(
	element,
	rule_index: Dictionary,
	diagnostics: Array[Dictionary],
	key_path: String,
	button_groups: Dictionary,
	binding_context: Variant = null,
	binding_scope: Dictionary = {},
	key_scope: String = ""
) -> Control:
	var class_binding_path := _resolve_bound_classes(element, binding_context, binding_scope, diagnostics)
	var control: Control
	if element.tag_name.to_lower() == "repeat" and element.children.size() == 1 and element.children[0].tag_name.to_lower() == "tablerow":
		control = CascadeTablePart.new()
		control.set("semantic_role", "group")
	else:
		control = _create_control(element.tag_name, diagnostics, element.attributes)
	if control == null:
		return null

	control.name = element.element_id() if not element.element_id().is_empty() else element.tag_name
	control.set_meta("cascade_element_type", element.tag_name)
	control.set_meta("cascade_id", element.element_id())
	control.set_meta("cascade_classes", element.classes())
	var local_key: String = "#" + element.element_id() if not element.element_id().is_empty() else key_path
	control.set_meta("cascade_key", "%s/%s" % [key_scope, local_key] if not key_scope.is_empty() else local_key)
	control.set_meta("cascade_bindings", {})
	control.set_meta("cascade_rebuild_bindings", PackedStringArray([class_binding_path]) if not class_binding_path.is_empty() else PackedStringArray())
	control.set_meta("cascade_writable_bindings", {})
	control.set_meta("cascade_events", {})
	control.set_meta("cascade_binding_scope", binding_scope)
	control.set_meta("cascade_source_line", element.source_line)
	control.set_meta("cascade_source_column", element.source_column)
	control.set_meta("cascade_transition_properties", PackedStringArray())
	control.set_meta("cascade_transition_duration", 0.0)
	control.set_meta("cascade_explicit_accessible_label", false)
	var compatibility_tier := "layout-only" if ComponentRegistry.has(element.tag_name) else ("adapted" if _is_text_input(control) or control is CascadeScroll else "exact")
	control.set_meta("cascade_compatibility_tier", compatibility_tier)
	if _is_text_input(control):
		control.set_meta("cascade_adapted_properties", PackedStringArray(["background", "border", "color", "font-size", "padding"]))
	elif control is CascadeScroll:
		control.set_meta("cascade_adapted_properties", PackedStringArray([
			"background", "background-color", "border", "border-color", "border-width", "border-radius", "padding",
		]))

	_apply_attributes(control, element.attributes, element.text, diagnostics, button_groups)
	if element.tag_name.to_lower() == "row":
		control.direction = CascadeBox.FlowDirection.ROW

	var computed := _compute_declarations(element, rule_index)
	DeclarationApplier.apply(control, computed, diagnostics)
	if control is CascadeSelect:
		_apply_select_options(control, element, rule_index, diagnostics)
		return control
	if element.tag_name.to_lower() == "repeat":
		_build_repeat_children(control, element, rule_index, diagnostics, key_path, button_groups, binding_context, key_scope)
		return control

	for index in element.children.size():
		var child_element = element.children[index]
		if child_element.tag_name.to_lower() == "bindings":
			continue
		var child_key := "%s/%s:%s" % [key_path, index, child_element.tag_name]
		var child_control := _build_element(child_element, rule_index, diagnostics, child_key, button_groups, binding_context, binding_scope, key_scope)
		if child_control != null:
			control.add_child(child_control)
	return control


static func _build_repeat_children(
	control: Control,
	element,
	rule_index: Dictionary,
	diagnostics: Array[Dictionary],
	key_path: String,
	button_groups: Dictionary,
	binding_context: Variant,
	key_scope: String
) -> void:
	if element.children.size() != 1:
		diagnostics.append(_diagnostic("error", "Repeat requires exactly one child template."))
		return
	var raw_items := str(element.attributes.get("items", "")).strip_edges()
	if raw_items.length() < 3 or not raw_items.begins_with("{") or not raw_items.ends_with("}"):
		diagnostics.append(_diagnostic("error", "Repeat 'items' must be an exact binding such as '{inventory.items}'."))
		return
	var items_path := BindingCompiler.binding_path(raw_items)
	var resolved := BindingResolver.resolve(binding_context, items_path)
	if not resolved["found"]:
		diagnostics.append(_diagnostic("error", "Repeat could not resolve items: %s" % resolved["message"]))
		return
	if not resolved["value"] is Array:
		diagnostics.append(_diagnostic("error", "Repeat 'items' must resolve to an Array."))
		return
	var key_property := str(element.attributes.get("key", "")).strip_edges()
	var seen_keys := {}
	var items: Array = resolved["value"]
	for index in items.size():
		var item: Variant = items[index]
		var item_key := str(index)
		if not key_property.is_empty():
			var key_result := BindingResolver.resolve(item, key_property)
			if not key_result["found"]:
				diagnostics.append(_diagnostic("error", "Repeat key '%s' could not be resolved for item %s." % [key_property, index]))
				continue
			item_key = str(key_result["value"])
		if seen_keys.has(item_key):
			diagnostics.append(_diagnostic("error", "Repeat key '%s' is duplicated." % item_key))
			continue
		seen_keys[item_key] = true
		var repeated_scope := {
			"item": item,
			"index": index,
		}
		var repeated_key_scope := "%s%srepeat:%s" % [key_scope, "/" if not key_scope.is_empty() else "", item_key]
		var template = element.children[0]
		var child := _build_element(
			template,
			rule_index,
			diagnostics,
			"%s/item:%s" % [key_path, item_key],
			button_groups,
			binding_context,
			repeated_scope,
			repeated_key_scope
		)
		if child != null:
			control.add_child(child)


static func _create_control(tag_name: String, diagnostics: Array[Dictionary], attributes: Dictionary = {}) -> Control:
	match tag_name.to_lower():
		"page", "row", "column":
			return CascadeBox.new()
		"stack":
			return CascadeStack.new()
		"grid":
			return CascadeGrid.new()
		"panel":
			return CascadePanel.new()
		"label":
			return CascadeLabel.new()
		"button":
			return CascadeButton.new()
		"checkbox":
			return CascadeCheckbox.new()
		"radiobutton", "radio":
			return CascadeRadioButton.new()
		"switch":
			return CascadeSwitch.new()
		"select":
			return CascadeSelect.new()
		"progress":
			return CascadeProgress.new()
		"slider":
			return CascadeSlider.new()
		"textinput", "input":
			return CascadeTextArea.new() if _raw_boolean_attribute(attributes, "multiline") else CascadeTextInput.new()
		"image":
			return CascadeImage.new()
		"scroll":
			return CascadeScroll.new()
		"table":
			var table := CascadeTable.new()
			table.set_meta("cascade_table_role", "table")
			return table
		"tableheader":
			var header := CascadeTablePart.new()
			header.semantic_role = "header"
			return header
		"tablebody":
			var body := CascadeTablePart.new()
			body.semantic_role = "body"
			return body
		"tablerow":
			var row := CascadeTablePart.new()
			row.semantic_role = "row"
			return row
		"tableheadercell":
			var header_cell := CascadeTableCell.new()
			header_cell.header = true
			return header_cell
		"tablecell":
			var cell := CascadeTableCell.new()
			cell.set_meta("cascade_table_role", "cell")
			return cell
		"repeat":
			return CascadeBox.new()
		"bindings":
			return null
		_:
			if ComponentRegistry.has(tag_name):
				var custom := ComponentRegistry.create(tag_name)
				if custom != null:
					return custom
				diagnostics.append(_diagnostic("error", "Custom component factory for <%s> did not return a Control." % tag_name))
				return null
			diagnostics.append(_diagnostic(
				"error",
				"Unknown GXML element <%s>. Register a native control factory before using it." % tag_name
			))
			return null


static func _raw_boolean_attribute(attributes: Dictionary, attribute_name: String) -> bool:
	if not attributes.has(attribute_name):
		return false
	return str(attributes[attribute_name]).strip_edges().to_lower() in ["true", "1", "yes", "on", attribute_name]


static func _is_text_input(control: Control) -> bool:
	return control is CascadeTextInput or control is CascadeTextArea


static func _compute_declarations(element, rule_index: Dictionary) -> Dictionary:
	var cache_key := "%s|%s|%s" % [rule_index.get("revision", 0), rule_index.get("viewport_width", INF), _element_signature(element)]
	if ComputedStyleCache.has(cache_key):
		return ComputedStyleCache.retrieve(cache_key)
	var winners := _compute_declarations_uncached(element, rule_index)
	_inherit_declarations(element, rule_index, winners)
	ComputedStyleCache.put(cache_key, winners, _element_dependencies(element))
	return winners


static func _compute_declarations_uncached(element, rule_index: Dictionary) -> Dictionary:
	var winners := {}
	for rule in _candidate_rules(element, rule_index):
		if not rule.matches(element, float(rule_index.get("viewport_width", INF))):
			continue
		var state: String = rule.pseudo_state
		if not winners.has(state):
			winners[state] = {}
		var expansion := DeclarationApplier.expand_shorthands(rule.declarations)
		var declarations: Dictionary = expansion["values"]
		var origins: Dictionary = expansion["origins"]
		for property_name in declarations:
			var existing: Dictionary = winners[state].get(property_name, {})
			if existing.is_empty() or rule.specificity > existing["specificity"] or (
				rule.specificity == existing["specificity"] and rule.order >= existing["order"]
			):
				var origin: String = origins[property_name]
				var location: Dictionary = rule.declaration_locations.get(origin, {"line": rule.line, "column": 1})
				winners[state][property_name] = {
					"value": declarations[property_name],
					"specificity": rule.specificity,
					"order": rule.order,
					"line": location["line"],
					"column": location["column"],
				}
	return winners


static func _inherit_declarations(element, rule_index: Dictionary, winners: Dictionary) -> void:
	var parent = element.parent_element()
	if not winners.has(""):
		winners[""] = {}
	if parent == null:
		for property_name in INHERITED_PROPERTIES:
			if winners[""].has(property_name) and str(winners[""][property_name]["value"]).to_lower() == "inherit":
				winners[""].erase(property_name)
		return
	var parent_computed := _compute_declarations(parent, rule_index)
	var parent_base: Dictionary = parent_computed.get("", {})
	for property_name in INHERITED_PROPERTIES:
		var own: Dictionary = winners[""].get(property_name, {})
		var requests_inherit := not own.is_empty() and str(own["value"]).to_lower() == "inherit"
		if (own.is_empty() or requests_inherit) and parent_base.has(property_name):
			var inherited: Dictionary = parent_base[property_name].duplicate(true)
			inherited["inherited"] = true
			winners[""][property_name] = inherited


static func _element_signature(element) -> String:
	var parts := PackedStringArray()
	var current = element
	while current != null:
		parts.append("%s#%s.%s" % [current.tag_name.to_lower(), current.element_id(), ".".join(current.classes())])
		current = current.parent_element()
	parts.reverse()
	return ">".join(parts)


static func _element_dependencies(element) -> PackedStringArray:
	var result := PackedStringArray()
	var current = element
	while current != null:
		var type_dependency := "type:%s" % current.tag_name.to_lower()
		if type_dependency not in result:
			result.append(type_dependency)
		if not current.element_id().is_empty():
			var id_dependency := "id:%s" % current.element_id()
			if id_dependency not in result:
				result.append(id_dependency)
		for class_value in current.classes():
			var class_dependency := "class:%s" % class_value
			if class_dependency not in result:
				result.append(class_dependency)
		current = current.parent_element()
	return result


static func _index_rules(rules: Array, viewport_size: Vector2) -> Dictionary:
	var viewport_width := viewport_size.x if viewport_size.x > 0.0 else INF
	var index := {"universal": [], "types": {}, "classes": {}, "ids": {}, "revision": _rules_revision(rules), "viewport_width": viewport_width}
	for rule in rules:
		var compound := str(rule.compounds[-1])
		var rule_id := _compound_token(compound, "#")
		var rule_class := _compound_token(compound, ".")
		var type_name := compound
		var marker_positions := [compound.find("."), compound.find("#")]
		for marker_position in marker_positions:
			if marker_position >= 0:
				type_name = compound.substr(0, mini(type_name.length(), marker_position))
		if not rule_id.is_empty():
			_append_indexed_rule(index["ids"], rule_id, rule)
		elif not rule_class.is_empty():
			_append_indexed_rule(index["classes"], rule_class, rule)
		elif not type_name.is_empty():
			_append_indexed_rule(index["types"], type_name.to_lower(), rule)
		else:
			index["universal"].append(rule)
	return index


static func _rules_revision(rules: Array) -> int:
	var parts := PackedStringArray()
	for rule in rules:
		parts.append("%s|%s|%s|%s|%s|%s|%s" % [rule.selector, rule.pseudo_state, rule.declarations, rule.declaration_locations, rule.order, rule.min_viewport_width, rule.max_viewport_width])
	return hash("\n".join(parts))


static func _candidate_rules(element, index: Dictionary) -> Array:
	var result: Array = index["universal"].duplicate()
	var seen := {}
	for rule in result:
		seen[rule.get_instance_id()] = true
	var buckets: Array = [index["types"].get(element.tag_name.to_lower(), [])]
	var element_id: String = element.element_id()
	if not element_id.is_empty():
		buckets.append(index["ids"].get(element_id, []))
	for class_value in element.classes():
		buckets.append(index["classes"].get(class_value, []))
	for bucket in buckets:
		for rule in bucket:
			if not seen.has(rule.get_instance_id()):
				result.append(rule)
				seen[rule.get_instance_id()] = true
	return result


static func _append_indexed_rule(index: Dictionary, key: String, rule) -> void:
	if not index.has(key):
		index[key] = []
	index[key].append(rule)


static func _compound_token(compound: String, marker: String) -> String:
	var start := compound.find(marker)
	if start < 0:
		return ""
	start += 1
	var end := compound.length()
	for other_marker in [".", "#"]:
		var found := compound.find(other_marker, start)
		if found >= 0:
			end = mini(end, found)
	return compound.substr(start, end - start)




static func _apply_attributes(
	control: Control,
	attributes: Dictionary,
	element_text: String,
	diagnostics: Array[Dictionary],
	button_groups: Dictionary
) -> void:
	BindingCompiler.apply_event_attributes(control, attributes, diagnostics)
	BindingCompiler.apply_writable_attributes(control, attributes, diagnostics)
	_apply_boolean_attribute(control, attributes, "visible", "visible", diagnostics)
	_apply_boolean_attribute(control, attributes, "disabled", "disabled", diagnostics)
	if control is CascadeLabel or control is CascadeButton or control is CascadeTableCell or _is_text_input(control):
		var raw_text := str(attributes.get("text", element_text))
		if raw_text.begins_with("@"):
			pass
		elif not control.get_meta("cascade_bindings", {}).has("text") and not BindingCompiler.record_one_way(control, "text", raw_text):
			control.set("text", raw_text)
	if attributes.has("accessible-label"):
		if _has_property(control, "accessibility_name"):
			control.set("accessibility_name", str(attributes["accessible-label"]))
			control.set_meta("cascade_explicit_accessible_label", true)
		else:
			control.set_meta("cascade_accessible_label", str(attributes["accessible-label"]))
	elif _has_property(control, "accessibility_name") and _has_property(control, "text"):
		control.set("accessibility_name", str(control.get("text")))
	if attributes.has("accessible-description") and _has_property(control, "accessibility_description"):
		control.set("accessibility_description", str(attributes["accessible-description"]))
		control.set_meta("cascade_authored_accessible_description", str(attributes["accessible-description"]))
	if control is BaseButton:
		_apply_button_attributes(control, attributes, diagnostics, button_groups)
	if _is_text_input(control):
		_apply_text_input_attributes(control, attributes, diagnostics)
	if control is CascadeImage:
		_apply_image_attributes(control, attributes, diagnostics)
	if not (control is CascadeProgress or control is CascadeSlider):
		return
	var range_values := {
		"min_value": control.min_value,
		"max_value": control.max_value,
		"value": control.value,
	}
	for attribute_name in ["min", "max", "value"]:
		if not attributes.has(attribute_name):
			continue
		var raw_value := str(attributes[attribute_name])
		var property_name := "%s_value" % attribute_name if attribute_name != "value" else "value"
		if raw_value.begins_with("@"):
			continue
		if BindingCompiler.record_one_way(control, property_name, raw_value):
			continue
		if not raw_value.is_valid_float():
			diagnostics.append(_diagnostic("error", "Progress attribute '%s' requires a number, got '%s'." % [attribute_name, raw_value]))
			continue
		range_values[property_name] = raw_value.to_float()
	if control is CascadeSlider and attributes.has("step"):
		var raw_step := str(attributes["step"])
		if raw_step.is_valid_float() and raw_step.to_float() > 0.0:
			control.set("step", raw_step.to_float())
		else:
			diagnostics.append(_diagnostic("error", "Slider attribute 'step' requires a positive number, got '%s'." % raw_step))
	control.set_range_values(range_values["min_value"], range_values["max_value"], range_values["value"])


static func _apply_text_input_attributes(control: Control, attributes: Dictionary, diagnostics: Array[Dictionary]) -> void:
	control.placeholder_text = str(attributes.get("placeholder", ""))
	for attribute_name in ["read-only", "secret", "required"]:
		if not attributes.has(attribute_name):
			continue
		var parsed: Variant = _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
		if parsed == null:
			continue
		match attribute_name:
			"read-only":
				control.read_only = parsed
			"secret":
				if control is CascadeTextArea and parsed:
					diagnostics.append(_diagnostic("error", "TextInput secret=true is only supported by the single-line LineEdit adapter."))
				elif control is CascadeTextInput:
					control.secret = parsed
			"required": control.required = parsed
	if attributes.has("multiline"):
		_parse_bool_attribute("multiline", str(attributes["multiline"]), diagnostics)
	if attributes.has("max-length"):
		var raw_max := str(attributes["max-length"])
		if not raw_max.is_valid_int() or raw_max.to_int() < 0:
			diagnostics.append(_diagnostic("error", "TextInput max-length requires a non-negative integer, got '%s'." % raw_max))
		else:
			control.max_length = raw_max.to_int()
	control.validation_pattern = str(attributes.get("pattern", ""))
	if not control.validation_pattern_is_valid():
		diagnostics.append(_diagnostic("error", "TextInput pattern is not a valid Godot regular expression."))
	control.validation_message = str(attributes.get("error-message", "Invalid value."))


static func _apply_image_attributes(control: Control, attributes: Dictionary, diagnostics: Array[Dictionary]) -> void:
	var raw_source := str(attributes.get("src", "")).strip_edges()
	if raw_source.begins_with("@"):
		return
	if BindingCompiler.record_one_way(control, "image_source", raw_source):
		return
	var error_message := str(control.call("set_source", raw_source))
	if not error_message.is_empty():
		diagnostics.append(_diagnostic("error", error_message))


static func _apply_button_attributes(
	control: BaseButton,
	attributes: Dictionary,
	diagnostics: Array[Dictionary],
	button_groups: Dictionary
) -> void:
	if attributes.has("checked"):
		if not control.toggle_mode:
			diagnostics.append(_diagnostic("error", "Attribute 'checked' requires a toggle control."))
		elif str(attributes["checked"]).strip_edges().begins_with("@"):
			pass
		elif not BindingCompiler.record_one_way(control, "button_pressed", str(attributes["checked"])):
			var parsed: Variant = _parse_bool_attribute("checked", str(attributes["checked"]), diagnostics)
			if parsed != null:
				control.button_pressed = parsed

	if not control is CascadeRadioButton:
		return
	var group_name := str(attributes.get("group", "default")).strip_edges()
	if group_name.is_empty():
		diagnostics.append(_diagnostic("error", "RadioButton attribute 'group' cannot be empty."))
		return
	if not button_groups.has(group_name):
		button_groups[group_name] = ButtonGroup.new()
	control.button_group = button_groups[group_name]


static func _apply_select_options(
	control: Control,
	element,
	rule_index: Dictionary,
	diagnostics: Array[Dictionary]
) -> void:
	var options: Array[Dictionary] = []
	for child in element.children:
		if child.tag_name.to_lower() != "option":
			diagnostics.append(_diagnostic("error", "Select only accepts <Option> children, got <%s>." % child.tag_name))
			continue
		var label := str(child.attributes.get("text", child.text)).strip_edges()
		if label.is_empty():
			diagnostics.append(_diagnostic("error", "Select options require text or a text attribute."))
			continue
		var option := {
			"label": label,
			"value": str(child.attributes.get("value", label)),
			"disabled": false,
		}
		if child.attributes.has("disabled"):
			var parsed: Variant = _parse_bool_attribute("disabled", str(child.attributes["disabled"]), diagnostics)
			if parsed != null:
				option["disabled"] = parsed
		DeclarationApplier.apply_select_option_styles(option, _compute_declarations(child, rule_index), diagnostics)
		options.append(option)
	control.set("options", options)

	var selected := str(element.attributes.get("selected", "")).strip_edges()
	if selected.is_empty():
		return
	if selected.begins_with("@") or BindingCompiler.record_one_way(control, "selected_value", selected):
		return
	var selected_index := -1
	if selected.is_valid_int():
		selected_index = selected.to_int()
	else:
		for index in options.size():
			if str(options[index]["value"]) == selected:
				selected_index = index
				break
	if selected_index < 0 or selected_index >= options.size():
		diagnostics.append(_diagnostic("error", "Select attribute 'selected' does not match an option: '%s'." % selected))
		return
	control.set("selected_index", selected_index)


static func _apply_boolean_attribute(
	control: Control,
	attributes: Dictionary,
	attribute_name: String,
	property_name: String,
	diagnostics: Array[Dictionary]
) -> void:
	if not attributes.has(attribute_name):
		return
	if not _has_property(control, property_name):
		diagnostics.append(_diagnostic("error", "Attribute '%s' is not supported on <%s>." % [attribute_name, control.get_meta("cascade_element_type", control.get_class())]))
		return
	if str(attributes[attribute_name]).strip_edges().begins_with("@"):
		return
	if BindingCompiler.record_one_way(control, property_name, str(attributes[attribute_name])):
		return
	var parsed: Variant = _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
	if parsed != null:
		control.set(property_name, parsed)


static func _resolve_bound_classes(
	element,
	binding_context: Variant,
	binding_scope: Dictionary,
	diagnostics: Array[Dictionary]
) -> String:
	var raw_value := str(element.attributes.get("class", ""))
	if raw_value.strip_edges().begins_with("@"):
		element.attributes["class"] = ""
		return ""
	var path := BindingCompiler.binding_path(raw_value)
	if path.is_empty():
		return ""
	var first_segment := path.get_slice(".", 0)
	var context: Variant = binding_scope if binding_scope.has(first_segment) else binding_context
	var result := BindingResolver.resolve(context, path)
	if not result["found"]:
		element.attributes["class"] = ""
		diagnostics.append(_diagnostic("warning", "class binding: %s" % result["message"]))
		return path
	var class_result := _class_string(result["value"])
	if not class_result["valid"]:
		element.attributes["class"] = ""
		diagnostics.append(_diagnostic("warning", "class binding '%s' requires a String or an Array of class names." % path))
		return path
	element.attributes["class"] = class_result["value"]
	return path


static func _class_string(value: Variant) -> Dictionary:
	if value is String or value is StringName:
		return {"valid": true, "value": str(value)}
	if value is Array or value is PackedStringArray:
		var names := PackedStringArray()
		for item in value:
			var name := str(item).strip_edges()
			if not name.is_empty():
				names.append(name)
		return {"valid": true, "value": " ".join(names)}
	return {"valid": false, "value": ""}




static func _parse_bool_attribute(attribute_name: String, value: String, diagnostics: Array[Dictionary]) -> Variant:
	var normalized := value.strip_edges().to_lower()
	if normalized in ["true", "1", "yes", "on", attribute_name]:
		return true
	if normalized in ["false", "0", "no", "off"]:
		return false
	diagnostics.append(_diagnostic(
		"error",
		"Attribute '%s' requires a boolean, got '%s'." % [attribute_name, value]
	))
	return null




static func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)




static func _diagnostic(severity: String, message: String) -> Dictionary:
	return {"severity": severity, "message": message}
