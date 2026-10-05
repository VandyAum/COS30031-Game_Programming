extends Area2D

var triggered: bool = false

func _ready() -> void:
	
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:

	
	if triggered:
		return

	
	if body.name == "Player":
		triggered = true

		
		get_tree().current_scene.fail_incident()
