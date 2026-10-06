class_name Station extends Node2D
## A crew base at a real Feature of Interest (police / ambulance / fire
## station). Owns its crews. Drawn as a rounded square in the crew type's
## colour with the type icon and a badge showing how many crews are home.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Station node for the dispatch game, replacing the
#    generic Crew_Points markers: it is placed at a Feature of Interest from
#    Map/world/foi.json, has a CrewType and a display name, creates its
#    starting crews (CrewType.crews_per_station, using the Crew class) and
#    can return its available crews. Draw it as a marker that stays a
#    readable size at any zoom: a rounded square in the type colour with the
#    white type icon, a small badge with the number of crews currently
#    available (grey when none), and a highlight ring when it is the station
#    of the crew the player has selected. Only stations inside the current
#    Stage can be used."

var type: CrewType
var station_name := ""
var crews: Array[Crew] = []
var highlighted := false


func setup(crew_type: CrewType, display_name: String, pos: Vector2, crews_parent: Node, first_number: int) -> void:
	type = crew_type
	station_name = display_name
	name = display_name.replace(" ", "")
	position = pos
	add_to_group("stations")
	for i in type.crews_per_station:
		var crew := Crew.new()
		crew.setup(type, self, first_number + i)
		crews.append(crew)
		crews_parent.add_child.call_deferred(crew)


func _ready() -> void:
	Events.crew_state_changed.connect(func(_c: Node) -> void: queue_redraw())
	Events.crew_selected.connect(func(c: Node) -> void:
		highlighted = c != null and (c as Crew).station == self
		queue_redraw())


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var s := clampf(1.0 / cam.zoom.x, 0.6, 1.8)
		if not is_equal_approx(scale.x, s):
			scale = Vector2(s, s)


func is_playable() -> bool:
	return Stage.is_playable(global_position)


func available_crews() -> Array[Crew]:
	return crews.filter(func(c: Crew) -> bool: return c.is_available())


func first_available() -> Crew:
	var a := available_crews()
	return a[0] if not a.is_empty() else null


func _draw() -> void:
	var r := Rect2(-14, -14, 28, 28)
	if highlighted:
		draw_rect(r.grow(5), Color.WHITE, false, 3.0)
	var box := StyleBoxFlat.new()
	box.bg_color = type.colour
	box.set_corner_radius_all(6)
	box.border_color = Color.WHITE
	box.set_border_width_all(2)
	draw_style_box(box, r)
	if type.icon:
		draw_texture_rect(type.icon, r.grow(-5), false)
	var n := available_crews().size()
	var badge := Vector2(13, -13)
	draw_circle(badge, 8.0, Color("2b2f36") if n > 0 else Color(0.5, 0.5, 0.5))
	var font := ThemeDB.fallback_font
	draw_string(font, badge + Vector2(-4, 5), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
