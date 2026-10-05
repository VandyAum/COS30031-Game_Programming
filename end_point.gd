class_name endPoint extends Area2D

@onready var timer = $Timer
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

func _on_timer_timeout() -> void:
	deactivate()
	
	get_parent().show_new_random_point()
				
func activate():
	visible = true
	can_clicked = true
	timer.start()
	
func deactivate():
	visible = false
	can_clicked = false
	clicked = false



	
