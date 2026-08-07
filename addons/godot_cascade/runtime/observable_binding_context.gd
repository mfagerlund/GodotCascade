extends RefCounted

## Wraps application state and emits explicit path invalidations without polling.
## The wrapped value remains a typed object, Resource, Array, or Dictionary.

signal paths_invalidated(paths: PackedStringArray)

var value: Variant


func _init(initial_value: Variant = null) -> void:
	value = initial_value


## Invalidates one exact dot-separated path and its parent/child dependencies.
func invalidate(path: String) -> bool:
	var normalized := path.strip_edges()
	if not is_valid_path(normalized):
		return false
	paths_invalidated.emit(PackedStringArray([normalized]))
	return true


## Coalesces several named paths into one synchronous invalidation notification.
func invalidate_many(paths: PackedStringArray) -> bool:
	var normalized_paths := PackedStringArray()
	for path in paths:
		var normalized := path.strip_edges()
		if not is_valid_path(normalized):
			return false
		if normalized not in normalized_paths:
			normalized_paths.append(normalized)
	if normalized_paths.is_empty():
		return false
	paths_invalidated.emit(normalized_paths)
	return true


## Requests a full binding refresh while preserving compatible native controls.
func invalidate_all() -> void:
	paths_invalidated.emit(PackedStringArray(["*"]))


static func is_valid_path(path: String) -> bool:
	var normalized := path.strip_edges()
	if normalized.is_empty() or normalized == "*":
		return false
	for segment in normalized.split(".", false):
		if segment.is_empty():
			return false
		if segment.is_valid_int():
			continue
		if not segment.is_valid_identifier():
			return false
	return true
