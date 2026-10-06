extends Camera2D

# Original: right-drag panning (team).
# AI-assisted (Claude Opus 5.5) additions. Prompt used:
#   "Extend our Godot 4.7 Camera2D script, which pans the map while the
#    'Move_Map' action (right mouse) is held, with mouse-wheel zoom that zooms
#    toward the point under the cursor (like Google Maps), clamped between a
#    min and max zoom. Fix panning so a drag moves the map exactly with the
#    mouse at any zoom level, and keep the camera position inside the
#    camera limits so it can't drift off the map and get 'stuck' past them.
#    Keep the original structure and comment the maths."
# Follow-up prompt (single world + stages):
#   "The map is now one large world that expands by stage. Take the camera
#    limits from Stage.bounds() instead of hard-coded numbers, and when the
#    stage changes (and at start) centre on the new area and zoom so the
#    whole stage fits on screen. Let the player zoom out only as far as
#    needed to see the whole current stage."
# Follow-up prompt (milestone 1 HUD):
#   "The HUD now covers the left 450 px (incidents panel) and top 102 px
#    (navigation bar) of a 1920x1080 screen. Fit each stage into the visible
#    map area to the right of and below the panels, not the whole screen, and
#    add focus_on(world_pos) that smoothly pans so a point sits in the middle
#    of that visible area (used when clicking an incident card)."

@export var min_zoom := 0.15     # recalculated per stage
@export var fit_margin := 0.92   # fraction of the screen the stage fills
@export var max_zoom := 2.5
@export var zoom_step := 1.15
## Screen pixels covered by the HUD on the left and top.
@export var ui_inset := Vector2(450, 102)

var dragging := false
var last_mouse_position : Vector2

func _ready():
	add_to_group("main_camera")
	Events.stage_changed.connect(_fit_stage)
	_fit_stage.call_deferred(Stage.current)

# Use the stage's area as the camera limits, then frame the whole of it in
# the part of the screen not covered by the HUD.
func _fit_stage(_stage: int):
	var area: Rect2 = Stage.bounds()
	var screen = get_viewport_rect().size
	var free = (screen - ui_inset).max(screen * 0.3)   # tiny windows: ignore HUD
	var fit = minf(free.x / area.size.x, free.y / area.size.y) * fit_margin
	# World rect the whole screen shows when the stage sits in the free area.
	var view = Rect2(area.get_center() - (ui_inset + free / 2.0) / fit, screen / fit)
	var limits = view.merge(area)
	limit_left = int(limits.position.x)
	limit_top = int(limits.position.y)
	limit_right = int(limits.end.x)
	limit_bottom = int(limits.end.y)
	min_zoom = fit
	zoom = Vector2(fit, fit)
	position = view.get_center()

# Smoothly pan so world_pos sits in the middle of the visible map area.
func focus_on(world_pos: Vector2):
	var offset = (ui_inset / 2.0) / zoom
	var target = world_pos - offset
	var tween = create_tween()
	tween.tween_property(self, "position", target, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_clamp_to_limits)

func _process(delta):
	if Input.is_action_just_pressed("Move_Map"):
		last_mouse_position = get_viewport().get_mouse_position()

	if Input.is_action_pressed("Move_Map"):
		var current_mouse_position = get_viewport().get_mouse_position()

		var difference = current_mouse_position - last_mouse_position

		# Screen pixels -> world pixels: divide by zoom.
		position -= difference / zoom

		last_mouse_position = current_mouse_position
		_clamp_to_limits()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / zoom_step)

# Zoom by a factor while keeping the world point under the cursor fixed.
func _zoom_at(factor: float):
	# Mouse offset from the screen centre (the camera is centre-anchored).
	var from_centre = get_viewport().get_mouse_position() - get_viewport_rect().size / 2.0
	var world_under_mouse = position + from_centre / zoom
	var new_zoom = clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	# Put the camera where that same world point is still under the mouse.
	position = world_under_mouse - from_centre / zoom
	_clamp_to_limits()

# Keep the visible rectangle inside the limits (or centred if the map is
# smaller than the screen at this zoom).
func _clamp_to_limits():
	var half = get_viewport_rect().size / zoom / 2.0
	var lo = Vector2(limit_left, limit_top) + half
	var hi = Vector2(limit_right, limit_bottom) - half
	position.x = clampf(position.x, lo.x, hi.x) if lo.x <= hi.x else (limit_left + limit_right) / 2.0
	position.y = clampf(position.y, lo.y, hi.y) if lo.y <= hi.y else (limit_top + limit_bottom) / 2.0
