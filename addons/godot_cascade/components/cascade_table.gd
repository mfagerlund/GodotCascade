@tool
extends Container

## Semantic table container with one shared column calculation across all rows.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const GridLayoutEngine := preload("res://addons/godot_cascade/layout/grid_layout_engine.gd")

@export var column_tracks: Array[Dictionary] = []:
	set(value):
		column_tracks = value
		request_table_layout()
@export var column_gap := 0.0:
	set(value):
		column_gap = maxf(value, 0.0)
		request_table_layout()
@export var row_gap := 0.0:
	set(value):
		row_gap = maxf(value, 0.0)
		request_table_layout()
@export var gap := 0.0:
	set(value):
		gap = maxf(value, 0.0)
		column_gap = gap
		row_gap = gap
		request_table_layout()
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		var next := value if value != null else CascadeStyle.new()
		if cascade_style == next:
			return
		_disconnect_style()
		cascade_style = next
		_connect_style()
		request_table_layout()
		queue_redraw()


func _ready() -> void:
	set_meta("cascade_table_role", "table")
	_connect_style()
	_apply_overflow()
	child_entered_tree.connect(_on_children_changed)
	child_exiting_tree.connect(_on_children_changed)
	queue_sort()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_arrange_table()


func _draw() -> void:
	BoxPainter.draw_box(
		self,
		Rect2(Vector2.ZERO, size),
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius,
		cascade_style.background_gradient
	)


func _get_minimum_size() -> Vector2:
	var model := _table_model(true)
	var columns: PackedFloat32Array = model["column_sizes"]
	var rows: PackedFloat32Array = model["row_sizes"]
	var content := Vector2(_sum(columns), _sum(rows))
	content.x += column_gap * maxf(columns.size() - 1, 0)
	content.y += row_gap * maxf(rows.size() - 1, 0)
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(content, cascade_style.padding(), cascade_style.border_width))


func request_table_layout() -> void:
	if not is_inside_tree():
		return
	update_minimum_size()
	queue_sort()
	queue_redraw()
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _arrange_table() -> void:
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	var records: Array[Dictionary] = []
	_collect_rows(self, [], records)
	if records.is_empty():
		return
	var tracks := _resolved_tracks(records, false)
	var items := _items(records)
	var result := GridLayoutEngine.arrange(content.size, tracks, [], items, column_gap, row_gap)
	var rects: Array = result["rects"]
	var row_rects: Array[Rect2] = []
	for row_index in records.size():
		var row_rect := Rect2(Vector2(0.0, INF), Vector2(content.size.x, 0.0))
		for item_index in items.size():
			if int(items[item_index]["row"]) != row_index:
				continue
			var cell_rect: Rect2 = rects[item_index]
			row_rect.position.y = minf(row_rect.position.y, cell_rect.position.y)
			row_rect.size.y = maxf(row_rect.size.y, cell_rect.size.y)
		if is_inf(row_rect.position.y):
			row_rect.position.y = 0.0 if row_index == 0 else row_rects[row_index - 1].end.y + row_gap
		row_rects.append(row_rect)

	var bounds := _ancestor_bounds(records, row_rects)
	var ancestors: Array = bounds.values()
	ancestors.sort_custom(func(a: Dictionary, b: Dictionary): return a["depth"] < b["depth"])
	for entry in ancestors:
		var part: Control = entry["node"]
		var parent_entry: Dictionary = bounds.get(entry["parent_id"], {})
		var parent_y := float(parent_entry.get("min_y", 0.0))
		var position := Vector2(0.0, float(entry["min_y"]) - parent_y)
		if parent_entry.is_empty():
			position += content.position
		var part_parent := part.get_parent() as Container
		if part_parent != null:
			part_parent.fit_child_in_rect(part, Rect2(position, Vector2(content.size.x, float(entry["max_y"]) - float(entry["min_y"]))))

	for row_index in records.size():
		var record: Dictionary = records[row_index]
		var row: Control = record["row"]
		var ancestor_chain: Array = record["ancestors"]
		var parent_y := 0.0
		if not ancestor_chain.is_empty():
			parent_y = float(bounds[ancestor_chain[-1].get_instance_id()]["min_y"])
		var row_position := Vector2(0.0, row_rects[row_index].position.y - parent_y)
		if ancestor_chain.is_empty():
			row_position += content.position
		var row_parent := row.get_parent() as Container
		if row_parent != null:
			row_parent.fit_child_in_rect(row, Rect2(row_position, row_rects[row_index].size))

	var cell_index := 0
	for row_index in records.size():
		var cells: Array[Control] = records[row_index]["cells"]
		for cell in cells:
			var cell_rect: Rect2 = rects[cell_index]
			cell_rect.position.y = 0.0
			var cell_parent := cell.get_parent() as Container
			if cell_parent != null:
				cell_parent.fit_child_in_rect(cell, cell_rect)
			cell_index += 1


func _table_model(measuring: bool) -> Dictionary:
	var records: Array[Dictionary] = []
	_collect_rows(self, [], records)
	if records.is_empty():
		return {"column_sizes": PackedFloat32Array(), "row_sizes": PackedFloat32Array()}
	var tracks := _resolved_tracks(records, measuring)
	var result := GridLayoutEngine.arrange(Vector2.ZERO, tracks, [], _items(records), column_gap, row_gap)
	return {"column_sizes": result["column_sizes"], "row_sizes": result["row_sizes"]}


func _resolved_tracks(records: Array[Dictionary], measuring: bool) -> Array[Dictionary]:
	var column_count := 0
	for record in records:
		column_count = maxi(column_count, record["cells"].size())
	var tracks: Array[Dictionary] = column_tracks.duplicate(true)
	while tracks.size() < column_count:
		tracks.append({"kind": "content"})
	if measuring:
		for index in tracks.size():
			var track: Dictionary = tracks[index]
			if track.get("kind", "content") == "fraction":
				tracks[index] = {"kind": "content"}
	return tracks


func _items(records: Array[Dictionary]) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for row_index in records.size():
		var cells: Array[Control] = records[row_index]["cells"]
		for column_index in cells.size():
			items.append({
				"minimum": cells[column_index].get_combined_minimum_size(),
				"column": column_index,
				"row": row_index,
			})
	return items


func _collect_rows(node: Node, ancestors: Array, records: Array[Dictionary]) -> void:
	for child in node.get_children():
		if not child is Control or not child.visible or child.top_level:
			continue
		var role := str(child.get_meta("cascade_table_role", ""))
		if role == "row":
			records.append({"row": child, "ancestors": ancestors.duplicate(), "cells": _row_cells(child)})
		elif role in ["header", "body", "group"]:
			var nested := ancestors.duplicate()
			nested.append(child)
			_collect_rows(child, nested, records)


func _row_cells(row: Control) -> Array[Control]:
	var result: Array[Control] = []
	for child in row.get_children():
		if child is Control and child.visible and not child.top_level and str(child.get_meta("cascade_table_role", "")) in ["cell", "columnheader"]:
			result.append(child)
	return result


func _ancestor_bounds(records: Array[Dictionary], row_rects: Array[Rect2]) -> Dictionary:
	var bounds := {}
	for row_index in records.size():
		var chain: Array = records[row_index]["ancestors"]
		for depth in chain.size():
			var part: Control = chain[depth]
			var id := part.get_instance_id()
			var entry: Dictionary = bounds.get(id, {
				"node": part,
				"depth": depth,
				"parent_id": chain[depth - 1].get_instance_id() if depth > 0 else 0,
				"min_y": INF,
				"max_y": 0.0,
			})
			entry["min_y"] = minf(float(entry["min_y"]), row_rects[row_index].position.y)
			entry["max_y"] = maxf(float(entry["max_y"]), row_rects[row_index].end.y)
			bounds[id] = entry
	return bounds


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _disconnect_style() -> void:
	if cascade_style != null and cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.disconnect(_on_style_invalidated)


func _on_style_invalidated(_flags: int) -> void:
	_apply_overflow()
	request_table_layout()


func _on_children_changed(_child: Node) -> void:
	request_table_layout.call_deferred()


func _sum(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP
