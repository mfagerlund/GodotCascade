extends RefCounted

## Shared strict grammar for retained binding and invalidation paths.


static func normalize(path: String) -> String:
	var normalized := path.strip_edges()
	return normalized if is_valid(normalized) else ""


static func is_valid(path: String) -> bool:
	var normalized := path.strip_edges()
	if normalized.is_empty() or normalized == "*" or normalized.begins_with(".") or normalized.ends_with(".") or ".." in normalized:
		return false
	for segment in normalized.split(".", true):
		if segment.is_empty():
			return false
		if _is_decimal_segment(segment):
			continue
		if not segment.is_valid_identifier():
			return false
	return true


static func _is_decimal_segment(segment: String) -> bool:
	if segment.is_empty() or (segment.length() > 1 and segment.begins_with("0")):
		return false
	for character in segment:
		if character < "0" or character > "9":
			return false
	return true
