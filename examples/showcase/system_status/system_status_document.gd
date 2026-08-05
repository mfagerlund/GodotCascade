extends "res://addons/godot_cascade/runtime/cascade_document.gd"

## Capture-time data source. A game can assign any Dictionary or Godot Object and
## call refresh_bindings() after its state changes.


func _init() -> void:
	binding_context = {
		"telemetry": {
			"status": "● All systems nominal",
			"reserve": 72.0,
			"reserve_label": "72%",
			"reserve_delta": "+4.8% this cycle",
			"reactor": 84.0,
			"life_support": 96.0,
			"navigation": 63.0,
			"last_sync": "Last synchronized 14 seconds ago",
			"tags": [
				{"id": "live", "label": "LIVE"},
				{"id": "linked", "label": "LINKED"},
			],
		}
	}


func _on_review_route() -> void:
	binding_context["telemetry"]["last_sync"] = "Route review requested"
	refresh_bindings()
