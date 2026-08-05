extends SceneTree

const GENERATED_SCENE := preload("res://examples/generated_showcase.tscn")
const SYSTEM_STATUS_SCENE := preload("res://examples/system_status_showcase.tscn")
const SETTINGS_MENU_SCENE := preload("res://examples/settings_menu_showcase.tscn")
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
	_test_form_controls_pipeline()
	_test_select_pipeline()
	_test_slider_pipeline()
	_test_image_pipeline()
	_test_stack_pipeline()
	_test_grid_pipeline()
	_test_review_regressions()
	_test_parser_recovery()
	_test_binding_resolver()
	await _test_identity_preserving_reload()
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
		var card_grids := _find_by_class(generated_root, "cards")
		_expect_int("one cards grid", card_grids.size(), 1)
		if card_grids.size() == 1:
			var cards_grid: Control = card_grids[0]
			_expect_int("cards grid column count", cards_grid.get("column_tracks").size(), 3)
			_expect_float("cards grid column gap", cards_grid.get("column_gap"), 18.0)

		var cards := _find_by_class(generated_root, "card")
		_expect_int("three generated cards", cards.size(), 3)
		if cards.size() == 3:
			for index in cards.size():
				var style: CascadeStyle = cards[index].get("cascade_style")
				_expect_float("card %s minimum height" % index, style.min_height, 210.0)
			_expect_float("cards share first row y (second)", cards[1].position.y, cards[0].position.y)
			_expect_float("cards share first row y (third)", cards[2].position.y, cards[0].position.y)
			_expect_float("fractional cards share width (second)", cards[1].size.x, cards[0].size.x)
			_expect_float("fractional cards share width (third)", cards[2].size.x, cards[0].size.x)

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

	var settings_document := SETTINGS_MENU_SCENE.instantiate()
	root.add_child(settings_document)
	await process_frame
	await process_frame
	await process_frame
	_expect_true("settings menu document has no errors", not _has_error_diagnostics(settings_document.diagnostics))
	var settings_root: Control = settings_document.generated_root()
	var shadows_controls := _find_by_id(settings_root, "shadows")
	var borderless_controls := _find_by_id(settings_root, "borderless")
	var fullscreen_controls := _find_by_id(settings_root, "fullscreen")
	_expect_int("settings menu has shadows checkbox", shadows_controls.size(), 1)
	_expect_int("settings menu has selected radio", borderless_controls.size(), 1)
	if shadows_controls.size() == 1:
		_expect_true("settings menu checkbox starts checked", shadows_controls[0].get("button_pressed"))
	if borderless_controls.size() == 1 and fullscreen_controls.size() == 1:
		_expect_true("settings menu radio starts checked", borderless_controls[0].get("button_pressed"))
		fullscreen_controls[0].set("button_pressed", true)
		_expect_true("settings menu radio group is exclusive", not borderless_controls[0].get("button_pressed"))

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


func _test_form_controls_pipeline() -> void:
	var markup := GxmlParser.parse("""<Page>
		<Checkbox id="shadows" checked="true" accessible-label="Enable shadows">Shadows</Checkbox>
		<Checkbox id="locked" disabled="true">Locked</Checkbox>
		<Switch id="vsync" checked="true">Vertical sync</Switch>
		<RadioButton id="windowed" group="display" checked="true">Windowed</RadioButton>
		<RadioButton id="fullscreen" group="display">Fullscreen</RadioButton>
	</Page>""")
	var stylesheet := GcssParser.parse("""Checkbox:checked { background: #123456; color: #abcdef; }
		Checkbox:disabled { background: #222222; color: #777777; }
		RadioButton:hover { background: #333333; }
		RadioButton:focused { border-color: #88aaff; border-width: 3px; }""")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("form-control markup diagnostics", markup["diagnostics"].size(), 0)
	_expect_int("form-control stylesheet diagnostics", stylesheet["diagnostics"].size(), 0)
	_expect_int("form-control builder diagnostics", build["diagnostics"].size(), 0)
	var built_root: Control = build["root"]
	if built_root == null:
		return
	var shadows: BaseButton = _find_by_id(built_root, "shadows")[0]
	var locked: BaseButton = _find_by_id(built_root, "locked")[0]
	var vsync: BaseButton = _find_by_id(built_root, "vsync")[0]
	var windowed: BaseButton = _find_by_id(built_root, "windowed")[0]
	var fullscreen: BaseButton = _find_by_id(built_root, "fullscreen")[0]
	_expect_true("checked attribute reaches native toggle state", shadows.button_pressed)
	_expect_true("disabled attribute reaches native state", locked.disabled)
	_expect_true("switch element keeps toggle semantics", vsync.toggle_mode and vsync.button_pressed)
	_expect_true("accessible label reaches native metadata", shadows.accessibility_name == "Enable shadows")
	_expect_true("checked pseudo background applies", shadows.get("checked_background_color") == Color("123456"))
	_expect_true("checked pseudo text applies", shadows.get("checked_text_color") == Color("abcdef"))
	_expect_true("disabled pseudo background applies", locked.get("disabled_background_color") == Color("222222"))
	_expect_true("radio group shares native ButtonGroup", windowed.button_group == fullscreen.button_group)
	_expect_true("radio checked attribute selects native group member", windowed.button_pressed)
	_expect_true("generalized hover style applies to radio", fullscreen.get("hover_background_color") == Color("333333"))
	_expect_float("generalized focus width applies to radio", fullscreen.get("focus_ring_width"), 3.0)
	fullscreen.button_pressed = true
	_expect_true("native radio selection unchecks peer", not windowed.button_pressed)
	built_root.free()


func _test_select_pipeline() -> void:
	var markup := GxmlParser.parse("""<Page><Select id="quality" selected="high" accessible-label="Graphics quality">
		<Option value="low">Low</Option>
		<Option value="medium" disabled="true">Medium</Option>
		<Option value="high">High</Option>
	</Select></Page>""")
	var stylesheet := GcssParser.parse("""Select:open { background: #234567; }
		Option { background: #101828; color: #dddddd; }
		Option:hover { background: #222222; }
		Option:selected { background: #345678; color: #ffffff; }
		Option:disabled { color: #777777; }""")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("select markup diagnostics", markup["diagnostics"].size(), 0)
	_expect_int("select stylesheet diagnostics", stylesheet["diagnostics"].size(), 0)
	_expect_int("select builder diagnostics", build["diagnostics"].size(), 0)
	var built_root: Control = build["root"]
	if built_root == null:
		return
	var select: Control = _find_by_id(built_root, "quality")[0]
	_expect_true("select GXML selected value", select.call("selected_value") == "high")
	_expect_true("select GXML accessibility label", select.get("accessibility_name") == "Graphics quality")
	_expect_true("select open pseudo style", select.get("open_background_color") == Color("234567"))
	var options: Array[Dictionary] = select.get("options")
	_expect_int("select GXML option count", options.size(), 3)
	_expect_true("select disabled option metadata", options[1]["disabled"])
	_expect_true("selected option background style", options[2]["selected_background_color"] == Color("345678"))
	built_root.free()


func _test_slider_pipeline() -> void:
	var markup := GxmlParser.parse("<Slider id=\"volume\" min=\"0\" max=\"10\" value=\"4\" step=\"0.5\" accessible-label=\"Master volume\" />")
	var stylesheet := GcssParser.parse("Slider { width: 220px; fill-color: #55aaff; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("slider builder diagnostics", build["diagnostics"].size(), 0)
	var slider: Control = build["root"]
	if slider == null:
		return
	_expect_float("slider markup minimum", slider.get("min_value"), 0.0)
	_expect_float("slider markup maximum", slider.get("max_value"), 10.0)
	_expect_float("slider markup value", slider.get("value"), 4.0)
	_expect_float("slider markup step", slider.get("step"), 0.5)
	_expect_true("slider GCSS fill", slider.get("fill_color") == Color("55aaff"))
	_expect_true("slider accessibility name", slider.get("accessibility_name") == "Master volume")
	slider.free()


func _test_stack_pipeline() -> void:
	var markup := GxmlParser.parse("<Stack><Panel id=\"back\"/><Button id=\"badge\">New</Button></Stack>")
	var stylesheet := GcssParser.parse("Stack { width: 200px; height: 100px; padding: 10px; } #badge { position: absolute; right: 5px; top: 7px; width: 50px; height: 24px; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("stack builder diagnostics", build["diagnostics"].size(), 0)
	var built_root: Control = build["root"]
	if built_root != null:
		var badge: Control = _find_by_id(built_root, "badge")[0]
		_expect_true("absolute position metadata", badge.get_meta("cascade_position") == "absolute")
		_expect_float("absolute right metadata", badge.get_meta("cascade_right"), 5.0)
		built_root.free()


func _test_grid_pipeline() -> void:
	var markup := GxmlParser.parse("<Grid><Panel id=\"first\"/><Panel id=\"featured\"/><Panel id=\"auto\"/></Grid>")
	var stylesheet := GcssParser.parse("Grid { width: 320px; height: 180px; grid-template-columns: 80px 1fr 2fr; grid-template-rows: minmax(40px, 1fr) auto; gap: 8px 12px; } #featured { grid-column: 2 / span 2; grid-row: 1; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("grid builder diagnostics", build["diagnostics"].size(), 0)
	var grid: Control = build["root"]
	if grid != null:
		_expect_int("grid column track count", grid.get("column_tracks").size(), 3)
		_expect_int("grid row track count", grid.get("row_tracks").size(), 2)
		_expect_float("grid column gap", grid.get("column_gap"), 12.0)
		_expect_float("grid row gap", grid.get("row_gap"), 8.0)
		var featured: Control = _find_by_id(grid, "featured")[0]
		_expect_int("grid authored column", int(featured.get_meta("cascade_grid_column")), 1)
		_expect_int("grid authored column span", int(featured.get_meta("cascade_grid_column_span")), 2)
		grid.free()


func _test_image_pipeline() -> void:
	var markup := GxmlParser.parse("<Image src=\"res://docs/showcase/assets/layout-foundation-godot.png\" accessible-label=\"Layout preview\"/>")
	var stylesheet := GcssParser.parse("Image { width: 160px; height: 90px; object-fit: cover; border-radius: 8px; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("image builder diagnostics", build["diagnostics"].size(), 0)
	var image: Control = build["root"]
	if image != null:
		_expect_true("image resource loads as texture", image.get("texture") is Texture2D)
		_expect_int("image cover fit is authored", int(image.get("fit")), 1)
		_expect_true("image accessibility label is retained", image.get("accessibility_name") == "Layout preview")
		_expect_true("image is marked exact", image.get_meta("cascade_compatibility_tier") == "exact")
		image.free()

	var missing_markup := GxmlParser.parse("<Image src=\"res://missing-texture.png\"/>")
	var missing_build := CascadeBuilder.build(missing_markup["root"], [])
	_expect_true("missing image resource is an error", _has_error_diagnostics(missing_build["diagnostics"]))
	if missing_build["root"] != null:
		missing_build["root"].free()


func _test_review_regressions() -> void:
	var magenta_markup := GxmlParser.parse("<Label id=\"color\">Magenta</Label>")
	var magenta_stylesheet := GcssParser.parse("#color { color: #f0f; }")
	var magenta_build := CascadeBuilder.build(magenta_markup["root"], magenta_stylesheet["rules"])
	_expect_int("shorthand magenta builder diagnostics", magenta_build["diagnostics"].size(), 0)
	if magenta_build["root"] != null:
		_expect_true("shorthand magenta color parses", magenta_build["root"].get("text_color") == Color("f0f"))
		magenta_build["root"].free()

	var panel_markup := GxmlParser.parse("<Panel />")
	var panel_stylesheet := GcssParser.parse("Panel { color: #ffffff; }")
	var panel_build := CascadeBuilder.build(panel_markup["root"], panel_stylesheet["rules"])
	_expect_int("not-applicable property emits one diagnostic", panel_build["diagnostics"].size(), 1)
	if panel_build["diagnostics"].size() == 1:
		_expect_true("not-applicable property is warning", panel_build["diagnostics"][0]["severity"] == "warning")
		_expect_true("not-applicable diagnostic names target", str(panel_build["diagnostics"][0]["message"]).contains("<Panel>"))
	if panel_build["root"] != null:
		panel_build["root"].free()

	var whitespace_markup := GxmlParser.parse("<Label class=\"alpha&#x9;beta\">Words</Label>")
	var whitespace_stylesheet := GcssParser.parse(".beta { padding: 3px\t7px; }")
	var whitespace_build := CascadeBuilder.build(whitespace_markup["root"], whitespace_stylesheet["rules"])
	_expect_int("whitespace-normalized builder diagnostics", whitespace_build["diagnostics"].size(), 0)
	if whitespace_build["root"] != null:
		var whitespace_style: CascadeStyle = whitespace_build["root"].get("cascade_style")
		_expect_float("tab-separated padding horizontal", whitespace_style.padding_left, 7.0)
		_expect_float("tab-separated padding vertical", whitespace_style.padding_top, 3.0)
		whitespace_build["root"].free()

	var negative_stylesheet := GcssParser.parse("Label { margin-left: -8px; }")
	var negative_build := CascadeBuilder.build(magenta_markup["root"], negative_stylesheet["rules"])
	_expect_true("negative length is diagnosed as an error", _has_error_diagnostics(negative_build["diagnostics"]))
	if negative_build["root"] != null:
		negative_build["root"].free()

	for source in [
		"#card { padding: 20px; } .card { padding-left: 4px; }",
		".card { padding-left: 4px; } #card { padding: 20px; }",
	]:
		var cascade_markup := GxmlParser.parse("<Panel id=\"card\" class=\"card\" />")
		var cascade_stylesheet := GcssParser.parse(source)
		var cascade_build := CascadeBuilder.build(cascade_markup["root"], cascade_stylesheet["rules"])
		_expect_int("shorthand cascade builder diagnostics", cascade_build["diagnostics"].size(), 0)
		if cascade_build["root"] != null:
			var cascade_style: CascadeStyle = cascade_build["root"].get("cascade_style")
			_expect_float("shorthand honors specificity in either source order", cascade_style.padding_left, 20.0)
			cascade_build["root"].free()

	var located_stylesheet := GcssParser.parse("Label {\n  font-size: 18px;\n  color: definitely-not-a-color;\n}")
	var located_build := CascadeBuilder.build(magenta_markup["root"], located_stylesheet["rules"])
	_expect_int("located builder diagnostic count", located_build["diagnostics"].size(), 1)
	if located_build["diagnostics"].size() == 1:
		_expect_int("builder diagnostic declaration line", int(located_build["diagnostics"][0]["line"]), 3)
		_expect_int("builder diagnostic declaration column", int(located_build["diagnostics"][0]["column"]), 3)
	if located_build["root"] != null:
		located_build["root"].free()

	var recovered_pseudo := GcssParser.parse("Label:focus { color: #123456; }")
	_expect_int("unsupported pseudo emits one diagnostic", recovered_pseudo["diagnostics"].size(), 1)
	_expect_true("unsupported pseudo is recoverable warning", recovered_pseudo["diagnostics"][0]["severity"] == "warning")
	var recovered_build := CascadeBuilder.build(magenta_markup["root"], recovered_pseudo["rules"])
	_expect_true("unsupported pseudo retains base declarations", recovered_build["root"].get("text_color") == Color("123456"))
	if recovered_build["root"] != null:
		recovered_build["root"].free()


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
	var initial_markup := "<Page><Button id=\"stable\">Before</Button><Button id=\"move\">Move</Button><Checkbox id=\"runtime\">Runtime</Checkbox></Page>"
	var updated_markup := "<Page><Checkbox id=\"runtime\">Runtime</Checkbox><Button id=\"move\">Move</Button><Button id=\"stable\">After</Button></Page>"
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
	var moved_button: Control = _find_by_id(document.generated_root(), "move")[0]
	var moved_instance_id := moved_button.get_instance_id()
	var runtime_checkbox: BaseButton = _find_by_id(document.generated_root(), "runtime")[0]
	runtime_checkbox.button_pressed = true
	initial_button.pressed.connect(_on_reload_test_pressed)
	initial_button.grab_focus()
	await process_frame
	_expect_true("reload fixture acquires focus", initial_button.has_focus())

	_expect_true("write updated reload markup", _write_text(markup_path, updated_markup))
	_expect_true("source polling detects edit", document.poll_sources())
	var updated_button: Control = _find_by_id(document.generated_root(), "stable")[0]
	_expect_true("reload preserves native node identity", updated_button.get_instance_id() == initial_instance_id)
	_expect_true("reload updates component properties", updated_button.get("text") == "After")
	_expect_true("reload preserves signal connections", updated_button.pressed.is_connected(_on_reload_test_pressed))
	_expect_true("reload preserves focus", updated_button.has_focus())
	_expect_true("reload preserves reordered keyed sibling", _find_by_id(document.generated_root(), "move")[0].get_instance_id() == moved_instance_id)
	_expect_true("reload applies authored sibling order", document.generated_root().get_child(0).get_meta("cascade_id") == "runtime")
	_expect_true("reload preserves runtime toggle state", _find_by_id(document.generated_root(), "runtime")[0].get("button_pressed"))
	_expect_true("reload reports reused nodes", int(document.last_reconcile_stats["reused"]) >= 4)

	var replacement_markup := "<Page><Label id=\"stable\">Replacement</Label><Checkbox id=\"runtime\">Runtime</Checkbox></Page>"
	_expect_true("write replacement reload markup", _write_text(markup_path, replacement_markup))
	_expect_true("replacement source polling detects edit", document.poll_sources())
	_expect_true("incompatible keyed type is replaced", _find_by_id(document.generated_root(), "stable")[0].get_instance_id() != initial_instance_id)
	_expect_int("replacement stats", int(document.last_reconcile_stats["replaced"]), 1)
	_expect_int("removal stats", int(document.last_reconcile_stats["removed"]), 1)
	_expect_true("replacement reload keeps runtime toggle state", _find_by_id(document.generated_root(), "runtime")[0].get("button_pressed"))

	_expect_true("write malformed reload markup", _write_text(markup_path, "<Page><Button>broken</Page>"))
	_expect_true("source polling detects malformed edit", document.poll_sources())
	var retained_control: Control = _find_by_id(document.generated_root(), "stable")[0]
	_expect_true("invalid edit retains native node identity", retained_control.get_meta("cascade_element_type") == "Label")
	_expect_true("invalid edit retains last valid properties", retained_control.get("text") == "Replacement")
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
