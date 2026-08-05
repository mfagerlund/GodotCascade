extends RefCounted

## Typed values for the supported GCSS grammar.

enum Kind { INVALID, KEYWORD, NUMBER, LENGTH, TIME, COLOR, STRING }

var kind := Kind.INVALID
var source := ""
var number := 0.0
var unit := ""
var color := Color.TRANSPARENT
var text := ""


static func parse(raw: String) -> RefCounted:
	var result := new()
	result.source = raw
	var normalized := raw.strip_edges()
	if normalized.is_empty():
		return result
	if normalized.length() >= 2 and normalized[0] in ["\"", "'"] and normalized[-1] == normalized[0]:
		result.kind = Kind.STRING
		result.text = normalized.substr(1, normalized.length() - 2)
		return result
	var black_probe := Color.from_string(normalized, Color.BLACK)
	var white_probe := Color.from_string(normalized, Color.WHITE)
	if black_probe == white_probe:
		result.kind = Kind.COLOR
		result.color = black_probe
		return result
	for suffix in ["ms", "px", "s"]:
		if normalized.to_lower().ends_with(suffix):
			var magnitude := normalized.substr(0, normalized.length() - suffix.length()).strip_edges()
			if not magnitude.is_valid_float():
				return result
			result.number = magnitude.to_float()
			result.unit = suffix
			result.kind = Kind.TIME if suffix in ["ms", "s"] else Kind.LENGTH
			return result
	if normalized.is_valid_float():
		result.kind = Kind.NUMBER
		result.number = normalized.to_float()
		return result
	if _is_keyword(normalized):
		result.kind = Kind.KEYWORD
		result.text = normalized.to_lower()
	return result


func milliseconds() -> float:
	if kind != Kind.TIME:
		return NAN
	return number if unit == "ms" else number * 1000.0


func is_valid() -> bool:
	return kind != Kind.INVALID


static func _is_keyword(value: String) -> bool:
	for character in value:
		var lowered := character.to_lower()
		if not (lowered >= "a" and lowered <= "z") and character not in ["-", "_"]:
			return false
	return true
