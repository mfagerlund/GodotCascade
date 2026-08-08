@tool
extends Container

## Non-visual table structure node used for headers, bodies, rows, and repeated row groups.
## CascadeTable owns descendant placement so every row shares one column calculation.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")
const AccessibilitySemantics := preload("res://addons/godot_cascade/runtime/accessibility_semantics.gd")

@export_enum("header", "body", "row", "group") var semantic_role := "body":
	set(value):
		semantic_role = value
		set_meta("cascade_table_role", value)
		_request_table_layout()
		queue_accessibility_update()
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		var next := value if value != null else CascadeStyle.new()
		if cascade_style == next:
			return
		_disconnect_style()
		cascade_style = next
		_connect_style()
		_request_table_layout()
		queue_redraw()


func _ready() -> void:
	set_meta("cascade_table_role", semantic_role)
	_connect_style()
	child_entered_tree.connect(_on_children_changed)
	child_exiting_tree.connect(_on_children_changed)
	queue_redraw()


func _draw() -> void:
	BoxPainter.draw_box(
		self,
		Rect2(Vector2.ZERO, size),
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius,
		cascade_style.background_gradient
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilitySemantics.set_table_part(self, semantic_role == "row")
	elif what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_request_table_layout()


func _get_minimum_size() -> Vector2:
	var result := Vector2.ZERO
	for child in get_children():
		if child is Control and child.visible and not child.top_level:
			result = result.max(child.get_combined_minimum_size())
	return result


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _disconnect_style() -> void:
	if cascade_style != null and cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.disconnect(_on_style_invalidated)


func _on_style_invalidated(_flags: int) -> void:
	queue_redraw()
	_request_table_layout()


func _on_children_changed(_child: Node) -> void:
	queue_accessibility_update()
	_request_table_layout.call_deferred()


func _request_table_layout() -> void:
	if not is_inside_tree():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("request_table_layout"):
			if ancestor.has_method("request_accessibility_structure_update"):
				ancestor.call("request_accessibility_structure_update")
			ancestor.call("request_table_layout")
			return
		ancestor = ancestor.get_parent()
