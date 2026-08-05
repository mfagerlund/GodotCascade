@tool
extends EditorImportPlugin

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const MarkupResource := preload("res://addons/godot_cascade/resources/cascade_markup_resource.gd")


func _get_importer_name() -> String:
	return "godot_cascade.gxml"


func _get_visible_name() -> String:
	return "GodotCascade Markup"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gxml"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "CascadeMarkupResource"


func _get_preset_count() -> int:
	return 0


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var resource := MarkupResource.new()
	resource.source_path = source_file
	resource.source = FileAccess.get_file_as_string(source_file)
	var parsed := GxmlParser.parse(resource.source)
	resource.diagnostics.assign(parsed["diagnostics"])
	if parsed["root"] != null:
		resource.root_element = parsed["root"].tag_name
	return ResourceSaver.save(resource, "%s.%s" % [save_path, _get_save_extension()])
