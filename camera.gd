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

@export var min_zoom := 0.35
@export var max_zoom := 2.5
@export var zoom_step := 1.15

var dragging := false
var last_mouse_position : Vector2

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
