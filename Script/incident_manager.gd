extends Node2D
## Incidents: spawns incidents on a fixed schedule from the IncidentType data
## in Data/incident_types/, places them on roads or at Features of Interest
## inside the current Stage, and tracks which one the player has selected.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write the Godot 4.7 incident manager for the dispatch game, replacing
#    incident.gd's random End_Points. Load every IncidentType from
#    Data/incident_types. Spawn on a fixed schedule: a first incident a few
#    seconds in, then one every N seconds (N and the cap on open incidents
#    set per stage in exported arrays). Only pick types whose needed crew
#    type has a station in play, weighted by IncidentType.weight. Place ROAD
#    incidents at a random point on a playable road of an allowed class
#    (named after that road) and FOI incidents at a matching Feature of
#    Interest from Map/world/foi.json (named after the landmark), always
#    inside the current stage and not on top of another incident or a
#    station. Keep track of the selected incident (select() emits
#    Events.incident_selected and moves the highlight), and add a debug key
#    (F5) that spawns one immediately."
# Follow-up prompt (milestone 2): "Pass the road edge of ROAD incidents to
#    the Incident so crashes can block their road, and don't place a new
#    road incident on a road that is already blocked."

const FOI_PATH := "res://Map/world/foi.json"

## Seconds before the first incident.
@export var first_delay := 3.0
## Seconds between incidents, per stage.
@export var interval_by_stage: Array[float] = [25.0, 20.0, 16.0, 12.0]
## Most open (unresolved) incidents at once, per stage.
@export var max_open_by_stage: Array[int] = [2, 3, 4, 6]

var types: Array[IncidentType] = []
var selected: Incident = null
var _timer := 0.0
var _fois: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("incident_manager")
	_rng.randomize()
	_timer = first_delay
	_fois = JSON.parse_string(FileAccess.get_file_as_string(FOI_PATH))
	for file in ResourceLoader.list_directory("res://Data/incident_types"):
		if file.ends_with(".tres"):
			types.append(load("res://Data/incident_types/" + file))
	Events.incident_resolved.connect(func(i: Node) -> void:
		if i == selected:
			select(null))


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval_by_stage[mini(Stage.current, interval_by_stage.size() - 1)]
		if open_incidents().size() < max_open_by_stage[mini(Stage.current, max_open_by_stage.size() - 1)]:
			spawn()


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F5:
		spawn()


func incidents() -> Array[Incident]:
	var out: Array[Incident] = []
	for c in get_children():
		if c is Incident and c.status != Incident.Status.RESOLVED:
			out.append(c)
	return out


func open_incidents() -> Array[Incident]:
	return incidents().filter(func(i: Incident) -> bool: return i.is_open())


func select(incident: Incident) -> void:
	if selected and is_instance_valid(selected):
		selected.selected = false
	selected = incident
	if incident:
		incident.selected = true
	Events.incident_selected.emit(incident)


## Spawn one incident now. Returns null if nothing suitable could be placed.
func spawn() -> Incident:
	var stations := get_tree().get_first_node_in_group("station_manager")
	var candidates := types.filter(func(t: IncidentType) -> bool:
		return stations.has_type_in_play(t.primary_crew_type()))
	for attempt in 6:
		var t := _pick_weighted(candidates)
		if t == null:
			return null
		var spot := _pick_location(t)
		if spot.is_empty():
			continue
		var ct: CrewType = null
		for c in stations.crew_types:
			if c.id == t.primary_crew_type():
				ct = c
		var inc := Incident.new()
		inc.setup(t, ct, spot["pos"], spot["place"], spot.get("edge", -1))
		inc.name = "%s_%d" % [t.id, Time.get_ticks_msec()]
		add_child(inc)
		Events.incident_spawned.emit(inc)
		return inc
	return null


func _pick_weighted(list: Array) -> IncidentType:
	var total := 0.0
	for t: IncidentType in list:
		total += t.weight
	var roll := _rng.randf() * total
	for t: IncidentType in list:
		roll -= t.weight
		if roll <= 0.0:
			return t
	return null


# Returns {pos, place} or {} if no free spot was found.
func _pick_location(t: IncidentType) -> Dictionary:
	if t.where == IncidentType.Where.FOI:
		var matches := _fois.filter(func(f: Dictionary) -> bool:
			return (t.foi_types.has(f["type"]) or t.foi_types.has(f["subtype"])) \
				and Stage.is_playable(Vector2(f["x"], f["y"])))
		matches.shuffle()
		for f: Dictionary in matches:
			var p := Vector2(f["x"], f["y"])
			if _is_free(p):
				return {"pos": p, "place": f["name"]}
		return {}

	var edges: Array[int] = []
	for e in RoadGraph.edge_count():
		if RoadGraph.is_playable(e) and t.road_classes.has(RoadGraph.edge_class(e)) and RoadGraph.edge_length(e) > 30.0 \
				and not World.is_blocked(e):
			edges.append(e)
	for attempt in 20:
		if edges.is_empty():
			return {}
		var e: int = edges[_rng.randi() % edges.size()]
		var p := RoadGraph.point_at(e, _rng.randf_range(0.2, 0.8) * RoadGraph.edge_length(e))
		if _is_free(p):
			var road: String = RoadGraph.edge_name[e]
			return {"pos": p, "edge": e, "place": road if road != "" and road != "Unnamed" else "an unnamed road"}
	return {}


func _is_free(p: Vector2) -> bool:
	for i in incidents():
		if i.position.distance_to(p) < 120.0:
			return false
	for s in get_tree().get_nodes_in_group("stations"):
		if s.position.distance_to(p) < 80.0:
			return false
	return true
