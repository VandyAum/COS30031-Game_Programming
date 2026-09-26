extends Node2D

@onready var Camberwell = $Camberwell


func _ready():
    fit_map_to_screen()


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
