@tool
extends Control

## Loads paired GXML/GCSS files and builds a native Godot Control tree.

signal diagnostics_changed(diagnostics: Array[Dictionary])
signal binding_value_changed(path: String, value: Variant, control: Control)
signal binding_trace_changed(trace: Dictionary)
signal validation_changed(valid: bool, diagnostics: Array[Dictionary])
signal document_reloaded(root: Control)
signal collection_updated(repeats: Array[Control], stats: Dictionary)

const GxmlParser := preload("res://addons/godot_cascade/markup/gxml_parser.gd")
const GcssParser := preload("res://addons/godot_cascade/style/gcss_parser.gd")
const CascadeBuilder := preload("res://addons/godot_cascade/runtime/cascade_builder.gd")
const CascadeReconciler := preload("res://addons/godot_cascade/runtime/cascade_reconciler.gd")
const BindingResolver := preload("res://addons/godot_cascade/runtime/binding_resolver.gd")
const ObservableBindingContext := preload("res://addons/godot_cascade/runtime/observable_binding_context.gd")
const ComponentRegistry := preload("res://addons/godot_cascade/runtime/component_registry.gd")
const AccessibilityAudit := preload("res://addons/godot_cascade/runtime/accessibility_audit.gd")
const FocusManager := preload("res://addons/godot_cascade/runtime/focus_manager.gd")
const BindingTrace := preload("res://addons/godot_cascade/runtime/binding_trace.gd")
const CascadeItemModel := preload("res://addons/godot_cascade/runtime/cascade_item_model.gd")
const CascadeCollectionChange := preload("res://addons/godot_cascade/runtime/collection_change.gd")
const CascadeVirtualWindow := preload("res://addons/godot_cascade/runtime/virtual_window.gd")
const CascadeTable := preload("res://addons/godot_cascade/components/cascade_table.gd")

@export_file("*.gxml") var markup_path := "":
	set(value):
		markup_path = value
		_request_reload()
@export_file("*.gcss") var stylesheet_path := "":
	set(value):
		stylesheet_path = value
		_request_reload()
@export var load_on_ready := true
@export var log_diagnostics_to_console := true
@export var watch_sources := true:
	set(value):
		watch_sources = value
		if is_inside_tree():
			set_process(watch_sources)
@export_range(0.05, 5.0, 0.05) var watch_interval := 0.25
@export var audit_accessibility := true
@export var wrap_focus_navigation := false

var diagnostics: Array[Dictionary] = []
var last_reconcile_stats := {"reused": 0, "created": 0, "replaced": 0, "removed": 0}
var last_collection_stats: Dictionary = {}
var binding_context: Variant:
	set(value):
		_disconnect_binding_observable()
		binding_context = value
		_connect_binding_observable()
		if _generated_root != null:
			_refresh_all_bindings("context_changed")
var event_context: Object:
	set(value):
		event_context = value
		if _generated_root != null:
			refresh_events()
var _generated_root: Control
var _reload_queued := false
var _watch_elapsed := 0.0
var _source_signatures := {}
var _published_diagnostic_keys := {}
var _last_build_size := Vector2.ZERO
var _applying_bindings := false
var _binding_trace_sequence := 0
var _last_binding_trace: Dictionary = {}
var _active_focus_trap: Control
var _focus_before_trap: WeakRef
var _focus_redirecting := false
var _suppress_focus_contract_refresh := false
var _item_model_connections: Array[Dictionary] = []
var _pending_item_models: Array[CascadeItemModel] = []
var _collection_transaction_blocked := false
var _virtual_scroll_connections: Array[Dictionary] = []
var _binding_targets_by_path: Dictionary = {}
var _dependency_targets_by_path: Dictionary = {}
var _dependency_index_order := 0
var _traced_controls: Array[Control] = []


func _ready() -> void:
	set_process(watch_sources)
	resized.connect(_on_document_resized)
	if not get_viewport().gui_focus_changed.is_connected(_on_viewport_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_viewport_focus_changed)
	if load_on_ready:
		reload_document()
	else:
		_capture_source_signatures()


func _exit_tree() -> void:
	_disconnect_virtual_scrolls()
	_disconnect_item_models()
	_binding_targets_by_path.clear()
	_dependency_targets_by_path.clear()
	_traced_controls.clear()
	if _generated_root != null:
		ComponentRegistry.unmount_tree(_generated_root)


func _process(delta: float) -> void:
	_watch_elapsed += delta
	if _watch_elapsed < watch_interval:
		return
	_watch_elapsed = 0.0
	poll_sources()


func _on_document_resized() -> void:
	if _generated_root == null or size.x <= 0.0 or size.is_equal_approx(_last_build_size) or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


func reload_document() -> bool:
	_reload_queued = false
	diagnostics = []
	_capture_source_signatures()
	var markup_source := _read_source(markup_path, "GXML")
	var stylesheet_source := _read_source(stylesheet_path, "GCSS")
	if markup_source.is_empty() or stylesheet_source.is_empty():
		_publish_diagnostics()
		return false

	var markup_result := GxmlParser.parse(markup_source)
	_append_diagnostics(markup_result["diagnostics"], markup_path)
	var style_result := GcssParser.parse(stylesheet_source)
	_append_diagnostics(style_result["diagnostics"], stylesheet_path)
	if _has_errors() or markup_result["root"] == null:
		_publish_diagnostics()
		return false

	_last_build_size = size
	var build_result := CascadeBuilder.build(markup_result["root"], style_result["rules"], _binding_root_context(), size)
	_append_diagnostics(build_result["diagnostics"], "builder")
	if _has_errors() or build_result["root"] == null:
		if build_result["root"] != null:
			build_result["root"].free()
		_publish_diagnostics()
		return false

	var desired_root: Control = build_result["root"]
	_apply_bindings(desired_root)
	for diagnostic in _validate_virtual_contracts(desired_root):
		diagnostic["path"] = markup_path
		diagnostics.append(diagnostic)
	if _has_errors():
		desired_root.free()
		_publish_diagnostics()
		return false
	var initial_mount := _generated_root == null
	_stamp_source_path(desired_root)
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	if _generated_root == null:
		_generated_root = desired_root
		add_child(_generated_root)
		_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ComponentRegistry.mount_tree(_generated_root)
		last_reconcile_stats = {"reused": 0, "created": 1, "replaced": 0, "removed": 0}
	else:
		var result := CascadeReconciler.reconcile(_generated_root, desired_root)
		last_reconcile_stats = result["stats"]
		if not result["reused_root"]:
			remove_child(_generated_root)
			_generated_root.queue_free()
			_generated_root = result["root"]
			add_child(_generated_root)
			_generated_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ComponentRegistry.mount_tree(_generated_root)
	BindingTrace.clear(_generated_root)
	_last_binding_trace = {}
	_traced_controls.clear()
	_rebuild_binding_target_index()
	_suppress_focus_contract_refresh = true
	_refresh_bindings(false)
	_applying_bindings = was_applying_bindings
	_refresh_writable_bindings(false)
	_refresh_events(false)
	_refresh_item_model_connections(true)
	_pending_item_models.clear()
	_collection_transaction_blocked = false
	_refresh_virtual_scroll_connections.call_deferred()
	_suppress_focus_contract_refresh = false
	_refresh_focus_contracts(initial_mount)
	if audit_accessibility:
		for diagnostic in AccessibilityAudit.audit(_generated_root):
			var stamped: Dictionary = diagnostic.duplicate()
			stamped["path"] = markup_path
			stamped["category"] = "accessibility"
			diagnostics.append(stamped)
	document_reloaded.emit(_generated_root)
	_publish_diagnostics()
	return true


## Checks source contents immediately and reloads when either file changed.
## The regular watcher calls this on an interval; tooling and tests may call it directly.
func poll_sources() -> bool:
	var current_signatures := _read_source_signatures()
	if current_signatures == _source_signatures:
		return false
	_source_signatures = current_signatures
	reload_document()
	return true


func generated_root() -> Control:
	return _generated_root


## Latest named/full binding refresh trace for runtime and editor tooling.
## Only the most recent trace is retained.
func last_binding_trace() -> Dictionary:
	return _last_binding_trace.duplicate(true)


func collection_stats() -> Dictionary:
	return last_collection_stats.duplicate(true)


## Returns the uniquely matching authored id, or null when it is absent or
## appears in more than one reusable-component scope.
func get_element_by_id(element_id: String) -> Control:
	var matches: Array[Control] = []
	_collect_elements_by_metadata(_generated_root, "cascade_id", element_id, matches)
	return matches[0] if matches.size() == 1 else null


## Returns an element by its component-qualified id, such as `audio/title`.
func get_element_by_scoped_id(scoped_id: String) -> Control:
	var matches: Array[Control] = []
	_collect_elements_by_metadata(_generated_root, "cascade_scoped_id", scoped_id, matches)
	return matches[0] if matches.size() == 1 else null


func _refresh_focus_contracts(initial_mount: bool) -> void:
	if _generated_root == null:
		return
	var previous_trap := _active_focus_trap
	var next_trap := FocusManager.active_trap(_generated_root)
	var focus_owner := get_viewport().gui_get_focus_owner()
	if previous_trap == null and next_trap != null and focus_owner is Control and not FocusManager.contains(next_trap, focus_owner):
		_focus_before_trap = weakref(focus_owner)
	_active_focus_trap = next_trap
	FocusManager.apply_navigation(_generated_root, wrap_focus_navigation)

	if previous_trap != null and next_trap == null:
		_restore_focus_before_trap()
		return
	var newly_activated := next_trap != null and previous_trap != next_trap
	if initial_mount or newly_activated:
		var scope := next_trap if next_trap != null else _generated_root
		var target := FocusManager.autofocus_target(scope)
		if target == null and newly_activated:
			target = FocusManager.first_focusable(scope)
		if target != null:
			target.call_deferred("grab_focus")
	elif next_trap != null and (not focus_owner is Control or not FocusManager.contains(next_trap, focus_owner)):
		_redirect_focus_to_trap.call_deferred()


func _on_viewport_focus_changed(control: Control) -> void:
	_refresh_released_virtual_focus_pins.call_deferred()
	if not _focus_redirecting and _active_focus_trap != null and control != null and not FocusManager.contains(_active_focus_trap, control):
		_redirect_focus_to_trap.call_deferred()


func _redirect_focus_to_trap() -> void:
	if _active_focus_trap == null or not is_instance_valid(_active_focus_trap):
		return
	var target := FocusManager.autofocus_target(_active_focus_trap)
	if target == null:
		target = FocusManager.first_focusable(_active_focus_trap)
	if target == null:
		return
	_focus_redirecting = true
	target.grab_focus()
	_focus_redirecting = false


func _restore_focus_before_trap() -> void:
	if _focus_before_trap == null:
		return
	var target = _focus_before_trap.get_ref()
	_focus_before_trap = null
	if target is Control and is_instance_valid(target) and target.is_inside_tree() and target.visible and target.focus_mode != Control.FOCUS_NONE:
		target.call_deferred("grab_focus")


## Reapplies every {dot.separated.path} binding to the existing native tree.
## Call this after mutating binding_context; compatible controls keep identity.
func refresh_bindings() -> bool:
	return _refresh_all_bindings("manual")


## Reapplies only bindings that overlap one of the named paths.
## Parent and child paths overlap: invalidating `settings` refreshes
## `settings.profile`, and invalidating `settings.profile.name` also refreshes
## a control bound to `settings.profile`.
func refresh_binding_paths(paths: PackedStringArray) -> bool:
	return _refresh_named_bindings(paths, "manual")


func _refresh_all_bindings(trigger: String, publish: bool = true) -> bool:
	var strategy := "targeted"
	var reason := "property"
	var success: bool
	if _generated_root != null and _tree_has_rebuild_binding_outside_repeat(_generated_root):
		strategy = "reconcile"
		reason = "rebuild_dependency"
		success = reload_document()
	elif _generated_root != null and _contains_element(_generated_root, "repeat"):
		strategy = "collection_patch"
		reason = "collection"
		success = _refresh_collections(publish)
	else:
		success = _refresh_bindings(publish)
	_record_binding_trace(PackedStringArray(["*"]), trigger, strategy, reason, success)
	return success


func _refresh_named_bindings(paths: PackedStringArray, trigger: String, publish: bool = true, reconcile_collections: bool = true) -> bool:
	var normalized := _normalized_binding_paths(paths)
	if normalized.is_empty():
		return false
	if "*" in normalized:
		return _refresh_all_bindings(trigger, publish)
	var strategy := "targeted"
	var reason := "property"
	var success: bool
	if _generated_root != null and _indexed_requires_full_reconcile(normalized):
		strategy = "reconcile"
		reason = "rebuild_dependency"
		success = reload_document()
	elif _generated_root != null and reconcile_collections and _indexed_requires_collection_patch(normalized):
		strategy = "collection_patch"
		reason = "collection"
		var matching_repeats: Array[Control] = []
		_collect_matching_outer_repeats(_generated_root, normalized, matching_repeats)
		var retained_reorder := _try_retained_array_reorder(matching_repeats, normalized, publish)
		success = bool(retained_reorder["success"]) if bool(retained_reorder["handled"]) else _refresh_collections(publish, matching_repeats)
	else:
		success = _refresh_binding_paths(normalized, publish)
	_record_binding_trace(normalized, trigger, strategy, reason, success)
	return success


func _try_retained_array_reorder(repeats: Array[Control], paths: PackedStringArray, publish: bool) -> Dictionary:
	if repeats.is_empty() or _collection_transaction_blocked:
		return {"handled": false, "success": false}
	var plans: Array[Dictionary] = []
	var scanned_keys := 0
	for repeat in repeats:
		if bool(repeat.get_meta("cascade_virtual", false)) or not bool(repeat.get_meta("cascade_collection_is_array", false)):
			return {"handled": false, "success": false}
		var element: Variant = repeat.get_meta("cascade_repeat_element") if repeat.has_meta("cascade_repeat_element") else null
		if element == null or element.children.size() != 1 or _element_tree_has_condition(element.children[0]):
			return {"handled": false, "success": false}
		var collection_path := str(repeat.get_meta("cascade_collection_binding", ""))
		var resolved := BindingResolver.resolve(_binding_context_for(repeat, collection_path), collection_path)
		var collection: Variant = resolved.get("value") if resolved.get("found", false) else null
		if not collection is Array:
			return {"handled": false, "success": false}
		var old_keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray())
		var rows: Array[Control] = []
		for child in repeat.get_children():
			if child is Control:
				rows.append(child)
		if rows.size() != old_keys.size() or collection.size() != old_keys.size():
			return {"handled": false, "success": false}
		var key_property := _repeat_key_property(repeat)
		var new_keys := PackedStringArray()
		var new_items: Array = []
		var seen_keys: Dictionary = {}
		for index in collection.size():
			scanned_keys += 1
			var item: Variant = collection[index]
			var key_result := BindingResolver.resolve(item, key_property) if not key_property.is_empty() else {"found": true, "value": index}
			if not bool(key_result.get("found", false)):
				return {"handled": false, "success": false}
			var item_key := str(key_result["value"])
			if seen_keys.has(item_key):
				return {"handled": false, "success": false}
			seen_keys[item_key] = true
			new_keys.append(item_key)
			new_items.append(item)
		var ordered_rows: Array[Control] = []
		for index in new_keys.size():
			var old_index := old_keys.find(new_keys[index])
			if old_index < 0:
				return {"handled": false, "success": false}
			var row := rows[old_index]
			var scope: Dictionary = row.get_meta("cascade_binding_scope", {})
			if not scope.has("item") or not is_same(scope["item"], new_items[index]):
				return {"handled": false, "success": false}
			if _tree_has_rebuild_binding(row) or _tree_has_focus_validation_contract(row) or _contains_element(row, "repeat"):
				return {"handled": false, "success": false}
			ordered_rows.append(row)
		plans.append({"repeat": repeat, "rows": ordered_rows, "keys": new_keys, "items": new_items, "reordered": new_keys != old_keys})

	# Match normal collection reconciliation: recovered row-binding and
	# collection-audit diagnostics must disappear before fresh results append.
	diagnostics = diagnostics.filter(func(diagnostic):
		if diagnostic.get("path", "") == "collection" or diagnostic.get("category", "") == "accessibility":
			return false
		return diagnostic.get("path", "") != "binding" or not _binding_path_matches(
			str(diagnostic.get("binding_path", "")),
			PackedStringArray(["item", "index"])
		)
	)
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	var reused_rows := 0
	var retained_reorders := 0
	for plan in plans:
		var repeat: Control = plan["repeat"]
		var ordered_rows: Array[Control] = plan["rows"]
		var items: Array = plan["items"]
		for index in ordered_rows.size():
			var row := ordered_rows[index]
			row.set_meta("cascade_repeat_index", index)
			_update_retained_repeat_scope(row, items[index], index)
			# A collection invalidation may combine a reorder with in-place item
			# mutations. Refresh every scoped item/index property while retaining
			# structure; otherwise unchanged key order could hide changed values.
			_apply_bindings(row, PackedStringArray(["item", "index"]))
			repeat.move_child(row, index)
			reused_rows += 1
		if bool(plan["reordered"]):
			retained_reorders += 1
		repeat.set_meta("cascade_repeat_keys", plan["keys"])
		repeat.set_meta("cascade_array_key_cache_valid", true)
		repeat.set_meta("cascade_collection_transaction_valid", true)
		if repeat is Container:
			(repeat as Container).queue_sort()
		if repeat.get_parent() is Container:
			(repeat.get_parent() as Container).queue_sort()
	_applying_bindings = was_applying_bindings
	_rebuild_binding_target_index()
	_refresh_binding_paths(paths, false)
	_refresh_focus_contracts(false)
	if audit_accessibility:
		_append_accessibility_diagnostics(AccessibilityAudit.audit(_generated_root), "collection")
	last_reconcile_stats = {
		"reused": reused_rows,
		"created": 0,
		"replaced": 0,
		"removed": 0,
		"repeat_candidates": 0,
		"candidate_native_controls": 0,
		"full_document_candidates": 0,
		"keys_scanned": scanned_keys,
		"retained_array_refreshes": plans.size(),
		"retained_reorders": retained_reorders,
	}
	last_collection_stats = last_reconcile_stats.duplicate(true)
	var patched: Array[Control] = []
	for plan in plans:
		patched.append(plan["repeat"])
	collection_updated.emit(patched, last_collection_stats.duplicate(true))
	if publish:
		_publish_diagnostics()
	return {"handled": true, "success": not _has_errors()}


func _update_retained_repeat_scope(node: Node, item: Variant, index: int) -> void:
	if node is Control:
		var scope: Dictionary = node.get_meta("cascade_binding_scope", {})
		if scope.has("item") and scope.has("index"):
			scope["item"] = item
			scope["index"] = index
			node.set_meta("cascade_binding_scope", scope)
	for child in node.get_children():
		_update_retained_repeat_scope(child, item, index)


func _refresh_collections(publish: bool, requested_repeats: Array[Control] = [], preserve_anchor: bool = true) -> bool:
	if not preserve_anchor and _collection_transaction_blocked:
		last_reconcile_stats = _failed_collection_delta_stats(requested_repeats, 0)
		last_collection_stats = last_reconcile_stats.duplicate(true)
		if publish:
			_publish_diagnostics()
		return false
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "collection" and diagnostic.get("category", "") != "accessibility")
	var repeats: Array[Control] = requested_repeats.duplicate()
	if preserve_anchor and _collection_transaction_blocked:
		repeats.clear()
		_collect_outer_repeats(_generated_root, repeats)
	if repeats.is_empty():
		_collect_outer_repeats(_generated_root, repeats)
	if repeats.is_empty():
		return _refresh_bindings(publish)
	var candidates: Array[Dictionary] = []
	var anchors := {}
	var candidate_button_groups: Dictionary = {}
	for repeat in repeats:
		_prepare_virtual_focus_pin(repeat)
		if preserve_anchor and bool(repeat.get_meta("cascade_virtual", false)):
			anchors[repeat.get_instance_id()] = _capture_virtual_anchor(repeat)
		var key_cache := _validated_virtual_model_key_cache(repeat)
		if (
			not key_cache is Array
			and not preserve_anchor
			and bool(repeat.get_meta("cascade_virtual", false))
			and bool(repeat.get_meta("cascade_collection_is_array", false))
			and bool(repeat.get_meta("cascade_array_key_cache_valid", false))
		):
			# A scroll-only rebuild does not represent a collection invalidation.
			# Reuse the already validated full key list for Array-backed virtual
			# repeats instead of rereading every item on every window shift.
			key_cache = Array(repeat.get_meta("cascade_repeat_keys", PackedStringArray()))
		var build := CascadeBuilder.rebuild_repeat(
			repeat,
			_binding_root_context(),
			size,
			key_cache,
			int(repeat.get_meta("cascade_item_model_delta_keys_scanned", 0)) if key_cache is Array else -1,
			candidate_button_groups
		)
		_append_collection_diagnostics(build["diagnostics"])
		if build["root"] != null:
			var desired: Control = build["root"]
			var repeat_keys_scanned := int(desired.get_meta("cascade_repeat_keys_scanned", 0))
			var anchor: Dictionary = anchors.get(repeat.get_instance_id(), {})
			if not anchor.is_empty():
				var desired_keys: PackedStringArray = desired.get_meta("cascade_repeat_keys", PackedStringArray())
				var anchor_index := desired_keys.find(str(anchor["key"]))
				if anchor_index >= 0:
					var anchored_offset := float(anchor_index) * float(repeat.get_meta("cascade_virtual_item_extent", 1.0)) + float(anchor["pixel_offset"])
					if not is_equal_approx(anchored_offset, float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))):
						desired.free()
						repeat.set_meta("cascade_virtual_scroll_offset", anchored_offset)
						build = CascadeBuilder.rebuild_repeat(
							repeat,
							_binding_root_context(),
							size,
							key_cache,
							int(repeat.get_meta("cascade_item_model_delta_keys_scanned", 0)) if key_cache is Array else -1,
							candidate_button_groups
						)
						_append_collection_diagnostics(build["diagnostics"])
						desired = build["root"]
						if desired == null:
							continue
						if not key_cache is Array:
							repeat_keys_scanned += int(desired.get_meta("cascade_repeat_keys_scanned", 0))
			_apply_bindings(desired)
			_append_collection_diagnostics(FocusManager.validate(desired))
			_append_collection_diagnostics(_validate_virtual_repeat_candidate(desired))
			_stamp_source_path(desired)
			candidates.append({"existing": repeat, "desired": desired, "anchor": anchor, "keys_scanned": repeat_keys_scanned})
	var collection_has_errors := diagnostics.any(func(diagnostic): return diagnostic.get("path", "") == "collection" and diagnostic.get("severity", "error") == "error")
	if collection_has_errors or candidates.size() != repeats.size():
		_collection_transaction_blocked = true
		_pending_item_models = _resolved_item_models_for_repeats(repeats)
		for candidate in candidates:
			_collect_item_models(candidate["desired"], _pending_item_models)
		var all_repeats: Array[Control] = []
		_collect_outer_repeats(_generated_root, all_repeats)
		for blocked_repeat in all_repeats:
			blocked_repeat.set_meta("cascade_collection_transaction_valid", false)
			if bool(blocked_repeat.get_meta("cascade_collection_is_array", false)):
				blocked_repeat.set_meta("cascade_array_key_cache_valid", false)
		var failed_keys_scanned := 0
		var failed_candidate_controls := 0
		for candidate in candidates:
			failed_keys_scanned += int(candidate.get("keys_scanned", 0))
			failed_candidate_controls += _count_controls(candidate["desired"])
			candidate["desired"].free()
		var failed_stats := _failed_collection_delta_stats(repeats, failed_keys_scanned)
		failed_stats["repeat_candidates"] = candidates.size()
		failed_stats["candidate_native_controls"] = failed_candidate_controls
		last_reconcile_stats = failed_stats
		last_collection_stats = failed_stats.duplicate(true)
		for repeat in repeats:
			var anchor: Dictionary = anchors.get(repeat.get_instance_id(), {})
			if anchor.has("original_scroll_offset"):
				repeat.set_meta("cascade_virtual_scroll_offset", anchor["original_scroll_offset"])
		_refresh_item_model_connections()
		if publish:
			_publish_diagnostics()
		return false

	var candidate_native_controls := 0
	for candidate in candidates:
		candidate_native_controls += _count_controls(candidate["desired"])
	var live_button_groups := CascadeBuilder.collect_button_groups(_generated_root)
	for candidate in candidates:
		CascadeBuilder.remap_button_groups(candidate["desired"], live_button_groups)
	var combined := {"reused": 0, "created": 0, "replaced": 0, "removed": 0, "repeat_candidates": candidates.size(), "candidate_native_controls": candidate_native_controls, "full_document_candidates": 0, "keys_scanned": 0}
	var patched: Array[Control] = []
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	for candidate in candidates:
		var existing: Control = candidate["existing"]
		combined["keys_scanned"] = int(combined["keys_scanned"]) + int(candidate.get("keys_scanned", 0))
		_copy_full_scan_item_model_cache(candidate["desired"], existing)
		if not candidate["desired"].has_meta("cascade_collection_model"):
			_clear_item_model_key_cache(existing)
		var result := CascadeReconciler.reconcile(existing, candidate["desired"])
		for name in ["reused", "created", "replaced", "removed"]:
			combined[name] = int(combined[name]) + int(result["stats"].get(name, 0))
		patched.append(result["root"])
	var virtual_ranges: Array[Dictionary] = []
	var model_count := 0
	var realized_count := 0
	var pinned_count := 0
	for repeat in patched:
		repeat.set_meta("cascade_collection_transaction_valid", true)
		repeat.set_meta("cascade_item_model_delta_keys_scanned", 0)
		if not bool(repeat.get_meta("cascade_virtual", false)):
			continue
		model_count += int(repeat.get_meta("cascade_virtual_model_count", 0))
		realized_count += int(repeat.get_meta("cascade_virtual_realized_count", 0))
		if int(repeat.get_meta("cascade_virtual_pinned_index", -1)) >= 0:
			pinned_count += 1
		virtual_ranges.append({"first": int(repeat.get_meta("cascade_virtual_first_index", 0)), "end": int(repeat.get_meta("cascade_virtual_end_index", 0))})
	combined["model_count"] = model_count
	combined["realized_count"] = realized_count
	combined["pinned_focus_count"] = pinned_count
	combined["virtual_ranges"] = virtual_ranges
	last_reconcile_stats = combined
	last_collection_stats = combined.duplicate(true)
	_rebuild_binding_target_index()
	_suppress_focus_contract_refresh = true
	_refresh_bindings(false)
	_applying_bindings = was_applying_bindings
	_refresh_writable_bindings(false)
	_refresh_events(false)
	if audit_accessibility:
		_append_accessibility_diagnostics(AccessibilityAudit.audit(_generated_root), "collection")
	_pending_item_models.clear()
	_collection_transaction_blocked = false
	_refresh_item_model_connections()
	_refresh_virtual_scroll_connections.call_deferred()
	_suppress_focus_contract_refresh = false
	_refresh_focus_contracts(false)
	for candidate in candidates:
		_restore_virtual_anchor(candidate["existing"], candidate.get("anchor", {}))
	collection_updated.emit(patched, combined.duplicate(true))
	if publish:
		_publish_diagnostics()
	return not collection_has_errors


## Reconnects authored on-* signal bindings without disturbing user connections.
func refresh_events() -> bool:
	return _refresh_events(true)


## Validates generated controls and publishes source-aware validation diagnostics.
func validate() -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "validation")
	if _generated_root != null:
		_validate_node(_generated_root)
	var valid := not diagnostics.any(func(diagnostic): return diagnostic.get("path", "") == "validation")
	validation_changed.emit(valid, diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") == "validation"))
	_publish_diagnostics()
	return valid


func _read_source(path: String, source_kind: String) -> String:
	if path.is_empty():
		diagnostics.append(_diagnostic("error", path, "%s path is empty." % source_kind))
		return ""
	if not FileAccess.file_exists(path):
		diagnostics.append(_diagnostic("error", path, "%s file does not exist." % source_kind))
		return ""
	return FileAccess.get_file_as_string(path)


func _append_diagnostics(source_diagnostics: Array, path: String) -> void:
	for source_diagnostic in source_diagnostics:
		var diagnostic: Dictionary = source_diagnostic.duplicate()
		diagnostic["path"] = path
		diagnostics.append(diagnostic)


func _has_errors() -> bool:
	for diagnostic in diagnostics:
		if diagnostic.get("severity", "error") == "error":
			return true
	return false


func _publish_diagnostics() -> void:
	var current_keys := {}
	if log_diagnostics_to_console:
		for diagnostic in diagnostics:
			var diagnostic_key := JSON.stringify(diagnostic)
			current_keys[diagnostic_key] = true
			if _published_diagnostic_keys.has(diagnostic_key):
				continue
			var location := str(diagnostic.get("path", ""))
			if diagnostic.has("line"):
				location += ":%s:%s" % [diagnostic["line"], diagnostic.get("column", 1)]
			var rendered := "%s: %s" % [location, diagnostic.get("message", "Unknown diagnostic")]
			if diagnostic.get("severity", "error") == "warning":
				push_warning(rendered)
			else:
				push_error(rendered)
	_published_diagnostic_keys = current_keys
	diagnostics_changed.emit(diagnostics)


func _request_reload() -> void:
	if not is_inside_tree() or not load_on_ready or _reload_queued:
		return
	_reload_queued = true
	reload_document.call_deferred()


func _diagnostic(severity: String, path: String, message: String) -> Dictionary:
	return {"severity": severity, "path": path, "message": message}


func _refresh_bindings(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "binding")
	if _generated_root == null or _binding_root_context() == null:
		if publish:
			_publish_diagnostics()
		return _generated_root != null
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	_apply_bindings(_generated_root)
	_applying_bindings = was_applying_bindings
	if not _suppress_focus_contract_refresh:
		_refresh_focus_contracts(false)
	_schedule_virtual_scroll_sync()
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _refresh_binding_paths(paths: PackedStringArray, publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic):
		return diagnostic.get("path", "") != "binding" or not _binding_path_matches(str(diagnostic.get("binding_path", "")), paths)
	)
	if _generated_root == null or _binding_root_context() == null:
		if publish:
			_publish_diagnostics()
		return _generated_root != null
	var was_applying_bindings := _applying_bindings
	_applying_bindings = true
	_apply_indexed_binding_paths(paths)
	_applying_bindings = was_applying_bindings
	if not _suppress_focus_contract_refresh and _indexed_paths_affect_focus(paths):
		_refresh_focus_contracts(false)
	_schedule_virtual_scroll_sync()
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _rebuild_binding_target_index() -> void:
	_binding_targets_by_path.clear()
	_dependency_targets_by_path.clear()
	_dependency_index_order = 0
	_index_binding_targets(_generated_root)


func _index_binding_targets(node: Node, inside_repeat: bool = false, inside_virtual_repeat: bool = false) -> void:
	if node == null:
		return
	var next_inside_repeat := inside_repeat
	var next_inside_virtual_repeat := inside_virtual_repeat
	if node is Control:
		var control := node as Control
		var is_repeat := str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat"
		next_inside_repeat = inside_repeat or is_repeat
		next_inside_virtual_repeat = inside_virtual_repeat or (is_repeat and bool(control.get_meta("cascade_virtual", false)))
		var bindings: Dictionary = control.get_meta("cascade_bindings", {})
		for property_name in bindings:
			var binding_path := str(bindings[property_name])
			if binding_path.is_empty():
				continue
			if not _binding_targets_by_path.has(binding_path):
				_binding_targets_by_path[binding_path] = []
			_binding_targets_by_path[binding_path].append({"control": control, "property": str(property_name)})
		for dependency in BindingTrace.dependencies(control):
			var dependency_path := str(dependency.get("path", ""))
			if dependency_path.is_empty():
				continue
			if not _dependency_targets_by_path.has(dependency_path):
				_dependency_targets_by_path[dependency_path] = []
			_dependency_targets_by_path[dependency_path].append({
				"control": control,
				"dependency": dependency,
				"order": _dependency_index_order,
				"inside_repeat": next_inside_repeat,
				"inside_virtual_repeat": next_inside_virtual_repeat,
			})
			_dependency_index_order += 1
	for child in node.get_children():
		_index_binding_targets(child, next_inside_repeat, next_inside_virtual_repeat)


func _indexed_requires_full_reconcile(paths: PackedStringArray) -> bool:
	for dependency_path_value in _dependency_targets_by_path:
		var dependency_path := str(dependency_path_value)
		if not _binding_path_matches(dependency_path, paths):
			continue
		for entry in _dependency_targets_by_path[dependency_path]:
			var dependency: Dictionary = entry["dependency"]
			if str(dependency.get("mode", "")) == "reconcile" and not bool(entry.get("inside_repeat", false)):
				return true
	return false


func _indexed_requires_collection_patch(paths: PackedStringArray) -> bool:
	for dependency_path_value in _dependency_targets_by_path:
		var dependency_path := str(dependency_path_value)
		if not _binding_path_matches(dependency_path, paths):
			continue
		for entry in _dependency_targets_by_path[dependency_path]:
			var dependency: Dictionary = entry["dependency"]
			var mode := str(dependency.get("mode", ""))
			if mode == "collection":
				return true
			if bool(entry.get("inside_repeat", false)) and mode == "reconcile":
				return true
			if bool(entry.get("inside_virtual_repeat", false)) and mode in ["one-way", "two-way"]:
				return true
	return false


func _matching_indexed_controls(paths: PackedStringArray) -> Array[Control]:
	var controls: Array[Control] = []
	var seen: Dictionary = {}
	for binding_path_value in _binding_targets_by_path:
		var binding_path := str(binding_path_value)
		if not _binding_path_matches(binding_path, paths):
			continue
		for entry in _binding_targets_by_path[binding_path]:
			var control: Variant = entry.get("control")
			if not control is Control or not is_instance_valid(control):
				continue
			var instance_id: int = control.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			controls.append(control)
	return controls


func _apply_indexed_binding_paths(paths: PackedStringArray) -> void:
	for control in _matching_indexed_controls(paths):
		_apply_control_bindings(control, paths)


func _indexed_paths_affect_focus(paths: PackedStringArray) -> bool:
	for binding_path_value in _binding_targets_by_path:
		var binding_path := str(binding_path_value)
		if not _binding_path_matches(binding_path, paths):
			continue
		for entry in _binding_targets_by_path[binding_path]:
			if str(entry.get("property", "")) in ["visible", "disabled"]:
				return true
	return false


func _apply_bindings(node: Node, paths: PackedStringArray = PackedStringArray()) -> void:
	if node is Control:
		_apply_control_bindings(node as Control, paths)
	for child in node.get_children():
		_apply_bindings(child, paths)


func _apply_control_bindings(control: Control, paths: PackedStringArray = PackedStringArray()) -> void:
	var bindings: Dictionary = control.get_meta("cascade_bindings", {})
	var range_values := {}
	var range_touched := false
	if control.has_method("set_range_values"):
		range_values = {
			"min_value": control.get("min_value"),
			"max_value": control.get("max_value"),
			"value": control.get("value"),
		}
	for property_name in bindings:
		var property_key := str(property_name)
		var binding_path := str(bindings[property_name])
		if not paths.is_empty() and not _binding_path_matches(binding_path, paths):
			continue
		if not range_values.is_empty() and property_key in ["min_value", "max_value", "value"]:
			range_touched = true
			var numeric := _resolve_numeric_binding(control, property_key, binding_path)
			if numeric["found"]:
				range_values[property_key] = numeric["value"]
		else:
			_apply_binding(control, property_key, binding_path)
	if not range_values.is_empty() and range_touched:
		control.call("set_range_values", range_values["min_value"], range_values["max_value"], range_values["value"])


func _apply_binding(control: Control, property_name: String, path: String) -> void:
	var result := BindingResolver.resolve(_binding_context_for(control, path), path)
	if not result["found"]:
		_append_binding_warning(control, property_name, path, result["message"])
		return
	var value: Variant = result["value"]
	if property_name in ["visible", "disabled", "button_pressed"]:
		if not value is bool:
			_append_binding_warning(control, property_name, path, "Requires a boolean value.")
			return
		control.set(property_name, value)
		return
	if property_name == "image_source" and control.has_method("set_source"):
		var error_message := str(control.call("set_source", value))
		if not error_message.is_empty():
			_append_binding_warning(control, property_name, path, error_message)
		return
	if property_name == "selected_value" and control.has_method("select_value"):
		if not control.call("select_value", value):
			_append_binding_warning(control, property_name, path, "No option '%s'." % value)
		return
	if property_name == "text":
		var rendered := str(value)
		if str(control.get(property_name)) != rendered:
			control.set(property_name, rendered)
		if not bool(control.get_meta("cascade_explicit_accessible_label", false)) and _has_control_property(control, "accessibility_name"):
			control.set("accessibility_name", rendered)
		if control.has_method("validate"):
			control.call("validate")
		return
	if property_name in ["min_value", "max_value", "value"]:
		var numeric := _resolve_numeric_binding(control, property_name, path)
		if numeric["found"]:
			control.set(property_name, numeric["value"])
		return
	control.set(property_name, value)


func _refresh_writable_bindings(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "writable-binding")
	if _generated_root == null:
		if publish:
			_publish_diagnostics()
		return false
	_apply_writable_bindings(_generated_root)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_writable_bindings(node: Node) -> void:
	if node is Control:
		var control := node as Control
		var previous: Array = control.get_meta("cascade_writable_connections", [])
		for connection in previous:
			var signal_name := StringName(connection["signal"])
			var callback: Callable = connection["callable"]
			if control.has_signal(signal_name) and control.is_connected(signal_name, callback):
				control.disconnect(signal_name, callback)
		var connected: Array[Dictionary] = []
		var bindings: Dictionary = control.get_meta("cascade_writable_bindings", {})
		for property_name in bindings:
			var definition: Dictionary = bindings[property_name]
			var signal_name := StringName(definition["signal"])
			var path := str(definition["path"])
			var callback: Callable
			if signal_name == &"selection_changed":
				callback = _on_writable_selection_changed.bind(control, path)
			elif bool(definition.get("read_property", false)):
				callback = _on_writable_property_changed.bind(control, str(property_name), path)
			else:
				callback = _on_writable_value_changed.bind(control, str(property_name), path)
			var error := control.connect(signal_name, callback)
			if error != OK:
				diagnostics.append(_diagnostic("warning", "writable-binding", "%s on %s could not observe native changes (error %s)." % [property_name, control.get_meta("cascade_key", control.name), error]))
				continue
			connected.append({"signal": signal_name, "callable": callback})
		control.set_meta("cascade_writable_connections", connected)
	for child in node.get_children():
		_apply_writable_bindings(child)


func _on_writable_value_changed(value: Variant, control: Control, property_name: String, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, property_name, path, value)


func _on_writable_property_changed(control: Control, property_name: String, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, property_name, path, control.get(property_name))


func _on_writable_selection_changed(value: String, _index: int, control: Control, path: String) -> void:
	if _applying_bindings:
		return
	_write_binding(control, "selected_value", path, value)


func _write_binding(control: Control, property_name: String, path: String, value: Variant) -> void:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "writable-binding")
	var result := BindingResolver.assign(_binding_context_for(control, path), path, value)
	if not result["written"]:
		diagnostics.append(_diagnostic("warning", "writable-binding", "%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), result["message"]]))
		_publish_diagnostics()
		return
	binding_value_changed.emit(path, value, control)
	var changed_paths := PackedStringArray([path])
	_refresh_named_bindings(changed_paths, "write_back", false, true)
	_publish_diagnostics()


func _validate_node(control: Control) -> void:
	if control.has_method("validate") and not control.call("validate"):
		diagnostics.append({
			"severity": "warning",
			"path": "validation",
			"message": "%s: %s" % [control.get_meta("cascade_key", control.name), control.call("current_validation_message")],
			"line": int(control.get_meta("cascade_source_line", 1)),
			"column": int(control.get_meta("cascade_source_column", 1)),
		})
	for child in control.get_children():
		if child is Control:
			_validate_node(child)


func _resolve_numeric_binding(control: Control, property_name: String, path: String) -> Dictionary:
	var result := BindingResolver.resolve(_binding_context_for(control, path), path)
	if not result["found"]:
		_append_binding_warning(control, property_name, path, result["message"])
		return {"found": false, "value": 0.0}
	var value: Variant = result["value"]
	if value is int or value is float:
		return {"found": true, "value": float(value)}
	var rendered := str(value)
	if rendered.is_valid_float():
		return {"found": true, "value": rendered.to_float()}
	_append_binding_warning(control, property_name, path, "Requires a number, got '%s'." % rendered)
	return {"found": false, "value": 0.0}


func _binding_context_for(control: Control, path: String) -> Variant:
	var scope: Dictionary = control.get_meta("cascade_binding_scope", {})
	var first_segment := path.get_slice(".", 0)
	return scope if scope.has(first_segment) else _binding_root_context()


func _binding_root_context() -> Variant:
	return binding_context.value if binding_context is ObservableBindingContext else binding_context


func _connect_binding_observable() -> void:
	if binding_context is ObservableBindingContext and not binding_context.paths_invalidated.is_connected(_on_binding_paths_invalidated):
		binding_context.paths_invalidated.connect(_on_binding_paths_invalidated)


func _disconnect_binding_observable() -> void:
	if binding_context is ObservableBindingContext and binding_context.paths_invalidated.is_connected(_on_binding_paths_invalidated):
		binding_context.paths_invalidated.disconnect(_on_binding_paths_invalidated)


func _on_binding_paths_invalidated(paths: PackedStringArray) -> void:
	_refresh_named_bindings(paths, "observable")


func _record_binding_trace(paths: PackedStringArray, trigger: String, strategy: String, reason: String, success: bool) -> void:
	_binding_trace_sequence += 1
	var stats := last_reconcile_stats if strategy in ["reconcile", "collection_patch", "virtual_window"] else {}
	var matching_entries: Array[Dictionary] = []
	for dependency_path_value in _dependency_targets_by_path:
		var dependency_path := str(dependency_path_value)
		if _binding_path_matches(dependency_path, paths):
			matching_entries.append_array(_dependency_targets_by_path[dependency_path])
	matching_entries.sort_custom(func(left: Dictionary, right: Dictionary):
		return int(left.get("order", 0)) < int(right.get("order", 0))
	)
	var indexed := BindingTrace.record_indexed(
		_generated_root,
		paths,
		trigger,
		strategy,
		reason,
		_binding_trace_sequence,
		success,
		matching_entries,
		_traced_controls,
		stats
	)
	_last_binding_trace = indexed["trace"]
	_traced_controls = indexed["controls"]
	binding_trace_changed.emit(_last_binding_trace.duplicate(true))


func _normalized_binding_paths(paths: PackedStringArray) -> PackedStringArray:
	var normalized := PackedStringArray()
	for path in paths:
		var candidate := path.strip_edges()
		if candidate == "*":
			return PackedStringArray(["*"])
		if not ObservableBindingContext.is_valid_path(candidate):
			continue
		if candidate not in normalized:
			normalized.append(candidate)
	return normalized


func _binding_path_matches(binding_path: String, invalidated_paths: PackedStringArray) -> bool:
	if binding_path.is_empty():
		return false
	for invalidated_path in invalidated_paths:
		if invalidated_path == "*" or binding_path == invalidated_path:
			return true
		if binding_path.begins_with(invalidated_path + ".") or invalidated_path.begins_with(binding_path + "."):
			return true
	return false


func _tree_has_rebuild_binding(node: Node) -> bool:
	if node is Control:
		var control := node as Control
		if not control.get_meta("cascade_rebuild_bindings", PackedStringArray()).is_empty():
			return true
		if not control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()).is_empty():
			return true
	for child in node.get_children():
		if _tree_has_rebuild_binding(child):
			return true
	return false


func _tree_has_focus_validation_contract(node: Node) -> bool:
	if node is Control:
		var control := node as Control
		if bool(control.get_meta("cascade_focus_trap", false)) or bool(control.get_meta("cascade_autofocus", false)):
			return true
	for child in node.get_children():
		if _tree_has_focus_validation_contract(child):
			return true
	return false


func _element_tree_has_condition(element: Variant) -> bool:
	if element == null:
		return false
	if not str(element.attributes.get("if", "")).strip_edges().is_empty():
		return true
	for child in element.children:
		if _element_tree_has_condition(child):
			return true
	return false


func _tree_has_rebuild_binding_outside_repeat(node: Node, inside_repeat: bool = false) -> bool:
	var next_inside := inside_repeat
	if node is Control:
		var control := node as Control
		next_inside = inside_repeat or str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat"
		if not next_inside:
			if not control.get_meta("cascade_rebuild_bindings", PackedStringArray()).is_empty():
				return true
			if not control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()).is_empty():
				return true
	for child in node.get_children():
		if _tree_has_rebuild_binding_outside_repeat(child, next_inside):
			return true
	return false


func _tree_has_matching_rebuild_binding(node: Node, paths: PackedStringArray) -> bool:
	if node is Control:
		var control := node as Control
		var rebuild_paths: PackedStringArray = control.get_meta("cascade_rebuild_bindings", PackedStringArray())
		rebuild_paths.append_array(control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()))
		for binding_path in rebuild_paths:
			if _binding_path_matches(str(binding_path), paths):
				return true
	for child in node.get_children():
		if _tree_has_matching_rebuild_binding(child, paths):
			return true
	return false


func _tree_has_matching_rebuild_binding_outside_repeat(node: Node, paths: PackedStringArray, inside_repeat: bool = false) -> bool:
	var next_inside := inside_repeat
	if node is Control:
		var control := node as Control
		next_inside = inside_repeat or str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat"
		if not next_inside:
			var rebuild_paths: PackedStringArray = control.get_meta("cascade_rebuild_bindings", PackedStringArray()).duplicate()
			rebuild_paths.append_array(control.get_meta("cascade_document_rebuild_bindings", PackedStringArray()))
			for binding_path in rebuild_paths:
				if _binding_path_matches(str(binding_path), paths):
					return true
	for child in node.get_children():
		if _tree_has_matching_rebuild_binding_outside_repeat(child, paths, next_inside):
			return true
	return false


func _tree_has_matching_collection_binding(node: Node, paths: PackedStringArray) -> bool:
	if node is Control:
		var collection_path := str(node.get_meta("cascade_collection_binding", ""))
		if not collection_path.is_empty() and _binding_path_matches(collection_path, paths):
			return true
	for child in node.get_children():
		if _tree_has_matching_collection_binding(child, paths):
			return true
	return false


func _tree_has_matching_repeat_rebuild_binding(node: Node, paths: PackedStringArray, inside_repeat: bool = false) -> bool:
	var next_inside := inside_repeat
	if node is Control:
		var control := node as Control
		next_inside = inside_repeat or str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat"
		if next_inside:
			var rebuild_paths: PackedStringArray = control.get_meta("cascade_rebuild_bindings", PackedStringArray())
			for binding_path in rebuild_paths:
				if _binding_path_matches(str(binding_path), paths):
					return true
	for child in node.get_children():
		if _tree_has_matching_repeat_rebuild_binding(child, paths, next_inside):
			return true
	return false


func _tree_has_matching_virtual_binding(node: Node, paths: PackedStringArray, inside_virtual_repeat: bool = false) -> bool:
	var next_inside := inside_virtual_repeat
	if node is Control:
		var control := node as Control
		if str(control.get_meta("cascade_element_type", "")).to_lower() == "repeat" and bool(control.get_meta("cascade_virtual", false)):
			next_inside = true
		if next_inside:
			var bindings: Dictionary = control.get_meta("cascade_bindings", {})
			for property_name in bindings:
				if _binding_path_matches(str(bindings[property_name]), paths):
					return true
	for child in node.get_children():
		if _tree_has_matching_virtual_binding(child, paths, next_inside):
			return true
	return false


func _collect_outer_repeats(node: Node, result: Array[Control]) -> void:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		result.append(node)
		return
	for child in node.get_children():
		_collect_outer_repeats(child, result)


func _collect_all_repeats(node: Node, result: Array[Control]) -> void:
	if node == null:
		return
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		result.append(node)
	for child in node.get_children():
		_collect_all_repeats(child, result)


func _collect_matching_outer_repeats(node: Node, paths: PackedStringArray, result: Array[Control]) -> void:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		if _tree_has_matching_collection_binding(node, paths) or _tree_has_matching_rebuild_binding(node, paths) or _tree_has_matching_virtual_binding(node, paths):
			result.append(node)
		return
	for child in node.get_children():
		_collect_matching_outer_repeats(child, paths, result)


func _collect_outer_repeats_for_model(node: Node, model: CascadeItemModel, result: Array[Control]) -> void:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		if _tree_uses_item_model(node, model):
			result.append(node)
		return
	for child in node.get_children():
		_collect_outer_repeats_for_model(child, model, result)


func _collect_outer_repeats_for_resolved_model(node: Node, model: CascadeItemModel, result: Array[Control]) -> void:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		if _tree_uses_resolved_item_model(node, model):
			result.append(node)
		return
	for child in node.get_children():
		_collect_outer_repeats_for_resolved_model(child, model, result)


func _tree_uses_resolved_item_model(node: Node, model: CascadeItemModel) -> bool:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		var control := node as Control
		var path := str(control.get_meta("cascade_collection_binding", ""))
		var resolved := BindingResolver.resolve(_binding_context_for(control, path), path) if not path.is_empty() else {}
		var value: Variant = resolved.get("value") if resolved.get("found", false) else null
		if value is CascadeItemModel and value.get_instance_id() == model.get_instance_id():
			return true
	for child in node.get_children():
		if _tree_uses_resolved_item_model(child, model):
			return true
	return false


func _tree_uses_item_model(node: Node, model: CascadeItemModel) -> bool:
	if node is Control and node.has_meta("cascade_collection_model") and node.get_meta("cascade_collection_model") == model:
		return true
	for child in node.get_children():
		if _tree_uses_item_model(child, model):
			return true
	return false


func _count_controls(node: Node) -> int:
	var result := 1 if node is Control else 0
	for child in node.get_children():
		result += _count_controls(child)
	return result


func _refresh_item_model_connections(force_cache_refresh: bool = false) -> void:
	_disconnect_item_models()
	_initialize_virtual_model_key_caches(force_cache_refresh)
	var models: Array[CascadeItemModel] = []
	_collect_item_models(_generated_root, models)
	for pending_model in _pending_item_models:
		if is_instance_valid(pending_model) and pending_model not in models:
			models.append(pending_model)
	for model in models:
		var callback := _on_item_model_changed.bind(model)
		model.changed.connect(callback)
		_item_model_connections.append({"model": model, "callback": callback})


func _disconnect_item_models() -> void:
	for connection in _item_model_connections:
		var model: CascadeItemModel = connection["model"]
		var callback: Callable = connection["callback"]
		if is_instance_valid(model) and model.changed.is_connected(callback):
			model.changed.disconnect(callback)
	_item_model_connections.clear()


func _collect_item_models(node: Node, result: Array[CascadeItemModel]) -> void:
	if node == null:
		return
	if node is Control:
		var model: Variant = node.get_meta("cascade_collection_model") if node.has_meta("cascade_collection_model") else null
		if model is CascadeItemModel and model not in result:
			result.append(model)
	for child in node.get_children():
		_collect_item_models(child, result)


func _on_item_model_changed(change: CascadeCollectionChange, model: CascadeItemModel) -> void:
	var matching_repeats: Array[Control] = []
	_collect_outer_repeats_for_model(_generated_root, model, matching_repeats)
	if matching_repeats.is_empty() and _collection_transaction_blocked:
		_collect_outer_repeats_for_resolved_model(_generated_root, model, matching_repeats)
	if matching_repeats.is_empty() and _collection_transaction_blocked and model in _pending_item_models:
		_collect_outer_repeats(_generated_root, matching_repeats)
	if _collection_transaction_blocked:
		var recovery_success := false
		if not matching_repeats.is_empty():
			recovery_success = _refresh_collections(true, matching_repeats)
		_record_binding_trace(PackedStringArray(["*"]), "item_model", "collection_patch", "collection", recovery_success)
		return
	var delta_diagnostics: Array[Dictionary] = []
	var keys_scanned := 0
	var delta_valid := true
	for repeat in matching_repeats:
		if not bool(repeat.get_meta("cascade_virtual", false)):
			continue
		if change.kind == CascadeCollectionChange.Kind.RESET:
			_clear_item_model_key_cache(repeat)
			continue
		var prepared := _apply_item_model_key_delta(repeat, model, change)
		keys_scanned += int(prepared["keys_scanned"])
		if not bool(prepared["valid"]):
			delta_valid = false
			repeat.set_meta("cascade_item_model_cache_valid", false)
			delta_diagnostics.append_array(prepared["diagnostics"])
	if not delta_valid:
		_collection_transaction_blocked = true
		var all_repeats: Array[Control] = []
		_collect_outer_repeats(_generated_root, all_repeats)
		for blocked_repeat in all_repeats:
			blocked_repeat.set_meta("cascade_collection_transaction_valid", false)
		diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "collection")
		for diagnostic in delta_diagnostics:
			var stamped: Dictionary = diagnostic.duplicate()
			stamped["path"] = "collection"
			diagnostics.append(stamped)
		var failed_stats := _failed_collection_delta_stats(matching_repeats, keys_scanned)
		last_reconcile_stats = failed_stats
		last_collection_stats = failed_stats.duplicate(true)
		_publish_diagnostics()
		_record_binding_trace(PackedStringArray(["*"]), "item_model", "collection_patch", "collection", false)
		return
	var success := false
	if not matching_repeats.is_empty():
		success = _refresh_collections(true, matching_repeats)
	_record_binding_trace(PackedStringArray(["*"]), "item_model", "collection_patch", "collection", success)


func _initialize_virtual_model_key_caches(force: bool) -> void:
	var repeats: Array[Control] = []
	_collect_all_repeats(_generated_root, repeats)
	for repeat in repeats:
		if not bool(repeat.get_meta("cascade_virtual", false)):
			continue
		var model: Variant = repeat.get_meta("cascade_collection_model") if repeat.has_meta("cascade_collection_model") else null
		if not model is CascadeItemModel:
			continue
		var key_property := _repeat_key_property(repeat)
		var cached: Variant = repeat.get_meta("cascade_item_model_key_cache") if repeat.has_meta("cascade_item_model_key_cache") else null
		var cache_matches: bool = (
			cached is Array
			and cached.size() == model.item_count()
			and int(repeat.get_meta("cascade_item_model_cache_model_id", -1)) == model.get_instance_id()
			and str(repeat.get_meta("cascade_item_model_cache_key_property", "")) == key_property
		)
		if cache_matches and not force:
			continue
		var keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray())
		if keys.size() != model.item_count():
			_clear_item_model_key_cache(repeat)
			continue
		var entries: Array = []
		var counts: Dictionary = {}
		for key in keys:
			var rendered_key := str(key)
			entries.append(rendered_key)
			counts[rendered_key] = int(counts.get(rendered_key, 0)) + 1
		repeat.set_meta("cascade_item_model_key_cache", entries)
		repeat.set_meta("cascade_item_model_key_counts", counts)
		repeat.set_meta("cascade_item_model_duplicate_keys", {})
		repeat.set_meta("cascade_item_model_missing_key_count", 0)
		repeat.set_meta("cascade_item_model_cache_valid", true)
		repeat.set_meta("cascade_item_model_cache_model_id", model.get_instance_id())
		repeat.set_meta("cascade_item_model_cache_key_property", key_property)
		repeat.set_meta("cascade_item_model_delta_keys_scanned", 0)


func _apply_item_model_key_delta(repeat: Control, model: CascadeItemModel, change: CascadeCollectionChange) -> Dictionary:
	var result := {"valid": false, "keys_scanned": 0, "diagnostics": []}
	var key_property := _repeat_key_property(repeat)
	var entries_value: Variant = repeat.get_meta("cascade_item_model_key_cache") if repeat.has_meta("cascade_item_model_key_cache") else null
	if (
		not entries_value is Array
		or int(repeat.get_meta("cascade_item_model_cache_model_id", -1)) != model.get_instance_id()
		or str(repeat.get_meta("cascade_item_model_cache_key_property", "")) != key_property
	):
		result["diagnostics"].append(_collection_key_diagnostic(repeat, "Retained Repeat key cache is unavailable or stale; emit RESET to resynchronize it."))
		return result
	var entries: Array = entries_value.duplicate()
	var counts: Dictionary = repeat.get_meta("cascade_item_model_key_counts", {}).duplicate()
	var duplicates: Dictionary = repeat.get_meta("cascade_item_model_duplicate_keys", {}).duplicate()
	var missing_count := int(repeat.get_meta("cascade_item_model_missing_key_count", 0))
	var new_count := model.item_count()
	var change_count := change.count
	var old_count := entries.size()
	if change_count <= 0:
		result["diagnostics"].append(_collection_key_diagnostic(repeat, "Item-model delta count must be positive; emit RESET to resynchronize it."))
		return result
	match change.kind:
		CascadeCollectionChange.Kind.INSERT:
			if new_count != old_count + change_count or change.index < 0 or change.index > old_count:
				result["diagnostics"].append(_collection_key_diagnostic(repeat, "Item-model INSERT does not match the retained key count; emit RESET to resynchronize it."))
				return result
			for offset in change_count:
				var key_result := _model_key_at(model, change.index + offset, key_property)
				result["keys_scanned"] = int(result["keys_scanned"]) + 1
				var entry: Variant = key_result["key"] if key_result["found"] else null
				entries.insert(change.index + offset, entry)
				if entry == null:
					missing_count += 1
				else:
					_increment_cached_key(counts, duplicates, str(entry))
		CascadeCollectionChange.Kind.REMOVE:
			if new_count != old_count - change_count or change.index < 0 or change.index + change_count > old_count:
				result["diagnostics"].append(_collection_key_diagnostic(repeat, "Item-model REMOVE does not match the retained key count; emit RESET to resynchronize it."))
				return result
			for _offset in change_count:
				var removed: Variant = entries[change.index]
				entries.remove_at(change.index)
				if removed == null:
					missing_count -= 1
				else:
					_decrement_cached_key(counts, duplicates, str(removed))
		CascadeCollectionChange.Kind.MOVE:
			var remaining_count := old_count - change_count
			if new_count != old_count or change.index < 0 or change.index + change_count > old_count or change.to_index < 0 or change.to_index > remaining_count:
				result["diagnostics"].append(_collection_key_diagnostic(repeat, "Item-model MOVE does not match the retained key count; emit RESET to resynchronize it."))
				return result
			var moved: Array = entries.slice(change.index, change.index + change_count)
			for _offset in change_count:
				entries.remove_at(change.index)
			for offset in moved.size():
				entries.insert(change.to_index + offset, moved[offset])
		CascadeCollectionChange.Kind.UPDATE:
			if new_count != old_count or change.index < 0 or change.index + change_count > old_count:
				result["diagnostics"].append(_collection_key_diagnostic(repeat, "Item-model UPDATE does not match the retained key count; emit RESET to resynchronize it."))
				return result
			for offset in change_count:
				var item_index := change.index + offset
				var previous: Variant = entries[item_index]
				if previous == null:
					missing_count -= 1
				else:
					_decrement_cached_key(counts, duplicates, str(previous))
				var key_result := _model_key_at(model, item_index, key_property)
				result["keys_scanned"] = int(result["keys_scanned"]) + 1
				var entry: Variant = key_result["key"] if key_result["found"] else null
				entries[item_index] = entry
				if entry == null:
					missing_count += 1
				else:
					_increment_cached_key(counts, duplicates, str(entry))
		_:
			result["diagnostics"].append(_collection_key_diagnostic(repeat, "Unsupported item-model delta; emit RESET to resynchronize it."))
			return result
	repeat.set_meta("cascade_item_model_key_cache", entries)
	repeat.set_meta("cascade_item_model_key_counts", counts)
	repeat.set_meta("cascade_item_model_duplicate_keys", duplicates)
	repeat.set_meta("cascade_item_model_missing_key_count", missing_count)
	repeat.set_meta("cascade_item_model_cache_valid", missing_count == 0 and duplicates.is_empty())
	repeat.set_meta("cascade_item_model_delta_keys_scanned", result["keys_scanned"])
	if missing_count > 0:
		result["diagnostics"].append(_collection_key_diagnostic(repeat, "Repeat key '%s' could not be resolved for the changed item-model state." % key_property))
	if not duplicates.is_empty():
		result["diagnostics"].append(_collection_key_diagnostic(repeat, "Repeat key '%s' is duplicated." % str(duplicates.keys()[0])))
	result["valid"] = missing_count == 0 and duplicates.is_empty()
	return result


func _model_key_at(model: CascadeItemModel, index: int, key_property: String) -> Dictionary:
	var item := model.item_at(index)
	var resolved := BindingResolver.resolve(item, key_property)
	if not resolved["found"]:
		return {"found": false, "key": ""}
	return {"found": true, "key": str(resolved["value"])}


func _increment_cached_key(counts: Dictionary, duplicates: Dictionary, key: String) -> void:
	var next_count := int(counts.get(key, 0)) + 1
	counts[key] = next_count
	if next_count > 1:
		duplicates[key] = next_count


func _decrement_cached_key(counts: Dictionary, duplicates: Dictionary, key: String) -> void:
	var next_count := int(counts.get(key, 0)) - 1
	if next_count <= 0:
		counts.erase(key)
		duplicates.erase(key)
		return
	counts[key] = next_count
	if next_count > 1:
		duplicates[key] = next_count
	else:
		duplicates.erase(key)


func _validated_virtual_model_key_cache(repeat: Control) -> Variant:
	if not bool(repeat.get_meta("cascade_virtual", false)) or not bool(repeat.get_meta("cascade_item_model_cache_valid", false)) or not bool(repeat.get_meta("cascade_collection_transaction_valid", true)):
		return null
	var model: Variant = repeat.get_meta("cascade_collection_model") if repeat.has_meta("cascade_collection_model") else null
	var entries: Variant = repeat.get_meta("cascade_item_model_key_cache") if repeat.has_meta("cascade_item_model_key_cache") else null
	var collection_path := str(repeat.get_meta("cascade_collection_binding", ""))
	var current_collection := BindingResolver.resolve(_binding_root_context(), collection_path)
	if not model is CascadeItemModel or not entries is Array or not current_collection.get("found", false):
		return null
	var current_value: Variant = current_collection.get("value")
	if not current_value is CascadeItemModel or current_value.get_instance_id() != model.get_instance_id():
		return null
	if (
		entries.size() != model.item_count()
		or int(repeat.get_meta("cascade_item_model_cache_model_id", -1)) != model.get_instance_id()
		or str(repeat.get_meta("cascade_item_model_cache_key_property", "")) != _repeat_key_property(repeat)
	):
		return null
	return entries


func _repeat_key_property(repeat: Control) -> String:
	var element: Variant = repeat.get_meta("cascade_repeat_element") if repeat.has_meta("cascade_repeat_element") else null
	return str(element.attributes.get("key", "")).strip_edges() if element != null else ""


func _clear_item_model_key_cache(repeat: Control) -> void:
	for metadata_name in [
		"cascade_item_model_key_cache", "cascade_item_model_key_counts", "cascade_item_model_duplicate_keys",
		"cascade_item_model_missing_key_count", "cascade_item_model_cache_valid", "cascade_item_model_cache_model_id",
		"cascade_item_model_cache_key_property",
	]:
		if repeat.has_meta(metadata_name):
			repeat.remove_meta(metadata_name)
	repeat.set_meta("cascade_item_model_delta_keys_scanned", 0)


func _copy_full_scan_item_model_cache(source: Control, target: Control) -> void:
	if not bool(source.get_meta("cascade_item_model_cache_from_full_scan", false)):
		return
	for metadata_name in [
		"cascade_item_model_key_cache", "cascade_item_model_key_counts", "cascade_item_model_duplicate_keys",
		"cascade_item_model_missing_key_count", "cascade_item_model_cache_valid", "cascade_item_model_cache_model_id",
		"cascade_item_model_cache_key_property",
	]:
		if source.has_meta(metadata_name):
			target.set_meta(metadata_name, source.get_meta(metadata_name).duplicate(true) if source.get_meta(metadata_name) is Array or source.get_meta(metadata_name) is Dictionary else source.get_meta(metadata_name))
	target.set_meta("cascade_item_model_delta_keys_scanned", 0)


func _failed_collection_delta_stats(repeats: Array[Control], keys_scanned: int) -> Dictionary:
	var model_count := 0
	var realized_count := 0
	var virtual_ranges: Array[Dictionary] = []
	for repeat in repeats:
		if bool(repeat.get_meta("cascade_virtual", false)):
			var model: Variant = repeat.get_meta("cascade_collection_model") if repeat.has_meta("cascade_collection_model") else null
			model_count += model.item_count() if model is CascadeItemModel else int(repeat.get_meta("cascade_virtual_model_count", 0))
			realized_count += int(repeat.get_meta("cascade_virtual_realized_count", 0))
			virtual_ranges.append({"first": int(repeat.get_meta("cascade_virtual_first_index", 0)), "end": int(repeat.get_meta("cascade_virtual_end_index", 0))})
	return {
		"reused": 0, "created": 0, "replaced": 0, "removed": 0,
		"repeat_candidates": 0, "candidate_native_controls": 0, "full_document_candidates": 0,
		"attempted_repeats": repeats.size(),
		"model_count": model_count, "realized_count": realized_count, "pinned_focus_count": 0,
		"keys_scanned": keys_scanned, "virtual_ranges": virtual_ranges,
	}


func _collection_key_diagnostic(repeat: Control, message: String) -> Dictionary:
	return {
		"severity": "error",
		"message": message,
		"line": int(repeat.get_meta("cascade_source_line", 1)),
		"column": int(repeat.get_meta("cascade_source_column", 1)),
	}


func _refresh_virtual_scroll_connections() -> void:
	_disconnect_virtual_scrolls()
	if _generated_root == null or not is_inside_tree():
		return
	var repeats: Array[Control] = []
	_collect_virtual_repeats(_generated_root, repeats)
	for repeat in repeats:
		var scroll := _find_scroll_ancestor(repeat)
		if scroll == null:
			continue
		var bar := scroll.get_v_scroll_bar()
		var value_callback := _on_virtual_scroll_changed.bind(repeat, scroll)
		var resize_callback := _on_virtual_scroll_resized.bind(repeat, scroll)
		if not bar.value_changed.is_connected(value_callback):
			bar.value_changed.connect(value_callback)
		if not scroll.resized.is_connected(resize_callback):
			scroll.resized.connect(resize_callback)
		_virtual_scroll_connections.append({"bar": bar, "value_callback": value_callback, "scroll": scroll, "resize_callback": resize_callback})
		_sync_virtual_repeat.call_deferred(repeat, scroll, false)


func _disconnect_virtual_scrolls() -> void:
	for connection in _virtual_scroll_connections:
		var bar: Range = connection["bar"]
		var value_callback: Callable = connection["value_callback"]
		var scroll: ScrollContainer = connection["scroll"]
		var resize_callback: Callable = connection["resize_callback"]
		if is_instance_valid(bar) and bar.value_changed.is_connected(value_callback):
			bar.value_changed.disconnect(value_callback)
		if is_instance_valid(scroll) and scroll.resized.is_connected(resize_callback):
			scroll.resized.disconnect(resize_callback)
	_virtual_scroll_connections.clear()


func _collect_virtual_repeats(node: Node, result: Array[Control]) -> void:
	if node is Control and bool(node.get_meta("cascade_virtual", false)):
		result.append(node)
	for child in node.get_children():
		_collect_virtual_repeats(child, result)


func _find_scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func _on_virtual_scroll_changed(_value: float, repeat: Control, scroll: ScrollContainer) -> void:
	_sync_virtual_repeat(repeat, scroll, true)


func _on_virtual_scroll_resized(repeat: Control, scroll: ScrollContainer) -> void:
	_sync_virtual_repeat.call_deferred(repeat, scroll, true)


func _sync_virtual_repeat(repeat: Control, scroll: ScrollContainer, publish_trace: bool) -> void:
	if not is_instance_valid(repeat) or not is_instance_valid(scroll) or not repeat.is_inside_tree():
		return
	var bar := scroll.get_v_scroll_bar()
	var viewport_extent := maxf(bar.page if bar.page > 0.0 else scroll.size.y, 1.0)
	var origin := _virtual_repeat_content_origin(repeat, scroll)
	repeat.set_meta("cascade_virtual_scroll_origin", origin)
	var local_offset := maxf(0.0, bar.value - origin)
	var window := CascadeVirtualWindow.new(
		int(repeat.get_meta("cascade_virtual_model_count", 0)),
		float(repeat.get_meta("cascade_virtual_item_extent", 1.0)),
		viewport_extent,
		int(repeat.get_meta("cascade_virtual_overscan", 3))
	)
	window.set_scroll_offset(local_offset)
	var range_changed := window.first_index != int(repeat.get_meta("cascade_virtual_first_index", -1)) or window.end_index != int(repeat.get_meta("cascade_virtual_end_index", -1))
	var viewport_changed := not is_equal_approx(viewport_extent, float(repeat.get_meta("cascade_virtual_viewport_extent", 0.0)))
	repeat.set_meta("cascade_virtual_scroll_offset", window.scroll_offset)
	repeat.set_meta("cascade_virtual_viewport_extent", viewport_extent)
	if not range_changed and not viewport_changed:
		return
	_prepare_virtual_focus_pin(repeat)
	var success := _refresh_collections(true, [repeat], false)
	if publish_trace:
		_record_binding_trace(PackedStringArray([str(repeat.get_meta("cascade_collection_binding", "*"))]), "scroll", "virtual_window", "viewport", success)


func _prepare_virtual_focus_pin(repeat: Control) -> void:
	if not bool(repeat.get_meta("cascade_virtual", false)) or not is_inside_tree():
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	var pinned_index := -1
	var pinned_key := ""
	if focus_owner is Control and (focus_owner == repeat or repeat.is_ancestor_of(focus_owner)):
		var cursor: Control = focus_owner
		while cursor != null and cursor != repeat:
			if cursor.has_meta("cascade_repeat_index"):
				pinned_index = int(cursor.get_meta("cascade_repeat_index"))
				var keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray())
				if pinned_index >= 0 and pinned_index < keys.size():
					pinned_key = keys[pinned_index]
				break
			cursor = cursor.get_parent() as Control
	repeat.set_meta("cascade_virtual_pinned_index", pinned_index)
	repeat.set_meta("cascade_virtual_pinned_key", pinned_key)


func _refresh_released_virtual_focus_pins() -> void:
	if _generated_root == null or _applying_bindings:
		return
	var repeats: Array[Control] = []
	_collect_virtual_repeats(_generated_root, repeats)
	for repeat in repeats:
		if str(repeat.get_meta("cascade_virtual_pinned_key", "")).is_empty():
			continue
		var previous_key := str(repeat.get_meta("cascade_virtual_pinned_key", ""))
		_prepare_virtual_focus_pin(repeat)
		if str(repeat.get_meta("cascade_virtual_pinned_key", "")) != previous_key:
			var success := _refresh_collections(true, [repeat], false)
			_record_binding_trace(PackedStringArray([str(repeat.get_meta("cascade_collection_binding", "*"))]), "focus", "virtual_window", "focus_pin", success)


func _capture_virtual_anchor(repeat: Control) -> Dictionary:
	var keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray())
	var extent := float(repeat.get_meta("cascade_virtual_item_extent", 1.0))
	var offset := float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
	if keys.is_empty() or extent <= 0.0:
		return {}
	var index := clampi(int(floor(offset / extent)), 0, keys.size() - 1)
	return {"key": keys[index], "pixel_offset": offset - float(index) * extent, "original_scroll_offset": offset}


func _append_collection_diagnostics(source_diagnostics: Array) -> void:
	for source_diagnostic in source_diagnostics:
		var diagnostic: Dictionary = source_diagnostic.duplicate()
		diagnostic["path"] = "collection"
		diagnostics.append(diagnostic)


func _append_accessibility_diagnostics(source_diagnostics: Array, path: String) -> void:
	for source_diagnostic in source_diagnostics:
		var diagnostic: Dictionary = source_diagnostic.duplicate()
		diagnostic["path"] = path
		diagnostic["category"] = "accessibility"
		diagnostics.append(diagnostic)


func _restore_virtual_anchor(repeat: Control, anchor: Dictionary) -> void:
	if anchor.is_empty() or not bool(repeat.get_meta("cascade_virtual", false)):
		return
	var scroll := _find_scroll_ancestor(repeat)
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	var origin := _virtual_repeat_content_origin(repeat, scroll)
	repeat.set_meta("cascade_virtual_scroll_origin", origin)
	var target := origin + float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
	if not is_equal_approx(bar.value, target):
		bar.set_value.call_deferred(target)


func _virtual_repeat_content_origin(repeat: Control, scroll: ScrollContainer) -> float:
	var origin := 0.0
	var cursor: Control = repeat
	while cursor != null and cursor.get_parent() != scroll:
		origin += cursor.position.y
		cursor = cursor.get_parent() as Control
	return maxf(origin, 0.0)


func _schedule_virtual_scroll_sync() -> void:
	if _generated_root != null and is_inside_tree():
		_resync_virtual_scrolls.call_deferred()


func _resync_virtual_scrolls() -> void:
	if _generated_root == null or not is_inside_tree():
		return
	var repeats: Array[Control] = []
	_collect_virtual_repeats(_generated_root, repeats)
	for repeat in repeats:
		var scroll := _find_scroll_ancestor(repeat)
		if scroll != null:
			_sync_virtual_repeat.call_deferred(repeat, scroll, false)


func _validate_virtual_contracts(root: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var repeats: Array[Control] = []
	_collect_virtual_repeats(root, repeats)
	for repeat in repeats:
		if _find_scroll_ancestor(repeat) == null:
			result.append(_virtual_diagnostic(repeat, "Virtual Repeat requires a Scroll ancestor."))
		var repeat_ancestor := repeat.get_parent()
		while repeat_ancestor is Control:
			if str(repeat_ancestor.get_meta("cascade_element_type", "")).to_lower() == "repeat":
				result.append(_virtual_diagnostic(repeat, "Virtual Repeat cannot be nested inside another Repeat."))
				break
			repeat_ancestor = repeat_ancestor.get_parent()
		var repeat_style: CascadeStyle = repeat.get("cascade_style")
		if repeat_style != null and (repeat_style.padding_top > 0.0 or repeat_style.padding_bottom > 0.0 or repeat_style.border_width > 0.0):
			result.append(_virtual_diagnostic(repeat, "Virtual Repeat does not support vertical padding or borders; apply them to its Scroll ancestor."))
		var item_height := float(repeat.get_meta("cascade_virtual_item_height", 0.0))
		for child in repeat.get_children():
			if child is Control and child.has_meta("cascade_repeat_index") and _fresh_control_minimum_height(child) > item_height + 0.01:
				result.append(_virtual_diagnostic(child, "Virtual Repeat item minimum height exceeds item-height; increase item-height or reduce the row content."))
				break
		var ancestor := repeat.get_parent()
		while ancestor != null and not ancestor is CascadeTable:
			ancestor = ancestor.get_parent()
		if ancestor is CascadeTable:
			var tracks: Array[Dictionary] = ancestor.get("column_tracks")
			if tracks.is_empty() or tracks.any(func(track: Dictionary): return _track_uses_content(track)):
				result.append(_virtual_diagnostic(repeat, "Virtual table Repeat requires explicit non-content column tracks."))
			if float(ancestor.get("row_gap")) > 0.0:
				result.append(_virtual_diagnostic(repeat, "Virtual table Repeat requires row-gap: 0; include spacing in item-height or cell padding."))
	return result


func _validate_virtual_repeat_candidate(repeat: Control) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bool(repeat.get_meta("cascade_virtual", false)):
		return result
	var repeat_style: CascadeStyle = repeat.get("cascade_style")
	if repeat_style != null and (repeat_style.padding_top > 0.0 or repeat_style.padding_bottom > 0.0 or repeat_style.border_width > 0.0):
		result.append(_virtual_diagnostic(repeat, "Virtual Repeat does not support vertical padding or borders; apply them to its Scroll ancestor."))
	var item_height := float(repeat.get_meta("cascade_virtual_item_height", 0.0))
	for child in repeat.get_children():
		if child is Control and child.has_meta("cascade_repeat_index") and _fresh_control_minimum_height(child) > item_height + 0.01:
			result.append(_virtual_diagnostic(child, "Virtual Repeat item minimum height exceeds item-height after binding values were applied; increase item-height or reduce the row content."))
	return result


func _fresh_control_minimum_height(control: Control) -> float:
	return maxf(control.get_minimum_size().y, control.custom_minimum_size.y)


func _resolved_item_models_for_repeats(repeats: Array[Control]) -> Array[CascadeItemModel]:
	var result: Array[CascadeItemModel] = []
	for repeat in repeats:
		_collect_resolved_item_models(repeat, result)
	return result


func _collect_resolved_item_models(node: Node, result: Array[CascadeItemModel]) -> void:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == "repeat":
		var control := node as Control
		var path := str(control.get_meta("cascade_collection_binding", ""))
		var resolved := BindingResolver.resolve(_binding_context_for(control, path), path) if not path.is_empty() else {}
		var value: Variant = resolved.get("value") if resolved.get("found", false) else null
		if value is CascadeItemModel and value not in result:
			result.append(value)
	for child in node.get_children():
		_collect_resolved_item_models(child, result)


func _track_uses_content(track: Dictionary) -> bool:
	if str(track.get("kind", "content")) == "content":
		return true
	for name in ["minimum", "maximum", "min", "max"]:
		if track.get(name) is Dictionary and _track_uses_content(track[name]):
			return true
	return false


func _virtual_diagnostic(control: Control, message: String) -> Dictionary:
	return {"severity": "error", "message": message, "line": int(control.get_meta("cascade_source_line", 1)), "column": int(control.get_meta("cascade_source_column", 1))}


func _append_binding_warning(control: Control, property_name: String, binding_path: String, message: String) -> void:
	diagnostics.append({
		"severity": "warning",
		"path": "binding",
		"binding_path": binding_path,
		"message": "%s on %s: %s" % [property_name, control.get_meta("cascade_key", control.name), message],
	})


func _refresh_events(publish: bool) -> bool:
	diagnostics = diagnostics.filter(func(diagnostic): return diagnostic.get("path", "") != "event")
	if _generated_root == null:
		if publish:
			_publish_diagnostics()
		return false
	var target: Object = event_context
	if target == null and _binding_root_context() is Object:
		target = _binding_root_context()
	if target == null:
		target = self
	_apply_events(_generated_root, target)
	if publish:
		_publish_diagnostics()
	return not _has_errors()


func _apply_events(node: Node, target: Object) -> void:
	if node is Control:
		var control := node as Control
		var previous: Array = control.get_meta("cascade_event_connections", [])
		for connection in previous:
			var signal_name := StringName(connection["signal"])
			var callback: Callable = connection["callable"]
			if control.has_signal(signal_name) and control.is_connected(signal_name, callback):
				control.disconnect(signal_name, callback)
		var connected: Array[Dictionary] = []
		var events: Dictionary = control.get_meta("cascade_events", {})
		for signal_value in events:
			var method_name := str(events[signal_value])
			if not target.has_method(method_name):
				diagnostics.append(_diagnostic("warning", "event", "%s on %s: target has no method '%s'." % [signal_value, control.get_meta("cascade_key", control.name), method_name]))
				continue
			var signal_name := StringName(signal_value)
			var callback := Callable(target, method_name)
			var error := control.connect(signal_name, callback)
			if error != OK:
				diagnostics.append(_diagnostic("warning", "event", "%s on %s could not connect method '%s' (error %s)." % [signal_value, control.get_meta("cascade_key", control.name), method_name, error]))
				continue
			connected.append({"signal": signal_name, "callable": callback})
		control.set_meta("cascade_event_connections", connected)
	for child in node.get_children():
		_apply_events(child, target)


func _contains_element(node: Node, element_type: String) -> bool:
	if node is Control and str(node.get_meta("cascade_element_type", "")).to_lower() == element_type:
		return true
	for child in node.get_children():
		if _contains_element(child, element_type):
			return true
	return false


func _has_control_property(control: Control, property_name: StringName) -> bool:
	for property in control.get_property_list():
		if property.name == property_name:
			return true
	return false


func _stamp_source_path(node: Node) -> void:
	if node is Control:
		node.set_meta("cascade_source_path", markup_path)
	for child in node.get_children():
		_stamp_source_path(child)


func _collect_elements_by_metadata(node: Node, metadata_name: String, value: String, matches: Array[Control]) -> void:
	if node == null:
		return
	if node is Control and str(node.get_meta(metadata_name, "")) == value:
		matches.append(node)
	for child in node.get_children():
		_collect_elements_by_metadata(child, metadata_name, value, matches)


func _capture_source_signatures() -> void:
	_source_signatures = _read_source_signatures()


func _read_source_signatures() -> Dictionary:
	return {
		"markup": _source_signature(markup_path),
		"stylesheet": _source_signature(stylesheet_path),
	}


func _source_signature(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	return FileAccess.get_file_as_string(path).hash()
