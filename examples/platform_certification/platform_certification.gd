extends Control

const CascadeDocumentScript := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const CertificationState := preload("res://examples/platform_certification/certification_state.gd")

var _document: Control
var _state := CertificationState.new()
var _native_profile: LineEdit
var _native_notes: TextEdit
var _native_profile_echo: Label
var _native_notes_echo: Label
var _telemetry: Label


func _ready() -> void:
	_build_fixture()
	set_process(true)


func cascade_document() -> Control:
	return _document


func native_profile() -> LineEdit:
	return _native_profile


func native_notes() -> TextEdit:
	return _native_notes


func _build_fixture() -> void:
	var background := ColorRect.new()
	background.color = Color("07101d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var vertical := VBoxContainer.new()
	vertical.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vertical.offset_left = 8
	vertical.offset_top = 8
	vertical.offset_right = -8
	vertical.offset_bottom = -8
	vertical.add_theme_constant_override("separation", 8)
	add_child(vertical)

	var split := HSplitContainer.new()
	split.name = "CertificationSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	vertical.add_child(split)

	_document = CascadeDocumentScript.new()
	_document.name = "CascadeFixture"
	_document.load_on_ready = false
	_document.watch_sources = false
	_document.log_diagnostics_to_console = true
	_document.binding_context = _state
	_document.event_context = self
	_document.markup_path = "res://examples/platform_certification/certification.gxml"
	_document.stylesheet_path = "res://examples/platform_certification/certification.gcss"
	_document.custom_minimum_size = Vector2(560, 640)
	_document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_document)
	assert(_document.reload_document(), "Platform certification Cascade fixture must load")

	var native_panel := PanelContainer.new()
	native_panel.name = "NativeBaseline"
	native_panel.custom_minimum_size = Vector2(500, 640)
	native_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	native_panel.add_theme_stylebox_override("panel", _panel_style())
	split.add_child(native_panel)
	_build_native_baseline(native_panel)

	_telemetry = Label.new()
	_telemetry.name = "Telemetry"
	_telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_telemetry.custom_minimum_size.y = 28
	_telemetry.add_theme_color_override("font_color", Color("a9bad4"))
	_telemetry.add_theme_font_size_override("font_size", 13)
	vertical.add_child(_telemetry)


func _build_native_baseline(panel: PanelContainer) -> void:
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 4)
	panel.add_child(fields)
	_add_heading(fields, "PLAIN GODOT BASELINE", 11, Color("65d6a7"))
	_add_heading(fields, "LineEdit / TextEdit", 24, Color("f5f8ff"))
	_add_body(fields, "These controls do not use GodotCascade. Repeat every platform-service check here.")

	_native_profile = _line_edit("Native editable profile", _state.profile)
	fields.add_child(_label("Editable profile"))
	fields.add_child(_native_profile)
	_native_profile_echo = _echo_label(_state.profile)
	fields.add_child(_label("Bound echo"))
	fields.add_child(_native_profile_echo)
	_native_profile.text_changed.connect(func(value: String): _native_profile_echo.text = value)

	fields.add_child(_label("Secret field"))
	var secret := _line_edit("Native secret value", _state.secret)
	secret.secret = true
	fields.add_child(secret)

	fields.add_child(_label("Read-only sample"))
	var read_only := _line_edit("Native read-only sample", "Read-only native selection sample")
	read_only.editable = false
	fields.add_child(read_only)

	fields.add_child(_label("Multiline and bidi"))
	_native_notes = TextEdit.new()
	_native_notes.name = "NativeNotes"
	_native_notes.text = _state.notes
	_native_notes.accessibility_name = "Native multiline notes"
	_native_notes.custom_minimum_size.y = 132
	_native_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_native_notes.add_theme_font_size_override("font_size", 15)
	fields.add_child(_native_notes)
	_native_notes_echo = _echo_label(_state.notes)
	_native_notes_echo.custom_minimum_size.y = 72
	fields.add_child(_label("Multiline bound echo"))
	fields.add_child(_native_notes_echo)
	_native_notes.text_changed.connect(func(): _native_notes_echo.text = _native_notes.text)


func _process(_delta: float) -> void:
	if _telemetry == null or _document == null:
		return
	var cascade_profile: LineEdit = _document.get_element_by_id("profile")
	var cascade_notes: TextEdit = _document.get_element_by_id("notes")
	if cascade_profile == null or cascade_notes == null:
		return
	_telemetry.text = "Cascade profile caret %d selection %s · notes caret %d:%d selection %s    |    Native profile caret %d selection %s · notes caret %d:%d selection %s" % [
		cascade_profile.caret_column,
		_selection_text(cascade_profile),
		cascade_notes.get_caret_line(),
		cascade_notes.get_caret_column(),
		_selection_text(cascade_notes),
		_native_profile.caret_column,
		_selection_text(_native_profile),
		_native_notes.get_caret_line(),
		_native_notes.get_caret_column(),
		_selection_text(_native_notes),
	]


func _on_reload() -> void:
	_document.reload_document()


func _selection_text(editor: Control) -> String:
	if not editor.has_selection():
		return "none"
	if editor is LineEdit:
		return "%d–%d" % [editor.get_selection_from_column(), editor.get_selection_to_column()]
	return "%d:%d–%d:%d" % [
		editor.get_selection_from_line(), editor.get_selection_from_column(),
		editor.get_selection_to_line(), editor.get_selection_to_column(),
	]


func _line_edit(accessible_name: String, value: String) -> LineEdit:
	var editor := LineEdit.new()
	editor.text = value
	editor.accessibility_name = accessible_name
	editor.custom_minimum_size.y = 38
	editor.add_theme_font_size_override("font_size", 15)
	return editor


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Color("9fb0cc"))
	return label


func _echo_label(value: String) -> Label:
	var label := _label(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("dbe7ff"))
	return label


func _add_heading(parent: Control, value: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _add_body(parent: Control, value: String) -> void:
	var label := _label(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b1220")
	style.border_color = Color("304160")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style
