class_name Camberwell extends Node2D

@onready var Map = $Map
@onready var Location = $Locations
const Location_IDS = [5,11,20,43,51]

const MIN_LONGITUDE = 145.056520
const MAX_LONGITUDE = 145.091800

const MIN_LATITUDE = -37.846020
const MAX_LATITUDE = -37.821410

const MAP_MARGIN = 42.0

func _ready():
	load_locations()
	
func geo_to_map_position(longitude: float, latitude: float) -> Vector2:
	var map_size = Map.texture.get_size()

	var usable_width = map_size.x - MAP_MARGIN * 2.0
	var usable_height = map_size.y - MAP_MARGIN * 2.0

	var x_ratio = (
		longitude - MIN_LONGITUDE
	) / (
		MAX_LONGITUDE - MIN_LONGITUDE
	)

	var y_ratio = (MAX_LATITUDE - latitude) / (MAX_LATITUDE - MIN_LATITUDE)

	return Vector2(
		MAP_MARGIN + x_ratio * usable_width,
		MAP_MARGIN + y_ratio * usable_height
	)
	
func load_locations():
	var file = FileAccess.open(
		"res://Map/boroondara_foi_game_data.json",
		FileAccess.READ
	)

	if file == null:
		push_error("Could not open location JSON")
		return

	var data = JSON.parse_string(file.get_as_text())

	if data == null:
		push_error("Could not parse JSON")
		return

	for feature in data["features"]:

		var id = int(feature["id"])

		if id in Location_IDS:
			create_location(feature)

func create_location(feature):
	var marker = Node2D.new()

	marker.name = str(feature["name"])

	marker.position = geo_to_map_position(
		float(feature["longitude"]),
		float(feature["latitude"])
	)

	Location.add_child(marker)

	var label = Label.new()

	label.text = "●"
	label.position = Vector2(-20, -35)
