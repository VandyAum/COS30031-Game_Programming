class_name Incident extends Node2D
## One live incident on the map. Status:
##   REPORTED -> ASSIGNED (crews on the way / some on scene) -> ON_SCENE
##   (every needed crew type is there; resolve timer runs) -> RESOLVED
##   ...or FAILED if its timer ring fills first (costs a life).
## A wrong crew type arriving is sent home with a note.
##
## Timer ring: fills while unattended, at half speed while a crew is en
## route, and pauses once all needed crews are on scene.

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
# Follow-up prompt (milestone 3 - timer rings, failure, multi-crew):
#   "Rework the incident for milestone 3. (1) Several crews: an incident can
#    need more than one crew type (a car crash needs police AND an
#    ambulance). Track the assigned crews; it stays open for dispatch until
#    every needed type has a crew assigned; crews that arrive early wait on
#    scene; the resolve timer only runs once every needed type is on scene.
#    (2) Timer ring, using Jessie's 'elapsed active seconds' idea but with a
#    rate instead of a pause flag: elapsed += delta * rate, where rate is 1
#    while nobody is on the way, 0.5 while any crew is en route, and 0 once
#    all needed crews are on scene. Draw it as a ring around the pin that
#    fills from orange to red. (3) When it fills the incident FAILS: draw it
#    distinctly (grey pin, red cross, 'Failed'), emit Events.incident_failed,
#    cost a life through Run.lose_life, send its crews home and clear any
#    road it blocked, then fade out. (4) Mini Metro style urgency: the pin
#    pulses in size while waiting, faster as the ring fills. Show small icons
#    for the other crew types it needs, ticked when that crew is on scene."
# Follow-up prompt (all-ages tone): "Call a missed incident 'Passed on'
#    rather than 'Failed' on the map and in the panel, in amber instead of
#    red, and give Run a neutral reason (just what and where)."
# Follow-up prompt: "Keep the pin the same size on screen when zoomed far
#    out to a big stage (scale up to 4.5x instead of 1.8x)."
# Follow-up prompt (physics): "Give each incident a scene zone: an Area2D
#    (Scenes/incident_zone.tscn, layer 4 'incident_zones') with a radius
#    of scene_radius_m, kept at world scale while the pin scales with the
#    zoom. A crew whose sensor overlaps its incident's zone can park and
#    walk in. Stop it being detected once the incident is finished."
# Follow-up prompt (audio): "Emit Events.incident_urgent once when the
#    timer ring passes three-quarters."

enum Status { REPORTED, ASSIGNED, ON_SCENE, RESOLVED, FAILED }
const STATUS_NAMES := ["Reported", "Crew en route", "On scene", "Resolved", "Passed on"]
const RING_START := Color("f5a623")
const RING_END := Color("d62828")
const ZONE_SCENE := preload("res://Scenes/incident_zone.tscn")
## Timer share at which the call counts as urgent (one warning sound).
const URGENT_AT := 0.75

## Crews within this many metres can park and walk in (the scene zone).
@export var scene_radius_m := 60.0
## Area2D the crews' sensors detect (collision layer "incident_zones").
var zone: Area2D
var _warned := false

var type: IncidentType
var crew_type: CrewType              # primary crew type (pin colour/icon)
var needed_types: Array[CrewType] = []
var place := ""
var description := ""
var status := Status.REPORTED
var crews: Array[Crew] = []          # assigned (en route or on scene)
var on_scene: Array[Crew] = []
var note := ""                       # e.g. wrong crew sent
var selected := false
var progress := 0.0                  # resolve progress 0..1 (all crews on scene)
var elapsed_active := 0.0            # timer seconds used (Jessie's elapsedActiveSeconds)
var reported_at := 0.0
var road_edge := -1                  # for ROAD incidents: the road it is on

var _pulse := 0.0
var _fade := 1.0
var _linger := 0.0


func setup(t: IncidentType, types: Array[CrewType], pos: Vector2, place_name: String, edge := -1) -> void:
	type = t
	needed_types = types
	crew_type = types[0] if not types.is_empty() else null
	road_edge = edge
	position = pos
	place = place_name
	description = t.descriptions.pick_random().replace("{place}", place_name)
	reported_at = Knowledge.clock
	add_to_group("incidents")
	if t.blocks_road and edge >= 0:
		World.block(edge, t.display_name, self)


func _ready() -> void:
	zone = ZONE_SCENE.instantiate()
	zone.top_level = true            # world scale, not the pin's zoom scale
	var shape := CircleShape2D.new()
	shape.radius = scene_radius_m * float(Stage.meta["px_per_m"])
	(zone.get_node("Shape") as CollisionShape2D).shape = shape
	add_child(zone)
	zone.global_position = global_position


func title() -> String:
	return type.display_name


## 0..1 share of the time limit used.
func timer() -> float:
	return clampf(elapsed_active / type.time_limit_seconds, 0.0, 1.0)


## Crew type ids still needing a crew assigned.
func missing_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in needed_types:
		if not crews.any(func(c: Crew) -> bool: return c.type.id == t.id):
			out.append(t.id)
	return out


func is_open() -> bool:
	return (status == Status.REPORTED or status == Status.ASSIGNED) and not missing_types().is_empty()


func is_finished() -> bool:
	return status == Status.RESOLVED or status == Status.FAILED


func is_crew_blocked() -> bool:
	return crews.any(func(c: Crew) -> bool: return c.state == Crew.State.BLOCKED)


func status_text() -> String:
	if is_finished():
		return STATUS_NAMES[status]
	for c in crews:
		if c.state == Crew.State.BLOCKED:
			return "%s %s" % [c.callsign, c.status_text()]
	var parts: Array[String] = []
	for t in needed_types:
		var c: Crew = null
		for x in crews:
			if x.type.id == t.id:
				c = x
		if c == null:
			parts.append("needs " + t.display_name)
		elif on_scene.has(c):
			parts.append(c.callsign + " on scene")
		else:
			parts.append(c.callsign + " en route")
	var s := ", ".join(parts)
	if note != "":
		s += " - " + note
	return s[0].to_upper() + s.substr(1)


func assign(c: Crew) -> void:
	if not crews.has(c):
		crews.append(c)
	note = ""
	if status == Status.REPORTED:
		status = Status.ASSIGNED
	Events.incident_updated.emit(self)


func unassign(c: Crew) -> void:
	crews.erase(c)
	on_scene.erase(c)
	if crews.is_empty() and status == Status.ASSIGNED:
		status = Status.REPORTED
	Events.incident_updated.emit(self)


## Returns true if this crew stays to work the incident.
func crew_arrived(c: Crew) -> bool:
	if is_finished():
		return false
	var already := on_scene.any(func(x: Crew) -> bool: return x.type.id == c.type.id)
	if not type.needs(c.type.id) or already:
		crews.erase(c)
		if crews.is_empty():
			status = Status.REPORTED
		note = "Wrong crew: needs %s" % ", ".join(needed_types.map(func(t: CrewType) -> String: return t.display_name))
		Events.incident_updated.emit(self)
		return false
	on_scene.append(c)
	if _all_on_scene():
		status = Status.ON_SCENE
		progress = 0.0
	Events.incident_updated.emit(self)
	return true


func _all_on_scene() -> bool:
	for t in needed_types:
		if not on_scene.any(func(c: Crew) -> bool: return c.type.id == t.id):
			return false
	return true


func _timer_rate() -> float:
	if status == Status.ON_SCENE:
		return 0.0                    # everyone is here: paused
	if not crews.is_empty():
		return 0.5                    # help is on the way: slowed
	return 1.0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		scale = Vector2.ONE * clampf(1.0 / cam.zoom.x, 0.6, 4.5)

	match status:
		Status.REPORTED, Status.ASSIGNED:
			elapsed_active += delta * _timer_rate()
			# Pulse faster as the ring fills.
			_pulse += delta * lerpf(2.5, 9.0, timer())
			if timer() >= URGENT_AT and not _warned:
				_warned = true
				Events.incident_urgent.emit(self)
			if timer() >= 1.0:
				fail("%s on %s" % [type.display_name.to_lower(), place])
		Status.ON_SCENE:
			progress += delta / type.resolve_seconds
			if progress >= 1.0:
				_resolve()
		Status.RESOLVED, Status.FAILED:
			_linger += delta
			if _linger > (3.0 if status == Status.FAILED else 0.3):
				_fade -= delta * 1.5
				modulate.a = maxf(_fade, 0.0)
				if _fade <= 0.0:
					queue_free()
	queue_redraw()


func _resolve() -> void:
	status = Status.RESOLVED
	progress = 1.0
	_clear_road()
	Events.incident_resolved.emit(self)
	Events.incident_updated.emit(self)
	_send_crews_home()


## The incident is lost: costs a life.
func fail(reason: String) -> void:
	if is_finished():
		return
	status = Status.FAILED
	_clear_road()
	Events.incident_failed.emit(self)
	Events.incident_updated.emit(self)
	_send_crews_home()
	Run.lose_life(reason)


func _clear_road() -> void:
	if zone:
		zone.set_deferred("monitorable", false)    # no longer a scene to walk into
	if road_edge >= 0 and World.blocked_by(road_edge) == self:
		World.unblock(road_edge)


func _send_crews_home() -> void:
	var all := crews.duplicate()
	crews.clear()
	on_scene.clear()
	for c in all:
		if is_instance_valid(c) and c.incident == self:
			c.go_home()


func _draw() -> void:
	if status == Status.FAILED:
		draw_circle(Vector2.ZERO, 15.0, Color(0.45, 0.45, 0.45))
		draw_circle(Vector2.ZERO, 15.0, Color.WHITE, false, 2.5)
		# Arrow out: handed to a neighbouring crew.
		draw_line(Vector2(-7, 0), Vector2(7, 0), Color("ffb347"), 4.0)
		draw_line(Vector2(2, -5), Vector2(7, 0), Color("ffb347"), 4.0)
		draw_line(Vector2(2, 5), Vector2(7, 0), Color("ffb347"), 4.0)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-34, 34), "Passed on", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.WHITE)
		draw_string(font, Vector2(-34, 34), "Passed on", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("c46a00"))
		return

	var colour := crew_type.colour if crew_type else Color.RED
	var waiting := status == Status.REPORTED or status == Status.ASSIGNED
	# Mini Metro style: pulse in size (and a soft halo) while waiting.
	var beat := 0.5 + 0.5 * sin(_pulse) if waiting else 0.0
	var size := 1.0 + 0.12 * beat * (0.5 + timer())
	if status == Status.REPORTED:
		draw_circle(Vector2.ZERO, (18.0 + 14.0 * beat) * size, Color(colour, 0.28 * (1.0 - beat)))

	# Timer ring: background track, then the used share from orange to red.
	var ring_r := 21.0 * size
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 48, Color(0, 0, 0, 0.25), 5.0)
	if timer() > 0.0:
		draw_arc(Vector2.ZERO, ring_r, -PI / 2, -PI / 2 + TAU * timer(), 48, RING_START.lerp(RING_END, timer()), 5.0)
	if selected:
		draw_arc(Vector2.ZERO, ring_r + 5.0, 0, TAU, 48, Color.WHITE, 3.0)

	draw_circle(Vector2.ZERO, 15.0 * size, colour)
	draw_circle(Vector2.ZERO, 15.0 * size, Color.WHITE, false, 2.5)
	if crew_type and crew_type.icon:
		draw_texture_rect(crew_type.icon, Rect2(Vector2(-10, -10) * size, Vector2(20, 20) * size), false)
	if status == Status.ON_SCENE or status == Status.RESOLVED:
		draw_arc(Vector2.ZERO, 11.0, -PI / 2, -PI / 2 + TAU * progress, 32, Color("2fbf71"), 4.0)

	# Other crew types needed: small badges below, ticked once on scene.
	for i in range(1, needed_types.size()):
		var t := needed_types[i]
		var p := Vector2(-8.0 + (i - 1) * 18.0, 30.0)
		var here := on_scene.any(func(c: Crew) -> bool: return c.type.id == t.id)
		draw_circle(p, 8.0, t.colour)
		draw_circle(p, 8.0, Color.WHITE, false, 1.5)
		if t.icon:
			draw_texture_rect(t.icon, Rect2(p - Vector2(5.5, 5.5), Vector2(11, 11)), false)
		if here:
			draw_circle(p + Vector2(6, -6), 4.0, Color("2fbf71"))
