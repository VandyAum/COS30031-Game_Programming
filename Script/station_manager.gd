extends Node2D
## Stations: creates a Station at every Feature of Interest whose subtype
## matches a crew type (Data/crew_types/*.tres), and holds all the crews.
## Stations outside the current Stage stay under the fog until it expands.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write the Godot 4.7 station manager for the dispatch game: load every
#    CrewType from Data/crew_types, read Map/world/foi.json and create a
#    Station (with its crews) at each FOI whose feature_subtype matches a
#    crew type's station_subtype and which is inside some stage. Keep crews
#    in a child node drawn above the stations, number crews per type
#    ('Police 1', 'Police 2'...), and offer helpers the rest of the game
#    uses: stations in play, all crews, and whether a crew type currently
#    has any station in play (so incidents only spawn if they can be
#    answered)."

const FOI_PATH := "res://Map/world/foi.json"

var crew_types: Array[CrewType] = []
var _crews_node: Node2D


func _ready() -> void:
	add_to_group("station_manager")
	crew_types = load_crew_types()
	_crews_node = Node2D.new()
	_crews_node.name = "Crews"
	_crews_node.z_index = 2
	add_child(_crews_node)

	var counts := {}
	var fois: Array = JSON.parse_string(FileAccess.get_file_as_string(FOI_PATH))
	for f: Dictionary in fois:
		if int(f["s"]) == Stage.OUTSIDE:
			continue
		for t in crew_types:
			if f["subtype"] == t.station_subtype:
				var st := Station.new()
				var n: int = counts.get(t.id, 0)
				st.setup(t, f["name"], Vector2(f["x"], f["y"]), _crews_node, n + 1)
				counts[t.id] = n + t.crews_per_station
				add_child(st)
	print("Stations: %d (%s)" % [get_stations().size(), counts])


## Every CrewType resource in Data/crew_types (works in exported builds too).
static func load_crew_types() -> Array[CrewType]:
	var out: Array[CrewType] = []
	for file in ResourceLoader.list_directory("res://Data/crew_types"):
		if file.ends_with(".tres"):
			out.append(load("res://Data/crew_types/" + file))
	return out


func get_stations() -> Array[Station]:
	var out: Array[Station] = []
	for c in get_children():
		if c is Station:
			out.append(c)
	return out


func stations_in_play() -> Array[Station]:
	return get_stations().filter(func(s: Station) -> bool: return s.is_playable())


func all_crews() -> Array[Crew]:
	var out: Array[Crew] = []
	for s in get_stations():
		out.append_array(s.crews)
	return out


func crews_in_play() -> Array[Crew]:
	return all_crews().filter(func(c: Crew) -> bool: return c.station.is_playable())


func has_type_in_play(type_id: StringName) -> bool:
	for s in stations_in_play():
		if s.type.id == type_id:
			return true
	return false
