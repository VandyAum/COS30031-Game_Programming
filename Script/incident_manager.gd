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
# Follow-up prompt (milestone 3): "Respect IncidentType.min_stage, only
#    spawn types whose every needed crew type has a station in play, pass
#    all needed CrewTypes to the incident (multi-crew crashes), and keep the
#    tutorial to a single call at a time. Stop spawning once the run is over."
# Follow-up prompt (pacing): "It was impossible to win: five medical calls
#    could pile up with one ambulance in play. Pace incidents so the player
#    isn't consistently overwhelmed at one failure point: never spawn an
#    incident needing a crew type whose open incidents already match the
#    number of crews of that type in play (plus a per-stage allowance), and
#    weight the choice toward crew types with the most spare capacity and
#    away from repeating the last type. Vary the interval by +-20%."

const FOI_PATH := "res://Map/world/foi.json"

## Seconds before the first incident.
@export var first_delay := 3.0
## Seconds between incidents, per stage.
@export var interval_by_stage: Array[float] = [25.0, 20.0, 16.0, 12.0]
## Most open (unresolved) incidents at once, per stage.
@export var max_open_by_stage: Array[int] = [1, 3, 4, 6]
## Extra open incidents allowed per crew type beyond its crews in play.
@export var overload_by_stage: Array[int] = [0, 0, 0, 1]

var types: Array[IncidentType] = []
var selected: Incident = null
var _timer := 0.0
var _fois: Array = []
var _rng := RandomNumberGenerator.new()
var _last_type: StringName = &""


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
	if Run.over:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = interval_by_stage[mini(Stage.current, interval_by_stage.size() - 1)] * _rng.randf_range(0.8, 1.2)
		if open_incidents().size() < max_open_by_stage[mini(Stage.current, max_open_by_stage.size() - 1)]:
			spawn()


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F5:
		spawn()


func incidents() -> Array[Incident]:
	var out: Array[Incident] = []
	for c in get_children():
		if c is Incident and not c.is_finished():
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
	var demand := crew_load()
	var allowance: int = overload_by_stage[mini(Stage.current, overload_by_stage.size() - 1)]
	var candidates := types.filter(func(t: IncidentType) -> bool:
		return t.min_stage <= Stage.current and t.crew_types.all(func(id: StringName) -> bool:
			return demand.has(id) and demand[id]["open"] < demand[id]["crews"] + allowance))
	for attempt in 6:
		var t := _pick_weighted(candidates, demand)
		if t == null:
			return null
		var spot := _pick_location(t)
		if spot.is_empty():
			continue
		var needed: Array[CrewType] = []
		for id in t.crew_types:
			for c: CrewType in stations.crew_types:
				if c.id == id:
					needed.append(c)
		var inc := Incident.new()
		inc.setup(t, needed, spot["pos"], spot["place"], spot.get("edge", -1))
		inc.name = "%s_%d" % [t.id, Time.get_ticks_msec()]
		add_child(inc)
		_last_type = t.id
		Events.incident_spawned.emit(inc)
		return inc
	return null


## Per crew type in play: {"crews": crews in play, "open": unfinished incidents needing it}.
func crew_load() -> Dictionary:
	var out := {}
	for c: Crew in get_tree().get_first_node_in_group("station_manager").crews_in_play():
		if not out.has(c.type.id):
			out[c.type.id] = {"crews": 0, "open": 0}
		out[c.type.id]["crews"] += 1
	for i in incidents():
		for t in i.needed_types:
			if out.has(t.id):
				out[t.id]["open"] += 1
	return out


# Weighted pick, favouring crew types with spare capacity and not repeating
# the last incident type.
func _pick_weighted(list: Array, demand: Dictionary) -> IncidentType:
	var weights: Array[float] = []
	var total := 0.0
	for t: IncidentType in list:
		var w := t.weight
		for id in t.crew_types:
			var l: Dictionary = demand[id]
			w *= 1.0 - 0.6 * clampf(float(l["open"]) / l["crews"], 0.0, 1.0)
		if t.id == _last_type:
			w *= 0.4
		weights.append(w)
		total += w
	var roll := _rng.randf() * total
	for k in list.size():
		roll -= weights[k]
		if roll <= 0.0:
			return list[k]
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
	if World.random_block_near(p, World.incident_clearance_m * float(Stage.meta["px_per_m"])):
		return false
	for i in incidents():
		if i.position.distance_to(p) < 120.0:
			return false
	for s in get_tree().get_nodes_in_group("stations"):
		if s.position.distance_to(p) < 80.0:
			return false
	return true
