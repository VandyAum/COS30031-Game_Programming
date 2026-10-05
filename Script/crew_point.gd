class_name Crew_points extends Area2D

var clicked := false
var can_click := true

@export var location_name : String
@export var location_type : String

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and can_click:
				clicked = true
				print("Point clicked")
