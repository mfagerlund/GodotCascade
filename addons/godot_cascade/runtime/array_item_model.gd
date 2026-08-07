class_name CascadeArrayItemModel
extends CascadeItemModel

## Mutable in-memory item model with synchronous, typed change notifications.

var _items: Array = []
var _key_selector: Callable


func _init(initial_items: Array = [], key_selector: Callable = Callable()) -> void:
	_items = initial_items.duplicate()
	_key_selector = key_selector


func item_count() -> int:
	return _items.size()


func item_at(index: int) -> Variant:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


func key_at(index: int) -> Variant:
	if index < 0 or index >= _items.size():
		return null
	if _key_selector.is_valid():
		return _key_selector.call(_items[index])
	return index


func items() -> Array:
	return _items.duplicate()


func append(item: Variant) -> void:
	insert(_items.size(), item)


func insert(index: int, item: Variant) -> bool:
	if index < 0 or index > _items.size():
		return false
	_items.insert(index, item)
	changed.emit(CascadeCollectionChange.inserted(index))
	return true


func insert_many(index: int, new_items: Array) -> bool:
	if index < 0 or index > _items.size() or new_items.is_empty():
		return false
	for offset in new_items.size():
		_items.insert(index + offset, new_items[offset])
	changed.emit(CascadeCollectionChange.inserted(index, new_items.size()))
	return true


func remove_at(index: int) -> bool:
	return remove_range(index, 1)


func remove_range(index: int, remove_count: int) -> bool:
	if remove_count <= 0 or index < 0 or index + remove_count > _items.size():
		return false
	for _offset in remove_count:
		_items.remove_at(index)
	changed.emit(CascadeCollectionChange.removed(index, remove_count))
	return true


## Moves a contiguous range. [param destination_index] is its first index after the move.
func move_items(from_index: int, destination_index: int, move_count: int = 1) -> bool:
	if move_count <= 0 or from_index < 0 or from_index + move_count > _items.size():
		return false
	var remaining_count := _items.size() - move_count
	if destination_index < 0 or destination_index > remaining_count:
		return false
	if destination_index == from_index:
		return false
	var moved_items: Array = []
	for offset in move_count:
		moved_items.append(_items[from_index + offset])
	for _offset in move_count:
		_items.remove_at(from_index)
	for offset in moved_items.size():
		_items.insert(destination_index + offset, moved_items[offset])
	changed.emit(CascadeCollectionChange.moved(from_index, destination_index, move_count))
	return true


func update(index: int, item: Variant) -> bool:
	if index < 0 or index >= _items.size():
		return false
	_items[index] = item
	changed.emit(CascadeCollectionChange.updated(index))
	return true


func reset(new_items: Array = []) -> void:
	_items = new_items.duplicate()
	changed.emit(CascadeCollectionChange.reset_to(_items.size()))


func clear() -> void:
	reset()
