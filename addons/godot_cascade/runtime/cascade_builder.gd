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
const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GxmlComponentExpander := preload("res://addons/godot_cascade/runtime/gxml_component_expander.gd")
const GcssExpression := preload("res://addons/godot_cascade/style/gcss_expression.gd")
const FocusManager := preload("res://addons/godot_cascade/runtime/focus_manager.gd")
const CascadeItemModel := preload("res://addons/godot_cascade/runtime/cascade_item_model.gd")
const CascadeVirtualWindow := preload("res://addons/godot_cascade/runtime/virtual_window.gd")

const INHERITED_PROPERTIES: PackedStringArray = ["color", "font-size", "font-source"]


static func build(root_element, rules: Array, binding_context: Variant = null, viewport_size: Vector2 = Vector2.ZERO) -> Dictionary:
	var expansion := GxmlComponentExpander.expand(root_element)
	var expanded_root = expansion["root"]
	var diagnostics: Array[Dictionary] = expansion["diagnostics"]
	if expanded_root == null:
		return {"root": null, "diagnostics": diagnostics}
	diagnostics.append_array(DocumentValidator.validate(expanded_root))
	var button_groups: Dictionary = {}
	var document_rebuild_bindings := PackedStringArray()
	DeclarationApplier.begin_build(viewport_size)
	var rule_index := _index_rules(rules, viewport_size)
	var root_control := _build_element(expanded_root, rule_index, diagnostics, "0", button_groups, binding_context, {}, "", document_rebuild_bindings)
	if root_control != null:
		root_control.set_meta("cascade_document_rebuild_bindings", document_rebuild_bindings)
		diagnostics.append_array(FocusManager.validate(root_control))
	return {"root": root_control, "diagnostics": diagnostics}


## Builds only one previously prepared Repeat subtree. The repeat descriptor and
## indexed rules are retained as metadata during the successful full build, so a
## collection refresh never needs to construct an off-tree document candidate.
static func rebuild_repeat(
	repeat_control: Control,
	binding_context: Variant,
	viewport_size: Vector2 = Vector2.ZERO,
	validated_model_keys: Variant = null,
	keys_scanned: int = -1,
	shared_button_groups: Variant = null
) -> Dictionary:
	var element: Variant = repeat_control.get_meta("cascade_repeat_element") if repeat_control != null else null
	var rule_index: Dictionary = repeat_control.get_meta("cascade_repeat_rule_index", {}) if repeat_control != null else {}
	if element == null or rule_index.is_empty():
		return {"root": null, "diagnostics": [_diagnostic("error", "Repeat does not have a retained build descriptor.")]}
	var diagnostics: Array[Dictionary] = []
	element = _clone_element_surface(element)
	element.attributes.erase("__validated_model_keys")
	element.attributes.erase("__keys_scanned")
	for metadata_name in ["cascade_virtual_scroll_offset", "cascade_virtual_viewport_extent", "cascade_virtual_pinned_index", "cascade_virtual_pinned_key"]:
		if repeat_control.has_meta(metadata_name):
			element.attributes["__" + metadata_name.trim_prefix("cascade_")] = repeat_control.get_meta(metadata_name)
	if validated_model_keys is Array:
		element.attributes["__validated_model_keys"] = validated_model_keys
		element.attributes["__keys_scanned"] = maxi(keys_scanned, 0)
	var button_groups: Dictionary = shared_button_groups if shared_button_groups is Dictionary else {}
	var rebuild_bindings := PackedStringArray()
	DeclarationApplier.begin_build(viewport_size)
	var root := _build_element(
		element,
		rule_index,
		diagnostics,
		str(repeat_control.get_meta("cascade_repeat_key_path", "0")),
		button_groups,
		binding_context,
		repeat_control.get_meta("cascade_binding_scope", {}),
		str(repeat_control.get_meta("cascade_repeat_key_scope", "")),
		rebuild_bindings
	)
	if root != null:
		root.set_meta("cascade_document_rebuild_bindings", rebuild_bindings)
		diagnostics.append_array(FocusManager.validate(root))
	return {"root": root, "diagnostics": diagnostics}


static func _build_element(
	element,
	rule_index: Dictionary,
	diagnostics: Array[Dictionary],
	key_path: String,
	button_groups: Dictionary,
	binding_context: Variant = null,
	binding_scope: Dictionary = {},
	key_scope: String = "",
	document_rebuild_bindings: PackedStringArray = PackedStringArray()
) -> Control:
	var source_element: Variant = element
	if not _condition_allows(element, binding_context, binding_scope, diagnostics, document_rebuild_bindings, key_path == "0"):
		return null
	var class_resolution := _resolve_bound_classes(element, binding_context, binding_scope, diagnostics)
	var class_binding_path := str(class_resolution["path"])
	if bool(class_resolution["bound"]):
		element = _clone_element_surface(element)
		element.attributes["class"] = class_resolution["value"]
	var control: Control
	if element.tag_name.to_lower() == "repeat" and element.children.size() == 1 and element.children[0].tag_name.to_lower() == "tablerow":
		control = CascadeTablePart.new()
		control.set("semantic_role", "group")
	else:
		control = _create_control(element, diagnostics)
	if control == null:
		return null

	control.name = element.element_id() if not element.element_id().is_empty() else element.tag_name
	control.set_meta("cascade_element_type", element.tag_name)
	control.set_meta("cascade_id", element.element_id())
	var component_scope := str(element.attributes.get("__component_scope", ""))
	control.set_meta("cascade_component_scope", component_scope)
	control.set_meta("cascade_scoped_id", "%s/%s" % [component_scope, element.element_id()] if not component_scope.is_empty() and not element.element_id().is_empty() else element.element_id())
	if element.attributes.has("__component_name"):
		control.set_meta("cascade_component_name", element.attributes["__component_name"])
	control.set_meta("cascade_classes", element.classes())
	var local_key: String = "#%s/%s" % [component_scope, element.element_id()] if not component_scope.is_empty() and not element.element_id().is_empty() else ("#" + element.element_id() if not element.element_id().is_empty() else key_path)
	control.set_meta("cascade_key", "%s/%s" % [key_scope, local_key] if not key_scope.is_empty() else local_key)
	control.set_meta("cascade_bindings", {})
	control.set_meta("cascade_rebuild_bindings", PackedStringArray([class_binding_path]) if not class_binding_path.is_empty() else PackedStringArray())
	control.set_meta("cascade_writable_bindings", {})
	control.set_meta("cascade_events", {})
	control.set_meta("cascade_binding_scope", binding_scope)
	control.set_meta("cascade_condition_binding", BindingCompiler.binding_path(str(element.attributes.get("if", ""))))
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
		control.set_meta("cascade_repeat_element", source_element)
		control.set_meta("cascade_repeat_rule_index", rule_index)
		control.set_meta("cascade_repeat_key_path", key_path)
		control.set_meta("cascade_repeat_key_scope", key_scope)
		_build_repeat_children(control, element, rule_index, diagnostics, key_path, button_groups, binding_context, key_scope, document_rebuild_bindings)
		return control

	for index in element.children.size():
		var child_element = element.children[index]
		if child_element.tag_name.to_lower() == "bindings":
			continue
		var child_key := "%s/%s:%s" % [key_path, index, child_element.tag_name]
		var child_control := _build_element(child_element, rule_index, diagnostics, child_key, button_groups, binding_context, binding_scope, key_scope, document_rebuild_bindings)
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
	key_scope: String,
	document_rebuild_bindings: PackedStringArray
) -> void:
	if element.children.size() != 1:
		diagnostics.append(_diagnostic("error", "Repeat requires exactly one child template."))
		return
	var raw_items := str(element.attributes.get("items", "")).strip_edges()
	if raw_items.length() < 3 or not raw_items.begins_with("{") or not raw_items.ends_with("}"):
		diagnostics.append(_diagnostic("error", "Repeat 'items' must be an exact binding such as '{inventory.items}'."))
		return
	var items_path := BindingCompiler.binding_path(raw_items)
	control.set_meta("cascade_collection_binding", items_path)
	var resolved := BindingResolver.resolve(binding_context, items_path)
	if not resolved["found"]:
		diagnostics.append(_diagnostic("error", "Repeat could not resolve items: %s" % resolved["message"]))
		return
	var collection: Variant = resolved["value"]
	if not collection is Array and not collection is CascadeItemModel:
		diagnostics.append(_diagnostic("error", "Repeat 'items' must resolve to an Array or CascadeItemModel."))
		return
	if collection is CascadeItemModel:
		control.set_meta("cascade_collection_model", collection)
	var key_property := str(element.attributes.get("key", "")).strip_edges()
	var repeat_keys := PackedStringArray()
	var collection_count: int = collection.size() if collection is Array else collection.item_count()
	var virtual := _raw_boolean_attribute(element.attributes, "virtual")
	var scanned_key_entries: Array = []
	var key_counts: Dictionary = {}
	var duplicate_keys: Dictionary = {}
	var missing_key_count := 0
	var scanned_count := 0
	var validated_keys: Variant = element.attributes.get("__validated_model_keys")
	if validated_keys is Array:
		if not virtual:
			diagnostics.append(_diagnostic("error", "A retained key cache can only rebuild a virtual Repeat."))
			return
		if validated_keys.size() != collection_count:
			diagnostics.append(_diagnostic("error", "Retained Repeat key cache count does not match the item model; emit RESET to resynchronize it."))
			return
		scanned_key_entries = validated_keys
		repeat_keys = PackedStringArray(validated_keys)
		scanned_count = int(element.attributes.get("__keys_scanned", 0))
	else:
		for index in collection_count:
			var key_item: Variant = collection[index] if collection is Array else collection.item_at(index)
			var scanned_key := str(index)
			var key_found := true
			if not key_property.is_empty():
				var key_result := BindingResolver.resolve(key_item, key_property)
				if not key_result["found"]:
					key_found = false
					missing_key_count += 1
					diagnostics.append(_diagnostic("error", "Repeat key '%s' could not be resolved for item %s." % [key_property, index]))
				else:
					scanned_key = str(key_result["value"])
			elif collection is CascadeItemModel:
				scanned_key = str(collection.key_at(index))
			scanned_count += 1
			if not key_found:
				scanned_key_entries.append(null)
				continue
			scanned_key_entries.append(scanned_key)
			repeat_keys.append(scanned_key)
			var next_count := int(key_counts.get(scanned_key, 0)) + 1
			key_counts[scanned_key] = next_count
			if next_count > 1:
				duplicate_keys[scanned_key] = next_count
		for duplicate_key in duplicate_keys:
			diagnostics.append(_diagnostic("error", "Repeat key '%s' is duplicated." % duplicate_key))
	control.set_meta("cascade_repeat_keys_scanned", scanned_count)
	if collection is Array:
		control.set_meta("cascade_collection_is_array", true)
		control.set_meta("cascade_array_key_cache_valid", missing_key_count == 0 and duplicate_keys.is_empty())
	if collection is CascadeItemModel:
		control.set_meta("cascade_item_model_key_cache", scanned_key_entries)
		control.set_meta("cascade_item_model_key_counts", key_counts)
		control.set_meta("cascade_item_model_duplicate_keys", duplicate_keys)
		control.set_meta("cascade_item_model_missing_key_count", missing_key_count)
		control.set_meta("cascade_item_model_cache_valid", missing_key_count == 0 and duplicate_keys.is_empty())
		control.set_meta("cascade_item_model_cache_model_id", collection.get_instance_id())
		control.set_meta("cascade_item_model_cache_key_property", key_property)
		control.set_meta("cascade_item_model_cache_from_full_scan", not validated_keys is Array)
	if missing_key_count > 0 or not duplicate_keys.is_empty():
		return
	var item_height := 0.0
	var overscan := 3
	var realized_indices: Array[int] = []
	if virtual:
		if key_property.is_empty():
			diagnostics.append(_diagnostic("error", "Virtual Repeat requires an explicit stable 'key'."))
			return
		if not str(element.children[0].attributes.get("if", "")).strip_edges().is_empty():
			diagnostics.append(_diagnostic("error", "Virtual Repeat item roots cannot use 'if'; filter the item model before binding it."))
			return
		item_height = _positive_pixel_attribute(element, "item-height", diagnostics)
		if item_height <= 0.0:
			return
		var raw_overscan := str(element.attributes.get("overscan", "3")).strip_edges()
		if not raw_overscan.is_valid_int() or raw_overscan.to_int() < 0:
			diagnostics.append(_diagnostic("error", "Virtual Repeat 'overscan' requires a non-negative integer."))
			return
		overscan = raw_overscan.to_int()
		if control is CascadeBox and (control.wrap or control.direction != CascadeBox.FlowDirection.COLUMN):
			diagnostics.append(_diagnostic("error", "Virtual Repeat requires a non-wrapping vertical layout."))
			return
		var viewport_extent := float(element.attributes.get("__virtual_viewport_extent", rule_index.get("viewport_size", Vector2(0.0, 600.0)).y))
		if viewport_extent <= 0.0:
			viewport_extent = 600.0
		var layout_gap := float(control.get("gap")) if control is CascadeBox else 0.0
		var window := CascadeVirtualWindow.new(collection_count, item_height + layout_gap, viewport_extent, overscan)
		window.set_scroll_offset(float(element.attributes.get("__virtual_scroll_offset", 0.0)))
		for index in range(window.first_index, window.end_index):
			realized_indices.append(index)
		var pinned_key := str(element.attributes.get("__virtual_pinned_key", ""))
		var pinned_index := repeat_keys.find(pinned_key) if not pinned_key.is_empty() else -1
		if pinned_index >= 0 and pinned_index < collection_count and pinned_index not in realized_indices:
			realized_indices.append(pinned_index)
			realized_indices.sort()
		control.set_meta("cascade_virtual", true)
		control.set_meta("cascade_virtual_item_height", item_height)
		control.set_meta("cascade_virtual_item_extent", item_height + layout_gap)
		control.set_meta("cascade_virtual_overscan", overscan)
		control.set_meta("cascade_virtual_model_count", collection_count)
		control.set_meta("cascade_virtual_first_index", window.first_index)
		control.set_meta("cascade_virtual_end_index", window.end_index)
		control.set_meta("cascade_virtual_scroll_offset", window.scroll_offset)
		control.set_meta("cascade_virtual_viewport_extent", viewport_extent)
		control.set_meta("cascade_virtual_pinned_index", pinned_index)
		control.set_meta("cascade_virtual_pinned_key", pinned_key if pinned_index >= 0 else "")
	else:
		for index in collection_count:
			realized_indices.append(index)
	var next_index := 0
	var actual_realized_count := 0
	for index in realized_indices:
		if virtual and index > next_index:
			_add_virtual_spacer(control, next_index, index - next_index, item_height)
		var item: Variant = collection[index] if collection is Array else collection.item_at(index)
		var item_key := repeat_keys[index]
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
			repeated_key_scope,
			document_rebuild_bindings
		)
		if child != null:
			actual_realized_count += 1
			child.set_meta("cascade_repeat_index", index)
			if virtual:
				if _virtual_item_has_vertical_margin(child):
					diagnostics.append(_diagnostic("error", "Virtual Repeat item roots cannot use vertical margins; include spacing in item-height or the Repeat gap."))
				_apply_virtual_item_height(child, item_height)
				var measured_height := maxf(child.get_minimum_size().y, child.custom_minimum_size.y)
				if measured_height > item_height + 0.01:
					diagnostics.append(_diagnostic("error", "Virtual Repeat item minimum height %.2fpx exceeds item-height %.2fpx; increase item-height or reduce the row content." % [measured_height, item_height]))
			control.add_child(child)
		next_index = index + 1
	if virtual and next_index < collection_count:
		_add_virtual_spacer(control, next_index, collection_count - next_index, item_height)
	control.set_meta("cascade_repeat_keys", repeat_keys)
	control.set_meta("cascade_virtual_realized_count", actual_realized_count if virtual else collection_count)
	control.set_meta("cascade_collection_transaction_valid", true)


static func _positive_pixel_attribute(element, attribute_name: String, diagnostics: Array[Dictionary]) -> float:
	var raw_value := str(element.attributes.get(attribute_name, "")).strip_edges().to_lower()
	if raw_value.ends_with("px"):
		raw_value = raw_value.trim_suffix("px").strip_edges()
	if not raw_value.is_valid_float() or raw_value.to_float() <= 0.0:
		diagnostics.append(_diagnostic("error", "Virtual Repeat '%s' requires a positive pixel length." % attribute_name))
		return 0.0
	return raw_value.to_float()


static func _add_virtual_spacer(control: Control, start_index: int, count: int, item_height: float) -> void:
	if count <= 0:
		return
	var gap := float(control.get("gap")) if control is CascadeBox else 0.0
	var spacer_height := maxf(0.0, float(count) * (item_height + gap) - gap)
	var spacer: Control
	if control is CascadeTablePart:
		var row := CascadeTablePart.new()
		row.semantic_role = "row"
		var cell := CascadeTableCell.new()
		cell.set_meta("cascade_table_role", "cell")
		cell.custom_minimum_size = Vector2(0.0, spacer_height)
		row.add_child(cell)
		spacer = row
	else:
		spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0.0, spacer_height)
	spacer.name = "VirtualSpacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.focus_mode = Control.FOCUS_NONE
	spacer.set_meta("cascade_element_type", "virtual-spacer")
	spacer.set_meta("cascade_key", "__virtual_spacer:%s:%s" % [start_index, count])
	spacer.set_meta("cascade_virtual_spacer", true)
	spacer.set_meta("cascade_virtual_start_index", start_index)
	spacer.set_meta("cascade_virtual_count", count)
	control.add_child(spacer)


static func _apply_virtual_item_height(control: Control, item_height: float) -> void:
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, item_height)
	if str(control.get_meta("cascade_table_role", "")) == "row":
		for child in control.get_children():
			if child is Control and str(child.get_meta("cascade_table_role", "")) in ["cell", "columnheader"]:
				child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, item_height)


static func _virtual_item_has_vertical_margin(control: Control) -> bool:
	if not _has_property(control, "cascade_style"):
		return false
	var style: CascadeStyle = control.get("cascade_style")
	return style != null and (style.margin_top > 0.0 or style.margin_bottom > 0.0)


static func _create_control(element, diagnostics: Array[Dictionary]) -> Control:
	var tag_name: String = element.tag_name
	var attributes: Dictionary = element.attributes
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
			diagnostics.append(_diagnostic_at(
				"error",
				"Unknown GXML element <%s>. Register a native control factory before using it." % tag_name,
				element
			))
			return null


static func _raw_boolean_attribute(attributes: Dictionary, attribute_name: String) -> bool:
	if not attributes.has(attribute_name):
		return false
	return str(attributes[attribute_name]).strip_edges().to_lower() in ["true", "1", "yes", "on", attribute_name]


static func _is_text_input(control: Control) -> bool:
	return control is CascadeTextInput or control is CascadeTextArea


static func _compute_declarations(element, rule_index: Dictionary) -> Dictionary:
	var viewport_size: Vector2 = rule_index.get("viewport_size", Vector2.ZERO)
	var cache_key := "%s|%s,%s|%s" % [rule_index.get("revision", 0), viewport_size.x, viewport_size.y, _element_signature(element)]
	if ComputedStyleCache.has(cache_key):
		return ComputedStyleCache.retrieve(cache_key)
	var winners := _compute_declarations_uncached(element, rule_index)
	_inherit_declarations(element, rule_index, winners)
	ComputedStyleCache.put(cache_key, winners, _element_dependencies(element))
	return winners


static func _compute_declarations_uncached(element, rule_index: Dictionary) -> Dictionary:
	var winners := {"__diagnostics": []}
	var matched_rules := []
	for rule in _candidate_rules(element, rule_index):
		if not rule.matches(element, float(rule_index.get("viewport_width", INF))):
			continue
		matched_rules.append(rule)
	var custom_properties := _compute_custom_properties(element, rule_index, matched_rules)
	winners["__custom_properties"] = custom_properties
	for rule in matched_rules:
		var state: String = rule.pseudo_state
		if not winners.has(state):
			winners[state] = {}
		var resolved_declarations := {}
		var resolution_errors := {}
		var environment: Dictionary = custom_properties.get(state, custom_properties.get("", {}))
		for property_name in rule.declarations:
			if str(property_name).begins_with("--"):
				continue
			var resolved := GcssExpression.resolve_variables(str(rule.declarations[property_name]), environment)
			if not bool(resolved.get("ok", false)):
				resolved_declarations[property_name] = DeclarationApplier.INVALID_RESOLVED_VALUE
				resolution_errors[property_name] = resolved.get("error", "variable resolution failed")
				continue
			resolved_declarations[property_name] = resolved["value"]
		var expansion := DeclarationApplier.expand_shorthands(resolved_declarations)
		var declarations: Dictionary = expansion["values"]
		var origins: Dictionary = expansion["origins"]
		var shorthand_errors: Dictionary = expansion.get("errors", {})
		for property_name in declarations:
			var existing: Dictionary = winners[state].get(property_name, {})
			if existing.is_empty() or rule.specificity > existing["specificity"] or (
				rule.specificity == existing["specificity"] and rule.order >= existing["order"]
			):
				var origin: String = origins[property_name]
				var location: Dictionary = rule.declaration_locations.get(origin, {"line": rule.line, "column": 1})
				winners[state][property_name] = {
					"value": declarations[property_name],
					"invalid": declarations[property_name] == DeclarationApplier.INVALID_RESOLVED_VALUE,
					"resolution_error": resolution_errors.get(origin, shorthand_errors.get(origin, "invalid shorthand value")),
					"origin": origin,
					"specificity": rule.specificity,
					"order": rule.order,
					"line": location["line"],
					"column": location["column"],
				}
	var reported := {}
	for state in winners:
		if str(state).begins_with("__"):
			continue
		for property_name in winners[state]:
			var declaration: Dictionary = winners[state][property_name]
			if not bool(declaration.get("invalid", false)):
				continue
			var report_key := "%s|%s|%s|%s" % [state, declaration["line"], declaration["column"], declaration.get("origin", property_name)]
			if reported.has(report_key):
				continue
			reported[report_key] = true
			winners["__diagnostics"].append({
				"severity": "error",
				"line": declaration["line"],
				"column": declaration["column"],
				"message": "Property '%s' was ignored: %s" % [declaration.get("origin", property_name), declaration.get("resolution_error", "variable resolution failed")],
			})
	return winners


static func _compute_custom_properties(element, rule_index: Dictionary, matched_rules: Array) -> Dictionary:
	var base := {}
	var parent = element.parent_element()
	if parent != null:
		var parent_computed := _compute_declarations(parent, rule_index)
		base = parent_computed.get("__custom_properties", {}).get("", {}).duplicate(true)
	var by_state := {"": base}
	var winners := {"": {}}
	for rule in matched_rules:
		var state: String = rule.pseudo_state
		if not winners.has(state):
			winners[state] = {}
		for property_name in rule.declarations:
			if not str(property_name).begins_with("--"):
				continue
			var existing: Dictionary = winners[state].get(property_name, {})
			if existing.is_empty() or rule.specificity > existing["specificity"] or (
				rule.specificity == existing["specificity"] and rule.order >= existing["order"]
			):
				winners[state][property_name] = {
					"value": rule.declarations[property_name],
					"specificity": rule.specificity,
					"order": rule.order,
				}
	for property_name in winners[""]:
		var raw_value := str(winners[""][property_name]["value"])
		if raw_value.strip_edges().to_lower() == "inherit":
			continue
		by_state[""][property_name] = raw_value
	for state in winners:
		if state.is_empty():
			continue
		var state_values: Dictionary = by_state[""].duplicate(true)
		for property_name in winners[state]:
			var raw_value := str(winners[state][property_name]["value"])
			if raw_value.strip_edges().to_lower() == "inherit":
				continue
			state_values[property_name] = raw_value
		by_state[state] = state_values
	return by_state


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
	var index := {"universal": [], "types": {}, "classes": {}, "ids": {}, "revision": _rules_revision(rules), "viewport_width": viewport_width, "viewport_size": viewport_size}
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
	_apply_focus_attributes(control, attributes, diagnostics)
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


static func _apply_focus_attributes(control: Control, attributes: Dictionary, diagnostics: Array[Dictionary]) -> void:
	if attributes.has("tab-index"):
		var raw_index := str(attributes["tab-index"]).strip_edges()
		if not raw_index.is_valid_int() or raw_index.to_int() < -1:
			diagnostics.append(_control_diagnostic(control, "Attribute 'tab-index' requires an integer of -1 or greater, got '%s'." % raw_index))
		else:
			control.set_meta("cascade_tab_index", raw_index.to_int())
	for attribute_name in ["autofocus", "focus-trap"]:
		if not attributes.has(attribute_name):
			continue
		var parsed: Variant = _parse_bool_attribute(attribute_name, str(attributes[attribute_name]), diagnostics)
		if parsed == null or not parsed:
			continue
		if attribute_name == "autofocus":
			control.set_meta("cascade_autofocus", true)
		else:
			var element_type := str(control.get_meta("cascade_element_type", "")).to_lower()
			if element_type not in ["page", "row", "column", "panel", "stack", "grid"]:
				diagnostics.append(_control_diagnostic(control, "Attribute 'focus-trap' requires a container element."))
			else:
				control.set_meta("cascade_focus_trap", true)


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
	control.set_meta("cascade_radio_group_name", group_name)


static func collect_button_groups(document_root: Node) -> Dictionary:
	var result: Dictionary = {}
	if document_root != null:
		_collect_button_groups(document_root, result)
	return result


static func remap_button_groups(root: Node, document_groups: Dictionary) -> void:
	if root is BaseButton and root.has_meta("cascade_radio_group_name"):
		var group_name := str(root.get_meta("cascade_radio_group_name"))
		var candidate_group: ButtonGroup = root.get("button_group")
		if not document_groups.has(group_name):
			document_groups[group_name] = candidate_group if candidate_group != null else ButtonGroup.new()
		root.set("button_group", document_groups[group_name])
	for child in root.get_children():
		remap_button_groups(child, document_groups)


static func _collect_button_groups(node: Node, result: Dictionary) -> void:
	if node is BaseButton and node.has_meta("cascade_radio_group_name"):
		var group_name := str(node.get_meta("cascade_radio_group_name"))
		var group: ButtonGroup = node.get("button_group")
		if not group_name.is_empty() and group != null and not result.has(group_name):
			result[group_name] = group
	for child in node.get_children():
		_collect_button_groups(child, result)


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
) -> Dictionary:
	var raw_value := str(element.attributes.get("class", ""))
	if raw_value.strip_edges().begins_with("@"):
		return {"path": "", "value": "", "bound": true}
	var path := BindingCompiler.binding_path(raw_value)
	if path.is_empty():
		return {"path": "", "value": raw_value, "bound": false}
	var first_segment := path.get_slice(".", 0)
	var context: Variant = binding_scope if binding_scope.has(first_segment) else binding_context
	var result := BindingResolver.resolve(context, path)
	if not result["found"]:
		diagnostics.append(_diagnostic("warning", "class binding: %s" % result["message"]))
		return {"path": path, "value": "", "bound": true}
	var class_result := _class_string(result["value"])
	if not class_result["valid"]:
		diagnostics.append(_diagnostic("warning", "class binding '%s' requires a String or an Array of class names." % path))
		return {"path": path, "value": "", "bound": true}
	return {"path": path, "value": class_result["value"], "bound": true}


static func _clone_element_surface(element):
	var clone := GxmlParser.Element.new(element.tag_name, element.parent_element())
	clone.attributes = element.attributes.duplicate(true)
	clone.text = element.text
	clone.raw_text = element.raw_text
	clone.source_offset = element.source_offset
	clone.source_line = element.source_line
	clone.source_column = element.source_column
	for child in element.children:
		clone.children.append(_clone_element_with_parent(child, clone))
	return clone


static func _clone_element_with_parent(element, parent):
	var clone := GxmlParser.Element.new(element.tag_name, parent)
	clone.attributes = element.attributes.duplicate(true)
	clone.text = element.text
	clone.raw_text = element.raw_text
	clone.source_offset = element.source_offset
	clone.source_line = element.source_line
	clone.source_column = element.source_column
	for child in element.children:
		clone.children.append(_clone_element_with_parent(child, clone))
	return clone


static func _condition_allows(
	element,
	binding_context: Variant,
	binding_scope: Dictionary,
	diagnostics: Array[Dictionary],
	document_rebuild_bindings: PackedStringArray,
	is_root: bool
) -> bool:
	if not element.attributes.has("if"):
		return true
	if is_root:
		diagnostics.append(_diagnostic("error", "The document root cannot use conditional 'if'."))
		return false
	var raw_value := str(element.attributes["if"]).strip_edges()
	var path := BindingCompiler.binding_path(raw_value)
	if path.is_empty():
		diagnostics.append(_diagnostic("error", "Conditional 'if' requires an exact {dot.separated.path}."))
		return false
	var first_segment := path.get_slice(".", 0)
	if not binding_scope.has(first_segment) and path not in document_rebuild_bindings:
		document_rebuild_bindings.append(path)
	var context: Variant = binding_scope if binding_scope.has(first_segment) else binding_context
	var result := BindingResolver.resolve(context, path)
	if not result["found"]:
		diagnostics.append(_diagnostic("warning", "conditional binding: %s" % result["message"]))
		return false
	if not result["value"] is bool:
		diagnostics.append(_diagnostic("warning", "Conditional binding '%s' requires a boolean value." % path))
		return false
	return result["value"]


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


static func _control_diagnostic(control: Control, message: String) -> Dictionary:
	return {
		"severity": "error",
		"message": message,
		"line": int(control.get_meta("cascade_source_line", 1)),
		"column": int(control.get_meta("cascade_source_column", 1)),
	}


static func _diagnostic_at(severity: String, message: String, element) -> Dictionary:
	return {
		"severity": severity,
		"line": element.source_line,
		"column": element.source_column,
		"message": message,
	}
