class_name CrewView
extends Node2D

var crew: Node2D
var heading := 0.0
var route := PackedVector2Array()

func setup(crew_logic: Node2D) -> void:
	crew = crew_logic
	queue_redraw()

func set_heading(angle: float) -> void:
	heading = angle
	queue_redraw()

func set_route(points: PackedVector2Array) -> void:
	route = points
	queue_redraw()

func clear_route() -> void:
	route.clear()
	queue_redraw()

func vehicle_rotation() -> float:
	return heading

func vehicle_scale() -> float:
	return 1.0

func _draw() -> void:
	if crew == null or crew.type == null:
		return

	if route.size() > 1:
		var local_route := PackedVector2Array()
		for point in route:
			local_route.append(to_local(point))
		draw_polyline(local_route, crew.type.colour, 2.0)

	draw_circle(Vector2.ZERO, 14.0, crew.type.colour)
	draw_circle(Vector2.ZERO, 14.0, Color.WHITE, false, 2.0)

	if crew.type.icon:
		draw_texture_rect(
			crew.type.icon,
			Rect2(Vector2(-9, -9), Vector2(18, 18)),
			false
		)

	if crew.is_blocked():
		draw_arc(
			Vector2.ZERO,
			20.0,
			-PI / 2.0,
			-PI / 2.0 + TAU * crew.patience_left(),
			32,
			Color.RED,
			3.0
		)
