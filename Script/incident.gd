class_name Incident extends Node2D
## One live incident on the map. Status:
##   REPORTED -> ASSIGNED (a crew is on the way) -> ON_SCENE (resolve timer)
##   -> RESOLVED. A wrong crew type arriving sends it back to REPORTED.
## Drawn as a pin in the needed crew type's colour; pulses while nobody is
## assigned, shows a ring when selected and a progress arc while on scene.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Incident node for the dispatch game, replacing the
#    old End_Points markers. It is created from an IncidentType resource
#    with a place name (road or landmark) and a caller description. It
#    tracks its status (REPORTED, ASSIGNED, ON_SCENE, RESOLVED) and the crew
#    assigned. crew_arrived(crew) returns false if that crew type isn't one
#    the incident needs (status goes back to REPORTED with a 'wrong crew'
#    note, matching the spec's 'wrong team sent' consequence) and otherwise
#    runs the type's resolve timer, then emits Events.incident_resolved,
#    sends the crew home and fades out. Draw it so it stays readable at any
#    zoom: a round pin with the crew type colour and icon, a soft pulsing
#    ring while unassigned, a white selection ring, and a progress arc while
#    the crew is on scene. Emit Events.incident_updated on every change for
#    the incidents panel."
# Follow-up prompt (milestone 2): "Road incidents that block their road call
#    World.block() on spawn and World.unblock() when resolved. Add unassign()
#    for when the player redirects the crew elsewhere, and make status_text()
#    say when the assigned crew is stuck at a blockage."

enum Status { REPORTED, ASSIGNED, ON_SCENE, RESOLVED }
const STATUS_NAMES := ["Reported", "Crew en route", "Crew on scene", "Resolved"]

var type: IncidentType
var crew_type: CrewType        # primary crew type needed (for colour/icon)
var place := ""
var description := ""
var status := Status.REPORTED
var crew: Crew = null
var note := ""                 # e.g. wrong crew sent
var selected := false
var progress := 0.0            # 0..1 while on scene
var reported_at := 0.0
var road_edge := -1            # for ROAD incidents: the road it is on

var _pulse := 0.0
var _fade := 1.0


func setup(t: IncidentType, ct: CrewType, pos: Vector2, place_name: String, edge := -1) -> void:
	type = t
	road_edge = edge
	crew_type = ct
	position = pos
	place = place_name
	description = t.descriptions.pick_random().replace("{place}", place_name)
	reported_at = Knowledge.clock
	add_to_group("incidents")
	if t.blocks_road and edge >= 0:
		World.block(edge, t.display_name, self)


func title() -> String:
	return type.display_name


func status_text() -> String:
	var s: String = STATUS_NAMES[status]
	if crew and status == Status.ASSIGNED and crew.state == Crew.State.BLOCKED:
		return "%s %s" % [crew.callsign, crew.status_text()]
	if crew and status in [Status.ASSIGNED, Status.ON_SCENE]:
		s += " (%s)" % crew.callsign
	if note != "" and status == Status.REPORTED:
		s += " - " + note
	return s


func is_open() -> bool:
	return status == Status.REPORTED


func assign(c: Crew) -> void:
	crew = c
	note = ""
	status = Status.ASSIGNED
	Events.incident_updated.emit(self)


func unassign() -> void:
	crew = null
	status = Status.REPORTED
	Events.incident_updated.emit(self)


func is_crew_blocked() -> bool:
	return crew != null and status == Status.ASSIGNED and crew.state == Crew.State.BLOCKED


## Returns true if this crew can work the incident.
func crew_arrived(c: Crew) -> bool:
	if status == Status.RESOLVED:
		return false
	if not type.needs(c.type.id):
		crew = null
		status = Status.REPORTED
		note = "Wrong crew: needs %s" % crew_type.display_name
		Events.incident_updated.emit(self)
		return false
	crew = c
	status = Status.ON_SCENE
	progress = 0.0
	Events.incident_updated.emit(self)
	return true


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		scale = Vector2.ONE * clampf(1.0 / cam.zoom.x, 0.6, 1.8)
	_pulse = fmod(_pulse + delta, 1.6)

	if status == Status.ON_SCENE:
		progress += delta / type.resolve_seconds
		if progress >= 1.0:
			_resolve()
	elif status == Status.RESOLVED:
		_fade -= delta * 1.5
		modulate.a = maxf(_fade, 0.0)
		if _fade <= 0.0:
			queue_free()
	queue_redraw()


func _resolve() -> void:
	status = Status.RESOLVED
	progress = 1.0
	if road_edge >= 0 and World.blocked_by(road_edge) == self:
		World.unblock(road_edge)
	Events.incident_resolved.emit(self)
	Events.incident_updated.emit(self)
	if crew:
		crew.go_home()


func _draw() -> void:
	var colour := crew_type.colour if crew_type else Color.RED
	if status == Status.REPORTED:
		var t := _pulse / 1.6
		draw_circle(Vector2.ZERO, 16.0 + 18.0 * t, Color(colour, 0.35 * (1.0 - t)))
	if selected:
		draw_arc(Vector2.ZERO, 20.0, 0, TAU, 40, Color.WHITE, 4.0)
		draw_arc(Vector2.ZERO, 23.0, 0, TAU, 40, Color("2b2f36"), 2.0)
	draw_circle(Vector2.ZERO, 15.0, colour)
	draw_circle(Vector2.ZERO, 15.0, Color.WHITE, false, 2.5)
	if crew_type and crew_type.icon:
		draw_texture_rect(crew_type.icon, Rect2(-10, -10, 20, 20), false)
	if status == Status.ON_SCENE or status == Status.RESOLVED:
		draw_arc(Vector2.ZERO, 19.0, -PI / 2, -PI / 2 + TAU * progress, 40, Color("2fbf71"), 4.0)
