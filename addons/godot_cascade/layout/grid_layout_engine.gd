extends RefCounted

## Scene-tree-free grid track sizing and placement.


static func arrange(
	container_size: Vector2,
	column_tracks: Array[Dictionary],
	row_tracks: Array[Dictionary],
	items: Array[Dictionary],
	column_gap: float,
	row_gap: float
) -> Dictionary:
	var placements := _place_items(items, maxi(column_tracks.size(), 1))
	var required_rows := 1
	for placement in placements:
		required_rows = maxi(required_rows, int(placement["row"]) + int(placement["row_span"]))
	var columns := column_tracks.duplicate(true)
	if columns.is_empty():
		columns.append({"kind": "fraction", "value": 1.0})
	var rows := row_tracks.duplicate(true)
	while rows.size() < required_rows:
		rows.append({"kind": "content"})

	var column_sizes := _resolve_tracks(container_size.x, columns, placements, items, true, column_gap)
	var row_sizes := _resolve_tracks(container_size.y, rows, placements, items, false, row_gap)
	var column_offsets := _offsets(column_sizes, column_gap)
	var row_offsets := _offsets(row_sizes, row_gap)
	var rects: Array[Rect2] = []
	for index in items.size():
		var placement: Dictionary = placements[index]
		var column := int(placement["column"])
		var row := int(placement["row"])
		var column_span := mini(int(placement["column_span"]), column_sizes.size() - column)
		var row_span := mini(int(placement["row_span"]), row_sizes.size() - row)
		rects.append(Rect2(
			Vector2(column_offsets[column], row_offsets[row]),
			Vector2(_span_size(column_sizes, column, column_span, column_gap), _span_size(row_sizes, row, row_span, row_gap))
		))
	return {"rects": rects, "column_sizes": column_sizes, "row_sizes": row_sizes, "placements": placements}


static func _place_items(items: Array[Dictionary], column_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items:
		result.append({})
	var occupied := {}
	for index in items.size():
		var item: Dictionary = items[index]
		var explicit_column := int(item.get("column", -1))
		var explicit_row := int(item.get("row", -1))
		if explicit_column < 0 or explicit_row < 0:
			continue
		var explicit_column_span := mini(maxi(int(item.get("column_span", 1)), 1), column_count)
		explicit_column = clampi(explicit_column, 0, column_count - 1)
		explicit_column_span = mini(explicit_column_span, column_count - explicit_column)
		var explicit_row_span := maxi(int(item.get("row_span", 1)), 1)
		result[index] = _placement(explicit_column, explicit_row, explicit_column_span, explicit_row_span)
		_reserve(explicit_column, explicit_row, explicit_column_span, explicit_row_span, column_count, occupied)

	var auto_cursor := 0
	for index in items.size():
		if not result[index].is_empty():
			continue
		var item: Dictionary = items[index]
		var column := int(item.get("column", -1))
		var row := int(item.get("row", -1))
		var column_span := mini(maxi(int(item.get("column_span", 1)), 1), column_count)
		var row_span := maxi(int(item.get("row_span", 1)), 1)
		if column >= 0:
			column = clampi(column, 0, column_count - 1)
			column_span = mini(column_span, column_count - column)
			row = 0
			while not _fits_at(column, row, column_span, row_span, column_count, occupied):
				row += 1
		elif row >= 0:
			row = maxi(row, 0)
			column = 0
			while column < column_count and not _fits_at(column, row, column_span, row_span, column_count, occupied):
				column += 1
			if column >= column_count:
				row += 1
				column = 0
				while not _fits_at(column, row, column_span, row_span, column_count, occupied):
					row += 1
		else:
			while not _placement_fits(auto_cursor, column_count, column_span, row_span, occupied):
				auto_cursor += 1
			column = auto_cursor % column_count
			row = auto_cursor / column_count as int
			auto_cursor += column_span
		result[index] = _placement(column, row, column_span, row_span)
		_reserve(column, row, column_span, row_span, column_count, occupied)
	return result


static func _placement_fits(cursor: int, column_count: int, column_span: int, row_span: int, occupied: Dictionary) -> bool:
	var column := cursor % column_count
	var row := cursor / column_count as int
	return _fits_at(column, row, column_span, row_span, column_count, occupied)


static func _fits_at(column: int, row: int, column_span: int, row_span: int, column_count: int, occupied: Dictionary) -> bool:
	if column + column_span > column_count:
		return false
	for placed_row in range(row, row + row_span):
		for placed_column in range(column, column + column_span):
			if occupied.has(placed_row * column_count + placed_column):
				return false
	return true


static func _placement(column: int, row: int, column_span: int, row_span: int) -> Dictionary:
	return {"column": column, "row": row, "column_span": column_span, "row_span": row_span}


static func _reserve(column: int, row: int, column_span: int, row_span: int, column_count: int, occupied: Dictionary) -> void:
	for placed_row in range(row, row + row_span):
		for placed_column in range(column, mini(column + column_span, column_count)):
			occupied[placed_row * column_count + placed_column] = true


static func _resolve_tracks(
	available: float,
	tracks: Array[Dictionary],
	placements: Array[Dictionary],
	items: Array[Dictionary],
	horizontal: bool,
	gap: float
) -> PackedFloat32Array:
	var sizes := PackedFloat32Array()
	var fraction_weight := 0.0
	for track in tracks:
		var kind := str(track.get("kind", "content"))
		var base := float(track.get("value", 0.0)) if kind == "fixed" else float(track.get("min", 0.0))
		sizes.append(maxf(base, 0.0))
		if kind == "fraction" or (kind == "minmax" and float(track.get("fraction", 0.0)) > 0.0):
			fraction_weight += float(track.get("value", track.get("fraction", 1.0)))
	for index in items.size():
		var placement: Dictionary = placements[index]
		var track_index := int(placement["column" if horizontal else "row"])
		var span := int(placement["column_span" if horizontal else "row_span"])
		if span != 1 or track_index < 0 or track_index >= tracks.size():
			continue
		if str(tracks[track_index].get("kind", "content")) in ["content", "minmax"]:
			var minimum: Vector2 = items[index].get("minimum", Vector2.ZERO)
			sizes[track_index] = maxf(sizes[track_index], minimum.x if horizontal else minimum.y)
	var remaining := maxf(available - gap * maxf(tracks.size() - 1, 0) - _sum(sizes), 0.0)
	remaining = _grow_bounded_tracks(tracks, sizes, remaining)
	if fraction_weight > 0.0:
		for index in tracks.size():
			var track: Dictionary = tracks[index]
			var weight := float(track.get("value", 0.0)) if track.get("kind") == "fraction" else float(track.get("fraction", 0.0))
			if weight > 0.0:
				sizes[index] += remaining * weight / fraction_weight
				if track.has("max"):
					sizes[index] = minf(sizes[index], float(track["max"]))
	return sizes


static func _grow_bounded_tracks(tracks: Array[Dictionary], sizes: PackedFloat32Array, remaining: float) -> float:
	var active: Array[int] = []
	for index in tracks.size():
		if str(tracks[index].get("kind", "")) == "minmax" and tracks[index].has("max") and sizes[index] < float(tracks[index]["max"]):
			active.append(index)
	while remaining > 0.001 and not active.is_empty():
		var share := remaining / active.size()
		var consumed := 0.0
		var next_active: Array[int] = []
		for index in active:
			var capacity := float(tracks[index]["max"]) - sizes[index]
			var growth := minf(share, capacity)
			sizes[index] += growth
			consumed += growth
			if capacity - growth > 0.001:
				next_active.append(index)
		remaining -= consumed
		if consumed <= 0.001:
			break
		active = next_active
	return remaining


static func _offsets(sizes: PackedFloat32Array, gap: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var cursor := 0.0
	for size in sizes:
		result.append(cursor)
		cursor += size + gap
	return result


static func _span_size(sizes: PackedFloat32Array, start: int, span: int, gap: float) -> float:
	var result := gap * maxf(span - 1, 0)
	for index in range(start, start + span):
		result += sizes[index]
	return result


static func _sum(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result += value
	return result
