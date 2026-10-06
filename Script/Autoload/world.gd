extends Node
## World (autoload): WHAT IS TRUE. The real traffic and blockages on every
## road. Crews experience this; the player never reads it directly. The map
## overlay must draw from Knowledge, not from here.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'World' holding the ground-truth live
#    conditions for every road edge in the RoadGraph autoload. Each edge has a
#    traffic level (CLEAR, SLOW, JAMMED, BLOCKED). Seed a believable starting
#    state where main roads are more likely to be slow or jammed than side
#    streets, using a seeded RandomNumberGenerator so runs can be reproduced.
#    Provide get/set functions, emit Events.road_truth_changed when a road
#    changes, and give each level a travel speed multiplier crews can use.
#    Random changes over time are a later task, so just leave a clear hook."

enum Traffic { CLEAR, SLOW, JAMMED, BLOCKED }

## How fast a crew moves on a road at each traffic level (1.0 = full speed).
const SPEED_MULT := {
	Traffic.CLEAR: 1.0,
	Traffic.SLOW: 0.6,
	Traffic.JAMMED: 0.3,
	Traffic.BLOCKED: 0.0,
}

@export var seed_value := 0   # 0 = random each run

var rng := RandomNumberGenerator.new()
var _traffic := PackedByteArray()


func _ready() -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_traffic.resize(RoadGraph.edge_count())
	for e in RoadGraph.edge_count():
		_traffic[e] = _roll_traffic(e)


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


# Starting traffic. Main roads (class 2) jam more often than side streets.
# Blockages are left for the "roads can become blocked" task.
func _roll_traffic(edge: int) -> int:
	var roll := rng.randf()
	match RoadGraph.edge_class(edge):
		2:
			return Traffic.JAMMED if roll < 0.15 else (Traffic.SLOW if roll < 0.45 else Traffic.CLEAR)
		1:
			return Traffic.JAMMED if roll < 0.05 else (Traffic.SLOW if roll < 0.25 else Traffic.CLEAR)
		_:
			return Traffic.SLOW if roll < 0.08 else Traffic.CLEAR
