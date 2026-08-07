extends RefCounted

const FIXTURE_PATH := "res://comparisons/deployment-queue/fixture.json"

var operator_name := ""
var environment := "Staging"
var concurrency := 1.0
var include_paused := false
var jobs: Array = []
var visible_jobs: Array = []
var has_error := false
var error_message := ""
var status_message := "Ready"
var summary := ""
var concurrency_label := "Concurrency · 1"


func _init() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	assert(parsed is Dictionary, "Deployment queue fixture must be a JSON object")
	operator_name = str(parsed.get("operator_name", ""))
	environment = str(parsed.get("environment", "Staging"))
	concurrency = float(parsed.get("concurrency", 1.0))
	include_paused = bool(parsed.get("include_paused", false))
	jobs = (parsed.get("jobs", []) as Array).duplicate(true)
	recompute()


func recompute() -> void:
	visible_jobs = jobs.duplicate() if include_paused else jobs.filter(
		func(job: Dictionary): return str(job.get("status", "")) != "Paused"
	)
	var active := jobs.filter(
		func(job: Dictionary): return str(job.get("status", "")) != "Paused"
	).size()
	summary = "%d active / %d total" % [active, jobs.size()]
	concurrency_label = "Concurrency · %d" % roundi(concurrency)
