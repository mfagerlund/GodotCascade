extends RefCounted

## Reconciliation-time CascadeStyle transitions with replace-from-current interruption.

const STYLE_PROPERTIES: PackedStringArray = [
	"background_color", "border_color", "border_width", "border_radius",
	"padding_left", "padding_top", "padding_right", "padding_bottom",
	"margin_left", "margin_top", "margin_right", "margin_bottom",
	"preferred_width", "preferred_height", "min_width", "min_height",
	"max_width", "max_height", "flex_grow",
]

const PROPERTY_MAP := {
	"background": "background_color",
	"background-color": "background_color",
	"border-color": "border_color",
	"border-width": "border_width",
	"border-radius": "border_radius",
	"padding-left": "padding_left",
	"padding-top": "padding_top",
	"padding-right": "padding_right",
	"padding-bottom": "padding_bottom",
	"margin-left": "margin_left",
	"margin-top": "margin_top",
	"margin-right": "margin_right",
	"margin-bottom": "margin_bottom",
	"width": "preferred_width",
	"height": "preferred_height",
	"min-width": "min_width",
	"min-height": "min_height",
	"max-width": "max_width",
	"max-height": "max_height",
	"flex-grow": "flex_grow",
}


static func mapped_property(property_name: String) -> String:
	return str(PROPERTY_MAP.get(property_name.to_lower(), ""))


static func apply_style(control: Control, desired: CascadeStyle) -> void:
	var current: CascadeStyle = control.get("cascade_style")
	var duration := float(control.get_meta("cascade_transition_duration", 0.0))
	var authored: PackedStringArray = control.get_meta("cascade_transition_properties", PackedStringArray())
	var previous: Variant = control.get_meta("cascade_transition_tween") if control.has_meta("cascade_transition_tween") else null
	if previous is Tween and previous.is_valid():
		previous.kill()
	if current == null or duration <= 0.0 or authored.is_empty() or not control.is_inside_tree():
		control.set("cascade_style", desired.duplicate(true))
		if control.has_meta("cascade_transition_tween"):
			control.remove_meta("cascade_transition_tween")
		return
	var properties := STYLE_PROPERTIES if "all" in authored else authored
	var tween := control.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var animated := false
	for property_name in STYLE_PROPERTIES:
		var target: Variant = desired.get(property_name)
		if property_name in properties and current.get(property_name) != target:
			tween.tween_property(current, property_name, target, duration)
			animated = true
		else:
			current.set(property_name, target)
	if not animated:
		tween.kill()
		control.remove_meta("cascade_transition_tween")
		return
	control.set_meta("cascade_transition_tween", tween)
