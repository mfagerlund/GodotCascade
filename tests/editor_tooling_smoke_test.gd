extends SceneTree

const SourceEditor := preload("res://addons/godot_cascade/editor/cascade_source_editor.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var editor: Control = SourceEditor.new()
	root.add_child(editor)
	await process_frame
	editor.open_source("res://examples/showcase/layout_foundation/interface.gxml", 2, 1)
	await process_frame
	var code_edit := _find_code_edit(editor)
	_expect("source editor creates CodeEdit", code_edit != null)
	if code_edit != null:
		_expect("source editor opens requested file", "<Page" in code_edit.text)
		code_edit.text = "<"
		code_edit.set_caret_line(0)
		code_edit.set_caret_column(1)
		editor.call("_on_completion_requested")
		_expect("CodeEdit receives completion candidates", not code_edit.get_code_completion_options().is_empty())
		code_edit.text = "<Page><Label>Text</Label></Page>"
		editor.call("_format")
		_expect("source editor formatting retains document", "<Page" in code_edit.text and "<Label>" in code_edit.text)
	_expect("source editor publishes diagnostic status", _find_labels(editor).any(func(label): return "error(s)" in label.text))
	editor.queue_free()
	await process_frame
	if _failures.is_empty():
		print("GodotCascade editor tooling smoke tests passed.")
		quit(0)
	else:
		for failure in _failures: push_error(failure)
		quit(1)


func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit: return node
	for child in node.get_children():
		var found := _find_code_edit(child)
		if found != null: return found
	return null


func _find_labels(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	if node is Label: result.append(node)
	for child in node.get_children(): result.append_array(_find_labels(child))
	return result


func _expect(label: String, condition: bool) -> void:
	if not condition: _failures.append(label)
