extends RefCounted

## Runtime registry for native custom GXML components and lifecycle callbacks.

static var _definitions: Dictionary = {}


static func register(
	tag_name: String,
	factory: Callable,
	on_mount: Callable = Callable(),
	on_update: Callable = Callable(),
	on_unmount: Callable = Callable()
) -> void:
	_definitions[tag_name.to_lower()] = {
		"factory": factory,
		"mount": on_mount,
		"update": on_update,
		"unmount": on_unmount,
	}


static func unregister(tag_name: String) -> void:
	_definitions.erase(tag_name.to_lower())


static func has(tag_name: String) -> bool:
	return _definitions.has(tag_name.to_lower())


static func create(tag_name: String) -> Control:
	var definition: Dictionary = _definitions.get(tag_name.to_lower(), {})
	if definition.is_empty() or not definition["factory"].is_valid():
		return null
	var created: Variant = definition["factory"].call()
	return created as Control if created is Control else null


static func mount_tree(node: Node) -> void:
	if node is Control:
		var control := node as Control
		var tag_name := str(control.get_meta("cascade_element_type", "")).to_lower()
		var definition: Dictionary = _definitions.get(tag_name, {})
		if not definition.is_empty() and not control.get_meta("cascade_component_mounted", false):
			control.set_meta("cascade_component_mounted", true)
			var callback: Callable = definition["mount"]
			if callback.is_valid():
				callback.call(control)
	for child in node.get_children():
		mount_tree(child)


static func update(control: Control) -> void:
	var definition: Dictionary = _definitions.get(str(control.get_meta("cascade_element_type", "")).to_lower(), {})
	if definition.is_empty():
		return
	var callback: Callable = definition["update"]
	if callback.is_valid():
		callback.call(control)


static func unmount_tree(node: Node) -> void:
	for child in node.get_children():
		unmount_tree(child)
	if not node is Control:
		return
	var control := node as Control
	var definition: Dictionary = _definitions.get(str(control.get_meta("cascade_element_type", "")).to_lower(), {})
	if not definition.is_empty() and control.get_meta("cascade_component_mounted", false):
		var callback: Callable = definition["unmount"]
		if callback.is_valid():
			callback.call(control)
		control.remove_meta("cascade_component_mounted")
