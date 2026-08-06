extends SceneTree

const GENERATED_SCENE := preload("res://examples/generated_showcase.tscn")
const SYSTEM_STATUS_SCENE := preload("res://examples/system_status_showcase.tscn")
const SETTINGS_MENU_SCENE := preload("res://examples/settings_menu_showcase.tscn")
const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")
const GcssTokenizer := preload("res://addons/godot_cascade/style/gcss_tokenizer.gd")
const GcssValue := preload("res://addons/godot_cascade/style/gcss_value.gd")
const ComputedStyleCache := preload("res://addons/godot_cascade/style/computed_style_cache.gd")
const ThemeAdapter := preload("res://addons/godot_cascade/style/theme_adapter.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")
const CascadePanel := preload("res://addons/godot_cascade/components/cascade_panel.gd")
const DebugSnapshot := preload("res://addons/godot_cascade/editor/debug_snapshot.gd")

var _failures: Array[String] = []
var _custom_mounts := 0
var _custom_updates := 0
var _custom_unmounts := 0
var _phase3_events := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_gxml_parser()
	_test_gcss_specificity()
	_test_style_foundations()
	_test_responsive_and_transition_styles()
	_test_form_controls_pipeline()
	_test_select_pipeline()
	_test_slider_pipeline()
	_test_text_input_attribute_contract()
	_test_layout_container_state_styles()
	_test_image_pipeline()
	_test_stack_pipeline()
	_test_grid_pipeline()
	_test_review_regressions()
	_test_parser_recovery()
	_test_binding_resolver()
	await _test_writable_binding_pipeline()
	await _test_repeated_writable_binding_pipeline()
	await _test_markup_state_features()
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
		_expect_true("generated root retains GXML source path", generated_root.get_meta("cascade_source_path") == "res://examples/showcase/layout_foundation/interface.gxml")
		_expect_true("generated root retains GXML source line", int(generated_root.get_meta("cascade_source_line")) > 0)
		var debug_snapshot := DebugSnapshot.capture(generated_root)
		_expect_true("layout debugger captures generated hierarchy", debug_snapshot.size() > 5)
		_expect_true("layout debugger includes resolved style", not debug_snapshot[0]["style"].is_empty())
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


func _test_style_foundations() -> void:
	var tokenized := GcssTokenizer.tokenize("Button > .label { transition-duration: 150ms; ?bad: 1; }")
	_expect_true("GCSS tokenizer emits source tokens", tokenized["tokens"].size() > 8)
	_expect_int("GCSS tokenizer recovers after an unexpected character", tokenized["diagnostics"].size(), 1)
	_expect_int("first GCSS token starts on line one", tokenized["tokens"][0]["line"], 1)
	_expect_int("first GCSS token starts in column one", tokenized["tokens"][0]["column"], 1)
	_expect_true("GCSS tokens carry exclusive end spans", tokenized["tokens"][0]["end"] > tokenized["tokens"][0]["start"])

	var milliseconds = GcssValue.parse("150ms")
	var seconds = GcssValue.parse("0.25s")
	var length = GcssValue.parse("12px")
	var color = GcssValue.parse("#4da3ff")
	_expect_int("typed milliseconds value", milliseconds.kind, GcssValue.Kind.TIME)
	_expect_float("milliseconds normalize directly", milliseconds.milliseconds(), 150.0)
	_expect_float("seconds normalize to milliseconds", seconds.milliseconds(), 250.0)
	_expect_int("typed length value", length.kind, GcssValue.Kind.LENGTH)
	_expect_int("typed color value", color.kind, GcssValue.Kind.COLOR)

	var markup := GxmlParser.parse("<Page class=\"theme\"><Label id=\"direct\" class=\"title\">Direct</Label><Panel><Label id=\"nested\">Nested</Label></Panel></Page>")
	var stylesheet := GcssParser.parse("Label { color: #222222; } Page { color: #55aaff; font-size: 19px; } Page > Label { color: #ff8844; } .theme > Panel Label { font-size: inherit; }")
	ComputedStyleCache.clear()
	var first_build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_true("inherited container declarations are recoverable warnings only", not _has_error_diagnostics(first_build["diagnostics"]))
	var first_root: Control = first_build["root"]
	if first_root != null:
		var direct: Control = _find_by_id(first_root, "direct")[0]
		var nested: Control = _find_by_id(first_root, "nested")[0]
		_expect_true("direct-child combinator matches immediate child", direct.get("text_color") == Color("ff8844"))
		_expect_true("direct-child combinator excludes deeper descendant", nested.get("text_color") == Color("222222"))
		_expect_int("font size inherits through a non-text container", int(nested.get("font_size")), 19)
		first_root.free()
	var after_first := ComputedStyleCache.stats()
	var second_build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	var after_second := ComputedStyleCache.stats()
	_expect_true("equivalent builds hit computed-style cache", int(after_second["hits"]) > int(after_first["hits"]))
	if second_build["root"] != null:
		second_build["root"].free()
	var invalidated := ComputedStyleCache.invalidate_class("title")
	_expect_true("class invalidation targets dependent computed styles", invalidated > 0)

	var gap_markup := GxmlParser.parse("<Page><Row id=\"row\"/><Column id=\"column\"/></Page>")
	var gap_styles := GcssParser.parse("#row { gap: 7px 13px; column-gap: 20px; } #column { gap: 7px 13px; }")
	var gap_build := CascadeBuilder.build(gap_markup["root"], gap_styles["rules"])
	_expect_int("gap shorthand build diagnostics", gap_build["diagnostics"].size(), 0)
	if gap_build["root"] != null:
		var row: Control = _find_by_id(gap_build["root"], "row")[0]
		var column: Control = _find_by_id(gap_build["root"], "column")[0]
		_expect_float("row main gap uses winning column-gap", row.get("gap"), 20.0)
		_expect_float("row line gap uses row-gap", row.get("line_gap"), 7.0)
		_expect_float("column main gap uses row-gap", column.get("gap"), 7.0)
		_expect_float("column line gap uses column-gap", column.get("line_gap"), 13.0)
		gap_build["root"].free()

	var adapted_style := CascadeStyle.new()
	adapted_style.background_color = Color("123456")
	adapted_style.border_color = Color("abcdef")
	adapted_style.border_width = 2.0
	adapted_style.border_radius = 6.0
	adapted_style.padding_left = 8.0
	var native := Button.new()
	ThemeAdapter.apply_style_box(native, adapted_style, &"normal")
	ThemeAdapter.apply_text(native, Color("f0f0f0"), 18)
	var native_box := native.get_theme_stylebox(&"normal") as StyleBoxFlat
	_expect_true("theme adapter maps box colors", native_box != null and native_box.bg_color == Color("123456"))
	_expect_float("theme adapter maps content margins", native_box.content_margin_left, 8.0)
	_expect_true("theme adapter declares adapted tier", native.get_meta("cascade_compatibility_tier") == "adapted")
	native.free()


func _test_responsive_and_transition_styles() -> void:
	var markup := GxmlParser.parse("<Page><Panel id=\"responsive\"/></Page>")
	var stylesheet := GcssParser.parse("""Panel { width: 50vw; transition: background-color 150ms; }
		@media (max-width: 700px) { Panel { width: 80vw; background: #ff6644; } }
		@media (min-width: 701px) { Panel { background: #4da3ff; } }""")
	_expect_int("responsive stylesheet diagnostics", stylesheet["diagnostics"].size(), 0)
	var narrow_build := CascadeBuilder.build(markup["root"], stylesheet["rules"], null, Vector2(600.0, 400.0))
	_expect_int("narrow responsive build diagnostics", narrow_build["diagnostics"].size(), 0)
	if narrow_build["root"] != null:
		var narrow: Control = _find_by_id(narrow_build["root"], "responsive")[0]
		_expect_float("narrow media rule resolves viewport width", narrow.get("cascade_style").preferred_width, 480.0)
		_expect_true("narrow media rule wins background", narrow.get("cascade_style").background_color == Color("ff6644"))
		_expect_float("transition duration normalizes to seconds", narrow.get_meta("cascade_transition_duration"), 0.15)
		_expect_true("transition shorthand maps style property", "background_color" in narrow.get_meta("cascade_transition_properties"))
		narrow_build["root"].free()
	var wide_build := CascadeBuilder.build(markup["root"], stylesheet["rules"], null, Vector2(1000.0, 600.0))
	_expect_int("wide responsive build diagnostics", wide_build["diagnostics"].size(), 0)
	if wide_build["root"] != null:
		var wide: Control = _find_by_id(wide_build["root"], "responsive")[0]
		_expect_float("wide viewport unit resolves", wide.get("cascade_style").preferred_width, 500.0)
		_expect_true("wide media rule wins background", wide.get("cascade_style").background_color == Color("4da3ff"))
		wide_build["root"].free()


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


func _test_text_input_attribute_contract() -> void:
	var markup := GxmlParser.parse("""<TextInput text="secret" placeholder="Access code" read-only="true" disabled="true" secret="true" max-length="12" required="true" pattern="^[a-z]+$" error-message="Lowercase letters only." accessible-label="Access code" accessible-description="Used to join the session." />""")
	var stylesheet := GcssParser.parse("""TextInput { background: #101828; color: #f2f4f7; font-size: 17px; padding: 7px 11px; border: 1px solid #405477; }
		TextInput:hover { background: #182235; }
		TextInput:focused { background: #131b2a; border-color: #84adff; border-width: 2px; }
		TextInput:disabled { background: #111827; color: #667085; }
		TextInput:invalid { background: #2a1720; color: #fff1f0; border-color: #f97066; }""")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_int("text-input attribute parser diagnostics", markup["diagnostics"].size(), 0)
	_expect_int("text-input style parser diagnostics", stylesheet["diagnostics"].size(), 0)
	_expect_int("text-input builder diagnostics", build["diagnostics"].size(), 0)
	var input: Control = build["root"]
	_expect_true("TextInput builds a native LineEdit adapter", input is LineEdit)
	_expect_true("TextInput is classified as adapted", input.get_meta("cascade_compatibility_tier") == "adapted")
	_expect_true("TextInput applies visible and placeholder text", input.get("text") == "secret" and input.get("placeholder_text") == "Access code")
	_expect_true("TextInput applies read-only and disabled semantics", not input.get("editable") and input.get("disabled"))
	_expect_true("TextInput applies secret and max-length attributes", input.get("secret") and input.get("max_length") == 12)
	_expect_true("TextInput applies accessibility metadata", input.get("accessibility_name") == "Access code" and input.get_meta("cascade_authored_accessible_description") == "Used to join the session.")
	_expect_true("TextInput applies adapted text style", input.get("font_size") == 17 and input.get("text_color") == Color("f2f4f7"))
	_expect_true("TextInput applies invalid appearance", input.get("invalid_border_color") == Color("f97066") and input.get("invalid_text_color") == Color("fff1f0"))
	if input != null:
		input.free()
	var multiline_markup := GxmlParser.parse("""<TextInput multiline="true" text="First line&#10;Second line" placeholder="Session notes" read-only="true" max-length="80" required="true" accessible-label="Session notes" />""")
	var multiline_build := CascadeBuilder.build(multiline_markup["root"], [])
	_expect_true("multiline TextInput builds without errors", not _has_error_diagnostics(multiline_build["diagnostics"]))
	var text_area: Control = multiline_build["root"]
	_expect_true("multiline TextInput builds a native TextEdit adapter", text_area is TextEdit)
	_expect_true("multiline TextInput is classified as adapted", text_area.get_meta("cascade_compatibility_tier") == "adapted")
	_expect_true("multiline TextInput applies editing attributes", text_area.get("text") == "First line\nSecond line" and text_area.get("placeholder_text") == "Session notes" and text_area.get("read_only") and text_area.get("max_length") == 80)
	if multiline_build["root"] != null:
		multiline_build["root"].free()
	var secret_multiline := GxmlParser.parse("<TextInput multiline=\"true\" secret=\"true\" />")
	var secret_multiline_build := CascadeBuilder.build(secret_multiline["root"], [])
	_expect_true("multiline secret mode is an explicit build error", _has_error_diagnostics(secret_multiline_build["diagnostics"]))
	if secret_multiline_build["root"] != null:
		secret_multiline_build["root"].free()


func _test_layout_container_state_styles() -> void:
	var markup := GxmlParser.parse("<Page><Panel class=\"hover-surface\" /><Grid class=\"hover-surface\" /><Stack class=\"hover-surface\" /></Page>")
	var stylesheet := GcssParser.parse(".hover-surface { background: #101828; } .hover-surface:hover { background: #1d2939; }")
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"])
	_expect_true("layout hover styles build without errors", not _has_error_diagnostics(build["diagnostics"]))
	var surfaces := _find_by_class(build["root"], "hover-surface")
	_expect_int("layout hover style surface count", surfaces.size(), 3)
	for index in surfaces.size():
		_expect_true("layout hover style is enabled %s" % index, surfaces[index].get("hover_style_enabled"))
		_expect_true("layout hover style color %s" % index, surfaces[index].get("hover_background_color") == Color("1d2939"))
	if build["root"] != null:
		build["root"].free()
	var unsupported_style := GcssParser.parse("Panel:pressed { background: #ff0000; }")
	var unsupported_markup := GxmlParser.parse("<Panel />")
	var unsupported_build := CascadeBuilder.build(unsupported_markup["root"], unsupported_style["rules"])
	_expect_true("unsupported container pressed state remains a warning", not _has_error_diagnostics(unsupported_build["diagnostics"]) and not unsupported_build["diagnostics"].is_empty())
	if unsupported_build["root"] != null:
		unsupported_build["root"].free()


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
	var write_result := BindingResolver.assign(context, "player.name", "Nova")
	_expect_true("binding assigns existing dictionary path", write_result["written"] and context["player"]["name"] == "Nova")
	var array_write := BindingResolver.assign(context, "player.inventory.1", "atlas")
	_expect_true("binding assigns existing array index", array_write["written"] and context["player"]["inventory"][1] == "atlas")
	var missing_write := BindingResolver.assign(context, "player.health", 10)
	_expect_true("binding refuses to invent missing path", not missing_write["written"])


func _test_writable_binding_pipeline() -> void:
	var markup_path := "user://cascade_writable_test.gxml"
	var stylesheet_path := "user://cascade_writable_test.gcss"
	var markup := """<Page>
		<TextInput id="profile" bind-text="{settings.profile}" placeholder="Profile name" required="true" pattern="^.{2,16}$" error-message="Enter 2–16 characters." accessible-label="Profile name" />
		<TextInput id="notes" multiline="true" bind-text="{settings.notes}" placeholder="Session notes" max-length="120" accessible-label="Session notes" />
		<Checkbox id="shadows" bind-checked="{settings.shadows}">Dynamic shadows</Checkbox>
		<Slider id="scale" min="75" max="125" bind-value="{settings.scale}" />
		<Select id="quality" bind-selected="{settings.quality}"><Option value="low">Low</Option><Option value="high">High</Option><Option value="ultra">Ultra</Option></Select>
		<Label id="profile-output" text="{settings.profile}" />
		<Label id="notes-output" text="{settings.notes}" />
		<Label id="scale-output" text="{settings.scale}" />
	</Page>"""
	var stylesheet := """Page { gap: 4px; }
		TextInput:invalid { background: #331122; color: #ffeeee; border-color: #ff6677; }
		TextInput:focus-visible { border-color: #88aaff; border-width: 3px; }
		Button:focus-visible { border-color: #99bbff; border-width: 4px; }"""
	_expect_true("write writable-binding markup", _write_text(markup_path, markup))
	_expect_true("write writable-binding stylesheet", _write_text(stylesheet_path, stylesheet))
	var context := {"settings": {"profile": "Rhea", "notes": "Ready\nfor launch", "shadows": true, "scale": 100.0, "quality": "high"}}
	var document: Control = CascadeDocument.new()
	document.load_on_ready = false
	document.log_diagnostics_to_console = false
	document.watch_sources = false
	document.binding_context = context
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect_true("writable-binding document loads", document.reload_document())
	var input: LineEdit = _find_by_id(document.generated_root(), "profile")[0]
	var notes: TextEdit = _find_by_id(document.generated_root(), "notes")[0]
	var checkbox: BaseButton = _find_by_id(document.generated_root(), "shadows")[0]
	var slider: Range = _find_by_id(document.generated_root(), "scale")[0]
	var select: Control = _find_by_id(document.generated_root(), "quality")[0]
	_expect_true("writable text binding initializes native text", input.text == "Rhea")
	_expect_true("writable multiline binding initializes native text", notes.text == "Ready\nfor launch")
	_expect_true("writable checked binding initializes toggle", checkbox.button_pressed)
	_expect_float("writable range binding initializes value", slider.value, 100.0)
	_expect_true("writable selected binding initializes select", select.call("selected_value") == "high")
	_expect_true("invalid pseudo applies adapted background", input.get("invalid_background_color") == Color("331122"))
	_expect_true("focus-visible pseudo enables modality-aware ring", input.get("focus_visible_style_enabled") and input.get("focus_visible_ring_color") == Color("88aaff"))
	input.text = "Nova"
	input.text_changed.emit(input.text)
	notes.text = "Launch\nconfirmed"
	notes.text_changed.emit()
	checkbox.button_pressed = false
	slider.value = 115.0
	select.call("select_value", "ultra", true)
	await process_frame
	_expect_true("text edit writes binding context", context["settings"]["profile"] == "Nova")
	_expect_true("multiline edit writes binding context", context["settings"]["notes"] == "Launch\nconfirmed")
	_expect_true("toggle writes binding context", not context["settings"]["shadows"])
	_expect_float("slider writes binding context", context["settings"]["scale"], 115.0)
	_expect_true("select writes binding context", context["settings"]["quality"] == "ultra")
	_expect_true("writable update refreshes dependent text", _find_by_id(document.generated_root(), "profile-output")[0].get("text") == "Nova")
	_expect_true("multiline writable update refreshes dependent text", _find_by_id(document.generated_root(), "notes-output")[0].get("text") == "Launch\nconfirmed")
	var input_instance := input.get_instance_id()
	var notes_instance := notes.get_instance_id()
	var refresh_writes: Array[String] = []
	document.binding_value_changed.connect(func(path: String, _value: Variant, _control: Control): refresh_writes.append(path))
	input.select(1, 3)
	notes.select(0, 1, 1, 4)
	_expect_true("write text-input hot-reload markup", _write_text(markup_path, markup.replace("Profile name", "Display name")))
	_expect_true("text-input source edit reloads", document.poll_sources())
	input = _find_by_id(document.generated_root(), "profile")[0]
	notes = _find_by_id(document.generated_root(), "notes")[0]
	_expect_true("text-input reload preserves native identity", input.get_instance_id() == input_instance)
	_expect_true("text-input reload preserves writable text", input.text == "Nova")
	_expect_true("text-input reload preserves selection", input.has_selection() and input.get_selection_from_column() == 1 and input.get_selection_to_column() == 3)
	_expect_true("multiline reload preserves native identity", notes.get_instance_id() == notes_instance)
	_expect_true("multiline reload preserves writable text", notes.text == "Launch\nconfirmed")
	_expect_true("multiline reload preserves selection", notes.has_selection() and notes.get_selection_from_line() == 0 and notes.get_selection_to_line() == 1)
	_expect_true("source reconciliation does not publish synthetic writable changes", refresh_writes.is_empty())

	input.text = ""
	input.text_changed.emit(input.text)
	_expect_true("document validation reports invalid field", not document.validate())
	_expect_true("invalid field retains authored error state", input.get("invalid"))
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_repeated_writable_binding_pipeline() -> void:
	var markup_path := "user://cascade_repeated_writable_test.gxml"
	var stylesheet_path := "user://cascade_repeated_writable_test.gcss"
	var markup := """<Page>
		<Repeat items="{entries}" key="id">
			<Row class="entry-row">
				<Checkbox class="entry-enabled" bind-checked="{item.enabled}" accessible-label="Toggle entry" />
				<TextInput class="entry-name" bind-text="{item.name}" accessible-label="Entry name" />
				<Label class="entry-output" text="{item.enabled}" />
			</Row>
		</Repeat>
	</Page>"""
	_expect_true("write repeated writable markup", _write_text(markup_path, markup))
	_expect_true("write repeated writable stylesheet", _write_text(stylesheet_path, "Page { gap: 4px; } .entry-row { gap: 4px; }"))
	var first := {"id": "alpha", "name": "Alpha", "enabled": true}
	var second := {"id": "beta", "name": "Beta", "enabled": false}
	var context := {"entries": [first, second]}
	var document: Control = CascadeDocument.new()
	document.load_on_ready = false
	document.log_diagnostics_to_console = false
	document.watch_sources = false
	document.binding_context = context
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect_true("repeated writable document loads", document.reload_document())
	var toggles := _find_by_class(document.generated_root(), "entry-enabled")
	var names := _find_by_class(document.generated_root(), "entry-name")
	_expect_int("repeated writable toggle count", toggles.size(), 2)
	_expect_int("repeated writable text count", names.size(), 2)
	var alpha_toggle_id := toggles[0].get_instance_id()
	toggles[0].set("button_pressed", false)
	toggles[0].emit_signal("toggled", false)
	names[0].set("text", "Alpha Prime")
	names[0].emit_signal("text_changed", "Alpha Prime")
	await process_frame
	_expect_true("repeated toggle writes backing item", not first["enabled"])
	_expect_true("repeated text writes backing item", first["name"] == "Alpha Prime")
	_expect_true("repeated write refreshes same-scope dependent label", _find_by_class(document.generated_root(), "entry-output")[0].get("text") == "false")
	context["entries"] = [second, first]
	_expect_true("repeated writable reorder refreshes", document.refresh_bindings())
	toggles = _find_by_class(document.generated_root(), "entry-enabled")
	_expect_true("keyed repeated writable control follows its item", toggles[1].get_instance_id() == alpha_toggle_id)
	toggles[0].set("button_pressed", true)
	toggles[0].emit_signal("toggled", true)
	await process_frame
	_expect_true("reordered repeated write targets current keyed item", second["enabled"])
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))

	var invalid_markup := GxmlParser.parse("<Repeat items=\"{entries}\"><TextInput bind-text=\"{index}\" /></Repeat>")
	var invalid_build := CascadeBuilder.build(invalid_markup["root"], [], context)
	_expect_true("repeat index writable binding is an explicit error", _has_error_diagnostics(invalid_build["diagnostics"]))
	if invalid_build["root"] != null:
		invalid_build["root"].free()


func _test_markup_state_features() -> void:
	_custom_mounts = 0
	_custom_updates = 0
	_custom_unmounts = 0
	_phase3_events = 0
	ComponentRegistry.register(
		"TestCard",
		_make_test_card,
		_on_test_card_mount,
		_on_test_card_update,
		_on_test_card_unmount
	)
	var markup_path := "user://cascade_phase3_test.gxml"
	var stylesheet_path := "user://cascade_phase3_test.gcss"
	var initial_markup := """<Page>
		<TestCard id="custom"><Label>Custom lifecycle</Label></TestCard>
		<Repeat id="rows" items="{entries}" key="id">
			<Row class="entry"><Label text="{item.label}"/><Button text="{item.label}" on-pressed="_on_phase3_event"/></Row>
		</Repeat>
	</Page>"""
	var without_custom := """<Page>
		<Repeat id="rows" items="{entries}" key="id">
			<Row class="entry"><Label text="{item.label}"/><Button text="{item.label}" on-pressed="_on_phase3_event"/></Row>
		</Repeat>
	</Page>"""
	_expect_true("write phase-three markup", _write_text(markup_path, initial_markup))
	_expect_true("write phase-three stylesheet", _write_text(stylesheet_path, "Page { gap: 4px; } .entry { gap: 6px; }"))

	var context := {
		"entries": [
			{"id": "a", "label": "Alpha"},
			{"id": "b", "label": "Beta"},
		],
	}
	var document: Control = CascadeDocument.new()
	document.load_on_ready = false
	document.log_diagnostics_to_console = false
	document.watch_sources = false
	document.binding_context = context
	document.event_context = self
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect_true("phase-three document loads", document.reload_document())
	_expect_int("custom component mounts once", _custom_mounts, 1)
	var rows: Control = _find_by_id(document.generated_root(), "rows")[0]
	_expect_int("repeat expands collection", rows.get_child_count(), 2)
	var beta_row: Control = rows.get_child(1)
	var beta_instance := beta_row.get_instance_id()
	_expect_true("repeat item binding uses local scope", beta_row.get_child(0).get("text") == "Beta")
	var beta_button: BaseButton = beta_row.get_child(1)
	beta_button.emit_signal("pressed")
	_expect_int("event attribute calls target method", _phase3_events, 1)

	context["entries"] = [
		{"id": "b", "label": "Beta 2"},
		{"id": "a", "label": "Alpha"},
		{"id": "c", "label": "Gamma"},
	]
	_expect_true("repeat refresh reconciles collection", document.refresh_bindings())
	rows = _find_by_id(document.generated_root(), "rows")[0]
	_expect_int("repeat adds a keyed item", rows.get_child_count(), 3)
	_expect_true("repeat preserves keyed item identity after reorder", rows.get_child(0).get_instance_id() == beta_instance)
	_expect_true("repeat refreshes scoped binding", rows.get_child(0).get_child(0).get("text") == "Beta 2")
	_expect_true("custom component receives update lifecycle", _custom_updates > 0)
	(rows.get_child(0).get_child(1) as BaseButton).emit_signal("pressed")
	_expect_int("event refresh avoids duplicate connection", _phase3_events, 2)

	_expect_true("write custom removal markup", _write_text(markup_path, without_custom))
	_expect_true("custom removal reloads", document.poll_sources())
	_expect_int("custom component unmounts before removal", _custom_unmounts, 1)
	document.queue_free()
	await process_frame
	ComponentRegistry.unregister("TestCard")

	var duplicate_markup := GxmlParser.parse("<Repeat items=\"{entries}\" key=\"id\"><Label text=\"{item.label}\"/></Repeat>")
	var duplicate_build := CascadeBuilder.build(duplicate_markup["root"], [], {"entries": [{"id": "same", "label": "One"}, {"id": "same", "label": "Two"}]})
	_expect_true("duplicate repeat keys are diagnosed", _has_error_diagnostics(duplicate_build["diagnostics"]))
	if duplicate_build["root"] != null:
		duplicate_build["root"].free()


func _make_test_card() -> Control:
	return CascadePanel.new()


func _on_test_card_mount(_control: Control) -> void:
	_custom_mounts += 1


func _on_test_card_update(_control: Control) -> void:
	_custom_updates += 1


func _on_test_card_unmount(_control: Control) -> void:
	_custom_unmounts += 1


func _on_phase3_event() -> void:
	_phase3_events += 1


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
