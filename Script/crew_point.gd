class_name Crew_points extends Area2D

var clicked := false

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				clicked = true
				print("Point clicked")
