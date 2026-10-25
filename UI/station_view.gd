class_name StationView
extends Node2D

var station
@export var crew_type: CrewType
@export var station_name := ""
@export var available_crews := 0

func _draw() -> void:
	if crew_type == null:
		return

	var box := Rect2(-14, -14, 28, 28)
	draw_rect(box, crew_type.colour)
	draw_rect(box, Color.WHITE, false, 2.0)

	if crew_type.icon:
		draw_texture_rect(crew_type.icon, box.grow(-5), false)

	var badge := Vector2(13, -13)
	draw_circle(badge, 8.0, Color("2b2f36"))
	draw_string(
		ThemeDB.fallback_font,
		badge + Vector2(-4, 5),
		str(available_crews),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-40, 34),
		station_name
	)
	var station

func setup(station_logic: Node2D) -> void:
	station = station_logic
	refresh()

func refresh() -> void:
	if station == null:
		return
	crew_type = station.type
	station_name = station.station_name
	available_crews = station.available_crews().size()
	queue_redraw()
