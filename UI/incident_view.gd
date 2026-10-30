class_name IncidentView
extends Node2D

# These status values match Incident.Status.
# This view avoids referencing the Incident global class directly.
enum Status { REPORTED, ASSIGNED, ON_SCENE, RESOLVED, FAILED }

const RING_START := Color("f5a623")
const RING_END := Color("d62828")

var incident


func setup(incident_logic) -> void:
	incident = incident_logic


func _draw() -> void:
	if incident == null:
		return

	if incident.status == Status.FAILED:
		draw_circle(Vector2.ZERO, 15.0, Color(0.45, 0.45, 0.45))
		draw_circle(Vector2.ZERO, 15.0, Color.WHITE, false, 2.5)

		# Arrow out: handed to a neighbouring crew.
		draw_line(Vector2(-7, 0), Vector2(7, 0), Color("ffb347"), 4.0)
		draw_line(Vector2(2, -5), Vector2(7, 0), Color("ffb347"), 4.0)
		draw_line(Vector2(2, 5), Vector2(7, 0), Color("ffb347"), 4.0)

		var font := ThemeDB.fallback_font
		draw_string_outline(
			font,
			Vector2(-34, 34),
			"Passed on",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			4,
			Color.WHITE
		)
		draw_string(
			font,
			Vector2(-34, 34),
			"Passed on",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			15,
			Color("c46a00")
		)
		return

	var colour: Color = incident.crew_type.colour if incident.crew_type else Color.RED
	var waiting: bool = (
		incident.status == Status.REPORTED
		or incident.status == Status.ASSIGNED
	)
	var beat: float = 0.5 + 0.5 * sin(incident.pulse_phase()) if waiting else 0.0
	var size: float = 1.0 + 0.12 * beat * (0.5 + incident.timer())

	if incident.status == Status.REPORTED:
		draw_circle(
			Vector2.ZERO,
			(18.0 + 14.0 * beat) * size,
			Color(colour, 0.28 * (1.0 - beat))
		)

	# Timer ring.
	var ring_radius := 21.0 * size
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0,
		TAU,
		48,
		Color(0, 0, 0, 0.25),
		5.0
	)

	if incident.timer() > 0.0:
		draw_arc(
			Vector2.ZERO,
			ring_radius,
			-PI / 2,
			-PI / 2 + TAU * incident.timer(),
			48,
			RING_START.lerp(RING_END, incident.timer()),
			5.0
		)

	if incident.selected:
		draw_arc(
			Vector2.ZERO,
			ring_radius + 5.0,
			0,
			TAU,
			48,
			Color.WHITE,
			3.0
		)

	draw_circle(Vector2.ZERO, 15.0 * size, colour)
	draw_circle(Vector2.ZERO, 15.0 * size, Color.WHITE, false, 2.5)

	if incident.crew_type and incident.crew_type.icon:
		draw_texture_rect(
			incident.crew_type.icon,
			Rect2(Vector2(-10, -10) * size, Vector2(20, 20) * size),
			false
		)

	if (
		incident.status == Status.ON_SCENE
		or incident.status == Status.RESOLVED
	):
		draw_arc(
			Vector2.ZERO,
			11.0,
			-PI / 2,
			-PI / 2 + TAU * incident.progress,
			32,
			Color("2fbf71"),
			4.0
		)

	# Small badges for other required crew types.
	for i in range(1, incident.needed_types.size()):
		var crew_type = incident.needed_types[i]
		var badge_position := Vector2(-8.0 + (i - 1) * 18.0, 30.0)
		var crew_is_here: bool = incident.on_scene.any(
			func(c): return c.type.id == crew_type.id
		)

		draw_circle(badge_position, 8.0, crew_type.colour)
		draw_circle(badge_position, 8.0, Color.WHITE, false, 1.5)

		if crew_type.icon:
			draw_texture_rect(
				crew_type.icon,
				Rect2(
					badge_position - Vector2(5.5, 5.5),
					Vector2(11, 11)
				),
				false
			)

		if crew_is_here:
			draw_circle(
				badge_position + Vector2(6, -6),
				4.0,
				Color("2fbf71")
			)
