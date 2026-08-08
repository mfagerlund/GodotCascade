extends RefCounted

## Development-time compatibility classification for native Control integration.

const CascadeBox := preload("res://addons/godot_cascade/layout/cascade_box.gd")
const CascadeGrid := preload("res://addons/godot_cascade/layout/cascade_grid.gd")
const CascadeStack := preload("res://addons/godot_cascade/layout/cascade_stack.gd")
const CascadeButton := preload("res://addons/godot_cascade/components/cascade_button.gd")
const CascadeCheckbox := preload("res://addons/godot_cascade/components/cascade_checkbox.gd")
const CascadeRadioButton := preload("res://addons/godot_cascade/components/cascade_radio_button.gd")
const CascadeSwitch := preload("res://addons/godot_cascade/components/cascade_switch.gd")
const CascadeSelect := preload("res://addons/godot_cascade/components/cascade_select.gd")
const CascadeSlider := preload("res://addons/godot_cascade/components/cascade_slider.gd")
const CascadeLabel := preload("res://addons/godot_cascade/components/cascade_label.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const CascadeProgress := preload("res://addons/godot_cascade/components/cascade_progress.gd")
const CascadeImage := preload("res://addons/godot_cascade/components/cascade_image.gd")
const CascadeTable := preload("res://addons/godot_cascade/components/cascade_table.gd")
const CascadeTablePart := preload("res://addons/godot_cascade/components/cascade_table_part.gd")
const CascadeTableCell := preload("res://addons/godot_cascade/components/cascade_table_cell.gd")

enum Tier { EXACT, ADAPTED, LAYOUT_ONLY }

const LAYOUT_PROPERTIES := {
	"width": true, "height": true, "min-width": true, "min-height": true,
	"max-width": true, "max-height": true, "margin": true, "margin-left": true,
	"margin-top": true, "margin-right": true, "margin-bottom": true,
	"flex-grow": true, "flex-shrink": true, "flex-basis": true, "align-self": true, "grid-column": true, "grid-row": true,
	"position": true, "left": true, "top": true, "right": true, "bottom": true,
	"opacity": true, "transform": true, "transform-origin": true, "font-source": true,
}


static func tier(control: Control) -> Tier:
	if _is_exact(control):
		return Tier.EXACT
	if str(control.get_meta("cascade_compatibility_tier", "")) == "adapted":
		return Tier.ADAPTED
	return Tier.LAYOUT_ONLY


static func tier_name(control: Control) -> String:
	return ["exact", "adapted", "layout-only"][tier(control)]


static func diagnose_property(control: Control, property_name: String) -> Dictionary:
	var resolved_tier := tier(control)
	if resolved_tier == Tier.EXACT or LAYOUT_PROPERTIES.has(property_name):
		return {}
	if resolved_tier == Tier.ADAPTED:
		var supported: PackedStringArray = control.get_meta("cascade_adapted_properties", PackedStringArray())
		if property_name in supported:
			return _warning("Property '%s' on %s uses an adapted native mapping; its documented limitations apply." % [property_name, control.get_class()])
		return _warning("Property '%s' is not supported by the adapted %s control." % [property_name, control.get_class()])
	return _warning("Property '%s' is visual and cannot be applied exactly to layout-only %s; native appearance is unchanged." % [property_name, control.get_class()])


static func _is_exact(control: Control) -> bool:
	return (
		control is CascadeBox or control is CascadeGrid or control is CascadeStack
		or control is CascadePanel or control is CascadeLabel or control is CascadeImage
		or control is CascadeButton or control is CascadeCheckbox or control is CascadeRadioButton
		or control is CascadeSwitch or control is CascadeSelect or control is CascadeSlider
		or control is CascadeProgress
		or control is CascadeTable or control is CascadeTablePart or control is CascadeTableCell
	)


static func _warning(message: String) -> Dictionary:
	return {"severity": "warning", "message": message}
