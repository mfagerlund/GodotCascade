extends SceneTree

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeReconciler := preload("res://addons/godot_cascade/runtime/cascade_reconciler.gd")
const DebugSnapshot := preload("res://addons/godot_cascade/editor/debug_snapshot.gd")

const ITEM_COUNT := 500
const PARSE_BUILD_BUDGET_MS := 2000.0
const LAYOUT_BUDGET_MS := 1000.0
const RECONCILE_BUDGET_MS := 1000.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fragments := PackedStringArray(["<Page>"])
	for index in ITEM_COUNT:
		fragments.append("<Label id=\"item-%s\" class=\"item\">Item %s</Label>" % [index, index])
	fragments.append("</Page>")
	var markup_source := "".join(fragments)
	var style_source := "Page { gap: 2px; } .item { height: 18px; color: #d0d5dd; }"

	var parse_start := Time.get_ticks_usec()
	var markup := GxmlParser.parse(markup_source)
	var stylesheet := GcssParser.parse(style_source)
	var build := CascadeBuilder.build(markup["root"], stylesheet["rules"], null, Vector2(960.0, 540.0))
	var parse_build_ms := (Time.get_ticks_usec() - parse_start) / 1000.0
	var failures := PackedStringArray()
	if not markup["diagnostics"].is_empty() or not stylesheet["diagnostics"].is_empty() or not build["diagnostics"].is_empty():
		failures.append("benchmark fixture produced diagnostics")
	if parse_build_ms > PARSE_BUILD_BUDGET_MS:
		failures.append("parse/build %.2fms exceeds %.2fms" % [parse_build_ms, PARSE_BUILD_BUDGET_MS])

	var built_root: Control = build["root"]
	root.add_child(built_root)
	built_root.size = Vector2(960.0, 540.0)
	var layout_start := Time.get_ticks_usec()
	await process_frame
	await process_frame
	var layout_ms := (Time.get_ticks_usec() - layout_start) / 1000.0
	if layout_ms > LAYOUT_BUDGET_MS:
		failures.append("layout %.2fms exceeds %.2fms" % [layout_ms, LAYOUT_BUDGET_MS])
	var node_count := DebugSnapshot.capture(built_root).size()
	if node_count != ITEM_COUNT + 1:
		failures.append("native node budget expected %s, got %s" % [ITEM_COUNT + 1, node_count])

	var desired: Control = CascadeBuilder.build(markup["root"], stylesheet["rules"], null, Vector2(960.0, 540.0))["root"]
	var reconcile_start := Time.get_ticks_usec()
	var reconciled := CascadeReconciler.reconcile(built_root, desired)
	var reconcile_ms := (Time.get_ticks_usec() - reconcile_start) / 1000.0
	if reconcile_ms > RECONCILE_BUDGET_MS:
		failures.append("reconcile %.2fms exceeds %.2fms" % [reconcile_ms, RECONCILE_BUDGET_MS])
	if int(reconciled["stats"]["created"]) != 0 or int(reconciled["stats"]["replaced"]) != 0 or int(reconciled["stats"]["reused"]) != ITEM_COUNT + 1:
		failures.append("equivalent rebuild exceeded zero-allocation reconciliation budget: %s" % reconciled["stats"])

	print(JSON.stringify({
		"items": ITEM_COUNT,
		"native_nodes": node_count,
		"parse_build_ms": parse_build_ms,
		"layout_ms": layout_ms,
		"reconcile_ms": reconcile_ms,
		"reconcile": reconciled["stats"],
		"budgets_ms": {
			"parse_build": PARSE_BUILD_BUDGET_MS,
			"layout": LAYOUT_BUDGET_MS,
			"reconcile": RECONCILE_BUDGET_MS,
		},
	}))
	if failures.is_empty():
		print("GodotCascade pipeline benchmark passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
