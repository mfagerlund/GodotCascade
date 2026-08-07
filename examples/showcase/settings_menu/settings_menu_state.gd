class_name ShowcaseSettingsMenuState
extends RefCounted

## Typed application state used by the settings binding showcase.


class HudChannelState extends RefCounted:
	var id: String
	var label: String
	var enabled: bool


	func _init(channel_id: String, channel_label: String, channel_enabled: bool) -> void:
		id = channel_id
		label = channel_label
		enabled = channel_enabled


class SettingsState extends RefCounted:
	var profile := "Rhea"
	var shadows := true
	var bloom := true
	var vsync := true
	var ui_scale := 100.0
	var quality := "high"
	var notes := "Ready for the next match."
	var hud_channels: Array[HudChannelState] = [
		HudChannelState.new("damage", "Damage numbers", true),
		HudChannelState.new("team", "Team markers", false),
	]


class UiState extends RefCounted:
	var scale_label := "100%"
	var status := "Change a setting, then apply"


var settings := SettingsState.new()
var ui := UiState.new()
