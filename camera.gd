extends Camera2D

var dragging := false
var last_mouse_position : Vector2

func _process(delta):
	if Input.is_action_just_pressed("Move_Map"):
		last_mouse_position = get_viewport().get_mouse_position()

	if Input.is_action_pressed("Move_Map"):
		var current_mouse_position = get_viewport().get_mouse_position()

		var difference = current_mouse_position - last_mouse_position

		position -= difference

		last_mouse_position = current_mouse_position
