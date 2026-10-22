extends Node
## Director: plays the game by script for the showcase video, in sync with
## the recorded narration. Each "shot" is a coroutine written against the
## narration's own timestamps (seconds into the recording), so a shot that
## starts at 100.2 s waits for at(115.5) to act on "you draw each route".
##
## It drives the game through the game's own code paths: routes are traced
## with the route drawer's sampling (snap, extend, despur) exactly as a held
## mouse would, incidents are real Incident nodes, blockages go through
## World.block, stage changes through Stage.set_stage. A drawn cursor shows
## where the "mouse" is, since Movie Maker doesn't capture the OS cursor.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Take the narration transcript and record gameplay video to sync
#    alongside it."

const FPS := 30.0
const ACCENT := Color("ffd23f")

var shot := "showcase"
## Narration time of the current frame.
var now := 0.0
var _running := false

var main: Node2D
var cam: Camera2D
var drawer: Node2D
var manager: Node2D
var stations: Node2D
var tutorial: CanvasLayer
var hud: Control
var physics: Node2D

var _overlay: CanvasLayer
var _marks: Control
var cursor := Vector2(-200, -200)       # screen px
var cursor_down := false
var cursor_shown := false
var _ripples: Array = []                # [{pos, t}]
var _highlights: Array = []             # [{rect: Callable, until: float, circle: bool}]
var title := ""
var subtitle := ""
var title_alpha := 0.0
## Short on-screen label at the top of the map (empty = none).
var caption := ""
var _truth: Node2D
var _follow: Node2D
var _follow_until := 0.0
## Incident -> timer seconds held fixed (a demo ring stops filling).
var _frozen := {}
var _cam_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.substr(5)
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	add_child(_overlay)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_overlay.add_child(_marks)

	while get_tree().current_scene == null or get_tree().current_scene.name != "Main":
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _settle_window()
	main = get_tree().current_scene
	cam = main.get_node("Camera2D")
	drawer = main.get_node("Drawing")
	manager = main.get_node("Incidents")
	stations = main.get_node("Stations")
	tutorial = main.get_node("Tutorial")
	hud = main.get_node("UI/HUD")
	physics = main.get_node("ScenePhysics")
	cam._fit_stage(Stage.current, false)      # the window size changed after it framed

	# The director decides when things happen.
	manager.set_process(false)
	World._block_timer = 1.0e9
	World.rng.seed = 30031
	World.reset()
	physics._rng.seed = 7

	print("DIRECTOR shot=%s start_frame=%d window=%s viewport=%s scale=%s" % [shot, Engine.get_process_frames(), DisplayServer.window_get_size(), get_viewport().get_visible_rect().size, DisplayServer.screen_get_scale()])
	await call("shot_" + shot)
	print("DIRECTOR done frame=%d" % Engine.get_process_frames())
	get_tree().quit()


## The project's fullscreen setting is applied a few frames after launch on
## macOS, and Movie Maker then records a 1920x1080 corner of the bigger
## window. Hold the game paused, keep forcing a 1920x1080 window, and only
## start once it has stayed that way for a second.
func _settle_window() -> void:
	get_tree().paused = true
	var want := Vector2i(1920, 1080)
	var stable := 0
	while stable < 30:
		await get_tree().process_frame
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			stable = 0
		elif DisplayServer.window_get_size() != want:
			DisplayServer.window_set_size(want)
			stable = 0
		else:
			stable += 1
	get_tree().paused = false


func _process(_delta: float) -> void:
	# Movie Maker runs at a fixed frame rate; count frames, so fast-forward
	# (Engine.time_scale) doesn't speed up the narration clock.
	if _running:
		now += 1.0 / FPS
	if _follow and is_instance_valid(_follow) and now < _follow_until:
		var offset := Vector2(cam.ui_inset.x, cam.ui_inset.y - cam.ui_inset_bottom) / 2.0
		var target := _follow.global_position - offset / cam.zoom.x
		cam.position = cam.position.lerp(target, 0.12)
	for inc in _frozen.keys():
		if is_instance_valid(inc):
			inc.elapsed_active = _frozen[inc]
	if _truth:
		_truth.queue_redraw()
	_marks.queue_redraw()


# --- Timing ---------------------------------------------------------------

## Start the shot clock at this narration time.
func begin(narration_time: float) -> void:
	now = narration_time
	_running = true
	print("DIRECTOR begin narration=%.2f frame=%d" % [narration_time, Engine.get_process_frames()])


func at(t: float) -> void:
	while now < t:
		await get_tree().process_frame


func frame() -> void:
	await get_tree().process_frame


# --- Lookups ----------------------------------------------------------------

func station(named: String) -> Station:
	for s: Station in stations.get_stations():
		if s.station_name == named:
			return s
	push_error("No station " + named)
	return null


func type_of(id: StringName) -> IncidentType:
	for t: IncidentType in manager.types:
		if t.id == id:
			return t
	return null


func screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


# --- Camera -------------------------------------------------------------------

func _free_camera() -> void:
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.limit_right = 100000
	cam.limit_bottom = 100000


## Glide so `centre` sits in the middle of the map area (right of the HUD).
func cam_to(centre: Vector2, zoom: float, seconds := 1.5) -> void:
	_free_camera()
	if cam._stage_tween:
		cam._stage_tween.kill()
	if _cam_tween:
		_cam_tween.kill()
	var offset := Vector2(cam.ui_inset.x, cam.ui_inset.y - cam.ui_inset_bottom) / 2.0
	var z0 := cam.zoom.x
	var p0 := cam.position
	if seconds <= 0.0:
		cam.zoom = Vector2(zoom, zoom)
		cam.position = centre - offset / zoom
		return
	_cam_tween = create_tween().set_ignore_time_scale(true)
	_cam_tween.tween_method(func(t: float) -> void:
		var z := exp(lerpf(log(z0), log(zoom), t))
		cam.zoom = Vector2(z, z)
		cam.position = p0.lerp(centre - offset / zoom, t),
		0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Frame a world rectangle in the map area.
func cam_fit(r: Rect2, seconds := 1.5, margin := 0.92) -> void:
	var f: Dictionary = cam._framing(r)
	cam_to(r.get_center(), f["zoom"] * margin / cam.fit_margin, seconds)


# --- Cursor -------------------------------------------------------------------

func move_cursor(to: Vector2, seconds := 0.5) -> void:
	cursor_shown = true
	var from := cursor if cursor.x > -100 else to + Vector2(120, 160)
	var t := 0.0
	while t < seconds:
		await frame()
		t += 1.0 / FPS
		cursor = from.lerp(to, smoothstep(0.0, 1.0, minf(t / seconds, 1.0)))
	cursor = to


func click_at(to: Vector2, seconds := 0.5) -> void:
	await move_cursor(to, seconds)
	cursor_down = true
	_ripples.append({"pos": to, "t": now})
	await frame()
	await frame()
	await frame()
	cursor_down = false


func click_world(p: Vector2, seconds := 0.5) -> void:
	await click_at(screen(p), seconds)


func hide_cursor() -> void:
	cursor_shown = false


# --- Routes -------------------------------------------------------------------

## Road route from a world point to an incident, as world points
## (start, the roads, the incident).
func road_path(from: Vector2, to: Vector2, avoid := {}) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var a := RoadGraph.snap(from, 200.0, avoid)
	var b := RoadGraph.snap(to, 200.0, avoid)
	if a and b:
		pts.append_array(RoadGraph.route(a, b, avoid).points)
	pts.append(to)
	return pts


static func path_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


static func point_along(pts: PackedVector2Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if d <= seg:
			return pts[i - 1].lerp(pts[i], d / maxf(seg, 0.0001))
		d -= seg
	return pts[pts.size() - 1]


## Press, trace `path` with the route drawer and let go on the incident.
## For a redraw, `crew` is out on the road and the path starts at it.
func drag(crew: Crew, path: PackedVector2Array, target: Incident, seconds: float, redraw := false) -> void:
	await move_cursor(screen(path[0]), 0.45)
	cursor_down = true
	_ripples.append({"pos": cursor, "t": now})
	drawer.set_process(false)
	if redraw:
		drawer._begin_redraw(crew, path[0])
	elif drawer.crew != crew or drawer.tips.is_empty():
		drawer._begin(crew, path[0])
	drawer.state = drawer.State.DRAWING
	var total := path_length(path)
	var t := 0.0
	while t < seconds:
		await frame()
		t += 1.0 / FPS
		var k := minf(t / seconds, 1.0)
		var eased := k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65     # gentle start and finish
		var p := point_along(path, total * eased)
		cursor = screen(p)
		if p.distance_to(drawer._last_sample) >= 3.0 / cam.zoom.x:
			drawer._last_sample = p
			drawer._sample(p)
		drawer._refresh_line()
	drawer._on_release(target.global_position)
	cursor_down = false
	_ripples.append({"pos": cursor, "t": now})
	drawer.set_process(true)


## Dispatch `crew` from its station to `inc`, tracing the shortest road route.
func send(crew: Crew, inc: Incident, seconds: float) -> void:
	await drag(crew, road_path(crew.station.global_position, inc.global_position), inc, seconds)


## Press "Send <crew>" on the incident's card.
func press_send(inc: Incident, crew: Crew) -> void:
	var b := send_button(inc, crew)
	if b:
		await click_at(b.get_global_rect().get_center(), 0.5)
		b.pressed.emit()
	else:
		Events.crew_selected.emit(crew)


func send_button(inc: Incident, crew: Crew) -> Button:
	var card = hud._cards.get(inc)
	if card == null or not is_instance_valid(card):
		return null
	for b: Button in card.find_children("*", "Button", true, false):
		if b.text == "Send " + crew.callsign:
			return b
	return null


# --- Incidents and roads ------------------------------------------------------

## A real incident of this type, on the playable road (or Feature of
## Interest) closest to `near`.
func spawn(id: StringName, near: Vector2, edge := -1) -> Incident:
	var t := type_of(id)
	var pos := near
	var place := ""
	if t.where == IncidentType.Where.FOI:
		var best_d := INF
		for f: Dictionary in manager._fois:
			var p := Vector2(f["x"], f["y"])
			if (t.foi_types.has(f["type"]) or t.foi_types.has(f["subtype"])) and Stage.is_playable(p) and p.distance_to(near) < best_d:
				best_d = p.distance_to(near)
				pos = p
				place = f["name"]
	else:
		if edge < 0:
			edge = road_near(near, t.road_classes)
		var on := RoadGraph.snap(near, 2000.0)
		pos = RoadGraph.point_at(edge, RoadGraph.edge_length(edge) * 0.5)
		if on and on.edge == edge:
			pos = on.point
		var road: String = RoadGraph.edge_name[edge]
		place = road if road != "" and road != "Unnamed" else "an unnamed road"
	var needed: Array[CrewType] = []
	for cid in t.crew_types:
		for c: CrewType in stations.crew_types:
			if c.id == cid:
				needed.append(c)
	var inc := Incident.new()
	inc.setup(t, needed, pos, place, edge if t.where == IncidentType.Where.ROAD else -1)
	inc.name = "%s_%d" % [t.id, Engine.get_process_frames()]
	manager.add_child(inc)
	Events.incident_spawned.emit(inc)
	return inc


## Closest playable road to a point, preferring these road classes.
func road_near(p: Vector2, classes: Array = []) -> int:
	var best := -1
	var best_d := INF
	for r in [60.0, 150.0, 400.0, 1200.0]:
		for e in RoadGraph.edges_near(p, r):
			if RoadGraph.edge_length(e) < 30.0 or World.is_blocked(e):
				continue
			if not classes.is_empty() and not classes.has(RoadGraph.edge_class(e)):
				continue
			var d := RoadGraph.edge_midpoint(e).distance_to(p)
			if d < best_d:
				best_d = d
				best = e
		if best >= 0:
			return best
	return road_near(p) if not classes.is_empty() else -1


## The first road on the crew's route at least `ahead` px in front of it
## (not its incident's road): where a staged roadblock goes.
func edge_ahead(crew: Crew, ahead := 50.0) -> int:
	var d := 0.0
	var pos := crew.global_position
	var current := crew._edges[mini(crew._index, crew._edges.size() - 1)]
	for i in range(crew._index, crew._points.size()):
		d += pos.distance_to(crew._points[i])
		pos = crew._points[i]
		var e: int = crew._edges[i]
		if e >= 0 and e != current and d >= ahead and (crew.incident == null or e != crew.incident.road_edge):
			return e
	return -1


# --- Highlights and titles --------------------------------------------------------

## Pulsing outline around a control (or a world point with radius) until t.
func highlight_ui(c: Control, until: float) -> void:
	_highlights.append({"rect": func() -> Rect2: return c.get_global_rect() if is_instance_valid(c) else Rect2(), "until": until, "circle": false})


func highlight_rect(r: Callable, until: float) -> void:
	_highlights.append({"rect": r, "until": until, "circle": false})


func highlight_world(p: Callable, radius: float, until: float) -> void:
	_highlights.append({"rect": func() -> Rect2:
		var s := screen(p.call())
		return Rect2(s - Vector2(radius, radius), Vector2(radius, radius) * 2.0), "until": until, "circle": true})


func fade_title(to: float, seconds: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(self, "title_alpha", to, seconds)


func _draw_marks() -> void:
	var beat := 0.5 + 0.5 * sin(now * 5.0)
	_highlights = _highlights.filter(func(h: Dictionary) -> bool: return now < h["until"])
	for h: Dictionary in _highlights:
		var r: Rect2 = h["rect"].call()
		if r.size == Vector2.ZERO:
			continue
		if h["circle"]:
			var rad := r.size.x / 2.0 + 6.0 * beat
			_marks.draw_arc(r.get_center(), rad + 6.0, 0, TAU, 64, Color(ACCENT, 0.35 * beat), 10.0)
			_marks.draw_arc(r.get_center(), rad, 0, TAU, 64, ACCENT, 4.0)
		else:
			var box := StyleBoxFlat.new()
			box.draw_center = false
			box.border_color = ACCENT
			box.set_border_width_all(4)
			box.set_corner_radius_all(12)
			box.shadow_color = Color(ACCENT, 0.5 * beat)
			box.shadow_size = 10
			_marks.draw_style_box(box, r.grow(6.0 + 4.0 * beat))

	if title_alpha > 0.0:
		var font := ThemeDB.fallback_font
		var size := _marks.size
		var band := Rect2(0, size.y * 0.5 - 130, size.x, 230)
		_marks.draw_rect(band, Color(0.08, 0.1, 0.14, 0.72 * title_alpha))
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 96).x
		_marks.draw_string(font, Vector2((size.x - w) / 2.0, size.y * 0.5 + 10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Color(1, 1, 1, title_alpha))
		var w2 := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_marks.draw_string(font, Vector2((size.x - w2) / 2.0, size.y * 0.5 + 66), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(ACCENT, title_alpha))

	var font2 := ThemeDB.fallback_font
	if caption != "":
		var cw := font2.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		var cx := 450.0 + (_marks.size.x - 450.0 - cw) / 2.0
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.08, 0.1, 0.14, 0.85)
		box.set_corner_radius_all(10)
		box.border_color = ACCENT
		box.border_width_left = 6
		_marks.draw_style_box(box, Rect2(cx - 22, 116, cw + 44, 52))
		_marks.draw_string(font2, Vector2(cx, 152), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	if Engine.time_scale > 1.01:
		var ff := "▶▶ %.1f×" % Engine.time_scale
		var box2 := StyleBoxFlat.new()
		box2.bg_color = Color(0.08, 0.1, 0.14, 0.85)
		box2.set_corner_radius_all(10)
		_marks.draw_style_box(box2, Rect2(_marks.size.x - 170, 116, 140, 48))
		_marks.draw_string(font2, Vector2(_marks.size.x - 152, 150), ff, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ACCENT)

	_ripples = _ripples.filter(func(r: Dictionary) -> bool: return now - r["t"] < 0.5)
	for r: Dictionary in _ripples:
		var k: float = (now - r["t"]) / 0.5
		_marks.draw_arc(r["pos"], 10.0 + 34.0 * k, 0, TAU, 32, Color(ACCENT, 1.0 - k), 3.0)

	if cursor_shown:
		# Arrow pointer with its tip on the cursor position.
		var c := cursor
		var arrow := PackedVector2Array([c, c + Vector2(0, 30), c + Vector2(8, 23), c + Vector2(14, 36),
			c + Vector2(19, 34), c + Vector2(13, 21), c + Vector2(23, 21)])
		_marks.draw_colored_polygon(arrow, Color.WHITE)
		var outline := arrow.duplicate()
		outline.append(c)
		_marks.draw_polyline(outline, Color("1d2433"), 2.0, true)
		if cursor_down:
			_marks.draw_circle(c, 9.0, Color(ACCENT, 0.55))


# --- More helpers -----------------------------------------------------------------

## Camera centre for a zoomed-in view of `p` that stays inside `r`.
func _inside(p: Vector2, r: Rect2, zoom: float) -> Vector2:
	var half := Vector2(1920.0 - cam.ui_inset.x, 1080.0 - cam.ui_inset.y - cam.ui_inset_bottom) / zoom / 2.0
	return Vector2(clampf(p.x, r.position.x + half.x, r.end.x - half.x) if r.size.x > half.x * 2.0 else r.get_center().x,
		clampf(p.y, r.position.y + half.y, r.end.y - half.y) if r.size.y > half.y * 2.0 else r.get_center().y)


## {edge, pos}: a point on the playable road nearest `near` (of these classes).
func road_spot(near: Vector2, classes: Array = []) -> Dictionary:
	var e := road_near(near, classes)
	var pos := RoadGraph.point_at(e, RoadGraph.edge_length(e) * 0.5)
	return {"edge": e, "pos": pos}


## Route points and their road edges, as the route drawer would produce.
func route_with_edges(from: Vector2, to: Vector2, avoid := {}) -> Array:
	var pts := PackedVector2Array([from])
	var edges := PackedInt32Array([-1])
	var a := RoadGraph.snap(from, 200.0, avoid)
	var b := RoadGraph.snap(to, 200.0, avoid)
	if a and b:
		var r := RoadGraph.route(a, b, avoid)
		pts.append_array(r.points)
		edges.append_array(r.point_edges)
	pts.append(to)
	edges.append(-1)
	return [pts, edges]


## Dispatch without showing the drawing (for crews off camera).
func dispatch_direct(crew: Crew, inc: Incident) -> void:
	var r := route_with_edges(crew.station.global_position, inc.global_position)
	inc.assign(crew)
	crew.dispatch(r[0], r[1], inc)
	Events.route_committed.emit(crew, r[0], Array(r[1]))


## Seconds a crew needs to drive from its station to an incident (no traffic).
func drive_seconds(crew: Crew, inc: Incident) -> float:
	var r := route_with_edges(crew.station.global_position, inc.global_position)
	return path_length(r[0]) / (crew.type.speed_mps * float(Stage.meta["px_per_m"]))


## Keep the camera on a node until narration time `until`.
func follow(n: Node2D, until: float) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_follow = n
	_follow_until = until


## A random-style roadblock on the road nearest `near`, shown on the map.
func roadblock(near: Vector2, reason: String, avoid_edges: Array = []) -> int:
	var best := -1
	var best_d := INF
	for e in RoadGraph.edges_near(near, 300.0):
		if avoid_edges.has(e) or World.is_blocked(e) or RoadGraph.edge_length(e) < 40.0 or RoadGraph.edge_class(e) > 2:
			continue
		var d := RoadGraph.edge_midpoint(e).distance_to(near)
		if d < best_d:
			best_d = d
			best = e
	if best >= 0:
		World.block(best, reason, null, 600.0)
		Knowledge.observe(best)
	return best


func foi_near(p: Vector2, types: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for f: Dictionary in manager._fois:
		var q := Vector2(f["x"], f["y"])
		if (types.has(f["type"]) or types.has(f["subtype"])) and Stage.is_playable(q) and q.distance_to(p) < best_d:
			best_d = q.distance_to(p)
			best = f
	return best


func press_key(key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		Input.parse_input_event(ev)
		await frame()


## Show/hide an overlay of the TRUE traffic on every playable road (World),
## for explaining truth vs knowledge.
func show_truth(on: bool) -> void:
	if _truth == null:
		_truth = Node2D.new()
		_truth.z_index = 45
		_truth.draw.connect(func() -> void:
			var colours: Array = main.get_node("RoadOverlay").TRAFFIC_COLOURS
			var batches := [[], [], [], []]
			for e in RoadGraph.edge_count():
				if RoadGraph.is_playable(e):
					var pts: PackedVector2Array = RoadGraph.edge_pts[e]
					for i in range(1, pts.size()):
						batches[World.get_traffic(e)].append(pts[i - 1])
						batches[World.get_traffic(e)].append(pts[i])
			for lvl in 4:
				if not batches[lvl].is_empty():
					_truth.draw_multiline(PackedVector2Array(batches[lvl]), colours[lvl], 4.0 / cam.zoom.x))
		main.add_child(_truth)
	_truth.visible = on


## Full-screen evidence card (file contents laid out like the editor).
func show_card(c: Control) -> void:
	_overlay.add_child(c)
	_overlay.move_child(c, 0)           # under the cursor and highlights


# =============================================================================
# Shots
# =============================================================================

## Part 1 showcase, narration 0:00 - 1:41 (and the end screen held for reuse).
func shot_showcase() -> void:
	var amb := station("Junction Ambulance Post")
	var r3: Rect2 = Stage.rects[3]

	# Open on all of Burrundara, then close in on the tutorial junction.
	Stage.shown = r3
	var f3: Dictionary = cam._framing(r3)
	_free_camera()
	cam.zoom = Vector2(f3["zoom"], f3["zoom"])
	cam.position = f3["position"]
	title = "The Race Against Time"
	subtitle = "Dispatch crews across a map that goes stale"

	begin(0.0)
	fade_title(1.0, 0.8)
	await at(6.6)
	fade_title(0.0, 0.8)
	await at(7.1)
	var old_seconds := Stage.transition_seconds
	Stage.transition_seconds = 4.0
	Stage.set_stage(0)
	await at(11.4)
	Stage.transition_seconds = old_seconds

	# Welcome tips while Leah reads the brief.
	Run.tips_seen.erase("welcome")
	tutorial._welcome()
	await at(15.0)
	tutorial._show_next()
	await at(18.8)
	tutorial._pages.clear()
	tutorial._close()

	# Vandy: the first call. Pick a call far enough from the ambulance post
	# that the crew is still driving when the roadblock goes up.
	var target := _tutorial_call_spot(amb)
	await at(21.0)
	Run.tips_seen.erase("first_call")
	var inc := spawn(&"street_medical", target["pos"], target["edge"])
	await at(25.7)
	tutorial._show_next()          # "Send a crew" with its demonstration
	await at(31.4)
	tutorial._pages.clear()
	tutorial._close()

	# Ishita: draw the route; the map lights up around the crew.
	var crew: Crew = amb.first_available()
	await at(33.6)
	await send(crew, inc, 4.6)
	hide_cursor()

	# Jessie: a roadblock the map didn't know about, just ahead of the crew.
	await at(43.6)
	var blocked := edge_ahead(crew, 45.0)
	print("DIRECTOR blocking edge %d (%s)" % [blocked, RoadGraph.edge_name[blocked] if blocked >= 0 else "-"])
	if blocked >= 0:
		World.block(blocked, "Roadworks", null, 600.0)
	while crew.state != Crew.State.BLOCKED and now < 52.0:
		await frame()
	print("DIRECTOR crew blocked at %.2f" % now)
	var zin := cam.zoom.x * 1.35
	cam_to(_inside(crew.global_position, Stage.rects[0], zin), zin, 1.6)
	await at(55.6)
	cam_fit(Stage.rects[0], 1.0)
	await at(56.8)
	var detour := road_path(crew.global_position, inc.global_position, {blocked: true})
	await drag(crew, detour, inc, 3.0, true)
	hide_cursor()

	# Leah: arrive, resolve, and the stage opens out.
	while inc.status != Incident.Status.RESOLVED and now < 75.0:
		await frame()
	print("DIRECTOR tutorial resolved at %.2f" % now)
	await at(74.0)
	var r1: Rect2 = Stage.rects[1]
	var crash := spawn(&"crash_injuries", r1.position + r1.size * Vector2(0.72, 0.30))
	await at(76.4)
	var fire := spawn(&"house_fire", r1.position + r1.size * Vector2(0.30, 0.66))
	await at(77.2)
	var storm := spawn(&"storm_damage", r1.position + r1.size * Vector2(0.55, 0.78))

	# Vandy: let three calls slip and the run ends.
	await at(80.2)
	crash.fail("crash with injuries on %s" % crash.place)
	await at(80.9)
	fire.fail("house fire on %s" % fire.place)
	await at(81.6)
	storm.fail("storm damage at %s" % storm.place)

	# Ishita: the after-action report (held long enough to reuse at 2:14).
	await at(106.0)


## A street call on a stage 0 road whose route from `st` is long enough to
## still be driving ~5 s after dispatch.
func _tutorial_call_spot(st: Station) -> Dictionary:
	var from := RoadGraph.snap(st.global_position, 200.0)
	var best := {}
	var best_score := INF
	for e in RoadGraph.edge_count():
		if not RoadGraph.is_playable(e) or RoadGraph.edge_length(e) < 40.0:
			continue
		var mid := RoadGraph.point_at(e, RoadGraph.edge_length(e) * 0.5)
		if not Stage.rects[0].grow(-40).has_point(mid):
			continue
		var near_station := false
		for s in stations.get_stations():
			if s.global_position.distance_to(mid) < 120.0:
				near_station = true
		if near_station:
			continue
		var r := RoadGraph.route(from, RoadGraph.snap(mid, 50.0))
		var score := absf(r.length - 900.0)
		if score < best_score:
			best_score = score
			best = {"pos": mid, "edge": e, "length": r.length}
	print("DIRECTOR tutorial call: edge %d route %.0f px" % [best["edge"], best["length"]])
	return best


const Cards := preload("res://tools/video/cards.gd")


## Challenge response, narration 1:40 - 2:33 (Leah).
func shot_challenge() -> void:
	Stage.set_stage(3, false)
	Knowledge.observe_all()                  # full colour: what the Vicmap data looks like
	var amb := station("Junction Ambulance Post")
	var credit: Control = main.get_node("WorldMap/Credit").get_child(0)
	await frame()
	cam_fit(Stage.rects[3], 0.0)
	begin(99.0)
	await at(100.2)
	highlight_ui(credit, 107.0)
	await at(104.8)
	var centre := Vector2(3150, 2650)
	cam_to(centre, 0.95, 2.2)
	await at(108.7)
	for f in [foi_near(centre, ["education centre"]), foi_near(centre, ["transport terminal"]), foi_near(centre + Vector2(-400, 0), ["sport facility", "community venue"])]:
		if not f.is_empty():
			var p := Vector2(f["x"], f["y"])
			highlight_world(func() -> Vector2: return p, 26.0, 111.6)

	# Knowing what is where: you draw each route yourself.
	var spot := road_spot(amb.global_position + Vector2(620, -260), [0, 1, 2])
	await at(114.4)
	cam_to(amb.global_position.lerp(spot["pos"], 0.5), 1.25, 1.0)
	await at(115.3)
	var inc := spawn(&"street_medical", spot["pos"], spot["edge"])
	var crew: Crew = amb.first_available()
	await at(116.0)
	await send(crew, inc, 2.8)
	hide_cursor()
	# Reliable information matters: a roadblock the map didn't show.
	await at(121.4)
	var b := edge_ahead(crew, 40.0)
	if b >= 0:
		World.block(b, "Fallen tree", null, 600.0)
	follow(crew, 124.6)

	# Features of Interest are meaningful places.
	var school := foi_near(Vector2(3400, 2700), ["education centre"])
	var care := foi_near(Vector2(3000, 2800), ["hospital", "care facility"])
	var sp := Vector2(school["x"], school["y"])
	var cp := Vector2(care["x"], care["y"])
	print("DIRECTOR school %s, care %s" % [school["name"], care["name"]])
	await at(124.8)
	cam_fit(Rect2(amb.global_position, Vector2.ZERO).expand(sp).expand(cp).grow(260), 1.6)
	await at(126.9)
	highlight_world(func() -> Vector2: return amb.global_position, 28.0, 133.4)
	await at(128.0)
	highlight_world(func() -> Vector2: return cp, 28.0, 133.4)
	await at(128.4)
	highlight_world(func() -> Vector2: return sp, 28.0, 133.4)
	# ...and where a call happens decides who's needed.
	await at(131.0)
	spawn(&"break_in", sp)
	await at(131.9)
	spawn(&"medical", cp)
	await at(134.0)
	highlight_ui(hud._list.get_parent(), 137.8)

	# Outdated data now; misplaced places next.
	await at(138.4)
	cam_to(_inside(crew.global_position, Stage.rects[3], 2.0), 2.0, 1.4)
	await at(142.9)
	caption = "Now: live road information goes out of date"
	await at(146.6)
	caption = "Assessment 3: places that aren't where the map says"
	cam_to(cp, 2.2, 1.2)
	highlight_world(func() -> Vector2: return cp, 34.0, 152.4)
	await at(152.4)
	caption = ""
	await at(156.0)


## Core gameplay and progression, narration 2:34 - 3:16 (Vandy).
func shot_core() -> void:
	Stage.set_stage(1, false)
	var police := station("Cambermere Police Station")
	await frame()
	# A close call on a clear road, so the whole loop fits the narration.
	var spot := {}
	for off in [Vector2(220, -60), Vector2(-200, -90), Vector2(180, 140), Vector2(-160, 160), Vector2(260, 0)]:
		spot = road_spot(police.global_position + off, [1, 2, 3])
		if World.get_traffic(spot["edge"]) == World.Traffic.CLEAR and spot["pos"].distance_to(police.global_position) > 120.0:
			break
	for e in RoadGraph.edges_near(police.global_position.lerp(spot["pos"], 0.5), 260.0):
		if not World.is_blocked(e):
			World.set_traffic(e, World.Traffic.CLEAR)       # a quiet morning around the station
	cam_to(police.global_position.lerp(spot["pos"], 0.5), 1.7, 0.0)
	begin(152.6)
	await at(154.6)
	var crash := spawn(&"car_crash", spot["pos"], spot["edge"])
	await at(156.5)
	await click_world(crash.global_position, 0.6)
	manager.select(crash)
	await at(157.3)
	var crew: Crew = police.first_available()
	await press_send(crash, crew)
	await at(158.3)
	await drag(crew, road_path(police.global_position, crash.global_position), crash, 1.5)
	hide_cursor()
	# Follow it on scene, home and into cooldown at 2.5x.
	Engine.time_scale = 3.0
	while crew.state != Crew.State.COOLDOWN and now < 165.0:
		await frame()
	Engine.time_scale = 1.0
	print("DIRECTOR core crew home at %.2f" % now)

	await at(164.1)
	highlight_ui(hud._run_bar, 169.6)
	await at(170.1)
	cam_fit(Stage.rects[1], 1.2)
	var r1: Rect2 = Stage.rects[1]
	await at(172.8)
	var c1 := spawn(&"car_crash", r1.position + r1.size * Vector2(0.75, 0.35))
	await at(174.1)
	spawn(&"break_in", r1.position + r1.size * Vector2(0.4, 0.7))
	await at(175.1)
	spawn(&"car_fire", r1.position + r1.size * Vector2(0.25, 0.3))
	await at(175.9)
	if _cam_tween:
		_cam_tween.kill()
	Stage.set_stage(2)
	var r2: Rect2 = Stage.rects[2]
	await at(178.1)
	spawn(&"house_fire", r2.position + r2.size * Vector2(0.18, 0.75))
	await at(179.5)
	spawn(&"storm_damage", r2.position + r2.size * Vector2(0.8, 0.25))
	await at(180.8)
	Stage.set_stage(3)
	var r3: Rect2 = Stage.rects[3]
	await at(183.4)
	spawn(&"serious_crash", r3.position + r3.size * Vector2(0.62, 0.8))
	await at(186.1)
	roadblock(r3.position + r3.size * Vector2(0.3, 0.2), "Roadworks")
	roadblock(r3.position + r3.size * Vector2(0.85, 0.6), "Fallen tree")
	await at(187.7)
	highlight_ui(hud._run_bar, 191.6)
	await at(189.8)
	c1.fail("car crash on %s" % c1.place)
	await at(192.0)
	highlight_rect(func() -> Rect2:
		var r: Rect2 = hud._run_bar.get_global_rect()
		return Rect2(r.end.x - 50, r.position.y + r.size.y * 0.35, 50, r.size.y * 0.65), 195.6)
	await at(196.2)


## Physics in play, narration 3:15 - 3:32 (Leah).
func shot_physics() -> void:
	Stage.set_stage(1, false)
	var police := station("Cambermere Police Station")
	var centre := Vector2(2960, 2660)
	var crash_spot := road_spot(Vector2(2900, 2590), [1, 2, 3])
	await frame()
	cam_to(crash_spot["pos"], 3.8, 0.0)
	begin(194.5)
	await at(196.8)
	var crash := spawn(&"car_crash", crash_spot["pos"], crash_spot["edge"])
	await at(199.4)
	cam_to(centre, 1.25, 1.4)
	await at(201.5)
	spawn(&"tree_down", centre + Vector2(220, -110))
	await at(202.5)
	var works := roadblock(centre + Vector2(80, 130), "Roadworks", [crash_spot["edge"]])
	await at(203.2)
	roadblock(centre + Vector2(-230, 110), "Flooded underpass", [crash_spot["edge"], works])
	# Send the police so it reaches the crash as the camera gets there.
	var crew: Crew = police.first_available()
	await at(maxf(203.4, 209.2 - drive_seconds(crew, crash) * 1.15))
	dispatch_direct(crew, crash)
	await at(205.2)
	if works >= 0:
		cam_to(RoadGraph.edge_midpoint(works), 2.8, 1.0)
	await at(207.6)
	cam_to(crash.global_position, 3.6, 0.8)
	await at(212.8)


## Editor evidence cards, narration 3:32 - 4:07 (Leah).
func shot_cards_physics() -> void:
	begin(211.8)
	var layers := Cards.layers_card()
	show_card(layers["root"])
	for k in 5:
		await at([214.5, 215.1, 215.9, 216.9, 217.9][k])
		for j in 5:
			Cards.lit(layers["rows"][j], j == k)
	await at(218.9)
	layers["root"].queue_free()
	var col := Cards.collision_card()
	show_card(col["root"])
	Cards.lit(col["rows"]["debris"], true)
	await at(223.9)
	Cards.lit(col["rows"]["debris"], false)
	Cards.lit(col["rows"]["sensor"], true)
	Cards.lit(col["rows"]["zone"], true)
	await at(232.0)
	Cards.lit(col["rows"]["zone"], false)
	Cards.lit(col["rows"]["sensor"], false)
	Cards.lit(col["rows"]["bumper"], true)
	await at(234.2)
	col["root"].queue_free()
	var mats := Cards.materials_card()
	show_card(mats["root"])
	var cues := {"rubber": 236.1, "glass": 237.8, "metal": 239.8, "wood": 240.8, "plastic": 241.6, "sandbag": 243.0, "concrete": 245.0}
	var last := ""
	for name in cues:
		await at(cues[name])
		if last != "":
			Cards.lit(mats["rows"][last], false)
		Cards.lit(mats["rows"][name], true)
		last = name
	await at(247.2)


## Debris materials up close, narration 4:07 - 4:14 (Leah).
func shot_physics2() -> void:
	Stage.set_stage(1, false)
	var spot := road_spot(Vector2(3300, 2500), [1, 2, 3])
	await frame()
	var flood_at: Vector2 = spot["pos"] + Vector2(-90, 50)
	cam_to(spot["pos"].lerp(flood_at, 0.5), 3.4, 0.0)
	begin(246.4)
	await at(247.0)
	spawn(&"car_crash", spot["pos"], spot["edge"])
	await at(248.2)
	var flood := roadblock(flood_at, "Flooded underpass", [spot["edge"]])
	if flood >= 0:
		cam_to(spot["pos"].lerp(RoadGraph.edge_midpoint(flood), 0.5), 3.4, 0.8)
	await at(256.0)


## Event bus and data cards, narration 4:14 - 4:36 (Ishita).
func shot_cards_modular() -> void:
	begin(253.4)
	var ev := Cards.events_card()
	show_card(ev["root"])
	await at(259.2)
	for file in ["sfx.gd", "effects.gd", "ticker.gd", "hud.gd"]:
		if ev["rows"].has(file):
			Cards.lit(ev["rows"][file], true)
	await at(265.4)
	ev["root"].queue_free()
	var data := Cards.data_card()
	show_card(data["root"])
	for k in ["crew_types", "debris_types", "incident_types"]:
		Cards.lit(data["rows"][k], true)
	await at(270.7)
	Cards.lit(data["rows"]["crew_types"], false)
	Cards.lit(data["rows"]["debris_types"], false)
	await at(272.4)
	Cards.lit(data["rows"]["car_crash.tres"], true)
	data["inspector"].visible = true
	for k in ["field_crew_types", "field_debris", "field_debris_count"]:
		Cards.lit(data["rows"][k], true)
	await at(276.8)


## Truth vs knowledge and the crew state machine, narration 4:36 - 5:00 (Ishita).
func shot_modular() -> void:
	Stage.set_stage(2, false)
	var amb := station("Junction Ambulance Post")
	var police := station("Cambermere Police Station")
	var fire := station("Cambermere Fire Station")
	await frame()
	cam_fit(Rect2(2300, 2200, 1500, 1050), 0.0)
	var a := spawn(&"street_medical", amb.global_position + Vector2(-350, -150))
	var p := spawn(&"disturbance", police.global_position + Vector2(260, 160))
	var f := spawn(&"car_fire", fire.global_position + Vector2(-420, -260))
	begin(276.0)
	dispatch_direct(amb.first_available(), a)
	await at(277.0)
	dispatch_direct(police.first_available(), p)
	await at(278.0)
	var fire_crew: Crew = fire.first_available()
	dispatch_direct(fire_crew, f)
	await at(279.2)
	show_truth(true)
	caption = "World: what is true on every road, right now"
	await at(281.6)
	show_truth(false)
	caption = "Knowledge: what the player has seen, and when"
	await at(285.1)
	caption = ""
	var b := edge_ahead(fire_crew, 40.0)
	if b >= 0:
		World.block(b, "Broken-down truck", null, 600.0)
	await at(289.1)
	caption = "Crew state machine: available, en route, blocked, on scene, returning, cooldown"
	highlight_ui(hud._crew_scroll, 298.6)
	await at(293.4)
	caption = "Timers: incident rings, blocked countdowns, crew cooldowns"
	await at(298.6)
	caption = ""
	await at(300.8)


## Animation, feedback and player experience, narration 5:00 - 5:56 (Jessie).
func shot_feedback() -> void:
	Stage.set_stage(2, false)
	var amb := station("Junction Ambulance Post")
	var police := station("Cambermere Police Station")
	var fire := station("Cambermere Fire Station")
	var r2: Rect2 = Stage.rects[2]
	await frame()
	cam_fit(r2, 0.0)
	var ring := spawn(&"car_crash", Vector2(3300, 2420))
	ring.elapsed_active = ring.type.time_limit_seconds * 0.30
	var done := spawn(&"street_medical", amb.global_position + Vector2(260, 120))
	var slip := spawn(&"disturbance", Vector2(2350, 2650))
	var house := spawn(&"house_fire", Vector2(2250, 3150))
	var storm := spawn(&"storm_damage", Vector2(3050, 3250))
	var amb_crew: Crew = amb.first_available()
	dispatch_direct(amb_crew, done)
	begin(299.0)

	await at(303.0)
	cam_to(ring.global_position, 2.2, 0.9)
	# Timer ring: fill it from 30% to past the 3/4 warning by 5:10.
	var extra := ring.type.time_limit_seconds * (0.78 - 0.30) / (310.4 - 303.5) - 1.0
	while now < 311.0:
		if now > 303.5:
			ring.elapsed_active += extra / FPS
		if done.status == Incident.Status.ON_SCENE:
			done.progress = minf(done.progress, 0.2)          # hold until its moment
		await frame()

	_frozen[ring] = ring.elapsed_active      # demo over: it mustn't cost a heart later

	# Obstacle: the fire crew heading for the house fire hits a roadblock.
	var fire_crew: Crew = fire.first_available()
	fire_crew.blocked_patience = 120.0       # waits for its redraw at 5:47
	dispatch_direct(fire_crew, house)
	follow(fire_crew, 318.2)
	cam_to(fire_crew.global_position, 2.0, 0.0)
	follow(fire_crew, 318.2)
	await at(312.4)
	var b := edge_ahead(fire_crew, 30.0)
	if b >= 0:
		World.block(b, "Roadworks", null, 600.0)
	while now < 318.3:
		if done.status == Incident.Status.ON_SCENE:
			done.progress = minf(done.progress, 0.2)
		await frame()

	# Resolved: green sparkle and chime.
	cam_to(done.global_position, 2.2, 0.5)
	await at(318.9)
	done.progress = 0.8
	await at(320.6)
	cam_to(slip.global_position, 2.2, 0.5)
	await at(321.4)
	slip.fail("disturbance on %s" % slip.place)
	highlight_ui(hud._run_bar, 323.6)
	await at(323.8)
	cam_to(house.global_position, 2.6, 0.7)
	await at(326.9)
	cam_to(storm.global_position + Vector2(60, 0), 2.2, 0.6)
	await at(328.3)
	roadblock(storm.global_position + Vector2(150, 30), "Burst water main")
	await at(330.4)
	cam_fit(Rect2(2000, 2200, 1900, 1300), 1.5)
	await at(335.6)
	highlight_ui(main.get_node("UI/Ticker"), 338.9)

	# Tutorial tip with its highlight: the first dispatch.
	var police_crew: Crew = police.first_available()
	var call := spawn(&"break_in", police.global_position + Vector2(240, -160))
	await at(339.0)
	Run.tips_seen.erase("dispatched")
	dispatch_direct(police_crew, call)
	await at(341.4)
	tutorial._pages.clear()
	tutorial._close()

	# Sound: more crews on the road, sirens, a crew pulling back in.
	await at(343.6)
	var harrowell := station("Harrowell Ambulance Station")
	var hawk := station("Hawkthorne Fire Station")
	if harrowell and harrowell.first_available():
		dispatch_direct(harrowell.first_available(), spawn(&"street_medical", harrowell.global_position + Vector2(-300, -250)))
	await at(344.6)
	if hawk and hawk.first_available():
		dispatch_direct(hawk.first_available(), spawn(&"car_fire", hawk.global_position + Vector2(350, 200)))
	await at(346.5)
	if fire_crew.state == Crew.State.BLOCKED:
		cam_to(fire_crew.global_position, 1.8, 0.4)
		await at(347.0)
		await drag(fire_crew, road_path(fire_crew.global_position, house.global_position, {b: true}), house, 1.4, true)
		hide_cursor()
	await at(348.4)
	cam_to(police.global_position, 1.8, 0.6)
	await at(352.2)
	for card in hud._cards.values():
		if is_instance_valid(card):
			for btn: Button in card.find_children("*", "Button", true, false):
				if btn.text.begins_with("Send"):
					await click_at(btn.get_global_rect().get_center(), 0.5)
					btn.pressed.emit()
					break
			break
	await at(353.6)
	drawer._clear_route()
	hide_cursor()
	await at(354.1)
	await press_key(KEY_M)
	await at(355.6)
	await press_key(KEY_M)
	await at(356.8)


## Technical delivery, narration 5:56 - 6:16 (Vandy).
func shot_delivery() -> void:
	var gitlog := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("gitlog="):
			gitlog = FileAccess.get_file_as_string(a.substr(7)).split("\n")
	begin(356.0)
	var itch := Cards.itch_card()
	show_card(itch["root"])
	await at(359.7)
	itch["root"].queue_free()
	var readme := Cards.outline_card("README", "res://README.md")
	show_card(readme["root"])
	for k in ["How to play", "Controls", "Running the game", "Key programming systems", "Known issues"]:
		if readme["rows"].has(k):
			Cards.lit(readme["rows"][k], true)
	await at(362.6)
	readme["root"].queue_free()
	var git := Cards.gitlog_card(gitlog.slice(0, 16))
	show_card(git["root"])
	await at(364.7)
	git["root"].queue_free()
	var attr := Cards.attributions_card()
	show_card(attr["root"])
	await at(371.0)
	attr["root"].queue_free()
	var overlay: Control = Credits.make_overlay(func() -> void: pass)
	main.get_node("EndScreen").add_child(overlay)
	await at(373.6)
	overlay.queue_free()
	title = "Thanks for watching!"
	subtitle = "The Race Against Time"
	fade_title(1.0, 0.6)
	await at(376.6)
