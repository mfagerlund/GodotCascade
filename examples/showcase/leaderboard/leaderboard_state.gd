class_name ShowcaseLeaderboardState
extends RefCounted


class Entry extends RefCounted:
	var id: String
	var rank: int
	var pilot: String
	var division: String
	var wins: int
	var rating: int


	func _init(entry_id: String, entry_rank: int, entry_pilot: String, entry_division: String, entry_wins: int, entry_rating: int) -> void:
		id = entry_id
		rank = entry_rank
		pilot = entry_pilot
		division = entry_division
		wins = entry_wins
		rating = entry_rating


var status := "Season 12 · five ranked pilots"
var entries: Array[Entry] = [
	Entry.new("rhea", 1, "Rhea Sol", "Orion", 18, 2480),
	Entry.new("milo", 2, "Milo Vance", "Aurora", 16, 2395),
	Entry.new("sana", 3, "Sana Keene", "Orion", 15, 2310),
	Entry.new("tomas", 4, "Tomas Reed", "Vanguard", 13, 2190),
	Entry.new("imani", 5, "Imani Vale", "Aurora", 12, 2115),
]

var next_pilot := 0

const NEW_PILOTS := [
	["nia", "Nia Ward", "Vanguard", 11, 2075],
	["oren", "Oren Pike", "Orion", 10, 2010],
	["luz", "Luz Hale", "Aurora", 9, 1960],
]


func add_pilot() -> Entry:
	var template: Array = NEW_PILOTS[next_pilot % NEW_PILOTS.size()]
	var cycle := next_pilot / NEW_PILOTS.size()
	next_pilot += 1
	var suffix := "" if cycle == 0 else " %s" % (cycle + 1)
	var entry := Entry.new(
		"%s-%s" % [template[0], next_pilot],
		entries.size() + 1,
		str(template[1]) + suffix,
		str(template[2]),
		int(template[3]),
		int(template[4])
	)
	entries.append(entry)
	return entry


func remove_pilot(entry_id: String) -> String:
	for index in entries.size():
		if entries[index].id != entry_id:
			continue
		var pilot := entries[index].pilot
		entries.remove_at(index)
		rerank()
		return pilot
	return ""


func sort_by_rating() -> void:
	entries.sort_custom(func(a: Entry, b: Entry) -> bool: return a.rating > b.rating)
	rerank()


func move_before(source_id: String, target_id: String) -> bool:
	if source_id == target_id:
		return false
	var source_index := _entry_index(source_id)
	var target_index := _entry_index(target_id)
	if source_index < 0 or target_index < 0:
		return false
	var entry := entries[source_index]
	entries.remove_at(source_index)
	if source_index < target_index:
		target_index -= 1
	entries.insert(target_index, entry)
	rerank()
	return true


func rerank() -> void:
	for index in entries.size():
		entries[index].rank = index + 1


func _entry_index(entry_id: String) -> int:
	for index in entries.size():
		if entries[index].id == entry_id:
			return index
	return -1
