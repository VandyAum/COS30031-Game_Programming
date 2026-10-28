extends Node3D
## City3D: a greybox 3D Cambermere, extruded at load time from the same
## Map/world/ files the 2D map uses (written by tools/build_world.py).
## Nothing here is hand-placed: change the data, rebuild, and the city
## follows. It is a prototype for checking scale, readability and frame rate
## in 3D (desktop and web), not a replacement for the 2D map yet.
##
## Units: 1 Godot unit = 1 metre. Map pixels (0.75 px per metre, y south)
## become x east / z south, with the origin at Cambermere Junction (the
## centre of the tutorial rectangle).

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Greybox a 3D city for Cambermere in Godot 4.7, extruded from the
#    output of tools/build_world.py, without changing that tool or the data
#    files. Read Map/world/world_meta.json (px_per_m, stage_rects; stage 1
#    is Cambermere), buildings.bin (records of u8 kind, u16 triangle count,
#    then 6 x int16 per triangle; kinds 0-3 residential / commercial /
#    public / industrial boxes, 4-7 the pale 'site' tints for big parcels),
#    roads.json (playable 'edges' with class 0-3 and 'decor' roads) and
#    areas.json (parks, water, real building 'footprints' as outlines).
#    Keep only what falls inside the chosen stage rectangle. Extrude every
#    box: recover each parcel's outline from its triangles (an edge used by
#    only one triangle is a wall), build outward-facing walls and a flat
#    roof from the stored triangles. There is no height data, so give each
#    building a believable, deterministic height from its land use and a
#    hash of its position (houses 1-2 storeys, shops taller towards the
#    junction, schools/civic 2-3 storeys, sheds single tall storey); extrude
#    the real footprints too, sized by area. Sites, parks and water are flat
#    slabs, roads are flat ribbons sized by class. Keep it a greybox: light
#    greys with only a faint land-use tint through vertex colours, one
#    shared material. For speed, bucket everything into ~250 m chunks, one
#    MeshInstance3D per chunk so the camera can frustum-cull, and build the
#    arrays by hand (no SurfaceTool). Add a sun with shadows, sky-coloured
#    background, ambient light and distance fog, the orbit camera
#    (city_3d_camera.gd) and the FPS probe (fps_probe.gd). Allow a bigger
#    extent for stress tests: an exported stage index, overridable with
#    '--stage=N' on the command line or '?stage=N' in the web page URL.
#    Print the counts and the build time."
# Follow-up prompt: "The first render is washed out (almost white) and decor
#    roads poke out past the edge of the ground. Darken the greybox palette
#    and the sun/ambient so the massing reads, and clip road segments to the
#    stage rectangle instead of keeping any segment with one end inside."

const META_PATH := "res://Map/world/world_meta.json"
const BUILDINGS_PATH := "res://Map/world/buildings.bin"
const ROADS_PATH := "res://Map/world/roads.json"
const AREAS_PATH := "res://Map/world/areas.json"

const SITE := 4                         # kinds 4-7 are flat site tints
const CHUNK_M := 250.0                  # mesh bucket size for culling
## Greybox palette: greys with a faint land-use hint (res, com, pub, ind).
const KIND_GREY: Array[Color] = [
	Color(0.62, 0.61, 0.59), Color(0.62, 0.58, 0.64), Color(0.56, 0.60, 0.66), Color(0.58, 0.57, 0.53),
]
const SITE_GREY := Color(0.42, 0.42, 0.40)
const FOOTPRINT_GREY := Color(0.55, 0.55, 0.57)
const GROUND := Color(0.33, 0.33, 0.32)
const ROAD := Color(0.17, 0.18, 0.19)
const PARK := Color(0.30, 0.38, 0.28)
const WATER := Color(0.22, 0.30, 0.38)
## Road ribbon width per class (local, collector, arterial, freeway), metres.
const ROAD_WIDTH_M := [9.0, 12.0, 16.0, 20.0]

## Which stage rectangle to build: 0 tutorial, 1 Cambermere, 3 everything.
@export_range(0, 3) var stage_extent := 1

var px_per_m := 0.75
var origin_px := Vector2.ZERO           # Cambermere Junction, in map pixels
var rect_px := Rect2()                  # the area being built, map pixels
var stats := {"buildings": 0, "footprints": 0, "sites": 0, "roads": 0, "triangles": 0, "chunks": 0, "build_ms": 0}

var _chunks := {}                       # Vector2i -> _MeshBucket
var _material: StandardMaterial3D


## Hand-built triangle arrays for one chunk.
class _MeshBucket:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	## Adds one triangle facing 'normal' (Godot front faces wind clockwise,
	## so swap two corners when the winding points the wrong way).
	func tri(a: Vector3, b: Vector3, d: Vector3, normal: Vector3, col: Color) -> void:
		if (b - a).cross(d - a).dot(normal) > 0.0:
			var t := b
			b = d
			d = t
		v.append(a); v.append(b); v.append(d)
		n.append(normal); n.append(normal); n.append(normal)
		c.append(col); c.append(col); c.append(col)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # Esc (Run autoload) must not freeze the test
	var t0 := Time.get_ticks_msec()
	stage_extent = _stage_override(stage_extent)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	px_per_m = float(meta["px_per_m"])
	var r0: Array = meta["stage_rects"][0]
	origin_px = Vector2((r0[0] + r0[2]) * 0.5, (r0[1] + r0[3]) * 0.5)
	var r: Array = meta["stage_rects"][stage_extent]
	rect_px = Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95

	_add_ground()
	var areas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AREAS_PATH))
	_add_flat_polygons(areas["water"], WATER, 0.03)
	_add_flat_polygons(areas["parks"], PARK, 0.06)
	_add_roads(JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH)))
	_add_buildings(FileAccess.get_file_as_bytes(BUILDINGS_PATH))
	_add_footprints(areas["footprints"])
	_commit_chunks()
	_add_lighting()

	stats["build_ms"] = Time.get_ticks_msec() - t0
	print("City3D: stage %d extent %.0f x %.0f m, %d buildings, %d footprints, %d sites, %d road segments, %d triangles in %d chunks, built in %d ms" % [
		stage_extent, rect_px.size.x / px_per_m, rect_px.size.y / px_per_m, stats["buildings"], stats["footprints"],
		stats["sites"], stats["roads"], stats["triangles"], stats["chunks"], stats["build_ms"]])


## The size of the built area in metres (for the camera's bounds).
func extent_m() -> Rect2:
	return Rect2(_m(rect_px.position), rect_px.size / px_per_m)


# --- Map pixels -> metres ---------------------------------------------------
func _m(p: Vector2) -> Vector2:
	return (p - origin_px) / px_per_m


func _v3(p_m: Vector2, y: float) -> Vector3:
	return Vector3(p_m.x, y, p_m.y)


func _bucket(p_m: Vector2) -> _MeshBucket:
	var key := Vector2i(floori(p_m.x / CHUNK_M), floori(p_m.y / CHUNK_M))
	if not _chunks.has(key):
		_chunks[key] = _MeshBucket.new()
	return _chunks[key]


# Small deterministic hash -> 0..1, so heights don't change between runs.
func _hash01(p: Vector2) -> float:
	var h := int(p.x * 73.0) * 73856093 ^ int(p.y * 31.0) * 19349663
	return float(absi(h) % 10007) / 10007.0


# --- Ground, water, parks ---------------------------------------------------
func _add_ground() -> void:
	var e := extent_m().grow(40.0)
	var b := _MeshBucket.new()
	var a := _v3(e.position, 0.0)
	var c := _v3(e.end, 0.0)
	var bb := Vector3(c.x, 0.0, a.z)
	var d := Vector3(a.x, 0.0, c.z)
	b.tri(a, bb, c, Vector3.UP, GROUND)
	b.tri(a, c, d, Vector3.UP, GROUND)
	_make_instance("Ground", b)


func _add_flat_polygons(polys: Array, col: Color, y: float) -> void:
	for poly: Array in polys:
		var pts := PackedVector2Array()
		var touches := false
		for p: Array in poly:
			var px := Vector2(p[0], p[1])
			touches = touches or rect_px.has_point(px)
			pts.append(_m(px))
		if not touches or pts.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(pts)
		for i in range(0, idx.size(), 3):
			var a := pts[idx[i]]
			var b := pts[idx[i + 1]]
			var c := pts[idx[i + 2]]
			_bucket((a + b + c) / 3.0).tri(_v3(a, y), _v3(b, y), _v3(c, y), Vector3.UP, col)


# --- Roads: flat ribbons, one quad per segment plus a square join cap -------
func _add_roads(roads: Dictionary) -> void:
	for list_name in ["edges", "decor"]:
		for e: Dictionary in roads[list_name]:
			var w: float = ROAD_WIDTH_M[clampi(int(e["c"]), 0, 3)] * 0.5
			var pts: Array = e["pts"]
			for i in pts.size() - 1:
				var p0 := Vector2(pts[i][0], pts[i][1])
				var p1 := Vector2(pts[i + 1][0], pts[i + 1][1])
				var clipped := _clip_segment(p0, p1)
				if clipped.is_empty():
					continue
				var a := _m(clipped[0])
				var b := _m(clipped[1])
				if a.is_equal_approx(b):
					continue
				var dir := (b - a).normalized()
				var side := Vector2(-dir.y, dir.x) * w
				# Extend each end by half a width so bends don't show gaps.
				a -= dir * w * 0.5
				b += dir * w * 0.5
				var y := 0.1 + 0.02 * float(e["c"])      # bigger roads draw on top
				var bucket := _bucket((a + b) * 0.5)
				bucket.tri(_v3(a + side, y), _v3(b + side, y), _v3(b - side, y), Vector3.UP, ROAD)
				bucket.tri(_v3(a + side, y), _v3(b - side, y), _v3(a - side, y), Vector3.UP, ROAD)
				stats["roads"] += 1


## Liang-Barsky: the part of segment p0-p1 inside rect_px, or [] if none.
## Stops roads that cross the edge from sticking out past the ground.
func _clip_segment(p0: Vector2, p1: Vector2) -> PackedVector2Array:
	var d := p1 - p0
	var t0 := 0.0
	var t1 := 1.0
	var lo := rect_px.position
	var hi := rect_px.end
	for k in 4:
		var p: float = [-d.x, d.x, -d.y, d.y][k]
		var q: float = [p0.x - lo.x, hi.x - p0.x, p0.y - lo.y, hi.y - p0.y][k]
		if is_zero_approx(p):
			if q < 0.0:
				return PackedVector2Array()
			continue
		var t := q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([p0 + d * t0, p0 + d * t1])


# --- Buildings (buildings.bin) ---------------------------------------------
func _add_buildings(bytes: PackedByteArray) -> void:
	var i := 0
	var tris := PackedVector2Array()
	while i + 3 <= bytes.size():
		var kind := bytes[i]
		var count := bytes.decode_u16(i + 1)
		i += 3
		tris.resize(count * 3)
		var centre := Vector2.ZERO
		for t in count * 3:
			var p := Vector2(bytes.decode_s16(i), bytes.decode_s16(i + 2))
			i += 4
			tris[t] = p
			centre += p
		centre /= float(count * 3)
		if not rect_px.has_point(centre):
			continue
		if kind >= SITE:
			_add_slab(tris, 0.18, SITE_GREY)
			stats["sites"] += 1
		else:
			_extrude(tris, _height_for(kind, centre), KIND_GREY[kind])
			stats["buildings"] += 1


## Believable greybox heights in metres; there is no height data in Vicmap
## parcels, so this is land use + a stable per-building random.
func _height_for(kind: int, centre_px: Vector2) -> float:
	var h := _hash01(centre_px)
	match kind:
		0:   # residential: mostly single storey, some double
			return 4.5 if h < 0.65 else 7.5 + h * 1.5
		1:   # commercial: taller towards the junction
			var near := clampf(1.0 - _m(centre_px).length() / 900.0, 0.0, 1.0)
			return 7.0 + h * 8.0 + near * 18.0
		2:   # public: schools, civic
			return 7.0 + h * 5.0
		_:   # industrial: one tall storey
			return 6.0 + h * 3.0


## Flat site tint: the stored triangles, raised just off the ground.
func _add_slab(tris: PackedVector2Array, y: float, col: Color) -> void:
	for t in range(0, tris.size(), 3):
		var a := _m(tris[t])
		var b := _m(tris[t + 1])
		var c := _m(tris[t + 2])
		_bucket(a).tri(_v3(a, y), _v3(b, y), _v3(c, y), Vector3.UP, col)


## Roof from the stored triangles, walls from the outline: an edge shared by
## two triangles is inside the roof, an edge used once is a wall. The wall
## faces away from the triangle it came from.
func _extrude(tris: PackedVector2Array, height: float, col: Color) -> void:
	var uses := {}
	for t in range(0, tris.size(), 3):
		for k in 3:
			var key := _edge_key(tris[t + k], tris[t + (k + 1) % 3])
			uses[key] = uses.get(key, 0) + 1
	var bucket := _bucket(_m(tris[0]))
	var wall_col := col.darkened(0.08)
	for t in range(0, tris.size(), 3):
		var a := _m(tris[t])
		var b := _m(tris[t + 1])
		var c := _m(tris[t + 2])
		bucket.tri(_v3(a, height), _v3(b, height), _v3(c, height), Vector3.UP, col)
		for k in 3:
			var p := tris[t + k]
			var q := tris[t + (k + 1) % 3]
			if uses[_edge_key(p, q)] != 1:
				continue
			var opposite := _m(tris[t + (k + 2) % 3])
			_wall(bucket, _m(p), _m(q), opposite, height, wall_col)


func _wall(bucket: _MeshBucket, a: Vector2, b: Vector2, inside: Vector2, height: float, col: Color) -> void:
	var d := b - a
	var n2 := Vector2(-d.y, d.x).normalized()
	if n2.dot(inside - a) > 0.0:
		n2 = -n2
	var n := Vector3(n2.x, 0.0, n2.y)
	bucket.tri(_v3(a, 0.0), _v3(b, 0.0), _v3(b, height), n, col)
	bucket.tri(_v3(a, 0.0), _v3(b, height), _v3(a, height), n, col)


func _edge_key(p: Vector2, q: Vector2) -> Vector4:
	return Vector4(p.x, p.y, q.x, q.y) if (p.x < q.x or (p.x == q.x and p.y < q.y)) else Vector4(q.x, q.y, p.x, p.y)


# --- Real Vicmap building footprints (outlines in areas.json) --------------
func _add_footprints(footprints: Array) -> void:
	for ring: Array in footprints:
		var pts := PackedVector2Array()
		for p: Array in ring:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() > 3 and pts[0].is_equal_approx(pts[pts.size() - 1]):
			pts.remove_at(pts.size() - 1)        # closed ring -> open polygon
		if pts.size() < 3:
			continue
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= float(pts.size())
		if not rect_px.has_point(centre):
			continue
		var idx := Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			continue
		var tris := PackedVector2Array()
		for k in idx:
			tris.append(pts[k])
		# Big footprints are schools and shopping centres: a bit taller.
		var area_m2 := absf(_signed_area(pts)) / (px_per_m * px_per_m)
		var height := clampf(5.0 + sqrt(area_m2) * 0.12, 6.0, 16.0) + _hash01(centre) * 2.0
		_extrude(tris, height, FOOTPRINT_GREY)
		stats["footprints"] += 1


func _signed_area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


# --- Meshes and lighting ----------------------------------------------------
func _commit_chunks() -> void:
	for key: Vector2i in _chunks:
		_make_instance("Chunk_%d_%d" % [key.x, key.y], _chunks[key])
	stats["chunks"] = _chunks.size()
	_chunks.clear()


func _make_instance(node_name: String, b: _MeshBucket) -> void:
	if b.v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_COLOR] = b.c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	add_child(mi)
	stats["triangles"] += b.v.size() / 3


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1200.0
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.78, 0.82, 0.87)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = env.background_color
	env.fog_density = 0.00035
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)


## '--stage=N' after '--' on the command line, or '?stage=N' in the web URL.
func _stage_override(fallback: int) -> int:
	var text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			text = arg.get_slice("=", 1)
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('stage') || ''")
		if q is String and q != "":
			text = q
	return clampi(int(text), 0, 3) if text.is_valid_int() else fallback
