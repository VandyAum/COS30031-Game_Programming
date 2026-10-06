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
# Follow-up prompt: "The area each station reveals doesn't read clearly.
#    Draw a dashed line around the perimeter of the station's visibility
#    radius while the station is in play."
# Follow-up prompt: "Make the station's dashed outline march slowly round
#    like the crews' do (same speed), to show the station is actively
#    watching its area."
# Follow-up prompt (legible from a distance): "Keep the station marker the
#    same size on screen when zoomed far out (scale up to 4.5x) and show the
#    station's name under it, white-outlined like the landmark labels."
# Follow-up prompt: "Show countdown dials on the station for crews on
#    cooldown: a ring around the marker that empties as the crew gets ready
#    (one ring per resting crew)."

var type: CrewType
var station_name := ""
var crews: Array[Crew] = []
var highlighted := false
## World-px radius of the area this station reveals (set by StationManager).
var reveal_radius := 0.0


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
	Events.stage_changed.connect(func(_s: int) -> void: queue_redraw())
	Events.crew_state_changed.connect(func(_c: Node) -> void: queue_redraw())
	Events.crew_selected.connect(func(c: Node) -> void:
		highlighted = c != null and (c as Crew).station == self
		queue_redraw())


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var s := clampf(1.0 / cam.zoom.x, 0.6, 4.5)
		if not is_equal_approx(scale.x, s):
			scale = Vector2(s, s)
	if reveal_radius > 0.0 and is_playable():
		queue_redraw()      # marching outline


func is_playable() -> bool:
	return Stage.is_playable(global_position)


func available_crews() -> Array[Crew]:
	return crews.filter(func(c: Crew) -> bool: return c.is_available())


func first_available() -> Crew:
	var a := available_crews()
	return a[0] if not a.is_empty() else null


func _draw() -> void:
	if reveal_radius > 0.0 and is_playable():
		# Our node is scaled for a constant marker size; undo that for the circle.
		# Same marching speed (world px/s) as the crews' outlines.
		DrawUtil.dashed_circle(self, Vector2.ZERO, reveal_radius / scale.x, Color(type.colour, 0.55),
			2.0, 9.0, Knowledge.clock * 12.0 / scale.x)
	var r := Rect2(-14, -14, 28, 28)
	if highlighted:
		draw_rect(r.grow(5), Color.WHITE, false, 3.0)
	# Cooldown dials: one ring per resting crew, emptying as it gets ready.
	var ring := 0
	for c in crews:
		var left := c.cooldown_left()
		if left <= 0.0:
			continue
		var rr := 23.0 + ring * 7.0
		draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color.WHITE, 8.0)
		draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color(0, 0, 0, 0.25), 5.0)
		draw_arc(Vector2.ZERO, rr, -PI / 2, -PI / 2 + TAU * left, 40, type.colour, 5.0)
		ring += 1
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
	var w := font.get_string_size(station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string_outline(font, Vector2(-w / 2.0, 34), station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(1, 1, 1, 0.92))
	draw_string(font, Vector2(-w / 2.0, 34), station_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, type.colour.darkened(0.35))
