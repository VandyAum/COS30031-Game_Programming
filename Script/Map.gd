extends Node2D

@onready var Camberwell = $Camberwell
@onready var Location = $Locations

const Location_IDS = [5,11,20,43,51]

const MIN_LONGITUDE = 145.056520
const MAX_LONGITUDE = 145.091800

const MIN_LATITUDE = -37.846020
const MAX_LATITUDE = -37.821410

const MAP_MARGIN = 42.0

func _ready():
    fit_map_to_screen()
    load_locations()

func fit_map_to_screen():
    var screen_size = get_viewport_rect().size
    var map_size = Camberwell.texture.get_size()

    var scale_x = screen_size.x / map_size.x
    var scale_y = screen_size.y / map_size.y

    var map_scale = min(scale_x, scale_y)

    scale = Vector2(map_scale, map_scale)

    var scaled_map_size = map_size * map_scale

    position = Vector2(
        (screen_size.x - scaled_map_size.x) / 2.0,
        (screen_size.y - scaled_map_size.y) / 2.0
    )
    
func geo_to_map_position(longitude: float, latitude: float) -> Vector2:
    var map_size = Camberwell.texture.get_size()

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

    marker.z_index = 100

    Location.add_child(marker)

    var label = Label.new()

    label.text = "● %s" % marker.name
    label.position = Vector2(-20, -35)
    label.add_theme_font_size_override("font_size", 70)
    label.add_theme_color_override("font_color", Color.RED)

    marker.add_child(label)
