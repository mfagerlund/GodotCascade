extends RefCounted

## Pure geometry calculator for CascadeBox.
##
## The engine knows nothing about the scene tree. Callers provide measured items and
## receive rectangles in the same order, keeping Godot node mutation at the adapter.

const DIRECTION_ROW := 0
const DIRECTION_COLUMN := 1

const JUSTIFY_START := 0
const JUSTIFY_CENTER := 1
const JUSTIFY_END := 2
const JUSTIFY_SPACE_BETWEEN := 3
const JUSTIFY_SPACE_AROUND := 4
const JUSTIFY_SPACE_EVENLY := 5

const ALIGN_START := 0
const ALIGN_CENTER := 1
const ALIGN_END := 2
const ALIGN_STRETCH := 3


class LayoutItem:
	extends RefCounted

	var minimum_size: Vector2
	var margins: Vector4
	var flex_grow: float
	var flex_shrink: float
	var flex_basis: float
	var shrink_minimum_size: Vector2
	var maximum_size: Vector2
	var align_self: int


	func _init(
		item_minimum_size: Vector2,
		item_margins := Vector4.ZERO,
		item_flex_grow := 0.0,
		item_maximum_size := Vector2(INF, INF),
		item_align_self := -1,
		item_flex_shrink := 0.0,
		item_flex_basis := -1.0,
		item_shrink_minimum_size := Vector2.ZERO
	) -> void:
		minimum_size = item_minimum_size.max(Vector2.ZERO)
		margins = Vector4(
			maxf(item_margins.x, 0.0),
			maxf(item_margins.y, 0.0),
			maxf(item_margins.z, 0.0),
			maxf(item_margins.w, 0.0)
		)
		flex_grow = maxf(item_flex_grow, 0.0)
		flex_shrink = maxf(item_flex_shrink, 0.0)
		flex_basis = item_flex_basis if item_flex_basis >= 0.0 else -1.0
		shrink_minimum_size = item_shrink_minimum_size.max(Vector2.ZERO).min(minimum_size)
		maximum_size = Vector2(
			maxf(item_maximum_size.x, minimum_size.x),
			maxf(item_maximum_size.y, minimum_size.y)
		)
		align_self = clampi(item_align_self, -1, ALIGN_STRETCH)


class LayoutRequest:
	extends RefCounted

	var size := Vector2.ZERO
	var padding := Vector4.ZERO
	var gap := 0.0
	var line_gap := 0.0
	var direction := DIRECTION_COLUMN
	var wrap := false
	var justify_content := JUSTIFY_START
	var align_items := ALIGN_STRETCH
	var pixel_snap := true


static func measure(items: Array[LayoutItem], request: LayoutRequest) -> Vector2:
	var content_minimum := Vector2.ZERO
	if not items.is_empty():
		if request.wrap:
			# Wrapped cross-size depends on the assigned main-axis constraint.
			# The largest item is the stable intrinsic minimum before arrangement.
			for item in items:
				var footprint := _item_measure_footprint(item, request.direction)
				content_minimum.x = maxf(content_minimum.x, footprint.x)
				content_minimum.y = maxf(content_minimum.y, footprint.y)
		else:
			for item in items:
				var footprint := _item_measure_footprint(item, request.direction)
				if request.direction == DIRECTION_ROW:
					content_minimum.x += footprint.x
					content_minimum.y = maxf(content_minimum.y, footprint.y)
				else:
					content_minimum.x = maxf(content_minimum.x, footprint.x)
					content_minimum.y += footprint.y

			var total_gap := request.gap * maxf(items.size() - 1, 0)
			if request.direction == DIRECTION_ROW:
				content_minimum.x += total_gap
			else:
				content_minimum.y += total_gap

	content_minimum.x += request.padding.x + request.padding.z
	content_minimum.y += request.padding.y + request.padding.w
	return content_minimum


static func arrange(items: Array[LayoutItem], request: LayoutRequest) -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	if items.is_empty():
		return rectangles

	for item in items:
		rectangles.append(Rect2(Vector2.ZERO, item.minimum_size))

	var content_position := Vector2(request.padding.x, request.padding.y)
	var content_size := Vector2(
		maxf(request.size.x - request.padding.x - request.padding.z, 0.0),
		maxf(request.size.y - request.padding.y - request.padding.w, 0.0)
	)
	var lines := _build_lines(items, request, _main_of(content_size, request.direction))
	if not request.wrap and lines.size() == 1:
		lines[0]["cross_size"] = maxf(
			float(lines[0]["cross_size"]),
			_cross_of(content_size, request.direction)
		)

	var cross_cursor := _cross_of(content_position, request.direction)
	for line in lines:
		_arrange_line(line, items, rectangles, request, content_position, content_size, cross_cursor)
		cross_cursor += float(line["cross_size"]) + request.line_gap
	if request.pixel_snap:
		for index in rectangles.size():
			rectangles[index] = _snap_rect(rectangles[index])
	return rectangles


static func _build_lines(
	items: Array[LayoutItem],
	request: LayoutRequest,
	available_main: float
) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var current := _new_line()

	for index in items.size():
		var item := items[index]
		var footprint := _item_footprint(item, request.direction)
		var next_main := float(current["main_size"])
		if not current["indices"].is_empty():
			next_main += request.gap
		next_main += _main_of(footprint, request.direction)

		if request.wrap and not current["indices"].is_empty() and next_main > available_main:
			lines.append(current)
			current = _new_line()

		if not current["indices"].is_empty():
			current["main_size"] = float(current["main_size"]) + request.gap
		current["indices"].append(index)
		current["main_size"] = float(current["main_size"]) + _main_of(footprint, request.direction)
		current["cross_size"] = maxf(
			float(current["cross_size"]),
			_cross_of(footprint, request.direction)
		)
		current["grow_total"] = float(current["grow_total"]) + item.flex_grow

	if not current["indices"].is_empty():
		lines.append(current)
	return lines


static func _arrange_line(
	line: Dictionary,
	items: Array[LayoutItem],
	rectangles: Array[Rect2],
	request: LayoutRequest,
	content_position: Vector2,
	content_size: Vector2,
	cross_cursor: float
) -> void:
	var available_main := _main_of(content_size, request.direction)
	var free_main := available_main - float(line["main_size"])
	var grow_total := float(line["grow_total"])
	var growth := _resize_main_sizes(line["indices"], items, request.direction, free_main)
	var distributable := maxf(float(growth["remaining"]) if grow_total > 0.0 else free_main, 0.0)
	var distribution := _main_distribution(
		distributable,
		line["indices"].size(),
		request.justify_content
	)
	var main_cursor := _main_of(content_position, request.direction) + float(distribution["offset"])

	for index in line["indices"]:
		var item := items[index]
		var before_main := item.margins.x if request.direction == DIRECTION_ROW else item.margins.y
		var after_main := item.margins.z if request.direction == DIRECTION_ROW else item.margins.w
		var before_cross := item.margins.y if request.direction == DIRECTION_ROW else item.margins.x
		var after_cross := item.margins.w if request.direction == DIRECTION_ROW else item.margins.z
		var child_main := float(growth["sizes"].get(
			index,
			_item_base_main(item, request.direction)
		))
		var child_cross := _cross_of(item.minimum_size, request.direction)

		var cross_available := maxf(float(line["cross_size"]) - before_cross - after_cross, 0.0)
		var cross_offset := before_cross
		var item_alignment := item.align_self if item.align_self >= 0 else request.align_items
		match item_alignment:
			ALIGN_CENTER:
				cross_offset += maxf(cross_available - child_cross, 0.0) * 0.5
			ALIGN_END:
				cross_offset += maxf(cross_available - child_cross, 0.0)
			ALIGN_STRETCH:
				child_cross = maxf(child_cross, cross_available)

		child_main = _clamp_item_axis(item, child_main, request.direction, true)
		child_cross = _clamp_item_axis(item, child_cross, request.direction, false)
		main_cursor += before_main
		rectangles[index] = Rect2(
			_from_axes(main_cursor, cross_cursor + cross_offset, request.direction),
			_from_axes(child_main, child_cross, request.direction)
		)
		main_cursor += child_main + after_main + request.gap + float(distribution["between"])


static func _grow_main_sizes(
	indices: Array,
	items: Array[LayoutItem],
	direction: int,
	free_space: float
) -> Dictionary:
	var sizes := {}
	var active: Array[int] = []
	for index in indices:
		var item := items[index]
		var base_size := _item_base_main(item, direction)
		sizes[index] = base_size
		if item.flex_grow > 0.0 and base_size < _main_of(item.maximum_size, direction):
			active.append(index)

	var remaining := free_space
	while remaining > 0.001 and not active.is_empty():
		var active_grow := 0.0
		for index in active:
			active_grow += items[index].flex_grow
		if active_grow <= 0.0:
			break

		var distributed := 0.0
		var next_active: Array[int] = []
		for index in active:
			var item := items[index]
			var share := remaining * item.flex_grow / active_grow
			var maximum := _main_of(item.maximum_size, direction)
			var capacity := maxf(maximum - float(sizes[index]), 0.0)
			var applied := minf(share, capacity)
			sizes[index] = float(sizes[index]) + applied
			distributed += applied
			if float(sizes[index]) < maximum - 0.001:
				next_active.append(index)

		remaining -= distributed
		active = next_active
		if distributed <= 0.001:
			break

	return {"sizes": sizes, "remaining": remaining}


static func _resize_main_sizes(
	indices: Array,
	items: Array[LayoutItem],
	direction: int,
	free_space: float
) -> Dictionary:
	if free_space >= 0.0:
		return _grow_main_sizes(indices, items, direction, free_space)

	var sizes := {}
	var active: Array[int] = []
	for index in indices:
		var item := items[index]
		var base_size := _item_base_main(item, direction)
		sizes[index] = base_size
		if item.flex_shrink > 0.0 and base_size > _item_shrink_minimum_main(item, direction):
			active.append(index)

	var deficit := -free_space
	while deficit > 0.001 and not active.is_empty():
		var total_weight := 0.0
		for index in active:
			total_weight += items[index].flex_shrink * _item_base_main(items[index], direction)
		if total_weight <= 0.0:
			break

		var removed := 0.0
		var next_active: Array[int] = []
		for index in active:
			var item := items[index]
			var weight := item.flex_shrink * _item_base_main(item, direction)
			var share := deficit * weight / total_weight
			var minimum := _item_shrink_minimum_main(item, direction)
			var capacity := maxf(float(sizes[index]) - minimum, 0.0)
			var applied := minf(share, capacity)
			sizes[index] = float(sizes[index]) - applied
			removed += applied
			if float(sizes[index]) > minimum + 0.001:
				next_active.append(index)
		deficit -= removed
		active = next_active
		if removed <= 0.001:
			break
	return {"sizes": sizes, "remaining": -deficit}


static func _main_distribution(free_space: float, item_count: int, alignment: int) -> Dictionary:
	var result := {"offset": 0.0, "between": 0.0}
	match alignment:
		JUSTIFY_CENTER:
			result["offset"] = free_space * 0.5
		JUSTIFY_END:
			result["offset"] = free_space
		JUSTIFY_SPACE_BETWEEN:
			if item_count > 1:
				result["between"] = free_space / (item_count - 1)
		JUSTIFY_SPACE_AROUND:
			if item_count > 0:
				result["between"] = free_space / item_count
				result["offset"] = float(result["between"]) * 0.5
		JUSTIFY_SPACE_EVENLY:
			if item_count > 0:
				result["between"] = free_space / (item_count + 1)
				result["offset"] = result["between"]
	return result


static func _item_footprint(item: LayoutItem, direction: int) -> Vector2:
	var base_size := item.minimum_size
	if direction == DIRECTION_ROW:
		base_size.x = _item_base_main(item, direction)
	else:
		base_size.y = _item_base_main(item, direction)
	return base_size + Vector2(
		item.margins.x + item.margins.z,
		item.margins.y + item.margins.w
	)


static func _item_measure_footprint(item: LayoutItem, direction: int) -> Vector2:
	var footprint := _item_footprint(item, direction)
	if item.flex_shrink <= 0.0:
		return footprint
	var main := _item_shrink_minimum_main(item, direction)
	if direction == DIRECTION_ROW:
		footprint.x = main + item.margins.x + item.margins.z
	else:
		footprint.y = main + item.margins.y + item.margins.w
	return footprint


static func _item_base_main(item: LayoutItem, direction: int) -> float:
	var authored := item.flex_basis if item.flex_basis >= 0.0 else _main_of(item.minimum_size, direction)
	return clampf(
		authored,
		_item_shrink_minimum_main(item, direction),
		_main_of(item.maximum_size, direction)
	)


static func _item_shrink_minimum_main(item: LayoutItem, direction: int) -> float:
	return _main_of(item.shrink_minimum_size, direction)


static func _clamp_item_axis(
	item: LayoutItem,
	value: float,
	direction: int,
	main_axis: bool
) -> float:
	var horizontal := main_axis == (direction == DIRECTION_ROW)
	var maximum := item.maximum_size.x if horizontal else item.maximum_size.y
	return minf(value, maximum)


static func _new_line() -> Dictionary:
	return {
		"indices": [],
		"main_size": 0.0,
		"cross_size": 0.0,
		"grow_total": 0.0,
	}


static func _main_of(vector: Vector2, direction: int) -> float:
	return vector.x if direction == DIRECTION_ROW else vector.y


static func _cross_of(vector: Vector2, direction: int) -> float:
	return vector.y if direction == DIRECTION_ROW else vector.x


static func _from_axes(main: float, cross: float, direction: int) -> Vector2:
	return Vector2(main, cross) if direction == DIRECTION_ROW else Vector2(cross, main)


static func _snap_rect(rectangle: Rect2) -> Rect2:
	var snapped_position := rectangle.position.round()
	var snapped_end := rectangle.end.round()
	return Rect2(snapped_position, (snapped_end - snapped_position).max(Vector2.ZERO))
