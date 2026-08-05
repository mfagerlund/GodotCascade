extends RefCounted

## Cross-build computed declaration cache with selector-targeted invalidation.

static var _entries: Dictionary = {}
static var _dependencies: Dictionary = {}
static var _hits := 0
static var _misses := 0


static func has(key: String) -> bool:
	if _entries.has(key):
		_hits += 1
		return true
	_misses += 1
	return false


static func retrieve(key: String) -> Dictionary:
	return _entries.get(key, {})


static func put(key: String, computed: Dictionary, dependencies: PackedStringArray) -> void:
	_entries[key] = computed
	_dependencies[key] = dependencies


static func invalidate_type(type_name: String) -> int:
	return _invalidate_dependency("type:%s" % type_name.to_lower())


static func invalidate_class(class_value: String) -> int:
	return _invalidate_dependency("class:%s" % class_value)


static func invalidate_id(element_id: String) -> int:
	return _invalidate_dependency("id:%s" % element_id)


static func clear() -> void:
	_entries.clear()
	_dependencies.clear()
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
			removed += 1
	return removed
