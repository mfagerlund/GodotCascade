extends RefCounted

## Memoizes immutable property-name sets per script/native class.

static var _names_by_type: Dictionary = {}
static var _dynamic_scripts: Dictionary = {}


static func has(target: Object, property_name: String) -> bool:
	var key := _type_key(target)
	if not _names_by_type.has(key):
		var names := {}
		for property in target.get_property_list():
			names[StringName(property.name)] = true
		_names_by_type[key] = names
	return _names_by_type[key].has(StringName(property_name))


static func has_uncached(target: Object, property_name: String) -> bool:
	var wanted := StringName(property_name)
	for property in target.get_property_list():
		if StringName(property.name) == wanted:
			return true
	return false


static func has_dynamic_property_list(target: Object) -> bool:
	var script: Script = target.get_script()
	if script == null:
		return false
	var key := script.get_instance_id()
	if not _dynamic_scripts.has(key):
		# Walk base scripts explicitly: virtual callbacks are not consistently
		# reported by has_script_method across supported Godot patch releases.
		var current: Script = script
		var dynamic := false
		while current != null:
			if current.get_script_method_list().any(func(method: Dictionary): return str(method.get("name", "")) == "_get_property_list"):
				dynamic = true
				break
			current = current.get_base_script()
		_dynamic_scripts[key] = dynamic
	return bool(_dynamic_scripts[key])


static func _type_key(target: Object) -> String:
	var script: Script = target.get_script()
	if script != null:
		# Inner GDScript classes share a resource path but have distinct Script
		# instances and property shapes.
		return "script:%s" % script.get_instance_id()
	return "native:%s" % target.get_class()
