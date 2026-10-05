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

var current_level: int = 1
var n_was_pressed: bool = false

@onready var camberwell = $MapChunk/Camberwell
@onready var hawthorn = $MapChunk/Hawthorn_EastMap
@onready var surrey = $MapChunk/Surrey_Hill


func _ready() -> void:
	print("GAME STARTED")
	set_level(1)


func _process(_delta: float) -> void:
	var n_pressed := Input.is_key_pressed(KEY_N)

	# Only trigger once per key press
	if n_pressed and not n_was_pressed:

		if current_level == 1:
			complete_level_1()

		elif current_level == 2:
			complete_level_2()

	n_was_pressed = n_pressed


func set_level(level: int) -> void:
	current_level = level

	# Hide all maps
	camberwell.visible = false
	hawthorn.visible = false
	surrey.visible = false

	# LEVEL 1
	if current_level == 1:
		camberwell.visible = true
		print("LEVEL 1 - CAMBERWELL")

	# LEVEL 2
	elif current_level == 2:
		hawthorn.visible = true
		print("LEVEL 2 - HAWTHORN EAST")

	# LEVEL 3
	elif current_level == 3:
		surrey.visible = true
		print("LEVEL 3 - SURREY HILL")


func complete_level_1() -> void:
	if current_level != 1:
		return

	print("LEVEL 1 COMPLETE")
	set_level(2)


func complete_level_2() -> void:
	if current_level != 2:
		return

	print("LEVEL 2 COMPLETE")
	set_level(3)


func complete_level_3() -> void:
	if current_level != 3:
		return

	print("LEVEL 3 COMPLETE")
	print("GAME COMPLETE")


func fail_incident() -> void:
	print("INCIDENT FAILED")
