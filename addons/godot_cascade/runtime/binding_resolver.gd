extends RefCounted

## Resolves focused dot-separated one-way binding paths against dictionaries,
## arrays, and Godot objects without exposing method calls or expression evaluation.

const PropertyCache := preload("res://addons/godot_cascade/runtime/property_cache.gd")


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


## Assigns an exact dot-separated path without evaluating expressions or calling methods.
static func assign(context: Variant, path: String, value: Variant) -> Dictionary:
	var normalized := path.strip_edges()
	var segments := normalized.split(".", false)
	if segments.is_empty():
		return {"written": false, "message": "Binding path is empty."}
	var current: Variant = context
	for index in segments.size() - 1:
		var segment := str(segments[index])
		var result := _read_segment(current, segment)
		if not result["found"]:
			return {"written": false, "message": "Could not resolve '%s' at '%s'." % [normalized, segment]}
		current = result["value"]
	var leaf := str(segments[-1])
	if current is Dictionary:
		if current.has(leaf):
			current[leaf] = value
			return {"written": true, "message": ""}
		var string_name := StringName(leaf)
		if current.has(string_name):
			current[string_name] = value
			return {"written": true, "message": ""}
		return {"written": false, "message": "Could not resolve '%s' at '%s'." % [normalized, leaf]}
	if current is Array:
		if not leaf.is_valid_int():
			return {"written": false, "message": "Array binding '%s' requires a numeric final segment." % normalized}
		var array_index := leaf.to_int()
		if array_index < 0 or array_index >= current.size():
			return {"written": false, "message": "Array binding index is out of range in '%s'." % normalized}
		current[array_index] = value
		return {"written": true, "message": ""}
	if current is Object and _has_property(current, leaf):
		current.set(leaf, value)
		return {"written": true, "message": ""}
	return {"written": false, "message": "Could not write '%s' at '%s'." % [normalized, leaf]}


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
	return PropertyCache.has(target, property_name)
