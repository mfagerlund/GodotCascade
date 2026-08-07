extends SceneTree

const SHOWCASE_APP := preload("res://examples/showcase_app.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var app: Control = SHOWCASE_APP.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	await process_frame
	_expect_true("showcase app discovers all manifest pages", app.call("page_count") == 4)
	_expect_true("showcase app starts on layout foundation", app.call("current_page_id") == "layout-foundation")
	await _verify_layout_page(app)
	await _verify_system_status_page(app)
	await _verify_settings_page(app)
	await _verify_leaderboard_page(app)
	_expect_true("showcase app previous navigation works", await app.call("previous_page"))
	_expect_true("showcase app returns to settings", app.call("current_page_id") == "settings-menu")
	_expect_true("showcase app next navigation works", await app.call("next_page"))
	_expect_true("showcase app reloads current document", await app.call("reload_current_page"))
	_expect_true("showcase app reports connected page", str(app.call("current_status")).begins_with("Connected"))
	app.queue_free()
	await process_frame

	if _failures.is_empty():
		print("GodotCascade showcase app tests passed.")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _verify_layout_page(app: Control) -> void:
	_expect_true("layout page loads", await app.call("show_page", 0))
	var scene: Control = app.call("current_showcase_scene")
	_expect_document_ready("layout", scene)
	var inspect_button := _find_by_id(scene, "inspect")
	_expect_true("layout inspect button exists", inspect_button != null)
	if inspect_button != null:
		var inspect_instance := inspect_button.get_instance_id()
		inspect_button.emit_signal("pressed")
		await process_frame
		var status := _find_by_class(scene, "status")
		_expect_true("layout button reaches event context", status != null and status.get("text") == "Layout inspection requested")
		inspect_button = _find_by_id(scene, "inspect")
		_expect_true("layout bound class reload preserves button identity", inspect_button != null and inspect_button.get_instance_id() == inspect_instance)
		_expect_true("layout bound disabled state updates", inspect_button != null and inspect_button.get("disabled"))
		_expect_true("layout bound class rematches descendant style", status != null and status.get("text_color") == Color("65d6a7"))
		_expect_true("layout conditional creates native branch", _find_by_class(scene, "inspection-note") != null)


func _verify_system_status_page(app: Control) -> void:
	_expect_true("system status page loads", await app.call("show_page", 1))
	var scene: Control = app.call("current_showcase_scene")
	_expect_document_ready("system status", scene)
	var route_button := _find_by_id(scene, "route")
	_expect_true("system status route button exists", route_button != null)
	if route_button != null:
		route_button.emit_signal("pressed")
		await process_frame
		var sync_label := _find_by_class(scene, "sync")
		_expect_true("system status button refreshes bound status", sync_label != null and sync_label.get("text") == "Route review requested")


func _verify_settings_page(app: Control) -> void:
	_expect_true("settings page loads", await app.call("show_page", 2))
	var scene: Control = app.call("current_showcase_scene")
	_expect_document_ready("settings", scene)
	var profile := _find_by_id(scene, "profile-name")
	var select := _find_by_id(scene, "quality")
	var apply_button := _find_by_id(scene, "apply")
	var shadows := _find_by_id(scene, "shadows") as BaseButton
	var scale := _find_by_id(scene, "ui-scale")
	var windowed := _find_by_id(scene, "windowed") as BaseButton
	var borderless := _find_by_id(scene, "borderless") as BaseButton
	var first_channel := _find_by_class(scene, "channel-setting") as BaseButton
	_expect_true("settings interactive controls exist", profile != null and select != null and apply_button != null and shadows != null and scale != null and windowed != null and borderless != null and first_channel != null)
	if profile == null or select == null or apply_button == null or shadows == null or scale == null or windowed == null or borderless == null or first_channel == null:
		return
	shadows.button_pressed = false
	shadows.emit_signal("toggled", false)
	windowed.button_pressed = true
	var state: Object = scene.get("binding_context")
	var settings: Object = state.get("settings")
	_expect_true("settings showcase uses typed object state", state is ShowcaseSettingsMenuState and settings is ShowcaseSettingsMenuState.SettingsState)
	_expect_true("settings checkbox writes through its connection", not bool(settings.get("shadows")))
	var bound_shadows := _find_by_id(scene, "bound-shadows")
	_expect_true("settings checkbox refreshes dependent bound output", bound_shadows != null and bound_shadows.get("text") == "false")
	_expect_true("settings native radio group selects one option", windowed.button_pressed and not borderless.button_pressed)
	_expect_true("settings HUD channel exposes its label as one control", first_channel.get("text") == "Damage numbers")
	first_channel.button_pressed = false
	first_channel.emit_signal("toggled", false)
	var channels: Array = settings.get("hud_channels")
	_expect_true("settings HUD channel row writes through its connection", not bool(channels[0].get("enabled")))
	profile.set("text", "Nova")
	profile.emit_signal("text_changed", "Nova")
	var bound_profile := _find_by_id(scene, "bound-profile")
	_expect_true("settings text input refreshes dependent bound output", bound_profile != null and bound_profile.get("text") == "Nova")
	scale.set("value", 115.0)
	await process_frame
	var bound_scale := _find_by_id(scene, "bound-scale")
	_expect_true("settings slider refreshes dependent bound output", bound_scale != null and bound_scale.get("text") == "115.0")
	select.call("select_value", "ultra", true)
	await process_frame
	var bound_quality := _find_by_id(scene, "bound-quality")
	_expect_true("settings select refreshes dependent bound output", bound_quality != null and bound_quality.get("text") == "ultra")
	# Binding refreshes may reconcile native controls, so resolve the live button
	# immediately before exercising its document event connection.
	apply_button = _find_by_id(scene, "apply")
	var status := _find_by_id(scene, "settings-status")
	_expect_true("settings Apply button remains connected", apply_button != null and apply_button.is_inside_tree())
	if apply_button == null or not apply_button.is_inside_tree():
		return
	apply_button.emit_signal("pressed")
	var immediate_status := str(status.get("text")) if status != null else "<missing>"
	await process_frame
	status = _find_by_id(scene, "settings-status")
	var actual_status := str(status.get("text")) if status != null else "<missing>"
	if actual_status != "Applied ultra quality for Nova":
		var event_connections: Array = apply_button.get_meta("cascade_event_connections", [])
		var event_method := str(event_connections[0]["callable"].get_method()) if not event_connections.is_empty() else "<none>"
		var context_status := str(state.get("ui").get("status"))
		_failures.append("settings bindings and Apply connection complete: expected 'Applied ultra quality for Nova', got immediate '%s', final '%s', context '%s'; signal connections=%s event method=%s valid=%s blocked=%s" % [immediate_status, actual_status, context_status, apply_button.get_signal_connection_list("pressed").size(), event_method, event_connections[0]["callable"].is_valid() if not event_connections.is_empty() else false, apply_button.is_blocking_signals()])


func _verify_leaderboard_page(app: Control) -> void:
	_expect_true("leaderboard page loads", await app.call("show_page", 3))
	var scene: Control = app.call("current_showcase_scene")
	_expect_document_ready("leaderboard", scene)
	var table := _find_by_id(scene, "leaderboard")
	var scroll := _find_by_id(scene, "leaderboard-scroll") as ScrollContainer
	var add_button := _find_by_id(scene, "add-pilot")
	var sort_button := _find_by_id(scene, "sort-rating")
	var pilots := _find_all_by_class(scene, "pilot-cell")
	_expect_true("leaderboard native table, scroll viewport, and collection controls exist", table != null and scroll != null and add_button != null and sort_button != null and pilots.size() == 5)
	if table == null or scroll == null or add_button == null or sort_button == null or pilots.size() != 5:
		return
	_expect_true("leaderboard starts with bound first pilot", pilots[0].get("text") == "Rhea Sol")
	add_button.emit_signal("pressed")
	await process_frame
	await process_frame
	var status := _find_by_id(scene, "leaderboard-status")
	pilots = _find_all_by_class(scene, "pilot-cell")
	_expect_true("leaderboard add event creates a keyed row", pilots.size() == 6 and pilots[-1].get("text") == "Nia Ward")
	_expect_true("leaderboard add event refreshes bound status", status != null and str(status.get("text")).begins_with("Added Nia Ward"))
	for _index in 2:
		add_button = _find_by_id(scene, "add-pilot")
		add_button.emit_signal("pressed")
		await process_frame
		await process_frame
	scroll = _find_by_id(scene, "leaderboard-scroll") as ScrollContainer
	pilots = _find_all_by_class(scene, "pilot-cell")
	_expect_true("leaderboard accepts additional keyed rows", pilots.size() == 8)
	_expect_true("leaderboard automatically scrolls overflowing rows", scroll != null and scroll.get_v_scroll_bar().visible and scroll.get_v_scroll_bar().max_value > scroll.size.y)

	var remove_buttons := _find_all_by_class(scene, "remove-pilot")
	_expect_true("leaderboard wires one remove action per row", remove_buttons.size() == 8)
	if not remove_buttons.is_empty():
		remove_buttons[0].emit_signal("pressed")
		await process_frame
		await process_frame
		pilots = _find_all_by_class(scene, "pilot-cell")
		_expect_true("leaderboard remove action deletes its keyed row", pilots.size() == 7 and pilots[0].get("text") == "Milo Vance")

	scene.set("_drag_source_id", "nia-1")
	var target_row := pilots[0].get_parent() as Control
	scene.call("_update_drag_target", target_row.get_global_rect().get_center())
	scene.call("_commit_pointer_drag")
	await process_frame
	await process_frame
	pilots = _find_all_by_class(scene, "pilot-cell")
	_expect_true("leaderboard pointer reorder moves keyed rows", pilots.size() == 7 and pilots[0].get("text") == "Nia Ward")

	sort_button = _find_by_id(scene, "sort-rating")
	sort_button.emit_signal("pressed")
	await process_frame
	await process_frame
	pilots = _find_all_by_class(scene, "pilot-cell")
	var ranks := _find_all_by_class(scene, "rank-cell")
	_expect_true("leaderboard sort restores descending rating order", pilots.size() == 7 and pilots[0].get("text") == "Milo Vance")
	_expect_true("leaderboard sort reranks rows", ranks.size() == 7 and ranks[0].get("text") == "1")


func _expect_document_ready(label: String, scene: Control) -> void:
	_expect_true("%s scene instantiated" % label, scene != null)
	if scene == null:
		return
	_expect_true("%s generated native root" % label, scene.call("generated_root") != null)
	var diagnostics: Array = scene.get("diagnostics")
	_expect_true("%s has no build errors" % label, not diagnostics.any(func(item): return item.get("severity", "error") == "error"))


func _find_by_id(node: Node, element_id: String) -> Control:
	if node is Control and node.get_meta("cascade_id", "") == element_id:
		return node
	for child in node.get_children():
		var found := _find_by_id(child, element_id)
		if found != null:
			return found
	return null


func _find_by_class(node: Node, selector_class: String) -> Control:
	if node is Control and selector_class in node.get_meta("cascade_classes", PackedStringArray()):
		return node
	for child in node.get_children():
		var found := _find_by_class(child, selector_class)
		if found != null:
			return found
	return null


func _find_all_by_class(node: Node, selector_class: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and selector_class in node.get_meta("cascade_classes", PackedStringArray()):
		matches.append(node)
	for child in node.get_children():
		matches.append_array(_find_all_by_class(child, selector_class))
	return matches


func _expect_true(label: String, condition: bool) -> void:
	if not condition:
		_failures.append("%s: expected true" % label)
