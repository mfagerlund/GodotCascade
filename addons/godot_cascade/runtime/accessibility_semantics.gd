extends RefCounted

## Applies semantic roles to GodotCascade-owned controls when Godot's native
## accessibility bridge is active. Native controls keep their built-in state,
## actions, and range updates; this helper corrects only the owned role surface.


static func set_role(control: Control, role: int) -> RID:
	if not AccessibilityServer.is_supported():
		return RID()
	var element := control.get_accessibility_element()
	if not element.is_valid():
		return RID()
	AccessibilityServer.update_set_role(element, role)
	return element


static func set_numeric(control: Control, role: int, value: float, minimum: float, maximum: float, step: float = 0.0) -> RID:
	var element := set_role(control, role)
	if not element.is_valid():
		return RID()
	AccessibilityServer.update_set_num_range(element, minimum, maximum)
	AccessibilityServer.update_set_num_value(element, value)
	if step > 0.0:
		AccessibilityServer.update_set_num_step(element, step)
	return element


static func set_table(control: Control) -> RID:
	var element := set_role(control, AccessibilityServer.ROLE_TABLE)
	if not element.is_valid():
		return RID()
	var snapshot := refresh_table_metadata(control)
	AccessibilityServer.update_set_table_row_count(element, int(snapshot["row_count"]))
	AccessibilityServer.update_set_table_column_count(element, int(snapshot["column_count"]))
	return element


static func set_table_part(control: Control, is_row: bool) -> RID:
	var element := set_role(control, AccessibilityServer.ROLE_ROW if is_row else AccessibilityServer.ROLE_ROW_GROUP)
	if not element.is_valid() or not is_row:
		return element
	var table := _table_ancestor(control)
	if table != null:
		var row_index := int(control.get_meta("cascade_accessibility_row_index", -1))
		if row_index < 0:
			refresh_table_metadata(table)
			row_index = int(control.get_meta("cascade_accessibility_row_index", -1))
		if row_index >= 0:
			AccessibilityServer.update_set_table_row_index(element, row_index)
	return element


static func set_table_cell(control: Control, header: bool) -> RID:
	var element := set_role(control, AccessibilityServer.ROLE_COLUMN_HEADER if header else AccessibilityServer.ROLE_CELL)
	if not element.is_valid():
		return RID()
	var row := control.get_parent() as Control
	var table := _table_ancestor(control)
	if row != null and table != null:
		var row_index := int(control.get_meta("cascade_accessibility_row_index", -1))
		var column := int(control.get_meta("cascade_accessibility_column_index", -1))
		if row_index < 0 or column < 0:
			refresh_table_metadata(table)
			row_index = int(control.get_meta("cascade_accessibility_row_index", -1))
			column = int(control.get_meta("cascade_accessibility_column_index", -1))
		if row_index >= 0 and column >= 0:
			AccessibilityServer.update_set_table_cell_position(element, row_index, column)
			AccessibilityServer.update_set_table_cell_span(element, 1, 1)
	return element


## Returns total/global table semantics, including unrealized virtual Repeat rows.
## The snapshot is independent of the platform accessibility backend and is
## therefore suitable for headless validation.
static func table_snapshot(table: Control) -> Dictionary:
	var result := {"row_count": 0, "column_count": 0, "rows": []}
	var cursor := [0]
	_collect_table_snapshot(table, result, cursor)
	result["row_count"] = cursor[0]
	return result


## Refreshes headless-readable derived indices before native notifications run.
static func refresh_table_metadata(table: Control) -> Dictionary:
	var snapshot := table_snapshot(table)
	table.set_meta("cascade_accessibility_row_count", snapshot["row_count"])
	table.set_meta("cascade_accessibility_column_count", snapshot["column_count"])
	for entry in snapshot["rows"]:
		var row: Control = entry["control"]
		row.set_meta("cascade_accessibility_row_index", entry["index"])
		var cells: Array[Control] = entry["cells"]
		for column in cells.size():
			cells[column].set_meta("cascade_accessibility_row_index", entry["index"])
			cells[column].set_meta("cascade_accessibility_column_index", column)
	return snapshot


## Coalesces semantic updates at the owned table ancestor.
static func queue_table_updates(control: Control) -> void:
	var table := _table_ancestor(control)
	if table != null and table.has_method("request_accessibility_structure_update"):
		table.call("request_accessibility_structure_update")


static func set_select(control: Control, option_buttons: Array[BaseButton], selected_index: int, highlighted_index: int) -> RID:
	var element := set_role(control, AccessibilityServer.ROLE_LIST_BOX)
	if not element.is_valid():
		return RID()
	AccessibilityServer.update_set_popup_type(element, AccessibilityServer.POPUP_LIST)
	AccessibilityServer.update_set_list_item_count(element, option_buttons.size())
	var active := RID()
	for index in option_buttons.size():
		var option_element := set_role(option_buttons[index], AccessibilityServer.ROLE_LIST_BOX_OPTION)
		if not option_element.is_valid():
			continue
		AccessibilityServer.update_set_list_item_index(option_element, index)
		AccessibilityServer.update_set_list_item_selected(option_element, index == selected_index)
		AccessibilityServer.update_set_flag(option_element, AccessibilityServer.FLAG_DISABLED, option_buttons[index].disabled)
		if index == highlighted_index:
			active = option_element
	if active.is_valid():
		AccessibilityServer.update_set_active_descendant(element, active)
	return element


static func _table_ancestor(control: Control) -> Control:
	var ancestor: Node = control
	while ancestor is Control:
		if str(ancestor.get_meta("cascade_table_role", "")) == "table":
			return ancestor
		ancestor = ancestor.get_parent()
	return null


static func _collect_table_snapshot(node: Node, result: Dictionary, cursor: Array) -> void:
	for child in node.get_children():
		if not child is Control or not child.visible or child.top_level:
			continue
		var role := str(child.get_meta("cascade_table_role", ""))
		if role == "row":
			_append_table_row(result, child, int(cursor[0]))
			cursor[0] = int(cursor[0]) + 1
		elif role in ["header", "body", "group"]:
			if role == "group" and bool(child.get_meta("cascade_virtual", false)):
				_collect_virtual_table_group(child, result, cursor)
			else:
				_collect_table_snapshot(child, result, cursor)


static func _collect_virtual_table_group(group: Control, result: Dictionary, cursor: Array) -> void:
	var base_index := int(cursor[0])
	var model_count := maxi(int(group.get_meta("cascade_virtual_model_count", 0)), 0)
	for child in group.get_children():
		if not child is Control or not child.visible or child.top_level:
			continue
		if str(child.get_meta("cascade_table_role", "")) != "row" or not child.has_meta("cascade_repeat_index"):
			continue
		var model_index := int(child.get_meta("cascade_repeat_index", -1))
		if model_index >= 0 and model_index < model_count:
			_append_table_row(result, child, base_index + model_index)
	cursor[0] = base_index + model_count


static func _append_table_row(result: Dictionary, row: Control, index: int) -> void:
	var cells := _row_cells(row)
	result["column_count"] = maxi(int(result["column_count"]), cells.size())
	result["rows"].append({"control": row, "index": index, "cells": cells})


static func _row_cells(row: Control) -> Array[Control]:
	var result: Array[Control] = []
	for child in row.get_children():
		if child is Control and child.visible and not child.top_level and str(child.get_meta("cascade_table_role", "")) in ["cell", "columnheader"]:
			result.append(child)
	return result
