extends SceneTree

const GENERATED_SCENE := preload("res://examples/generated_showcase.tscn")
const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_gxml_parser()
	_test_gcss_specificity()
	_test_parser_recovery()
	root.size = Vector2i(960, 540)
	var document := GENERATED_SCENE.instantiate()
	root.add_child(document)
	await process_frame
	await process_frame
	await process_frame

	_expect_true("source document has no errors", not _has_error_diagnostics(document.diagnostics))
	var generated_root: Control = document.generated_root()
	_expect_true("source document generated a root", generated_root != null)
	if generated_root != null:
		var card_rows := _find_by_class(generated_root, "cards")
		_expect_int("one cards row", card_rows.size(), 1)
		if card_rows.size() == 1:
			var cards_row: Control = card_rows[0]
			_expect_int("cards row direction", int(cards_row.get("direction")), 0)
			_expect_true("cards row wraps", bool(cards_row.get("wrap")))

		var cards := _find_by_class(generated_root, "card")
		_expect_int("three generated cards", cards.size(), 3)
		if cards.size() == 3:
			for index in cards.size():
				var style: CascadeStyle = cards[index].get("cascade_style")
				_expect_float("card %s preferred width" % index, style.preferred_width, 250.0)
			_expect_float("cards share first row y (second)", cards[1].position.y, cards[0].position.y)
			_expect_float("cards share first row y (third)", cards[2].position.y, cards[0].position.y)

		var inspect_buttons := _find_by_id(generated_root, "inspect")
		_expect_int("one generated inspect button", inspect_buttons.size(), 1)
		if inspect_buttons.size() == 1:
			var inspect_button: Control = inspect_buttons[0]
			_expect_true("hover pseudo style", inspect_button.get("hover_background_color") == Color("475467"))
			_expect_true("pressed pseudo style", inspect_button.get("pressed_background_color") == Color("1d2939"))
			_expect_true("focused pseudo style", inspect_button.get("focus_ring_color") == Color("84adff"))

		var card_titles := _find_by_class(generated_root, "card-title")
		_expect_int("three generated card titles", card_titles.size(), 3)
		if card_titles.size() == 3:
			_expect_true("descendant selector blue title", card_titles[0].get("text_color") == Color("7dbfff"))
			_expect_true("descendant selector green title", card_titles[1].get("text_color") == Color("a8e08c"))
			_expect_true("descendant selector orange title", card_titles[2].get("text_color") == Color("ffb064"))

	var warnings := 0
	for diagnostic in document.diagnostics:
		if diagnostic.get("severity") == "warning":
			warnings += 1
	_expect_int("showcase stylesheet warnings", warnings, 0)

	if _failures.is_empty():
		print("GodotCascade source pipeline tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_gxml_parser() -> void:
	var result := GxmlParser.parse("<Page class=\"shell\">\n  <Label id=\"title\"> Hello\nworld </Label>\n</Page>")
	_expect_int("valid GXML diagnostics", result["diagnostics"].size(), 0)
	_expect_true("GXML root exists", result["root"] != null)
	if result["root"] != null:
		_expect_int("GXML child count", result["root"].children.size(), 1)
		_expect_true("GXML text normalization", result["root"].children[0].text == "Hello world")


func _test_gcss_specificity() -> void:
	var markup := GxmlParser.parse("<Page><Label id=\"hero\" class=\"title\">Hello</Label></Page>")
	var stylesheet := GcssParser.parse("Label { color: #111111; } .title { color: #22aa22; } #hero { color: #3366ff; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("specificity stylesheet diagnostics", stylesheet["diagnostics"].size(), 0)
	_expect_int("specificity builder diagnostics", build["diagnostics"].size(), 0)
	var built_root: Control = build["root"]
	if built_root != null and built_root.get_child_count() == 1:
		var label: Control = built_root.get_child(0)
		_expect_true("ID selector wins specificity", label.get("text_color") == Color("3366ff"))
	if built_root != null:
		built_root.free()


func _test_parser_recovery() -> void:
	var malformed_markup := GxmlParser.parse("<Page><Label>broken</Page>")
	_expect_true("malformed GXML reports diagnostics", not malformed_markup["diagnostics"].is_empty())
	var malformed_style := GcssParser.parse(".card { color: ; broken }")
	_expect_true("malformed GCSS reports diagnostics", not malformed_style["diagnostics"].is_empty())


func _find_by_class(node: Node, class_value: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and node.has_meta("cascade_classes"):
		var classes: PackedStringArray = node.get_meta("cascade_classes")
		if classes.has(class_value):
			matches.append(node)
	for child in node.get_children():
		matches.append_array(_find_by_class(child, class_value))
	return matches


func _find_by_id(node: Node, id_value: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and node.get_meta("cascade_id", "") == id_value:
		matches.append(node)
	for child in node.get_children():
		matches.append_array(_find_by_id(child, id_value))
	return matches


func _has_error_diagnostics(diagnostics: Array[Dictionary]) -> bool:
	for diagnostic in diagnostics:
		if diagnostic.get("severity", "error") == "error":
			return true
	return false


func _expect_true(label: String, actual: bool) -> void:
	if not actual:
		_failures.append("%s: expected true" % label)


func _expect_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_float(label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])
