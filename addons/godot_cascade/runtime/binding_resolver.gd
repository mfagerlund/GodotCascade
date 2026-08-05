extends RefCounted

## Resolves focused dot-separated one-way binding paths against dictionaries,
## arrays, and Godot objects without exposing method calls or expression evaluation.


static func resolve(context: Variant, path: String) -> Dictionary:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return {"found": false, "value": null, "message": "Binding path is empty."}

	var current: Variant = context
	for segment in normalized.split(".", false):
		var result := _read_segment(current, segment)
		if not result["found"]:
			return {
				"found": false,
				"value": null,
				"message": "Could not resolve '%s' at '%s'." % [normalized, segment],
			}
		current = result["value"]
	return {"found": true, "value": current, "message": ""}


static func _read_segment(source: Variant, segment: String) -> Dictionary:
	if source is Dictionary:
		if source.has(segment):
			return {"found": true, "value": source[segment]}
		var string_name := StringName(segment)
		if source.has(string_name):
			return {"found": true, "value": source[string_name]}
		return {"found": false, "value": null}

	if source is Array:
		if not segment.is_valid_int():
			return {"found": false, "value": null}
		var index := segment.to_int()
		if index < 0 or index >= source.size():
			return {"found": false, "value": null}
		return {"found": true, "value": source[index]}

	if source is Object and _has_property(source, segment):
		return {"found": true, "value": source.get(segment)}
	return {"found": false, "value": null}


static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
