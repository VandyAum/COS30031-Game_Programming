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
# Follow-up prompt (OpenStreetMap prototype): "Add OpenStreetMap buildings
#    (Map/world/osm_buildings.json from tools/fetch_osm_buildings.py: per
#    building [kind, height m, height-from-data flag, x0, y0, ...] in map
#    px) as a second building source, to compare with the Vicmap boxes.
#    Three sources: 'vicmap' (the current boxes, sites and footprints),
#    'osm' (OSM outlines at their tagged or estimated heights, plus the
#    flat site tints) and 'hybrid' (OSM where it has a building, Vicmap
#    boxes only for parcels OSM doesn't cover, found with a grid index of
#    the OSM outlines). Build the ground, water, parks and roads once; build
#    each source lazily into its own node so O can switch between them
#    without rebuilding. Pick the starting source with the building_source
#    export, '--buildings=osm' or '?buildings=hybrid'. Keep the stats the
#    FPS probe shows correct for whichever source is visible."
# Follow-up prompt (hybrid overlaps + lessons from OSM): "In hybrid mode some
#    Vicmap shop boxes still stand between OSM buildings. Compare shapes by
#    overlapping area instead of centre points. Then measure real OSM
#    buildings against the Vicmap parcels they stand on (size, lot cover,
#    setback, width, orientation, storeys by land use and distance from the
#    junction) and recalibrate the Vicmap box heights to match."
# Follow-up prompt: "osm_buildings.json records are now [kind, base m, top m,
#    from data, x0, y0, ...] (building parts can start above a podium):
#    extrude from base to top and give lifted shapes an underside."
# Follow-up prompt (terrain prototype): "Add optional terrain from
#    Map/world/terrain.bin / terrain.json (tools/build_terrain.py): a 10 m
#    height grid with a land-cover byte, and a height profile every 5 m
#    along every road. When terrain is on, the ground is a chunked grid mesh
#    tinted by cover (so parks, water and sites need no slabs), roads are
#    ribbons that follow their profiles (the same profiles the simulation
#    would use), and every building stands at the lowest ground under it
#    with its roof at mean ground + height. Heights are relative to the
#    junction so the camera's numbers stay familiar. Expose ground_height()
#    and road_height() for the camera and the demo traffic. T toggles
#    terrain by reloading the scene (keeping the building source); start
#    with it on via '--terrain' or '?terrain=1'."

const META_PATH := "res://Map/world/world_meta.json"
const TERRAIN_JSON := "res://Map/world/terrain.json"
const TERRAIN_BIN := "res://Map/world/terrain.bin"
const COVER_COL: Array[Color] = [Color(0.33, 0.33, 0.32), Color(0.30, 0.38, 0.28),
	Color(0.22, 0.30, 0.38), Color(0.42, 0.42, 0.40)]   # ground, park, water, site

## Terrain on/off survives the T-key reload; -1 = not decided yet.
static var _terrain_choice := -1
static var _reload_source := ""
const OSM_PATH := "res://Map/world/osm_buildings.json"
const SOURCES: Array[String] = ["vicmap", "osm", "hybrid"]
const OSM_CELL_PX := 40.0               # grid cell for the hybrid coverage test
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
## Where buildings come from: Vicmap parcel boxes, OpenStreetMap, or both.
@export_enum("vicmap", "osm", "hybrid") var building_source := "vicmap"

var px_per_m := 0.75
var origin_px := Vector2.ZERO           # Cambermere Junction, in map pixels
var rect_px := Rect2()                  # the area being built, map pixels
## What the FPS probe shows; describes the visible source plus the base.
var stats := {"source": "", "buildings": 0, "osm": 0, "osm_tagged": 0, "footprints": 0, "sites": 0,
	"roads": 0, "triangles": 0, "chunks": 0, "build_ms": 0}

var _chunks := {}                       # Vector2i -> _MeshBucket
var _material: StandardMaterial3D
var _count := {}                        # counters while one source is built
var _base := {"triangles": 0, "chunks": 0, "build_ms": 0}
var _sources := {}                      # source name -> {"node": Node3D, "stats": Dictionary}
var _osm_polys: Array[PackedVector2Array] = []   # OSM outlines in map px (built once)
var _osm_grid := {}                     # Vector2i cell -> Array of _osm_polys indices

var terrain_on := false
var _terrain := {}                      # terrain.json (grid size + road profiles)
var _heights := PackedFloat32Array()    # metres above the junction, row-major
var _cover := PackedByteArray()
var _tnx := 0
var _tny := 0
var _tcell := 10.0
var _datum := 0.0                       # ground height at the junction (AHD m)


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
	building_source = _source_override(building_source)
	if _reload_source != "":
		building_source = _reload_source
	if _terrain_choice < 0:
		_terrain_choice = 1 if _terrain_override() else 0
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	px_per_m = float(meta["px_per_m"])
	var r0: Array = meta["stage_rects"][0]
	origin_px = Vector2((r0[0] + r0[2]) * 0.5, (r0[1] + r0[3]) * 0.5)
	var r: Array = meta["stage_rects"][stage_extent]
	rect_px = Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])
	terrain_on = _terrain_choice == 1 and _load_terrain()
	stats["terrain"] = terrain_on

	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95

	# Base layer, shared by every building source.
	_count = {"roads": 0, "triangles": 0}
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	if terrain_on:
		_add_terrain_ground()               # cover tints replace the flat slabs
	else:
		_add_ground()
		var areas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AREAS_PATH))
		_add_flat_polygons(areas["water"], WATER, 0.03)
		_add_flat_polygons(areas["parks"], PARK, 0.06)
	_add_roads(roads)
	_base["chunks"] = _commit_chunks(self)
	_base["triangles"] = _count["triangles"]
	stats["roads"] = _count["roads"]
	_add_lighting()
	_base["build_ms"] = Time.get_ticks_msec() - t0
	show_source(building_source)
	_add_traffic(roads)


func _add_traffic(roads: Dictionary) -> void:
	var traffic := City3DTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	traffic.setup(self, roads)


# --- Terrain ------------------------------------------------------------------
func _load_terrain() -> bool:
	if not FileAccess.file_exists(TERRAIN_JSON) or not FileAccess.file_exists(TERRAIN_BIN):
		push_warning("City3D: terrain files missing; run tools/build_terrain.py")
		return false
	_terrain = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN_JSON))
	_tnx = int(_terrain["nx"])
	_tny = int(_terrain["ny"])
	_tcell = float(_terrain["cell_m"])
	var bytes := FileAccess.get_file_as_bytes(TERRAIN_BIN)
	var n := _tnx * _tny
	_heights.resize(n)
	for k in n:
		_heights[k] = bytes.decode_u16(k * 2) * 0.1
	_cover = bytes.slice(n * 2, n * 3)
	_datum = 0.0
	_datum = ground_height(Vector2.ZERO)
	for k in n:
		_heights[k] -= _datum
	return true


## Ground height (metres above the junction) at a point in scene metres
## (x east, z south of the junction). 0 everywhere without terrain.
func ground_height(p_m: Vector2) -> float:
	if _heights.is_empty():
		return 0.0
	var g := (p_m + origin_px / px_per_m) / _tcell
	var fx := clampf(g.x, 0.0, _tnx - 1.001)
	var fy := clampf(g.y, 0.0, _tny - 1.001)
	var i := int(fx)
	var j := int(fy)
	var tx := fx - i
	var ty := fy - j
	var k := j * _tnx + i
	return lerpf(lerpf(_heights[k], _heights[k + 1], tx), lerpf(_heights[k + _tnx], _heights[k + _tnx + 1], tx), ty)


## Road surface height 'dist' metres along road 'index' of roads.json list
## 'list_name' ("edges" or "decor"), from the shared road profiles.
func road_height(list_name: String, index: int, dist: float) -> float:
	if _terrain.is_empty():
		return 0.0
	var prof: Array = _terrain["roads"][list_name][index]
	var f := clampf(dist / float(_terrain["road_step_m"]), 0.0, prof.size() - 1.001)
	var i := int(f)
	return lerpf(float(prof[i]), float(prof[mini(i + 1, prof.size() - 1)]), f - i) * 0.1 - _datum


func _add_terrain_ground() -> void:
	var e := extent_m().grow(40.0)
	var off := origin_px / px_per_m
	var i0 := maxi(0, floori((e.position.x + off.x) / _tcell))
	var i1 := mini(_tnx - 1, ceili((e.end.x + off.x) / _tcell))
	var j0 := maxi(0, floori((e.position.y + off.y) / _tcell))
	var j1 := mini(_tny - 1, ceili((e.end.y + off.y) / _tcell))
	for j in range(j0, j1):
		for i in range(i0, i1):
			var k := j * _tnx + i
			var p00 := Vector3(i * _tcell - off.x, _heights[k], j * _tcell - off.y)
			var p10 := Vector3(p00.x + _tcell, _heights[k + 1], p00.z)
			var p01 := Vector3(p00.x, _heights[k + _tnx], p00.z + _tcell)
			var p11 := Vector3(p00.x + _tcell, _heights[k + _tnx + 1], p00.z + _tcell)
			var col: Color = COVER_COL[mini(_cover[k], 3)]
			var bucket := _bucket(Vector2(p00.x, p00.z))
			var n1 := (p10 - p00).cross(p01 - p00).normalized()
			if n1.y < 0.0:
				n1 = -n1
			var n2 := (p01 - p11).cross(p10 - p11).normalized()
			if n2.y < 0.0:
				n2 = -n2
			bucket.tri(p00, p10, p01, n1, col)
			bucket.tri(p11, p01, p10, n2, col)


## T: rebuild the scene with terrain switched (keeps the building source).
func toggle_terrain() -> void:
	_terrain_choice = 0 if terrain_on else 1
	_reload_source = building_source
	get_tree().reload_current_scene()


func _terrain_override() -> bool:
	if "--terrain" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('terrain') || ''")) == "1"
	return false


## Shows one building source, building it the first time it is asked for.
func show_source(source: String) -> void:
	if not SOURCES.has(source):
		source = "vicmap"
	if not _sources.has(source):
		_sources[source] = _build_source(source)
	for key: String in _sources:
		_sources[key]["node"].visible = key == source
	building_source = source
	var s: Dictionary = _sources[source]["stats"]
	for key: String in s:
		stats[key] = s[key]
	stats["source"] = source
	stats["triangles"] = _base["triangles"] + s["triangles"]
	stats["chunks"] = _base["chunks"] + s["chunks"]
	stats["build_ms"] = _base["build_ms"] + s["build_ms"]
	print("City3D [%s]: stage %d extent %.0f x %.0f m, %d Vicmap boxes, %d OSM buildings (%d with real heights), %d footprints, %d sites, %d road segments, %d triangles in %d chunks, built in %d ms" % [
		source, stage_extent, rect_px.size.x / px_per_m, rect_px.size.y / px_per_m, stats["buildings"], stats["osm"],
		stats["osm_tagged"], stats["footprints"], stats["sites"], stats["roads"], stats["triangles"], stats["chunks"],
		stats["build_ms"]])


## O cycles the building source (vicmap -> osm -> hybrid).
func next_source() -> void:
	show_source(SOURCES[(SOURCES.find(building_source) + 1) % SOURCES.size()])


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_O:
		next_source()
	elif k and k.pressed and not k.echo and k.keycode == KEY_T:
		toggle_terrain()


func _build_source(source: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_count = {"buildings": 0, "osm": 0, "osm_tagged": 0, "footprints": 0, "sites": 0, "triangles": 0}
	var hybrid := source == "hybrid"
	if source != "vicmap" and _osm_polys.is_empty():
		_load_osm()
	if source != "vicmap":
		_add_osm()
	_add_buildings(FileAccess.get_file_as_bytes(BUILDINGS_PATH), source != "osm", hybrid)
	if source == "vicmap" or hybrid:
		var areas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AREAS_PATH))
		_add_footprints(areas["footprints"], hybrid)
	var node := Node3D.new()
	node.name = "Buildings_" + source
	add_child(node)
	var s := _count.duplicate()
	s["chunks"] = _commit_chunks(node)
	s["triangles"] = _count["triangles"]
	s["build_ms"] = Time.get_ticks_msec() - t0
	return {"node": node, "stats": s}


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
## With terrain, each segment is cut into pieces of at most the profile step
## and each piece's ends take their height from the road's profile.
func _add_roads(roads: Dictionary) -> void:
	var step: float = float(_terrain.get("road_step_m", 5.0))
	for list_name: String in ["edges", "decor"]:
		var list: Array = roads[list_name]
		for idx in list.size():
			var e: Dictionary = list[idx]
			var w: float = ROAD_WIDTH_M[clampi(int(e["c"]), 0, 3)] * 0.5
			var lift := 0.1 + 0.02 * float(e["c"]) + (0.25 if terrain_on else 0.0)   # bigger roads on top
			var pts: Array = e["pts"]
			var cum := 0.0                      # metres along the unclipped polyline
			for i in pts.size() - 1:
				var p0 := Vector2(pts[i][0], pts[i][1])
				var p1 := Vector2(pts[i + 1][0], pts[i + 1][1])
				var seg_m := p0.distance_to(p1) / px_per_m
				var clipped := _clip_segment(p0, p1)
				if clipped.is_empty() or clipped[0].is_equal_approx(clipped[1]):
					cum += seg_m
					continue
				var d0 := cum + p0.distance_to(clipped[0]) / px_per_m
				var d1 := cum + p0.distance_to(clipped[1]) / px_per_m
				cum += seg_m
				var a := _m(clipped[0])
				var b := _m(clipped[1])
				var dir := (b - a).normalized()
				var side := Vector2(-dir.y, dir.x) * w
				var pieces := maxi(1, ceili((d1 - d0) / step)) if terrain_on else 1
				var bucket := _bucket((a + b) * 0.5)
				for s in pieces:
					var t0 := float(s) / pieces
					var t1 := float(s + 1) / pieces
					var pa := a.lerp(b, t0)
					var pb := a.lerp(b, t1)
					var za := road_height(list_name, idx, lerpf(d0, d1, t0)) + lift
					var zb := road_height(list_name, idx, lerpf(d0, d1, t1)) + lift
					# Extend the segment's outer ends by half a width so bends don't gap.
					if s == 0:
						pa -= dir * w * 0.5
					if s == pieces - 1:
						pb += dir * w * 0.5
					bucket.tri(_v3(pa + side, za), _v3(pb + side, zb), _v3(pb - side, zb), Vector3.UP, ROAD)
					bucket.tri(_v3(pa + side, za), _v3(pb - side, zb), _v3(pa - side, za), Vector3.UP, ROAD)
				_count["roads"] += 1


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
## boxes: false keeps only the flat site tints. skip_covered: drop boxes that
## an OSM building already stands on (hybrid).
func _add_buildings(bytes: PackedByteArray, boxes := true, skip_covered := false) -> void:
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
			if not terrain_on:                  # with terrain the ground cover tints sites
				_add_slab(tris, 0.18, SITE_GREY)
			_count["sites"] += 1
		elif boxes and not (skip_covered and _osm_covers(centre, tris)):
			var area_m2 := 0.0
			for t in range(0, tris.size(), 3):
				area_m2 += absf((tris[t + 1] - tris[t]).cross(tris[t + 2] - tris[t])) * 0.5
			_extrude(tris, _height_for(kind, centre, area_m2 / (px_per_m * px_per_m)), KIND_GREY[kind])
			_count["buildings"] += 1


## Greybox heights in metres. Vicmap parcels have no heights, so the storey
## counts are drawn (stable per building) from what OpenStreetMap's
## building:levels tags show for Cambermere (tools/fetch_osm_buildings.py,
## 2,567 tagged houses and 121 tagged shops in stage 1):
##   houses: 62% one storey, 37% two; two storeys are likelier on bigger
##     footprints (30% under 200 m2 real, 48% over 300 m2) and near the
##     junction (66% within 300 m). Our boxes are ~1.5x the real footprint,
##     so box areas are scaled down before the lookup.
##   shops: median two storeys (33% one, 57% two), with the only 4+ storey
##     buildings within ~700 m of the junction (10% of them). The old rule
##     (7-33 m, taller towards the junction) made towers that aren't there.
func _height_for(kind: int, centre_px: Vector2, box_m2 := 0.0) -> float:
	var h := _hash01(centre_px)
	var h2 := _hash01(centre_px.rotated(1.0) + Vector2(17.0, 3.0))   # independent jitter
	var dist := _m(centre_px).length()
	match kind:
		0:   # residential
			var real_m2 := box_m2 * 0.67
			var p2 := 0.30 if real_m2 < 200.0 else (0.41 if real_m2 < 300.0 else 0.48)
			if dist < 300.0:
				p2 = 0.66
			return (7.0 if h < p2 else 4.0) + h2 * 0.8
		1:   # commercial strip
			var tall := 0.10 if dist < 700.0 else 0.0
			if h < tall:
				return 13.0 + h2 * 6.0                   # 4-6 storeys
			return (4.5 if h < tall + 0.33 else 8.0) + h2 * 0.8
		2:   # public: schools, civic, two-three storeys
			return 7.0 + h * 3.0
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
## 'base' lifts the walls off the ground (OSM building parts that start
## above a podium); a lifted shape also gets an underside.
func _extrude(tris: PackedVector2Array, height: float, col: Color, base := 0.0) -> void:
	var uses := {}
	for t in range(0, tris.size(), 3):
		for k in 3:
			var key := _edge_key(tris[t + k], tris[t + (k + 1) % 3])
			uses[key] = uses.get(key, 0) + 1
	var bucket := _bucket(_m(tris[0]))
	var wall_col := col.darkened(0.08)
	var lifted := base > 0.0
	if terrain_on:
		# Stand on the lowest ground under the shape (walls sink a little into
		# the slope); the roof sits 'height' above the average ground.
		var g_min := INF
		var g_sum := 0.0
		for p in tris:
			var g := ground_height(_m(p))
			g_min = minf(g_min, g)
			g_sum += g
		var g_mean := g_sum / tris.size()
		base = g_mean + base if lifted else g_min - 0.3
		height += g_mean
	for t in range(0, tris.size(), 3):
		var a := _m(tris[t])
		var b := _m(tris[t + 1])
		var c := _m(tris[t + 2])
		bucket.tri(_v3(a, height), _v3(b, height), _v3(c, height), Vector3.UP, col)
		if lifted:
			bucket.tri(_v3(a, base), _v3(b, base), _v3(c, base), Vector3.DOWN, wall_col)
		for k in 3:
			var p := tris[t + k]
			var q := tris[t + (k + 1) % 3]
			if uses[_edge_key(p, q)] != 1:
				continue
			var opposite := _m(tris[t + (k + 2) % 3])
			_wall(bucket, _m(p), _m(q), opposite, height, wall_col, base)


func _wall(bucket: _MeshBucket, a: Vector2, b: Vector2, inside: Vector2, height: float, col: Color,
		base := 0.0) -> void:
	var d := b - a
	var n2 := Vector2(-d.y, d.x).normalized()
	if n2.dot(inside - a) > 0.0:
		n2 = -n2
	var n := Vector3(n2.x, 0.0, n2.y)
	bucket.tri(_v3(a, base), _v3(b, base), _v3(b, height), n, col)
	bucket.tri(_v3(a, base), _v3(b, height), _v3(a, height), n, col)


func _edge_key(p: Vector2, q: Vector2) -> Vector4:
	return Vector4(p.x, p.y, q.x, q.y) if (p.x < q.x or (p.x == q.x and p.y < q.y)) else Vector4(q.x, q.y, p.x, p.y)


# --- Real Vicmap building footprints (outlines in areas.json) --------------
func _add_footprints(footprints: Array, skip_covered := false) -> void:
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
		if skip_covered and _osm_covers(centre, tris):
			continue
		# Big footprints are schools and shopping centres: a bit taller.
		var area_m2 := absf(_signed_area(pts)) / (px_per_m * px_per_m)
		var height := clampf(5.0 + sqrt(area_m2) * 0.12, 6.0, 16.0) + _hash01(centre) * 2.0
		_extrude(tris, height, FOOTPRINT_GREY)
		_count["footprints"] += 1


# --- OpenStreetMap buildings (osm_buildings.json) ---------------------------
## Reads the outlines inside the built area once and indexes them on a grid
## for the hybrid coverage test. Heights and kinds live alongside.
var _osm_meta: Array[Vector4] = []      # per outline: kind, base m, top m, from data 0/1


func _load_osm() -> void:
	if not FileAccess.file_exists(OSM_PATH):
		push_warning("City3D: %s missing; run tools/fetch_osm_buildings.py" % OSM_PATH)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OSM_PATH))
	for rec: Array in data["buildings"]:
		var pts := PackedVector2Array()
		for j in range(4, rec.size() - 1, 2):
			pts.append(Vector2(rec[j], rec[j + 1]))
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		if not rect_px.intersects(box):
			continue
		var index := _osm_polys.size()
		_osm_polys.append(pts)
		_osm_meta.append(Vector4(rec[0], rec[1], rec[2], rec[3]))
		for cx in range(floori(box.position.x / OSM_CELL_PX), floori(box.end.x / OSM_CELL_PX) + 1):
			for cy in range(floori(box.position.y / OSM_CELL_PX), floori(box.end.y / OSM_CELL_PX) + 1):
				var cell := Vector2i(cx, cy)
				if not _osm_grid.has(cell):
					_osm_grid[cell] = []
				_osm_grid[cell].append(index)


func _add_osm() -> void:
	for i in _osm_polys.size():
		var pts := _osm_polys[i]
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= float(pts.size())
		if not rect_px.has_point(centre):
			continue
		var idx := Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			continue                        # self-crossing outline: no roof possible
		var tris := PackedVector2Array()
		for k in idx:
			tris.append(pts[k])
		var m := _osm_meta[i]
		_extrude(tris, m.z, KIND_GREY[clampi(int(m.x), 0, 3)], m.y)
		_count["osm"] += 1
		_count["osm_tagged"] += int(m.w)


## True if an OSM building stands on this Vicmap shape. Shapes are compared
## by overlapping area, not centre points: a shop box centred on its lot
## often misses the real shop at the front of the lot, and a big OSM block
## spanning several lots has its centre in only one of them. Drop the box if
## OSM covers OSM_OVERLAP of it, or it covers OSM_OVERLAP of an OSM building
## (a small house fully under a big box).
const OSM_OVERLAP := 0.15


func _osm_covers(centre: Vector2, tris: PackedVector2Array) -> bool:
	var outline := Geometry2D.convex_hull(tris)   # boxes are (near) convex
	var area := absf(_signed_area(outline))
	if area <= 0.0:
		return false
	var box := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		box = box.expand(p)
	var covered := 0.0
	var seen := {}
	for cx in range(floori(box.position.x / OSM_CELL_PX), floori(box.end.x / OSM_CELL_PX) + 1):
		for cy in range(floori(box.position.y / OSM_CELL_PX), floori(box.end.y / OSM_CELL_PX) + 1):
			for i: int in _osm_grid.get(Vector2i(cx, cy), []):
				if seen.has(i):
					continue
				seen[i] = true
				var poly := _osm_polys[i]
				if Geometry2D.is_point_in_polygon(centre, poly):
					return true
				var shared := 0.0
				for part in Geometry2D.intersect_polygons(outline, poly):
					shared += absf(_signed_area(part))
				if shared <= 0.0:
					continue
				if shared >= OSM_OVERLAP * absf(_signed_area(poly)):
					return true
				covered += shared
				if covered >= OSM_OVERLAP * area:
					return true
	return false


func _signed_area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


# --- Meshes and lighting ----------------------------------------------------
## Turns the pending chunks into meshes under 'parent'; returns how many.
func _commit_chunks(parent: Node) -> int:
	for key: Vector2i in _chunks:
		_make_instance("Chunk_%d_%d" % [key.x, key.y], _chunks[key], parent)
	var n := _chunks.size()
	_chunks.clear()
	return n


func _make_instance(node_name: String, b: _MeshBucket, parent: Node = self) -> void:
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
	parent.add_child(mi)
	_count["triangles"] += b.v.size() / 3


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


## '--buildings=osm' on the command line, or '?buildings=hybrid' in the web URL.
func _source_override(fallback: String) -> String:
	var text := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--buildings="):
			text = arg.get_slice("=", 1)
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('buildings') || ''")
		if q is String and q != "":
			text = q
	return text if SOURCES.has(text) else fallback
