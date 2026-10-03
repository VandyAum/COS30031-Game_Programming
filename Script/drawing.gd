extends Node2D


@onready var line = $Line

# For the points
@export var crew_points : Area2D
@export var end_points : Area2D
@export var camberwell : Camberwell
@onready var road_points = camberwell.get_node("RoadPoints")

# For police crew
var crew_scene = preload("res://police_crew.tscn")
@onready var crew = crew_scene.instantiate()
var crew_spawned := false
var path_index := 1
var is_following_path := false
@export var crew_speed := 200

#For drawing
var is_drawing := true
var drawing_started := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if is_drawing:
		draw()
	if is_following_path:
		move_crew(delta)
	
func draw():
	
	# This is responsible for check if the point is clicked
	if(line.points.size() == 0) and crew_points.clicked and !end_points.clicked:
		# add 2 lines here because inorder for the line to show when we firt draw
		# we need to get line.points.size()-1 without 2 lines you would not be able to see the line
		# on the first line drawn	
		var point_position = line.to_local(crew_points.global_position)

		line.add_point(point_position)
		line.add_point(point_position)
		
		drawing_started = true
	if Input.is_action_just_pressed("Draw") and line.points.size() > 0:
		line.add_point(get_local_mouse_position())
	if line.points.size() > 0:
#		This is for showing the line from one point to another when drawing
		line.set_point_position(line.points.size()-1, get_local_mouse_position())
		if !crew_spawned:
			add_child(crew)
			crew.position = line.points[0]
			crew_spawned = true
	#if Input.is_action_just_pressed("Stop_Draw"):
		#is_drawing = false
		#if line.points.size() > 1:
			#path_index = 1
			#is_following_path = true
	if drawing_started:
		end_points.can_clicked = true
		if end_points.clicked and drawing_started:
			# This is where the snapping occur
			var closest_point = get_closest_road_point(end_points.global_position)
			if closest_point != null:
				var snapped_position = line.to_local(closest_point.global_position)
				line.set_point_position(line.points.size() - 1, snapped_position)
			snap_line_to_road()
			var end_position = line.to_local(end_points.global_position)
			line.set_point_position(line.points.size() - 1, end_position)
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
		

func get_closest_road_point(position):
	var closest_point = null
	var closest_distance = INF

	for point in road_points.get_children():
		var distance = position.distance_to(point.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_point = point

	return closest_point
	
func snap_line_to_road():
	for i in range(1, line.points.size() - 1):
		var line_point_global = line.to_global(line.points[i])

		var closest_point = get_closest_road_point(line_point_global)

		if closest_point != null:
			var snapped_position = line.to_local(closest_point.global_position)

			line.set_point_position(i, snapped_position)
