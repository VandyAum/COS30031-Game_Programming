extends Node
## World (autoload): WHAT IS TRUE. The real traffic and blockages on every
## road. Crews experience this; the player never reads it directly. The map
## overlay must draw from Knowledge, not from here.
##
## The truth keeps changing: traffic drifts on every road, and roads get
## blocked (roadworks, fallen trees, crashes) for a while. The player only
## finds out when a crew sees it - or runs into it.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'World' holding the ground-truth live
#    conditions for every road edge in the RoadGraph autoload. Each edge has a
#    traffic level (CLEAR, SLOW, JAMMED, BLOCKED). Seed a believable starting
#    state where main roads are more likely to be slow or jammed than side
#    streets, using a seeded RandomNumberGenerator so runs can be reproduced.
#    Provide get/set functions, emit Events.road_truth_changed when a road
#    changes, and give each level a travel speed multiplier crews can use.
#    Random changes over time are a later task, so just leave a clear hook."
# Follow-up prompt: "Road classes are now 0 local, 1 collector, 2 arterial,
#    3 freeway (Vicmap). Freeways and arterials should jam most often."
# Follow-up prompt (milestone 2 - the truth changes):
#   "Make the true world change over time, using the game clock
#    (Knowledge.clock, which stops while paused): (1) traffic drifts - each
#    playable road re-rolls its traffic on average every
#    traffic_change_seconds; (2) random blockages appear on playable roads on
#    a per-stage schedule and cap (roadworks, fallen tree, burst water main,
#    broken-down truck...) and clear after a random duration; (3) other
#    systems can block a road with an owner (e.g. a car crash incident
#    blocks its own road until resolved) and unblock it later. Remember the
#    reason and owner of each blockage so crews can tell whether a blockage
#    is their own incident and the UI can say what it is. Never block roads
#    right next to a station. Emit road_truth_changed for every change."

enum Traffic { CLEAR, SLOW, JAMMED, BLOCKED }

## How fast a crew moves on a road at each traffic level (1.0 = full speed).
const SPEED_MULT := {
	Traffic.CLEAR: 1.0,
	Traffic.SLOW: 0.6,
	Traffic.JAMMED: 0.3,
	Traffic.BLOCKED: 0.0,
}
const BLOCK_REASONS := ["Roadworks", "Fallen tree", "Burst water main", "Broken-down truck", "Flooded underpass"]

@export var seed_value := 0   # 0 = random each run
## Average seconds between traffic changes on any one road.
@export var traffic_change_seconds := 75.0
## Seconds between random blockages, per stage.
@export var blockage_interval_by_stage: Array[float] = [35.0, 30.0, 25.0, 20.0]
## Most random blockages at once, per stage.
@export var max_blockages_by_stage: Array[int] = [1, 2, 4, 6]
## Random blockages last between x and y seconds.
@export var blockage_duration := Vector2(50.0, 110.0)

var rng := RandomNumberGenerator.new()
var _traffic := PackedByteArray()
var _blocks := {}             # edge -> {reason, owner, until}
var _playable: Array[int] = []
var _change_budget := 0.0
var _block_timer := 0.0
var _last_clock := 0.0


func _ready() -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_traffic.resize(RoadGraph.edge_count())
	for e in RoadGraph.edge_count():
		_traffic[e] = _roll_traffic(e)
	_refresh_playable()
	_block_timer = blockage_interval_by_stage[0] * 0.5
	Events.stage_changed.connect(func(_s: int) -> void: _refresh_playable())


func _process(_delta: float) -> void:
	var dt := Knowledge.clock - _last_clock      # game time only
	_last_clock = Knowledge.clock
	if dt <= 0.0:
		return

	# Traffic drift: on average every road changes once per traffic_change_seconds.
	_change_budget += _playable.size() * dt / traffic_change_seconds
	while _change_budget >= 1.0:
		_change_budget -= 1.0
		var e: int = _playable[rng.randi() % _playable.size()]
		if not _blocks.has(e):
			set_traffic(e, _roll_traffic(e))

	# Random blockages appear and expire.
	_block_timer -= dt
	if _block_timer <= 0.0:
		var s := mini(Stage.current, blockage_interval_by_stage.size() - 1)
		_block_timer = blockage_interval_by_stage[s] * rng.randf_range(0.7, 1.3)
		if _random_block_count() < max_blockages_by_stage[s]:
			_add_random_block()
	for e in _blocks.keys():
		var b: Dictionary = _blocks[e]
		if b["until"] >= 0.0 and Knowledge.clock >= b["until"]:
			unblock(e)


func get_traffic(edge: int) -> int:
	return _traffic[edge]


func set_traffic(edge: int, level: int) -> void:
	if _traffic[edge] == level:
		return
	_traffic[edge] = level
	Events.road_truth_changed.emit(edge)


func is_blocked(edge: int) -> bool:
	return _traffic[edge] == Traffic.BLOCKED


func speed_multiplier(edge: int) -> float:
	return SPEED_MULT[_traffic[edge]]


## Block a road. owner (e.g. an Incident) may drive onto it; duration < 0
## means until unblock() is called.
func block(edge: int, reason: String, owner: Object = null, duration := -1.0) -> void:
	_blocks[edge] = {"reason": reason, "owner": owner,
		"until": Knowledge.clock + duration if duration >= 0.0 else -1.0}
	set_traffic(edge, Traffic.BLOCKED)


func unblock(edge: int) -> void:
	if _blocks.erase(edge):
		_traffic[edge] = Traffic.BLOCKED   # force a change event below
		set_traffic(edge, _roll_traffic(edge))


func block_reason(edge: int) -> String:
	return _blocks[edge]["reason"] if _blocks.has(edge) else ""


func blocked_by(edge: int) -> Object:
	return _blocks[edge]["owner"] if _blocks.has(edge) else null


func _refresh_playable() -> void:
	_playable.clear()
	for e in RoadGraph.edge_count():
		if RoadGraph.is_playable(e):
			_playable.append(e)


func _random_block_count() -> int:
	var n := 0
	for e in _blocks:
		if _blocks[e]["owner"] == null:
			n += 1
	return n


func _add_random_block() -> void:
	var stations := get_tree().get_nodes_in_group("stations")
	for attempt in 20:
		var e: int = _playable[rng.randi() % _playable.size()]
		if _blocks.has(e) or RoadGraph.edge_class(e) > 2 or RoadGraph.edge_length(e) < 40.0:
			continue
		var mid := RoadGraph.edge_midpoint(e)
		if stations.any(func(s: Node2D) -> bool: return s.global_position.distance_to(mid) < 120.0):
			continue
		block(e, BLOCK_REASONS[rng.randi() % BLOCK_REASONS.size()], null,
			rng.randf_range(blockage_duration.x, blockage_duration.y))
		return


# Traffic roll. Big roads jam more often than side streets. Never BLOCKED.
func _roll_traffic(edge: int) -> int:
	var roll := rng.randf()
	match RoadGraph.edge_class(edge):
		2, 3:
			return Traffic.JAMMED if roll < 0.15 else (Traffic.SLOW if roll < 0.45 else Traffic.CLEAR)
		1:
			return Traffic.JAMMED if roll < 0.05 else (Traffic.SLOW if roll < 0.25 else Traffic.CLEAR)
		_:
			return Traffic.SLOW if roll < 0.08 else Traffic.CLEAR
