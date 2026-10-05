extends Node2D


@onready var line = $Line

# For the points
@export var locations : Node2D
@export var end_points : Area2D
@export var camberwell : Camberwell
@export var surreyHill : surreyHill
@export var EHawthorn: EHawthorn
@onready var road_points = camberwell.get_node("RoadPoints")
@onready var surreyHill_road_points = surreyHill.get_node("RoadPoints")
@onready var ehawthorn_road_points = EHawthorn.get_node("RoadPoints")
var start_point = null

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
#	Tempory for now
	if Input.is_action_just_pressed("clear_draw"):
		if line.points.size() > 0 and !is_drawing:
			line.clear_points()
			crew.queue_free()
			crew_spawned = false
			#crew = crew_scene.instantiate()
			is_drawing = true
func draw():
	# This is responsible for check if the point is clicked
	if line.points.size() == 0:
		var clicked_location = get_clicked_location()
		if clicked_location != null:
			start_point = clicked_location
			var point_position = line.to_local(start_point.global_position)

			line.add_point(point_position)
			line.add_point(point_position)
			
			drawing_started = true
			start_point.clicked = false
			return
	if Input.is_action_just_pressed("Draw") and line.points.size() > 0:
		line.add_point(get_local_mouse_position())
	if Input.is_action_just_pressed("Undo_Drawing"):
		if line.points.size() > 2:
			line.remove_point(line.points.size() - 1)
	if line.points.size() > 0:
		#	NEED TO STUDY THIS BLOCK HERE
		if line.points.size() >= 2:
			var previous_point = line.points[line.points.size() - 2]

			var previous_global = line.to_global(previous_point)
			var mouse_global = get_global_mouse_position()

			var collision = check_collision(previous_global, mouse_global)

			if collision.is_empty():
				line.set_point_position(
					line.points.size() - 1,
					line.to_local(mouse_global)
				)
			else:
				var hit_position = collision.position

				line.set_point_position(
					line.points.size() - 1,
					line.to_local(hit_position)
				)
		
	if drawing_started:
		end_points.can_clicked = true
		if end_points.clicked:
			# This is where the snapping occur
	
			snap_line_to_road()
			
			var end_position = line.to_local(end_points.global_position)
			line.set_point_position(line.points.size() - 1, end_position)
			
			is_drawing = false
			
			if line.points.size() > 1:
				path_index = 1
				is_following_path = true
			if !crew_spawned:
				add_child(crew)
				if line.points.size() == 0:
					return
				else:
					crew.position = line.points[0]
				crew_spawned = true
	
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
		
func get_closest_valid_road_point(position, previous_position):
	var closest_point = null
	var closest_distance = INF

	var all_road_points = [
		road_points,
		surreyHill_road_points,
		ehawthorn_road_points
	]

	for road_group in all_road_points:
		for point in road_group.get_children():

			var collision = check_collision(
				previous_position,
				point.global_position
			)

			if collision.is_empty():
				var distance = position.distance_to(point.global_position)

				if distance < closest_distance:
					closest_distance = distance
					closest_point = point

	return closest_point


func snap_line_to_road():
	if line.points.size() == 0:
		return
	var previous_position = line.to_global(line.points[0])
	for i in range(1, line.points.size() - 1):
		var line_point_global = line.to_global(line.points[i])

		#var closest_point = get_closest_road_point(line_point_global)
		var closest_point = get_closest_valid_road_point(
			line_point_global,
			previous_position
		)

		if closest_point != null:
			var snapped_position = line.to_local(closest_point.global_position)

			line.set_point_position(i, snapped_position)
			previous_position = closest_point.global_position

func check_collision(from_position, to_position):
	var space_state = get_world_2d().direct_space_state

	var query = PhysicsRayQueryParameters2D.create(
		from_position,
		to_position
	)

	var result = space_state.intersect_ray(query)

	return result
	
func get_clicked_location():
	for point in locations.get_children():
		if point.clicked:
			return point

	return null
