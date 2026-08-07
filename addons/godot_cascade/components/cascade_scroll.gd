@tool
extends ScrollContainer

## Native scroll viewport for content whose intrinsic size may exceed layout space.

const ThemeAdapter := preload("res://addons/godot_cascade/style/theme_adapter.gd")

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(value):
		var next := value if value != null else CascadeStyle.new()
		if cascade_style == next:
			return
		_disconnect_style()
		cascade_style = next
		_connect_style()
		_apply_style()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	child_entered_tree.connect(_configure_child)
	for child in get_children():
		_configure_child(child)
	_connect_style()
	_apply_style()


func _get_minimum_size() -> Vector2:
	var scrollbar_width := get_v_scroll_bar().get_combined_minimum_size().x
	return cascade_style.constrain_minimum(Vector2(scrollbar_width, 0.0))


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _disconnect_style() -> void:
	if cascade_style != null and cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.disconnect(_on_style_invalidated)


func _on_style_invalidated(_flags: int) -> void:
	_apply_style()


func _apply_style() -> void:
	if not is_inside_tree():
		return
	ThemeAdapter.apply_style_box(self, cascade_style)
	update_minimum_size()
	queue_sort()


func _configure_child(child: Node) -> void:
	if child is Control:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
