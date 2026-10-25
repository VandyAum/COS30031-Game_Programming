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
var _view: StationView


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
	_view = StationView.new()
	_view.setup(self)
	add_child(_view)
	Events.stage_changed.connect(func(_s: int) -> void: redraw_view())
	Events.crew_state_changed.connect(func(_c: Node) -> void: redraw_view())
	Events.crew_selected.connect(func(c: Node) -> void:
		highlighted = c != null and (c as Crew).station == self
		redraw_view()
	)


func redraw_view() -> void:
	if _view:
		_view.refresh()


func is_playable() -> bool:
	return Stage.is_playable(global_position)


func available_crews() -> Array[Crew]:
	return crews.filter(func(c: Crew) -> bool: return c.is_available())


func first_available() -> Crew:
	var a := available_crews()
	return a[0] if not a.is_empty() else null
