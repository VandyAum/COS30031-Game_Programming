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
#
# Follow-up prompt (crew sightings + colour reveal):
#   "Crews should see everything within a sighting radius, not just the road
#    they drive (the spec's 'crew sightings' Intel source, upgradable later).
#    Add sight(world_pos) that observes every playable road within
#    sight_radius_m and also stamps that circle into a low-resolution 'sight
#    map' image (one float per 16 world px holding the time it was last seen,
#    with a soft edge). WorldMap uses that texture to show the map in colour
#    near what crews have seen and fade it back to monochrome as the
#    information ages, using the same fade_seconds as the roads. Only emit
#    Events.road_observed when a road is first seen or its known state
#    changes, so repeated sightings don't flood the event log. Upload the
#    sight texture at most ten times a second."
# Follow-up prompt: "Sightings revealed whole side streets as soon as any
#    part was in range, so long streets lit up far outside the coloured
#    circle. Only observe a road if its midpoint is within 1.5x the sight
#    radius (or it is short enough to be seen in full)."
# Follow-up prompt (one vision radius for traffic and map):
#   "Traffic vision is bigger than the map-colour vision and clips off
#    instead of fading. Make the sight map two channels: R = time last seen
#    (for fading), G = soft 'has been seen' coverage (0..1, permanent).
#    The traffic overlay will be masked and faded per pixel from this same
#    texture, so observe every road with any part inside the sight radius
#    and let the shader decide what is visible."
# Follow-up prompt: "Add reset() for 'play again' (autoloads survive a scene
#    reload)."
# Follow-up prompt: "Make traffic vision last twice as long: 60 s is too
#    short. fade_seconds 120."

const UNKNOWN := -1

## Seconds for a fresh observation to fade fully to grey. Tune in playtest.
@export var fade_seconds := 120.0

## How far a crew can see, in metres. Upgradable later.
@export var sight_radius_m := 110.0

const SIGHT_CELL := 16.0             # world px per sight-map pixel
const NEVER_SEEN := -10000.0

var clock := 0.0                     # game seconds, stops while paused
var _level := PackedInt32Array()     # last seen traffic level or UNKNOWN
var _seen_at := PackedFloat32Array() # clock time of last observation

## Sight map (FORMAT_RGF): R = clock time each area was last seen,
## G = soft coverage 0..1 (has this spot ever been seen).
var sight_image: Image
var sight_texture: ImageTexture
var _sight_dirty := false
var _sight_upload_timer := 0.0


func _ready() -> void:
	_level.resize(RoadGraph.edge_count())
	_level.fill(UNKNOWN)
	_seen_at.resize(RoadGraph.edge_count())
	var size := (Stage.world_size / SIGHT_CELL).ceil()
	sight_image = Image.create_empty(int(size.x), int(size.y), false, Image.FORMAT_RGF)
	sight_image.fill(Color(NEVER_SEEN, 0, 0))
	sight_texture = ImageTexture.create_from_image(sight_image)


## Forget everything (new run).
func reset() -> void:
	clock = 0.0
	_level.fill(UNKNOWN)
	_seen_at.fill(0.0)
	sight_image.fill(Color(NEVER_SEEN, 0, 0))
	sight_texture.update(sight_image)


func _process(delta: float) -> void:
	clock += delta
	_sight_upload_timer -= delta
	if _sight_dirty and _sight_upload_timer <= 0.0:
		sight_texture.update(sight_image)
		_sight_dirty = false
		_sight_upload_timer = 0.1


## A crew (or later: scout, camera) looks around this point.
func sight(world_pos: Vector2, radius_m := -1.0) -> void:
	var r := (sight_radius_m if radius_m < 0.0 else radius_m) * float(Stage.meta["px_per_m"])
	for e in RoadGraph.edges_near(world_pos, r):
		observe(e)
	_stamp(world_pos, r)


# Write "seen now" into the sight map, soft at the edge of the circle.
func _stamp(world_pos: Vector2, r: float) -> void:
	var c := world_pos / SIGHT_CELL
	var rc := r / SIGHT_CELL
	var w := sight_image.get_width()
	var h := sight_image.get_height()
	for y in range(maxi(0, floori(c.y - rc)), mini(h, ceili(c.y + rc) + 1)):
		for x in range(maxi(0, floori(c.x - rc)), mini(w, ceili(c.x + rc) + 1)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / rc
			if d > 1.0:
				continue
			# Centre = seen now; edge = as if seen fade_seconds ago.
			var old := sight_image.get_pixel(x, y)
			var seen := maxf(old.r, clock - fade_seconds * smoothstep(0.55, 1.0, d))
			var cover := maxf(old.g, 1.0 - smoothstep(0.6, 1.0, d))
			if seen != old.r or cover != old.g:
				sight_image.set_pixel(x, y, Color(seen, cover, 0))
	_sight_dirty = true


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F3:
		observe_all()


## Record what is really on this road right now.
func observe(edge: int) -> void:
	var level := World.get_traffic(edge)
	var changed := level != _level[edge]
	_level[edge] = level
	_seen_at[edge] = clock
	if changed:
		Events.road_observed.emit(edge)


func observe_all() -> void:
	for e in _level.size():
		observe(e)
	sight_image.fill(Color(clock, 1, 0))
	_sight_dirty = true


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
