extends CharacterBody2D

#Assets was taken from itch.io by SomeGame_Dev

@onready var timer = $Timer

var is_solving := false
var is_returning := false
var is_solved := false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func start_solving():
	is_solving = true
	timer.start()
	print("Crew started solving incident")

func _on_timer_timeout() -> void:
	is_solving = false
	is_returning = true
	is_solved = true
	print("Incident solved")
