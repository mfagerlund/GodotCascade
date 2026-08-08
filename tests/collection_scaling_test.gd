extends SceneTree

const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const ArrayItemModel := preload("res://addons/godot_cascade/runtime/array_item_model.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var markup_path := "user://cascade_collection_scaling.gxml"
	var stylesheet_path := "user://cascade_collection_scaling.gcss"
	_expect("write collection markup", _write(markup_path, """<Page>
	<Repeat id="rows" items="{model}" key="id">
		<Row class="{item.css}"><Label text="{item.name}" /></Row>
	</Repeat>
	<Repeat id="other-rows" items="{other_model}" key="id">
		<Row><Label text="{item.name}" /></Row>
	</Repeat>
</Page>"""))
	_expect("write collection stylesheet", _write(stylesheet_path, ".alpha { gap: 1px; } .beta { gap: 2px; } .gamma { gap: 3px; }"))

	var model := ArrayItemModel.new([
		{"id": "a", "name": "Alpha", "css": "alpha"},
		{"id": "b", "name": "Beta", "css": "beta"},
		{"id": "c", "name": "Gamma", "css": "gamma"},
	], func(item: Dictionary): return item["id"])
	var other_model := ArrayItemModel.new([
		{"id": "other", "name": "Unaffected"},
	], func(item: Dictionary): return item["id"])
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"model": model, "other_model": other_model}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("item-model document loads", document.reload_document())
	var rows: Control = document.get_element_by_id("rows")
	_expect("all initial model rows materialize", rows != null and rows.get_child_count() == 3)
	if rows != null and rows.get_child_count() == 3:
		_expect("bound classes do not leak between repeat items", _classes(rows.get_child(0)) == PackedStringArray(["alpha"]) and _classes(rows.get_child(1)) == PackedStringArray(["beta"]) and _classes(rows.get_child(2)) == PackedStringArray(["gamma"]))
		var beta_id := rows.get_child(1).get_instance_id()
		var updates := [0]
		document.collection_updated.connect(func(_repeats: Array[Control], _stats: Dictionary): updates[0] += 1)
		_expect("typed move succeeds", model.move_items(1, 0))
		_expect("typed move preserves keyed native identity", rows.get_child(0).get_instance_id() == beta_id)
		_expect("typed update succeeds", model.update(0, {"id": "b", "name": "Beta 2", "css": "beta"}))
		_expect("typed update refreshes item scope", rows.get_child(0).get_child(0).get("text") == "Beta 2")
		_expect("typed insert succeeds", model.insert(1, {"id": "x", "name": "Xenon", "css": "alpha"}))
		_expect("insert materializes one keyed row", rows.get_child_count() == 4 and "repeat:x" in str(rows.get_child(1).get_meta("cascade_key", "")))
		_expect("typed removal succeeds", model.remove_at(1))
		_expect("removal returns to three rows", rows.get_child_count() == 3)
		_expect("each model event publishes one collection update", updates[0] == 4)
		var trace: Dictionary = document.last_binding_trace()
		_expect("model event records localized collection strategy", trace.get("trigger", "") == "item_model" and trace.get("strategy", "") == "collection_patch")
		_expect("model patch builds no full-document candidate", int(trace.get("reconcile_stats", {}).get("full_document_candidates", -1)) == 0)
		_expect("model event rebuilds only repeats using that model", int(trace.get("reconcile_stats", {}).get("repeat_candidates", -1)) == 1)

		var stable_children := rows.get_children().duplicate()
		_expect("duplicate model key mutation is accepted by model", model.insert(0, {"id": "a", "name": "Duplicate", "css": "alpha"}))
		_expect("duplicate key aborts native patch atomically", rows.get_children() == stable_children and document.diagnostics.any(func(diagnostic): return "duplicated" in str(diagnostic.get("message", ""))))
		_expect("removing invalid duplicate repairs model", model.remove_at(0))
		_expect("repaired model resumes localized updates", rows.get_child_count() == 3 and document.last_binding_trace().get("success", false))

	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))
	await _test_radio_group_rebuild()
	await _test_radio_group_without_live_seed()
	await _test_radio_candidate_atomicity()
	await _test_nested_invalid_model_recovery()
	await _test_collection_accessibility_audit()
	await _test_repeat_ancestor_style_retention()
	await _test_document_reattach()
	if _failures.is_empty():
		print("GodotCascade collection scaling tests passed.")
		quit(0)
	else:
		for failure in _failures: push_error(failure)
		quit(1)


func _test_radio_group_rebuild() -> void:
	var markup_path := "user://cascade_collection_radio_group.gxml"
	var stylesheet_path := "user://cascade_collection_radio_group.gcss"
	_expect("write radio collection markup", _write(markup_path, """<Page>
	<RadioButton id="outside" text="Outside" group="shared" />
	<Repeat id="radio-rows" items="{model}" key="id">
		<RadioButton text="{item.name}" group="shared" />
	</Repeat>
</Page>"""))
	_expect("write radio collection stylesheet", _write(stylesheet_path, "Page { gap: 4px; }"))
	var model := ArrayItemModel.new([{"id": "one", "name": "One"}], func(item: Dictionary): return item["id"])
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"model": model}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("radio collection document loads", document.reload_document())
	var outside: BaseButton = document.get_element_by_id("outside")
	var rows: Control = document.get_element_by_id("radio-rows")
	_expect("initial radio crosses Repeat group boundary", outside.button_group == (rows.get_child(0) as BaseButton).button_group)
	_expect("radio collection insert succeeds", model.insert(1, {"id": "two", "name": "Two"}))
	_expect("localized rebuild retains document-wide radio group", outside.button_group == (rows.get_child(0) as BaseButton).button_group and outside.button_group == (rows.get_child(1) as BaseButton).button_group)
	outside.button_pressed = true
	(rows.get_child(1) as BaseButton).button_pressed = true
	_expect("cross-boundary radio exclusivity remains native", not outside.button_pressed and (rows.get_child(1) as BaseButton).button_pressed)
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_collection_accessibility_audit() -> void:
	var markup_path := "user://cascade_collection_accessibility.gxml"
	var stylesheet_path := "user://cascade_collection_accessibility.gcss"
	_expect("write accessibility collection markup", _write(markup_path, "<Page><Repeat id=\"rows\" items=\"{model}\" key=\"id\"><Button text=\"{item.name}\" /></Repeat></Page>"))
	_expect("write accessibility collection stylesheet", _write(stylesheet_path, "Page { gap: 0px; }"))
	var model := ArrayItemModel.new([], func(item: Dictionary): return item["id"])
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.audit_accessibility = true
	document.binding_context = {"model": model}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("empty accessibility collection loads", document.reload_document())
	_expect("empty Repeat has no inaccessible realized row", not document.diagnostics.any(func(diagnostic): return diagnostic.get("severity") == "warning" and "requires visible text" in str(diagnostic.get("message", ""))))
	_expect("accessible collection insert succeeds", model.insert(0, {"id": "blank", "name": "Named action"}))
	_expect("nonempty bound text avoids a false accessibility warning", not document.diagnostics.any(func(diagnostic): return diagnostic.get("severity") == "warning" and "requires visible text" in str(diagnostic.get("message", ""))))
	_expect("blank accessibility update enters model", model.update(0, {"id": "blank", "name": ""}))
	_expect("localized collection patch reruns accessibility audit (%s)" % [document.diagnostics], document.diagnostics.any(func(diagnostic): return diagnostic.get("path") == "collection" and diagnostic.get("severity") == "warning" and "requires visible text" in str(diagnostic.get("message", ""))))
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_radio_group_without_live_seed() -> void:
	var markup_path := "user://cascade_collection_radio_empty_seed.gxml"
	var stylesheet_path := "user://cascade_collection_radio_empty_seed.gcss"
	_expect("write empty-seed radio markup", _write(markup_path, """<Page>
	<Repeat id="left" items="{model}" key="id"><RadioButton text="{item.name}" group="shared" /></Repeat>
	<Repeat id="right" items="{model}" key="id"><RadioButton text="{item.name}" group="shared" /></Repeat>
</Page>"""))
	_expect("write empty-seed radio stylesheet", _write(stylesheet_path, "Page { gap: 2px; }"))
	var model := ArrayItemModel.new([], func(item: Dictionary): return item["id"])
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"model": model}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("empty-seed radio document loads", document.reload_document())
	_expect("shared-model radio insert succeeds", model.insert(0, {"id": "one", "name": "One"}))
	var left: BaseButton = document.get_element_by_id("left").get_child(0)
	var right: BaseButton = document.get_element_by_id("right").get_child(0)
	_expect("simultaneously created Repeat radios share one group", left.button_group != null and left.button_group == right.button_group)
	left.button_pressed = true
	right.button_pressed = true
	_expect("empty-seed radio group remains natively exclusive", not left.button_pressed and right.button_pressed)
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_radio_candidate_atomicity() -> void:
	var markup_path := "user://cascade_collection_radio_atomic.gxml"
	var stylesheet_path := "user://cascade_collection_radio_atomic.gcss"
	_expect("write atomic radio markup", _write(markup_path, """<Page>
	<RadioButton id="outside" text="Outside" group="shared" checked="true" />
	<Repeat id="candidate" items="{candidate_items}" key="id"><RadioButton text="{item.name}" group="shared" checked="true" /></Repeat>
	<Repeat id="invalid" items="{invalid_items}" key="id"><Label text="{item.name}" /></Repeat>
</Page>"""))
	_expect("write atomic radio stylesheet", _write(stylesheet_path, "Page { gap: 2px; }"))
	var candidate_items: Array = []
	var invalid_items: Array = [{"id": "stable", "name": "Stable"}]
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"candidate_items": candidate_items, "invalid_items": invalid_items}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("atomic radio document loads", document.reload_document())
	var outside: BaseButton = document.get_element_by_id("outside")
	var toggle_count := [0]
	outside.toggled.connect(func(_pressed: bool): toggle_count[0] += 1)
	candidate_items.append({"id": "candidate", "name": "Candidate"})
	invalid_items.append({"id": "stable", "name": "Duplicate"})
	_expect("multi-Repeat invalid patch is rejected", not document.refresh_bindings())
	_expect("off-tree radio candidate cannot mutate live selection", outside.button_pressed and toggle_count[0] == 0 and document.get_element_by_id("candidate").get_child_count() == 0)
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_nested_invalid_model_recovery() -> void:
	var markup_path := "user://cascade_nested_model_recovery.gxml"
	var stylesheet_path := "user://cascade_nested_model_recovery.gcss"
	_expect("write nested recovery markup", _write(markup_path, """<Page>
	<Repeat id="outer" items="{outer_model}" key="id"><Column>
		<Label text="{item.name}" />
		<Repeat id="nested" items="{nested_model}" key="id"><Label text="{item.name}" /></Repeat>
	</Column></Repeat>
</Page>"""))
	_expect("write nested recovery stylesheet", _write(stylesheet_path, "Page { gap: 0px; }"))
	var outer_model := ArrayItemModel.new([], func(item: Dictionary): return item["id"])
	var nested_a := ArrayItemModel.new([{"id": "a", "name": "A"}], func(item: Dictionary): return item["id"])
	var nested_b := ArrayItemModel.new([{"id": "b", "name": "B"}, {"id": "b", "name": "Duplicate"}], func(item: Dictionary): return item["id"])
	var context := {"outer_model": outer_model, "nested_model": nested_a}
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = context
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("nested recovery document loads", document.reload_document())
	context["nested_model"] = nested_b
	_expect("empty outer accepts unresolved nested model transition", document.refresh_binding_paths(PackedStringArray(["nested_model"])))
	_expect("first outer insertion exposing invalid nested model is atomic", outer_model.insert(0, {"id": "outer", "name": "Outer"}) and not bool(document.last_binding_trace().get("success", true)) and document.get_element_by_id("outer").get_child_count() == 0)
	_expect("repairing newly resolved nested model recovers automatically", nested_b.remove_at(1) and bool(document.last_binding_trace().get("success", false)) and document.get_element_by_id("nested").get_child_count() == 1 and str(document.get_element_by_id("nested").get_meta("cascade_repeat_keys", PackedStringArray())[0]) == "b")
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_repeat_ancestor_style_retention() -> void:
	var markup_path := "user://cascade_repeat_ancestor_style.gxml"
	var stylesheet_path := "user://cascade_repeat_ancestor_style.gcss"
	_expect("write ancestor-style markup", _write(markup_path, """<Page>
	<Column class="list">
		<Repeat id="styled-rows" items="{entries}" key="id">
			<Row><Label class="row-label" text="{item.name}" /></Row>
		</Repeat>
	</Column>
</Page>"""))
	_expect("write ancestor-style stylesheet", _write(stylesheet_path, """Page { color: #ff0000; font-size: 21px; --accent: #00ff00; }
.list .row-label { background-color: var(--accent); }"""))
	var entries := [{"id": "a", "name": "Alpha"}]
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"entries": entries}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("ancestor-style document loads", document.reload_document())
	var rows: Control = document.get_element_by_id("styled-rows")
	var initial_label: Control = rows.get_child(0).get_child(0)
	var initial_style: CascadeStyle = initial_label.get("cascade_style")
	_expect("Repeat row initially receives ancestor declarations", initial_label.get("text_color") == Color("ff0000") and is_equal_approx(float(initial_label.get("font_size")), 21.0) and initial_style.background_color == Color("00ff00"))
	entries.append({"id": "b", "name": "Beta"})
	_expect("ancestor-style collection patch succeeds", document.refresh_binding_paths(PackedStringArray(["entries"])))
	rows = document.get_element_by_id("styled-rows")
	_expect("ancestor-style patch materializes new row", rows.get_child_count() == 2)
	for row in rows.get_children():
		var label: Control = row.get_child(0)
		var style: CascadeStyle = label.get("cascade_style")
		_expect("localized Repeat rebuild retains inheritance, selector ancestry, and custom properties", label.get("text_color") == Color("ff0000") and is_equal_approx(float(label.get("font_size")), 21.0) and style.background_color == Color("00ff00"))
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _test_document_reattach() -> void:
	var markup_path := "user://cascade_document_reattach.gxml"
	var stylesheet_path := "user://cascade_document_reattach.gcss"
	_expect("write reattach markup", _write(markup_path, """<Page>
	<Label id="reattach-status" text="{status}" />
	<Repeat id="reattach-rows" items="{model}" key="id"><Label text="{item.name}" /></Repeat>
</Page>"""))
	_expect("write reattach stylesheet", _write(stylesheet_path, "Page { gap: 2px; }"))
	var state := {"status": "Before"}
	var model := ArrayItemModel.new([{"id": "a", "name": "Alpha"}], func(item: Dictionary): return item["id"])
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"status": state["status"], "model": model}
	document.markup_path = markup_path
	document.stylesheet_path = stylesheet_path
	root.add_child(document)
	_expect("reattach document loads", document.reload_document())
	root.remove_child(document)
	root.add_child(document)
	document.binding_context["status"] = "After"
	_expect("targeted refresh works immediately after reattach", document.refresh_binding_paths(PackedStringArray(["status"])) and document.get_element_by_id("reattach-status").get("text") == "After")
	_expect("item-model signals reconnect after reattach", model.insert(1, {"id": "b", "name": "Beta"}) and document.get_element_by_id("reattach-rows").get_child_count() == 2)
	document.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(markup_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stylesheet_path))


func _classes(control: Control) -> PackedStringArray:
	return control.get_meta("cascade_classes", PackedStringArray())


func _write(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	return true


func _expect(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
