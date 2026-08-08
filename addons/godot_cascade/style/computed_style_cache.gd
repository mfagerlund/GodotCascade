extends RefCounted

## Cross-build computed declaration cache with selector-targeted invalidation.

static var _entries: Dictionary = {}
static var _dependencies: Dictionary = {}
static var _hits := 0
static var _misses := 0
static var _access_order: Dictionary = {}
static var _sequence := 0
const MAX_ENTRIES := 4096


static func has(key: String) -> bool:
	if _entries.has(key):
		_hits += 1
		_touch(key)
		return true
	_misses += 1
	return false


static func retrieve(key: String) -> Dictionary:
	return _entries.get(key, {})


static func put(key: String, computed: Dictionary, dependencies: PackedStringArray) -> void:
	_entries[key] = computed
	_dependencies[key] = dependencies
	_touch(key)
	_evict_overflow()


static func invalidate_type(type_name: String) -> int:
	return _invalidate_dependency("type:%s" % type_name.to_lower())


static func invalidate_class(class_value: String) -> int:
	return _invalidate_dependency("class:%s" % class_value)


static func invalidate_id(element_id: String) -> int:
	return _invalidate_dependency("id:%s" % element_id)


static func clear() -> void:
	_entries.clear()
	_dependencies.clear()
	_access_order.clear()
	_sequence = 0
	_hits = 0
	_misses = 0


static func stats() -> Dictionary:
	return {"entries": _entries.size(), "hits": _hits, "misses": _misses}


static func _invalidate_dependency(dependency: String) -> int:
	var removed := 0
	for key in _dependencies.keys():
		var values: PackedStringArray = _dependencies[key]
		if dependency in values:
			_entries.erase(key)
			_dependencies.erase(key)
			_access_order.erase(key)
			removed += 1
	return removed


static func _touch(key: String) -> void:
	_sequence += 1
	_access_order[key] = _sequence


static func _evict_overflow() -> void:
	if _entries.size() <= MAX_ENTRIES:
		return
	# Batch eviction amortizes the one ordering pass across the next quarter of
	# the cache instead of scanning every entry for every post-capacity put.
	var ordered_keys: Array = _access_order.keys()
	ordered_keys.sort_custom(func(left: Variant, right: Variant): return int(_access_order[left]) < int(_access_order[right]))
	var target_size := maxi(MAX_ENTRIES * 3 / 4, 1)
	var remove_count := mini(_entries.size() - target_size, ordered_keys.size())
	for index in remove_count:
		var key: Variant = ordered_keys[index]
		_entries.erase(key)
		_dependencies.erase(key)
		_access_order.erase(key)
