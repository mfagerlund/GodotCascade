extends SceneTree

const NativeBaselines := preload("res://benchmarks/native_workload_baselines.gd")
const SETTINGS_SCENE := preload("res://examples/settings_menu_showcase.tscn")
const DASHBOARD_SCENE := preload("res://examples/system_status_showcase.tscn")
const LEADERBOARD_SCENE := preload("res://examples/leaderboard_showcase.tscn")
const INVENTORY_SCENE := preload("res://examples/collection_scale_showcase.tscn")

const RUN_COUNT := 5
const VIEWPORT_SIZE := Vector2(1280.0, 800.0)
const EXPECTED_INVENTORY_ITEMS := 10_000
const MAX_REALIZED_INVENTORY_ITEMS := 32

# Regression alarms, deliberately wider than normal local and CI variance. These
# protect against accidental whole-document work or unbounded materialization;
# they are not product-performance claims or competitive targets.
const CEILINGS := {
	"settings": {"cascade_total_ceiling_ms": 1200.0, "cascade_nodes": 180, "time_ratio_vs_native": 30.0, "node_ratio_vs_native": 3.0},
	"system_status_dashboard": {"cascade_total_ceiling_ms": 1200.0, "cascade_nodes": 140, "time_ratio_vs_native": 25.0, "node_ratio_vs_native": 3.0},
	"leaderboard": {"cascade_total_ceiling_ms": 1200.0, "cascade_nodes": 260, "time_ratio_vs_native": 30.0, "node_ratio_vs_native": 3.0},
	"virtual_inventory_10k": {"cascade_total_ceiling_ms": 3000.0, "cascade_nodes": 320, "collection_patch_total_ceiling_ms": 1500.0, "time_ratio_vs_native": 25.0, "node_ratio_vs_native": 3.0},
}

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(VIEWPORT_SIZE)
	var workloads: Array[Dictionary] = []
	workloads.append(await _benchmark_pair(
		"settings",
		Callable(self, "_instantiate_settings"),
		Callable(NativeBaselines, "settings_menu")
	))
	workloads.append(await _benchmark_pair(
		"system_status_dashboard",
		Callable(self, "_instantiate_dashboard"),
		Callable(NativeBaselines, "system_status_dashboard")
	))
	workloads.append(await _benchmark_pair(
		"leaderboard",
		Callable(self, "_instantiate_leaderboard"),
		Callable(NativeBaselines, "leaderboard")
	))

	var inventory_cascade := await _measure(
		"virtual_inventory_10k/cascade",
		Callable(self, "_instantiate_inventory"),
		true,
		true
	)
	var cascade_realized_rows := int(inventory_cascade["observations"][0].get("virtual_realized_count", 1))
	var inventory_native := await _measure(
		"virtual_inventory_10k/native_fixed_window",
		Callable(NativeBaselines, "virtual_inventory").bind(cascade_realized_rows),
		false,
		false
	)
	var inventory_item_list := await _measure(
		"virtual_inventory_10k/native_item_list",
		Callable(NativeBaselines, "item_list_inventory"),
		false,
		false
	)
	var inventory_comparison := _comparison("virtual_inventory_10k", inventory_cascade, inventory_native)
	inventory_comparison["native_item_list"] = inventory_item_list
	inventory_comparison["native_baseline_definition"] = "Hand-authored ScrollContainer with a 10,000-Dictionary model, the same %d initially realized fixed-height rows as Cascade at the benchmark viewport, and an unrealized extent spacer." % cascade_realized_rows
	inventory_comparison["item_list_definition"] = "Godot ItemList populated with all 10,000 display strings; included as the closest built-in specialized list alternative."
	_validate_inventory(inventory_comparison)
	workloads.append(inventory_comparison)

	var version := Engine.get_version_info()
	var record := {
		"schema": "godot-cascade-workload-benchmark/v1",
		"success": _failures.is_empty(),
		"engine": {
			"string": str(version.get("string", "unknown")),
			"major": int(version.get("major", 0)),
			"minor": int(version.get("minor", 0)),
			"patch": int(version.get("patch", 0)),
		},
		"methodology": {
			"cold_operations_per_implementation": RUN_COUNT,
			"inventory_collection_patch_operations": RUN_COUNT,
			"processed_layout_frames_per_operation": 2,
			"statistic": "median",
			"viewport": [int(VIEWPORT_SIZE.x), int(VIEWPORT_SIZE.y)],
			"measured_interval": "one total operation: fresh factory/scene instantiation, tree entry and ready/build, followed by two complete process/layout frames",
			"timing_semantics": "Every reported millisecond sample is the total elapsed time for an entire operation including both frames; no value is a per-frame time",
			"resource_loading": "PackedScenes and benchmark scripts are preloaded; every timed sample creates a fresh native tree and fresh binding state",
			"node_metric": "all native Godot Control nodes in the workload subtree, including the workload root",
			"comparability": "Native baselines reproduce semantic content and control shape without custom visual themes; they are not pixel-identical implementations",
		},
		"workloads": workloads,
		"failures": Array(_failures),
	}
	print(JSON.stringify(record))
	if _failures.is_empty():
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _benchmark_pair(workload_name: String, cascade_factory: Callable, native_factory: Callable) -> Dictionary:
	var cascade := await _measure("%s/cascade" % workload_name, cascade_factory, true, false)
	var native := await _measure("%s/native" % workload_name, native_factory, false, false)
	var result := _comparison(workload_name, cascade, native)
	result["native_baseline_definition"] = {
		"settings": "Hand-authored VBox/HBox/PanelContainer tree with equivalent labels, form controls, binding monitor and footer.",
		"system_status_dashboard": "Hand-authored VBox/HBox/PanelContainer tree with equivalent telemetry cards, progress bars, tags and action.",
		"leaderboard": "Hand-authored ScrollContainer/GridContainer with the same seven columns, five standings rows and actions.",
	}.get(workload_name, "Hand-authored native Godot Control tree.")
	_validate_comparison(result)
	return result


func _measure(case_name: String, factory: Callable, inspect_document: bool, probe_collection: bool) -> Dictionary:
	var elapsed_samples: Array[float] = []
	var node_samples: Array[int] = []
	var observations: Array[Dictionary] = []
	var collection_patch_samples: Array[float] = []
	for run_index in RUN_COUNT:
		var started := Time.get_ticks_usec()
		var instance := factory.call() as Control
		if instance == null:
			_failures.append("%s run %d factory did not return a Control" % [case_name, run_index + 1])
			continue
		root.add_child(instance)
		# Packed showcase roots already use full-rect anchors and are sized by the
		# Window. Hand-authored roots use equal anchors and need an explicit size.
		if is_equal_approx(instance.anchor_left, instance.anchor_right) and is_equal_approx(instance.anchor_top, instance.anchor_bottom):
			instance.size = VIEWPORT_SIZE
		await process_frame
		await process_frame
		elapsed_samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		node_samples.append(_count_controls(instance))

		var observation := _inspect(instance, inspect_document)
		if probe_collection:
			var patch_started := Time.get_ticks_usec()
			var probe: Dictionary = _trigger_inventory_update(instance)
			await process_frame
			await process_frame
			collection_patch_samples.append(float(Time.get_ticks_usec() - patch_started) / 1000.0)
			observation = _inspect(instance, inspect_document)
			observation["collection_probe"] = "change the visible name field of item 0 while retaining its stable key via CascadeArrayItemModel.update"
			observation["collection_probe_rendered_value"] = probe.get("expected_text", "")
			observation["collection_probe_rendered_value_verified"] = _tree_contains_text(instance, str(probe.get("expected_text", "")))
			if not bool(probe.get("success", false)):
				_failures.append("%s run %d could not execute the collection probe" % [case_name, run_index + 1])
			elif not bool(observation["collection_probe_rendered_value_verified"]):
				_failures.append("%s run %d collection probe did not update the rendered visible cell to '%s'" % [case_name, run_index + 1, probe.get("expected_text", "")])
		_validate_observation(case_name, run_index, observation)
		observations.append(observation)
		instance.free()
		await process_frame

	if elapsed_samples.size() != RUN_COUNT:
		_failures.append("%s completed %d/%d timing samples" % [case_name, elapsed_samples.size(), RUN_COUNT])
	if not node_samples.is_empty() and (node_samples.min() != node_samples.max()):
		_failures.append("%s native Control count was unstable across fresh runs: %s" % [case_name, node_samples])
	return {
		"median_total_cold_build_plus_two_frames_ms": _median_floats(elapsed_samples),
		"total_cold_build_plus_two_frames_samples_ms": elapsed_samples,
		"median_native_control_count": _median_ints(node_samples),
		"native_control_count_samples": node_samples,
		"median_total_collection_patch_plus_two_frames_ms": _median_floats(collection_patch_samples) if not collection_patch_samples.is_empty() else null,
		"total_collection_patch_plus_two_frames_samples_ms": collection_patch_samples,
		"observations": observations,
	}


func _comparison(workload_name: String, cascade: Dictionary, native: Dictionary) -> Dictionary:
	var cascade_ms := float(cascade["median_total_cold_build_plus_two_frames_ms"])
	var native_ms := float(native["median_total_cold_build_plus_two_frames_ms"])
	var cascade_nodes := int(cascade["median_native_control_count"])
	var native_nodes := int(native["median_native_control_count"])
	return {
		"name": workload_name,
		"cascade": cascade,
		"native_control_baseline": native,
		"ratios": {
			"total_cold_build_plus_two_frames_vs_native": cascade_ms / maxf(native_ms, 0.001),
			"native_controls_vs_native": float(cascade_nodes) / maxf(float(native_nodes), 1.0),
		},
		"ceilings": CEILINGS[workload_name],
	}


func _validate_comparison(comparison: Dictionary) -> void:
	var workload_name := str(comparison["name"])
	var ceilings: Dictionary = comparison["ceilings"]
	var cascade: Dictionary = comparison["cascade"]
	var ratios: Dictionary = comparison["ratios"]
	_assert_budget(workload_name, "Cascade median total cold build plus two frames", float(cascade["median_total_cold_build_plus_two_frames_ms"]), float(ceilings["cascade_total_ceiling_ms"]), "ms")
	_assert_budget(workload_name, "Cascade native Control count", float(cascade["median_native_control_count"]), float(ceilings["cascade_nodes"]), "controls")
	_assert_budget(workload_name, "total cold build plus two frames ratio versus native", float(ratios["total_cold_build_plus_two_frames_vs_native"]), float(ceilings["time_ratio_vs_native"]), "x")
	_assert_budget(workload_name, "native Control ratio versus native", float(ratios["native_controls_vs_native"]), float(ceilings["node_ratio_vs_native"]), "x")


func _validate_inventory(comparison: Dictionary) -> void:
	_validate_comparison(comparison)
	var cascade: Dictionary = comparison["cascade"]
	var ceilings: Dictionary = comparison["ceilings"]
	_assert_budget(
		"virtual_inventory_10k",
		"localized collection patch plus two frames median total",
		float(cascade["median_total_collection_patch_plus_two_frames_ms"]),
		float(ceilings["collection_patch_total_ceiling_ms"]),
		"ms"
	)
	for observation in cascade["observations"]:
		if int(observation.get("virtual_model_count", -1)) != EXPECTED_INVENTORY_ITEMS:
			_failures.append("virtual_inventory_10k expected %d model items, got %s" % [EXPECTED_INVENTORY_ITEMS, observation.get("virtual_model_count", "missing")])
		if int(observation.get("virtual_realized_count", MAX_REALIZED_INVENTORY_ITEMS + 1)) > MAX_REALIZED_INVENTORY_ITEMS:
			_failures.append("virtual_inventory_10k realized %s items; ceiling is %d" % [observation.get("virtual_realized_count", "missing"), MAX_REALIZED_INVENTORY_ITEMS])
		var stats: Dictionary = observation.get("collection_stats", {})
		if int(stats.get("model_count", -1)) != EXPECTED_INVENTORY_ITEMS:
			_failures.append("virtual_inventory_10k collection stats did not report the 10k model: %s" % stats)
		if int(stats.get("realized_count", MAX_REALIZED_INVENTORY_ITEMS + 1)) > MAX_REALIZED_INVENTORY_ITEMS:
			_failures.append("virtual_inventory_10k collection stats exceeded the realized-row ceiling: %s" % stats)
		if int(stats.get("full_document_candidates", -1)) != 0:
			_failures.append("virtual_inventory_10k collection update built a full-document candidate: %s" % stats)
		if int(stats.get("repeat_candidates", 0)) < 1:
			_failures.append("virtual_inventory_10k collection update did not build a localized Repeat candidate: %s" % stats)
		var trace: Dictionary = observation.get("binding_trace", {})
		if trace.get("strategy", "") != "collection_patch" or not bool(trace.get("success", false)):
			_failures.append("virtual_inventory_10k did not report a successful collection-only binding trace: %s" % trace)

	for baseline_name in ["native_control_baseline", "native_item_list"]:
		var baseline: Dictionary = comparison[baseline_name]
		for observation in baseline["observations"]:
			if int(observation.get("model_count", -1)) != EXPECTED_INVENTORY_ITEMS:
				_failures.append("virtual_inventory_10k %s did not contain 10k model items" % baseline_name)
	var fixed_observations: Array = comparison["native_control_baseline"]["observations"]
	var expected_baseline_rows := int(cascade["observations"][0].get("virtual_realized_count", -1))
	for observation in fixed_observations:
		if int(observation.get("realized_count", -1)) != expected_baseline_rows:
			_failures.append("native fixed-window baseline did not match Cascade's %d initially realized rows" % expected_baseline_rows)


func _validate_observation(case_name: String, run_index: int, observation: Dictionary) -> void:
	var diagnostics: Array = observation.get("diagnostics", [])
	if not diagnostics.is_empty():
		_failures.append("%s run %d emitted diagnostics: %s" % [case_name, run_index + 1, diagnostics])
	if observation.has("generated_root_present") and not bool(observation["generated_root_present"]):
		_failures.append("%s run %d did not mount a generated native Control root" % [case_name, run_index + 1])


func _inspect(instance: Control, inspect_document: bool) -> Dictionary:
	var result: Dictionary = {}
	if inspect_document:
		result["diagnostics"] = instance.get("diagnostics").duplicate(true)
		result["generated_root_present"] = instance.has_method("generated_root") and instance.call("generated_root") != null
		var repeat := _find_virtual_repeat(instance)
		if repeat != null:
			result["virtual_model_count"] = int(repeat.get_meta("cascade_virtual_model_count", -1))
			result["virtual_realized_count"] = int(repeat.get_meta("cascade_virtual_realized_count", -1))
			result["virtual_first_index"] = int(repeat.get_meta("cascade_virtual_first_index", -1))
			result["virtual_end_index"] = int(repeat.get_meta("cascade_virtual_end_index", -1))
		if instance.has_method("collection_stats"):
			result["collection_stats"] = instance.call("collection_stats")
		if instance.has_method("last_binding_trace"):
			var trace: Dictionary = instance.call("last_binding_trace")
			result["binding_trace"] = {
				"strategy": trace.get("strategy", ""),
				"trigger": trace.get("trigger", ""),
				"reason": trace.get("reason", ""),
				"success": trace.get("success", false),
				"affected_bindings": trace.get("affected_bindings", 0),
			}
	else:
		result["diagnostics"] = []
		if instance.has_meta("benchmark_model_count"):
			result["model_count"] = int(instance.get_meta("benchmark_model_count"))
		if instance.has_meta("benchmark_realized_count"):
			result["realized_count"] = int(instance.get_meta("benchmark_realized_count"))
	return result


func _trigger_inventory_update(instance: Control) -> Dictionary:
	var model: Variant = instance.get("model")
	if model == null:
		return {"success": false}
	var items: Variant = model.get("items")
	if items == null or not items.has_method("item_at") or not items.has_method("update"):
		return {"success": false}
	var current: Variant = items.call("item_at", 0)
	if not current is Dictionary:
		return {"success": false}
	var updated: Dictionary = current.duplicate(true)
	var expected_text := "%s · benchmark update" % str(current.get("name", "record 0"))
	updated["name"] = expected_text
	return {"success": bool(items.call("update", 0, updated)), "expected_text": expected_text}


func _tree_contains_text(node: Node, expected_text: String) -> bool:
	if expected_text.is_empty():
		return false
	if node is Control:
		for property in node.get_property_list():
			if StringName(property.get("name", "")) == &"text" and str(node.get("text")) == expected_text:
				return true
	for child in node.get_children():
		if _tree_contains_text(child, expected_text):
			return true
	return false


func _find_virtual_repeat(node: Node) -> Control:
	if node is Control and bool(node.get_meta("cascade_virtual", false)):
		return node
	for child in node.get_children():
		var match := _find_virtual_repeat(child)
		if match != null:
			return match
	return null


func _count_controls(node: Node) -> int:
	var result := 1 if node is Control else 0
	for child in node.get_children():
		result += _count_controls(child)
	return result


func _median_floats(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[middle]
	return (sorted[middle - 1] + sorted[middle]) / 2.0


func _median_ints(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _assert_budget(workload_name: String, metric: String, actual: float, ceiling: float, unit: String) -> void:
	if actual > ceiling:
		_failures.append("%s %s %.3f%s exceeds broad regression ceiling %.3f%s" % [workload_name, metric, actual, unit, ceiling, unit])


func _instantiate_settings() -> Control:
	return SETTINGS_SCENE.instantiate()


func _instantiate_dashboard() -> Control:
	return DASHBOARD_SCENE.instantiate()


func _instantiate_leaderboard() -> Control:
	return LEADERBOARD_SCENE.instantiate()


func _instantiate_inventory() -> Control:
	return INVENTORY_SCENE.instantiate()
