class_name CascadeItemModel
extends RefCounted

## Typed collection interface consumed by retained and virtualized Repeat controls.
## Implementations publish explicit changes; consumers never need to poll per frame.

signal changed(change: CascadeCollectionChange)


func item_count() -> int:
	return 0


func item_at(_index: int) -> Variant:
	return null


func key_at(index: int) -> Variant:
	return index
