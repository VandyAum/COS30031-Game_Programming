extends Node2D

@onready var line = $Line

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	drawing()

func drawing():
	var label = Label.new()
	label.z_index = 1

	if Input.is_action_just_pressed("Draw"):
		line.add_point(get_global_mouse_position())
	if Input.is_action_just_pressed("Clear_Draw"):
		line.clear_points()
		
		
		
