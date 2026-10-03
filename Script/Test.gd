extends Node2D

@onready var line = $Line
@onready var main = $".."

# This is how you create a variable so you can access var and func from other scene
@export var main3 : main
@export var main2 : Node2D
@export var camberwell : Camberwell


@onready var crew = crew_scene.instantiate()
var crew_scene = preload("res://police_crew.tscn")

var crew_spawned := false
var is_drawing := true

var path_index := 1
var is_following_path := false



@export var crew_speed := 200.0

var test_var: String

func _ready() -> void:
	pass

func _process(delta: float) -> void:	
	if is_drawing:	
		drawing()
	if is_following_path:
		move_crew(delta)
	if Input.is_action_just_pressed("Clear_Draw"):
		line.clear_points()
		crew.queue_free()
		crew_spawned = false
		crew = crew_scene.instantiate()
		is_drawing = true

func drawing():
	
	if Input.is_action_just_pressed("Draw"):
#		add 2 lines here because inorder for the line to show when we firt draw
# 		we need to get line.points.size()-1 without 2 lines you would not be able to see the line
#		on the first line drawn
		
		if(line.points.size() == 0):
			line.add_point(get_local_mouse_position())
			line.add_point(get_local_mouse_position())
			print(line.points.size())
		else:
			line.add_point(get_local_mouse_position())
		
	if line.points.size() > 0:	
		if !crew_spawned:
			add_child(crew)
			crew.position = line.points[0]
			crew_spawned = true
#	This is the code that show the line
	if line.points.size() > 0:
		line.set_point_position(line.points.size()-1, get_local_mouse_position())
			
	if Input.is_action_just_pressed("Undo_Drawing"):
		if line.points.size() > 2:
			line.remove_point(line.points.size() - 1)
	
	if Input.is_action_just_pressed("Stop_Draw"):
		is_drawing = false
		if line.points.size() > 1:
			path_index = 1
			is_following_path = true
			
func move_crew(delta):
	if path_index >= line.points.size():
		is_following_path = false
		return

	var target_position = line.points[path_index]
	var direction = target_position - crew.position
	crew.rotation = direction.angle()

	crew.position = crew.position.move_toward(
		target_position,
		crew_speed * delta
	)
	if crew.position.distance_to(target_position) < 5:
		path_index += 1
		
		
