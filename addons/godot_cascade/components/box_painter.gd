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
	border_radius: float
) -> void:
	if background_color.a <= 0.0 and (border_color.a <= 0.0 or border_width <= 0.0):
		return

	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(roundi(maxf(border_width, 0.0)))
	style.set_corner_radius_all(roundi(maxf(border_radius, 0.0)))
	canvas_item.draw_style_box(style, box_rect)
