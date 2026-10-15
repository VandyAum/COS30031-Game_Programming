extends Node
## Stage (autoload): which part of the map is currently in play.
##
## Each stage is a plain rectangle (from Map/world/world_meta.json, built by
## tools/build_world.py). Stage 0 is a small tutorial area around the
## junction, stage 1 is halfway between 0 and 2, stage 2 covers three suburbs
## and stage 3 is exactly double stage 2. Anything outside the current
## stage's rectangle is under fog and can't be used.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'Stage' for our single-world dispatch map. It
#    loads Map/world/world_meta.json (stage names, per-stage pixel bounds,
#    projection constants) and Map/world/stage_mask.bin (one byte per 8 world
#    px, value = first stage that area is playable in, 255 = outside the
#    council). Provide: current stage, set_stage(n) that emits
#    Events.stage_changed, stage_at(world_pos), is_playable(world_pos),
#    bounds(stage) as a Rect2 for camera limits, and geo_to_world(lon, lat)
#    using the same projection as the build script so FOI data and any other
#    lon/lat data line up. Add a debug key (F4) to step through the stages so
#    the expansion can be tested without playing for 20 minutes."
#
# Follow-up prompt: "Stages are now axis-aligned rectangles ('stage_rects' in
#    world_meta.json) instead of a raster mask. Drop the mask entirely; the
#    first rectangle containing a point is its stage. Also expose the map
#    credit line from world_meta.json for the on-screen attribution."
# Follow-up prompt (animated stage changes): "Moving to the next stage
#    should be animated, not snap. Keep a 'shown' rectangle that the fog
#    draws around: on set_stage, tween it smoothly (ease in-out over
#    transition_seconds) from the old stage rectangle to the new one, and
#    emit Events.stage_changed straight away so the camera can glide out
#    at the same pace. Gameplay (is_playable) switches immediately."

const META_PATH := "res://Map/world/world_meta.json"
const OUTSIDE := 255

var current := 0
var meta: Dictionary
var world_size := Vector2.ZERO
var rects: Array[Rect2] = []
## The rectangle the fog currently leaves clear (animates between stages).
var shown := Rect2()
## Seconds the fog and camera take to open up to a new stage.
@export var transition_seconds := 2.5

var _tween: Tween


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	world_size = Vector2(meta["size"][0], meta["size"][1])
	for r: Array in meta["stage_rects"]:
		rects.append(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]))
	shown = rects[0]


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F4:
		set_stage((current + 1) % stage_count())


func stage_count() -> int:
	return rects.size()


func stage_name(stage := -1) -> String:
	return meta["stage_names"][current if stage < 0 else stage]


func set_stage(stage: int, animate := true) -> void:
	current = clampi(stage, 0, stage_count() - 1)
	if _tween:
		_tween.kill()
	if animate:
		_tween = create_tween()
		_tween.tween_property(self, "shown", rects[current], transition_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		shown = rects[current]
	Events.stage_changed.emit(current)


## Back to the tutorial for a new run (no animation, no signal).
func reset() -> void:
	if _tween:
		_tween.kill()
	current = 0
	shown = rects[0]


## First stage whose rectangle contains this position (255 = never).
func stage_at(world_pos: Vector2) -> int:
	for s in rects.size():
		if rects[s].has_point(world_pos):
			return s
	return OUTSIDE


func is_playable(world_pos: Vector2) -> bool:
	return stage_at(world_pos) <= current


## Rectangle of a stage (defaults to the current one).
func bounds(stage := -1) -> Rect2:
	return rects[current if stage < 0 else stage]


## Attribution line required by the data licence (shown bottom-right).
func credit() -> String:
	return meta.get("credit", "")


## GDA94 lon/lat -> world pixels (same maths as tools/build_world.py).
func geo_to_world(lon: float, lat: float) -> Vector2:
	var p: Dictionary = meta["projection"]
	var s: float = meta["px_per_m"]
	return Vector2((lon - p["lon0"]) * p["m_per_deg_lon"] * s, (p["lat0"] - lat) * p["m_per_deg_lat"] * s)
