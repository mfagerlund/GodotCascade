extends RefCounted

const ArrayItemModel := preload("res://addons/godot_cascade/runtime/array_item_model.gd")

var items: CascadeArrayItemModel
var status := "10,000 records · bounded native virtual window"
var count_label := "10,000 MODEL ITEMS"


func _init() -> void:
	var initial: Array = []
	for index in 10_000:
		initial.append({
			"id": "record-%05d" % index,
			"name": "Cargo record %05d" % index,
			"category": ["Navigation", "Reactor", "Medical", "Survey"][index % 4],
			"value": "%s cr" % (1200 + (index * 73) % 88_000),
		})
	items = ArrayItemModel.new(initial, func(item: Dictionary): return item["id"])


func refresh_count() -> void:
	count_label = "%s MODEL ITEMS" % items.item_count()
