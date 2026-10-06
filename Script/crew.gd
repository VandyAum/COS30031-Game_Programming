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

enum State { AVAILABLE, EN_ROUTE, ON_SCENE, RETURNING, COOLDOWN }

const STATE_NAMES := ["Available", "En route", "On scene", "Returning", "Cooldown"]
const SIGHT_INTERVAL := 0.15
const POLICE_TEXTURE := preload("res://Assets/police_car.png")
const AMBULANCE_TEXTURE := preload("res://Assets/ambulance.png")
const FIRE_TEXTURE := preload("res://Assets/fire_truck.png")

const CREW_TEXTURES := {
	&"police": POLICE_TEXTURE,
	&"ambulance": AMBULANCE_TEXTURE,
	&"fire": FIRE_TEXTURE
}
## Tint applied to the (black and white) car sprite per crew type.
#const TINTS := {&"police": Color(1, 1, 1), &"ambulance": Color(1.0, 0.93, 0.62), &"fire": Color(1.0, 0.36, 0.26)}

var type: CrewType
var station: Node2D
var callsign := ""
var state := State.AVAILABLE
var incident: Node2D = null

var _points := PackedVector2Array()
var _edges := PackedInt32Array()
var _index := 0
var _cooldown := 0.0
var _sight_timer := 0.0
var _body: Node2D
var _trail: Line2D


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
	car.texture = CREW_TEXTURES.get(type.id, POLICE_TEXTURE)
	car.scale = Vector2(0.32, 0.34)
	#car.modulate = TINTS.get(type.id, Color.WHITE)
	_body.add_child(car)

	global_position = station.global_position
	visible = false


func _process(delta: float) -> void:
	# Stay readable at any zoom (between 60% and 160% of natural size).
	var cam := get_viewport().get_camera_2d()
	if cam:
		_body.scale = Vector2.ONE * clampf(1.0 / cam.zoom.x, 0.6, 1.6)
	queue_redraw()

	match state:
		State.EN_ROUTE, State.RETURNING:
			_drive(delta)
		State.COOLDOWN:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_set_state(State.AVAILABLE)
				Events.crew_ready.emit(self)


func _draw() -> void:
	# Round badge with the crew type icon, drawn upright above the car.
	if not visible:
		return
	var s: float = _body.scale.x
	var c := Vector2(0, -26) * s
	draw_circle(c, 11.0 * s, type.colour)
	draw_circle(c, 11.0 * s, Color.WHITE, false, 2.0 * s)
	if type.icon:
		var r := Rect2(c - Vector2(8, 8) * s, Vector2(16, 16) * s)
		draw_texture_rect(type.icon, r, false, Color.WHITE)


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
	var from: Variant = RoadGraph.snap(global_position, 300.0)
	var to: Variant = RoadGraph.snap(station.global_position, 300.0)
	var path := PackedVector2Array([global_position])
	var edges := PackedInt32Array([-1])
	if from != null and to != null:
		var r = RoadGraph.route(from, to)
		path.append_array(r.points)
		edges.append_array(r.point_edges)
	path.append(station.global_position)
	edges.append(-1)
	_follow(path, edges)
	_set_state(State.RETURNING)


func status_text() -> String:
	match state:
		State.COOLDOWN:
			return "Cooldown %ds" % ceili(_cooldown)
		State.EN_ROUTE, State.RETURNING:
			var e := _edges[mini(_index, _edges.size() - 1)] if not _edges.is_empty() else -1
			var road := RoadGraph.edge_name[e] if e >= 0 else ""
			return "%s%s" % [STATE_NAMES[state], (" - " + road) if road != "" else ""]
	return STATE_NAMES[state]


# --- Movement ------------------------------------------------------------------

func _follow(points: PackedVector2Array, edges: PackedInt32Array) -> void:
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
	var target := _points[_index]
	var to_target := target - global_position
	if to_target.length() > 0.01:
		_body.rotation = to_target.angle()

	var speed := type.speed_mps * float(Stage.meta["px_per_m"])
	var edge := _edges[_index]
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
