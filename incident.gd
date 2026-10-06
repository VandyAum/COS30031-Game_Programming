extends Node2D

# AI-assisted edit (Claude Opus 5.5). Prompt used:
#   "Our incident spawner picks random incident points from its children.
#    Now that the map is one world revealed by stage, only pick points that
#    are inside the current Stage (Stage.is_playable) so incidents never
#    appear under the fog, and announce each one with
#    Events.incident_spawned so the debug HUD and future incident panel can
#    react. Keep the existing structure; proper data-driven incidents are a
#    later task."


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
	var points = _playable_points()
	points.shuffle()

	# This will show the amount of incident depend on the level
	for i in range(mini(amount, points.size())):
		_activate(points[i])

func show_new_random_point():
	var points = _playable_points()

	points.shuffle()

	for point in points:
		if !point.visible:
			_activate(point)
			break

func _playable_points():
	return get_children().filter(func(p): return Stage.is_playable(p.global_position))

func _activate(point):
	point.activate()
	Events.incident_spawned.emit(point)
