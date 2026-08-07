@tool
extends VBoxContainer

const LanguageService := preload("res://addons/godot_cascade/tooling/language_service.gd")

var _path: LineEdit
var _code: CodeEdit
var _status: Label
var _rename: LineEdit
var _diagnostics: Array[Dictionary] = []


func _ready() -> void:
	name = "Cascade Source"
	_build_ui()


func open_source(path: String, line: int = 1, column: int = 1) -> void:
	if _code == null:
		await ready
	_path.text = path
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		_status.text = "Source not found: %s" % path
		return
	_code.text = FileAccess.get_file_as_string(absolute)
	_code.set_caret_line(clampi(line - 1, 0, maxi(_code.get_line_count() - 1, 0)))
	_code.set_caret_column(maxi(column - 1, 0))
	_code.grab_focus()
	_update_diagnostics()


func _build_ui() -> void:
	var path_bar := HBoxContainer.new()
	add_child(path_bar)
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "res://path/to/interface.gxml"
	_path.text_submitted.connect(func(_value): open_source(_path.text.strip_edges()))
	path_bar.add_child(_path)
	var open_button := Button.new()
	open_button.text = "Open"
	open_button.pressed.connect(func(): open_source(_path.text.strip_edges()))
	path_bar.add_child(open_button)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_save)
	path_bar.add_child(save_button)

	var actions := HBoxContainer.new()
	add_child(actions)
	var format_button := Button.new()
	format_button.text = "Format"
	format_button.pressed.connect(_format)
	actions.add_child(format_button)
	var definition_button := Button.new()
	definition_button.text = "Go to definition"
	definition_button.pressed.connect(_go_to_definition)
	actions.add_child(definition_button)
	_rename = LineEdit.new()
	_rename.placeholder_text = "New symbol name"
	_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_rename)
	var rename_button := Button.new()
	rename_button.text = "Rename"
	rename_button.pressed.connect(_rename_symbol)
	actions.add_child(rename_button)

	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(700.0, 300.0)
	_code.gutters_draw_line_numbers = true
	_code.code_completion_enabled = true
	_code.code_completion_prefixes = ["<", " ", ":", "-"]
	_code.auto_brace_completion_enabled = true
	_code.symbol_lookup_on_click = true
	_code.symbol_tooltip_on_hover = true
	_code.code_completion_requested.connect(_on_completion_requested)
	_code.symbol_validate.connect(_on_symbol_validate)
	_code.symbol_lookup.connect(_on_symbol_lookup)
	_code.symbol_hovered.connect(_on_symbol_hovered)
	_code.text_changed.connect(_update_diagnostics)
	add_child(_code)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _save() -> void:
	var path := _path.text.strip_edges()
	if not path.begins_with("res://"):
		_status.text = "Save requires a res:// project path."
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "Could not save %s." % path
		return
	file.store_string(_code.text)
	_status.text = "Saved %s." % path


func _format() -> void:
	var caret_offset := _caret_offset()
	_code.text = LanguageService.format(_code.text, _extension())
	_set_caret_offset(mini(caret_offset, _code.text.length()))
	_update_diagnostics()


func _go_to_definition() -> void:
	var location := LanguageService.definition(_code.text, _caret_offset(), _extension(), _path.text.strip_edges())
	if location.is_empty():
		_status.text = "No safe definition found for this symbol."
		return
	_code.set_caret_line(int(location["line"]) - 1)
	_code.set_caret_column(int(location["column"]) - 1)
	_code.center_viewport_to_caret()
	_status.text = "Definition: %s:%s:%s" % [location.get("path", _path.text), location["line"], location["column"]]


func _rename_symbol() -> void:
	var new_name := _rename.text.strip_edges()
	var edits := LanguageService.rename(_code.text, _caret_offset(), new_name, _extension())
	if edits.is_empty():
		_status.text = "No safe rename available for this symbol."
		return
	_code.text = LanguageService.apply_edits(_code.text, edits)
	_status.text = "Renamed %s occurrence(s); review and save." % edits.size()
	_update_diagnostics()


func _on_completion_requested() -> void:
	for option in LanguageService.completions(_code.text, _caret_offset(), _extension()):
		_code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, option["label"], option["insert"])
	_code.update_code_completion_options(true)


func _on_symbol_validate(symbol: String) -> void:
	var offset := _line_column_offset(_code.get_caret_line(), _code.get_caret_column())
	var result := LanguageService.hover(_code.text, offset, _extension())
	_code.set_symbol_lookup_word_as_valid(not result.is_empty() and result.get("symbol", "") == symbol)


func _on_symbol_lookup(symbol: String, line: int, column: int) -> void:
	var location := LanguageService.definition(_code.text, _line_column_offset(line, column), _extension(), _path.text.strip_edges())
	if not location.is_empty():
		_code.set_caret_line(int(location["line"]) - 1)
		_code.set_caret_column(int(location["column"]) - 1)
		_status.text = "%s → %s:%s" % [symbol, location["line"], location["column"]]


func _on_symbol_hovered(symbol: String, line: int, column: int) -> void:
	var result := LanguageService.hover(_code.text, _line_column_offset(line, column), _extension())
	_code.tooltip_text = str(result.get("documentation", symbol))


func _update_diagnostics() -> void:
	if _code == null or _status == null:
		return
	for line in _code.get_line_count():
		_code.set_line_background_color(line, Color.TRANSPARENT)
	_diagnostics = LanguageService.diagnostics(_code.text, _extension())
	var errors := 0
	var warnings := 0
	var messages := PackedStringArray()
	for diagnostic in _diagnostics:
		var severity := str(diagnostic.get("severity", "error"))
		if severity == "warning": warnings += 1
		else: errors += 1
		var line := clampi(int(diagnostic.get("line", 1)) - 1, 0, maxi(_code.get_line_count() - 1, 0))
		_code.set_line_background_color(line, Color(0.45, 0.08, 0.08, 0.28) if severity == "error" else Color(0.45, 0.3, 0.05, 0.2))
		messages.append("%s:%s %s" % [line + 1, diagnostic.get("column", 1), diagnostic.get("message", "")])
	_status.text = "%s error(s), %s warning(s)" % [errors, warnings]
	_status.tooltip_text = "\n".join(messages)


func _extension() -> String:
	return _path.text.get_extension().to_lower()


func _caret_offset() -> int:
	return _line_column_offset(_code.get_caret_line(), _code.get_caret_column())


func _line_column_offset(line: int, column: int) -> int:
	var offset := 0
	for index in mini(line, _code.get_line_count()):
		offset += _code.get_line(index).length() + 1
	return offset + column


func _set_caret_offset(offset: int) -> void:
	var remaining := offset
	for line in _code.get_line_count():
		var length := _code.get_line(line).length()
		if remaining <= length:
			_code.set_caret_line(line)
			_code.set_caret_column(remaining)
			return
		remaining -= length + 1
