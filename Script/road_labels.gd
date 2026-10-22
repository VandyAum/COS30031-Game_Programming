extends Node2D
## RoadLabels: street names drawn along the roads, like Google Maps. Main
## roads are named when zoomed out; collectors, then local streets, appear
## as you zoom in. Labels keep a constant size on screen, follow the road's
## direction (never upside down) and never overlap each other.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Show road names on the roads like Google Maps when zoomed in, and only
#    on major roads when more zoomed out. Write a Godot 4.7 Node2D for the
#    dispatch game that reads the playable road graph (RoadGraph autoload:
#    edge_pts, edge_name, edge_cls, edge_stage). Join consecutive edges of
#    the same name into one polyline per street, cut it into straight runs
#    (direction changes under ~12 degrees), and use those runs as label
#    spots. On draw, take the camera's visible rectangle and zoom: show
#    arterials/freeways from MAJOR_ZOOM, collectors from COLLECTOR_ZOOM and
#    local streets from LOCAL_ZOOM; only label a run inside the current
#    stage that is long enough for the text at this zoom; draw the text at
#    a fixed screen size through a rotate+scale transform, flipped so it
#    reads left to right, with a white halo; place the most important
#    (biggest class, longest run) first and skip any label that would
#    overlap one already placed or repeat the same name too close by.
#    Redraw only when the camera moves or zooms or the stage changes."

const FONT_SIZE := 14
const MAJOR_ZOOM := 0.3
const COLLECTOR_ZOOM := 0.6
const LOCAL_ZOOM := 1.0
## Same name again no closer than this (screen px).
const REPEAT_SPACING := 450.0
const STRAIGHT_TOLERANCE := deg_to_rad(12.0)
const TEXT := Color("3d4350")
const HALO := Color(1, 1, 1, 0.9)

var _runs: Array = []      # {name, cls, stage, a, b, len} sorted by importance
var _last_view := Rect2()
var _last_zoom := -1.0
var _last_stage := -1


func _ready() -> void:
	_build_runs()
	Events.stage_changed.connect(func(_s: int) -> void: queue_redraw())


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view := _view_rect(cam)
	if view != _last_view or cam.zoom.x != _last_zoom or Stage.current != _last_stage:
		_last_view = view
		_last_zoom = cam.zoom.x
		_last_stage = Stage.current
		queue_redraw()


func _view_rect(cam: Camera2D) -> Rect2:
	var size := get_viewport_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size / 2.0, size)


# --- Building label spots -------------------------------------------------------

func _build_runs() -> void:
	# Group edges by street name, then walk each street's chains.
	var by_name := {}
	for e in RoadGraph.edge_count():
		var n := RoadGraph.edge_name[e]
		if n == "" or n == "Unnamed":
			continue
		if not by_name.has(n):
			by_name[n] = []
		by_name[n].append(e)
	for n: String in by_name:
		for chain in _chains(by_name[n]):
			_add_runs(n, chain)
	_runs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x["cls"] > y["cls"] if x["cls"] != y["cls"] else x["len"] > y["len"])


# Split one street's edges into chains (polylines) that continue through
# nodes where exactly two of its edges meet. Returns [[points, cls, stage], ...].
func _chains(edges: Array) -> Array:
	var at_node := {}
	for e: int in edges:
		for n in [RoadGraph.edge_a[e], RoadGraph.edge_b[e]]:
			if not at_node.has(n):
				at_node[n] = []
			at_node[n].append(e)
	var used := {}
	var out := []
	for start: int in edges:
		if used.has(start):
			continue
		# Walk back to an end of this chain first.
		var e := start
		var node := RoadGraph.edge_a[e]
		var guard := 0
		while at_node[node].size() == 2 and guard < 500:
			var other: int = at_node[node][0] if at_node[node][1] == e else at_node[node][1]
			if other == start:
				break
			e = other
			node = RoadGraph.edge_b[e] if RoadGraph.edge_a[e] == node else RoadGraph.edge_a[e]
			guard += 1
		# Now walk forward from `node` collecting points.
		var pts := PackedVector2Array()
		var cls := 0
		var stage := 0
		while not used.has(e):
			used[e] = true
			var p := RoadGraph.edge_pts[e]
			if RoadGraph.edge_a[e] != node:
				p = p.duplicate()
				p.reverse()
			pts.append_array(p if pts.is_empty() else p.slice(1))
			cls = maxi(cls, RoadGraph.edge_cls[e])
			stage = maxi(stage, RoadGraph.edge_stage[e])
			node = RoadGraph.edge_b[e] if RoadGraph.edge_a[e] == node else RoadGraph.edge_a[e]
			if at_node[node].size() != 2:
				break
			e = at_node[node][0] if at_node[node][1] == e else at_node[node][1]
		out.append([pts, cls, stage])
	return out


# Cut a chain into straight runs and keep each as a label spot.
func _add_runs(street: String, chain: Array) -> void:
	var pts: PackedVector2Array = chain[0]
	var i := 0
	while i < pts.size() - 1:
		var j := i + 1
		var dir := (pts[j] - pts[i]).angle()
		while j < pts.size() - 1 and absf(angle_difference(dir, (pts[j + 1] - pts[j]).angle())) < STRAIGHT_TOLERANCE:
			j += 1
		var length := pts[i].distance_to(pts[j])
		if length > 20.0:
			_runs.append({"name": street, "cls": chain[1], "stage": chain[2], "a": pts[i], "b": pts[j], "len": length,
				"w": _text_width(street)})
		i = j


var _widths := {}

func _text_width(text: String) -> float:
	if not _widths.has(text):
		_widths[text] = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return _widths[text]


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	if _last_zoom <= 0.0 or _last_zoom < MAJOR_ZOOM:
		return
	var min_cls := 2 if _last_zoom < COLLECTOR_ZOOM else (1 if _last_zoom < LOCAL_ZOOM else 0)
	var s := 1.0 / _last_zoom                      # world px per screen px
	var font := ThemeDB.fallback_font
	var view := _last_view.grow(50.0 * s)
	var placed: Array[Rect2] = []                  # world-space boxes (axis-aligned bounds)
	var named := {}                                # name -> [centres]
	for run: Dictionary in _runs:
		if run["cls"] < min_cls or run["stage"] > Stage.current:
			continue
		if run["len"] < (run["w"] + 16.0) * s:
			continue                                # road too short for the text here
		var a: Vector2 = run["a"]
		var b: Vector2 = run["b"]
		var mid := (a + b) / 2.0
		if not view.has_point(mid):
			continue
		var text: String = run["name"]
		var w: float = run["w"]
		if run["len"] < (w + 16.0) * s:
			continue                                # road too short for the text here
		var close := false
		for c: Vector2 in named.get(text, []):
			if c.distance_to(mid) < REPEAT_SPACING * s:
				close = true
				break
		if close:
			continue
		var angle := (b - a).angle()
		if angle > PI / 2.0 or angle <= -PI / 2.0:
			angle = wrapf(angle + PI, -PI, PI)         # keep text upright
		var half := Vector2(w / 2.0 + 4.0, FONT_SIZE * 0.7) * s
		var box := _rotated_bounds(mid, half, angle)
		if placed.any(func(r: Rect2) -> bool: return r.intersects(box)):
			continue
		placed.append(box)
		if not named.has(text):
			named[text] = []
		named[text].append(mid)
		draw_set_transform(mid, angle, Vector2(s, s))
		var at := Vector2(-w / 2.0, FONT_SIZE * 0.35)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, HALO)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	draw_set_transform(Vector2.ZERO)


func _rotated_bounds(centre: Vector2, half: Vector2, angle: float) -> Rect2:
	var c := absf(cos(angle))
	var sn := absf(sin(angle))
	var ext := Vector2(half.x * c + half.y * sn, half.x * sn + half.y * c)
	return Rect2(centre - ext, ext * 2.0)
