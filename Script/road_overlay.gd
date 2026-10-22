extends Node2D
## RoadOverlay: draws the player's knowledge of every road on top of the map.
##
##   Fresh   -> full traffic colour (green / amber / red, dark red if blocked)
##   Ageing  -> desaturating toward grey
##   Stale   -> grey, but a darker grey for worse traffic so the old jam is
##              still visible ("is that still there?")
##   Unknown -> not drawn (the base map shows through; fog is a later task)
##
## F2 toggles a debug view of the raw road graph.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Node2D script that renders our road knowledge layer in
#    _draw(). For every road edge in the RoadGraph autoload that the Knowledge
#    autoload says is known, draw its polyline over the map, slightly thinner
#    than the road itself (width from the road class), coloured by the
#    last-known traffic level in a Google Maps / Waze style palette. As the
#    observation ages (Knowledge.freshness goes 1 -> 0), blend the colour
#    toward a grey of the SAME perceived lightness, so stale roads are fully
#    desaturated but worse traffic stays darker. Mark known-blocked roads with
#    a small cross at their midpoint so they read even when grey. Redraw on a
#    short timer (fading is continuous) and immediately when Events.road_observed
#    fires. Add an F2 debug toggle that draws every edge and intersection of the
#    raw graph so teammates can check the generated network lines up with the
#    map art. Read only from Knowledge, never from World."
# Follow-up prompt: "Roads now have four classes (local, collector, arterial,
#    freeway); add a width for each to match the new WorldMap road widths."
# Follow-up prompt: "Stale traffic shouldn't go fully grey either; keep at
#    least 10% of its colour."
# Follow-up prompt (match the map's vision radius, performance):
#   "Traffic should be revealed in exactly the same soft circle as the map
#    colours and fade the same way, instead of whole roads appearing and
#    clipping off. Draw known roads once in their fresh traffic colour and
#    let a canvas shader do the rest per pixel from Knowledge.sight_texture:
#    alpha from the G 'seen' coverage, colour fading from R (time last
#    seen) toward a grey of the same lightness with a 10% colour floor.
#    Only redraw when a road's known traffic changes (not on a timer); the
#    old 4x-per-second redraw of every road cost ~50% of the frame rate at
#    stage 3. Keep the F2 debug graph unmasked in a child node."
# Follow-up prompt (web build): "The web build loses its WebGL context
#    (GL_OUT_OF_MEMORY on Chrome/Metal): the overlay redraws every known road
#    as its own wide polyline, thousands of separate GPU buffers, almost
#    every frame. Batch the roads into one draw_multiline per traffic colour
#    and road width, and redraw at most every redraw_interval seconds."

# Indexed by World.Traffic (CLEAR, SLOW, JAMMED, BLOCKED).
const TRAFFIC_COLOURS: Array[Color] = [
	Color("2fbf71"),
	Color("f5a623"),
	Color("e5383b"),
	Color("7a1020"),
]
## Minimum share of the traffic colour kept once fully stale.
const STALE_COLOUR_FLOOR := 0.1
## Line width per road class (local, collector, arterial, freeway).
## Slightly narrower than the road drawn by WorldMap so the road edge shows.
const CLASS_WIDTH := [4.0, 5.5, 7.5, 9.5]

const OVERLAY_SHADER := """
shader_type canvas_item;
uniform sampler2D sight_tex : filter_linear;
uniform vec2 world_size;
uniform float now;
uniform float fade = 60.0;
uniform float colour_floor = 0.1;
varying vec2 world_pos;
void vertex() {
	world_pos = VERTEX;   // node sits at the world origin
}
void fragment() {
	vec2 sight = texture(sight_tex, world_pos / world_size).rg;
	float fresh = clamp(1.0 - (now - sight.r) / fade, 0.0, 1.0);
	vec3 c = COLOR.rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 stale = mix(vec3(luma), vec3(0.55), 0.25);   // worse traffic stays darker
	COLOR.rgb = mix(stale, c, max(colour_floor, smoothstep(0.0, 1.0, fresh)));
	COLOR.a *= smoothstep(0.0, 1.0, sight.g);          // only where it was seen
}
"""

var show_debug_graph := false
var _debug_layer: Node2D
var _dirty := true
## Shortest gap between overlay rebuilds (seconds).
@export var redraw_interval := 0.2
var _redraw_wait := 0.0


func _ready() -> void:
	var shader := Shader.new()
	shader.code = OVERLAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("sight_tex", Knowledge.sight_texture)
	mat.set_shader_parameter("world_size", Stage.world_size)
	mat.set_shader_parameter("fade", Knowledge.fade_seconds)
	mat.set_shader_parameter("colour_floor", STALE_COLOUR_FLOOR)
	material = mat

	_debug_layer = Node2D.new()
	_debug_layer.use_parent_material = false
	_debug_layer.draw.connect(_draw_debug)
	add_child(_debug_layer)

	Events.road_observed.connect(func(_edge: int) -> void: _dirty = true)
	Events.stage_changed.connect(func(_s: int) -> void: _dirty = true)


func _process(delta: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("now", Knowledge.clock)
	_redraw_wait -= delta
	if _dirty and _redraw_wait <= 0.0:
		_dirty = false
		_redraw_wait = redraw_interval
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F2:
		show_debug_graph = not show_debug_graph
		_debug_layer.queue_redraw()


func _draw() -> void:
	# One batch of segments per (traffic level, road class): ~20 draw calls
	# instead of one per road.
	var batches := []           # index level * CLASSES + class -> Array of Vector2
	var classes := CLASS_WIDTH.size()
	for i in TRAFFIC_COLOURS.size() * classes:
		batches.append([])
	var crosses := PackedVector2Array()
	for e in RoadGraph.edge_count():
		if not Knowledge.is_known(e):
			continue
		var level := Knowledge.known_level(e)
		var segs: Array = batches[level * classes + RoadGraph.edge_class(e)]
		var pts: PackedVector2Array = RoadGraph.edge_pts[e]
		for i in range(1, pts.size()):
			segs.append(pts[i - 1])
			segs.append(pts[i])
		if level == World.Traffic.BLOCKED:
			var m := RoadGraph.edge_midpoint(e)
			crosses.append_array([m + Vector2(-6, -6), m + Vector2(6, 6), m + Vector2(-6, 6), m + Vector2(6, -6)])
	for i in batches.size():
		if not batches[i].is_empty():
			draw_multiline(PackedVector2Array(batches[i]), TRAFFIC_COLOURS[i / classes], CLASS_WIDTH[i % classes])
	if not crosses.is_empty():
		draw_multiline(crosses, (TRAFFIC_COLOURS[World.Traffic.BLOCKED] as Color).darkened(0.4), 3.0)


func _draw_debug() -> void:
	if not show_debug_graph:
		return
	for e in RoadGraph.edge_count():
		_debug_layer.draw_polyline(RoadGraph.edge_pts[e], Color(0.2, 0.4, 1.0, 0.8), 1.5)
	for p in RoadGraph.node_positions:
		_debug_layer.draw_circle(p, 3.0, Color(1, 0.2, 0.8))
