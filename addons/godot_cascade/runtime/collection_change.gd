class_name CascadeCollectionChange
extends RefCounted

## A typed, immutable-by-convention description of one item-model mutation.
## Indices use the collection state before the change except [member to_index],
## which is the moved range's first index in the resulting collection.

enum Kind {
	INSERT,
	REMOVE,
	MOVE,
	UPDATE,
	RESET,
}

var kind: Kind = Kind.RESET
var index: int = 0
var count: int = 0
var to_index: int = -1


func _init(change_kind: Kind = Kind.RESET, change_index: int = 0, change_count: int = 0, destination_index: int = -1) -> void:
	kind = change_kind
	index = change_index
	count = change_count
	to_index = destination_index


static func inserted(at_index: int, inserted_count: int = 1) -> CascadeCollectionChange:
	return CascadeCollectionChange.new(Kind.INSERT, at_index, inserted_count)


static func removed(at_index: int, removed_count: int = 1) -> CascadeCollectionChange:
	return CascadeCollectionChange.new(Kind.REMOVE, at_index, removed_count)


static func moved(from_index: int, destination_index: int, moved_count: int = 1) -> CascadeCollectionChange:
	return CascadeCollectionChange.new(Kind.MOVE, from_index, moved_count, destination_index)


static func updated(at_index: int, updated_count: int = 1) -> CascadeCollectionChange:
	return CascadeCollectionChange.new(Kind.UPDATE, at_index, updated_count)


static func reset_to(new_count: int) -> CascadeCollectionChange:
	return CascadeCollectionChange.new(Kind.RESET, 0, new_count)
