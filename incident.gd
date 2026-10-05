extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var points = get_children()
	show_random_points(2)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func hide_all_points():
	for point in get_children():
		point.visible = false
		point.can_clicked = false
		point.clicked = false

func show_random_points(amount):
	hide_all_points()
	
	# This will get all the incident point in this node and shuffle
	# since its stored as an array it will then only take the first few location
	var points = get_children()
	points.shuffle()

	# This will show the amount of incident depend on the level
	for i in range(amount):
		points[i].activate()

func show_new_random_point():
	var points = get_children()

	points.shuffle()

	for point in points:
		if !point.visible:
			point.activate()
			break
