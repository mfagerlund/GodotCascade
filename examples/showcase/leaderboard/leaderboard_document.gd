extends "res://addons/godot_cascade/runtime/cascade_document.gd"

const LeaderboardState := preload("res://examples/showcase/leaderboard/leaderboard_state.gd")

var model := LeaderboardState.new()


func _ready() -> void:
	binding_context = model
	event_context = self
	document_reloaded.connect(_on_document_reloaded)
	super()


func _on_add_pilot() -> void:
	if model.entries.size() >= 6:
		model.status = "Table holds six pilots · remove one to add another"
		refresh_bindings()
		return
	var entry: LeaderboardState.Entry = model.add_pilot()
	model.status = "Added %s · drag a handle to reorder" % entry.pilot
	refresh_bindings()


func _on_sort_rating() -> void:
	model.sort_by_rating()
	model.status = "Sorted by rating · highest first"
	refresh_bindings()


func _on_remove_pilot(entry_id: String) -> void:
	var pilot := model.remove_pilot(entry_id)
	if pilot.is_empty():
		return
	model.status = "Removed %s · %s pilots remain" % [pilot, model.entries.size()]
	refresh_bindings()


func _on_document_reloaded(_root: Control) -> void:
	_wire_row_interactions.call_deferred()


func _wire_row_interactions() -> void:
	var root := generated_root()
	if root == null:
		return
	for remove_button in _find_by_class(root, "remove-pilot"):
		var entry := _scoped_entry(remove_button)
		if entry == null:
			continue
		var previous: Callable = remove_button.get_meta("showcase_remove_callback", Callable())
		if previous.is_valid() and remove_button.pressed.is_connected(previous):
			remove_button.pressed.disconnect(previous)
		var callback := _on_remove_pilot.bind(entry.id)
		remove_button.pressed.connect(callback)
		remove_button.set_meta("showcase_remove_callback", callback)

	for row in _find_by_class(root, "pilot-row"):
		var entry := _scoped_entry(row)
		if entry == null:
			continue
		row.set_drag_forwarding(
			_no_drag_data,
			_can_drop_pilot.bind(entry.id),
			_drop_pilot.bind(entry.id)
		)
		for cell in row.get_children():
			if cell is Control:
				cell.set_drag_forwarding(
					_no_drag_data,
					_can_drop_pilot.bind(entry.id),
					_drop_pilot.bind(entry.id)
				)

	for handle in _find_by_class(root, "drag-handle"):
		var entry := _scoped_entry(handle)
		if entry == null:
			continue
		handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
		handle.set_drag_forwarding(
			_get_pilot_drag_data.bind(handle, entry.id, entry.pilot),
			_no_drop,
			_ignore_drop
		)


func _get_pilot_drag_data(_position: Vector2, handle: Control, entry_id: String, pilot: String) -> Variant:
	var preview := Label.new()
	preview.text = "Move %s" % pilot
	preview.add_theme_color_override("font_color", Color("f2f5fb"))
	preview.add_theme_color_override("font_shadow_color", Color("0a0f19"))
	preview.add_theme_constant_override("shadow_offset_x", 1)
	preview.add_theme_constant_override("shadow_offset_y", 1)
	handle.set_drag_preview(preview)
	return {"kind": "leaderboard-pilot", "id": entry_id, "pilot": pilot}


func _can_drop_pilot(_position: Vector2, data: Variant, target_id: String) -> bool:
	return data is Dictionary and data.get("kind", "") == "leaderboard-pilot" and data.get("id", "") != target_id


func _drop_pilot(_position: Vector2, data: Variant, target_id: String) -> void:
	if not _can_drop_pilot(Vector2.ZERO, data, target_id):
		return
	if model.move_before(str(data["id"]), target_id):
		model.status = "Moved %s · standings manually reordered" % data.get("pilot", "pilot")
		refresh_bindings()


func _no_drag_data(_position: Vector2) -> Variant:
	return null


func _no_drop(_position: Vector2, _data: Variant) -> bool:
	return false


func _ignore_drop(_position: Vector2, _data: Variant) -> void:
	pass


func _scoped_entry(control: Control) -> LeaderboardState.Entry:
	var scope: Dictionary = control.get_meta("cascade_binding_scope", {})
	return scope.get("item") as LeaderboardState.Entry


func _find_by_class(node: Node, selector_class: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and selector_class in node.get_meta("cascade_classes", PackedStringArray()):
		matches.append(node)
	for child in node.get_children():
		matches.append_array(_find_by_class(child, selector_class))
	return matches
