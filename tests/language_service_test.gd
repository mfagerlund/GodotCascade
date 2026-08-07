extends SceneTree

const LanguageService := preload("res://addons/godot_cascade/tooling/language_service.gd")

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
	var elements := LanguageService.completions("<", 1, ".gxml")
	_expect("GXML element completion", elements.any(func(item): return item["label"] == "Button"))
	var attributes := LanguageService.completions("<Button ", 8, ".gxml")
	_expect("GXML attribute completion", attributes.any(func(item): return item["label"] == "autofocus"))
	var binding_attributes := LanguageService.completions("<Bindings ", 10, ".gxml")
	_expect("Bindings output completion matches generator contract", binding_attributes.any(func(item): return item["label"] == "output"))
	var properties := LanguageService.completions("Button {\n  ", 11, ".gcss")
	_expect("GCSS property completion", properties.any(func(item): return item["label"] == "flex-shrink"))
	var hover := LanguageService.hover("Button { opacity: 1; }", 11, ".gcss")
	_expect("GCSS hover documentation", hover.get("symbol", "") == "opacity" and not str(hover.get("documentation", "")).is_empty())


func _test_diagnostics() -> void:
	var gxml := LanguageService.diagnostics("<Page><Unknown /></Page>", ".gxml")
	_expect("unknown GXML element diagnostic", gxml.any(func(item): return "Unknown GXML element" in item["message"]))
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
	var cdata := "<Formatter><![CDATA[\nreturn value;\n]]></Formatter>"
	_expect("formatter preserves verbatim CDATA", LanguageService.format(cdata, ".gxml") == cdata)


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


func _expect(label: String, condition: bool) -> void:
	if not condition: _failures.append(label)
