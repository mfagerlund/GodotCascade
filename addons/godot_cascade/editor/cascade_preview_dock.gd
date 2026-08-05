@tool
extends VBoxContainer

signal source_requested(path: String, line: int, column: int)

const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const DebugSnapshot := preload("res://addons/godot_cascade/editor/debug_snapshot.gd")

var _markup_path: LineEdit
var _stylesheet_path: LineEdit
var _status: Label
var _tree: Tree
var _viewport: SubViewport
var _document: Control


func _ready() -> void:
	name = "Cascade Preview"
	_build_ui()
	_load_preview()


func set_sources(markup_path: String, stylesheet_path: String) -> void:
	if _markup_path == null:
		await ready
	_markup_path.text = markup_path
	_stylesheet_path.text = stylesheet_path
	_load_preview()


func _build_ui() -> void:
	var heading := Label.new()
	heading.text = "GodotCascade live preview"
	heading.add_theme_font_size_override(&"font_size", 16)
	add_child(heading)

	_markup_path = LineEdit.new()
	_markup_path.placeholder_text = "res://path/to/interface.gxml"
	_markup_path.text = "res://examples/showcase/layout_foundation/interface.gxml"
	add_child(_markup_path)
	_stylesheet_path = LineEdit.new()
	_stylesheet_path.placeholder_text = "res://path/to/styles.gcss"
	_stylesheet_path.text = "res://examples/showcase/layout_foundation/styles.gcss"
	add_child(_stylesheet_path)

	var refresh := Button.new()
	refresh.text = "Reload preview"
	refresh.pressed.connect(_load_preview)
	add_child(refresh)

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(420.0, 236.0)
	viewport_container.stretch = true
	add_child(viewport_container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(960, 540)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(_viewport)
	_document = CascadeDocument.new()
	_document.load_on_ready = false
	_document.watch_sources = true
	_document.log_diagnostics_to_console = false
	_document.size = Vector2(960.0, 540.0)
	_document.diagnostics_changed.connect(_on_diagnostics_changed)
	_viewport.add_child(_document)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_tree = Tree.new()
	_tree.custom_minimum_size.y = 220.0
	_tree.columns = 4
	_tree.set_column_title(0, "Element")
	_tree.set_column_title(1, "ID / classes")
	_tree.set_column_title(2, "Rect")
	_tree.set_column_title(3, "Resolved style")
	_tree.column_titles_visible = true
	_tree.item_activated.connect(_on_tree_item_activated)
	add_child(_tree)


func _load_preview() -> void:
	if _document == null:
		return
	_document.markup_path = _markup_path.text.strip_edges()
	_document.stylesheet_path = _stylesheet_path.text.strip_edges()
	_document.reload_document()
	_update_debug_tree()


func _on_diagnostics_changed(diagnostics: Array[Dictionary]) -> void:
	var errors := 0
	var warnings := 0
	for diagnostic in diagnostics:
		if diagnostic.get("severity", "error") == "warning":
			warnings += 1
		else:
			errors += 1
	_status.text = "Preview: %s error(s), %s warning(s)" % [errors, warnings]
	if not diagnostics.is_empty():
		_status.tooltip_text = "\n".join(diagnostics.map(func(value): return str(value.get("message", ""))))
	_update_debug_tree()


func _update_debug_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var tree_root := _tree.create_item()
	var generated: Control = _document.generated_root()
	if generated == null:
		return
	var parents: Array[TreeItem] = [tree_root]
	for entry in DebugSnapshot.capture(generated):
		var depth := int(entry["depth"])
		while parents.size() > depth + 1:
			parents.pop_back()
		var item := _tree.create_item(parents.back())
		item.set_text(0, "<%s>" % entry["element"])
		item.set_text(1, "%s  .%s" % [entry["id"], ".".join(entry["classes"])])
		item.set_text(2, str(entry["rect"]))
		var style: Dictionary = entry["style"]
		item.set_text(3, "bg %s · pad %s" % [style.get("background", "—"), style.get("padding", "—")])
		item.set_metadata(0, {"path": entry["source_path"], "line": entry["source_line"], "column": entry["source_column"]})
		if parents.size() == depth + 1:
			parents.append(item)
		else:
			parents[depth + 1] = item


func _on_tree_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var location: Dictionary = item.get_metadata(0)
	var path := str(location.get("path", ""))
	var line := int(location.get("line", 1))
	var column := int(location.get("column", 1))
	_status.text = "Source: %s:%s:%s" % [path, line, column]
	source_requested.emit(path, line, column)
