extends RefCounted

## Optional bridge from Cascade values to Godot-native theme resources.


static func style_box(style: CascadeStyle) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = style.background_color
	box.border_color = style.border_color
	box.set_border_width_all(roundi(style.border_width))
	box.set_corner_radius_all(roundi(style.border_radius))
	box.content_margin_left = style.padding_left
	box.content_margin_top = style.padding_top
	box.content_margin_right = style.padding_right
	box.content_margin_bottom = style.padding_bottom
	return box


static func apply_style_box(control: Control, style: CascadeStyle, theme_slot: StringName = &"panel") -> void:
	control.add_theme_stylebox_override(theme_slot, style_box(style))
	control.set_meta("cascade_compatibility_tier", "adapted")
	var supported: PackedStringArray = control.get_meta("cascade_adapted_properties", PackedStringArray())
	for property_name in ["background", "background-color", "border", "border-color", "border-width", "border-radius", "padding"]:
		if property_name not in supported:
			supported.append(property_name)
	control.set_meta("cascade_adapted_properties", supported)


static func apply_text(control: Control, color: Color, font_size: int) -> void:
	control.add_theme_color_override(&"font_color", color)
	control.add_theme_font_size_override(&"font_size", maxi(font_size, 1))
	control.set_meta("cascade_compatibility_tier", "adapted")
	var supported: PackedStringArray = control.get_meta("cascade_adapted_properties", PackedStringArray())
	for property_name in ["color", "font-size"]:
		if property_name not in supported:
			supported.append(property_name)
	control.set_meta("cascade_adapted_properties", supported)
