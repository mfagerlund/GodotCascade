@tool
extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	return object is Control and object.has_meta("cascade_element_type")


func _parse_begin(object: Object) -> void:
	var control := object as Control
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = "GXML <%s>  id=%s  classes=%s\nkey: %s\nsource: %s:%s:%s\nresolved rect: %s" % [
		control.get_meta("cascade_element_type", control.get_class()),
		control.get_meta("cascade_id", "—"),
		", ".join(control.get_meta("cascade_classes", PackedStringArray())),
		control.get_meta("cascade_key", ""),
		control.get_meta("cascade_source_path", ""),
		control.get_meta("cascade_source_line", 1),
		control.get_meta("cascade_source_column", 1),
		Rect2(control.position, control.size),
	]
	add_custom_control(summary)
