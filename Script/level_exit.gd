extends Area2D

@export var next_level: int = 1

var triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:

	if triggered:
		return

	if body.name != "Player":
		return

	triggered = true

	var main = get_tree().current_scene

	if next_level == 1:
		main.complete_level_1()

	elif next_level == 2:
		main.complete_level_2()

	elif next_level == 3:
		main.complete_level_3()
