extends RefCounted

## Shared box geometry and drawing used by GodotCascade-owned controls.


static func outer_minimum_size(
	content_size: Vector2,
	padding: Vector4,
	border_width: float
) -> Vector2:
	var border_total := maxf(border_width, 0.0) * 2.0
	return content_size + Vector2(
		maxf(padding.x, 0.0) + maxf(padding.z, 0.0) + border_total,
		maxf(padding.y, 0.0) + maxf(padding.w, 0.0) + border_total
	)


static func content_rect(box_rect: Rect2, padding: Vector4, border_width: float) -> Rect2:
	var border := maxf(border_width, 0.0)
	var left := border + maxf(padding.x, 0.0)
	var top := border + maxf(padding.y, 0.0)
	var right := border + maxf(padding.z, 0.0)
	var bottom := border + maxf(padding.w, 0.0)
	return Rect2(
		box_rect.position + Vector2(left, top),
		Vector2(
			maxf(box_rect.size.x - left - right, 0.0),
			maxf(box_rect.size.y - top - bottom, 0.0)
		)
	)


static func draw_box(
	canvas_item: CanvasItem,
	box_rect: Rect2,
	background_color: Color,
	border_color: Color,
	border_width: float,
	border_radius: Variant,
	background_gradient: Dictionary = {}
) -> void:
	if background_color.a <= 0.0 and background_gradient.is_empty() and (border_color.a <= 0.0 or border_width <= 0.0):
		return
	if not background_gradient.is_empty():
		_draw_linear_gradient(canvas_item, box_rect, border_radius, background_gradient)

	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(roundi(maxf(border_width, 0.0)))
	if border_radius is Vector4:
		var radii := border_radius as Vector4
		style.corner_radius_top_left = roundi(maxf(radii.x, 0.0))
		style.corner_radius_top_right = roundi(maxf(radii.y, 0.0))
		style.corner_radius_bottom_right = roundi(maxf(radii.z, 0.0))
		style.corner_radius_bottom_left = roundi(maxf(radii.w, 0.0))
	else:
		style.set_corner_radius_all(roundi(maxf(float(border_radius), 0.0)))
	canvas_item.draw_style_box(style, box_rect)


static func _draw_linear_gradient(
	canvas_item: CanvasItem,
	box_rect: Rect2,
	border_radius: Variant,
	gradient: Dictionary
) -> void:
	if box_rect.size.x <= 0.0 or box_rect.size.y <= 0.0:
		return
	var radius := float(border_radius) if not border_radius is Vector4 else 0.0
	radius = minf(maxf(radius, 0.0), minf(box_rect.size.x, box_rect.size.y) * 0.5)
	var points := _rounded_rect_points(box_rect, radius)
	var colors := PackedColorArray()
	var angle := float(gradient.get("angle", PI))
	var direction := Vector2(sin(angle), -cos(angle)).normalized()
	var corners := [box_rect.position, Vector2(box_rect.end.x, box_rect.position.y), box_rect.end, Vector2(box_rect.position.x, box_rect.end.y)]
	var minimum := INF
	var maximum := -INF
	for corner in corners:
		var projection := (corner as Vector2).dot(direction)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	var span := maxf(maximum - minimum, 0.001)
	var from_color: Color = gradient.get("from", Color.TRANSPARENT)
	var to_color: Color = gradient.get("to", Color.TRANSPARENT)
	for point in points:
		colors.append(from_color.lerp(to_color, clampf((point.dot(direction) - minimum) / span, 0.0, 1.0)))
	canvas_item.draw_polygon(points, colors)


static func _rounded_rect_points(rectangle: Rect2, radius: float) -> PackedVector2Array:
	if radius <= 0.0:
		return PackedVector2Array([
			rectangle.position,
			Vector2(rectangle.end.x, rectangle.position.y),
			rectangle.end,
			Vector2(rectangle.position.x, rectangle.end.y),
		])
	var result := PackedVector2Array()
	var centers := [
		Vector2(rectangle.end.x - radius, rectangle.position.y + radius),
		Vector2(rectangle.end.x - radius, rectangle.end.y - radius),
		Vector2(rectangle.position.x + radius, rectangle.end.y - radius),
		Vector2(rectangle.position.x + radius, rectangle.position.y + radius),
	]
	for corner in 4:
		var start_angle := -PI * 0.5 + corner * PI * 0.5
		for step in 5:
			var angle := start_angle + step * PI * 0.5 / 4.0
			result.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return result
