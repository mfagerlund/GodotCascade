extends "res://addons/godot_cascade/runtime/cascade_document.gd"

const CascadeDocumentScript := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const DeploymentState := preload("res://comparisons/deployment-queue/godot-cascade/deployment_state.gd")
const MARKUP_PATH := "res://comparisons/deployment-queue/godot-cascade/interface.gxml"
const STYLE_PATH := "res://comparisons/deployment-queue/godot-cascade/style.gcss"
const INVALID_MARKUP_PATH := "res://comparisons/deployment-queue/godot-cascade/invalid.gxml"
const COLD_BUILD_COUNT := 10
const SCALAR_UPDATE_COUNT := 100
const REORDER_COUNT := 40

var state := DeploymentState.new()
var _next_id := 13


func _ready() -> void:
	binding_context = state
	event_context = self
	binding_value_changed.connect(_on_binding_value_changed)
	super()
	if "--comparison-verify" in OS.get_cmdline_user_args():
		_run_verification.call_deferred()


func _on_binding_value_changed(path: String, _value: Variant, _control: Control) -> void:
	if path == "concurrency" or path == "include_paused":
		state.recompute()
		refresh_binding_paths(PackedStringArray(["concurrency_label", "visible_jobs", "summary"]))
	state.status_message = "Form values updated"
	refresh_binding_paths(PackedStringArray(["status_message"]))


func _on_queue_job() -> void:
	if not validate():
		state.has_error = true
		state.error_message = "Operator is required"
		state.status_message = "Fix the operator field"
		refresh_binding_paths(PackedStringArray(["has_error", "error_message", "status_message"]))
		return
	state.has_error = false
	state.error_message = ""
	state.jobs.append({
		"id": "job-%03d" % _next_id,
		"service": "worker-%03d" % _next_id,
		"ref": "pending",
		"status": "Queued",
		"owner": state.operator_name,
		"priority": _next_id,
		"selected": false,
	})
	_next_id += 1
	state.status_message = "Deployment queued"
	_refresh_operational_state()


func _on_remove_selected() -> void:
	state.jobs = state.jobs.filter(func(job: Dictionary): return not bool(job.get("selected", false)))
	state.status_message = "Selected deployments removed"
	_refresh_operational_state()


func _on_sort_priority() -> void:
	state.jobs.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("priority", 0)) < int(b.get("priority", 0)))
	state.status_message = "Sorted by priority"
	_refresh_operational_state()


func _refresh_operational_state() -> void:
	state.recompute()
	refresh_binding_paths(PackedStringArray(["visible_jobs", "summary", "status_message", "has_error", "error_message"]))


func _run_verification() -> void:
	await get_tree().process_frame
	log_diagnostics_to_console = false
	var result := {
		"implementation": "godot-cascade",
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"native_control_count": _count_native_controls(generated_root()),
		"functional": {},
		"identity_preserved": false,
		"diagnostic": {},
		"timings": {},
	}
	var functional: Dictionary = result["functional"]
	functional["initial_error_count"] = diagnostics.filter(func(item: Dictionary): return item.get("severity", "error") == "error").size()
	functional["initial_job_count"] = state.jobs.size()
	functional["initial_visible_count"] = state.visible_jobs.size()

	var operator := get_element_by_id("operator")
	operator.text = "Rhea Operator"
	operator.text_changed.emit(operator.text)
	var environment_control := get_element_by_id("environment")
	environment_control.select_value("Production", true)
	var concurrency_control := get_element_by_id("concurrency")
	concurrency_control.value = 4.0
	concurrency_control.value_changed.emit(4.0)
	var paused_control := get_element_by_id("include-paused")
	paused_control.button_pressed = true
	paused_control.toggled.emit(true)
	functional["form_writeback"] = state.operator_name == "Rhea Operator" and state.environment == "Production" and is_equal_approx(state.concurrency, 4.0) and state.include_paused
	functional["visible_after_include_paused"] = state.visible_jobs.size()

	var selected_row := _find_control_by_key_suffix(generated_root(), "job-002")
	var selected_checkbox := _find_element_type(selected_row, "checkbox")
	selected_checkbox.button_pressed = true
	selected_checkbox.toggled.emit(true)
	var selected_backing_item: Dictionary = state.jobs.filter(func(job: Dictionary): return str(job.get("id", "")) == "job-002")[0]
	functional["row_writeback"] = bool(selected_backing_item.get("selected", false))
	var identity_before := selected_row.get_instance_id()
	_on_sort_priority()
	var identity_after_control := _find_control_by_key_suffix(generated_root(), "job-002")
	result["identity_preserved"] = identity_after_control != null and identity_after_control.get_instance_id() == identity_before
	_on_queue_job()
	_on_remove_selected()
	functional["count_after_add_remove"] = state.jobs.size()
	functional["sorted_priority"] = _is_priority_sorted(state.jobs)

	operator = get_element_by_id("operator")
	operator.text = ""
	operator.text_changed.emit("")
	var count_before_invalid := state.jobs.size()
	_on_queue_job()
	functional["invalid_form_blocked"] = state.has_error and state.jobs.size() == count_before_invalid
	operator = get_element_by_id("operator")
	operator.text = "Rhea"
	operator.text_changed.emit("Rhea")
	state.has_error = false
	state.error_message = ""
	_refresh_operational_state()

	result["diagnostic"] = _probe_last_valid_diagnostic()
	result["timings"] = _benchmark_batches()
	result["functional"]["passed"] = (
		functional["initial_error_count"] == 0
		and functional["initial_job_count"] == 12
		and functional["initial_visible_count"] == 10
		and functional["form_writeback"]
		and functional["visible_after_include_paused"] == 12
		and functional["row_writeback"]
		and functional["count_after_add_remove"] == 12
		and functional["sorted_priority"]
		and functional["invalid_form_blocked"]
		and result["identity_preserved"]
		and bool(result["diagnostic"].get("retained_last_valid", false))
		and bool(result["timings"]["scalar_update_batch"].get("rendered_endpoint", false))
		and bool(result["timings"]["scalar_coalesced_batch"].get("rendered_endpoint", false))
		and bool(result["timings"]["keyed_reorder_batch"].get("rendered_endpoint", false))
		and bool(result["timings"]["keyed_reorder_batch"].get("zero_candidate_retained", false))
	)
	print("COMPARISON_JSON=" + JSON.stringify(result))
	get_tree().quit(0 if result["functional"]["passed"] else 1)


func _probe_last_valid_diagnostic() -> Dictionary:
	var probe = CascadeDocumentScript.new()
	probe.name = "DiagnosticProbe"
	probe.load_on_ready = false
	probe.watch_sources = false
	probe.audit_accessibility = false
	probe.log_diagnostics_to_console = false
	probe.binding_context = DeploymentState.new()
	probe.markup_path = MARKUP_PATH
	probe.stylesheet_path = STYLE_PATH
	probe.size = Vector2(1200, 720)
	add_child(probe)
	var valid := probe.reload_document()
	var retained := probe.generated_root()
	var retained_id := retained.get_instance_id() if retained != null else 0
	probe.markup_path = INVALID_MARKUP_PATH
	var invalid_accepted := probe.reload_document()
	var errors: Array = probe.diagnostics.filter(func(item: Dictionary): return item.get("severity", "error") == "error")
	var result := {
		"valid_build": valid,
		"invalid_accepted": invalid_accepted,
		"error_count": errors.size(),
		"first_message": str(errors[0].get("message", "")) if not errors.is_empty() else "",
		"retained_last_valid": probe.generated_root() != null and probe.generated_root().get_instance_id() == retained_id,
	}
	probe.free()
	return result


func _benchmark_batches() -> Dictionary:
	var cold_samples: Array[float] = []
	for _index in COLD_BUILD_COUNT:
		var probe = CascadeDocumentScript.new()
		probe.load_on_ready = false
		probe.watch_sources = false
		probe.audit_accessibility = false
		probe.log_diagnostics_to_console = false
		probe.binding_context = DeploymentState.new()
		probe.markup_path = MARKUP_PATH
		probe.stylesheet_path = STYLE_PATH
		probe.size = Vector2(1200, 720)
		add_child(probe)
		var started := Time.get_ticks_usec()
		var ok := probe.reload_document()
		cold_samples.append((Time.get_ticks_usec() - started) / 1000.0)
		assert(ok)
		probe.free()

	var scalar_started := Time.get_ticks_usec()
	for index in SCALAR_UPDATE_COUNT:
		state.status_message = "Scalar update %d" % index
		refresh_binding_paths(PackedStringArray(["status_message"]))
	var scalar_endpoint := get_element_by_id("status")
	var scalar_rendered := scalar_endpoint != null and str(scalar_endpoint.text) == "Scalar update %d" % (SCALAR_UPDATE_COUNT - 1)
	var scalar_total := (Time.get_ticks_usec() - scalar_started) / 1000.0

	var coalesced_started := Time.get_ticks_usec()
	for index in SCALAR_UPDATE_COUNT:
		state.status_message = "Coalesced update %d" % index
	refresh_binding_paths(PackedStringArray(["status_message"]))
	var coalesced_endpoint := get_element_by_id("status")
	var coalesced_rendered := coalesced_endpoint != null and str(coalesced_endpoint.text) == "Coalesced update %d" % (SCALAR_UPDATE_COUNT - 1)
	var coalesced_total := (Time.get_ticks_usec() - coalesced_started) / 1000.0

	var reorder_started := Time.get_ticks_usec()
	for _index in REORDER_COUNT:
		var moved = state.jobs.pop_front()
		state.jobs.append(moved)
		state.recompute()
		refresh_binding_paths(PackedStringArray(["visible_jobs"]))
	var expected_first_id := str(state.visible_jobs[0].get("id", ""))
	var expected_first_control := _find_control_by_key_suffix(generated_root(), expected_first_id)
	var repeat_control := get_element_by_id("jobs")
	var reorder_rendered := repeat_control != null and repeat_control.get_child_count() > 0 and expected_first_control == repeat_control.get_child(0)
	var reorder_stats: Dictionary = last_binding_trace().get("reconcile_stats", {})
	var zero_candidate_retained := int(reorder_stats.get("repeat_candidates", -1)) == 0 and int(reorder_stats.get("retained_reorders", 0)) == 1
	var reorder_total := (Time.get_ticks_usec() - reorder_started) / 1000.0
	return {
		"cold_build_samples_ms": cold_samples,
		"cold_build_median_ms": _median(cold_samples),
		"scalar_update_batch": {"operations": SCALAR_UPDATE_COUNT, "total_ms": scalar_total, "average_ms_per_operation": scalar_total / SCALAR_UPDATE_COUNT, "rendered_endpoint": scalar_rendered},
		"scalar_coalesced_batch": {"mutations": SCALAR_UPDATE_COUNT, "render_refreshes": 1, "total_ms": coalesced_total, "amortized_ms_per_mutation": coalesced_total / SCALAR_UPDATE_COUNT, "rendered_endpoint": coalesced_rendered},
		"keyed_reorder_batch": {"operations": REORDER_COUNT, "total_ms": reorder_total, "average_ms_per_operation": reorder_total / REORDER_COUNT, "rendered_endpoint": reorder_rendered, "rendered_first_id": expected_first_id, "zero_candidate_retained": zero_candidate_retained, "reconcile_stats": reorder_stats},
	}


func _count_native_controls(root: Node) -> int:
	if root == null:
		return 0
	var count := 1 if root is Control else 0
	for child in root.get_children():
		count += _count_native_controls(child)
	return count


func _find_control_by_key_suffix(root: Node, suffix: String) -> Control:
	if root == null:
		return null
	if root is Control and str(root.get_meta("cascade_key", "")).contains("repeat:%s/" % suffix):
		return root
	for child in root.get_children():
		var found := _find_control_by_key_suffix(child, suffix)
		if found != null:
			return found
	return null


func _find_element_type(root: Node, element_type: String) -> Control:
	if root == null:
		return null
	if root is Control and str(root.get_meta("cascade_element_type", "")).to_lower() == element_type.to_lower():
		return root
	for child in root.get_children():
		var found := _find_element_type(child, element_type)
		if found != null:
			return found
	return null


func _is_priority_sorted(items: Array) -> bool:
	for index in range(1, items.size()):
		if int(items[index - 1].get("priority", 0)) > int(items[index].get("priority", 0)):
			return false
	return true


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	if sorted.is_empty():
		return 0.0
	var middle := sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 == 1 else (sorted[middle - 1] + sorted[middle]) * 0.5
