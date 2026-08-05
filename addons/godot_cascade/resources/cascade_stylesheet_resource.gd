@tool
class_name CascadeStylesheetResource
extends Resource

@export_multiline var source := ""
@export var source_path := ""
@export var rule_count := 0
@export var token_count := 0
@export var diagnostics: Array[Dictionary] = []
