@tool
extends Control

## GodotCascade-owned image component with deterministic fit and crop geometry.

const BoxPainter := preload("res://addons/godot_cascade/components/box_painter.gd")

enum FitMode { CONTAIN, COVER, FILL, NONE }

@export_group("Content")
@export var texture: Texture2D:
	set(next):
		texture = next
		update_minimum_size()
		queue_redraw()
@export var fit := FitMode.CONTAIN:
	set(next):
		fit = next
		queue_redraw()

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(next):
		var resolved := next if next != null else CascadeStyle.new()
		if cascade_style == resolved:
			return
		_disconnect_style()
		cascade_style = resolved
		_connect_style()
		_on_style_invalidated(CascadeStyle.Invalidation.ALL)


func _ready() -> void:
	_connect_style()
	clip_contents = true


func _get_minimum_size() -> Vector2:
	var intrinsic := texture.get_size() if texture != null else Vector2.ZERO
	var outer := BoxPainter.outer_minimum_size(
		intrinsic,
		cascade_style.padding(),
		cascade_style.border_width
	)
	if cascade_style.preferred_width > 0.0:
		outer.x = cascade_style.preferred_width
	if cascade_style.preferred_height > 0.0:
		outer.y = cascade_style.preferred_height
	return Vector2(maxf(outer.x, cascade_style.min_width), maxf(outer.y, cascade_style.min_height))


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	BoxPainter.draw_box(
		self,
		box,
		cascade_style.background_color,
		cascade_style.border_color,
		cascade_style.border_width,
		cascade_style.border_radius
	)
	if texture == null:
		return
	var geometry := image_geometry()
	var destination: Rect2 = geometry["destination"]
	var source: Rect2 = geometry["source"]
	if destination.size.x > 0.0 and destination.size.y > 0.0 and source.size.x > 0.0 and source.size.y > 0.0:
		draw_texture_rect_region(texture, destination, source)


func image_geometry() -> Dictionary:
	var content := BoxPainter.content_rect(
		Rect2(Vector2.ZERO, size),
		cascade_style.padding(),
		cascade_style.border_width
	)
	if texture == null or content.size.x <= 0.0 or content.size.y <= 0.0:
		return {"destination": Rect2(content.position, Vector2.ZERO), "source": Rect2()}
	var texture_size := texture.get_size()
	var full_source := Rect2(Vector2.ZERO, texture_size)
	match fit:
		FitMode.FILL:
			return {"destination": content, "source": full_source}
		FitMode.COVER:
			var content_ratio := content.size.x / content.size.y
			var texture_ratio := texture_size.x / texture_size.y
			var source := full_source
			if texture_ratio > content_ratio:
				source.size.x = texture_size.y * content_ratio
				source.position.x = (texture_size.x - source.size.x) * 0.5
			else:
				source.size.y = texture_size.x / content_ratio
				source.position.y = (texture_size.y - source.size.y) * 0.5
			return {"destination": content, "source": source}
		FitMode.NONE:
			var visible_size := texture_size.min(content.size)
			var source_position := (texture_size - visible_size) * 0.5
			var destination_position := content.position + (content.size - visible_size) * 0.5
			return {
				"destination": Rect2(destination_position, visible_size),
				"source": Rect2(source_position, visible_size),
			}
		_:
			var scale := minf(content.size.x / texture_size.x, content.size.y / texture_size.y)
			var destination_size := texture_size * scale
			return {
				"destination": Rect2(content.position + (content.size - destination_size) * 0.5, destination_size),
				"source": full_source,
			}


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _disconnect_style() -> void:
	if cascade_style != null and cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.disconnect(_on_style_invalidated)


func _on_style_invalidated(flags: int) -> void:
	if flags & CascadeStyle.Invalidation.DRAW and is_inside_tree():
		queue_redraw()
	if flags & CascadeStyle.Invalidation.MEASURE and is_inside_tree():
		update_minimum_size()
	if flags & CascadeStyle.Invalidation.ARRANGE and is_inside_tree() and get_parent() is Container:
		get_parent().queue_sort()
