@tool
extends Container

## Table cell with owned box/text rendering and optional authored child content.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const AccessibilitySemantics := preload("res://addons/godot_cascade/runtime/accessibility_semantics.gd")

@export_group("Content")
@export_multiline var text := "":
	set(value):
		text = value
		_sync_label()
		_invalidate_measure()
@export var header := false:
	set(value):
		header = value
		set_meta("cascade_table_role", "columnheader" if value else "cell")
		queue_accessibility_update()
@export var font: Font:
	set(value):
		font = value
		_sync_label()
		_invalidate_measure()
@export_range(1, 256, 1, "or_greater") var font_size := 16:
	set(value):
		font_size = maxi(value, 1)
		_sync_label()
		_invalidate_measure()
@export var text_color := Color("d0d5dd"):
	set(value):
		text_color = value
		_sync_label()
@export var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT:
	set(value):
		horizontal_alignment = value
		_sync_label()
@export var vertical_alignment: VerticalAlignment = VERTICAL_ALIGNMENT_CENTER:
	set(value):
		vertical_alignment = value
		_sync_label()

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		var next := value if value != null else CascadeStyle.new()
		if cascade_style == next:
			return
		_disconnect_style()
		cascade_style = next
		_connect_style()
		_invalidate_measure()

var _label: Label


func _ready() -> void:
	set_meta("cascade_table_role", "columnheader" if header else "cell")
	if accessibility_description.is_empty():
		accessibility_description = "Column header" if header else "Table cell"
	_connect_style()
	_apply_overflow()
	_ensure_label()
	resized.connect(_arrange_content)
	child_entered_tree.connect(_on_children_changed)
	child_exiting_tree.connect(_on_children_changed)
	_sync_label()
	_arrange_content()


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_arrange_content()
	elif what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilitySemantics.set_table_cell(self, header)


func _get_minimum_size() -> Vector2:
	var content_minimum := Vector2.ZERO
	var authored := _authored_children()
	if authored.is_empty():
		if _label != null:
			content_minimum = _label.get_combined_minimum_size()
		elif not text.is_empty():
			var resolved_font := font if font != null else get_theme_default_font()
			if resolved_font != null:
				content_minimum = resolved_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	else:
		for child in authored:
			content_minimum = content_minimum.max(child.get_combined_minimum_size())
	return cascade_style.constrain_minimum(BoxPainter.outer_minimum_size(content_minimum, cascade_style.padding(), cascade_style.border_width))


func _draw() -> void:
	BoxPainter.draw_box(
		self,
		Rect2(Vector2.ZERO, size),
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		_resolved_corner_radii(),
		cascade_style.background_gradient
	)


func _resolved_corner_radii() -> Variant:
	if cascade_style.border_radius > 0.0 or not header:
		return cascade_style.border_radius
	var row := get_parent()
	if row == null:
		return 0.0
	var header_cells: Array[Control] = []
	for sibling in row.get_children():
		if sibling is Control and str(sibling.get_meta("cascade_table_role", "")) == "columnheader":
			header_cells.append(sibling)
	if header_cells.is_empty():
		return 0.0
	var ancestor := row.get_parent()
	while ancestor != null and str(ancestor.get_meta("cascade_table_role", "")) != "table":
		ancestor = ancestor.get_parent()
	if ancestor == null:
		return 0.0
	var table_style: CascadeStyle = ancestor.get("cascade_style")
	var radius := maxf(table_style.border_radius - table_style.border_width, 0.0)
	return Vector4(
		radius if header_cells[0] == self else 0.0,
		radius if header_cells[-1] == self else 0.0,
		0.0,
		0.0
	)


func _ensure_label() -> void:
	if _label != null:
		return
	_label = Label.new()
	_label.name = "_Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label, false, Node.INTERNAL_MODE_BACK)


func _sync_label() -> void:
	if _label == null:
		return
	_label.text = text
	_label.horizontal_alignment = horizontal_alignment
	_label.vertical_alignment = vertical_alignment
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	if font != null:
		_label.add_theme_font_override("font", font)
	else:
		_label.remove_theme_font_override("font")
	if not get_meta("cascade_explicit_accessible_label", false):
		accessibility_name = text
	_arrange_content()


func _arrange_content() -> void:
	var content := BoxPainter.content_rect(Rect2(Vector2.ZERO, size), cascade_style.padding(), cascade_style.border_width)
	var authored := _authored_children()
	if _label != null:
		_label.visible = authored.is_empty()
		_label.position = content.position
		_label.size = content.size
	for child in authored:
		fit_child_in_rect(child, content)


func _authored_children() -> Array[Control]:
	var result: Array[Control] = []
	for child in get_children():
		if child is Control and child != _label and child.visible and not child.top_level:
			result.append(child)
	return result


func _invalidate_measure() -> void:
	queue_redraw()
	if not is_inside_tree():
		return
	update_minimum_size()
	queue_sort()
	_request_table_layout()


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
	_invalidate_measure()


func _on_children_changed(_child: Node) -> void:
	_invalidate_measure.call_deferred()


func _request_table_layout() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("request_table_layout"):
			ancestor.call("request_table_layout")
			return
		ancestor = ancestor.get_parent()


func _apply_overflow() -> void:
	clip_contents = cascade_style.overflow == CascadeStyle.Overflow.CLIP
