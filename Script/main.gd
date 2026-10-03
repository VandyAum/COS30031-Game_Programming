class_name main extends Node2D

@onready var map_chunks = $MapChunks

@onready var camberwell = $MapChunk/Camberwell
@onready var camberwell_map = $MapChunk/Camberwell/Map

@onready var Draw = $Draw

var test_var: String = "hello"

func _ready():
	test_var = "hellooo"
	fit_maps_to_screen()


# This is just for the map to fit in the screen for now
func fit_maps_to_screen():
	var screen_size = get_viewport_rect().size

	var camberwell_size = camberwell_map.texture.get_size()

	var camberwell_rect = Rect2(
		camberwell.position,
		camberwell_size
	)

	

	var world_rect = camberwell_rect

	var scale_x = screen_size.x / world_rect.size.x
	var scale_y = screen_size.y / world_rect.size.y

	var map_scale = min(scale_x, scale_y)

	camberwell.scale = Vector2(map_scale, map_scale)

func get_test() -> String:
	return test_var
