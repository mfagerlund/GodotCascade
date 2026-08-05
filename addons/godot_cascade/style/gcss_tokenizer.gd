extends RefCounted

## Recoverable GCSS tokenizer. Every token carries an inclusive start and exclusive end span.

enum Type {
	IDENTIFIER,
	NUMBER,
	DIMENSION,
	HASH,
	STRING,
	COLON,
	SEMICOLON,
	OPEN_BRACE,
	CLOSE_BRACE,
	OPEN_PAREN,
	CLOSE_PAREN,
	DOT,
	COMMA,
	COMBINATOR,
	DELIMITER,
}


static func tokenize(source: String) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var diagnostics: Array[Dictionary] = []
	var cursor := 0
	while cursor < source.length():
		var character := source[cursor]
		if character in [" ", "\t", "\r", "\n"]:
			cursor += 1
			continue
		if character == "/" and cursor + 1 < source.length() and source[cursor + 1] == "*":
			var comment_end := source.find("*/", cursor + 2)
			if comment_end < 0:
				diagnostics.append(_diagnostic(source, cursor, source.length(), "Unclosed stylesheet comment."))
				break
			cursor = comment_end + 2
			continue
		var start := cursor
		if character in ["\"", "'"]:
			var quote := character
			cursor += 1
			while cursor < source.length() and source[cursor] != quote:
				cursor += 2 if source[cursor] == "\\" and cursor + 1 < source.length() else 1
			if cursor >= source.length():
				diagnostics.append(_diagnostic(source, start, source.length(), "Unclosed stylesheet string."))
				tokens.append(_token(Type.STRING, source.substr(start + 1), source, start, source.length()))
				break
			cursor += 1
			tokens.append(_token(Type.STRING, source.substr(start + 1, cursor - start - 2), source, start, cursor))
			continue
		if _starts_number(source, cursor):
			cursor = _consume_number(source, cursor)
			var number_end := cursor
			while cursor < source.length() and (_is_name_character(source[cursor]) or source[cursor] == "%"):
				cursor += 1
			var token_type := Type.DIMENSION if cursor > number_end else Type.NUMBER
			tokens.append(_token(token_type, source.substr(start, cursor - start), source, start, cursor))
			continue
		if character == "#":
			cursor += 1
			while cursor < source.length() and _is_name_character(source[cursor]):
				cursor += 1
			tokens.append(_token(Type.HASH, source.substr(start, cursor - start), source, start, cursor))
			continue
		if _is_name_start(character):
			cursor += 1
			while cursor < source.length() and _is_name_character(source[cursor]):
				cursor += 1
			tokens.append(_token(Type.IDENTIFIER, source.substr(start, cursor - start), source, start, cursor))
			continue
		var punctuation := {
			":": Type.COLON, ";": Type.SEMICOLON, "{": Type.OPEN_BRACE, "}": Type.CLOSE_BRACE,
			"(": Type.OPEN_PAREN, ")": Type.CLOSE_PAREN, ".": Type.DOT, ",": Type.COMMA,
			">": Type.COMBINATOR,
		}
		if punctuation.has(character):
			cursor += 1
			tokens.append(_token(punctuation[character], character, source, start, cursor))
			continue
		cursor += 1
		tokens.append(_token(Type.DELIMITER, character, source, start, cursor))
		if character not in ["/", "*", "+", "-", "@"]:
			diagnostics.append(_diagnostic(source, start, cursor, "Unexpected character '%s'; tokenizer recovered at the next token." % character))
	return {"tokens": tokens, "diagnostics": diagnostics}


static func _starts_number(source: String, cursor: int) -> bool:
	var character := source[cursor]
	if character >= "0" and character <= "9":
		return true
	if character in ["+", "-"] and cursor + 1 < source.length():
		return source[cursor + 1] >= "0" and source[cursor + 1] <= "9"
	if character == "." and cursor + 1 < source.length():
		return source[cursor + 1] >= "0" and source[cursor + 1] <= "9"
	return false


static func _consume_number(source: String, cursor: int) -> int:
	if source[cursor] in ["+", "-"]:
		cursor += 1
	while cursor < source.length() and source[cursor] >= "0" and source[cursor] <= "9":
		cursor += 1
	if cursor < source.length() and source[cursor] == ".":
		cursor += 1
		while cursor < source.length() and source[cursor] >= "0" and source[cursor] <= "9":
			cursor += 1
	return cursor


static func _is_name_start(character: String) -> bool:
	return character == "_" or character == "-" or (character.to_lower() >= "a" and character.to_lower() <= "z")


static func _is_name_character(character: String) -> bool:
	return _is_name_start(character) or (character >= "0" and character <= "9")


static func _token(type: Type, value: String, source: String, start: int, end: int) -> Dictionary:
	var start_location := _location(source, start)
	var end_location := _location(source, end)
	return {
		"type": type,
		"value": value,
		"start": start,
		"end": end,
		"line": start_location.x,
		"column": start_location.y,
		"end_line": end_location.x,
		"end_column": end_location.y,
	}


static func _diagnostic(source: String, start: int, end: int, message: String) -> Dictionary:
	var location := _location(source, start)
	return {"severity": "error", "line": location.x, "column": location.y, "start": start, "end": end, "message": message}


static func _location(source: String, offset: int) -> Vector2i:
	var prefix := source.substr(0, clampi(offset, 0, source.length()))
	var last_newline := prefix.rfind("\n")
	return Vector2i(prefix.count("\n") + 1, offset + 1 if last_newline < 0 else offset - last_newline)
