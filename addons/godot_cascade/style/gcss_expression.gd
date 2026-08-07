extends RefCounted

## Focused variable substitution and typed arithmetic for GCSS values.
## This is intentionally smaller and more deterministic than browser CSS Values.

const MAX_VARIABLE_DEPTH := 64


static func resolve_variables(source: String, custom_properties: Dictionary) -> Dictionary:
	return _resolve_variables(source, custom_properties, PackedStringArray(), 0)


static func evaluate(source: String, viewport_size: Vector2) -> Dictionary:
	var normalized := source.strip_edges()
	if not normalized.to_lower().begins_with("calc(") or not normalized.ends_with(")"):
		return {"ok": false, "error": "Expected a complete calc(...) expression."}
	var parser := _TypedCalcParser.new(normalized.substr(5, normalized.length() - 6), viewport_size)
	return parser.parse()


static func _resolve_variables(source: String, custom_properties: Dictionary, stack: PackedStringArray, depth: int) -> Dictionary:
	if depth > MAX_VARIABLE_DEPTH:
		return {"ok": false, "error": "Custom-property expansion exceeded %s levels." % MAX_VARIABLE_DEPTH}
	var output := ""
	var cursor := 0
	while cursor < source.length():
		var start := _find_var_call(source, cursor)
		if start < 0:
			output += source.substr(cursor)
			break
		output += source.substr(cursor, start - cursor)
		var open_paren := source.find("(", start)
		var close_paren := _matching_paren(source, open_paren)
		if close_paren < 0:
			return {"ok": false, "error": "Unclosed var(...) expression."}
		var arguments := source.substr(open_paren + 1, close_paren - open_paren - 1)
		var comma := _top_level_comma(arguments)
		var property_name := (arguments if comma < 0 else arguments.substr(0, comma)).strip_edges()
		var fallback := "" if comma < 0 else arguments.substr(comma + 1).strip_edges()
		if not _valid_custom_property_name(property_name):
			return {"ok": false, "error": "var() requires a custom-property name beginning with '--'."}
		var resolved := {}
		if property_name in stack:
			resolved = {"ok": false, "error": "Circular custom-property reference involving '%s'." % property_name}
		elif custom_properties.has(property_name):
			var next_stack := stack.duplicate()
			next_stack.append(property_name)
			resolved = _resolve_variables(str(custom_properties[property_name]), custom_properties, next_stack, depth + 1)
		else:
			resolved = {"ok": false, "error": "Custom property '%s' is not defined." % property_name}
		if not bool(resolved.get("ok", false)) and not fallback.is_empty():
			resolved = _resolve_variables(fallback, custom_properties, stack, depth + 1)
		if not bool(resolved.get("ok", false)):
			return resolved
		output += str(resolved["value"])
		cursor = close_paren + 1
	return {"ok": true, "value": output}


static func _find_var_call(source: String, from: int) -> int:
	var cursor := from
	var quote := ""
	while cursor < source.length():
		var character := source[cursor]
		if not quote.is_empty():
			if character == quote and (cursor == 0 or source[cursor - 1] != "\\"):
				quote = ""
			cursor += 1
			continue
		if character in ["\"", "'"]:
			quote = character
			cursor += 1
			continue
		if cursor + 3 <= source.length() and source.substr(cursor, 3).to_lower() == "var":
			var before_ok := cursor == 0 or not _is_name_character(source[cursor - 1])
			var after := cursor + 3
			while after < source.length() and source[after] in [" ", "\t", "\r", "\n"]:
				after += 1
			if before_ok and after < source.length() and source[after] == "(":
				return cursor
		cursor += 1
	return -1


static func _matching_paren(source: String, open_paren: int) -> int:
	var depth := 0
	var quote := ""
	for cursor in range(open_paren, source.length()):
		var character := source[cursor]
		if not quote.is_empty():
			if character == quote and (cursor == 0 or source[cursor - 1] != "\\"):
				quote = ""
			continue
		if character in ["\"", "'"]:
			quote = character
		elif character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
			if depth == 0:
				return cursor
	return -1


static func _top_level_comma(source: String) -> int:
	var depth := 0
	var quote := ""
	for cursor in source.length():
		var character := source[cursor]
		if not quote.is_empty():
			if character == quote and (cursor == 0 or source[cursor - 1] != "\\"):
				quote = ""
			continue
		if character in ["\"", "'"]:
			quote = character
		elif character == "(":
			depth += 1
		elif character == ")":
			depth = maxi(depth - 1, 0)
		elif character == "," and depth == 0:
			return cursor
	return -1


static func _valid_custom_property_name(value: String) -> bool:
	if not value.begins_with("--") or value.length() < 3:
		return false
	for cursor in range(2, value.length()):
		if not _is_name_character(value[cursor]):
			return false
	return true


static func _is_name_character(character: String) -> bool:
	var lowered := character.to_lower()
	return character in ["-", "_"] or (lowered >= "a" and lowered <= "z") or (character >= "0" and character <= "9")


class _TypedCalcParser:
	extends RefCounted

	var _source := ""
	var _cursor := 0
	var _viewport_size := Vector2.ZERO
	var _error := ""


	func _init(source: String, viewport_size: Vector2) -> void:
		_source = source
		_viewport_size = viewport_size


	func parse() -> Dictionary:
		var result := _parse_sum()
		_skip_whitespace()
		if _error.is_empty() and _cursor < _source.length():
			_error = "Unexpected token '%s'." % _source[_cursor]
		if not _error.is_empty():
			return {"ok": false, "error": _error}
		if not is_finite(float(result.get("value", NAN))):
			return {"ok": false, "error": "Arithmetic produced a non-finite value."}
		result["ok"] = true
		return result


	func _parse_sum() -> Dictionary:
		var left := _parse_product()
		while _error.is_empty():
			_skip_whitespace()
			var operation := _peek()
			if operation not in ["+", "-"]:
				break
			_cursor += 1
			var right := _parse_product()
			if str(left.get("kind", "")) != str(right.get("kind", "")):
				_error = "Addition and subtraction require matching value types."
				return {}
			left["value"] = float(left["value"]) + float(right["value"]) * (1.0 if operation == "+" else -1.0)
		return left


	func _parse_product() -> Dictionary:
		var left := _parse_unary()
		while _error.is_empty():
			_skip_whitespace()
			var operation := _peek()
			if operation not in ["*", "/"]:
				break
			_cursor += 1
			var right := _parse_unary()
			var left_kind := str(left.get("kind", ""))
			var right_kind := str(right.get("kind", ""))
			if operation == "*":
				if left_kind == "number":
					left = {"kind": right_kind, "value": float(left["value"]) * float(right["value"])}
				elif right_kind == "number":
					left["value"] = float(left["value"]) * float(right["value"])
				else:
					_error = "Multiplication requires at least one unitless number."
			else:
				if right_kind != "number":
					_error = "Division requires a unitless divisor."
				elif is_zero_approx(float(right["value"])):
					_error = "Division by zero is not allowed."
				else:
					left["value"] = float(left["value"]) / float(right["value"])
		return left


	func _parse_unary() -> Dictionary:
		_skip_whitespace()
		var sign := 1.0
		while _peek() in ["+", "-"]:
			if _peek() == "-":
				sign *= -1.0
			_cursor += 1
			_skip_whitespace()
		var value := _parse_primary()
		if value.has("value"):
			value["value"] = float(value["value"]) * sign
		return value


	func _parse_primary() -> Dictionary:
		_skip_whitespace()
		if _peek() == "(":
			_cursor += 1
			var nested := _parse_sum()
			_skip_whitespace()
			if _peek() != ")":
				_error = "Expected ')'."
				return {}
			_cursor += 1
			return nested
		return _parse_literal()


	func _parse_literal() -> Dictionary:
		_skip_whitespace()
		var start := _cursor
		var saw_digit := false
		while _cursor < _source.length() and _source[_cursor] >= "0" and _source[_cursor] <= "9":
			saw_digit = true
			_cursor += 1
		if _cursor < _source.length() and _source[_cursor] == ".":
			_cursor += 1
			while _cursor < _source.length() and _source[_cursor] >= "0" and _source[_cursor] <= "9":
				saw_digit = true
				_cursor += 1
		if not saw_digit:
			_error = "Expected a number."
			return {}
		var magnitude := _source.substr(start, _cursor - start).to_float()
		var unit_start := _cursor
		while _cursor < _source.length() and _source[_cursor].to_lower() >= "a" and _source[_cursor].to_lower() <= "z":
			_cursor += 1
		if _cursor < _source.length() and _source[_cursor] == "%":
			_cursor += 1
		var unit := _source.substr(unit_start, _cursor - unit_start).to_lower()
		match unit:
			"":
				return {"kind": "number", "value": magnitude}
			"px":
				return {"kind": "length", "value": magnitude}
			"vw", "vh":
				var reference := _viewport_size.x if unit == "vw" else _viewport_size.y
				if reference <= 0.0:
					_error = "Viewport units require a positive viewport size."
					return {}
				return {"kind": "length", "value": magnitude * reference / 100.0}
			"ms":
				return {"kind": "time", "value": magnitude}
			"s":
				return {"kind": "time", "value": magnitude * 1000.0}
			_:
				_error = "Unsupported unit '%s'." % unit
				return {}


	func _skip_whitespace() -> void:
		while _cursor < _source.length() and _source[_cursor] in [" ", "\t", "\r", "\n"]:
			_cursor += 1


	func _peek() -> String:
		return _source[_cursor] if _cursor < _source.length() else ""
