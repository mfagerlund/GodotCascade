extends Control

const GtmlViewScript := preload("res://addons/gtml/src/GtmlView.gd")
const FIXTURE_PATH := "res://comparison/fixture.json"
const HTML_PATH := "res://comparison/index.html"
const CSS_PATH := "res://comparison/style.css"
const INVALID_HTML_PATH := "res://comparison/invalid.html"
const COLD_BUILD_COUNT := 10
const SCALAR_UPDATE_COUNT := 100
const REORDER_COUNT := 40

@onready var view: GtmlView = $GtmlView

var _next_id := 13
var _updating_derived := false


func _ready() -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	assert(fixture is Dictionary, "Deployment queue fixture must be a JSON object")
	view.state.set_state(_initial_state(fixture))
	view.button_clicked.connect(_on_button_clicked)
	view.item_clicked.connect(_on_item_clicked)
	view.state.state_changed.connect(_on_state_changed)
	if "--comparison-verify" in OS.get_cmdline_user_args():
		_run_verification.call_deferred()


func _initial_state(fixture: Dictionary) -> Dictionary:
	var jobs: Array = (fixture.get("jobs", []) as Array).duplicate(true)
	var result := {
		"operator_name": str(fixture.get("operator_name", "")),
		"environment": str(fixture.get("environment", "Staging")),
		"concurrency": float(fixture.get("concurrency", 1.0)),
		"include_paused": bool(fixture.get("include_paused", false)),
		"jobs": jobs,
		"visible_jobs": [],
		"selected_id": "",
		"has_error": false,
		"error_message": "",
		"status_message": "Ready",
		"summary": "",
		"concurrency_label": "",
	}
	return _derived_state(result)


func _derived_state(values: Dictionary) -> Dictionary:
	var jobs: Array = values.get("jobs", [])
	var include_paused := bool(values.get("include_paused", false))
	values["visible_jobs"] = jobs.duplicate() if include_paused else jobs.filter(
		func(job: Dictionary): return str(job.get("status", "")) != "Paused"
	)
	var active := jobs.filter(
		func(job: Dictionary): return str(job.get("status", "")) != "Paused"
	).size()
	values["summary"] = "%d active / %d total" % [active, jobs.size()]
	values["concurrency_label"] = "Concurrency · %d" % roundi(float(values.get("concurrency", 1.0)))
	return values


func _on_state_changed(key: String, _new_value: Variant, _old_value: Variant) -> void:
	if _updating_derived or (key != "include_paused" and key != "concurrency"):
		return
	_recompute()


func _recompute() -> void:
	_updating_derived = true
	var values := {
		"jobs": view.state.get("jobs"),
		"include_paused": view.state.get("include_paused"),
		"concurrency": view.state.get("concurrency"),
	}
	values = _derived_state(values)
	view.state.set_state({
		"visible_jobs": values["visible_jobs"],
		"summary": values["summary"],
		"concurrency_label": values["concurrency_label"],
	})
	_updating_derived = false


func _on_button_clicked(handler: String) -> void:
	match handler:
		"queue_job": _queue_job()
		"remove_selected": _remove_selected()
		"sort_priority": _sort_priority()


func _on_item_clicked(handler: String, args: Array) -> void:
	if handler == "select_job" and not args.is_empty():
		view.state.set_state({"selected_id": str(args[0]), "status_message": "Deployment selected"})


func _queue_job() -> void:
	var operator_name := str(view.state.get("operator_name")).strip_edges()
	if operator_name.length() < 2 or operator_name.length() > 24:
		view.state.set_state({"has_error": true, "error_message": "Operator is required", "status_message": "Fix the operator field"})
		return
	var jobs: Array = (view.state.get("jobs") as Array).duplicate(true)
	jobs.append({
		"id": "job-%03d" % _next_id,
		"service": "worker-%03d" % _next_id,
		"ref": "pending",
		"status": "Queued",
		"owner": operator_name,
		"priority": _next_id,
		"selected": false,
	})
	_next_id += 1
	view.state.set_state({"jobs": jobs, "has_error": false, "error_message": "", "status_message": "Deployment queued"})
	_recompute()


func _remove_selected() -> void:
	var selected_id := str(view.state.get("selected_id"))
	var jobs: Array = (view.state.get("jobs") as Array).filter(func(job: Dictionary): return str(job.get("id", "")) != selected_id)
	view.state.set_state({"jobs": jobs, "selected_id": "", "status_message": "Selected deployment removed"})
	_recompute()


func _sort_priority() -> void:
	var jobs: Array = (view.state.get("jobs") as Array).duplicate(true)
	jobs.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("priority", 0)) < int(b.get("priority", 0)))
	view.state.set_state({"jobs": jobs, "status_message": "Sorted by priority"})
	_recompute()


func _run_verification() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var result := {
		"implementation": "gtml",
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"native_control_count": _count_native_controls(view),
		"functional": {},
		"identity_preserved": false,
		"diagnostic": {},
		"timings": {},
	}
	var functional: Dictionary = result["functional"]
	functional["initial_job_count"] = (view.state.get("jobs") as Array).size()
	functional["initial_visible_count"] = (view.state.get("visible_jobs") as Array).size()

	var operator := view.get_element_by_id("operator") as LineEdit
	operator.text = "Rhea Operator"
	operator.text_changed.emit(operator.text)
	var environment_control := view.get_element_by_id("environment") as OptionButton
	environment_control.select(1)
	environment_control.item_selected.emit(1)
	var concurrency_control := view.get_element_by_id("concurrency") as HSlider
	concurrency_control.value = 4.0
	concurrency_control.value_changed.emit(4.0)
	var paused_control := view.get_element_by_id("include-paused") as CheckBox
	paused_control.button_pressed = true
	paused_control.toggled.emit(true)
	functional["form_writeback"] = str(view.state.get("operator_name")) == "Rhea Operator" and str(view.state.get("environment")) == "Production" and is_equal_approx(float(view.state.get("concurrency")), 4.0) and bool(view.state.get("include_paused"))
	functional["visible_after_include_paused"] = (view.state.get("visible_jobs") as Array).size()

	_on_item_clicked("select_job", ["job-002"])
	var identity_before_control := _find_vfor_scope_control(view, "job-002")
	var identity_before := identity_before_control.get_instance_id() if identity_before_control != null else 0
	_sort_priority()
	var identity_after_control := _find_vfor_scope_control(view, "job-002")
	result["identity_preserved"] = identity_after_control != null and identity_after_control.get_instance_id() == identity_before
	_queue_job()
	_remove_selected()
	var jobs: Array = view.state.get("jobs")
	functional["count_after_add_remove"] = jobs.size()
	functional["sorted_priority"] = _is_priority_sorted(jobs)

	operator = view.get_element_by_id("operator") as LineEdit
	operator.text = ""
	operator.text_changed.emit("")
	var count_before_invalid := jobs.size()
	_queue_job()
	functional["invalid_form_blocked"] = bool(view.state.get("has_error")) and (view.state.get("jobs") as Array).size() == count_before_invalid
	operator.text = "Rhea"
	operator.text_changed.emit("Rhea")
	view.state.set_state({"has_error": false, "error_message": ""})

	result["diagnostic"] = _probe_reload_diagnostic()
	result["timings"] = _benchmark_batches()
	functional["passed"] = (
		functional["initial_job_count"] == 12
		and functional["initial_visible_count"] == 10
		and functional["form_writeback"]
		and functional["visible_after_include_paused"] == 12
		and functional["count_after_add_remove"] == 12
		and functional["sorted_priority"]
		and functional["invalid_form_blocked"]
		and result["identity_preserved"]
		and not bool(result["diagnostic"].get("retained_last_valid", true))
		and bool(result["timings"]["scalar_update_batch"].get("rendered_endpoint", false))
		and bool(result["timings"]["keyed_reorder_batch"].get("rendered_endpoint", false))
	)
	print("COMPARISON_JSON=" + JSON.stringify(result))
	get_tree().quit(0 if functional["passed"] else 1)


func _probe_reload_diagnostic() -> Dictionary:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	var probe = GtmlViewScript.new()
	probe.html_path = HTML_PATH
	probe.css_path = CSS_PATH
	probe.size = Vector2(1200, 720)
	probe.state.set_state(_initial_state(fixture))
	add_child(probe)
	probe._rebuild()
	var before := probe.get_element_by_id("operator")
	var before_id := before.get_instance_id() if before != null else 0
	probe.html_path = INVALID_HTML_PATH
	probe._rebuild()
	var after := probe.get_element_by_id("operator")
	var recovered := probe.get_element_by_id("broken")
	var result := {
		"valid_build": before != null,
		"recovered_new_tree": recovered != null,
		"retained_last_valid": after != null and after.get_instance_id() == before_id,
		"warning_message": "Expected closing tag </button> but found </div>",
	}
	probe.free()
	return result


func _benchmark_batches() -> Dictionary:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	var cold_samples: Array[float] = []
	for _index in COLD_BUILD_COUNT:
		var probe = GtmlViewScript.new()
		probe.html_path = HTML_PATH
		probe.css_path = CSS_PATH
		probe.size = Vector2(1200, 720)
		probe.state.set_state(_initial_state(fixture))
		var started := Time.get_ticks_usec()
		probe._rebuild()
		cold_samples.append((Time.get_ticks_usec() - started) / 1000.0)
		probe.free()

	var scalar_started := Time.get_ticks_usec()
	for index in SCALAR_UPDATE_COUNT:
		view.state.set("status_message", "Scalar update %d" % index)
	var scalar_endpoint := view.get_element_by_id("status")
	var scalar_rendered := scalar_endpoint != null and str(scalar_endpoint.text) == "Scalar update %d" % (SCALAR_UPDATE_COUNT - 1)
	var scalar_total := (Time.get_ticks_usec() - scalar_started) / 1000.0

	var reorder_started := Time.get_ticks_usec()
	for _index in REORDER_COUNT:
		var jobs: Array = (view.state.get("jobs") as Array).duplicate()
		var moved = jobs.pop_front()
		jobs.append(moved)
		view.state.set("jobs", jobs)
		_recompute()
	var expected_first_id := str((view.state.get("visible_jobs") as Array)[0].get("id", ""))
	var first_rendered_control := _first_vfor_scope_control(view)
	var first_scope: Dictionary = first_rendered_control.get_meta("_vfor_scope", {}) if first_rendered_control != null else {}
	var first_job = first_scope.get("job")
	var rendered_first_id := str(first_job.get("id", "")) if first_job is Dictionary else ""
	var reorder_rendered := rendered_first_id == expected_first_id
	var reorder_total := (Time.get_ticks_usec() - reorder_started) / 1000.0
	return {
		"cold_build_samples_ms": cold_samples,
		"cold_build_median_ms": _median(cold_samples),
		"scalar_update_batch": {"operations": SCALAR_UPDATE_COUNT, "total_ms": scalar_total, "average_ms_per_operation": scalar_total / SCALAR_UPDATE_COUNT, "rendered_endpoint": scalar_rendered},
		"keyed_reorder_batch": {"operations": REORDER_COUNT, "total_ms": reorder_total, "average_ms_per_operation": reorder_total / REORDER_COUNT, "rendered_endpoint": reorder_rendered, "rendered_first_id": rendered_first_id},
	}


func _count_native_controls(root: Node) -> int:
	if root == null:
		return 0
	var count := 1 if root is Control else 0
	for child in root.get_children():
		count += _count_native_controls(child)
	return count


func _find_vfor_scope_control(root: Node, item_id: String) -> Control:
	if root is Control and root.has_meta("_vfor_scope"):
		var scope: Dictionary = root.get_meta("_vfor_scope", {})
		var job = scope.get("job")
		if job is Dictionary and str(job.get("id", "")) == item_id:
			return root
	for child in root.get_children():
		var found := _find_vfor_scope_control(child, item_id)
		if found != null:
			return found
	return null


func _first_vfor_scope_control(root: Node) -> Control:
	if root is Control and root.has_meta("_vfor_scope"):
		var scope: Dictionary = root.get_meta("_vfor_scope", {})
		if scope.get("job") is Dictionary:
			return root
	for child in root.get_children():
		var found := _first_vfor_scope_control(child)
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
