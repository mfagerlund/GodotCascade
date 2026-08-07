extends SceneTree

## Generates a typed C# partial binding class from a GXML <Bindings> contract.

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")

const WRITABLE_ATTRIBUTES := {
	"bind-text": {"property": "text", "signal": "text_changed", "native_type": "string"},
	"bind-checked": {"property": "button_pressed", "signal": "toggled", "native_type": "bool"},
	"bind-value": {"property": "value", "signal": "value_changed", "native_type": "double"},
	"bind-selected": {"property": "selected_value", "signal": "selection_changed", "native_type": "string"},
}
const ONE_WAY_ATTRIBUTES := {
	"text": "text",
	"checked": "button_pressed",
	"selected": "selected_value",
	"min": "min_value",
	"max": "max_value",
	"value": "value",
}


static func generate(source: String, source_path := "interface.gxml") -> Dictionary:
	var parsed: Dictionary = GxmlParser.parse(source)
	var diagnostics: Array[Dictionary] = []
	for diagnostic in parsed["diagnostics"]:
		diagnostics.append(diagnostic.duplicate())
	var root = parsed["root"]
	if root == null or _has_errors(diagnostics):
		return {"code": "", "diagnostics": diagnostics, "class_name": "", "output_path": ""}
	var contracts: Array = []
	_find_contracts(root, contracts)
	if contracts.size() != 1:
		diagnostics.append(_diagnostic(root, "GXML code generation requires exactly one <Bindings> contract."))
		return {"code": "", "diagnostics": diagnostics, "class_name": "", "output_path": ""}

	var contract = contracts[0]
	var generated_class: String = str(contract.attributes.get("class", "")).strip_edges()
	var namespace_name: String = str(contract.attributes.get("namespace", "")).strip_edges()
	var document_path: String = str(contract.attributes.get("document", "CascadeDocument")).strip_edges()
	if not _is_qualified_identifier(generated_class):
		diagnostics.append(_diagnostic(contract, "Bindings 'class' must be a valid C# identifier."))
	if not namespace_name.is_empty() and not _is_qualified_identifier(namespace_name):
		diagnostics.append(_diagnostic(contract, "Bindings 'namespace' must contain valid dot-separated C# identifiers."))
	if document_path.is_empty():
		diagnostics.append(_diagnostic(contract, "Bindings 'document' must not be empty."))

	var definitions: Dictionary = _read_definitions(contract, diagnostics)
	var usages: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	_collect_usages(root, definitions, usages, seen_ids, diagnostics)
	if usages.is_empty():
		diagnostics.append(_diagnostic(contract, "Bindings contract has no @Binding usages."))
	if _has_errors(diagnostics):
		return {"code": "", "diagnostics": diagnostics, "class_name": generated_class, "output_path": ""}

	var output_path: String = str(contract.attributes.get("output", "%s.g.cs" % generated_class)).strip_edges()
	var code: String = _render_code(generated_class, namespace_name, document_path, source_path, definitions, usages)
	return {"code": code, "diagnostics": diagnostics, "class_name": generated_class, "output_path": output_path}


static func _read_definitions(contract, diagnostics: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {"bindings": {}, "formatters": {}, "parsers": {}, "usings": []}
	for child in contract.children:
		var kind: String = child.tag_name.to_lower()
		if kind == "using":
			var imported: String = str(child.attributes.get("namespace", "")).strip_edges()
			if not _is_qualified_identifier(imported):
				diagnostics.append(_diagnostic(child, "Using 'namespace' must be a valid C# namespace."))
			elif imported not in result["usings"]:
				result["usings"].append(imported)
			continue
		if kind not in ["binding", "formatter", "parser"]:
			diagnostics.append(_diagnostic(child, "Unsupported <%s> inside <Bindings>." % child.tag_name))
			continue
		var name: String = str(child.attributes.get("name", "")).strip_edges()
		if not _is_identifier(name):
			diagnostics.append(_diagnostic(child, "%s 'name' must be a valid C# identifier." % child.tag_name))
			continue
		var bucket_name: String = "%ss" % kind
		var bucket: Dictionary = result[bucket_name]
		if bucket.has(name):
			diagnostics.append(_diagnostic(child, "Duplicate %s '%s'." % [child.tag_name, name]))
			continue
		if kind == "binding":
			var type_name: String = str(child.attributes.get("type", "")).strip_edges()
			var getter: String = str(child.attributes.get("get", "")).strip_edges()
			var setter: String = str(child.attributes.get("set", "")).strip_edges()
			if type_name.is_empty():
				diagnostics.append(_diagnostic(child, "Binding '%s' requires a C# type." % name))
			if not _is_identifier(getter):
				diagnostics.append(_diagnostic(child, "Binding '%s' requires a valid getter method name." % name))
			if not setter.is_empty() and not _is_identifier(setter):
				diagnostics.append(_diagnostic(child, "Binding '%s' setter must be a valid method name." % name))
			bucket[name] = {"name": name, "type": type_name, "get": getter, "set": setter, "element": child}
		else:
			var input_type: String = str(child.attributes.get("input", "")).strip_edges()
			var output_type: String = str(child.attributes.get("output", "")).strip_edges()
			var body: String = str(child.raw_text).strip_edges()
			if input_type.is_empty() or output_type.is_empty():
				diagnostics.append(_diagnostic(child, "%s '%s' requires input and output C# types." % [child.tag_name, name]))
			if body.is_empty():
				diagnostics.append(_diagnostic(child, "%s '%s' requires a CDATA method body." % [child.tag_name, name]))
			bucket[name] = {"name": name, "input": input_type, "output": output_type, "body": body, "element": child}
	return result


static func _collect_usages(element, definitions: Dictionary, usages: Array[Dictionary], seen_ids: Dictionary, diagnostics: Array[Dictionary]) -> void:
	if element.tag_name.to_lower() == "bindings":
		return
	for attribute_name in element.attributes:
		var normalized: String = str(attribute_name).to_lower()
		var raw_value: String = str(element.attributes[attribute_name]).strip_edges()
		if not raw_value.begins_with("@"):
			continue
		var binding_name: String = raw_value.trim_prefix("@").strip_edges()
		var property_name := ""
		var writable := false
		var signal_name := ""
		var native_type := ""
		var format_name := ""
		var parser_name := ""
		if WRITABLE_ATTRIBUTES.has(normalized):
			var writable_definition: Dictionary = WRITABLE_ATTRIBUTES[normalized]
			property_name = writable_definition["property"]
			signal_name = writable_definition["signal"]
			native_type = writable_definition["native_type"]
			writable = true
		elif ONE_WAY_ATTRIBUTES.has(normalized):
			property_name = ONE_WAY_ATTRIBUTES[normalized]
		else:
			diagnostics.append(_diagnostic(element, "Unsupported generated binding attribute '%s'." % attribute_name))
			continue
		if not definitions["bindings"].has(binding_name):
			diagnostics.append(_diagnostic(element, "Generated binding '@%s' has no <Binding> declaration." % binding_name))
			continue
		var element_id: String = str(element.attributes.get("id", "")).strip_edges()
		if element_id.is_empty():
			diagnostics.append(_diagnostic(element, "An element using '@%s' requires a stable id." % binding_name))
			continue
		if seen_ids.has(element_id) and seen_ids[element_id] != element:
			diagnostics.append(_diagnostic(element, "Generated binding id '%s' is duplicated." % element_id))
			continue
		seen_ids[element_id] = element
		var binding: Dictionary = definitions["bindings"][binding_name]
		if writable and str(binding["set"]).is_empty():
			diagnostics.append(_diagnostic(element, "Writable '@%s' requires a setter in its <Binding> declaration." % binding_name))
			continue
		var authored_property: String = normalized.trim_prefix("bind-")
		format_name = str(element.attributes.get("format-%s" % authored_property, "")).strip_edges()
		parser_name = str(element.attributes.get("parse-%s" % authored_property, "")).strip_edges()
		if not format_name.is_empty() and not definitions["formatters"].has(format_name):
			diagnostics.append(_diagnostic(element, "Unknown formatter '%s'." % format_name))
		if not parser_name.is_empty() and not definitions["parsers"].has(parser_name):
			diagnostics.append(_diagnostic(element, "Unknown parser '%s'." % parser_name))
		usages.append({
			"id": element_id,
			"binding": binding_name,
			"property": property_name,
			"writable": writable,
			"signal": signal_name,
			"native_type": native_type,
			"formatter": format_name,
			"parser": parser_name,
			"multiline": str(element.attributes.get("multiline", "false")).to_lower() in ["true", "1", "yes", "on"],
		})
	for child in element.children:
		_collect_usages(child, definitions, usages, seen_ids, diagnostics)


static func _render_code(generated_class: String, namespace_name: String, document_path: String, source_path: String, definitions: Dictionary, usages: Array[Dictionary]) -> String:
	var lines: PackedStringArray = [
		"// <auto-generated />",
		"// Generated by GodotCascade from %s. Do not edit." % source_path,
		"#nullable enable",
		"using System;",
		"using System.Globalization;",
		"using Godot;",
	]
	for imported in definitions["usings"]:
		if imported not in ["System", "System.Globalization", "Godot"]:
			lines.append("using %s;" % imported)
	lines.append("")
	var indent := ""
	if not namespace_name.is_empty():
		lines.append("namespace %s" % namespace_name)
		lines.append("{")
		indent = "    "
	lines.append("%spublic partial class %s : Control" % [indent, generated_class])
	lines.append("%s{" % indent)
	var body_indent := indent + "    "
	lines.append("%s[Export] public NodePath CascadeDocumentPath { get; set; } = %s;" % [body_indent, _csharp_string(document_path)])
	lines.append("%sprivate Control _cascadeDocument = null!;" % body_indent)
	lines.append("%sprivate bool _applyingGeneratedBindings;" % body_indent)
	lines.append("")
	for binding_name in definitions["bindings"]:
		var binding: Dictionary = definitions["bindings"][binding_name]
		lines.append("%sprivate partial %s %s();" % [body_indent, binding["type"], binding["get"]])
		if not str(binding["set"]).is_empty():
			lines.append("%sprivate partial void %s(%s value);" % [body_indent, binding["set"], binding["type"]])
	lines.append("%spartial void OnGeneratedBindingsReady();" % body_indent)
	lines.append("")
	for formatter_name in definitions["formatters"]:
		_append_inline_method(lines, body_indent, definitions["formatters"][formatter_name], source_path, false)
	for parser_name in definitions["parsers"]:
		_append_inline_method(lines, body_indent, definitions["parsers"][parser_name], source_path, true)
	lines.append("%spublic override void _Ready()" % body_indent)
	lines.append("%s{" % body_indent)
	lines.append("%s    base._Ready();" % body_indent)
	lines.append("%s    _cascadeDocument = GetNode<Control>(CascadeDocumentPath);" % body_indent)
	lines.append("%s    var reloaded = Callable.From<Control>(OnCascadeDocumentReloaded);" % body_indent)
	lines.append("%s    if (!_cascadeDocument.IsConnected(\"document_reloaded\", reloaded))" % body_indent)
	lines.append("%s        _cascadeDocument.Connect(\"document_reloaded\", reloaded);" % body_indent)
	lines.append("%s    OnGeneratedBindingsReady();" % body_indent)
	lines.append("%s    RebindGeneratedControls();" % body_indent)
	lines.append("%s}" % body_indent)
	lines.append("")
	lines.append("%sprivate void OnCascadeDocumentReloaded(Control _root) => RebindGeneratedControls();" % body_indent)
	lines.append("")
	lines.append("%sprivate void RebindGeneratedControls()" % body_indent)
	lines.append("%s{" % body_indent)
	var writable_index := 0
	for usage in usages:
		if not usage["writable"]:
			continue
		var local_name: String = "control%s" % writable_index
		var handler_name: String = _handler_name(usage, writable_index)
		lines.append("%s    var %s = FindGeneratedControl(%s);" % [body_indent, local_name, _csharp_string(usage["id"])])
		lines.append("%s    if (%s != null)" % [body_indent, local_name])
		lines.append("%s    {" % body_indent)
		var callable: String = _callable_expression(usage, handler_name)
		lines.append("%s        var callback = %s;" % [body_indent, callable])
		lines.append("%s        if (!%s.IsConnected(%s, callback))" % [body_indent, local_name, _csharp_string(usage["signal"])])
		lines.append("%s            %s.Connect(%s, callback);" % [body_indent, local_name, _csharp_string(usage["signal"])])
		lines.append("%s    }" % body_indent)
		writable_index += 1
	lines.append("%s    RefreshGeneratedBindings();" % body_indent)
	lines.append("%s}" % body_indent)
	lines.append("")
	lines.append("%spublic void RefreshGeneratedBindings()" % body_indent)
	lines.append("%s{" % body_indent)
	lines.append("%s    _applyingGeneratedBindings = true;" % body_indent)
	for index in usages.size():
		var usage: Dictionary = usages[index]
		var binding: Dictionary = definitions["bindings"][usage["binding"]]
		var control_name: String = "bound%s" % index
		lines.append("%s    var %s = FindGeneratedControl(%s);" % [body_indent, control_name, _csharp_string(usage["id"])])
		lines.append("%s    if (%s != null)" % [body_indent, control_name])
		var value_expression: String = "%s()" % binding["get"]
		if not str(usage["formatter"]).is_empty():
			value_expression = "%s(%s)" % [usage["formatter"], value_expression]
		elif usage["property"] == "text":
			value_expression = "Convert.ToString(%s, CultureInfo.InvariantCulture) ?? string.Empty" % value_expression
		if usage["property"] == "selected_value":
			lines.append("%s        %s.Call(\"select_value\", %s);" % [body_indent, control_name, value_expression])
		else:
			lines.append("%s        %s.Set(%s, %s);" % [body_indent, control_name, _csharp_string(usage["property"]), value_expression])
	lines.append("%s    _applyingGeneratedBindings = false;" % body_indent)
	lines.append("%s}" % body_indent)
	lines.append("")
	writable_index = 0
	for usage in usages:
		if not usage["writable"]:
			continue
		_append_handler(lines, body_indent, usage, definitions["bindings"][usage["binding"]], writable_index)
		writable_index += 1
	lines.append("%sprivate Control? FindGeneratedControl(string id)" % body_indent)
	lines.append("%s{" % body_indent)
	lines.append("%s    return FindGeneratedControlIn(_cascadeDocument, id);" % body_indent)
	lines.append("%s}" % body_indent)
	lines.append("")
	lines.append("%sprivate static Control? FindGeneratedControlIn(Node node, string id)" % body_indent)
	lines.append("%s{" % body_indent)
	lines.append("%s    if (node is Control control && control.HasMeta(\"cascade_id\") && control.GetMeta(\"cascade_id\").AsString() == id)" % body_indent)
	lines.append("%s        return control;" % body_indent)
	lines.append("%s    foreach (Node child in node.GetChildren())" % body_indent)
	lines.append("%s    {" % body_indent)
	lines.append("%s        var found = FindGeneratedControlIn(child, id);" % body_indent)
	lines.append("%s        if (found != null)" % body_indent)
	lines.append("%s            return found;" % body_indent)
	lines.append("%s    }" % body_indent)
	lines.append("%s    return null;" % body_indent)
	lines.append("%s}" % body_indent)
	lines.append("%s}" % indent)
	if not namespace_name.is_empty():
		lines.append("}")
	return "\n".join(lines) + "\n"


static func _append_inline_method(lines: PackedStringArray, indent: String, definition: Dictionary, source_path: String, parser: bool) -> void:
	var signature := "private static %s %s(%s value)" % [definition["output"], definition["name"], definition["input"]]
	if parser:
		signature = "private static bool %s(%s value, out %s result)" % [definition["name"], definition["input"], definition["output"]]
	lines.append("%s%s" % [indent, signature])
	lines.append("%s{" % indent)
	var element = definition["element"]
	lines.append("%s#line %s %s" % [indent, element.source_line + 1, _csharp_string(source_path)])
	for body_line in str(definition["body"]).split("\n"):
		lines.append("%s    %s" % [indent, body_line])
	lines.append("%s#line default" % indent)
	lines.append("%s}" % indent)
	lines.append("")


static func _append_handler(lines: PackedStringArray, indent: String, usage: Dictionary, binding: Dictionary, index: int) -> void:
	var handler_name := _handler_name(usage, index)
	var signature := "private void %s(%s value)" % [handler_name, usage["native_type"]]
	if usage["signal"] == "selection_changed":
		signature = "private void %s(string value, long _index)" % handler_name
	elif usage["signal"] == "text_changed" and usage["multiline"]:
		signature = "private void %s()" % handler_name
	lines.append("%s%s" % [indent, signature])
	lines.append("%s{" % indent)
	lines.append("%s    if (_applyingGeneratedBindings) return;" % indent)
	var value_expression := "value"
	if usage["signal"] == "text_changed" and usage["multiline"]:
		value_expression = "FindGeneratedControl(%s)?.Get(\"text\").AsString() ?? string.Empty" % _csharp_string(usage["id"])
	if not str(usage["parser"]).is_empty():
		lines.append("%s    if (!%s(%s, out var parsed)) return;" % [indent, usage["parser"], value_expression])
		value_expression = "parsed"
	lines.append("%s    %s(%s);" % [indent, binding["set"], value_expression])
	lines.append("%s    RefreshGeneratedBindings();" % indent)
	lines.append("%s}" % indent)
	lines.append("")


static func _callable_expression(usage: Dictionary, handler_name: String) -> String:
	if usage["signal"] == "selection_changed":
		return "Callable.From<string, long>(%s)" % handler_name
	if usage["signal"] == "text_changed" and usage["multiline"]:
		return "Callable.From(%s)" % handler_name
	return "Callable.From<%s>(%s)" % [usage["native_type"], handler_name]


static func _handler_name(usage: Dictionary, index: int) -> String:
	return "OnGenerated%s%s%sChanged" % [_pascal_case(usage["id"]), _pascal_case(usage["property"]), index]


static func _find_contracts(element, result: Array) -> void:
	if element.tag_name.to_lower() == "bindings":
		result.append(element)
		return
	for child in element.children:
		_find_contracts(child, result)


static func _pascal_case(value: String) -> String:
	var result := ""
	for part in value.replace("_", "-").split("-", false):
		if not part.is_empty():
			result += part.substr(0, 1).to_upper() + part.substr(1)
	return result


static func _is_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var character := value[index]
		var letter := character.to_lower() >= "a" and character.to_lower() <= "z"
		var digit := index > 0 and character >= "0" and character <= "9"
		if not letter and not digit and character != "_":
			return false
	return true


static func _is_qualified_identifier(value: String) -> bool:
	if value.is_empty():
		return false
	for part in value.split("."):
		if not _is_identifier(part):
			return false
	return true


static func _csharp_string(value: String) -> String:
	return "\"%s\"" % value.replace("\\", "\\\\").replace("\"", "\\\"")


static func _diagnostic(element, message: String) -> Dictionary:
	return {"severity": "error", "line": element.source_line, "column": element.source_column, "message": message}


static func _has_errors(diagnostics: Array[Dictionary]) -> bool:
	return diagnostics.any(func(diagnostic): return diagnostic.get("severity", "error") == "error")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or "--help" in arguments or "-h" in arguments:
		print("Usage: godot --headless --path . --script res://addons/godot_cascade/codegen/csharp_binding_generator.gd -- <input.gxml> [output.g.cs]")
		quit(0 if not arguments.is_empty() else 2)
		return
	var source_path: String = arguments[0]
	var absolute_source := ProjectSettings.globalize_path(source_path) if source_path.begins_with("res://") or source_path.begins_with("user://") else source_path
	if not FileAccess.file_exists(absolute_source):
		push_error("GXML source does not exist: %s" % source_path)
		quit(2)
		return
	var result := generate(FileAccess.get_file_as_string(absolute_source), source_path)
	for diagnostic in result["diagnostics"]:
		push_error("%s:%s:%s: %s" % [source_path, diagnostic.get("line", 1), diagnostic.get("column", 1), diagnostic["message"]])
	if result["code"].is_empty():
		quit(1)
		return
	var output_path: String = arguments[1] if arguments.size() > 1 else str(result["output_path"])
	if not output_path.is_absolute_path() and not output_path.begins_with("res://") and not output_path.begins_with("user://"):
		output_path = source_path.get_base_dir().path_join(output_path)
	var absolute_output := ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") or output_path.begins_with("user://") else output_path
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	if make_error != OK:
		push_error("Could not create generated output directory: %s" % absolute_output.get_base_dir())
		quit(1)
		return
	var file := FileAccess.open(absolute_output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write generated C# file: %s" % output_path)
		quit(1)
		return
	file.store_string(result["code"])
	file.close()
	print("Generated %s from %s" % [output_path, source_path])
	quit(0)
