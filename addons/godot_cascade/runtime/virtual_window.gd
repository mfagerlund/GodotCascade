class_name CascadeVirtualWindow
extends RefCounted

## Event-driven fixed-extent vertical virtualization math.
## [member end_index] is exclusive and the spacer extents sum with realized rows
## to [member content_extent].

signal range_changed(first_index: int, end_index: int)

var item_count: int = 0
var item_extent: float = 1.0
var viewport_extent: float = 0.0
var overscan: int = 0
var scroll_offset: float = 0.0

var first_index: int = 0
var end_index: int = 0
var top_spacer_extent: float = 0.0
var bottom_spacer_extent: float = 0.0
var content_extent: float = 0.0


func _init(new_item_count: int = 0, new_item_extent: float = 1.0, new_viewport_extent: float = 0.0, new_overscan: int = 0) -> void:
	item_count = maxi(0, new_item_count)
	item_extent = maxf(0.001, new_item_extent)
	viewport_extent = maxf(0.0, new_viewport_extent)
	overscan = maxi(0, new_overscan)
	_recalculate(false)


## Reconfigures the fixed geometry and emits only if the realized range changes.
func configure(new_item_count: int, new_item_extent: float, new_viewport_extent: float, new_overscan: int = 0) -> bool:
	if new_item_extent <= 0.0:
		return false
	item_count = maxi(0, new_item_count)
	item_extent = new_item_extent
	viewport_extent = maxf(0.0, new_viewport_extent)
	overscan = maxi(0, new_overscan)
	_recalculate(true)
	return true


## Applies a scroll event. Offsets are clamped to the content's reachable range.
func set_scroll_offset(new_offset: float) -> void:
	scroll_offset = new_offset
	_recalculate(true)


func realized_count() -> int:
	return end_index - first_index


func _recalculate(emit_change: bool) -> void:
	var previous_first := first_index
	var previous_end := end_index
	content_extent = float(item_count) * item_extent
	var maximum_offset := maxf(0.0, content_extent - viewport_extent)
	scroll_offset = clampf(scroll_offset, 0.0, maximum_offset)
	if item_count == 0 or viewport_extent <= 0.0:
		first_index = 0
		end_index = 0
	else:
		var visible_first := mini(item_count, int(floor(scroll_offset / item_extent)))
		var visible_end := mini(item_count, int(ceil((scroll_offset + viewport_extent) / item_extent)))
		first_index = maxi(0, visible_first - overscan)
		end_index = mini(item_count, visible_end + overscan)
	top_spacer_extent = float(first_index) * item_extent
	bottom_spacer_extent = float(item_count - end_index) * item_extent
	if emit_change and (first_index != previous_first or end_index != previous_end):
		range_changed.emit(first_index, end_index)
