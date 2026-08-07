extends "res://addons/godot_cascade/runtime/cascade_document.gd"

const LeaderboardState := preload("res://examples/showcase/leaderboard/leaderboard_state.gd")

var model := LeaderboardState.new()
var _drag_source_id := ""
var _drag_target_id := ""


func _ready() -> void:
	binding_context = model
	event_context = self
	document_reloaded.connect(_on_document_reloaded)
	super()


func _on_add_pilot() -> void:
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

	for handle in _find_by_class(root, "drag-handle"):
		var entry := _scoped_entry(handle)
		if entry == null:
			continue
		handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
		var previous: Callable = handle.get_meta("showcase_drag_callback", Callable())
		if previous.is_valid() and handle.gui_input.is_connected(previous):
			handle.gui_input.disconnect(previous)
		var callback := _on_drag_handle_input.bind(handle, entry.id)
		handle.gui_input.connect(callback)
		handle.set_meta("showcase_drag_callback", callback)


func _on_drag_handle_input(event: InputEvent, handle: Control, entry_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_source_id = entry_id
			_update_drag_target(handle.get_global_mouse_position())
		else:
			_update_drag_target(handle.get_global_mouse_position())
			_commit_pointer_drag()
		handle.accept_event()
	elif event is InputEventMouseMotion and not _drag_source_id.is_empty():
		_update_drag_target(handle.get_global_mouse_position())
		handle.accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_up"):
			_move_pilot_by(entry_id, -1)
			handle.accept_event()
		elif event.is_action_pressed("ui_down"):
			_move_pilot_by(entry_id, 1)
			handle.accept_event()


func _update_drag_target(global_position: Vector2) -> void:
	_drag_target_id = ""
	var root := generated_root()
	if root == null:
		return
	for row in _find_by_class(root, "pilot-row"):
		var entry := _scoped_entry(row)
		var targeted := entry != null and row.get_global_rect().has_point(global_position)
		row.modulate = Color("c7dcff") if targeted else Color.WHITE
		if targeted:
			_drag_target_id = entry.id


func _commit_pointer_drag() -> void:
	var source_id := _drag_source_id
	var target_id := _drag_target_id
	_clear_drag_state()
	if source_id.is_empty() or target_id.is_empty() or source_id == target_id:
		return
	var pilot := model.pilot_name(source_id)
	if model.move_before(source_id, target_id):
		model.status = "Moved %s · standings manually reordered" % pilot
		refresh_bindings()


func _move_pilot_by(entry_id: String, offset: int) -> void:
	var pilot := model.pilot_name(entry_id)
	if model.move_by(entry_id, offset):
		model.status = "Moved %s · standings manually reordered" % pilot
		refresh_bindings()


func _clear_drag_state() -> void:
	_drag_source_id = ""
	_drag_target_id = ""
	var root := generated_root()
	if root == null:
		return
	for row in _find_by_class(root, "pilot-row"):
		row.modulate = Color.WHITE


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
