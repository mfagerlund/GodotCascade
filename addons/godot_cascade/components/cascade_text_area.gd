@tool
extends TextEdit

## Adapted multiline text entry: Godot owns editing; Cascade owns its box and validation state.

signal validation_changed(valid: bool, message: String)

const FocusVisibilityTracker := preload("res://addons/godot_cascade/components/focus_visibility_tracker.gd")

@export_group("Computed Style")
@export var cascade_style: CascadeStyle = CascadeStyle.new():
	set(next):
		var resolved := next if next != null else CascadeStyle.new()
		if cascade_style == resolved:
			return
		if cascade_style != null and cascade_style.invalidated.is_connected(_on_style_invalidated):
			cascade_style.invalidated.disconnect(_on_style_invalidated)
		cascade_style = resolved
		_connect_style()
		_sync_theme()

@export_group("Appearance")
@export var text_color := Color("f2f4f7"):
	set(next):
		text_color = next
		_sync_theme()
@export var font: Font:
	set(next):
		font = next
		_sync_theme()
		update_minimum_size()
@export_range(1, 256, 1, "or_greater") var font_size := 16:
	set(next):
		font_size = maxi(next, 1)
		_sync_theme()
		update_minimum_size()
@export var placeholder_color := Color("667085"):
	set(next):
		placeholder_color = next
		_sync_theme()
@export var hover_background_color := Color("182235"):
	set(next):
		hover_background_color = next
		_sync_theme()
@export var focused_background_color := Color("131b2a"):
	set(next):
		focused_background_color = next
		_sync_theme()
@export var disabled_background_color := Color("111827"):
	set(next):
		disabled_background_color = next
		_sync_theme()
@export var disabled_text_color := Color("667085"):
	set(next):
		disabled_text_color = next
		_sync_theme()
@export var invalid_background_color := Color("2a1720"):
	set(next):
		invalid_background_color = next
		_sync_theme()
@export var invalid_text_color := Color("f2f4f7"):
	set(next):
		invalid_text_color = next
		_sync_theme()
@export var invalid_border_color := Color("f97066"):
	set(next):
		invalid_border_color = next
		_sync_theme()
@export var focus_ring_color := Color("84adff"):
	set(next):
		focus_ring_color = next
		_sync_theme()
@export var focus_ring_width := 2.0:
	set(next):
		focus_ring_width = maxf(next, 0.0)
		_sync_theme()
@export var focus_visible_ring_color := Color("84adff"):
	set(next):
		focus_visible_ring_color = next
		_sync_theme()
@export var focus_visible_ring_width := 2.0:
	set(next):
		focus_visible_ring_width = maxf(next, 0.0)
		_sync_theme()
@export var focus_visible_style_enabled := false:
	set(next):
		focus_visible_style_enabled = next
		_sync_theme()

@export_group("Editing")
@export var disabled := false:
	set(next):
		disabled = next
		_sync_editability()
@export var read_only := false:
	set(next):
		read_only = next
		_sync_editability()
@export_range(0, 1000000, 1, "or_greater") var max_length := 0:
	set(next):
		max_length = maxi(next, 0)
		_enforce_max_length()

@export_group("Validation")
@export var required := false:
	set(next):
		required = next
		validate()
@export var validation_pattern := "":
	set(next):
		validation_pattern = next
		_compile_pattern()
		validate()
@export var validation_message := "Invalid value.":
	set(next):
		validation_message = next
		validate()
@export var invalid := false:
	set(next):
		if invalid == next:
			return
		invalid = next
		_sync_theme()

var _compiled_pattern: RegEx
var _pattern_error := ""
var _focus_tracker: RefCounted
var _last_validation_message := ""
var _mouse_inside := false
var _base_accessibility_description := ""
var _enforcing_max_length := false


func _init() -> void:
	context_menu_enabled = true
	selecting_enabled = true
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	scroll_fit_content_height = false
	cascade_style.padding_left = 12.0
	cascade_style.padding_top = 8.0
	cascade_style.padding_right = 12.0
	cascade_style.padding_bottom = 8.0
	cascade_style.background_color = Color("131b2a")
	cascade_style.border_color = Color("405477")
	cascade_style.border_width = 1.0
	cascade_style.border_radius = 8.0


func _ready() -> void:
	_connect_style()
	_base_accessibility_description = str(get_meta("cascade_authored_accessible_description", accessibility_description))
	_focus_tracker = FocusVisibilityTracker.new()
	_focus_tracker.attach(self)
	_focus_tracker.changed.connect(_sync_theme)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_sync_theme)
	focus_exited.connect(_sync_theme)
	text_changed.connect(_on_text_changed)
	_sync_editability()
	_sync_theme()
	validate()


func _get_minimum_size() -> Vector2:
	var resolved_font := font if font != null else get_theme_default_font()
	var sample := placeholder_text if text.is_empty() else text
	var content := Vector2(160.0, float(font_size) * 4.0)
	if resolved_font != null:
		var measured := resolved_font.get_multiline_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		content.x = maxf(measured.x, 160.0)
		content.y = maxf(measured.y, resolved_font.get_height(font_size) * 4.0)
	var minimum := content + Vector2(
		cascade_style.padding_left + cascade_style.padding_right + cascade_style.border_width * 2.0,
		cascade_style.padding_top + cascade_style.padding_bottom + cascade_style.border_width * 2.0
	)
	return cascade_style.constrain_minimum(minimum)


## Re-evaluates authored constraints and returns true when the current text is valid.
func validate() -> bool:
	var message := ""
	if required and text.strip_edges().is_empty():
		message = validation_message if not validation_message.is_empty() else "A value is required."
	elif not _pattern_error.is_empty():
		message = _pattern_error
	elif _compiled_pattern != null and _compiled_pattern.search(text) == null:
		message = validation_message if not validation_message.is_empty() else "The value has an invalid format."
	var next_invalid := not message.is_empty()
	var changed := invalid != next_invalid or _last_validation_message != message
	invalid = next_invalid
	_last_validation_message = message
	accessibility_description = _base_accessibility_description if message.is_empty() else (
		message if _base_accessibility_description.is_empty() else "%s %s" % [_base_accessibility_description, message]
	)
	if changed:
		validation_changed.emit(not invalid, message)
	return not invalid


func current_validation_message() -> String:
	return _last_validation_message


func validation_pattern_is_valid() -> bool:
	return _pattern_error.is_empty()


func cascade_focus_visible() -> bool:
	return _focus_tracker != null and bool(_focus_tracker.is_focus_visible())


## Captures native editing state before a keyed hot reload updates authored properties.
func capture_runtime_state() -> Dictionary:
	return {
		"text": text,
		"caret_line": get_caret_line(),
		"caret_column": get_caret_column(),
		"selection_from_line": get_selection_from_line() if has_selection() else -1,
		"selection_from_column": get_selection_from_column() if has_selection() else -1,
		"selection_to_line": get_selection_to_line() if has_selection() else -1,
		"selection_to_column": get_selection_to_column() if has_selection() else -1,
		"scroll_vertical": scroll_vertical,
		"scroll_horizontal": scroll_horizontal,
	}


## Restores native text, primary caret, selection, and scroll after a compatible keyed reload.
func restore_runtime_state(state: Dictionary) -> void:
	text = str(state.get("text", text))
	var caret_line := _clamped_line(int(state.get("caret_line", get_caret_line())))
	set_caret_line(caret_line)
	set_caret_column(_clamped_column(caret_line, int(state.get("caret_column", get_caret_column()))))
	var from_line := int(state.get("selection_from_line", -1))
	var to_line := int(state.get("selection_to_line", -1))
	if from_line >= 0 and to_line >= from_line:
		from_line = _clamped_line(from_line)
		to_line = _clamped_line(to_line)
		select(
			from_line,
			_clamped_column(from_line, int(state.get("selection_from_column", 0))),
			to_line,
			_clamped_column(to_line, int(state.get("selection_to_column", 0)))
		)
	else:
		deselect()
	scroll_vertical = float(state.get("scroll_vertical", scroll_vertical))
	scroll_horizontal = int(state.get("scroll_horizontal", scroll_horizontal))
	validate()


func _clamped_line(line: int) -> int:
	return clampi(line, 0, maxi(get_line_count() - 1, 0))


func _clamped_column(line: int, column: int) -> int:
	return clampi(column, 0, get_line(line).length())


func _compile_pattern() -> void:
	_compiled_pattern = null
	_pattern_error = ""
	if validation_pattern.is_empty():
		return
	var expression := RegEx.new()
	var error := expression.compile(validation_pattern)
	if error != OK:
		_pattern_error = "Invalid validation pattern."
		return
	_compiled_pattern = expression


func _connect_style() -> void:
	if cascade_style == null or not is_inside_tree():
		return
	if not cascade_style.invalidated.is_connected(_on_style_invalidated):
		cascade_style.invalidated.connect(_on_style_invalidated)


func _on_style_invalidated(_flags: int) -> void:
	_sync_theme()
	update_minimum_size()


func _on_text_changed() -> void:
	_enforce_max_length()
	validate()


func _enforce_max_length() -> void:
	if _enforcing_max_length or max_length <= 0 or text.length() <= max_length:
		return
	_enforcing_max_length = true
	var caret_line := get_caret_line()
	var caret_column := get_caret_column()
	text = text.left(max_length)
	caret_line = _clamped_line(caret_line)
	set_caret_line(caret_line)
	set_caret_column(_clamped_column(caret_line, caret_column))
	_enforcing_max_length = false


func _sync_editability() -> void:
	editable = not disabled and not read_only
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	_sync_theme()


func _on_mouse_entered() -> void:
	_mouse_inside = true
	_sync_theme()


func _on_mouse_exited() -> void:
	_mouse_inside = false
	_sync_theme()


func _sync_theme() -> void:
	if not is_inside_tree():
		return
	var background := cascade_style.background_color
	var border := cascade_style.border_color
	var border_width := cascade_style.border_width
	var resolved_text := text_color
	if disabled:
		background = disabled_background_color
		resolved_text = disabled_text_color
	elif invalid:
		background = invalid_background_color
		border = invalid_border_color
		resolved_text = invalid_text_color
	elif _mouse_inside:
		background = hover_background_color
	elif has_focus():
		background = focused_background_color
	if has_focus():
		if focus_visible_style_enabled:
			if _focus_tracker != null and _focus_tracker.is_focus_visible():
				border = focus_visible_ring_color
				border_width = focus_visible_ring_width
		else:
			border = focus_ring_color
			border_width = focus_ring_width
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(roundi(border_width))
	style.corner_radius_top_left = roundi(cascade_style.border_radius)
	style.corner_radius_top_right = roundi(cascade_style.border_radius)
	style.corner_radius_bottom_left = roundi(cascade_style.border_radius)
	style.corner_radius_bottom_right = roundi(cascade_style.border_radius)
	style.content_margin_left = cascade_style.padding_left
	style.content_margin_top = cascade_style.padding_top
	style.content_margin_right = cascade_style.padding_right
	style.content_margin_bottom = cascade_style.padding_bottom
	add_theme_stylebox_override("normal", style)
	add_theme_stylebox_override("focus", style)
	add_theme_stylebox_override("read_only", style)
	add_theme_color_override("font_color", resolved_text)
	add_theme_color_override("font_readonly_color", resolved_text)
	add_theme_color_override("font_placeholder_color", placeholder_color)
	add_theme_font_size_override("font_size", font_size)
	if font != null:
		add_theme_font_override("font", font)
	else:
		remove_theme_font_override("font")
