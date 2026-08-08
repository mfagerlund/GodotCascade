extends SceneTree

const LanguageService := preload("res://addons/godot_cascade/tooling/language_service.gd")
const GxmlSchema := preload("res://addons/godot_cascade/runtime/gxml_schema.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_completion_and_hover()
	_test_diagnostics()
	_test_formatting()
	_test_definition_and_rename()
	if _failures.is_empty():
		print("GodotCascade language service tests passed.")
		quit(0)
	else:
		for failure in _failures: push_error(failure)
		quit(1)


func _test_completion_and_hover() -> void:
	_expect("language service documents every authoritative element", LanguageService.ELEMENTS.size() == GxmlSchema.ELEMENT_ATTRIBUTES.size() and GxmlSchema.ELEMENT_ATTRIBUTES.keys().all(func(element_name): return LanguageService.ELEMENTS.has(element_name)))
	_expect("language service uses authoritative element attributes", LanguageService.ELEMENT_ATTRIBUTES == GxmlSchema.ELEMENT_ATTRIBUTES)
	_expect("language service uses authoritative aliases", LanguageService.ELEMENT_ALIASES == GxmlSchema.ALIASES)
	_expect("language service uses authoritative generated binding attributes", LanguageService.GENERATED_BINDING_ATTRIBUTES == GxmlSchema.GENERATED_BINDING_ATTRIBUTES)
	_expect("language service documents every authoritative common attribute", LanguageService.GLOBAL_ATTRIBUTES.size() == GxmlSchema.COMMON_ATTRIBUTES.size() and GxmlSchema.COMMON_ATTRIBUTES.all(func(attribute_name): return LanguageService.GLOBAL_ATTRIBUTES.has(attribute_name)))
	var elements := LanguageService.completions("<", 1, ".gxml")
	_expect("GXML element completion", elements.any(func(item): return item["label"] == "Button"))
	var attributes := LanguageService.completions("<Button ", 8, ".gxml")
	_expect("GXML attribute completion", attributes.any(func(item): return item["label"] == "autofocus"))
	_expect("non-Container completion omits focus-trap", not attributes.any(func(item): return item["label"] == "focus-trap"))
	_expect("Container completion includes focus-trap", LanguageService.completions("<Panel ", 7, ".gxml").any(func(item): return item["label"] == "focus-trap"))
	_expect("custom completion leaves focus-trap undecided", LanguageService.completions("<ProjectWidget ", 15, ".gxml").any(func(item): return item["label"] == "focus-trap"))
	var binding_attributes := LanguageService.completions("<Bindings ", 10, ".gxml")
	_expect("Bindings output completion matches generator contract", binding_attributes.any(func(item): return item["label"] == "output"))
	for completion_probe in [
		["<Button ", "on-pressed"], ["<Checkbox ", "bind-checked"], ["<Radio ", "bind-checked"],
		["<Switch ", "on-toggled"], ["<Select ", "bind-selected"], ["<Slider ", "bind-value"],
		["<Input ", "bind-text"],
	]:
		var probe_source := str(completion_probe[0])
		_expect("GXML completion includes %s for %s" % [completion_probe[1], probe_source], LanguageService.completions(probe_source, probe_source.length(), ".gxml").any(func(item): return item["label"] == completion_probe[1]))
	var properties := LanguageService.completions("Button {\n  ", 11, ".gcss")
	_expect("GCSS property completion", properties.any(func(item): return item["label"] == "flex-shrink"))
	var hover := LanguageService.hover("Button { opacity: 1; }", 11, ".gcss")
	_expect("GCSS hover documentation", hover.get("symbol", "") == "opacity" and not str(hover.get("documentation", "")).is_empty())


func _test_diagnostics() -> void:
	var gxml := LanguageService.diagnostics("<Page><Unknown /></Page>", ".gxml")
	_expect("unknown GXML element diagnostic", gxml.any(func(item): return "Unknown GXML element" in item["message"]))
	_expect("GXML diagnostics accept runtime aliases and element case", LanguageService.diagnostics("<page><Input /><Radio /></page>", ".gxml").is_empty())
	_expect("unknown built-in GXML attribute diagnostic", LanguageService.diagnostics("<Button disabeld=\"true\" />", ".gxml").any(func(item): return "Unknown attribute" in item["message"]))
	_expect("wrong-case built-in GXML attribute diagnostic", LanguageService.diagnostics("<Button Disabled=\"true\" />", ".gxml").any(func(item): return "Unknown attribute" in item["message"]))
	_expect("reserved internal GXML attribute diagnostic", LanguageService.diagnostics("<Page __component_scope=\"spoofed\" />", ".gxml").any(func(item): return "Unknown attribute" in item["message"]))
	_expect("reserved internal attribute is rejected on custom elements", LanguageService.diagnostics("<Page><Widget __component_scope=\"spoofed\" /></Page>", ".gxml").any(func(item): return "Unknown attribute '__component_scope'" in item["message"]))
	_expect("Option accepts selector identity attributes", LanguageService.diagnostics("<Select><Option id=\"high\" class=\"premium\">High</Option></Select>", ".gxml").is_empty())
	_expect("Option still rejects irrelevant common attributes", LanguageService.diagnostics("<Select><Option visible=\"false\">Hidden</Option></Select>", ".gxml").any(func(item): return "Unknown attribute 'visible'" in item["message"]))
	var option_attributes := LanguageService.completions("<Option ", 8, ".gxml")
	_expect("Option completion includes id and class", option_attributes.any(func(item): return item["label"] == "id") and option_attributes.any(func(item): return item["label"] == "class"))
	_expect("Option completion omits irrelevant common attributes", not option_attributes.any(func(item): return item["label"] == "visible" or item["label"] == "focus-trap"))
	_expect("root if diagnostic", LanguageService.diagnostics("<Page if=\"{show}\" />", ".gxml").any(func(item): return "document root cannot use 'if'" in item["message"] and item.get("line", 0) == 1))
	_expect("root component invocation if diagnostic", LanguageService.diagnostics("<RootCard if=\"{show}\"><Component name=\"RootCard\"><Page><Slot /></Page></Component></RootCard>", ".gxml").any(func(item): return "document root cannot use 'if'" in item["message"]))
	_expect("bound visible remains allowed on root", not _has_message(LanguageService.diagnostics("<Page visible=\"{show}\" />", ".gxml"), "document root"))
	_expect("non-visual root diagnostic", LanguageService.diagnostics("<Bindings class=\"ScreenBindings\" />", ".gxml").any(func(item): return "document root must be visual" in item["message"]))
	for invalid_trap_tag in ["Button", "Label", "Slider"]:
		_expect("%s focus trap diagnostic" % invalid_trap_tag, LanguageService.diagnostics("<Page>\n<%s focus-trap=\"true\" />\n</Page>" % invalid_trap_tag, ".gxml").any(func(item): return "native Container" in item["message"] and item.get("line", 0) > 0 and item.get("column", 0) > 0))
	_expect("false non-Container focus trap remains harmless", not _has_message(LanguageService.diagnostics("<Button focus-trap=\"off\" />", ".gxml"), "native Container"))
	_expect("virtual item-root visible binding diagnostic", _has_message(LanguageService.diagnostics("<Page><Scroll><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Row visible=\"{item.shown}\" /></Repeat></Scroll></Page>", ".gxml"), "item roots cannot use conditional 'visible'"))
	_expect("virtual item-root if diagnostic", _has_message(LanguageService.diagnostics("<Page><Scroll><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Row if=\"{item.shown}\" /></Repeat></Scroll></Page>", ".gxml"), "item roots cannot use 'if'"))
	_expect("literal true virtual item-root visible remains valid", not _has_message(LanguageService.diagnostics("<Page><Scroll><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Row visible=\"true\" /></Repeat></Scroll></Page>", ".gxml"), "item roots cannot use conditional 'visible'"))
	_expect("virtual item descendant visible binding remains valid", not _has_message(LanguageService.diagnostics("<Page><Scroll><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Row><Label visible=\"{item.shown}\" /></Row></Repeat></Scroll></Page>", ".gxml"), "item roots cannot use conditional 'visible'"))
	var gcss := LanguageService.diagnostics("Button { opacityy: 1; }", ".gcss")
	_expect("unknown GCSS property diagnostic", gcss.any(func(item): return "Unsupported GCSS property" in item["message"]))


func _test_formatting() -> void:
	var source := "<Page><Button id=\"save\">Save</Button></Page>"
	var formatted := LanguageService.format(source, ".gxml")
	_expect("GXML formatter expands nesting", "    <Button" in formatted)
	_expect("GXML formatter is idempotent", LanguageService.format(formatted, ".gxml") == formatted)
	var gcss := "Button{opacity:1;flex-grow:2;}"
	var formatted_gcss := LanguageService.format(gcss, ".gcss")
	_expect("GCSS formatter normalizes declarations", "    opacity: 1;" in formatted_gcss)
	_expect("GCSS formatter is idempotent", LanguageService.format(formatted_gcss, ".gcss") == formatted_gcss)
	var complex_gcss := "Page{font-source:resource(\"res://fonts/a;b}.tres\");opacity:1;}"
	var formatted_complex_gcss := LanguageService.format(complex_gcss, ".gcss")
	_expect("GCSS tooling accepts quoted declaration boundaries", LanguageService.diagnostics(complex_gcss, ".gcss").is_empty())
	_expect("GCSS formatter preserves quoted semicolons and braces", "font-source: resource(\"res://fonts/a;b}.tres\");" in formatted_complex_gcss and "opacity: 1;" in formatted_complex_gcss)
	var cdata := "<Formatter><![CDATA[\nreturn value;\n]]></Formatter>"
	_expect("formatter preserves verbatim CDATA", LanguageService.format(cdata, ".gxml") == cdata)
	var quoted_greater_than := "<Page><Label accessible-description=\"Score > target\">Ready</Label></Page>"
	var formatted_greater_than := LanguageService.format(quoted_greater_than, ".gxml")
	_expect("GXML formatter preserves greater-than signs inside quoted attributes", "accessible-description=\"Score > target\"" in formatted_greater_than and "Ready" in formatted_greater_than)
	var commented_gcss := "/* keep this note */\nButton{opacity:1;}"
	_expect("Godot GCSS formatter never drops comments", LanguageService.format(commented_gcss, ".gcss") == commented_gcss)


func _test_definition_and_rename() -> void:
	var source := "<Page><Component name=\"Card\"><Slot /></Component><Card /></Page>"
	var usage := source.rfind("Card")
	var definition := LanguageService.definition(source, usage + 1, ".gxml", "res://ui.gxml")
	_expect("component definition lookup", definition.get("path", "") == "res://ui.gxml" and int(definition.get("line", 0)) == 1)
	var edits := LanguageService.rename(source, usage + 1, "FeatureCard", ".gxml")
	var renamed := LanguageService.apply_edits(source, edits)
	_expect("component rename updates definition and use", "name=\"FeatureCard\"" in renamed and "<FeatureCard" in renamed)
	var custom := ".a { --Accent: #fff; color: var(--Accent); }"
	var custom_offset := custom.rfind("--Accent")
	var custom_edits := LanguageService.rename(custom, custom_offset + 2, "--Primary", ".gcss")
	_expect("custom-property rename updates declaration and reference", LanguageService.apply_edits(custom, custom_edits).count("--Primary") == 2)
	var prose := "<Page><!-- <Card /> --><Card /></Page>"
	_expect("component rename requires a local declaration", LanguageService.rename(prose, prose.rfind("Card") + 1, "FeatureCard", ".gxml").is_empty())
	var guarded := "<Page><Component name=\"Card\"><Slot /></Component><!-- <Card /> --><Card /></Page>"
	var guarded_edits := LanguageService.rename(guarded, guarded.rfind("Card") + 1, "FeatureCard", ".gxml")
	var guarded_renamed := LanguageService.apply_edits(guarded, guarded_edits)
	_expect("component rename skips comments", "<!-- <Card /> -->" in guarded_renamed and "<FeatureCard />" in guarded_renamed)
	var quoted_custom := ".a { --Accent: #fff; content: \"--Accent\"; /* --Accent */ color: var(--Accent); }"
	var quoted_edits := LanguageService.rename(quoted_custom, quoted_custom.find("--Accent") + 2, "--Primary", ".gcss")
	var quoted_renamed := LanguageService.apply_edits(quoted_custom, quoted_edits)
	_expect("custom-property rename skips strings and comments", quoted_renamed.count("--Primary") == 2 and "\"--Accent\"" in quoted_renamed and "/* --Accent */" in quoted_renamed)
	var quoted_component := "<Page><Component accessible-description=\"score > target\" name=\"Card\"><Slot /></Component><Card /></Page>"
	var quoted_usage := quoted_component.rfind("Card")
	var quoted_definition := LanguageService.definition(quoted_component, quoted_usage + 1, ".gxml", "res://quoted.gxml")
	_expect("component definition tolerates greater-than signs in quoted attributes", quoted_definition.get("path", "") == "res://quoted.gxml")
	var quoted_component_edits := LanguageService.rename(quoted_component, quoted_usage + 1, "ScoreCard", ".gxml")
	var quoted_component_renamed := LanguageService.apply_edits(quoted_component, quoted_component_edits)
	_expect("component rename tolerates greater-than signs in quoted attributes", "name=\"ScoreCard\"" in quoted_component_renamed and "<ScoreCard" in quoted_component_renamed)
	var cdata_component := "<Page><Component name=\"Card\"><Slot /></Component><Formatter><![CDATA[return value > 0 ? \"<Card />\" : value;]]></Formatter><Card /></Page>"
	var cdata_usage := cdata_component.rfind("Card")
	var cdata_edits := LanguageService.rename(cdata_component, cdata_usage + 1, "FeatureCard", ".gxml")
	var cdata_renamed := LanguageService.apply_edits(cdata_component, cdata_edits)
	_expect("component rename preserves verbatim CDATA", "\"<Card />\"" in cdata_renamed and "<FeatureCard />" in cdata_renamed)
	var flexible_component := "<Page><component name = 'Card'><Slot /></component><card /><CARD /></Page>"
	var flexible_usage := flexible_component.rfind("CARD")
	var flexible_edits := LanguageService.rename(flexible_component, flexible_usage + 1, "FeatureCard", ".gxml")
	var flexible_renamed := LanguageService.apply_edits(flexible_component, flexible_edits)
	_expect("component rename handles lowercase declarations, spaced equals, and mixed-case usages", "name = 'FeatureCard'" in flexible_renamed and flexible_renamed.count("<FeatureCard") == 2)
	var lowercase_usage := flexible_component.find("<card") + 2
	var lowercase_edits := LanguageService.rename(flexible_component, lowercase_usage, "FeatureCard", ".gxml")
	var lowercase_renamed := LanguageService.apply_edits(flexible_component, lowercase_edits)
	_expect("component rename accepts a lowercase invocation cursor", "name = 'FeatureCard'" in lowercase_renamed and lowercase_renamed.count("<FeatureCard") == 2)
	var attribute_prose := "<Page><Component name=\"Card\"><Slot /></Component><Label text=\"card\" /><Card /></Page>"
	_expect("component rename ignores matching lowercase attribute prose", LanguageService.rename(attribute_prose, attribute_prose.find("text=\"card\"") + 7, "FeatureCard", ".gxml").is_empty())
	var entity_component := "<Page><Component name=\"Ca&#114;d\"><Slot /></Component><Card /></Page>"
	var entity_usage := entity_component.rfind("Card")
	var entity_edits := LanguageService.rename(entity_component, entity_usage + 1, "FeatureCard", ".gxml")
	var entity_renamed := LanguageService.apply_edits(entity_component, entity_edits)
	_expect("component rename replaces an entity-encoded declaration value atomically", "name=\"FeatureCard\"" in entity_renamed and "<FeatureCard />" in entity_renamed)
	var reserved_component := "<Page><Component name=\"Component\"><Slot /></Component></Page>"
	var reserved_offset := reserved_component.find("name=\"Component\"") + 7
	_expect("component rename cannot target a reserved built-in name", LanguageService.rename(reserved_component, reserved_offset, "FeatureCard", ".gxml").is_empty())
	_expect("component rename cannot produce a reserved built-in name", LanguageService.rename(source, usage + 1, "Component", ".gxml").is_empty())
	var quoted_completion_source := "<Button text=\"1 > 0\" dis"
	_expect("attribute completion tolerates greater-than signs in quoted attributes", LanguageService.completions(quoted_completion_source, quoted_completion_source.length(), ".gxml").any(func(item): return item["label"] == "disabled"))


func _expect(label: String, condition: bool) -> void:
	if not condition: _failures.append(label)


func _has_message(diagnostics: Array[Dictionary], needle: String) -> bool:
	return diagnostics.any(func(item): return needle in str(item.get("message", "")))
