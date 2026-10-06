class_name Fx
## Particle effects, built in code from a few presets so every system can
## ask for the same look: Fx.burst(parent, pos, &"resolved") for a one-shot
## burst that frees itself, Fx.ambient(&"fire") for a looping emitter to
## attach to something. CPUParticles2D, so they also run in the web build.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a static Godot 4.7 helper class Fx that builds CPUParticles2D
#    effects from named presets, for feedback in the dispatch game. One-shot
#    bursts (free themselves when finished): 'resolved' (green and white
#    sparkles fanning out), 'passed_on' (a grey puff drifting up), 'alert'
#    (red sparks when a crew hits an obstacle), 'arrive' (a small white ring
#    when a crew reaches the scene), 'dust' (beige puff when a scene is
#    cleared), 'sparks' (metal hit) and 'glint' (glass hit). Looping ambient
#    emitters: 'fire' (flames turning to smoke), 'water' (spray from a burst
#    main) and 'rain' (storm). Use a soft round texture made with
#    GradientTexture2D, colour ramps that fade to transparent, and a scale
#    argument so effects can match the zoom like the incident pins do."

const PRESETS := {
	&"resolved": {"amount": 30, "life": 0.9, "speed": Vector2(70, 150), "size": Vector2(3, 6),
		"damping": 90.0, "colours": ["#2fbf71", "#d9ffe8", "#2fbf7100"]},
	&"passed_on": {"amount": 16, "life": 1.4, "speed": Vector2(15, 45), "size": Vector2(8, 15),
		"gravity": Vector2(0, -25), "colours": ["#9aa0a6cc", "#9aa0a600"]},
	&"alert": {"amount": 22, "life": 0.6, "speed": Vector2(80, 190), "size": Vector2(2, 5),
		"damping": 150.0, "colours": ["#ffd166", "#d62828", "#d6282800"]},
	&"arrive": {"amount": 18, "life": 0.5, "speed": Vector2(90, 110), "size": Vector2(2, 4),
		"damping": 120.0, "colours": ["#ffffff", "#ffffff00"]},
	&"dust": {"amount": 14, "life": 1.0, "speed": Vector2(20, 60), "size": Vector2(6, 12),
		"damping": 40.0, "colours": ["#c8b89acc", "#c8b89a00"]},
	&"sparks": {"amount": 10, "life": 0.35, "speed": Vector2(60, 150), "size": Vector2(1.5, 3),
		"damping": 200.0, "colours": ["#fff3b0", "#ff9f1c", "#ff9f1c00"]},
	&"glint": {"amount": 6, "life": 0.4, "speed": Vector2(20, 60), "size": Vector2(1.5, 3),
		"damping": 100.0, "colours": ["#ffffff", "#bde8ff00"]},
	# Looping
	&"fire": {"amount": 48, "life": 1.1, "speed": Vector2(25, 55), "size": Vector2(10, 20), "loop": true,
		"direction": Vector2(0, -1), "spread": 25.0, "gravity": Vector2(0, -40), "box": Vector2(34, 12),
		"colours": ["#fff3b0", "#ff9f1c", "#e63946", "#5c5c5c99", "#5c5c5c00"]},
	&"water": {"amount": 40, "life": 0.7, "speed": Vector2(50, 90), "size": Vector2(4, 7), "loop": true,
		"direction": Vector2(0, -1), "spread": 35.0, "gravity": Vector2(0, 160),
		"colours": ["#bde8ff", "#4ea8de", "#4ea8de00"]},
	&"rain": {"amount": 70, "life": 0.6, "speed": Vector2(90, 130), "size": Vector2(3, 5), "loop": true,
		"direction": Vector2(0.3, 1), "spread": 4.0, "box": Vector2(110, 80),
		"colours": ["#3d6fb0dd", "#3d6fb000"]},
}

static var _soft_texture: Texture2D


## A one-shot burst at pos (in parent's space). Frees itself.
static func burst(parent: Node, pos: Vector2, kind: StringName, scale := 1.0) -> CPUParticles2D:
	var p := _make(kind)
	if p == null:
		return null
	p.position = pos
	p.scale = Vector2.ONE * scale
	p.one_shot = true
	p.explosiveness = 0.9
	p.finished.connect(p.queue_free)
	parent.add_child(p)
	p.emitting = true
	return p


## A looping emitter to add as a child of whatever is burning/flooding.
static func ambient(kind: StringName) -> CPUParticles2D:
	var p := _make(kind)
	if p:
		p.emitting = true
	return p


static func _make(kind: StringName) -> CPUParticles2D:
	if not PRESETS.has(kind):
		return null
	var d: Dictionary = PRESETS[kind]
	var p := CPUParticles2D.new()
	p.local_coords = true
	p.amount = d["amount"]
	p.lifetime = d["life"]
	p.texture = _texture()
	p.direction = d.get("direction", Vector2.RIGHT)
	p.spread = d.get("spread", 180.0)
	p.gravity = d.get("gravity", Vector2.ZERO)
	p.initial_velocity_min = d["speed"].x
	p.initial_velocity_max = d["speed"].y
	p.damping_min = d.get("damping", 0.0)
	p.damping_max = d.get("damping", 0.0)
	# "size" is the visible diameter in px; the soft texture fades out
	# towards its 32 px edge, so 24 px of it reads as solid.
	p.scale_amount_min = d["size"].x / 24.0
	p.scale_amount_max = d["size"].y / 24.0
	if d.has("box"):
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = d["box"] * 0.5
	var colours: Array = d["colours"]
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colours.size():
		offsets.append(float(i) / (colours.size() - 1))
		cols.append(Color(colours[i]))
	var ramp := Gradient.new()
	ramp.offsets = offsets
	ramp.colors = cols
	p.color_ramp = ramp
	return p


static func _texture() -> Texture2D:
	if _soft_texture == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 32
		t.height = 32
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_soft_texture = t
	return _soft_texture
