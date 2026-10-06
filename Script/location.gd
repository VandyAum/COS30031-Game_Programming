extends Area2D

var clicked: bool = false

func _input_event(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicked = true
			print("LOCATION CLICKED: ", name)
