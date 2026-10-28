extends Camera3D
## City3DCamera: orbit camera for the greybox city. Right-drag to orbit,
## left- or middle-drag to pan, wheel to zoom, WASD / arrows to move,
## Q / E to turn. During a benchmark the FPS probe drives it with
## set_bench_angle() so every run follows the same path.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 orbit camera for the greybox 3D city (city_3d.gd).
#    It orbits a focus point on the ground: right mouse drag orbits (yaw and
#    pitch, pitch clamped between 15 and 85 degrees), left or middle drag
#    pans across the ground at a speed that scales with distance, the wheel
#    zooms between 60 m and 3 km, WASD / arrow keys pan and Q / E turn.
#    Keep the focus inside the city's extent (City3D.extent_m()). Start
#    over Cambermere Junction looking down at about 55 degrees from 900 m.
#    Add set_bench_angle(t) for the FPS benchmark: a repeatable fly-around
#    of the junction (full turn, distance easing in and out) so frame-rate
#    numbers can be compared between builds. Keep working while the tree is
#    paused."
# Follow-up prompt (chase camera): "Add a chase mode on C that follows the
#    demo traffic's ChaseTarget (city_3d_traffic.gd) from behind and above,
#    smoothed; C again returns to orbiting where the camera is. The
#    benchmark turns it off. start_chase() turns it on from code (for
#    scripted screenshots)."

@export var min_distance := 60.0
@export var max_distance := 3000.0
@export var orbit_speed := 0.005
@export var key_pan_speed := 0.9        # screen heights per second

var focus := Vector3.ZERO
var yaw := deg_to_rad(-30.0)
var pitch := deg_to_rad(55.0)
var distance := 900.0
var bounds := Rect2(-2000, -2000, 4000, 4000)
var chasing := false                    # C: follow the demo traffic's chase car

var _city: Node
var _chase_target: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	far = 8000.0
	near = 0.5
	_city = get_parent()
	if _city and not _city.is_node_ready():
		await _city.ready                 # the city builds after its children
	if _city and _city.has_method("extent_m"):
		bounds = _city.extent_m()
	_apply()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_C:
		if chasing:
			chasing = false
			focus = Vector3(_chase_target.global_position.x, 0.0, _chase_target.global_position.z)
			distance = maxf(distance, 200.0)
			_apply()
		else:
			start_chase()


func start_chase() -> void:
	_chase_target = _city.get_node_or_null("Traffic/ChaseTarget") if _city else null
	chasing = _chase_target != null
	if chasing:
		global_position = _chase_target.global_position + Vector3(0, 30, 30)


# Behind and above the car, smoothed.
func _chase(delta: float) -> void:
	var car := _chase_target.global_transform
	var fwd := -car.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var want := car.origin - fwd * 11.0 + Vector3.UP * 4.0
	global_position = global_position.lerp(want, 1.0 - exp(-6.0 * delta))
	look_at(car.origin + Vector3.UP * 1.2, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if m.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= m.relative.x * orbit_speed
			pitch = clampf(pitch + m.relative.y * orbit_speed, deg_to_rad(15.0), deg_to_rad(85.0))
		elif m.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
			var scale := distance / get_viewport().get_visible_rect().size.y * 1.2
			_pan(Vector2(-m.relative.x, -m.relative.y) * scale)
	elif event is InputEventMouseButton and event.pressed:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.88)
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance / 0.88)
	_apply()


func _process(delta: float) -> void:
	if chasing and is_instance_valid(_chase_target):
		_chase(delta)
		return
	var move := Vector2(
		Input.get_axis(&"ui_left", &"ui_right") + float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		Input.get_axis(&"ui_up", &"ui_down") + float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if move != Vector2.ZERO:
		_pan(move.limit_length(1.0) * distance * key_pan_speed * delta)
	var turn := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	yaw += turn * 1.2 * delta
	_apply()


## Benchmark path, t in 0..1: one full turn round the junction, swinging
## from 1.2 km out to 350 m and back, so near and far detail both count.
func set_bench_angle(t: float) -> void:
	chasing = false
	focus = Vector3.ZERO
	yaw = deg_to_rad(-30.0) + TAU * t
	pitch = deg_to_rad(lerpf(60.0, 35.0, sin(PI * t)))
	distance = lerpf(1200.0, 350.0, sin(PI * t))
	_apply()


# Pan in screen directions, flattened onto the ground.
func _pan(screen: Vector2) -> void:
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	focus += right * screen.x - forward * screen.y
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)


func _apply() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	global_position = focus + offset
	look_at(focus, Vector3.UP)
