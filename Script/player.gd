extends CharacterBody2D

@export var speed: float = 300.0


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1

	if Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1

	if Input.is_key_pressed(KEY_UP):
		direction.y -= 1

	if Input.is_key_pressed(KEY_DOWN):
		direction.y += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()

	velocity = direction * speed

	print("INPUT: ", direction)
	print("VELOCITY BEFORE: ", velocity)
	print("POSITION BEFORE: ", position)

	move_and_slide()

	print("POSITION AFTER: ", position)
	print("COLLISIONS: ", get_slide_collision_count())
