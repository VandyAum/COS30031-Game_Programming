class_name DebrisPiece extends RigidBody2D
## One piece of scene debris: a real 2D physics body set up from a
## DebrisType. It scatters when its scene appears, bounces off barriers and
## other debris according to its PhysicsMaterial, gets shoved aside by crew
## vehicles, and fades away once the scene is cleared.
##
## Collision filtering (set in Scenes/debris_piece.tscn):
##   layer 3 "debris"; mask 1 "barriers" + 2 "vehicles" + 3 "debris".
##   It never touches incident zones or crew sensors.

# AI-assisted (Claude Opus 5.5): written from the prompt in
# Script/Data/debris_type.gd, plus: "DebrisPiece: a RigidBody2D scene that
#    takes its shape, PhysicsMaterial, mass and damping from a DebrisType,
#    draws itself (box or circle with an accent detail, outlined so it reads
#    on the grey map), plays its impact sound through Sfx and throws a small
#    Fx burst on hard hits (rate limited, using the speed from the previous
#    physics frame because contacts have already slowed it), and has
#    sweep() to stop colliding and fade out when the scene is cleared."

## Slower hits than this (world px/s) make no sound.
const QUIET_SPEED := 22.0
## Hits faster than this throw the type's impact effect.
const FX_SPEED := 70.0

var type: DebrisType
var _last_speed := 0.0
var _hit_cooldown := 0.0


func setup(t: DebrisType) -> void:
	type = t
	physics_material_override = t.physics_material
	mass = t.mass
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = t.linear_damp
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = t.angular_damp
	var shape_node := $Shape as CollisionShape2D
	if t.shape == DebrisType.Shape.CIRCLE:
		var c := CircleShape2D.new()
		c.radius = t.size.x * 0.5
		shape_node.shape = c
	else:
		var r := RectangleShape2D.new()
		r.size = t.size
		shape_node.shape = r


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_last_speed = linear_velocity.length()
	_hit_cooldown -= delta


func _on_body_entered(_other: Node) -> void:
	var speed := maxf(_last_speed, linear_velocity.length())
	if speed < QUIET_SPEED or _hit_cooldown > 0.0:
		return
	_hit_cooldown = 0.18
	Sfx.play_at(type.impact_sound, global_position, linear_to_db(clampf(speed / 160.0, 0.25, 1.0)))
	if speed > FX_SPEED and type.impact_fx != &"":
		Fx.burst(get_parent(), position, type.impact_fx, 0.6)


## The scene is cleared: stop colliding and fade out.
func sweep(seconds := 0.8) -> void:
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, seconds)
	tween.tween_callback(queue_free)


func _draw() -> void:
	if type == null:
		return
	var outline := type.colour.darkened(0.45)
	if type.shape == DebrisType.Shape.CIRCLE:
		var r := type.size.x * 0.5
		draw_circle(Vector2.ZERO, r, type.colour)
		if type.accent.a > 0.0:
			draw_circle(Vector2.ZERO, r * 0.45, type.accent)
		draw_circle(Vector2.ZERO, r, outline, false, 1.0)
	else:
		var rect := Rect2(-type.size * 0.5, type.size)
		draw_rect(rect, type.colour)
		if type.accent.a > 0.0:
			# A band across the middle (bin lid, branch leaves, panel crease).
			draw_rect(Rect2(Vector2(-type.size.x * 0.12, -type.size.y * 0.5), Vector2(type.size.x * 0.24, type.size.y)), type.accent)
		draw_rect(rect, outline, false, 1.0)
