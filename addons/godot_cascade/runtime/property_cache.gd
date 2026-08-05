extends RefCounted

## Memoizes immutable property-name sets per script/native class.

static var _names_by_type: Dictionary = {}


static func has(target: Object, property_name: String) -> bool:
	var key := _type_key(target)
	if not _names_by_type.has(key):
		var names := {}
		for property in target.get_property_list():
			names[StringName(property.name)] = true
		_names_by_type[key] = names
	return _names_by_type[key].has(StringName(property_name))


static func _type_key(target: Object) -> String:
	var script: Script = target.get_script()
	if script != null:
		return "script:%s" % script.resource_path
	return "native:%s" % target.get_class()
