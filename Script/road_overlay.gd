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

# Indexed by World.Traffic (CLEAR, SLOW, JAMMED, BLOCKED).
const TRAFFIC_COLOURS: Array[Color] = [
	Color("2fbf71"),
	Color("f5a623"),
	Color("e5383b"),
	Color("7a1020"),
]
## Line width per road class (local street, collector, main road).
const CLASS_WIDTH := [3.5, 5.0, 7.0]
const REDRAW_INTERVAL := 0.25

var show_debug_graph := false
var _redraw_timer := 0.0


func _ready() -> void:
	Events.road_observed.connect(func(_edge: int) -> void: queue_redraw())


func _process(delta: float) -> void:
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_pressed() and (event as InputEventKey).keycode == KEY_F2:
		show_debug_graph = not show_debug_graph
		queue_redraw()


## Colour for a road given what the player knows about it.
func knowledge_colour(level: int, freshness: float) -> Color:
	var fresh: Color = TRAFFIC_COLOURS[level]
	# Perceived lightness (Rec. 601 luma) keeps "worse = darker" once grey.
	var luma := fresh.r * 0.299 + fresh.g * 0.587 + fresh.b * 0.114
	var stale := Color(luma, luma, luma).lerp(Color(0.55, 0.55, 0.55), 0.25)
	# Ease so colour hangs on for a while, then drains (reads as "ageing").
	return stale.lerp(fresh, smoothstep(0.0, 1.0, freshness))


func _draw() -> void:
	for e in RoadGraph.edge_count():
		if not Knowledge.is_known(e):
			continue
		var level := Knowledge.known_level(e)
		var colour := knowledge_colour(level, Knowledge.freshness(e))
		var width: float = CLASS_WIDTH[RoadGraph.edge_class(e)]
		draw_polyline(RoadGraph.edge_pts[e], colour, width, true)
		if level == World.Traffic.BLOCKED:
			var m := RoadGraph.edge_midpoint(e)
			draw_line(m + Vector2(-6, -6), m + Vector2(6, 6), colour.darkened(0.4), 3.0)
			draw_line(m + Vector2(-6, 6), m + Vector2(6, -6), colour.darkened(0.4), 3.0)

	if show_debug_graph:
		for e in RoadGraph.edge_count():
			draw_polyline(RoadGraph.edge_pts[e], Color(0.2, 0.4, 1.0, 0.8), 1.5)
		for p in RoadGraph.node_positions:
			draw_circle(p, 3.0, Color(1, 0.2, 0.8))
