class_name Crew extends Node2D
## One emergency crew (a vehicle). Belongs to a Station. Life cycle:
##   AVAILABLE (parked) -> EN_ROUTE (follows the drawn route) -> ON_SCENE
##   (the incident runs its resolve timer) -> RETURNING (pathfinds home along
##   roads) -> COOLDOWN (rests at the station) -> AVAILABLE
## While driving it reveals what it sees (Knowledge.sight) and is slowed by
## the TRUE traffic in World, whatever the player's map says.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Crew node for the dispatch game, replacing the single
#    hard-coded police car in drawing.gd and building on Vandy's
#    solve-then-return idea (police_crew.gd). Each crew has a CrewType
#    resource, a home Station, a short callsign (e.g. 'Police 1') and a state
#    machine: AVAILABLE, EN_ROUTE, ON_SCENE, RETURNING, COOLDOWN.
#    dispatch(points, edges, incident) makes it follow a drawn route exactly,
#    at the crew type's speed scaled by World.speed_multiplier for the road
#    it is on; every 0.15 s it calls Knowledge.sight() at its position. On
#    reaching the end it tells the incident it has arrived; the incident
#    decides whether it is the right crew and calls go_home() when done (or
#    straight away if it's the wrong crew). go_home() pathfinds back to the
#    station along roads with RoadGraph.route and follows that path; on
#    arrival it rests for the type's cooldown, then becomes available.
#    Emit the matching Events (crew_dispatched, crew_arrived, crew_returned,
#    crew_ready, crew_state_changed). Draw it as the police car sprite tinted
#    by crew type with a small round icon badge, kept a readable size on
#    screen at any zoom, hidden while parked. Show the remaining route ahead
#    of it as a thin line in its type colour (nothing behind it, so the
#    revealed traffic is visible). Provide status_text() for the UI."
# Follow-up prompt (milestone 2 - obstacles and redraws):
#   "Before driving onto each road of its route, the crew checks the TRUE
#    world: if the road is blocked (and the blockage isn't its own incident,
#    e.g. the crash it is going to), it stops at the junction in a new
#    BLOCKED state, looks around (Knowledge.sight, so the blockage appears on
#    the player's map) and emits Events.crew_blocked. Time keeps running
#    while it waits. If the road clears it carries on by itself. While
#    blocked, draw a pulsing red alert badge with an exclamation mark. Add
#    reroute(points, edges, incident) for a route the player redraws from the
#    crew's current position, and a 'held' flag that pauses it while the
#    player is drawing that new route. A crew driving home on its own that
#    hits a blockage just pathfinds around it. Include the blockage reason
#    and road in status_text()."
# Follow-up prompt: "A crew standing at a junction next to a blockage got
#    stuck: a zero-length step 'on' the blocked road counted as driving onto
#    it, and the route home snapped onto the blocked road. Skip zero-length
#    steps before checking for blockages, and snap away from avoided roads."
# Follow-up prompt: "Draw a slowly marching dashed circle around the crew
#    showing its vision radius (Knowledge.sight_radius_m) while it is out."
# Follow-up prompt (milestone 3 - blocked countdown):
#   "Replace the blocked '!' badge with a Mini Metro style countdown dial
#    around the crew's icon: a red arc showing how much patience is left
#    (blocked_patience seconds), with the badge pulsing in size and a pulsing
#    halo, faster as it runs out. If it reaches zero the crew gives up: it
#    heads home and its incident fails, which costs a life."
# Follow-up prompt: "Remember whether the player's map already showed the
#    blockage before the crew stopped (for the 'stopped by obstacles the
#    map didn't show' statistic) - check before revealing it."
# Follow-up: "The crew's own sight reveals the block just before it arrives,
#    so instead record which roads the map showed as blocked when the route
#    was drawn, and compare against that."
# Follow-up prompt: "Widen the area from which a crew can reach its
#    incident: once an en-route crew is within access_radius_m of its
#    incident it counts as arrived (it parks and goes in on foot), even if
#    the last bit of road ahead is blocked."
# Follow-up prompt: "Keep the car and badge the same size on screen when
#    zoomed far out (scale up to 4.5x), add an SES tint."
# Follow-up prompt: "Crews now stop too far from the incident. They should
#    still drive all the way if they can, and only park within
#    access_radius_m if the road ahead is blocked. Add cooldown_left() for
#    the station's cooldown dial."
# Follow-up prompt (physics): "Give the crew Scenes/crew_physics.tscn: a
#    kinematic AnimatableBody2D bumper the size of the car (layer 2
#    'vehicles', mask 3 'debris') that turns with the car and shoves scene
#    debris aside, scaled with the car up to 1.6x so it doesn't bulldoze the
#    map when zoomed out, and disabled while parked at the station; and an
#    Area2D sensor (layer 5 'crew_sensors', mask 4 'incident_zones') that
#    replaces the distance check: a crew can park and walk in once its
#    sensor overlaps its own incident's scene zone. Crews ignore each other,
#    barriers and other crews' sensors."

enum State { AVAILABLE, EN_ROUTE, ON_SCENE, RETURNING, COOLDOWN, BLOCKED }

const STATE_NAMES := ["Available", "En route", "On scene", "Returning", "Cooldown", "Blocked"]
const SIGHT_INTERVAL := 0.15
const CAR_TEXTURE := preload("res://Assets/Police car.svg")
const PHYSICS_SCENE := preload("res://Scenes/crew_physics.tscn")
## Car sprite size at scale 1 (texture 159 x 63 at the sprite's 0.32 x 0.34).
const CAR_SIZE := Vector2(51, 21.5)
## Biggest the bumper grows with the zoom-out scale.
const MAX_BUMPER_SCALE := 1.6
## Tint applied to the (black and white) car sprite per crew type.
const TINTS := {&"police": Color(1, 1, 1), &"ambulance": Color(1.0, 0.93, 0.62), &"fire": Color(1.0, 0.36, 0.26),
	&"ses": Color(1.0, 0.75, 0.2)}

var type: CrewType
var station: Node2D
var callsign := ""
var state := State.AVAILABLE
var incident: Node2D = null
## Paused while the player redraws this crew's route.
var held := false
var blocked_edge := -1
## Seconds a blocked crew waits for a new route before giving up.
@export var blocked_patience := 25.0
var _patience := 0.0
## Did the player's map already show this blockage when we hit it?
var blocked_was_known := false
var _known_blocked_at_dispatch := {}

var _points := PackedVector2Array()
var _edges := PackedInt32Array()
var _index := 0
var _cooldown := 0.0
var _sight_timer := 0.0
var _body: Node2D
var _trail: Line2D
var _alert_t := 0.0
var _waiting_on := -1     # blocked road a returning crew already tried to avoid
var _physics: Node2D
var _sensor: Area2D
var _bumper_shape: CollisionShape2D
var _bumper_scale := 0.0


func setup(crew_type: CrewType, home: Node2D, number: int) -> void:
	type = crew_type
	station = home
	callsign = "%s %d" % [type.display_name, number]
	name = callsign.replace(" ", "")
	add_to_group("crews")


func _ready() -> void:
	_trail = Line2D.new()
	_trail.top_level = true          # world coordinates, ignores our rotation
	_trail.width = 3.0
	_trail.default_color = Color(type.colour, 0.85)
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_trail)

	_body = Node2D.new()
	add_child(_body)
	var car := Sprite2D.new()
	car.texture = CAR_TEXTURE
	car.scale = Vector2(0.32, 0.34)
	car.modulate = TINTS.get(type.id, Color.WHITE)
	_body.add_child(car)

	_physics = PHYSICS_SCENE.instantiate()
	add_child(_physics)
	_sensor = _physics.get_node("Sensor")
	_bumper_shape = _physics.get_node("Bumper/Shape")
	_bumper_shape.shape = _bumper_shape.shape.duplicate()   # each crew sizes its own

	global_position = station.global_position
	visible = false


func _process(delta: float) -> void:
	# Stay readable at any zoom (between 60% and 160% of natural size).
	var cam := get_viewport().get_camera_2d()
	if cam:
		_body.scale = Vector2.ONE * clampf(1.0 / cam.zoom.x, 0.6, 4.5)
	_sync_physics()
	queue_redraw()

	if held:
		return
	match state:
		State.EN_ROUTE, State.RETURNING:
			_drive(delta)
		State.BLOCKED:
			_patience -= delta
			_alert_t += delta * lerpf(4.0, 12.0, 1.0 - patience_left())
			if not _blocks_us(blocked_edge) or _close_enough():
				blocked_edge = -1
				_set_state(State.EN_ROUTE)   # road cleared: carry on
			elif _patience <= 0.0:
				_give_up()
		State.COOLDOWN:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_set_state(State.AVAILABLE)
				Events.crew_ready.emit(self)


func _draw() -> void:
	# Round badge with the crew type icon, drawn upright above the car.
	if not visible:
		return
	var vision := Knowledge.sight_radius_m * float(Stage.meta["px_per_m"])
	DrawUtil.dashed_circle(self, Vector2.ZERO, vision, Color(type.colour, 0.6), 2.0 * _body.scale.x,
		8.0, Knowledge.clock * 12.0)
	var s: float = _body.scale.x
	var c := Vector2(0, -26) * s
	var badge := 11.0 * s
	if state == State.BLOCKED:
		# Countdown dial + pulse: the crew needs a new route, now.
		var beat := 0.5 + 0.5 * sin(_alert_t)
		badge *= 1.0 + 0.25 * beat
		draw_circle(c, badge + (8.0 + 8.0 * beat) * s, Color(0.85, 0.1, 0.1, 0.3 * (1.0 - beat)))
		draw_arc(c, badge + 4.0 * s, 0, TAU, 40, Color(0, 0, 0, 0.3), 4.0 * s)
		draw_arc(c, badge + 4.0 * s, -PI / 2, -PI / 2 + TAU * patience_left(), 40, Color("d62828"), 4.0 * s)
	draw_circle(c, badge, type.colour)
	draw_circle(c, badge, Color.WHITE, false, 2.0 * s)
	if type.icon:
		var half := badge * 0.72
		draw_texture_rect(type.icon, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false, Color.WHITE)


# --- Commands ------------------------------------------------------------------

func is_available() -> bool:
	return state == State.AVAILABLE


## Follow a drawn route (world points + the road edge of each point).
func dispatch(points: PackedVector2Array, edges: PackedInt32Array, target: Node2D) -> void:
	incident = target
	_follow(points, edges)
	_set_state(State.EN_ROUTE)
	Events.crew_dispatched.emit(self, target)


## Called by the incident when the job is finished (or we were the wrong crew).
func go_home() -> void:
	incident = null
	_route_home({})
	_set_state(State.RETURNING)


func _route_home(avoid: Dictionary) -> void:
	if avoid.is_empty():
		_waiting_on = -1
	var from: Variant = RoadGraph.snap(global_position, 300.0, avoid)
	var to: Variant = RoadGraph.snap(station.global_position, 300.0)
	var path := PackedVector2Array([global_position])
	var edges := PackedInt32Array([-1])
	if from != null and to != null:
		var r = RoadGraph.route(from, to, avoid)
		path.append_array(r.points)
		edges.append_array(r.point_edges)
	path.append(station.global_position)
	edges.append(-1)
	_follow(path, edges)


# True if the real world has this road blocked by something other than our
# own incident (a crew may drive onto the crash it is attending).
func _blocks_us(edge: int) -> bool:
	return edge >= 0 and World.is_blocked(edge) and (World.blocked_by(edge) == null or World.blocked_by(edge) != incident)


func _stop_blocked(edge: int) -> void:
	blocked_edge = edge
	blocked_was_known = _known_blocked_at_dispatch.has(edge)
	_alert_t = 0.0
	_patience = blocked_patience
	Knowledge.sight(global_position)      # now the player can see why
	Knowledge.observe(edge)
	_set_state(State.BLOCKED)
	Events.crew_blocked.emit(self, edge)


## A route the player redrew from the crew's current position.
func reroute(points: PackedVector2Array, edges: PackedInt32Array, target: Node2D) -> void:
	incident = target
	held = false
	blocked_edge = -1
	_follow(points, edges)
	_set_state(State.EN_ROUTE)
	Events.crew_dispatched.emit(self, target)


## 1 = cooldown just started, 0 = ready (or not cooling down).
func cooldown_left() -> float:
	return clampf(_cooldown / type.cooldown_seconds, 0.0, 1.0) if state == State.COOLDOWN else 0.0


## 1 = just stopped, 0 = about to give up.
func patience_left() -> float:
	return clampf(_patience / blocked_patience, 0.0, 1.0) if state == State.BLOCKED else 1.0


func _give_up() -> void:
	var inc := incident
	Events.ticker_message.emit("%s [color=#ffb347]couldn't get past[/color] the %s" % [callsign, World.block_reason(blocked_edge).to_lower()])
	go_home()
	if inc != null and is_instance_valid(inc) and inc.has_method("fail"):
		inc.fail("%s on %s" % [inc.title().to_lower(), inc.place])


func is_redrawable() -> bool:
	return state == State.EN_ROUTE or state == State.BLOCKED


func status_text() -> String:
	match state:
		State.BLOCKED:
			var road: String = RoadGraph.edge_name[blocked_edge] if blocked_edge >= 0 else ""
			return "BLOCKED: %s%s - redraw (%ds)" % [World.block_reason(blocked_edge).to_lower(),
				(" on " + road) if road != "" else "", ceili(_patience)]
		State.COOLDOWN:
			return "Cooldown %ds" % ceili(_cooldown)
		State.EN_ROUTE, State.RETURNING:
			var e := _edges[mini(_index, _edges.size() - 1)] if not _edges.is_empty() else -1
			var road := RoadGraph.edge_name[e] if e >= 0 else ""
			return "%s%s" % [STATE_NAMES[state], (" - " + road) if road != "" else ""]
	return STATE_NAMES[state]


# --- Movement ------------------------------------------------------------------

func _follow(points: PackedVector2Array, edges: PackedInt32Array) -> void:
	_known_blocked_at_dispatch.clear()
	for e in edges:
		if e >= 0 and Knowledge.known_level(e) == World.Traffic.BLOCKED:
			_known_blocked_at_dispatch[e] = true
	_points = points
	_edges = edges
	_index = 1
	_sight_timer = 0.0
	global_position = points[0]
	visible = true


func _drive(delta: float) -> void:
	if _index >= _points.size():
		_finish_leg()
		return
	var edge := _edges[_index]
	if global_position.distance_to(_points[_index]) < 0.5:
		_index += 1            # already there (e.g. a junction point): not driving onto it
		return
	if _blocks_us(edge):
		if _close_enough():
			_finish_leg()       # blocked just short of the incident: park and walk in
			return
		if state == State.RETURNING:
			# Nobody to ask: find another way, or wait if there is none.
			if _waiting_on != edge:
				_waiting_on = edge
				_route_home({edge: true})
			return
		_stop_blocked(edge)
		return
	var target := _points[_index]
	var to_target := target - global_position
	if to_target.length() > 0.01:
		_body.rotation = to_target.angle()

	var speed := type.speed_mps * float(Stage.meta["px_per_m"])
	if edge >= 0:
		speed *= maxf(World.speed_multiplier(edge), 0.15)   # true traffic
	global_position = global_position.move_toward(target, speed * delta)
	if global_position.distance_to(target) < 0.5:
		_index += 1

	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = SIGHT_INTERVAL
		Knowledge.sight(global_position)

	# Only the route still ahead of the crew.
	var ahead := PackedVector2Array([global_position])
	ahead.append_array(_points.slice(_index))
	_trail.points = ahead


# Near enough to walk in from here? (Our sensor is inside its scene zone.)
func _close_enough() -> bool:
	return state == State.EN_ROUTE and incident != null and is_instance_valid(incident) \
		and incident.zone != null and _sensor.overlaps_area(incident.zone)


# Bumper follows the car: same heading, same size (capped), off when parked.
func _sync_physics() -> void:
	_physics.rotation = _body.rotation
	var s := minf(_body.scale.x, MAX_BUMPER_SCALE)
	if not is_equal_approx(s, _bumper_scale):
		_bumper_scale = s
		(_bumper_shape.shape as RectangleShape2D).size = CAR_SIZE * s
	if _bumper_shape.disabled == visible:
		_bumper_shape.set_deferred("disabled", not visible)


func _finish_leg() -> void:
	_trail.clear_points()
	if state == State.EN_ROUTE:
		_set_state(State.ON_SCENE)
		Events.crew_arrived.emit(self, incident)
		if incident == null or not is_instance_valid(incident) or not incident.crew_arrived(self):
			go_home()
	elif state == State.RETURNING:
		visible = false
		global_position = station.global_position
		_cooldown = type.cooldown_seconds
		_set_state(State.COOLDOWN)
		Events.crew_returned.emit(self)


func _set_state(s: State) -> void:
	state = s
	Events.crew_state_changed.emit(self)
