extends RefCounted

## Reconciles a freshly built native tree into an existing one using stable GXML keys.

const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")

const COPIED_PROPERTIES: PackedStringArray = [
	"direction", "wrap", "gap", "line_gap", "justify_content", "align_items", "pixel_snap",
	"column_tracks", "row_tracks", "column_gap", "row_gap",
	"text", "font", "font_size", "text_color", "horizontal_alignment", "vertical_alignment",
	"autowrap_mode", "text_overrun_behavior", "max_lines_visible", "text_alignment",
	"hover_background_color", "pressed_background_color", "checked_background_color", "open_background_color", "disabled_background_color",
	"checked_text_color", "disabled_text_color", "focus_ring_color", "focus_ring_width", "disabled", "toggle_mode",
	"button_group", "action_mode", "accessibility_name", "accessibility_description", "indicator_size", "indicator_gap",
	"indicator_background_color", "indicator_border_color", "checked_indicator_color",
	"checkmark_color", "disabled_indicator_color", "track_width", "track_height", "track_color",
	"checked_track_color", "thumb_color",
	"placeholder", "options", "option_background_color", "option_hover_background_color",
	"option_selected_background_color", "option_text_color", "option_selected_text_color", "option_height",
	"min_value", "max_value", "value", "fill_color", "fill_border_radius",
	"step", "track_height", "thumb_size", "thumb_color", "disabled_thumb_color",
	"texture", "fit",
]


static func reconcile(existing_root: Control, desired_root: Control) -> Dictionary:
	var stats := {"reused": 0, "created": 0, "replaced": 0, "removed": 0}
	if not _compatible(existing_root, desired_root):
		ComponentRegistry.unmount_tree(existing_root)
		stats["replaced"] = 1
		return {"root": desired_root, "stats": stats, "reused_root": false}

	_reconcile_node(existing_root, desired_root, stats)
	desired_root.free()
	return {"root": existing_root, "stats": stats, "reused_root": true}


static func _reconcile_node(existing: Control, desired: Control, stats: Dictionary) -> void:
	stats["reused"] = int(stats["reused"]) + 1
	_copy_properties(existing, desired)
	ComponentRegistry.update(existing)
	_reconcile_children(existing, desired, stats)


static func _reconcile_children(existing: Control, desired: Control, stats: Dictionary) -> void:
	var existing_by_key := {}
	for child in existing.get_children():
		if child is Control:
			existing_by_key[str(child.get_meta("cascade_key", ""))] = child

	var ordered_children: Array[Control] = []
	for desired_child_node in desired.get_children():
		if not desired_child_node is Control:
			continue
		var desired_child := desired_child_node as Control
		var key := str(desired_child.get_meta("cascade_key", ""))
		var existing_child: Control = existing_by_key.get(key)
		if existing_child != null and _compatible(existing_child, desired_child):
			_reconcile_node(existing_child, desired_child, stats)
			ordered_children.append(existing_child)
			existing_by_key.erase(key)
		elif existing_child != null:
			ComponentRegistry.unmount_tree(existing_child)
			existing.remove_child(existing_child)
			existing_child.queue_free()
			existing_by_key.erase(key)
			desired.remove_child(desired_child)
			existing.add_child(desired_child)
			ComponentRegistry.mount_tree(desired_child)
			ordered_children.append(desired_child)
			stats["replaced"] = int(stats["replaced"]) + 1
		else:
			desired.remove_child(desired_child)
			existing.add_child(desired_child)
			ComponentRegistry.mount_tree(desired_child)
			ordered_children.append(desired_child)
			stats["created"] = int(stats["created"]) + 1

	for remaining_child in existing_by_key.values():
		ComponentRegistry.unmount_tree(remaining_child)
		existing.remove_child(remaining_child)
		remaining_child.queue_free()
		stats["removed"] = int(stats["removed"]) + 1

	for index in ordered_children.size():
		existing.move_child(ordered_children[index], index)


static func _copy_properties(existing: Control, desired: Control) -> void:
	existing.name = desired.name
	existing.visible = desired.visible
	for metadata_name in ["cascade_element_type", "cascade_id", "cascade_classes", "cascade_key", "cascade_bindings", "cascade_events", "cascade_binding_scope", "cascade_explicit_accessible_label", "cascade_compatibility_tier"]:
		existing.set_meta(metadata_name, desired.get_meta(metadata_name))
	for metadata_name in ["cascade_position", "cascade_left", "cascade_top", "cascade_right", "cascade_bottom"]:
		if desired.has_meta(metadata_name):
			existing.set_meta(metadata_name, desired.get_meta(metadata_name))
		elif existing.has_meta(metadata_name):
			existing.remove_meta(metadata_name)
	for metadata_name in ["cascade_grid_column", "cascade_grid_row", "cascade_grid_column_span", "cascade_grid_row_span"]:
		if desired.has_meta(metadata_name):
			existing.set_meta(metadata_name, desired.get_meta(metadata_name))
		elif existing.has_meta(metadata_name):
			existing.remove_meta(metadata_name)

	if _has_property(existing, "cascade_style") and _has_property(desired, "cascade_style"):
		var desired_style: CascadeStyle = desired.get("cascade_style")
		existing.set("cascade_style", desired_style.duplicate(true))
	if existing.has_method("set_range_values") and desired.has_method("set_range_values"):
		existing.call("set_range_values", desired.get("min_value"), desired.get("max_value"), desired.get("value"))

	for property_name in COPIED_PROPERTIES:
		if property_name in ["min_value", "max_value", "value"] and existing.has_method("set_range_values"):
			continue
		if _has_property(existing, property_name) and _has_property(desired, property_name):
			existing.set(property_name, desired.get(property_name))


static func _compatible(existing: Control, desired: Control) -> bool:
	return (
		existing.get_script() == desired.get_script()
		and existing.get_meta("cascade_element_type", "") == desired.get_meta("cascade_element_type", "")
	)


static func _has_property(target: Object, property_name: String) -> bool:
	return PropertyCache.has(target, property_name)
