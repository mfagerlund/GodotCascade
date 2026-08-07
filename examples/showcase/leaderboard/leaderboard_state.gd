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
