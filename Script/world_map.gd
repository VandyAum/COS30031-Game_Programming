extends Node2D
## WorldMap: the whole play area as one scene, drawn from real Vicmap data
## in Map/world/ (built by tools/build_world.py).
##
## Layers, bottom to top: land, parks, water, sites + buildings, rail, roads,
## suburb names, then the colour filter (monochrome except where crews have
## recently looked), then the rectangular stage fog. The licence credit sits
## bottom-right on its own CanvasLayer.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Node2D script that renders our single world map from
#    the processed Vicmap files in res://Map/world/: areas.json (council and
#    suburb outlines, parks, water polygons, waterway lines with widths, rail
#    and tram lines, real building footprints), buildings.bin (packed records
#    of 8 int16 box corner coordinates + 1 byte land-use kind + 1 byte stage)
#    and roads.json (playable road edges with class 0-3 plus 'decor' roads
#    outside the council). Aim for a clean Mini Motorways / Google Maps look:
#    warm paper land, soft green parks, blue water, pale building boxes tinted
#    by land use (residential, commercial, public, industrial), white roads
#    with a darker casing, wider for bigger road classes, and large faded
#    suburb names. Build each filled layer as ONE ArrayMesh (MeshInstance2D)
#    so 140k building boxes stay fast; draw lines once in child nodes' draw
#    callbacks so they're cached. Finally add a fog Sprite2D using the Stage
#    autoload's mask image (one byte per 8 px = first playable stage) and a
#    small canvas shader that fogs every pixel whose stage is above
#    Stage.current, updating the shader uniform on Events.stage_changed.
#    Print how long loading took."
# Follow-up prompt: "When zoomed out at stage 3 the screen is wider than the
#    world, and decor roads/rivers past the world edge show unfogged. Surround
#    the world with an opaque frame matching the fog-over-land colour so
#    nothing beyond the edge is ever visible."
# Follow-up prompt (monochrome + reveal, rectangular fog, credit):
#   "Make the map monochrome by default and reveal its colours only near
#    where crews have looked, fading back to grey as that information ages:
#    add a full-world filter drawn after the map layers whose canvas shader
#    reads the screen texture underneath, converts it to greyscale, and mixes
#    the original colour back in by the freshness sampled from
#    Knowledge.sight_texture (time last seen per 16 px cell) and
#    Knowledge.clock / fade_seconds. Replace the mask-based stage fog with
#    simple rectangular fog: dark panels covering everything outside
#    Stage.bounds(), rebuilt on Events.stage_changed, which also hide
#    everything past the world edge. Load the new buildings.bin format
#    (records of u8 kind, u16 triangle count, then triangles as int16 x/y),
#    where kinds 4-7 are pale 'site' tints for big parcels drawn under the
#    boxes. Show the licence credit from Stage.credit() in small text in the
#    bottom-right corner of the screen at all times."
# Follow-up prompt: "The palette is so pastel that revealed colour barely
#    reads against the monochrome. Make parks, water and the land-use tints
#    noticeably richer (still soft) so the reveal around crews pops."

const AREAS_PATH := "res://Map/world/areas.json"
const BUILDINGS_PATH := "res://Map/world/buildings.bin"
const ROADS_PATH := "res://Map/world/roads.json"

const LAND := Color("efeae0")
const PARK := Color("b4dc98")
const WATER := Color("86c0ea")
const FOOTPRINT := Color("c4b9a8")
const RAIL := Color("8d8a85")
const TRAM := Color("c4b7a3")
const ROAD_FILL := Color("ffffff")
const ROAD_CASING := Color("cdc5b6")
const SUBURB_LINE := Color(0.55, 0.5, 0.42, 0.45)
const SUBURB_TEXT := Color(0.45, 0.4, 0.33, 0.35)
## Colour by kind: 0-3 building boxes (residential, commercial, public,
## industrial), 4-7 the matching pale site tints for big parcels.
const KIND_COLOURS: Array[Color] = [
	Color("e6d2b0"), Color("e7b9d6"), Color("b3cdee"), Color("d8c79f"),
	Color("eee2cb"), Color("f0d7e6"), Color("d3e1f3"), Color("e6dcc2"),
]
## Road width per class (local, collector, arterial, freeway), world px.
const ROAD_WIDTH := [7.0, 9.0, 12.0, 15.0]
const CASING := 2.5

@export var fog_colour := Color(0.20, 0.23, 0.29, 0.82)
## 1.0 = fully grey where unseen; lower keeps a hint of colour everywhere.
@export var monochrome := 1.0

var _areas: Dictionary
var _roads: Dictionary
var _filter: Polygon2D
var _fog_panels: Array[Polygon2D] = []


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	RenderingServer.set_default_clear_color(LAND)   # beyond the world edge, under fog
	_areas = JSON.parse_string(FileAccess.get_file_as_string(AREAS_PATH))
	_roads = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))

	_add_rect("Land", Rect2(Vector2.ZERO, Stage.world_size), LAND, 0)
	_add_polygon_layer("Parks", _areas["parks"], PARK)
	_add_polygon_layer("Water", _areas["water"], WATER)
	_add_line_layer("Waterways", _draw_waterways)
	_add_buildings()
	_add_polygon_layer("Footprints", _areas["footprints"], FOOTPRINT)
	_add_line_layer("Rail", _draw_rail)
	_add_line_layer("Roads", _draw_roads)
	_add_line_layer("Suburbs", _draw_suburbs)
	_add_colour_filter()
	_add_fog()
	_add_credit()

	Events.stage_changed.connect(_on_stage_changed)
	print("WorldMap: loaded in %d ms" % (Time.get_ticks_msec() - t0))


func _process(_delta: float) -> void:
	(_filter.material as ShaderMaterial).set_shader_parameter("now", Knowledge.clock)


# --- Filled layers (one mesh each) -----------------------------------------

func _add_rect(layer_name: String, r: Rect2, colour: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.name = layer_name
	p.color = colour
	p.z_index = z
	p.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	add_child(p)
	return p


func _add_polygon_layer(layer_name: String, polygons: Array, colour: Color) -> void:
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	for raw: Array in polygons:
		var poly := _pts(raw)
		var tris := Geometry2D.triangulate_polygon(poly)
		if tris.is_empty():
			continue  # self-intersecting outline; skip rather than error
		var base := verts.size()
		verts.append_array(poly)
		for i in tris:
			indices.append(base + i)
	var colours := PackedColorArray()
	colours.resize(verts.size())
	colours.fill(colour)
	_add_mesh(layer_name, verts, colours, indices)


# buildings.bin: records of [u8 kind][u16 tri count][tri count * 6 int16].
func _add_buildings() -> void:
	var data := FileAccess.get_file_as_bytes(BUILDINGS_PATH)
	var verts := PackedVector2Array()
	var colours := PackedColorArray()
	var o := 0
	while o < data.size():
		var colour := KIND_COLOURS[data[o]]
		var tri_count := data.decode_u16(o + 1)
		o += 3
		for v in tri_count * 3:
			verts.append(Vector2(data.decode_s16(o), data.decode_s16(o + 2)))
			colours.append(colour)
			o += 4
	_add_mesh("Buildings", verts, colours, PackedInt32Array())


func _add_mesh(layer_name: String, verts: PackedVector2Array, colours: PackedColorArray, indices: PackedInt32Array) -> void:
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = layer_name
	node.mesh = mesh
	add_child(node)


# --- Line layers (drawn once, cached by the renderer) ----------------------

func _add_line_layer(layer_name: String, painter: Callable) -> void:
	var node := Node2D.new()
	node.name = layer_name
	add_child(node)
	node.draw.connect(painter.bind(node))
	node.queue_redraw()


static func _pts(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in raw:
		out.append(Vector2(p[0], p[1]))
	return out


func _draw_waterways(node: Node2D) -> void:
	for w: Dictionary in _areas["waterways"]:
		node.draw_polyline(_pts(w["pts"]), WATER, float(w["w"]))


func _draw_rail(node: Node2D) -> void:
	for line: Array in _areas["tram"]:
		node.draw_polyline(_pts(line), TRAM, 1.5)
	for line: Array in _areas["rail"]:
		var pts := _pts(line)
		node.draw_polyline(pts, RAIL, 4.0)
		node.draw_polyline(pts, LAND, 1.5)   # hollow centre reads as track


func _draw_roads(node: Node2D) -> void:
	var lines := []   # [class, points]
	for e: Dictionary in _roads["decor"]:
		lines.append([int(e["c"]), _pts(e["pts"])])
	for e: Dictionary in _roads["edges"]:
		lines.append([int(e["c"]), _pts(e["pts"])])
	# Casings first so junctions merge cleanly, small roads under big ones.
	for cls in 4:
		for l: Array in lines:
			if l[0] == cls:
				node.draw_polyline(l[1], ROAD_CASING, ROAD_WIDTH[cls] + CASING * 2)
	for cls in 4:
		for l: Array in lines:
			if l[0] == cls:
				node.draw_polyline(l[1], ROAD_FILL, ROAD_WIDTH[cls])


func _draw_suburbs(node: Node2D) -> void:
	var font := ThemeDB.fallback_font
	for s: Dictionary in _areas["suburbs"]:
		var pts := _pts(s["pts"])
		pts.append(pts[0])
		node.draw_polyline(pts, SUBURB_LINE, 3.0)
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= pts.size()
		var text := str(s["name"]).to_upper()
		var size := 80
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		node.draw_string(font, centre - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, SUBURB_TEXT)


# --- Colour filter: monochrome except where crews have looked --------------

const FILTER_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D sight_tex : filter_linear;
uniform vec2 world_size;
uniform float now;
uniform float fade = 60.0;
uniform float monochrome = 1.0;
varying vec2 world_pos;
void vertex() {
	world_pos = VERTEX;   // node sits at the world origin
}
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float seen = texture(sight_tex, world_pos / world_size).r;
	float fresh = clamp(1.0 - (now - seen) / fade, 0.0, 1.0);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 mono = mix(c, vec3(grey), monochrome);
	COLOR = vec4(mix(mono, c, smoothstep(0.0, 1.0, fresh)), 1.0);
}
"""

func _add_colour_filter() -> void:
	_filter = _add_rect("ColourFilter", Rect2(Vector2.ZERO, Stage.world_size), Color.WHITE, 0)
	var shader := Shader.new()
	shader.code = FILTER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("sight_tex", Knowledge.sight_texture)
	mat.set_shader_parameter("world_size", Stage.world_size)
	mat.set_shader_parameter("fade", Knowledge.fade_seconds)
	mat.set_shader_parameter("monochrome", monochrome)
	_filter.material = mat


# --- Stage fog: dark panels around the current stage rectangle -------------

func _add_fog() -> void:
	for i in 4:
		_fog_panels.append(_add_rect("Fog%d" % i, Rect2(), fog_colour, 50))   # above crews and routes
	_on_stage_changed(Stage.current)


func _on_stage_changed(_stage: int) -> void:
	var r := Stage.bounds()
	var far := 30000.0
	var outer := Rect2(-far, -far, Stage.world_size.x + far * 2, Stage.world_size.y + far * 2)
	var panels := [
		Rect2(outer.position.x, outer.position.y, outer.size.x, r.position.y - outer.position.y),   # top
		Rect2(outer.position.x, r.end.y, outer.size.x, outer.end.y - r.end.y),                       # bottom
		Rect2(outer.position.x, r.position.y, r.position.x - outer.position.x, r.size.y),            # left
		Rect2(r.end.x, r.position.y, outer.end.x - r.end.x, r.size.y),                               # right
	]
	for i in 4:
		var q: Rect2 = panels[i]
		_fog_panels[i].polygon = PackedVector2Array([q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)])


# --- Licence credit (always on screen, bottom-right) -----------------------

func _add_credit() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Credit"
	layer.layer = 90
	add_child(layer)
	var label := Label.new()
	label.text = Stage.credit()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15, 0.9))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.7)
	box.set_content_margin_all(4)
	label.add_theme_stylebox_override("normal", box)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 6)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(label)
