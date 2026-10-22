extends Node2D
## ScenePhysics: the physical stuff at each scene on the map. Incidents
## scatter the debris their IncidentType lists (a crash: glass, tyres and
## panels); random roadblocks get two concrete barriers across the road and
## debris to match their reason (roadworks: cones, fallen tree: branches).
## Crews' bumpers shove the debris aside when they arrive, and a scene's
## debris fades once it is resolved or the road reopens.
##
## A roadblock is only VISIBLE once the player's map knows the road is
## blocked (Knowledge), and stays until the player sees it has reopened,
## so the physics never gives away what the player hasn't seen.

# AI-assisted (Claude Opus 5.5): written from the prompt in
# Script/Data/debris_type.gd, plus: "ScenePhysics node: load every
#    DebrisType from Data/debris_types. scatter(site, centre, kinds, count,
#    along) drops pieces in a small ring and throws them outward (mostly
#    along the road when a direction is given) so they bounce off each other
#    and the barriers. On Events.incident_spawned scatter the incident's
#    debris; on resolved/failed sweep it with a dust puff. When World blocks
#    a road with no owner, put two barriers across it either side of the
#    middle and scatter debris for the reason between them. Hide roadblocks
#    the player's map doesn't show as blocked, and remove one only once the
#    road is open in truth AND the map no longer shows it blocked."

const PIECE := preload("res://Scenes/debris_piece.tscn")
const BARRIER := preload("res://Scenes/barrier.tscn")

## Debris per World.BLOCK_REASONS reason, and how many pieces.
const ROADBLOCK_DEBRIS := {
	"Roadworks": [[&"cone"], 6],
	"Fallen tree": [[&"branch"], 5],
	"Burst water main": [[&"sandbag"], 5],
	"Broken-down truck": [[&"panel", &"tyre"], 5],
	"Flooded underpass": [[&"sandbag", &"bin"], 5],
}
## Looping particles at a roadblock, per reason.
const ROADBLOCK_FX := {"Burst water main": &"water", "Flooded underpass": &"water"}

## Gap between a roadblock's two barriers (world px).
@export var barrier_gap := 56.0
## Debris launch speed range (world px/s).
@export var launch_speed := Vector2(50.0, 120.0)

var debris_types := {}        # id -> DebrisType
var _incident_sites := {}     # Incident -> Node2D
var _road_sites := {}         # edge -> Node2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for file in ResourceLoader.list_directory("res://Data/debris_types"):
		if file.ends_with(".tres"):
			var t: DebrisType = load("res://Data/debris_types/" + file)
			debris_types[t.id] = t
	Events.incident_spawned.connect(_on_incident_spawned)
	Events.incident_resolved.connect(_clear_incident)
	Events.incident_failed.connect(_clear_incident)
	Events.road_truth_changed.connect(_on_road_truth_changed)
	Events.road_observed.connect(_refresh_road)


## Reusable: throw `count` pieces of the given debris kinds out from centre
## (site-local). With `along` set, most pieces fly along that direction
## (a road), the rest in any direction.
func scatter(site: Node2D, centre: Vector2, kinds: Array, count: int, along := Vector2.ZERO) -> void:
	if kinds.is_empty():
		return
	for i in count:
		var t: DebrisType = debris_types.get(kinds[i % kinds.size()])
		if t == null:
			continue
		var dir := Vector2.RIGHT.rotated(_rng.randf() * TAU)
		if along != Vector2.ZERO and _rng.randf() < 0.75:
			dir = (along * (1.0 if _rng.randf() < 0.5 else -1.0)).rotated(_rng.randf_range(-0.5, 0.5))
		var p: DebrisPiece = PIECE.instantiate()
		p.setup(t)
		p.position = centre + dir * _rng.randf_range(3.0, 9.0)
		p.rotation = _rng.randf() * TAU
		p.linear_velocity = dir * _rng.randf_range(launch_speed.x, launch_speed.y)
		p.angular_velocity = _rng.randf_range(-8.0, 8.0)
		site.add_child(p)


func _new_site(pos: Vector2) -> Node2D:
	var site := Node2D.new()
	site.position = pos
	add_child(site)
	return site


func _clear_site(site: Node2D) -> void:
	if not is_instance_valid(site):
		return
	Fx.burst(self, site.position, &"dust")
	for c in site.get_children():
		if c is DebrisPiece:
			c.sweep()
		elif c is CPUParticles2D:
			c.emitting = false
	var tween := site.create_tween()
	tween.tween_property(site, "modulate:a", 0.0, 0.9)
	tween.tween_callback(site.queue_free)


# --- Incidents ------------------------------------------------------------------

func _on_incident_spawned(inc: Node) -> void:
	var t: IncidentType = inc.type
	if t.debris.is_empty() or t.debris_count <= 0:
		return
	var site := _new_site(inc.global_position)
	var along := Vector2.ZERO
	if inc.road_edge >= 0:
		along = _road_direction(inc.road_edge, inc.global_position)
	scatter(site, Vector2.ZERO, t.debris, t.debris_count, along)
	_incident_sites[inc] = site


func _clear_incident(inc: Node) -> void:
	if _incident_sites.has(inc):
		_clear_site(_incident_sites[inc])
		_incident_sites.erase(inc)


# --- Roadblocks -----------------------------------------------------------------

func _on_road_truth_changed(edge: int) -> void:
	if World.is_blocked(edge) and World.blocked_by(edge) == null and not _road_sites.has(edge):
		_make_roadblock(edge)
	_refresh_road(edge)


func _refresh_road(edge: int) -> void:
	if not _road_sites.has(edge):
		return
	var site: Node2D = _road_sites[edge]
	var map_says_blocked := Knowledge.known_level(edge) == World.Traffic.BLOCKED
	if not World.is_blocked(edge) and not map_says_blocked:
		_road_sites.erase(edge)
		if site.visible:
			_clear_site(site)
		else:
			site.queue_free()
		return
	site.visible = map_says_blocked


func _make_roadblock(edge: int) -> void:
	var length := RoadGraph.edge_length(edge)
	var half_gap := minf(barrier_gap * 0.5, length * 0.35)
	var mid := RoadGraph.point_at(edge, length * 0.5)
	var dir := _road_direction(edge, mid)
	var site := _new_site(mid)
	site.visible = false
	var barrier_len := 22.0 + 5.0 * RoadGraph.edge_class(edge)
	for side in [-1.0, 1.0]:
		var b := BARRIER.instantiate()
		b.setup(barrier_len)
		b.position = RoadGraph.point_at(edge, length * 0.5 + side * half_gap) - mid
		b.rotation = dir.angle() + PI * 0.5
		site.add_child(b)
	var reason := World.block_reason(edge)
	var spec: Array = ROADBLOCK_DEBRIS.get(reason, [[&"cone"], 4])
	scatter(site, Vector2.ZERO, spec[0], spec[1], dir)
	if ROADBLOCK_FX.has(reason):
		site.add_child(Fx.ambient(ROADBLOCK_FX[reason]))
	_road_sites[edge] = site


## Unit direction of a road near a point on it.
func _road_direction(edge: int, near: Vector2) -> Vector2:
	var pts := RoadGraph.edge_pts[edge]
	var best := Vector2.RIGHT
	var best_d := INF
	for i in range(1, pts.size()):
		var d := Geometry2D.get_closest_point_to_segment(near, pts[i - 1], pts[i]).distance_to(near)
		if d < best_d and pts[i] != pts[i - 1]:
			best_d = d
			best = (pts[i] - pts[i - 1]).normalized()
	return best
