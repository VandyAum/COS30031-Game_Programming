extends Node2D

@onready var line = $Line
@onready var main = $".."

@export var main2 : Node2D
@export var camberwell : Camberwell


@onready var crew = crew_scene.instantiate()
var crew_scene = preload("res://police_crew.tscn")
@onready var isDraw = false

var crew_spawned := false
var is_drawing := true

var test_var: String

func _ready() -> void:
	test_var = main2.get_test()
	camberwell.test()
	print(test_var)
	pass

func _process(delta: float) -> void:	
	if is_drawing:	
		drawing()
	#print(get_parent().name)

func drawing():
	
	if Input.is_action_just_pressed("Draw"):
#		add 2 lines here because inorder for the line to show when we firt draw
# 		we need to get line.points.size()-1 without 2 lines you would not be able to see the line
#		on the first line drawn

		
		#if line.points.size() > 0:
			
			#crew.position = line.points[0]
			
		
		
			
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
		
	if Input.is_action_just_pressed("Clear_Draw"):
		line.clear_points()
	
	if Input.is_action_just_pressed("Stop_Draw"):
		is_drawing = false
		
		
