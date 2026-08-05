@tool
extends Container

## Native row/column layout implementing GodotCascade's first box-model slice.

enum FlowDirection {
	ROW,
	COLUMN,
}

enum MainAlignment {
	START,
	CENTER,
	END,
	SPACE_BETWEEN,
	SPACE_AROUND,
	SPACE_EVENLY,
}

enum CrossAlignment {
	START,
	CENTER,
	END,
	STRETCH,
}

const META_PREFIX := "cascade_"

@export_group("Layout")
@export var direction: FlowDirection = FlowDirection.COLUMN:
	set(value):
		direction = value
		_invalidate_layout()
@export var wrap: bool = false:
	set(value):
		wrap = value
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var gap: float = 0.0:
	set(value):
		gap = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var line_gap: float = 0.0:
	set(value):
		line_gap = maxf(value, 0.0)
		_invalidate_layout()
@export var justify_content: MainAlignment = MainAlignment.START:
	set(value):
		justify_content = value
		_invalidate_layout()
@export var align_items: CrossAlignment = CrossAlignment.STRETCH:
	set(value):
		align_items = value
		_invalidate_layout()

@export_group("Padding")
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_left: float = 0.0:
	set(value):
		padding_left = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_top: float = 0.0:
	set(value):
		padding_top = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_right: float = 0.0:
	set(value):
		padding_right = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 4096.0, 0.5, "or_greater") var padding_bottom: float = 0.0:
	set(value):
		padding_bottom = maxf(value, 0.0)
		_invalidate_layout()

@export_group("Margin")
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_left: float = 0.0:
	set(value):
		margin_left = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_top: float = 0.0:
	set(value):
		margin_top = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_right: float = 0.0:
	set(value):
		margin_right = maxf(value, 0.0)
		_notify_parent_layout_changed()
@export_range(0.0, 4096.0, 0.5, "or_greater") var margin_bottom: float = 0.0:
	set(value):
		margin_bottom = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Size")
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_width: float = 0.0:
	set(value):
		preferred_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var preferred_height: float = 0.0:
	set(value):
		preferred_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_width: float = 0.0:
	set(value):
		min_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var min_height: float = 0.0:
	set(value):
		min_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_width: float = 0.0:
	set(value):
		max_width = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 16384.0, 0.5, "or_greater") var max_height: float = 0.0:
	set(value):
		max_height = maxf(value, 0.0)
		_invalidate_layout()
@export_range(0.0, 100.0, 0.05, "or_greater") var flex_grow: float = 0.0:
	set(value):
		flex_grow = maxf(value, 0.0)
		_notify_parent_layout_changed()

@export_group("Appearance")
@export var background_color: Color = Color.TRANSPARENT:
	set(value):
		background_color = value
		queue_redraw()
@export var border_color: Color = Color.TRANSPARENT:
	set(value):
		border_color = value
		queue_redraw()
@export_range(0.0, 128.0, 1.0, "or_greater") var border_width: float = 0.0:
	set(value):
		border_width = maxf(value, 0.0)
		queue_redraw()
@export_range(0.0, 512.0, 1.0, "or_greater") var border_radius: float = 0.0:
	set(value):
		border_radius = maxf(value, 0.0)
		queue_redraw()


func _ready() -> void:
	resized.connect(_on_resized)
	queue_sort()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_arrange_children()
		NOTIFICATION_DRAW:
			_draw_box()


func _get_minimum_size() -> Vector2:
	var children := _layout_children()
	var content_minimum := Vector2.ZERO

	if not children.is_empty():
		if wrap:
			# Cross-axis size depends on the eventual main-axis constraint.
			# The largest item is the stable intrinsic minimum before arrangement.
			for child in children:
				var footprint := _child_footprint(child)
				content_minimum.x = maxf(content_minimum.x, footprint.x)
				content_minimum.y = maxf(content_minimum.y, footprint.y)
		else:
			for child in children:
				var footprint := _child_footprint(child)
				if direction == FlowDirection.ROW:
					content_minimum.x += footprint.x
					content_minimum.y = maxf(content_minimum.y, footprint.y)
				else:
					content_minimum.x = maxf(content_minimum.x, footprint.x)
					content_minimum.y += footprint.y

			var total_gap := gap * maxf(children.size() - 1, 0)
			if direction == FlowDirection.ROW:
				content_minimum.x += total_gap
			else:
				content_minimum.y += total_gap

	content_minimum += Vector2(padding_left + padding_right, padding_top + padding_bottom)
	content_minimum.x = maxf(maxf(content_minimum.x, min_width), preferred_width)
	content_minimum.y = maxf(maxf(content_minimum.y, min_height), preferred_height)
	return content_minimum


func _arrange_children() -> void:
	var children := _layout_children()
	if children.is_empty():
		return

	var content_rect := Rect2(
		Vector2(padding_left, padding_top),
		Vector2(
			maxf(size.x - padding_left - padding_right, 0.0),
			maxf(size.y - padding_top - padding_bottom, 0.0)
		)
	)
	var lines := _build_lines(children, _main_of(content_rect.size))
	if not wrap and lines.size() == 1:
		lines[0].cross_size = maxf(lines[0].cross_size, _cross_of(content_rect.size))

	var cross_cursor := _cross_of(content_rect.position)
	for line in lines:
		_arrange_line(line, content_rect, cross_cursor)
		cross_cursor += line.cross_size + line_gap


func _build_lines(children: Array[Control], available_main: float) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var current := _new_line()

	for child in children:
		var footprint := _child_footprint(child)
		var next_main: float = current.main_size
		if not current.items.is_empty():
			next_main += gap
		next_main += _main_of(footprint)

		if wrap and not current.items.is_empty() and next_main > available_main:
			lines.append(current)
			current = _new_line()

		if not current.items.is_empty():
			current.main_size += gap
		current.items.append(child)
		current.main_size += _main_of(footprint)
		current.cross_size = maxf(current.cross_size, _cross_of(footprint))
		current.grow_total += _child_value(child, "flex_grow", 0.0)

	if not current.items.is_empty():
		lines.append(current)
	return lines


func _arrange_line(line: Dictionary, content_rect: Rect2, cross_cursor: float) -> void:
	var available_main := _main_of(content_rect.size)
	var free_main := maxf(available_main - line.main_size, 0.0)
	var distributable := 0.0 if line.grow_total > 0.0 else free_main
	var distribution := _main_distribution(distributable, line.items.size())
	var main_cursor: float = _main_of(content_rect.position) + float(distribution.offset)

	for child in line.items:
		var margins := _child_margins(child)
		var before_main := margins.x if direction == FlowDirection.ROW else margins.y
		var after_main := margins.z if direction == FlowDirection.ROW else margins.w
		var before_cross := margins.y if direction == FlowDirection.ROW else margins.x
		var after_cross := margins.w if direction == FlowDirection.ROW else margins.z
		var child_minimum := _child_constrained_size(child)
		var child_main := _main_of(child_minimum)
		var child_cross := _cross_of(child_minimum)

		if line.grow_total > 0.0:
			var share: float = free_main * _child_value(child, "flex_grow", 0.0) / line.grow_total
			child_main += share

		var cross_available: float = maxf(line.cross_size - before_cross - after_cross, 0.0)
		var cross_offset := before_cross
		match align_items:
			CrossAlignment.CENTER:
				cross_offset += maxf(cross_available - child_cross, 0.0) * 0.5
			CrossAlignment.END:
				cross_offset += maxf(cross_available - child_cross, 0.0)
			CrossAlignment.STRETCH:
				child_cross = maxf(child_cross, cross_available)

		child_main = _clamp_child_axis(child, child_main, true)
		child_cross = _clamp_child_axis(child, child_cross, false)
		main_cursor += before_main
		fit_child_in_rect(
			child,
			Rect2(
				_from_axes(main_cursor, cross_cursor + cross_offset),
				_from_axes(child_main, child_cross)
			)
		)
		main_cursor += child_main + after_main + gap + distribution.between


func _main_distribution(free_space: float, item_count: int) -> Dictionary:
	var result := {"offset": 0.0, "between": 0.0}
	match justify_content:
		MainAlignment.CENTER:
			result.offset = free_space * 0.5
		MainAlignment.END:
			result.offset = free_space
		MainAlignment.SPACE_BETWEEN:
			if item_count > 1:
				result.between = free_space / (item_count - 1)
		MainAlignment.SPACE_AROUND:
			if item_count > 0:
				result.between = free_space / item_count
				result.offset = result.between * 0.5
		MainAlignment.SPACE_EVENLY:
			if item_count > 0:
				result.between = free_space / (item_count + 1)
				result.offset = result.between
	return result


func _child_constrained_size(child: Control) -> Vector2:
	var intrinsic := child.get_combined_minimum_size()
	var result := intrinsic
	result.x = maxf(maxf(result.x, _child_value(child, "preferred_width", 0.0)), _child_value(child, "min_width", 0.0))
	result.y = maxf(maxf(result.y, _child_value(child, "preferred_height", 0.0)), _child_value(child, "min_height", 0.0))
	var child_max_width := _child_value(child, "max_width", 0.0)
	var child_max_height := _child_value(child, "max_height", 0.0)
	if child_max_width > 0.0:
		result.x = maxf(minf(result.x, child_max_width), intrinsic.x)
	if child_max_height > 0.0:
		result.y = maxf(minf(result.y, child_max_height), intrinsic.y)
	return result


func _child_footprint(child: Control) -> Vector2:
	var result := _child_constrained_size(child)
	var margins := _child_margins(child)
	result.x += margins.x + margins.z
	result.y += margins.y + margins.w
	return result


func _child_margins(child: Control) -> Vector4:
	return Vector4(
		_child_value(child, "margin_left", 0.0),
		_child_value(child, "margin_top", 0.0),
		_child_value(child, "margin_right", 0.0),
		_child_value(child, "margin_bottom", 0.0)
	)


func _child_value(child: Control, property_name: String, fallback: float) -> float:
	var metadata_name := StringName(META_PREFIX + property_name)
	if child.has_meta(metadata_name):
		return maxf(float(child.get_meta(metadata_name)), 0.0)

	for property in child.get_property_list():
		if property.name == property_name:
			return maxf(float(child.get(property_name)), 0.0)
	return fallback


func _clamp_child_axis(child: Control, value: float, main_axis: bool) -> float:
	var horizontal := main_axis == (direction == FlowDirection.ROW)
	var maximum_name := "max_width" if horizontal else "max_height"
	var maximum := _child_value(child, maximum_name, 0.0)
	if maximum > 0.0:
		return minf(value, maximum)
	return value


func _layout_children() -> Array[Control]:
	var result: Array[Control] = []
	for node in get_children():
		if node is Control and node.visible and not node.top_level:
			result.append(node)
	return result


func _new_line() -> Dictionary:
	return {
		"items": [],
		"main_size": 0.0,
		"cross_size": 0.0,
		"grow_total": 0.0,
	}


func _main_of(vector: Vector2) -> float:
	return vector.x if direction == FlowDirection.ROW else vector.y


func _cross_of(vector: Vector2) -> float:
	return vector.y if direction == FlowDirection.ROW else vector.x


func _from_axes(main: float, cross: float) -> Vector2:
	return Vector2(main, cross) if direction == FlowDirection.ROW else Vector2(cross, main)


func _invalidate_layout() -> void:
	if not is_inside_tree():
		return
	update_minimum_size()
	queue_sort()
	queue_redraw()
	_notify_parent_layout_changed()


func _notify_parent_layout_changed() -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	if parent is Container:
		parent.queue_sort()


func _on_resized() -> void:
	queue_sort()
	queue_redraw()


func _draw_box() -> void:
	if background_color.a <= 0.0 and (border_color.a <= 0.0 or border_width <= 0.0):
		return

	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(roundi(border_width))
	style.set_corner_radius_all(roundi(border_radius))
	draw_style_box(style, Rect2(Vector2.ZERO, size))
