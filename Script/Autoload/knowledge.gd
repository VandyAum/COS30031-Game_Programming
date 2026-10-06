extends Node
## Knowledge (autoload): WHAT THE PLAYER KNOWS. For every road, the last
## traffic level someone reported and when. Everything the player sees on the
## map should be drawn from here, never from World.
##
## Roads never observed are UNKNOWN (fog). Observed roads are fresh, then
## fade toward grey over FADE_SECONDS but keep their last-known level.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'Knowledge' that stores the player's view of
#    every road edge, separate from the World autoload's truth. Per edge keep
#    the last observed traffic level and the game time it was observed (or
#    'never'). observe(edge) copies the current truth from World, stamps the
#    time and emits Events.road_observed. Add freshness(edge) returning 1.0 when
#    just seen down to 0.0 when fully stale after a tunable FADE_SECONDS, and
#    is_known(edge). Use a game clock that only advances while the tree is not
#    paused, so pausing doesn't age information. Add a debug key (F3) that
#    observes every road at once so the overlay can be checked."

const UNKNOWN := -1

## Seconds for a fresh observation to fade fully to grey. Tune in playtest.
@export var fade_seconds := 60.0

var clock := 0.0                     # game seconds, stops while paused
var _level := PackedInt32Array()     # last seen traffic level or UNKNOWN
var _seen_at := PackedFloat32Array() # clock time of last observation


func _ready() -> void:
	_level.resize(RoadGraph.edge_count())
	_level.fill(UNKNOWN)
	_seen_at.resize(RoadGraph.edge_count())


func _process(delta: float) -> void:
	clock += delta


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F3:
		observe_all()


## Record what is really on this road right now.
func observe(edge: int) -> void:
	_level[edge] = World.get_traffic(edge)
	_seen_at[edge] = clock
	Events.road_observed.emit(edge)


func observe_all() -> void:
	for e in _level.size():
		observe(e)


func is_known(edge: int) -> bool:
	return _level[edge] != UNKNOWN


## Last-known traffic level (World.Traffic) or UNKNOWN.
func known_level(edge: int) -> int:
	return _level[edge]


## 1.0 = just observed, 0.0 = fully stale (or unknown).
func freshness(edge: int) -> float:
	if _level[edge] == UNKNOWN:
		return 0.0
	return clampf(1.0 - (clock - _seen_at[edge]) / fade_seconds, 0.0, 1.0)


## Seconds since this road was observed (INF if never).
func age(edge: int) -> float:
	return INF if _level[edge] == UNKNOWN else clock - _seen_at[edge]
