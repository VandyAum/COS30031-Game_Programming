class_name City3DTraffic
extends Node3D
## City3DTraffic: demo cars wandering the playable road graph in the 3D
## city test, to see how vehicles read from different cameras. Each car
## keeps the same state the game's crews do (an edge, a distance along it
## and a direction, all 2D). Car 0 drives a ChaseTarget node for the
## camera's chase mode (C).
##
## A terrain version (cars following per-road height profiles, with a slope
## speed factor) is archived in archive/terrain_prototype/.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Add demo traffic to the greybox 3D city: CAR_COUNT cars on random
#    playable edges of roads.json inside the built stage rectangle, random
#    walking through junctions (no U-turns unless it's a dead end), keeping
#    left. Keep each car's state 2D like the game's crews (edge, distance
#    along it, direction) and move it at its road class's speed. Draw them
#    with one MultiMesh. Expose car 0 as a ChaseTarget node and a one-line
#    status (speed, road class) for the FPS panel."
# Follow-up prompt: "Terrain is archived: drop the road height profiles and
#    slope speed factor, keep the cars flat on the roads."

const CAR_COUNT := 150
## Free-flow speed by road class (local, collector, arterial, freeway), km/h.
const SPEED_KMH: Array[float] = [40.0, 50.0, 60.0, 80.0]
## Distance from the centreline to the middle of the left lane, metres.
const LANE_OFFSET_M: Array[float] = [2.0, 2.8, 4.0, 5.0]
const RIDE_HEIGHT := 0.2 + 0.75           # above the road ribbons + half the body
const CLASS_NAMES: Array[String] = ["local", "collector", "arterial", "freeway"]

var status := ""
var chase: Node3D

var _edges: Array[Dictionary] = []      # local edges: pts (m), cum (m), length, a, b, c
var _adj := {}                          # node id -> Array[int] of local edges
var _cars: Array[Dictionary] = []       # e, d, dir
var _mm: MultiMesh
var _rng := RandomNumberGenerator.new()


func setup(city: Node, roads: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	var rect: Rect2 = city.rect_px
	for e: Dictionary in roads["edges"]:
		var pts := PackedVector2Array()
		var inside := true
		for p: Array in e["pts"]:
			var px := Vector2(p[0], p[1])
			inside = inside and rect.has_point(px)
			pts.append(city._m(px))
		if not inside or pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		if cum[cum.size() - 1] < 1.0:
			continue
		var local := _edges.size()
		_edges.append({"pts": pts, "cum": cum, "length": cum[cum.size() - 1],
			"a": int(e["a"]), "b": int(e["b"]), "c": clampi(int(e["c"]), 0, 3)})
		for node in [int(e["a"]), int(e["b"])]:
			if not _adj.has(node):
				_adj[node] = []
			_adj[node].append(local)
	if _edges.is_empty():
		return
	for i in CAR_COUNT:
		var e := _rng.randi_range(0, _edges.size() - 1)
		_cars.append({"e": e, "d": _rng.randf() * _edges[e]["length"], "dir": 1 if _rng.randf() < 0.5 else -1})

	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.5, 4.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.62, 0.15)
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = box
	_mm.instance_count = _cars.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cars"
	mmi.multimesh = _mm
	add_child(mmi)
	chase = Node3D.new()
	chase.name = "ChaseTarget"
	add_child(chase)


func _process(delta: float) -> void:
	for i in _cars.size():
		var car := _cars[i]
		var speed: float = SPEED_KMH[_edges[car["e"]]["c"]] / 3.6
		car["d"] += car["dir"] * speed * delta
		_advance(car)
		var e: Dictionary = _edges[car["e"]]
		var xf := _transform(e, car["d"], car["dir"])
		_mm.set_instance_transform(i, xf)
		if i == 0:
			chase.global_transform = xf
			status = "Chase car: %.0f km/h (%s road)" % [speed * 3.6, CLASS_NAMES[e["c"]]]


# Off the end of the edge: take another edge at that junction.
func _advance(car: Dictionary) -> void:
	for _guard in 8:
		var e: Dictionary = _edges[car["e"]]
		var over := 0.0
		var node := -1
		if car["d"] > e["length"]:
			over = car["d"] - e["length"]
			node = e["b"]
		elif car["d"] < 0.0:
			over = -car["d"]
			node = e["a"]
		else:
			return
		var options: Array = _adj.get(node, []).filter(func(x: int) -> bool: return x != car["e"])
		var next: int = car["e"] if options.is_empty() else options[_rng.randi_range(0, options.size() - 1)]
		var n: Dictionary = _edges[next]
		car["e"] = next
		if n["a"] == node:
			car["dir"] = 1
			car["d"] = over
		else:
			car["dir"] = -1
			car["d"] = n["length"] - over


func _transform(e: Dictionary, d: float, dir: int) -> Transform3D:
	var cum: PackedFloat32Array = e["cum"]
	var pts: PackedVector2Array = e["pts"]
	var i := 0
	while i < cum.size() - 2 and cum[i + 1] < d:
		i += 1
	var seg := maxf(cum[i + 1] - cum[i], 0.001)
	var p := pts[i].lerp(pts[i + 1], clampf((d - cum[i]) / seg, 0.0, 1.0))
	var t := (pts[i + 1] - pts[i]).normalized() * dir
	p += Vector2(t.y, -t.x) * LANE_OFFSET_M[e["c"]]   # keep left (map y points south)
	var forward := Vector3(t.x, 0.0, t.y)
	return Transform3D(Basis.looking_at(forward, Vector3.UP), Vector3(p.x, RIDE_HEIGHT, p.y))
