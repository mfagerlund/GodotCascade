extends "res://addons/godot_cascade/runtime/cascade_document.gd"

const LeaderboardState := preload("res://examples/showcase/leaderboard/leaderboard_state.gd")

var model := LeaderboardState.new()


func _init() -> void:
	binding_context = model
	event_context = self


func _on_record_result() -> void:
	model.entries[0].wins += 1
	model.entries[0].rating += 12
	model.status = "Recorded a win for Rhea · rating 2492"
	refresh_bindings()
