extends Node2D
## Effects: particle feedback on the map, driven only by Events (nothing
## calls it). Looping fire/rain on incidents whose IncidentType asks for it,
## bursts when a call is resolved or passed on, when a crew arrives, and
## when a crew runs into an obstacle. Bursts are scaled with the zoom like
## the incident pins, so they read at any distance.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Add an Effects node to main.tscn that listens to Events and uses Fx:
#    on incident_spawned attach the type's ambient_fx (fire, rain) behind
#    the incident pin, and stop it when the incident ends; resolved ->
#    'resolved' burst; failed (passed on) -> 'passed_on' puff; crew_arrived
#    -> 'arrive' ring; crew_blocked -> 'alert' sparks at the crew. Scale
#    bursts by 1/zoom clamped like the pins (0.6 to 4.5)."


func _ready() -> void:
	Events.incident_spawned.connect(_on_incident_spawned)
	Events.incident_resolved.connect(func(i: Node2D) -> void:
		_stop_ambient(i)
		_burst(i.global_position, &"resolved"))
	Events.incident_failed.connect(func(i: Node2D) -> void:
		_stop_ambient(i)
		_burst(i.global_position, &"passed_on"))
	Events.crew_arrived.connect(func(c: Node2D, _i: Node) -> void: _burst(c.global_position, &"arrive"))
	Events.crew_blocked.connect(func(c: Node2D, _e: int) -> void: _burst(c.global_position, &"alert"))


func _on_incident_spawned(inc: Node2D) -> void:
	var kind: StringName = inc.type.ambient_fx
	if kind == &"":
		return
	var p := Fx.ambient(kind)
	if p:
		p.name = "AmbientFx"
		p.show_behind_parent = true      # flames under the pin, not over its icon
		inc.add_child(p)


func _stop_ambient(inc: Node) -> void:
	var p := inc.get_node_or_null("AmbientFx") as CPUParticles2D
	if p:
		p.emitting = false


func _burst(pos: Vector2, kind: StringName) -> void:
	var cam := get_viewport().get_camera_2d()
	var s := clampf(1.0 / cam.zoom.x, 0.6, 4.5) if cam else 1.0
	Fx.burst(self, pos, kind, s)
