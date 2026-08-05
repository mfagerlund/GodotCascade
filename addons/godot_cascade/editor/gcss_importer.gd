@tool
extends EditorImportPlugin

const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const StylesheetResource := preload("res://addons/godot_cascade/resources/cascade_stylesheet_resource.gd")


func _get_importer_name() -> String:
	return "godot_cascade.gcss"


func _get_visible_name() -> String:
	return "GodotCascade Stylesheet"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gcss"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "CascadeStylesheetResource"


func _get_preset_count() -> int:
	return 0


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _import(source_file: String, save_path: String, _options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var resource := StylesheetResource.new()
	resource.source_path = source_file
	resource.source = FileAccess.get_file_as_string(source_file)
	var parsed := GcssParser.parse(resource.source)
	resource.diagnostics.assign(parsed["diagnostics"])
	resource.rule_count = parsed["rules"].size()
	resource.token_count = parsed["tokens"].size()
	return ResourceSaver.save(resource, "%s.%s" % [save_path, _get_save_extension()])
