extends Node2D

# Route drawing: press on a station, HOLD the mouse and trace along the roads
# you want the crew to take, then release on an incident to dispatch.
#
# Original version (Vandy): free-hand line, raycasts against block collisions,
# and ChatGPT-assisted snapping of the corners to hand-placed RoadPoints.
#
# AI-assisted rewrite (Claude Opus 5.5). Prompt used:
#   "Rewrite our Godot 4.7 route drawing as true freehand drawing in the style
#    of Mini Motorways: the player presses the left mouse ('Draw') on a
#    station, holds, and traces the route with the mouse; release over an
#    incident to dispatch the crew. While held, sample the mouse every few
#    pixels, snap each sample to the nearest playable road (RoadGraph.snap) and
#    extend the route from its current tip to that point along the road
#    network - but ONLY for short local steps (the road distance must be close
#    to the straight-line distance), so the game never invents a long detour:
#    the player has to actually trace corners and turns, and dragging across a
#    block does nothing until the mouse comes back to a connected road.
#    Moving back over the route trims it (retracing = undo). Releasing
#    anywhere other than an incident keeps the unfinished route; pressing near
#    its end continues it. Space ('clear_draw') clears it, R ('Undo_Drawing')
#    trims the last bit. Stations and incidents are picked by proximity to the
#    mouse (scaled by zoom) and must be inside the current Stage. Show the
#    route as a thick blue line, faded while unfinished, with a red hint line
#    to the mouse when it's too far from a usable road. Once dispatched, the
#    crew follows the route; its speed on each road is scaled by the TRUE
#    traffic in World, and each road it finishes is reported to
#    Knowledge.observe(). Emit Events for drawing started, route committed,
#    crew dispatched and crew arrived, and expose a one-line status string for
#    the debug HUD. Keep the single temporary crew (real crews/stations are
#    the next task)."
# Follow-up prompt: "A nearly-straight long jump still got accepted by the
#    detour check. Also cap each step's road length to ~90 screen pixels so a
#    single mouse sample can never auto-route a long way; the player must
#    trace it."
# Follow-up prompt (spurs, trail, sightings):
#   "Wobbling the mouse at junctions leaves little spurs where the line pokes
#    a few pixels into a side street and comes back. Whenever a new step
#    makes the route pass back through a point it already visited, cut out
#    the loop between the two visits (and drop the undo anchors inside it).
#    While the crew drives, erase the line behind it so only the remaining
#    route shows and the player can see the traffic being revealed. Replace
#    'observe the road when finished' with crew sightings: every 0.15 s call
#    Knowledge.sight() at the crew's position, which reveals the roads and the
#    map colour around it."

@onready var line = $Line

# For the points
@export var locations : Node2D
@export var end_points : Node2D

# For police crew (temporary: replaced by real crews/stations next task)
var crew_scene = preload("res://police_crew.tscn")
var crew : Node2D = null
@export var crew_speed := 120.0          # world px per second at full speed

## Screen-pixel radius for picking stations/incidents and finding roads.
@export var pick_radius_screen := 26.0
## A step is accepted if its road distance <= this x straight-line distance...
@export var max_detour := 1.8
## ...and no longer than this many screen pixels.
@export var max_step_screen := 90.0

const ROUTE_COLOUR := Color("1f6fd8")
const DRAFT_ALPHA := 0.55

enum State { IDLE, DRAWING, FOLLOWING }
var state := State.IDLE

var start_point = null                  # station the route starts from
var tips : Array = []                   # accepted RoadGraph.RoadPos samples
var tip_sizes : Array[int] = []         # route_points.size() after each tip
var route_points := PackedVector2Array()
var route_point_edges := PackedInt32Array()   # road edge of each point (-1 = off road)
var _last_sample := Vector2.INF
var _hint_to := Vector2.INF             # red "can't reach" hint end

# Crew following
var path_index := 1
var target_incident = null
const SIGHT_INTERVAL := 0.15
var _sight_timer := 0.0


func _ready() -> void:
	add_to_group("route_drawer")
	line.width = 6.0
	line.default_color = ROUTE_COLOUR
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			_idle()
		State.DRAWING:
			_drawing()
		State.FOLLOWING:
			move_crew(delta)


# --- Drawing ---------------------------------------------------------------

func _idle():
	if Input.is_action_just_pressed("clear_draw"):
		_clear_route()
	if Input.is_action_just_pressed("Undo_Drawing"):
		_trim_tips(10)
	if not Input.is_action_just_pressed("Draw"):
		return
	var mouse = get_global_mouse_position()
	# Continue an unfinished route by pressing near its end...
	if not tips.is_empty() and mouse.distance_to(route_points[route_points.size() - 1]) <= _pick_radius():
		state = State.DRAWING
		return
	# ...or start a new one from a station.
	var station = _nearest(locations, mouse)
	if station == null:
		return
	_begin_at_station(station, mouse)


## Start a new route at a station (separate so tests can call it directly).
func _begin_at_station(station, mouse: Vector2):
	var start_pos = RoadGraph.snap(station.global_position, 200.0)
	if start_pos == null:
		return
	_clear_route()
	start_point = station
	tips = [start_pos]
	route_points = PackedVector2Array([station.global_position, start_pos.point])
	route_point_edges = PackedInt32Array([-1, start_pos.edge])
	tip_sizes = [route_points.size()]
	_last_sample = mouse
	state = State.DRAWING
	Events.route_drawing_started.emit(null)


func _drawing():
	var mouse = get_global_mouse_position()

	if not Input.is_action_pressed("Draw"):
		_on_release(mouse)
		return

	if mouse.distance_to(_last_sample) >= 3.0 / _zoom():
		_last_sample = mouse
		_sample(mouse)
	_refresh_line()


# One mouse sample while the button is held.
func _sample(mouse: Vector2):
	# Retracing: if the mouse is back over an earlier tip, cut the route there.
	var back_r = 12.0 / _zoom()
	for k in range(tips.size() - 2, maxi(-1, tips.size() - 60), -1):
		if tips[k].point.distance_to(mouse) <= back_r:
			_trim_tips(tips.size() - 1 - k)
			_hint_to = Vector2.INF
			return

	var snapped = RoadGraph.snap(mouse, _pick_radius())
	if snapped == null:
		_hint_to = mouse
		return
	if _extend_to(snapped):
		_hint_to = Vector2.INF
	else:
		_hint_to = mouse


# Try to extend the route along roads to a snapped point. Only short, local
# steps are allowed so the player draws the route, not the pathfinder.
func _extend_to(snapped) -> bool:
	var tip = tips.back()
	var straight = tip.point.distance_to(snapped.point)
	if straight < 0.5:
		return true
	var leg = RoadGraph.route(tip, snapped)
	if leg.points.is_empty() or leg.length > maxf(40.0, straight * max_detour) or leg.length > max_step_screen / _zoom():
		return false
	var new_pts = leg.points.slice(1)
	var new_edges = leg.point_edges.slice(1)
	# If the step passes back through a point already on the route, the bit
	# in between is a spur or loop: cut it out.
	var loop = _find_loop(new_pts)
	if not loop.is_empty():
		var k = loop[0]
		route_points.resize(k + 1)
		route_point_edges.resize(k + 1)
		new_pts = new_pts.slice(loop[1] + 1)
		new_edges = new_edges.slice(loop[1] + 1)
		while tip_sizes.size() > 1 and tip_sizes.back() > k + 1:
			tips.pop_back()
			tip_sizes.pop_back()
	route_points.append_array(new_pts)
	route_point_edges.append_array(new_edges)
	tips.append(snapped)
	tip_sizes.append(route_points.size())
	return true


# [route index, new point index] of the first new point that revisits the
# route (ignoring the current tip itself), or [] if there is no loop.
func _find_loop(new_pts: PackedVector2Array) -> Array:
	var last = route_points.size() - 1
	for j in new_pts.size():
		for k in range(last - 1, maxi(0, last - 400), -1):
			if route_points[k].distance_to(new_pts[j]) < 1.0:
				# Must actually have left that point (not a duplicate junction).
				var away = 0.0
				for i in range(k + 1, last + 1):
					away += route_points[i - 1].distance_to(route_points[i])
				if away > 1.0:
					return [k, j]
	return []


func _on_release(mouse: Vector2):
	_hint_to = Vector2.INF
	state = State.IDLE
	var incident = _nearest(end_points, mouse)
	if incident != null:
		var end_pos = RoadGraph.snap(incident.global_position, 200.0)
		if end_pos != null and _extend_to(end_pos):
			_dispatch(incident)
			return
	_refresh_line()   # keep the unfinished route on screen


func _trim_tips(count: int):
	if tips.is_empty():
		return
	var keep = maxi(1, tips.size() - count)
	tips.resize(keep)
	tip_sizes.resize(keep)
	route_points.resize(tip_sizes[keep - 1])
	route_point_edges.resize(tip_sizes[keep - 1])
	_refresh_line()


func _clear_route():
	tips = []
	tip_sizes = []
	route_points = PackedVector2Array()
	route_point_edges = PackedInt32Array()
	start_point = null
	line.clear_points()


func _refresh_line():
	var shown = route_points.duplicate()
	var finished = state == State.FOLLOWING
	line.default_color = ROUTE_COLOUR if finished or state == State.DRAWING else Color(ROUTE_COLOUR, DRAFT_ALPHA)
	_show(shown)
	queue_redraw()


func _draw():
	# Red hint: the mouse is too far from a road connected to the route tip.
	if state == State.DRAWING and _hint_to != Vector2.INF and not route_points.is_empty():
		var tip = to_local(route_points[route_points.size() - 1])
		draw_dashed_line(tip, to_local(_hint_to), Color(0.9, 0.2, 0.2, 0.8), 3.0, 10.0)


# --- Dispatch & crew -------------------------------------------------------

func _dispatch(incident):
	route_points.append(incident.global_position)
	route_point_edges.append(-1)
	target_incident = incident
	crew = crew_scene.instantiate()
	crew.scale = Vector2(0.6, 0.6)   # sprite was sized for the old map scale
	add_child(crew)
	crew.global_position = route_points[0]
	path_index = 1
	_sight_timer = 0.0
	state = State.FOLLOWING
	_refresh_line()
	Events.route_committed.emit(crew, route_points, Array(route_point_edges))
	Events.crew_dispatched.emit(crew, incident)


func move_crew(delta):
	if path_index >= route_points.size():
		_arrive()
		return

	var target_position = to_local(route_points[path_index])
	var direction = target_position - crew.position
	if direction.length() > 0.01:
		crew.rotation = direction.angle()

	# True traffic slows the crew, whatever the player's map says.
	var edge = route_point_edges[path_index]
	var speed = crew_speed
	if edge >= 0:
		speed *= maxf(World.speed_multiplier(edge), 0.15)

	crew.position = crew.position.move_toward(target_position, speed * delta)
	if crew.position.distance_to(target_position) < 0.5:
		path_index += 1

	# Crew sightings: reveal roads and map colour around the crew.
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = SIGHT_INTERVAL
		Knowledge.sight(crew.global_position)

	# Only show the route still ahead of the crew.
	var ahead = PackedVector2Array([crew.global_position])
	ahead.append_array(route_points.slice(path_index))
	_show(ahead)


func _arrive():
	Events.crew_arrived.emit(crew, target_incident)
	if target_incident != null and target_incident.visible:
		target_incident.deactivate()
		Events.incident_resolved.emit(target_incident)
		target_incident.get_parent().show_new_random_point()
	if crew != null:
		crew.queue_free()
		crew = null
	target_incident = null
	state = State.IDLE
	_clear_route()


# --- Helpers ---------------------------------------------------------------

## One-line summary for the debug HUD.
func status_text() -> String:
	match state:
		State.DRAWING:
			var e = route_point_edges[route_point_edges.size() - 1]
			return "Drawing route (%d m) - on %s" % [_route_metres(), RoadGraph.edge_name[e] if e >= 0 else "?"]
		State.FOLLOWING:
			var e = route_point_edges[mini(path_index, route_point_edges.size() - 1)]
			if e < 0:
				return "Crew en route"
			return "Crew driving %s (true traffic x%.1f speed)" % [RoadGraph.edge_name[e], World.speed_multiplier(e)]
	if not tips.is_empty():
		return "Unfinished route (%d m) - press near its end to keep drawing, Space to clear" % _route_metres()
	return "Idle - press on a station and drag along the roads"


func _route_metres() -> int:
	var total = 0.0
	for i in range(1, route_points.size()):
		total += route_points[i - 1].distance_to(route_points[i])
	return int(total / float(Stage.meta["px_per_m"]))


func _zoom() -> float:
	var cam = get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0


func _pick_radius() -> float:
	return pick_radius_screen / _zoom()


# Closest visible, playable child of `group_node` within the pick radius.
func _nearest(group_node: Node2D, world_pos: Vector2):
	var best = null
	var best_d = _pick_radius()
	for point in group_node.get_children():
		if not point.visible or not Stage.is_playable(point.global_position):
			continue
		var d = point.global_position.distance_to(world_pos)
		if d <= best_d:
			best = point
			best_d = d
	return best


func _show(world_points: PackedVector2Array):
	var local = PackedVector2Array()
	for p in world_points:
		local.append(line.to_local(p))
	line.points = local
