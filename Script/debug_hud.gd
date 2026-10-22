extends CanvasLayer
## DebugHUD: on-screen help, live status and an event log so you can SEE the
## systems working while testing. F1 toggles it. Safe to leave in the scene;
## it only reads from other systems.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 CanvasLayer debug HUD for our dispatch game prototype,
#    built entirely in code (no extra scene). Top-left: a short controls
#    cheat-sheet (drag from a station to draw, release on an incident, pan,
#    zoom, clear/undo, and the debug keys F1-F4). Under it a live status block
#    refreshed a few times per second: current stage name and number, the
#    route drawer's status_text() (found via the 'route_drawer' group), how
#    many roads the player knows vs total playable roads, the road name under
#    the mouse, and FPS. Bottom-left: a scrolling log of the last 12 signals
#    emitted on the Events autoload with a timestamp and readable arguments
#    (node names instead of object ids). Connect to every Events signal
#    automatically from get_signal_list() so new signals show up without
#    editing the HUD. Use semi-transparent dark panels and readable text."
# Follow-up prompt: "Jessie's HUD now owns the left side and top bar, so
#    right-align the debug panels below the navigation bar (event log
#    bottom-right above the map credit), update the help text for the
#    milestone 1 controls, and add F5 (spawn an incident now)."
# Follow-up prompt: "The true world now changes constantly; don't log
#    road_truth_changed (it would flood the log and it's not player info),
#    and add F6 to block the road under the mouse for testing obstacles."
# Follow-up prompt: "Turn the debug panels off by default (F1 still shows
#    them); the controls are documented in the README."

const LOG_LINES := 12

var _help: Label
var _status: Label
var _log: Label
var _lines: Array[String] = []
var _timer := 0.0


func _ready() -> void:
	layer = 100
	visible = false
	_help = _panel(Vector2.ZERO, 0.0)
	_help.text = "\n".join([
		"DEBUG HUD (F1 show/hide)",
		"Click an incident pin (or its card) to select it.",
		"Hold LEFT MOUSE on a station square and drag along",
		"the roads; release on the incident to dispatch.",
		"Or press 'Send ...' on the card, then drag from the station.",
		"Retrace to undo. Released early? Press the line's end.",
		"RIGHT drag pan  Wheel zoom  Space clear  R trim",
		"F2 road graph  F3 reveal roads  F4 next stage  F5 spawn",
		"F6 block the road under the mouse (test obstacles)",
	])
	_status = _panel(Vector2.ZERO, 0.0)
	_log = _panel(Vector2.ZERO, 1.0)

	for sig in Events.get_signal_list():
		if sig["name"] == "road_truth_changed":
			continue
		var n: int = sig["args"].size()
		var cb: Callable
		match n:
			0: cb = _on_event0
			1: cb = _on_event1
			2: cb = _on_event2
			_: cb = _on_event3
		Events.connect(sig["name"], cb.bind(sig["name"]))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_F1:
		visible = not visible
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_F6:
		var mouse_world := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
		var p := RoadGraph.snap(mouse_world, 40.0)
		if p:
			World.block(p.edge, "Test roadblock", null, 60.0)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not visible:
		return
	_timer = 0.2

	var known := 0
	var playable := 0
	for e in RoadGraph.edge_count():
		if RoadGraph.is_playable(e):
			playable += 1
			if Knowledge.is_known(e):
				known += 1
	var drawer := get_tree().get_first_node_in_group("route_drawer")
	var mouse_world := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var under := RoadGraph.snap(mouse_world, 25.0)
	_status.text = "\n".join([
		"Stage %d: %s" % [Stage.current, Stage.stage_name()],
		drawer.status_text() if drawer else "(no route drawer in scene)",
		"Roads known: %d / %d playable   (fade %ds)" % [known, playable, int(Knowledge.fade_seconds)],
		"Under mouse: %s" % (RoadGraph.edge_name[under.edge] if under and RoadGraph.edge_name[under.edge] != "" else "-"),
		"FPS %d" % Engine.get_frames_per_second(),
	])
	var vp := get_viewport().get_visible_rect().size
	_help.position = Vector2(vp.x - _help.size.x - 12, 114)
	_status.position = Vector2(vp.x - _status.size.x - 12, _help.position.y + _help.size.y + 8)
	_log.position = Vector2(vp.x - _log.size.x - 12, vp.y - _log.size.y - 100)   # above ticker + credit


func _on_event0(sig: String) -> void:
	_add(sig, [])

func _on_event1(a, sig: String) -> void:
	_add(sig, [a])

func _on_event2(a, b, sig: String) -> void:
	_add(sig, [a, b])

func _on_event3(a, b, c, sig: String) -> void:
	_add(sig, [a, b, c])


func _add(sig: String, args: Array) -> void:
	var parts: Array[String] = []
	for a in args:
		if a is Node:
			parts.append(a.name)
		elif a is PackedVector2Array or a is Array:
			parts.append("[%d]" % a.size())
		elif sig.begins_with("road_") and a is int and a < RoadGraph.edge_count():
			parts.append(RoadGraph.edge_name[a] if RoadGraph.edge_name[a] != "" else "road %d" % a)
		else:
			parts.append(str(a))
	_lines.append("%6.1fs  %s(%s)" % [Knowledge.clock, sig, ", ".join(parts)])
	while _lines.size() > LOG_LINES:
		_lines.pop_front()
	_log.text = "EVENTS\n" + "\n".join(_lines)


func _panel(pos: Vector2, _anchor_bottom: float) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.09, 0.12, 0.72)
	box.set_content_margin_all(8)
	box.set_corner_radius_all(6)
	label.add_theme_stylebox_override("normal", box)
	add_child(label)
	return label
