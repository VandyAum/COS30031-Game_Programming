extends Node2D

# Route drawing: click a station, click along the roads you want the crew to
# take, then click an incident. The crew drives the drawn route.
#
# Original version (Vandy): free-hand line, raycasts against block collisions,
# and ChatGPT-assisted snapping of the corners to hand-placed RoadPoints.
#
# AI-assisted rewrite (Claude Opus 5.5). Prompt used:
#   "Rewrite our Godot 4.7 route drawing script to use the new RoadGraph
#    autoload instead of raycasts and RoadPoints, keeping the same player flow
#    and input actions: click a station (Crew_points.clicked) to start, left
#    click ('Draw') to drop waypoints, 'Undo_Drawing' (R) removes the last
#    waypoint, 'clear_draw' (Space) cancels, and clicking a visible incident
#    (endPoint.clicked) finishes the route. Every click snaps to the nearest
#    point on a road, and each leg between waypoints follows the roads exactly
#    using RoadGraph.route(), so the route can never cut through a block. Show
#    a live preview leg from the last waypoint to the road point under the
#    mouse. When finished, the crew follows the polyline; its speed on each
#    road is scaled by the TRUE traffic in World (so stale map data costs real
#    time), and every road it drives is reported to Knowledge.observe() so the
#    overlay lights up behind it. On arrival emit Events.crew_arrived, resolve
#    the incident, remove the crew and allow a new route to be drawn. Proper
#    crews, stations, return trips and cooldowns are the next task, so keep
#    the crew handling simple and clearly marked as temporary."

@onready var line = $Line

# For the points
@export var locations : Node2D
@export var end_points : Node2D

# For police crew (temporary: replaced by real crews/stations next task)
var crew_scene = preload("res://police_crew.tscn")
var crew : Node2D = null
@export var crew_speed := 200

enum State { WAITING_FOR_STATION, DRAWING, FOLLOWING }
var state := State.WAITING_FOR_STATION

var start_point = null              # station the route starts from
var waypoints : Array = []          # RoadGraph.RoadPos per click
var leg_lengths : Array[int] = []   # how many points each leg added (for undo)
var route_points := PackedVector2Array()
var route_point_edges := PackedInt32Array()   # road edge of each point (-1 = off road)

# Crew following
var path_index := 1
var target_incident = null


func _process(delta: float) -> void:
	match state:
		State.WAITING_FOR_STATION:
			_wait_for_station()
		State.DRAWING:
			_draw_route()
		State.FOLLOWING:
			move_crew(delta)


func _wait_for_station():
	var clicked_location = get_clicked_location()
	if clicked_location == null:
		return
	clicked_location.clicked = false
	var start_pos = RoadGraph.snap(clicked_location.global_position)
	if start_pos == null:
		return
	start_point = clicked_location
	waypoints = [start_pos]
	leg_lengths = []
	route_points = PackedVector2Array([clicked_location.global_position, start_pos.point])
	route_point_edges = PackedInt32Array([-1, start_pos.edge])
	for point in end_points.get_children():
		point.can_clicked = point.visible
	state = State.DRAWING
	Events.route_drawing_started.emit(null)


func _draw_route():
	if Input.is_action_just_pressed("clear_draw"):
		_reset()
		return

	var end_point = get_clicked_end_point()
	if end_point != null:
		end_point.clicked = false
		_finish_route(end_point)
		return

	if Input.is_action_just_pressed("Undo_Drawing") and leg_lengths.size() > 0:
		var n = leg_lengths.pop_back()
		route_points.resize(route_points.size() - n)
		route_point_edges.resize(route_point_edges.size() - n)
		waypoints.pop_back()

	var mouse_pos = RoadGraph.snap(get_global_mouse_position())

	if Input.is_action_just_pressed("Draw") and mouse_pos != null:
		_add_leg(mouse_pos)

	# Show committed route + preview leg to the road under the mouse.
	var shown = route_points.duplicate()
	if mouse_pos != null:
		shown.append_array(RoadGraph.route(waypoints.back(), mouse_pos).points)
	_show(shown)


func _add_leg(to_pos):
	var leg = RoadGraph.route(waypoints.back(), to_pos)
	if leg.points.is_empty():
		return
	route_points.append_array(leg.points)
	route_point_edges.append_array(leg.point_edges)
	leg_lengths.append(leg.points.size())
	waypoints.append(to_pos)


func _finish_route(end_point):
	var end_pos = RoadGraph.snap(end_point.global_position)
	if end_pos == null:
		return
	_add_leg(end_pos)
	route_points.append(end_point.global_position)
	route_point_edges.append(-1)
	_show(route_points)

	target_incident = end_point
	crew = crew_scene.instantiate()
	add_child(crew)
	crew.global_position = route_points[0]
	path_index = 1
	state = State.FOLLOWING
	Events.route_committed.emit(crew, route_points, Array(route_point_edges))


func move_crew(delta):
	if path_index >= route_points.size():
		_arrive()
		return

	var target_position = line.to_local(route_points[path_index])
	var direction = target_position - crew.position
	if direction.length() > 0.01:
		crew.rotation = direction.angle()

	# True traffic slows the crew, whatever the player's map says.
	var edge = route_point_edges[path_index]
	var speed = crew_speed
	if edge >= 0:
		speed *= maxf(World.speed_multiplier(edge), 0.15)

	crew.position = crew.position.move_toward(target_position, speed * delta)
	if crew.position.distance_to(target_position) < 1.0:
		# Report the road we just drove so the player's map refreshes.
		if edge >= 0 and (path_index + 1 >= route_point_edges.size() or route_point_edges[path_index + 1] != edge):
			Knowledge.observe(edge)
		path_index += 1


func _arrive():
	Events.crew_arrived.emit(crew, target_incident)
	if target_incident != null and target_incident.visible:
		target_incident.deactivate()
		target_incident.get_parent().show_new_random_point()
	_reset()


func _reset():
	if crew != null:
		crew.queue_free()
		crew = null
	line.clear_points()
	waypoints = []
	leg_lengths = []
	route_points = PackedVector2Array()
	route_point_edges = PackedInt32Array()
	target_incident = null
	for point in locations.get_children():
		point.clicked = false
	state = State.WAITING_FOR_STATION


func _show(world_points: PackedVector2Array):
	var local = PackedVector2Array()
	for p in world_points:
		local.append(line.to_local(p))
	line.points = local


func get_clicked_location():
	for point in locations.get_children():
		if point.clicked:
			return point

	return null

func get_clicked_end_point():
	for point in end_points.get_children():
		if point.clicked:
			return point

	return null
