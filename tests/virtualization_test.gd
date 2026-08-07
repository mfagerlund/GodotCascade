extends SceneTree

const CascadeDocument := preload("res://addons/godot_cascade/runtime/cascade_document.gd")
const ArrayItemModel := preload("res://addons/godot_cascade/runtime/array_item_model.gd")
const CollectionChange := preload("res://addons/godot_cascade/runtime/collection_change.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var items: Array = []
	for index in 10_000:
		items.append({"id": "item-%05d" % index, "name": "Item %05d" % index})
	var model := ArrayItemModel.new(items, func(item: Dictionary): return item["id"])
	await _test_virtual_list(model)
	await _test_virtual_table(model)
	await _test_virtual_model_deltas(items)
	await _test_virtual_array(items.duplicate(true))
	await _test_moving_virtual_origin(model)
	await _test_bound_virtual_contracts()
	await _test_writeback_virtual_contract()
	await _test_invalid_model_transition()
	await _test_malformed_delta_blocks_scroll()
	await _test_multi_repeat_transaction()
	await _test_padded_scroll_viewport(model)
	await _test_invalid_virtual_contract(model)
	if _failures.is_empty():
		print("GodotCascade virtualization tests passed.")
		quit(0)
	else:
		for failure in _failures: push_error(failure)
		quit(1)


func _test_virtual_list(model: ArrayItemModel) -> void:
	var paths := _write_pair("virtual_list", """<Page>
	<Scroll id="viewport">
		<Repeat id="rows" items="{model}" key="id" virtual="true" item-height="44" overscan="2">
			<Button text="{item.name}" />
		</Repeat>
	</Scroll>
	<Button id="outside-focus" text="Outside focus" />
</Page>""", "Page { width: 400px; height: 240px; } #viewport { width: 400px; height: 240px; } #rows { gap: 0px; }")
	var document := await _load_document(paths, model)
	_expect(
		"virtual list document loads (%s)" % [document.diagnostics],
		document.generated_root() != null
	)
	if document.generated_root() != null:
		var repeat: Control = document.get_element_by_id("rows")
		var scroll: ScrollContainer = document.get_element_by_id("viewport")
		_expect("10k list realizes a bounded top window", _realized_rows(repeat).size() <= 15 and int(repeat.get_meta("cascade_virtual_model_count", 0)) == 10_000)
		_expect("virtual list exposes full native scroll extent", scroll.get_v_scroll_bar().max_value >= 239_000.0)
		scroll.set_v_scroll(220_000)
		await _frames(3)
		var middle := _realized_rows(repeat)
		_expect("midpoint scroll remains bounded", middle.size() <= 15)
		_expect("midpoint realizes the correct model neighborhood", middle.any(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) in range(4998, 5013)))
		var overlap: Control = middle[middle.size() - 2]
		var overlap_index := int(overlap.get_meta("cascade_repeat_index"))
		var overlap_id := overlap.get_instance_id()
		scroll.set_v_scroll(220_044)
		await _frames(3)
		var shifted := _realized_rows(repeat)
		var same := shifted.filter(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) == overlap_index)
		_expect("window shift preserves overlapping keyed identity", same.size() == 1 and same[0].get_instance_id() == overlap_id)

		# A collection insertion before the viewport must keep the same first
		# visible key and the same intra-row pixel offset, rather than making the
		# user's content jump by one row.
		scroll.set_v_scroll(220_013)
		await _frames(3)
		var anchor_offset := float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
		var anchor_index := int(floor(anchor_offset / 44.0))
		var anchor_key := str(model.item_at(anchor_index)["id"])
		var anchor_pixel := fmod(anchor_offset, 44.0)
		_expect("insert before virtual viewport succeeds", model.insert(0, {"id": "inserted-anchor", "name": "Inserted anchor"}))
		await _frames(3)
		repeat = document.get_element_by_id("rows")
		var shifted_offset := float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
		var shifted_index := int(floor(shifted_offset / 44.0))
		_expect("collection patch preserves first-visible keyed anchor", str(model.item_at(shifted_index)["id"]) == anchor_key)
		_expect("collection patch preserves anchor intra-row offset", is_equal_approx(fmod(shifted_offset, 44.0), anchor_pixel))
		_expect("remove anchor fixture succeeds", model.remove_at(0))
		await _frames(3)

		var pinned: Control = shifted[0]
		pinned.grab_focus()
		await process_frame
		var pinned_id := pinned.get_instance_id()
		var pinned_index := int(pinned.get_meta("cascade_repeat_index"))
		var pinned_key := str(repeat.get_meta("cascade_repeat_keys", PackedStringArray())[pinned_index])
		scroll.set_v_scroll(200_000)
		await _frames(3)
		var far_rows := _realized_rows(repeat)
		var pinned_matches := far_rows.filter(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) == pinned_index)
		_expect("focused virtual row is pinned outside the viewport", pinned_matches.size() == 1 and pinned_matches[0].get_instance_id() == pinned_id)
		_expect("focus pin adds at most one realized row", far_rows.size() <= 16)
		_expect("insert before focused pin succeeds", model.insert(0, {"id": "before-focus", "name": "Before focus"}))
		var moved_pin := _realized_rows(repeat).filter(func(row: Control): return "repeat:%s" % pinned_key in str(row.get_meta("cascade_key", "")))
		_expect("focused pin follows its key across insert", moved_pin.size() == 1 and moved_pin[0].get_instance_id() == pinned_id and str(repeat.get_meta("cascade_virtual_pinned_key", "")) == pinned_key)
		_expect("remove before focused pin succeeds", model.remove_at(0))
		_expect("move before focused pin succeeds", model.move_items(0, 10))
		moved_pin = _realized_rows(repeat).filter(func(row: Control): return "repeat:%s" % pinned_key in str(row.get_meta("cascade_key", "")))
		_expect("focused pin follows its key across move", moved_pin.size() == 1 and moved_pin[0].get_instance_id() == pinned_id)
		_expect("inverse move restores model order", model.move_items(10, 0))
		var outside: Control = document.get_element_by_id("outside-focus")
		outside.grab_focus()
		await _frames(3)
		_expect("moving focus outside releases off-window pin", str(repeat.get_meta("cascade_virtual_pinned_key", "")).is_empty() and not _realized_rows(repeat).any(func(row: Control): return row.get_instance_id() == pinned_id))
		_expect("scroll trace reports virtual-window strategy", document.last_binding_trace().get("strategy", "") == "virtual_window")
		_expect("virtual window builds no document candidate", int(document.last_binding_trace().get("reconcile_stats", {}).get("full_document_candidates", -1)) == 0)
	await _dispose_document(document, paths)


func _test_virtual_table(model: ArrayItemModel) -> void:
	var paths := _write_pair("virtual_table", """<Page>
	<Scroll id="table-scroll">
		<Table id="inventory">
			<TableHeader><TableRow><TableHeaderCell>Code</TableHeaderCell><TableHeaderCell>Name</TableHeaderCell></TableRow></TableHeader>
			<TableBody><Repeat id="table-rows" items="{model}" key="id" virtual="true" item-height="24" overscan="2">
				<TableRow><TableCell text="{item.id}" /><TableCell text="{item.name}" /></TableRow>
			</Repeat></TableBody>
		</Table>
	</Scroll>
</Page>""", "Page { width: 480px; height: 240px; } #table-scroll { width: 480px; height: 240px; } #inventory { grid-template-columns: 120px 1fr; gap: 0px; }")
	var document := await _load_document(paths, model)
	_expect("virtual table document loads with explicit tracks", document.generated_root() != null)
	if document.generated_root() != null:
		var repeat: Control = document.get_element_by_id("table-rows")
		var scroll: ScrollContainer = document.get_element_by_id("table-scroll")
		_expect("10k table realizes bounded native rows", _realized_rows(repeat).size() <= 15)
		_expect("table scrollbar represents unrealized rows", scroll.get_v_scroll_bar().max_value >= 239_000.0)
		scroll.set_v_scroll(120_024)
		await _frames(3)
		var middle := _realized_rows(repeat)
		_expect("virtual table midpoint is correct and bounded", middle.size() <= 15 and middle.any(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) in range(4998, 5014)))
		var table: Control = document.get_element_by_id("inventory")
		_expect("virtual table keeps two explicit stable columns", table.get("column_tracks").size() == 2)
	await _dispose_document(document, paths)


func _test_virtual_model_deltas(initial_items: Array) -> void:
	var model := ArrayItemModel.new(initial_items, func(item: Dictionary): return item.get("id"))
	var paths := _write_pair("virtual_deltas", """<Page>
	<Scroll id="viewport">
		<Repeat id="rows" items="{model}" key="id" virtual="true" item-height="60.5" overscan="2">
			<Label text="{item.name}" />
		</Repeat>
	</Scroll>
</Page>""", "Page { width: 400px; height: 240px; } #viewport { width: 400px; height: 240px; } #rows { gap: 0px; }")
	var document := await _load_document(paths, model)
	_expect("virtual delta document loads (%s)" % [document.diagnostics], document.generated_root() != null)
	if document.generated_root() != null:
		var repeat: Control = document.get_element_by_id("rows")
		var scroll: ScrollContainer = document.get_element_by_id("viewport")
		scroll.get_v_scroll_bar().value = 120_007.25
		await _frames(3)
		var extent := float(repeat.get_meta("cascade_virtual_item_extent", 24.0))
		var original_offset := float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
		var original_index := int(floor(original_offset / extent))
		var original_pixel_offset := original_offset - float(original_index) * extent
		var original_anchor := str(repeat.get_meta("cascade_repeat_keys", PackedStringArray())[original_index])

		_expect("delta insert succeeds", model.insert(0, {"id": "inserted", "name": "Inserted"}))
		var insert_stats := document.collection_stats()
		var inserted_offset := float(repeat.get_meta("cascade_virtual_scroll_offset", 0.0))
		var inserted_index := int(floor(inserted_offset / extent))
		var inserted_pixel_offset := inserted_offset - float(inserted_index) * extent
		_expect("insert scans only inserted key", int(insert_stats.get("keys_scanned", -1)) == 1 and int(insert_stats.get("full_document_candidates", -1)) == 0)
		_expect("insert preserves keyed scroll anchor", str(repeat.get_meta("cascade_repeat_keys", PackedStringArray())[inserted_index]) == original_anchor and is_equal_approx(inserted_pixel_offset, original_pixel_offset))
		_expect("delta remove succeeds", model.remove_at(0))
		_expect("remove scans no model keys", int(document.collection_stats().get("keys_scanned", -1)) == 0)

		_expect("delta move succeeds", model.move_items(9_999, 0))
		_expect("move updates retained keys without a scan", int(document.collection_stats().get("keys_scanned", -1)) == 0 and str(repeat.get_meta("cascade_repeat_keys", PackedStringArray())[0]) == "item-09999")
		_expect("inverse move succeeds", model.move_items(0, 9_999))
		_expect("inverse move also scans no keys", int(document.collection_stats().get("keys_scanned", -1)) == 0)

		var update_index := int(repeat.get_meta("cascade_virtual_first_index", 0)) + 2
		var updated: Dictionary = model.item_at(update_index).duplicate(true)
		updated["name"] = "Updated visible row"
		_expect("delta update succeeds", model.update(update_index, updated))
		_expect("update scans only changed key", int(document.collection_stats().get("keys_scanned", -1)) == 1)
		var updated_rows := _realized_rows(repeat).filter(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) == update_index)
		_expect("updated delta reaches the realized row", updated_rows.size() == 1 and str(updated_rows[0].get("text")) == "Updated visible row")

		var stable_keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
		var duplicate_id := str(model.item_at(0)["id"])
		_expect("duplicate delta enters the model", model.insert(0, {"id": duplicate_id, "name": "Duplicate"}))
		_expect("duplicate delta scans one key and preserves native rows", int(document.collection_stats().get("keys_scanned", -1)) == 1 and int(document.collection_stats().get("attempted_repeats", 0)) == 1 and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys and not bool(document.last_binding_trace().get("success", true)))
		_expect("duplicate delta publishes an error", document.diagnostics.any(func(diagnostic): return "duplicated" in str(diagnostic.get("message", ""))))
		scroll.get_v_scroll_bar().value += extent
		await _frames(3)
		_expect("scroll cannot render a known-invalid duplicate model", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys and document.diagnostics.any(func(diagnostic): return "duplicated" in str(diagnostic.get("message", ""))))
		_expect("removing invalid duplicate repairs cache", model.remove_at(0))
		_expect("duplicate recovery performs a safe full rescan", int(document.collection_stats().get("keys_scanned", -1)) == model.item_count() and bool(document.last_binding_trace().get("success", false)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)

		var valid_first: Dictionary = model.item_at(0).duplicate(true)
		_expect("missing-key delta enters the model", model.update(0, {"name": "Missing key"}))
		_expect("missing-key delta is atomic and scans one key", int(document.collection_stats().get("keys_scanned", -1)) == 1 and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys and document.diagnostics.any(func(diagnostic): return "could not be resolved" in str(diagnostic.get("message", ""))))
		scroll.get_v_scroll_bar().value += extent
		await _frames(3)
		_expect("scroll cannot render a known-invalid missing-key model", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys and document.diagnostics.any(func(diagnostic): return "could not be resolved" in str(diagnostic.get("message", ""))))
		_expect("correcting missing key repairs cache", model.update(0, valid_first))
		_expect("missing-key recovery performs a safe full rescan", int(document.collection_stats().get("keys_scanned", -1)) == model.item_count() and bool(document.last_binding_trace().get("success", false)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)

		model.reset(model.items())
		var reset_stats := document.collection_stats()
		_expect("RESET performs the allowed full key scan (%s)" % reset_stats, int(reset_stats.get("keys_scanned", -1)) == model.item_count() and int(reset_stats.get("full_document_candidates", -1)) == 0)
		var transitioned_array := model.items()
		document.binding_context = {"model": transitioned_array}
		repeat = document.get_element_by_id("rows")
		_expect("virtual binding can transition ItemModel to Array", bool(document.last_binding_trace().get("success", false)) and not repeat.has_meta("cascade_collection_model") and bool(repeat.get_meta("cascade_array_key_cache_valid", false)))
		document.binding_context = {"model": model}
		repeat = document.get_element_by_id("rows")
		_expect("virtual binding can transition Array back to ItemModel", bool(document.last_binding_trace().get("success", false)) and repeat.get_meta("cascade_collection_model") == model and bool(repeat.get_meta("cascade_item_model_cache_valid", false)))
	await _dispose_document(document, paths)


func _test_virtual_array(items: Array) -> void:
	var paths := _write_pair("virtual_array", """<Page>
	<Scroll id="array-scroll">
		<Repeat id="array-rows" items="{items}" key="id" virtual="true" item-height="60" overscan="2">
			<Label text="{item.name}" />
		</Repeat>
	</Scroll>
</Page>""", "Page { width: 400px; height: 240px; } #array-scroll { width: 400px; height: 240px; } #array-rows { gap: 0px; }")
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"items": items}
	document.markup_path = paths[0]
	document.stylesheet_path = paths[1]
	document.size = Vector2(400.0, 240.0)
	root.add_child(document)
	_expect("virtual Array document loads (%s)" % [document.diagnostics], document.reload_document())
	await _frames(3)
	var scroll: ScrollContainer = document.get_element_by_id("array-scroll")
	scroll.set_v_scroll(120_000)
	await _frames(3)
	var scroll_stats: Dictionary = document.last_binding_trace().get("reconcile_stats", {})
	_expect("Array virtual scroll reuses validated keys", document.last_binding_trace().get("strategy", "") == "virtual_window" and int(scroll_stats.get("keys_scanned", -1)) == 0)
	items.insert(0, {"id": "array-insert", "name": "Array insert"})
	_expect("explicit Array invalidation succeeds", document.refresh_binding_paths(PackedStringArray(["items"])))
	var patch_stats: Dictionary = document.last_binding_trace().get("reconcile_stats", {})
	_expect("Array collection invalidation rescans current keys", int(patch_stats.get("keys_scanned", 0)) >= items.size())
	_expect("Array collection invalidation remains localized", int(patch_stats.get("full_document_candidates", -1)) == 0)
	var repeat: Control = document.get_element_by_id("array-rows")
	var stable_keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
	var valid_first: Dictionary = items[0]
	items[0] = {"id": items[1]["id"], "name": "Duplicate Array key"}
	_expect("invalid Array duplicate is rejected", not document.refresh_binding_paths(PackedStringArray(["items"])) and not bool(repeat.get_meta("cascade_array_key_cache_valid", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)
	scroll.get_v_scroll_bar().value += 60.0
	await _frames(3)
	_expect("Array scroll cannot reuse keys after a failed invalidation", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys and document.diagnostics.any(func(diagnostic): return "duplicated" in str(diagnostic.get("message", ""))))
	items[0] = valid_first
	_expect("valid Array repair restores the scroll cache", document.refresh_binding_paths(PackedStringArray(["items"])) and bool(repeat.get_meta("cascade_array_key_cache_valid", false)))
	items[0] = {"name": "Missing Array key"}
	_expect("invalid Array missing key is rejected", not document.refresh_binding_paths(PackedStringArray(["items"])) and not bool(repeat.get_meta("cascade_array_key_cache_valid", true)))
	scroll.get_v_scroll_bar().value += 60.0
	await _frames(3)
	_expect("Array scroll preserves missing-key atomic failure", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)
	items[0] = valid_first
	_expect("Array missing-key repair succeeds", document.refresh_binding_paths(PackedStringArray(["items"])))
	await _dispose_document(document, paths)


func _test_moving_virtual_origin(model: ArrayItemModel) -> void:
	var prefix_model := ArrayItemModel.new(
		[{"id": "prefix-one", "name": "Prefix one"}],
		func(item: Dictionary): return item["id"]
	)
	var paths := _write_pair("moving_virtual_origin", """<Page>
	<Scroll id="viewport">
		<Column>
			<Repeat id="prefix" items="{prefix_model}" key="id"><Label text="{item.name}" /></Repeat>
			<Repeat id="rows" items="{model}" key="id" virtual="true" item-height="60" overscan="2"><Label text="{item.name}" /></Repeat>
		</Column>
	</Scroll>
</Page>""", "Page { width: 400px; height: 240px; } #viewport { width: 400px; height: 240px; } Column { gap: 0px; } #prefix { gap: 0px; } #rows { gap: 0px; }")
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"model": model, "prefix_model": prefix_model}
	document.markup_path = paths[0]
	document.stylesheet_path = paths[1]
	document.size = Vector2(400.0, 240.0)
	root.add_child(document)
	_expect("moving-origin document loads (%s)" % [document.diagnostics], document.reload_document())
	await _frames(3)
	var repeat: Control = document.get_element_by_id("rows")
	var scroll: ScrollContainer = document.get_element_by_id("viewport")
	scroll.get_v_scroll_bar().value = 100_007.5
	await _frames(3)
	var before_origin := float(repeat.get_meta("cascade_virtual_scroll_origin", -1.0))
	var before_offset := float(repeat.get_meta("cascade_virtual_scroll_offset", -1.0))
	var before_first := int(repeat.get_meta("cascade_virtual_first_index", -1))
	_expect("prefix insertion succeeds", prefix_model.insert(0, {"id": "prefix-zero", "name": "Prefix zero"}))
	await _frames(4)
	repeat = document.get_element_by_id("rows")
	var after_origin := float(repeat.get_meta("cascade_virtual_scroll_origin", -1.0))
	_expect("virtual origin follows preceding sibling growth", after_origin > before_origin)
	_expect("moving origin resynchronizes the bounded window", int(repeat.get_meta("cascade_virtual_first_index", -1)) <= before_first and float(repeat.get_meta("cascade_virtual_scroll_offset", -1.0)) < before_offset and _realized_rows(repeat).size() <= 15)
	await _dispose_document(document, paths)


func _test_bound_virtual_contracts() -> void:
	var model := ArrayItemModel.new([{"id": "one", "name": "One"}], func(item: Dictionary): return item["id"])
	var context := {"model": model, "row_class": ""}
	var paths := _write_pair("bound_virtual_contracts", """<Page><Scroll id="viewport">
	<Repeat id="rows" class="{row_class}" items="{model}" key="id" virtual="true" item-height="60" overscan="1"><Label text="{item.name}" /></Repeat>
</Scroll></Page>""", "Page { height: 180px; } #viewport { height: 180px; } #rows { gap: 0px; } .padded { padding: 4px; }")
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = context
	document.markup_path = paths[0]
	document.stylesheet_path = paths[1]
	root.add_child(document)
	_expect("bound-contract document loads (%s)" % [document.diagnostics], document.reload_document())
	var repeat: Control = document.get_element_by_id("rows")
	var stable_row: Control = _realized_rows(repeat)[0]
	var stable_id := stable_row.get_instance_id()
	_expect("oversized bound row enters model", model.update(0, {"id": "one", "name": "One\nTwo\nThree\nFour\nFive\nSix"}))
	_expect("post-binding row overflow is rejected atomically (%s, %s)" % [document.last_binding_trace(), document.diagnostics], not bool(document.last_binding_trace().get("success", true)) and _realized_rows(repeat)[0].get_instance_id() == stable_id and str(_realized_rows(repeat)[0].get("text")) == "One" and document.diagnostics.any(func(diagnostic): return "after binding values" in str(diagnostic.get("message", ""))))
	_expect("repairing bound row recovers", model.update(0, {"id": "one", "name": "One repaired"}) and bool(document.last_binding_trace().get("success", false)))
	context["row_class"] = "padded"
	_expect("bound Repeat padding is rejected", not document.refresh_binding_paths(PackedStringArray(["row_class"])) and not "padded" in _classes(document.get_element_by_id("rows")) and document.diagnostics.any(func(diagnostic): return "vertical padding or borders" in str(diagnostic.get("message", ""))))
	context["row_class"] = ""
	_expect("bound Repeat class repair succeeds", document.refresh_binding_paths(PackedStringArray(["row_class"])))
	await _dispose_document(document, paths)


func _test_invalid_model_transition() -> void:
	var model_a := ArrayItemModel.new([{"id": "a", "name": "A"}], func(item: Dictionary): return item["id"])
	var model_b := ArrayItemModel.new([{"id": "b", "name": "B"}, {"id": "b", "name": "Duplicate"}], func(item: Dictionary): return item["id"])
	var paths := _write_pair("invalid_model_transition", "<Page><Scroll><Repeat id=\"rows\" items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"60\"><Label text=\"{item.name}\" /></Repeat></Scroll></Page>", "Page { height: 180px; } Scroll { height: 180px; }")
	var document := await _load_document(paths, model_a)
	var repeat: Control = document.get_element_by_id("rows")
	var stable_keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
	document.binding_context = {"model": model_b}
	_expect("transition to invalid model retains last valid tree", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)
	var repaired := model_b.remove_at(1)
	_expect("repairing newly resolved model emits automatic recovery (%s, %s, %s)" % [document.last_binding_trace(), repeat.get_meta("cascade_collection_model"), repeat.get_meta("cascade_repeat_keys", PackedStringArray())], repaired and bool(document.last_binding_trace().get("success", false)) and repeat.get_meta("cascade_collection_model") == model_b and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == PackedStringArray(["b"]))
	await _dispose_document(document, paths)


func _test_writeback_virtual_contract() -> void:
	var model := ArrayItemModel.new([{"id": "one"}], func(item: Dictionary): return item["id"])
	var context := {"model": model, "caption": "Short"}
	var paths := _write_pair("writeback_virtual_contract", """<Page>
	<TextInput id="editor" bind-text="{caption}" />
	<Scroll><Repeat id="rows" items="{model}" key="id" virtual="true" item-height="60"><Label text="{caption}" /></Repeat></Scroll>
</Page>""", "Page { height: 220px; } Scroll { height: 160px; }")
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = context
	document.markup_path = paths[0]
	document.stylesheet_path = paths[1]
	root.add_child(document)
	_expect("writeback virtual contract loads", document.reload_document())
	var repeat: Control = document.get_element_by_id("rows")
	var row: Control = _realized_rows(repeat)[0]
	var stable_id := row.get_instance_id()
	var editor: LineEdit = document.get_element_by_id("editor")
	editor.text = "One\nTwo\nThree\nFour\nFive"
	editor.text_changed.emit(editor.text)
	_expect("writeback overlapping a virtual row uses atomic candidate validation", context["caption"].contains("Five") and not bool(document.last_binding_trace().get("success", true)) and _realized_rows(repeat)[0].get_instance_id() == stable_id and str(_realized_rows(repeat)[0].get("text")) == "Short")
	context["caption"] = "Repaired"
	_expect("writeback overflow can be repaired explicitly", document.refresh_binding_paths(PackedStringArray(["caption"])) and str(_realized_rows(repeat)[0].get("text")) == "Repaired")
	await _dispose_document(document, paths)


func _test_malformed_delta_blocks_scroll() -> void:
	var items: Array = []
	for index in 100:
		items.append({"id": "malformed-%03d" % index, "name": "Item %s" % index})
	var model := ArrayItemModel.new(items, func(item: Dictionary): return item["id"])
	var paths := _write_pair("malformed_delta", "<Page><Scroll id=\"viewport\"><Repeat id=\"rows\" items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"60\"><Label text=\"{item.name}\" /></Repeat></Scroll></Page>", "Page { height: 180px; } #viewport { height: 180px; }")
	var document := await _load_document(paths, model)
	var repeat: Control = document.get_element_by_id("rows")
	var scroll: ScrollContainer = document.get_element_by_id("viewport")
	var stable_keys: PackedStringArray = repeat.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
	model._items[0] = {"id": "silently-changed", "name": "Changed without a valid delta"}
	model.changed.emit(CollectionChange.updated(999))
	_expect("malformed delta invalidates the retained transaction", not bool(document.last_binding_trace().get("success", true)) and not bool(repeat.get_meta("cascade_collection_transaction_valid", true)))
	scroll.get_v_scroll_bar().value += 60.0
	await _frames(3)
	_expect("scroll cannot commit after malformed delta", not bool(document.last_binding_trace().get("success", true)) and repeat.get_meta("cascade_repeat_keys", PackedStringArray()) == stable_keys)
	model.reset(model.items())
	_expect("RESET safely recovers malformed model", bool(document.last_binding_trace().get("success", false)) and str(repeat.get_meta("cascade_repeat_keys", PackedStringArray())[0]) == "silently-changed")
	await _dispose_document(document, paths)


func _test_multi_repeat_transaction() -> void:
	var model := ArrayItemModel.new([
		{"id": "one", "alternate": "alpha", "name": "One"},
		{"id": "two", "alternate": "beta", "name": "Two"},
	], func(item: Dictionary): return item["id"])
	var paths := _write_pair("multi_repeat_transaction", """<Page><Scroll><Column>
	<Repeat id="primary" items="{model}" key="id" virtual="true" item-height="60"><Label text="{item.name}" /></Repeat>
	<Repeat id="alternate" items="{model}" key="alternate" virtual="true" item-height="60"><Label text="{item.name}" /></Repeat>
</Column></Scroll></Page>""", "Page { height: 180px; } Scroll { height: 180px; } Column { gap: 0px; }")
	var document := await _load_document(paths, model)
	var primary: Control = document.get_element_by_id("primary")
	var alternate: Control = document.get_element_by_id("alternate")
	var primary_keys: PackedStringArray = primary.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
	var alternate_keys: PackedStringArray = alternate.get_meta("cascade_repeat_keys", PackedStringArray()).duplicate()
	_expect("one-key-path collision enters shared model", model.update(1, {"id": "two", "alternate": "alpha", "name": "Two"}))
	_expect("multi-Repeat delta aborts both trees", not bool(document.last_binding_trace().get("success", true)) and primary.get_meta("cascade_repeat_keys", PackedStringArray()) == primary_keys and alternate.get_meta("cascade_repeat_keys", PackedStringArray()) == alternate_keys)
	var diagnostic_count := document.diagnostics.size()
	var scroll := primary.get_parent().get_parent() as ScrollContainer
	scroll.get_v_scroll_bar().value += 10.0
	await _frames(3)
	_expect("blocked sibling scroll preserves transaction diagnostic", not bool(document.last_binding_trace().get("success", true)) and document.diagnostics.size() == diagnostic_count and primary.get_meta("cascade_repeat_keys", PackedStringArray()) == primary_keys)
	_expect("repairing all key paths commits together", model.update(1, {"id": "two", "alternate": "beta", "name": "Two"}) and bool(document.last_binding_trace().get("success", false)))
	await _dispose_document(document, paths)


func _test_padded_scroll_viewport(model: ArrayItemModel) -> void:
	var paths := _write_pair("padded_scroll_viewport", "<Page><Scroll id=\"viewport\"><Repeat id=\"rows\" items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"60\" overscan=\"0\"><Label text=\"{item.name}\" /></Repeat></Scroll></Page>", "Page { width: 400px; height: 240px; } #viewport { width: 400px; height: 240px; padding: 12px; border: 2px solid #334455; }")
	var document := await _load_document(paths, model)
	var repeat: Control = document.get_element_by_id("rows")
	var scroll: ScrollContainer = document.get_element_by_id("viewport")
	var bar := scroll.get_v_scroll_bar()
	_expect("virtual viewport uses native scrollbar page", is_equal_approx(float(repeat.get_meta("cascade_virtual_viewport_extent", -1.0)), bar.page) and bar.page < scroll.size.y)
	bar.value = bar.max_value
	await _frames(3)
	_expect("padded Scroll reaches final model neighborhood", _realized_rows(repeat).any(func(row: Control): return int(row.get_meta("cascade_repeat_index", -1)) == model.item_count() - 1))
	await _dispose_document(document, paths)


func _test_invalid_virtual_contract(model: ArrayItemModel) -> void:
	var paths := _write_pair("virtual_invalid", "<Page><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"24\"><Label text=\"{item.name}\" /></Repeat></Page>", "Page { height: 240px; }")
	var document := await _load_document(paths, model)
	_expect("virtual repeat without Scroll is rejected", document.generated_root() == null and document.diagnostics.any(func(diagnostic): return "Scroll ancestor" in str(diagnostic.get("message", ""))))
	await _dispose_document(document, paths)
	await _expect_invalid_virtual(
		"oversized_item",
		"<Page><Scroll><Repeat id=\"rows\" items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"20\"><Button text=\"{item.name}\" /></Repeat></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; }",
		model,
		"minimum height"
	)
	await _expect_invalid_virtual(
		"repeat_padding",
		"<Page><Scroll><Repeat id=\"rows\" items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Label text=\"{item.name}\" /></Repeat></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; } #rows { padding: 2px; }",
		model,
		"vertical padding or borders"
	)
	await _expect_invalid_virtual(
		"table_row_gap",
		"<Page><Scroll><Table id=\"table\"><TableBody><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"24\"><TableRow><TableCell text=\"{item.name}\" /></TableRow></Repeat></TableBody></Table></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; } #table { grid-template-columns: 1fr; row-gap: 2px; }",
		model,
		"row-gap: 0"
	)
	var small_model := ArrayItemModel.new([{"id": "one", "name": "One"}], func(item: Dictionary): return item["id"])
	await _expect_invalid_virtual(
		"nested_repeat",
		"<Page><Scroll><Repeat items=\"{model}\" key=\"id\"><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Label text=\"{item.name}\" /></Repeat></Repeat></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; }",
		small_model,
		"cannot be nested"
	)
	await _expect_invalid_virtual(
		"conditional_item",
		"<Page><Scroll><Repeat items=\"{model}\" key=\"id\" virtual=\"true\" item-height=\"44\"><Label if=\"{item.visible}\" text=\"{item.name}\" /></Repeat></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; }",
		small_model,
		"item roots cannot use 'if'"
	)
	await _expect_invalid_virtual(
		"repeat_autofocus",
		"<Page><Repeat items=\"{model}\" key=\"id\"><Button autofocus=\"true\" text=\"{item.name}\" /></Repeat></Page>",
		"Page { height: 240px; }",
		small_model,
		"cannot author autofocus"
	)
	var false_paths := _write_pair("repeat_false_focus", "<Page><Repeat items=\"{model}\" key=\"id\"><Button autofocus=\"no\" focus-trap=\"off\" text=\"{item.name}\" /></Repeat></Page>", "Page { height: 240px; }")
	var false_document := await _load_document(false_paths, small_model)
	_expect("false focus spellings match builder semantics", false_document.generated_root() != null)
	await _dispose_document(false_document, false_paths)
	await _expect_invalid_virtual(
		"nested_repeat_on",
		"<Page><Scroll><Repeat items=\"{model}\" key=\"id\"><Repeat items=\"{model}\" key=\"id\" virtual=\"on\" item-height=\"44\"><Label text=\"{item.name}\" /></Repeat></Repeat></Scroll></Page>",
		"Page { height: 240px; } Scroll { height: 240px; }",
		small_model,
		"cannot be nested"
	)


func _expect_invalid_virtual(name: String, markup: String, stylesheet: String, model: ArrayItemModel, message_fragment: String) -> void:
	var paths := _write_pair(name, markup, stylesheet)
	var document := await _load_document(paths, model)
	_expect(
		"%s contract is rejected (%s)" % [name, document.diagnostics],
		document.generated_root() == null and document.diagnostics.any(func(diagnostic): return message_fragment in str(diagnostic.get("message", "")))
	)
	await _dispose_document(document, paths)


func _load_document(paths: PackedStringArray, model: ArrayItemModel) -> CascadeDocument:
	var document := CascadeDocument.new()
	document.load_on_ready = false
	document.watch_sources = false
	document.log_diagnostics_to_console = false
	document.binding_context = {"model": model}
	document.markup_path = paths[0]
	document.stylesheet_path = paths[1]
	document.size = Vector2(480.0, 240.0)
	root.add_child(document)
	document.reload_document()
	await _frames(3)
	return document


func _dispose_document(document: CascadeDocument, paths: PackedStringArray) -> void:
	document.queue_free()
	await process_frame
	for path in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_pair(name: String, markup: String, stylesheet: String) -> PackedStringArray:
	var markup_path := "user://cascade_%s.gxml" % name
	var stylesheet_path := "user://cascade_%s.gcss" % name
	_expect("write %s markup" % name, _write(markup_path, markup))
	_expect("write %s stylesheet" % name, _write(stylesheet_path, stylesheet))
	return PackedStringArray([markup_path, stylesheet_path])


func _realized_rows(repeat: Control) -> Array[Control]:
	var result: Array[Control] = []
	for child in repeat.get_children():
		if child is Control and child.has_meta("cascade_repeat_index"):
			result.append(child)
	return result


func _classes(control: Control) -> PackedStringArray:
	return control.get_meta("cascade_classes", PackedStringArray())


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _write(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(contents)
	return true


func _expect(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
