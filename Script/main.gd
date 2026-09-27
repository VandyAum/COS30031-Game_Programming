#extends Node2D
#
#@onready var camberwell = $Camberwell
#@onready var camberwell_map = $Camberwell/Map
#
#@onready var Canterbury = $Canterbury
#@onready var canterbury_map = $Canterbury/Map
#
#
#func _ready():
    #fit_map_to_screen()
#
#
#func fit_map_to_screen():
    #var screen_size = get_viewport_rect().size
    #
    #var camberwell_size = camberwell_map.texture.get_size()
    #var canterbury_size = canterbury_map.texture.get_size()
    #
    #
    #var scale_x = screen_size.x / map_size.x
    #var scale_y = screen_size.y / map_size.y
#
    #var map_scale = min(scale_x, scale_y)
#
    #camberwell.scale = Vector2(
        #map_scale,
        #map_scale
    #)
#
    #var scaled_map_size = map_size * map_scale
#
    #camberwell.position = Vector2(
        #(screen_size.x - scaled_map_size.x) / 2.0,
        #(screen_size.y - scaled_map_size.y) / 2.0
    #)
    
extends Node2D
@onready var map_chunks = $MapChunks

@onready var camberwell = $MapChunk/Camberwell
@onready var camberwell_map = $MapChunk/Camberwell/Map

@onready var canterbury = $MapChunk/Canterbury
@onready var canterbury_map = $MapChunk/Canterbury/Map


func _ready():
    fit_maps_to_screen()


# This is just for the map to fit in the screen for now
func fit_maps_to_screen():
    var screen_size = get_viewport_rect().size

    var camberwell_size = camberwell_map.texture.get_size()
    var canterbury_size = canterbury_map.texture.get_size()

    var camberwell_rect = Rect2(
        camberwell.position,
        camberwell_size
    )

    var canterbury_rect = Rect2(
        canterbury.position,
        canterbury_size
    )

    var world_rect = camberwell_rect.merge(canterbury_rect)

    var scale_x = screen_size.x / world_rect.size.x
    var scale_y = screen_size.y / world_rect.size.y

    var map_scale = min(scale_x, scale_y)

    camberwell.scale = Vector2(map_scale, map_scale)
    canterbury.scale = Vector2(map_scale, map_scale)
