extends "res://addons/godot_cascade/runtime/cascade_document.gd"

const ScaleState := preload("res://examples/showcase/collection_scale/scale_state.gd")

var model := ScaleState.new()


func _ready() -> void:
	binding_context = model
	event_context = self
	super()


func _on_jump_top() -> void:
	_set_scroll(0)
	model.status = "Top window · only visible records are native controls"
	_refresh_status()


func _on_jump_middle() -> void:
	_set_scroll(180_000)
	model.status = "Middle window near record 5,000 · overlapping row identity retained"
	_refresh_status()


func _on_jump_end() -> void:
	var scroll := get_element_by_id("inventory-scroll") as ScrollContainer
	if scroll != null:
		scroll.set_v_scroll(int(scroll.get_v_scroll_bar().max_value))
	model.status = "End window · native scrollbar covers the full item model"
	_refresh_status()


func _on_insert_record() -> void:
	var next_id := "inserted-%s" % Time.get_ticks_msec()
	model.items.insert(0, {"id": next_id, "name": "Priority cargo", "category": "Inserted", "value": "99,000 cr"})
	model.refresh_count()
	model.status = "Inserted one keyed record · collection patch built no document candidate"
	_refresh_status()


func _on_remove_record() -> void:
	if model.items.item_count() <= 0:
		return
	model.items.remove_at(0)
	model.refresh_count()
	model.status = "Removed the first record · visible keyed anchor preserved"
	_refresh_status()


func _set_scroll(value: int) -> void:
	var scroll := get_element_by_id("inventory-scroll") as ScrollContainer
	if scroll != null:
		scroll.set_v_scroll(value)


func _refresh_status() -> void:
	refresh_binding_paths(PackedStringArray(["status", "count_label"]))
