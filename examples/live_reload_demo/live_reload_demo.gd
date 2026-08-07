extends Control

## Deterministic public demonstration of source reload and native-node reconciliation.

const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const MARKUP_PATH := "user://godot_cascade_live_reload_demo.gxml"
const STYLESHEET_PATH := "user://godot_cascade_live_reload_demo.gcss"
const MARKUP_INITIAL := """<Page class="preview">
  <Panel id="card" class="card">
    <Label class="eyebrow">LIVE GXML + GCSS</Label>
    <Label id="title" class="title">Native controls</Label>
    <Label class="body">Edit source. Keep focus, signals, and identity.</Label>
    <Button id="inspect">Inspect node</Button>
  </Panel>
</Page>"""
const MARKUP_UPDATED := """<Page class="preview">
  <Panel id="card" class="card">
    <Label class="eyebrow">LIVE GXML + GCSS</Label>
    <Label id="title" class="title">Still native</Label>
    <Label class="body">The same Control instances received the update.</Label>
    <Button id="inspect">Inspect node</Button>
  </Panel>
</Page>"""
const STYLE_INITIAL := """.preview {
  padding: 30px;
  background: #0e1014;
}
.card {
  padding: 24px;
  gap: 14px;
  background: #182338;
  border: 1px solid #315a89;
  border-radius: 12px;
}
.eyebrow { color: #65d6a7; font-size: 12px; }
.title { color: #dbe8ff; font-size: 27px; }
.body { color: #aebbd2; font-size: 14px; }
#inspect {
  min-height: 42px;
  background: #246bce;
  color: #ffffff;
  border-radius: 8px;
}
"""
const STYLE_UPDATED := """.preview {
  padding: 30px;
  background: #0e1014;
}
.card {
  padding: 24px;
  gap: 14px;
  background: #15372f;
  border: 2px solid #65d6a7;
  border-radius: 12px;
}
.eyebrow { color: #7dbfff; font-size: 12px; }
.title { color: #effff9; font-size: 27px; }
.body { color: #b9d8cc; font-size: 14px; }
#inspect {
  min-height: 42px;
  background: #246bce;
  color: #ffffff;
  border-radius: 8px;
}
"""

var _document: Control
var _source_view: RichTextLabel
var _status: Label
var _identity: Label
var _frame := 0
var _card_instance_id := 0


func _ready() -> void:
	_build_shell()
	_write_text(MARKUP_PATH, MARKUP_INITIAL)
	_write_text(STYLESHEET_PATH, STYLE_INITIAL)
	_show_source("initial.gcss", STYLE_INITIAL, 6)
	_start_document.call_deferred()


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_apply_style_edit()
	elif _frame == 43:
		_apply_markup_edit()


func _start_document() -> void:
	if not _document.reload_document():
		_status.text = "Build failed — inspect diagnostics"
		return
	var card := _find_by_id(_document.generated_root(), "card")
	_card_instance_id = card.get_instance_id() if card != null else 0
	_update_identity("Native tree built")


func _apply_style_edit() -> void:
	_show_source("edited.gcss", STYLE_UPDATED, 6)
	_write_text(STYLESHEET_PATH, STYLE_UPDATED)
	var changed: bool = bool(_document.poll_sources())
	_update_identity("GCSS changed → watcher rebuilt → reconciler reused" if changed else "No source change detected")


func _apply_markup_edit() -> void:
	_show_source("edited.gxml", MARKUP_UPDATED, 3)
	_write_text(MARKUP_PATH, MARKUP_UPDATED)
	var changed: bool = bool(_document.poll_sources())
	_update_identity("GXML changed → text updated → identity preserved" if changed else "No source change detected")


func _update_identity(message: String) -> void:
	var card := _find_by_id(_document.generated_root(), "card")
	var current_id := card.get_instance_id() if card != null else 0
	var preserved := _card_instance_id != 0 and current_id == _card_instance_id
	_status.text = message
	_identity.text = "engine instance unchanged  •  SAME NODE" if preserved else "engine instance replaced  •  NEW NODE"
	_identity.modulate = Color("65d6a7") if preserved else Color("f6b86b")


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("0b1220")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 13)
	margin.add_child(page)

	var heading := Label.new()
	heading.text = "GodotCascade live reload"
	heading.add_theme_font_size_override("font_size", 27)
	heading.add_theme_color_override("font_color", Color("e8f0ff"))
	page.add_child(heading)

	var lede := Label.new()
	lede.text = "Focused GXML + GCSS in. Real Godot Controls out. Compatible nodes stay alive across edits."
	lede.add_theme_font_size_override("font_size", 14)
	lede.add_theme_color_override("font_color", Color("95a6c3"))
	page.add_child(lede)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	page.add_child(columns)

	var source_panel := _panel("SOURCE EDIT", 300)
	columns.add_child(source_panel)
	_source_view = RichTextLabel.new()
	_source_view.bbcode_enabled = true
	_source_view.fit_content = false
	_source_view.scroll_active = false
	_source_view.add_theme_font_size_override("normal_font_size", 12)
	_source_view.add_theme_color_override("default_color", Color("c7d2e6"))
	_panel_content(source_panel).add_child(_source_view)
	_source_view.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var preview_panel := _panel("NATIVE GODOT RENDER", 370)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(preview_panel)
	_document = CascadeDocument.new()
	_document.load_on_ready = false
	_document.watch_sources = false
	_document.log_diagnostics_to_console = false
	_document.markup_path = MARKUP_PATH
	_document.stylesheet_path = STYLESHEET_PATH
	_document.custom_minimum_size = Vector2(0, 320)
	_document.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel_content(preview_panel).add_child(_document)

	var tree_panel := _panel("NATIVE CONTROL TREE", 218)
	columns.add_child(tree_panel)
	var tree := RichTextLabel.new()
	tree.bbcode_enabled = true
	tree.fit_content = false
	tree.scroll_active = false
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.add_theme_font_size_override("normal_font_size", 12)
	tree.text = "[color=#7dbfff]CascadeBox[/color]  Page\n  └─ [color=#65d6a7]CascadePanel[/color]  #card\n      ├─ CascadeLabel\n      ├─ CascadeLabel  #title\n      ├─ CascadeLabel\n      └─ CascadeButton  #inspect\n\n[color=#95a6c3]No WebView. No DOM.\nInspectable native nodes.[/color]"
	_panel_content(tree_panel).add_child(tree)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	page.add_child(footer)
	_status = Label.new()
	_status.text = "Loading native document…"
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color("dbe8ff"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	_identity = Label.new()
	_identity.text = "engine instance: pending"
	_identity.add_theme_font_size_override("font_size", 12)
	footer.add_child(_identity)


func _panel(title: String, minimum_width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minimum_width
	panel.add_theme_stylebox_override("panel", _panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 13)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 13)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("7dbfff"))
	content.add_child(label)
	return panel


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a2a")
	style.border_color = Color("263653")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _panel_content(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0).get_child(0) as VBoxContainer


func _show_source(filename: String, source: String, highlighted_line: int) -> void:
	var lines := source.split("\n")
	var output := "[color=#65d6a7]%s[/color]\n\n" % filename
	for index in lines.size():
		var color := "#ffffff" if index + 1 == highlighted_line else "#9eacc7"
		var marker := "▶" if index + 1 == highlighted_line else " "
		output += "[color=%s]%s %2d  %s[/color]\n" % [color, marker, index + 1, _escape_bbcode(lines[index])]
	_source_view.text = output


func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]")


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(contents)


func _find_by_id(node: Node, id_value: String) -> Control:
	if node is Control and node.get_meta("cascade_id", "") == id_value:
		return node
	for child in node.get_children():
		var found := _find_by_id(child, id_value)
		if found != null:
			return found
	return null
