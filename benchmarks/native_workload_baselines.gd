class_name CascadeNativeWorkloadBaselines
extends RefCounted

## Hand-authored native Godot Control trees used by workload_benchmark.gd.
##
## These intentionally avoid GodotCascade, custom themes, and third-party code.
## They reproduce the semantic content and native-control shape of each benchmark
## workload; they are not pixel-for-pixel showcase reimplementations.

const INVENTORY_COUNT := 10_000
const DEFAULT_VIRTUAL_INVENTORY_ROWS := 22


static func settings_menu() -> Control:
	var page := _column("NativeSettingsMenu")
	page.add_child(_heading("GAME SETTINGS", "Graphics & display", "Native form-control baseline"))

	var content := _row("SettingsContent")
	content.add_child(_settings_effects_panel())
	content.add_child(_settings_window_panel())
	page.add_child(content)

	var monitor := _panel_column("BindingMonitor")
	var monitor_content := _panel_content(monitor)
	monitor_content.add_child(_label("LIVE BINDING MODEL"))
	monitor_content.add_child(_label("Form values reflected by application state"))
	var values := _row("BindingValues")
	for text in ["PROFILE\nRhea", "QUALITY\nhigh", "UI SCALE\n100", "SHADOWS\ntrue"]:
		values.add_child(_label(text))
	monitor_content.add_child(values)
	page.add_child(monitor)

	var footer := _row("SettingsFooter")
	footer.add_child(_label("Change a setting, then apply"))
	footer.add_child(_label("QUALITY"))
	var quality := OptionButton.new()
	for quality_name in ["Low quality", "Medium quality", "High quality", "Ultra quality"]:
		quality.add_item(quality_name)
	quality.select(2)
	footer.add_child(quality)
	footer.add_child(_button("Apply settings"))
	page.add_child(footer)
	return page


static func system_status_dashboard() -> Control:
	var page := _column("NativeSystemStatus")
	page.add_child(_heading("EXPEDITION 07 · LIVE TELEMETRY", "Helios systems", "Resource allocation across the current deep-space route."))

	var content := _row("DashboardContent")
	var overview := _panel_column("PowerReserve")
	var overview_content := _panel_content(overview)
	overview_content.add_child(_label("POWER RESERVE"))
	var metric := _row("ReserveMetric")
	metric.add_child(_label("72%"))
	metric.add_child(_label("+4.8% this cycle"))
	overview_content.add_child(metric)
	overview_content.add_child(_progress(72.0))
	overview_content.add_child(_label("18h 42m estimated endurance at current draw"))
	content.add_child(overview)

	var systems := _column("Systems")
	for system in [["Reactor output", 84.0], ["Life support", 96.0], ["Navigation array", 63.0]]:
		var card := _panel_column(str(system[0]).replace(" ", ""))
		var card_content := _panel_content(card)
		var heading := _row("SystemHeading")
		heading.add_child(_label(str(system[0])))
		heading.add_child(_label("%d%%" % int(system[1])))
		card_content.add_child(heading)
		card_content.add_child(_progress(float(system[1])))
		systems.add_child(card)
	content.add_child(systems)
	page.add_child(content)

	var footer := _row("DashboardFooter")
	footer.add_child(_label("Last synchronized 14 seconds ago"))
	footer.add_child(_label("LIVE"))
	footer.add_child(_label("LINKED"))
	footer.add_child(_button("Review route"))
	page.add_child(footer)
	return page


static func leaderboard() -> Control:
	var page := _column("NativeLeaderboard")
	page.add_child(_heading("SEASON 12 · COMPETITIVE", "Flight leaderboard", "Five sortable, removable standings rows"))
	var scroll := ScrollContainer.new()
	scroll.name = "LeaderboardScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.name = "LeaderboardGrid"
	grid.columns = 7
	for title in ["", "Rank", "Pilot", "Division", "Wins", "Rating", "Action"]:
		grid.add_child(_label(title))
	var pilots := [
		["1", "Milo Vance", "Apex", "31", "2294"],
		["2", "Rhea Sol", "Apex", "28", "2210"],
		["3", "Tarin Vale", "Nova", "24", "2148"],
		["4", "Ilya Chen", "Nova", "22", "2087"],
		["5", "Soren Pike", "Drift", "19", "1996"],
	]
	for pilot in pilots:
		grid.add_child(_button("↕"))
		for value in pilot:
			grid.add_child(_label(str(value)))
		grid.add_child(_button("Remove"))
	scroll.add_child(grid)
	page.add_child(scroll)
	var footer := _row("LeaderboardFooter")
	footer.add_child(_label("Drag a handle to reorder"))
	footer.add_child(_button("Sort by rating"))
	footer.add_child(_button("Add pilot"))
	page.add_child(footer)
	return page


static func virtual_inventory(realized_row_count: int = DEFAULT_VIRTUAL_INVENTORY_ROWS) -> Control:
	realized_row_count = clampi(realized_row_count, 1, INVENTORY_COUNT)
	var page := _inventory_shell("NativeVirtualInventory")
	var model: Array[Dictionary] = _inventory_model()
	page.set_meta("benchmark_model", model)
	page.set_meta("benchmark_model_count", model.size())
	page.set_meta("benchmark_realized_count", realized_row_count)

	var scroll := ScrollContainer.new()
	scroll.name = "InventoryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var window := VBoxContainer.new()
	window.name = "FixedExtentWindow"
	var grid := GridContainer.new()
	grid.name = "VisibleInventoryGrid"
	grid.columns = 3
	for title in ["Record", "Category", "Value"]:
		grid.add_child(_label(title))
	for index in realized_row_count:
		var item: Dictionary = model[index]
		grid.add_child(_label(item["name"]))
		grid.add_child(_label(item["category"]))
		grid.add_child(_label(item["value"]))
	window.add_child(grid)
	var remaining_extent := Control.new()
	remaining_extent.name = "UnrealizedExtent"
	remaining_extent.custom_minimum_size.y = float(INVENTORY_COUNT - realized_row_count) * 36.0
	remaining_extent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(remaining_extent)
	scroll.add_child(window)
	page.add_child(scroll)
	return page


static func item_list_inventory() -> Control:
	var page := _inventory_shell("NativeItemListInventory")
	var list := ItemList.new()
	list.name = "InventoryItemList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for index in INVENTORY_COUNT:
		list.add_item("Cargo record %05d · %s · %s cr" % [
			index,
			["Navigation", "Reactor", "Medical", "Survey"][index % 4],
			1200 + (index * 73) % 88_000,
		])
	page.set_meta("benchmark_model_count", list.item_count)
	page.set_meta("benchmark_realized_count", list.item_count)
	page.add_child(list)
	return page


static func _settings_effects_panel() -> Control:
	var panel := _panel_column("EffectsPanel")
	var content := _panel_content(panel)
	content.add_child(_label("Effects"))
	content.add_child(_label("Tune visual features independently."))
	var profile := _row("Profile")
	profile.add_child(_label("Profile"))
	var edit := LineEdit.new()
	edit.text = "Rhea"
	profile.add_child(edit)
	content.add_child(profile)
	for option in [["Dynamic shadows", true, false], ["Bloom", true, false], ["Vertical sync", true, false], ["Ray tracing · unavailable", false, true], ["Damage numbers", true, false], ["Team markers", false, false]]:
		var check := CheckButton.new()
		check.text = str(option[0])
		check.button_pressed = bool(option[1])
		check.disabled = bool(option[2])
		content.add_child(check)
	return panel


static func _settings_window_panel() -> Control:
	var panel := _panel_column("WindowPanel")
	var content := _panel_content(panel)
	content.add_child(_label("Window mode"))
	content.add_child(_label("Choose one native radio-group option."))
	var group := ButtonGroup.new()
	for option in ["Windowed", "Borderless", "Exclusive fullscreen"]:
		var radio := CheckButton.new()
		radio.text = option
		radio.button_group = group
		radio.button_pressed = option == "Borderless"
		content.add_child(radio)
	var scale := _row("Scale")
	scale.add_child(_label("UI scale"))
	var slider := HSlider.new()
	slider.min_value = 75.0
	slider.max_value = 125.0
	slider.value = 100.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale.add_child(slider)
	scale.add_child(_label("100%"))
	content.add_child(scale)
	content.add_child(_label("Session notes"))
	var notes := TextEdit.new()
	notes.text = "Ready for the next match."
	notes.custom_minimum_size.y = 72.0
	content.add_child(notes)
	return panel


static func _inventory_shell(node_name: String) -> VBoxContainer:
	var page := _column(node_name)
	page.add_child(_heading("SCALE LAB · FIXED EXTENT", "Virtual inventory", "10,000 records"))
	var toolbar := _row("InventoryToolbar")
	for text in ["Jump to top", "Jump to 5,000", "Jump to end", "Insert record", "Remove first"]:
		toolbar.add_child(_button(text))
	page.add_child(toolbar)
	page.add_child(_label("Only the visible record window is materialized"))
	return page


static func _inventory_model() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(INVENTORY_COUNT)
	for index in INVENTORY_COUNT:
		result[index] = {
			"id": "record-%05d" % index,
			"name": "Cargo record %05d" % index,
			"category": ["Navigation", "Reactor", "Medical", "Survey"][index % 4],
			"value": "%s cr" % (1200 + (index * 73) % 88_000),
		}
	return result


static func _heading(eyebrow: String, title: String, subtitle: String) -> VBoxContainer:
	var heading := _column("Heading")
	heading.add_child(_label(eyebrow))
	heading.add_child(_label(title))
	heading.add_child(_label(subtitle))
	return heading


static func _column(node_name: String) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.name = node_name
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return result


static func _row(node_name: String) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.name = node_name
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


static func _panel_column(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_column("Content"))
	return panel


static func _panel_content(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0) as VBoxContainer


static func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


static func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	return button


static func _progress(value: float) -> ProgressBar:
	var progress := ProgressBar.new()
	progress.max_value = 100.0
	progress.value = value
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return progress
