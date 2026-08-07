extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://examples/platform_certification/platform_certification.tscn")
	var fixture: Control = scene.instantiate()
	fixture.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	fixture.size = Vector2(1200, 760)
	root.add_child(fixture)
	await process_frame
	await process_frame
	var document: Control = fixture.cascade_document()
	_expect("Cascade fixture loads without errors", document != null and document.diagnostics.filter(func(d): return d.get("severity", "error") == "error").is_empty())
	_expect("Cascade fixture includes all manual control states", document.get_element_by_id("profile") is LineEdit and document.get_element_by_id("secret") is LineEdit and document.get_element_by_id("read-only") is LineEdit and document.get_element_by_id("notes") is TextEdit)
	_expect("plain native baseline is present", fixture.native_profile() is LineEdit and fixture.native_notes() is TextEdit)
	var profile: LineEdit = document.get_element_by_id("profile")
	profile.text = "Certification edit"
	profile.text_changed.emit(profile.text)
	await process_frame
	_expect("Cascade writable echo updates", str(document.get_element_by_id("profile-echo").text) == "Certification edit")
	fixture.native_profile().text = "Native edit"
	fixture.native_profile().text_changed.emit("Native edit")
	await process_frame
	_expect("native baseline remains editable", fixture.native_profile().text == "Native edit")
	fixture.queue_free()
	await process_frame
	if _failures.is_empty():
		print("GodotCascade platform certification fixture tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _expect(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
