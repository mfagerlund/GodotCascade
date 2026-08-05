extends SceneTree

const GENERATED_SCENE := preload("res://examples/generated_showcase.tscn")
const SYSTEM_STATUS_SCENE := preload("res://examples/system_status_showcase.tscn")
const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_gxml_parser()
	_test_gcss_specificity()
	_test_parser_recovery()
	_test_binding_resolver()
	_test_identity_preserving_reload()
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

	var system_document := SYSTEM_STATUS_SCENE.instantiate()
	root.add_child(system_document)
	await process_frame
	await process_frame
	await process_frame
	_expect_true("system status document has no errors", not _has_error_diagnostics(system_document.diagnostics))
	var system_root: Control = system_document.generated_root()
	var reserve_controls := _find_by_id(system_root, "reserve")
	_expect_int("one generated reserve progress", reserve_controls.size(), 1)
	if reserve_controls.size() == 1:
		var reserve: Control = reserve_controls[0]
		var reserve_instance_id := reserve.get_instance_id()
		_expect_float("progress markup value", reserve.get("value"), 72.0)
		_expect_float("progress markup maximum", reserve.get("max_value"), 100.0)
		_expect_float("progress normalized ratio", reserve.call("ratio"), 0.72)
		_expect_true("progress GCSS fill color", reserve.get("fill_color") == Color("5aa7ff"))
		var telemetry: Dictionary = system_document.binding_context["telemetry"]
		telemetry["reserve"] = 41.0
		telemetry["reserve_label"] = "41%"
		_expect_true("manual binding refresh succeeds", system_document.refresh_bindings())
		_expect_float("binding refresh updates progress", reserve.get("value"), 41.0)
		_expect_true("binding refresh preserves progress identity", reserve.get_instance_id() == reserve_instance_id)
		var reserve_labels := _find_by_id(system_root, "reserve-value")
		_expect_int("one bound reserve label", reserve_labels.size(), 1)
		if reserve_labels.size() == 1:
			_expect_true("binding refresh updates text", reserve_labels[0].get("text") == "41%")
	var system_progress := _find_by_class(system_root, "system-progress")
	_expect_int("three generated system progress controls", system_progress.size(), 3)
	if system_progress.size() == 3:
		_expect_true("descendant progress fill purple", system_progress[0].get("fill_color") == Color("b18cff"))
		_expect_true("descendant progress fill green", system_progress[1].get("fill_color") == Color("65d6a7"))
		_expect_true("descendant progress fill orange", system_progress[2].get("fill_color") == Color("ffb665"))

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


func _test_binding_resolver() -> void:
	var context := {"player": {"name": "Rhea", "inventory": ["key", "map"]}}
	var name_result := BindingResolver.resolve(context, "player.name")
	_expect_true("binding resolves dictionary path", name_result["found"] and name_result["value"] == "Rhea")
	var array_result := BindingResolver.resolve(context, "player.inventory.1")
	_expect_true("binding resolves array index", array_result["found"] and array_result["value"] == "map")
	var missing_result := BindingResolver.resolve(context, "player.health")
	_expect_true("missing binding path reports failure", not missing_result["found"])


func _test_identity_preserving_reload() -> void:
	var markup_path := "user://cascade_reload_test.gxml"
	var stylesheet_path := "user://cascade_reload_test.gcss"
	var initial_markup := "<Page><Button id=\"stable\">Before</Button></Page>"
	var updated_markup := "<Page><Button id=\"stable\">After</Button></Page>"
	var stylesheet := "Page { display: flex; flex-direction: column; } Button { padding: 8px; }"
	_expect_true("write initial reload markup", _write_text(markup_path, initial_markup))
	_expect_true("write initial reload stylesheet", _write_text(stylesheet_path, stylesheet))

	var document: Control = CascadeDocument.new()
	document.load_on_ready = false
	document.log_diagnostics_to_console = false
	document.watch_sources = false
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect_true("initial document reload succeeds", document.reload_document())

	var initial_button: Control = _find_by_id(document.generated_root(), "stable")[0]
	var initial_instance_id := initial_button.get_instance_id()
	initial_button.pressed.connect(_on_reload_test_pressed)

	_expect_true("write updated reload markup", _write_text(markup_path, updated_markup))
	_expect_true("source polling detects edit", document.poll_sources())
	var updated_button: Control = _find_by_id(document.generated_root(), "stable")[0]
	_expect_true("reload preserves native node identity", updated_button.get_instance_id() == initial_instance_id)
	_expect_true("reload updates component properties", updated_button.get("text") == "After")
	_expect_true("reload preserves signal connections", updated_button.pressed.is_connected(_on_reload_test_pressed))
	_expect_true("reload reports reused nodes", int(document.last_reconcile_stats["reused"]) >= 2)

	_expect_true("write malformed reload markup", _write_text(markup_path, "<Page><Button>broken</Page>"))
	_expect_true("source polling detects malformed edit", document.poll_sources())
	var retained_button: Control = _find_by_id(document.generated_root(), "stable")[0]
	_expect_true("invalid edit retains native node identity", retained_button.get_instance_id() == initial_instance_id)
	_expect_true("invalid edit retains last valid properties", retained_button.get("text") == "After")
	_expect_true("invalid edit publishes diagnostics", _has_error_diagnostics(document.diagnostics))

	root.remove_child(document)
	document.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _on_reload_test_pressed() -> void:
	pass


func _write_text(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	return true


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
