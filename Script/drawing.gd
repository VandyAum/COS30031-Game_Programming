extends Node2D

# Route drawing / map input: click an incident to select it, then press on a
# station (or pick a crew in the panel), HOLD the mouse and trace along the
# roads you want the crew to take, and release on the incident to dispatch.
#
# Original version (Vandy): free-hand line, raycasts against block collisions,
# and ChatGPT-assisted snapping of the corners to hand-placed RoadPoints.
#
# AI-assisted rewrite (Claude Opus 5.5). Prompt used:
#   "Rewrite our Godot 4.7 route drawing as true freehand drawing in the style
#    of Mini Motorways: the player presses the left mouse ('Draw') on a
#    station, holds, and traces the route with the mouse; release over an
#    incident to dispatch the crew. While held, sample the mouse every few
#    pixels, snap each sample to the nearest playable road (RoadGraph.snap) and
#    extend the route from its current tip to that point along the road
#    network - but ONLY for short local steps (the road distance must be close
#    to the straight-line distance), so the game never invents a long detour:
#    the player has to actually trace corners and turns, and dragging across a
#    block does nothing until the mouse comes back to a connected road.
#    Moving back over the route trims it (retracing = undo). Releasing
#    anywhere other than an incident keeps the unfinished route; pressing near
#    its end continues it. Space ('clear_draw') clears it, R ('Undo_Drawing')
#    trims the last bit. Stations and incidents are picked by proximity to the
#    mouse (scaled by zoom) and must be inside the current Stage. Show the
#    route as a thick blue line, faded while unfinished, with a red hint line
#    to the mouse when it's too far from a usable road. Once dispatched, the
#    crew follows the route; its speed on each road is scaled by the TRUE
#    traffic in World, and each road it finishes is reported to
#    Knowledge.observe(). Emit Events for drawing started, route committed,
#    crew dispatched and crew arrived, and expose a one-line status string for
#    the debug HUD. Keep the single temporary crew (real crews/stations are
#    the next task)."
# Follow-up prompt: "A nearly-straight long jump still got accepted by the
#    detour check. Also cap each step's road length to ~90 screen pixels so a
#    single mouse sample can never auto-route a long way; the player must
#    trace it."
# Follow-up prompt (spurs, trail, sightings):
#   "Wobbling the mouse at junctions leaves little spurs where the line pokes
#    a few pixels into a side street and comes back. Whenever a new step
#    makes the route pass back through a point it already visited, cut out
#    the loop between the two visits (and drop the undo anchors inside it).
#    While the crew drives, erase the line behind it so only the remaining
#    route shows and the player can see the traffic being revealed. Replace
#    'observe the road when finished' with crew sightings: every 0.15 s call
#    Knowledge.sight() at the crew's position, which reveals the roads and the
#    map colour around it."
# Follow-up prompt (milestone 1 - many crews, selection, choosing a crew):
#   "Crews are now real Crew nodes owned by Stations, and incidents are
#    Incident nodes from the IncidentManager. Turn this script into the map
#    input handler only (no crew movement any more): a quick left click on an
#    incident selects it; pressing on a playable station starts a route for
#    that station's first available crew (or the crew the player picked in
#    the panel, via Events.crew_selected / prepare_for(crew), which starts the
#    route at its station so the player just drags from there). Releasing on
#    an open incident dispatches that crew along the drawn route (Crew.dispatch
#    + Incident.assign); several crews can be out at once. Colour the route in
#    the crew type's colour. Keep the freehand rules, spur removal, undo and
#    status_text(). Read stations, incidents and the manager through groups
#    instead of exported node paths."
# Follow-up prompt (milestone 2 - redraw mid-journey):
#   "Let the player press on a crew that is en route or stopped at a
#    blockage and drag a NEW route starting from where the crew is now. The
#    crew pauses ('held') while its new route is being drawn. Releasing on
#    its incident (or another open incident, which re-assigns it) hands it
#    the new route via Crew.reroute. Releasing anywhere else keeps the
#    unfinished route for a blocked crew (press its end to continue) but
#    drops it for a moving crew, which carries on with its old route.
#    Space / clearing also releases a held crew."
# Follow-up prompt (milestone 3): "Incidents can now take several crews:
#    allow dispatching to any incident that still needs a crew, and when a
#    crew is redirected call unassign(crew) on its old incident."
# Follow-up prompt (bumps): "Little spurs still survive at some junctions,
#    because a step only counted as a loop when it passed back through
#    exactly the same point. Treat a step as doubling back when any new
#    point comes within LOOP_TOL world px of any earlier SEGMENT of the
#    route (not just its points) after the route has gone at least
#    2 x LOOP_TOL further, and cut the route back to there."
# Follow-up prompt: "Bumps still appear (e.g. along Lookout Hill Road):
#    a short dip into a side street wasn't 'far enough' to count. Reproduce
#    it with a simulated wobbly drag, then after every step run a clean-up
#    pass over the end of the route that removes any point where the route
#    doubles straight back along the line it came in on (the next point
#    lies on the previous segment, or the previous point lies on the next
#    segment), plus zero-length duplicates, until nothing changes. Keep the
#    undo anchors in step with removed points."

@onready var line = $Line

## Screen-pixel radius for picking stations/incidents and finding roads.
@export var pick_radius_screen := 26.0
## A step is accepted if its road distance <= this x straight-line distance...
@export var max_detour := 1.8
## ...and no longer than this many screen pixels.
@export var max_step_screen := 90.0

const DRAFT_ALPHA := 0.55
## A new point this close (world px) to an earlier part of the route means
## the route doubled back: cut out the spur.
const LOOP_TOL := 3.0

enum State { IDLE, DRAWING }
var state := State.IDLE

var crew: Crew = null                   # crew the route is for
var redraw := false                     # route starts at a crew on the road, not a station
var tips : Array = []                   # accepted RoadGraph.RoadPos samples
var tip_sizes : Array[int] = []         # route_points.size() after each tip
var route_points := PackedVector2Array()
var route_point_edges := PackedInt32Array()   # road edge of each point (-1 = off road)
var _last_sample := Vector2.INF
var _hint_to := Vector2.INF             # red "can't reach" hint end
var _press_pos := Vector2.INF           # where an idle click started
var _message := ""
var _message_timer := 0.0


func _ready() -> void:
	add_to_group("route_drawer")
	line.width = 6.0
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	Events.crew_selected.connect(func(c: Node) -> void:
		if c != null and c != crew:
			prepare_for(c))


func _process(delta: float) -> void:
	_message_timer -= delta
	match state:
		State.IDLE:
			_idle()
		State.DRAWING:
			_drawing()


# --- Idle: selecting and starting routes ------------------------------------

func _idle():
	if Input.is_action_just_pressed("clear_draw"):
		_clear_route()
	if Input.is_action_just_pressed("Undo_Drawing"):
		_trim_tips(10)
	if not Input.is_action_just_pressed("Draw") or _mouse_over_ui():
		return
	var mouse = get_global_mouse_position()

	# Continue an unfinished route by pressing near its end.
	if not tips.is_empty() and mouse.distance_to(route_points[route_points.size() - 1]) <= _pick_radius():
		state = State.DRAWING
		return

	# Redraw the route of a crew that is out on the road.
	var moving = get_tree().get_nodes_in_group("crews").filter(func(c): return c.visible and c.is_redrawable())
	var out_crew = _nearest(moving, mouse)
	if out_crew != null:
		_begin_redraw(out_crew, mouse)
		state = State.DRAWING
		return

	# Start a route from a station.
	var station = _nearest(get_tree().get_nodes_in_group("stations"), mouse)
	if station != null:
		var c: Crew = crew if crew != null and crew.station == station and crew.is_available() else station.first_available()
		if c == null:
			_say("No crews available at %s" % station.station_name)
			return
		_begin(c, mouse)
		state = State.DRAWING
		return

	# Otherwise: select (or deselect) an incident.
	var manager = get_tree().get_first_node_in_group("incident_manager")
	if manager:
		manager.select(_nearest(get_tree().get_nodes_in_group("incidents"), mouse))


## Start a route for a crew chosen in the panel. The player then presses on
## the station (the start of the line) and drags.
func prepare_for(c: Crew) -> void:
	if not c.is_available():
		_say("%s is not available" % c.callsign)
		return
	_begin(c, c.station.global_position)
	_say("Drag from %s to the incident" % c.station.station_name)


func _begin(c: Crew, mouse: Vector2):
	var start_pos = RoadGraph.snap(c.station.global_position, 200.0)
	if start_pos == null:
		return
	_clear_route()
	crew = c
	tips = [start_pos]
	route_points = PackedVector2Array([c.station.global_position, start_pos.point])
	route_point_edges = PackedInt32Array([-1, start_pos.edge])
	tip_sizes = [route_points.size()]
	_last_sample = mouse
	_refresh_line()
	Events.route_drawing_started.emit(c)


func _begin_redraw(c: Crew, mouse: Vector2):
	var start_pos = RoadGraph.snap(c.global_position, 200.0)
	if start_pos == null:
		return
	_clear_route()
	crew = c
	redraw = true
	c.held = true
	tips = [start_pos]
	route_points = PackedVector2Array([c.global_position, start_pos.point])
	route_point_edges = PackedInt32Array([-1, start_pos.edge])
	tip_sizes = [route_points.size()]
	_last_sample = mouse
	_refresh_line()
	Events.route_drawing_started.emit(c)


## Start a route at a station (kept for tests): uses its first available crew.
func _begin_at_station(station, mouse: Vector2):
	var c = station.first_available()
	if c:
		_begin(c, mouse)
		state = State.DRAWING


# --- Drawing (mouse held) ------------------------------------------------------

func _drawing():
	var mouse = get_global_mouse_position()

	if not Input.is_action_pressed("Draw"):
		_on_release(mouse)
		return

	if mouse.distance_to(_last_sample) >= 3.0 / _zoom():
		_last_sample = mouse
		_sample(mouse)
	_refresh_line()


# One mouse sample while the button is held.
func _sample(mouse: Vector2):
	# Retracing: if the mouse is back over an earlier tip, cut the route there.
	var back_r = 12.0 / _zoom()
	for k in range(tips.size() - 2, maxi(-1, tips.size() - 60), -1):
		if tips[k].point.distance_to(mouse) <= back_r:
			_trim_tips(tips.size() - 1 - k)
			_hint_to = Vector2.INF
			return

	var snapped = RoadGraph.snap(mouse, _pick_radius())
	if snapped == null:
		_hint_to = mouse
		return
	if _extend_to(snapped):
		_hint_to = Vector2.INF
	else:
		_hint_to = mouse


# Try to extend the route along roads to a snapped point. Only short, local
# steps are allowed so the player draws the route, not the pathfinder.
func _extend_to(snapped) -> bool:
	var tip = tips.back()
	var straight = tip.point.distance_to(snapped.point)
	if straight < 0.5:
		return true
	var leg = RoadGraph.route(tip, snapped)
	if leg.points.is_empty() or leg.length > maxf(40.0, straight * max_detour) or leg.length > max_step_screen / _zoom():
		return false
	var new_pts = leg.points.slice(1)
	var new_edges = leg.point_edges.slice(1)
	# If the step passes back through a point already on the route, the bit
	# in between is a spur or loop: cut it out.
	var loop = _find_loop(new_pts)
	if not loop.is_empty():
		var k = loop[0]
		route_points.resize(k + 1)
		route_point_edges.resize(k + 1)
		new_pts = new_pts.slice(loop[1])
		new_edges = new_edges.slice(loop[1])
		while tip_sizes.size() > 1 and tip_sizes.back() > k + 1:
			tips.pop_back()
			tip_sizes.pop_back()
	route_points.append_array(new_pts)
	route_point_edges.append_array(new_edges)
	tips.append(snapped)
	tip_sizes.append(route_points.size())
	_despur()
	return true


# Remove out-and-back spurs: wherever the route turns straight back along
# the line it arrived on, drop the turning point. Repeats until clean, so a
# spur of several points unwinds from its tip.
func _despur() -> void:
	var changed := true
	while changed:
		changed = false
		var n := route_points.size()
		for i in range(maxi(1, n - 300), n - 1):
			var a := route_points[i - 1]
			var b := route_points[i]
			var c := route_points[i + 1]
			if b.distance_to(c) < 0.05:
				_remove_point(i + 1)
				changed = true
				break
			if a.distance_to(b) < 0.05:
				continue
			var back_on_ab := Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < LOOP_TOL * 0.5
			var back_on_bc := Geometry2D.get_closest_point_to_segment(a, b, c).distance_to(a) < LOOP_TOL * 0.5
			if (back_on_ab or back_on_bc) and (b - a).dot(c - b) < 0.0:
				_remove_point(i)
				changed = true
				break


# Remove one route point, keeping the undo anchors (tip_sizes) in step. The
# first two points (station + its road) are never removed.
func _remove_point(i: int) -> void:
	if i < 2:
		return
	route_points.remove_at(i)
	route_point_edges.remove_at(i)
	var k := 0
	while k < tip_sizes.size():
		if tip_sizes[k] - 1 == i and k > 0:
			tips.remove_at(k)          # its anchor point is gone
			tip_sizes.remove_at(k)
			continue
		if tip_sizes[k] - 1 >= i:
			tip_sizes[k] -= 1
		k += 1


# [route index k, new point index j]: new point j lies on (or within
# LOOP_TOL of) route segment k -> k+1, and the route has travelled on from
# there, so everything after k is a spur or loop. [] if there is none.
func _find_loop(new_pts: PackedVector2Array) -> Array:
	var last = route_points.size() - 1
	for j in new_pts.size():
		var away = 0.0      # route length from segment k's far end to the tip
		for k in range(last - 1, maxi(-1, last - 400), -1):
			var a = route_points[k]
			var b = route_points[k + 1]
			var p = Geometry2D.get_closest_point_to_segment(new_pts[j], a, b)
			if p.distance_to(new_pts[j]) < LOOP_TOL and away + p.distance_to(b) > 1.0:
				return [k, j]
			away += a.distance_to(b)
	return []


func _on_release(mouse: Vector2):
	_hint_to = Vector2.INF
	state = State.IDLE
	var incident = _nearest(get_tree().get_nodes_in_group("incidents"), mouse)
	var own = redraw and crew != null and incident == crew.incident
	if incident != null and not incident.is_open() and not own:
		_say("%s already has its crews" % incident.title())
	elif incident != null:
		var end_pos = RoadGraph.snap(incident.global_position, 200.0)
		if end_pos != null and _extend_to(end_pos):
			_dispatch(incident)
			return
	if redraw and crew != null and crew.state != Crew.State.BLOCKED:
		_say("%s keeps its old route" % crew.callsign)
		_clear_route()           # moving crew: drop the draft, carry on
		return
	if redraw and crew != null:
		crew.held = false        # blocked crew: keep the draft, it is waiting anyway
	_refresh_line()   # keep the unfinished route on screen


func _trim_tips(count: int):
	if tips.is_empty():
		return
	var keep = maxi(1, tips.size() - count)
	tips.resize(keep)
	tip_sizes.resize(keep)
	route_points.resize(tip_sizes[keep - 1])
	route_point_edges.resize(tip_sizes[keep - 1])
	_refresh_line()


func _clear_route():
	if crew != null:
		crew.held = false
	redraw = false
	tips = []
	tip_sizes = []
	route_points = PackedVector2Array()
	route_point_edges = PackedInt32Array()
	crew = null
	line.clear_points()
	queue_redraw()


func _refresh_line():
	var colour = crew.type.colour if crew else Color("1f6fd8")
	line.default_color = colour if state == State.DRAWING else Color(colour, DRAFT_ALPHA)
	_show(route_points)
	queue_redraw()


func _draw():
	# Red hint: the mouse is too far from a road connected to the route tip.
	if state == State.DRAWING and _hint_to != Vector2.INF and not route_points.is_empty():
		var tip = to_local(route_points[route_points.size() - 1])
		draw_dashed_line(tip, to_local(_hint_to), Color(0.9, 0.2, 0.2, 0.8), 3.0, 10.0)


# --- Dispatch --------------------------------------------------------------------

func _dispatch(incident):
	if crew == null or (not redraw and not crew.is_available()) or (redraw and not crew.is_redrawable()):
		_say("That crew is no longer available")
		_clear_route()
		return
	route_points.append(incident.global_position)
	route_point_edges.append(-1)
	var c = crew
	var pts = route_points
	var edges = route_point_edges
	var was_redraw = redraw
	_clear_route()                      # the crew draws its own remaining route
	if was_redraw:
		if c.incident != incident and c.incident != null and is_instance_valid(c.incident):
			c.incident.unassign(c)      # redirected to a different incident
		incident.assign(c)
		c.reroute(pts, edges, incident)
	else:
		incident.assign(c)
		c.dispatch(pts, edges, incident)
	Events.route_committed.emit(c, pts, Array(edges))
	Events.crew_selected.emit(null)


# --- Helpers ---------------------------------------------------------------

## One-line summary for the debug HUD.
func status_text() -> String:
	if _message_timer > 0.0:
		return _message
	if state == State.DRAWING:
		var e = route_point_edges[route_point_edges.size() - 1]
		return "%s %s route (%d m) - on %s" % ["Redrawing" if redraw else "Drawing", crew.callsign, _route_metres(), RoadGraph.edge_name[e] if e >= 0 else "?"]
	if not tips.is_empty():
		return "Unfinished %s route (%d m) - press near its end to keep drawing, Space to clear" % [crew.callsign, _route_metres()]
	return "Click an incident, then drag from a station along the roads to it"


func _say(text: String) -> void:
	_message = text
	_message_timer = 3.0


func _route_metres() -> int:
	var total = 0.0
	for i in range(1, route_points.size()):
		total += route_points[i - 1].distance_to(route_points[i])
	return int(total / float(Stage.meta["px_per_m"]))


func _zoom() -> float:
	var cam = get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0


func _pick_radius() -> float:
	return pick_radius_screen / _zoom()


func _mouse_over_ui() -> bool:
	var hovered = get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


# Closest visible, playable node from `nodes` within the pick radius.
func _nearest(nodes: Array, world_pos: Vector2):
	var best = null
	var best_d = _pick_radius()
	for point in nodes:
		if not point.visible or not Stage.is_playable(point.global_position):
			continue
		if point is Incident and point.is_finished():
			continue
		var d = point.global_position.distance_to(world_pos)
		if d <= best_d:
			best = point
			best_d = d
	return best


func _show(world_points: PackedVector2Array):
	var local = PackedVector2Array()
	for p in world_points:
		local.append(line.to_local(p))
	line.points = local
