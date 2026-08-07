extends "res://addons/godot_cascade/runtime/cascade_document.gd"


class PlayerState extends RefCounted:
	var name := "Rhea"
	var status := "Armor reserve"
	var health := 72.0


var player := PlayerState.new()


func _ready() -> void:
	binding_context = {"player": player}
	event_context = self
	super()


func _on_repair() -> void:
	player.health = minf(player.health + 10.0, 100.0)
	player.status = "Armor repaired"
	refresh_bindings()
