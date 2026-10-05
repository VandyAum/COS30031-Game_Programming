extends Area2D


var clicked := false
var can_clicked := false

func _input_event(viewport, event, shape_idx):
	if !can_clicked:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				clicked = true
				print("Point clicked")
