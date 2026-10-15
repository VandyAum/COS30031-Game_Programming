extends CanvasLayer
## Tutorial: short paused pop-ups that explain the controls and the game
## the first time each thing happens (first call, first dispatch, first
## blocked crew, each new stage...). Each tip shows once per session; the
## player can skip the rest.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 CanvasLayer for the dispatch game's tutorial: paused
#    pop-ups with real control and gameplay guidance, shown the first time
#    each moment happens. Tips: (1) welcome at the start - you're the
#    dispatcher, the map only shows what crews have seen, and the camera
#    controls (wheel zoom, right-drag pan, Esc pause); (2) the first call -
#    what the pulsing pin, its timer ring and the card mean, then a second
#    page on how to dispatch: press and hold on the station, trace the
#    roads to the incident, release on it (or 'Send' on the card), R to undo
#    a bit, Space to clear; (3) first dispatch - the dashed circle is what
#    the crew can see, seen traffic is coloured and fades over time, and you
#    can drag from a moving crew to redraw its route; (4) first blocked
#    crew - redraw before its dial runs out; (5) first call passed on - what
#    the hearts mean, kindly; (6) each new stage once the camera has
#    finished opening out - which new stations and kinds of call it brings,
#    read from the data so it stays correct. While a tip is open the game is
#    paused (and Esc doesn't toggle the pause), the map stays visible behind
#    a light dim, and Enter or 'Got it' continues. 'Skip tips' turns
#    the rest off for this session. Remember what was shown in the Run
#    autoload so 'Play again' doesn't repeat them."
# Follow-up prompt (show, don't just tell): "Highlight the UI or the map
#    item each tip is talking about while it is up: a pulsing yellow outline
#    around HUD controls (incident card, Send buttons, top bar, ticker, crew
#    list) and a pulsing ring around map things (the incident pin, the
#    station, a crew and its vision circle, new stations), with a pointer
#    line from the pop-up to each. For 'how to dispatch', play an animated
#    demonstration on the map: a cursor presses on the station, traces the
#    real road route to the incident in the crew colour and lets go on the
#    pin, on a loop. Move the pop-up so it never covers what it points at.
#    Targets are looked up every frame so they follow the camera and
#    rebuilt HUD cards."

const WIDTH := 600.0
const ACCENT := Color("ffd23f")
const DEMO_SECONDS := 3.0

var _dim: ColorRect
var _marks: Control
var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _next: Button
var _pages: Array = []       # [{title, body, targets}, ...] still to show
var _targets: Array = []     # current page's targets (see _target_rects)
var _t := 0.0


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	_dim.visible = false

	Events.incident_spawned.connect(func(i: Node) -> void:
		var st := _station_for(i)
		tip("first_call", [
			_page("A call has come in", "The pulsing pin on the map is an incident, and its card is in the panel on the left.\n\n" +
				"The [b]ring around the pin[/b] fills up while nobody is on the way. With a crew on the way it fills at half speed, and it stops when every crew it needs is on scene.",
				[{"world": func() -> Vector2: return i.global_position, "r": 34.0}, {"ui": func() -> Control: return _card(i)}]),
			_page("Send a crew", "[b]Press and hold[/b] on the station, [b]trace along the roads[/b] to the incident and [b]let go on the pin[/b], like the demonstration on the map.\n\n" +
				"Your crew drives exactly the way you draw. [b]R[/b] undoes the last bit, [b]Space[/b] clears it.",
				[{"world": func() -> Vector2: return st.global_position, "r": 30.0},
				 {"demo": func() -> Array: return [st, i]}] if st else []),
			_page("Or use the card", "You can also press [b]Send[/b] on the card to pick a crew, then drag from its station to the incident.",
				[{"ui": func() -> Control: return _send_buttons(i)}]),
		]))
	Events.crew_dispatched.connect(func(c: Node, _i: Node) -> void:
		tip("dispatched", [_page("On the road", "The [b]dashed circle[/b] around a crew is what it can see. Traffic it spots appears on the map in colour, then fades as the information gets old.\n\n" +
			"[color=#2fbf71][b]Green[/b][/color] roads are clear, [color=#f5a623][b]orange[/b][/color] is slow, [color=#e5383b][b]red[/b][/color] is jammed, and a dark road with a cross is blocked.\n\n" +
			"Changed your mind? [b]Press on a moving crew[/b] and draw it a new route from where it is.",
			[{"world": func() -> Vector2: return c.global_position, "r": _vision_px()}, {"ui": func() -> Control: return _hud_part("_crew_scroll")}])]))
	Events.crew_blocked.connect(func(c: Node, _e: int) -> void:
		tip("blocked", [_page("A crew is stuck", "Something is blocking the road ahead, and your map didn't know.\n\n" +
			"[b]Press on the stuck crew[/b] and draw it a way around before the [b]red dial[/b] around it runs out.",
			[{"world": func() -> Vector2: return c.global_position, "r": 40.0}])]))
	Events.incident_failed.connect(func(_i: Node) -> void:
		tip("passed_on", [_page("Passed to a neighbouring crew", "That call took too long, so a crew from next door is handling it.\n\n" +
			"The [b]hearts[/b] at the top show how many more calls can be passed on before the shift is handed over. Keep your map fresh and your routes clear!",
			[{"ui": func() -> Control: return _hud_part("_run_bar")}])]))
	Events.stage_changed.connect(func(s: int) -> void:
		if s > 0:
			# Wait for the camera and fog to finish opening out.
			await get_tree().create_timer(Stage.transition_seconds + 0.2, false).timeout
			if Stage.current == s:
				tip("stage_%d" % s, [_stage_page(s)]))
	_welcome.call_deferred()


func _welcome() -> void:
	tip("welcome", [
		_page("Welcome, dispatcher", "Emergency calls are coming in across Burrundara, and you decide which crew goes and which way it drives.\n\n" +
			"Your map only knows what your crews and stations have [b]seen[/b]. Grey roads are old news; the fog hides streets nobody has driven yet.\n\n" +
			"[b]Mouse wheel[/b] zooms, [b]right-drag[/b] moves the map, [b]Esc[/b] pauses.", []),
		_page("Your shift", "The [b]bar[/b] at the top shows your progress: the tutorial call, three stages, then the finish.\n\n" +
			"The [b]hearts[/b] show how many calls can be passed to neighbouring crews before the shift is handed over.",
			[{"ui": func() -> Control: return _hud_part("_run_bar")}]),
		_page("The news ticker", "Everything that happens is reported along the bottom, with the time. The clock in the corner runs one minute every second.",
			[{"ui": func() -> Control: return _ui_node("UI/Ticker")}]),
	])


func _page(title: String, body: String, targets: Array) -> Dictionary:
	return {"title": title, "body": body, "targets": targets}


## Show these pages once (per session), pausing the game while they're up.
func tip(id: String, pages: Array) -> void:
	if Run.skip_tips or Run.tips_seen.has(id) or Run.over:
		return
	Run.tips_seen[id] = true
	_pages.append_array(pages)
	if not _panel.visible:
		_show_next()


func _show_next() -> void:
	if _pages.is_empty():
		_close()
		return
	var page: Dictionary = _pages.pop_front()
	_title.text = page["title"]
	_body.text = page["body"]
	_targets = page["targets"]
	_t = 0.0
	_next.text = "Next" if not _pages.is_empty() else "Got it"
	_panel.visible = true
	_dim.visible = true
	_panel.modulate.a = 0.0             # placed (and shown) next frame, once sized
	Run.modal = true
	get_tree().paused = true
	_next.grab_focus.call_deferred()
	_place_panel.call_deferred()


func _close() -> void:
	_panel.visible = false
	_dim.visible = false
	_targets = []
	_marks.queue_redraw()        # clear the highlights
	Run.modal = false
	if not Run.over:
		get_tree().paused = false


func _skip() -> void:
	Run.skip_tips = true
	_pages.clear()
	_close()


func _unhandled_key_input(event: InputEvent) -> void:
	if _panel.visible and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER:
			_show_next()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _panel.visible:
		_t += delta
		_marks.queue_redraw()


# --- Finding things to point at ---------------------------------------------------

func _hud() -> Node:
	return _ui_node("UI/HUD")


func _ui_node(path: String) -> Control:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(path) as Control if scene else null


func _hud_part(field: String) -> Control:
	var hud := _hud()
	return hud.get(field) as Control if hud else null


func _card(inc: Node) -> Control:
	var hud := _hud()
	if hud == null or not is_instance_valid(inc):
		return null
	var card = hud._cards.get(inc)
	return card if card != null and is_instance_valid(card) else null


func _send_buttons(inc: Node) -> Control:
	var card := _card(inc)
	if card == null:
		return null
	for b in card.find_children("*", "HFlowContainer", true, false):
		return b
	return card


# The station a first call would be answered from: in play, with a free crew
# of a type the incident needs, nearest first.
func _station_for(inc: Node) -> Node2D:
	var best: Node2D = null
	for st in get_tree().get_nodes_in_group("stations"):
		if st.is_playable() and inc.type.needs(st.type.id) and st.first_available() != null:
			if best == null or st.global_position.distance_to(inc.global_position) < best.global_position.distance_to(inc.global_position):
				best = st
	return best


func _vision_px() -> float:
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam else 1.0
	return Knowledge.sight_radius_m * float(Stage.meta["px_per_m"]) * z + 6.0


func _to_screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


# Screen rectangles of the current targets (for placing the pop-up).
func _target_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t: Dictionary in _targets:
		if t.has("ui"):
			var c: Control = t["ui"].call()
			if c and c.is_visible_in_tree():
				out.append(c.get_global_rect())
		elif t.has("world"):
			var p := _to_screen(t["world"].call())
			var r: float = t.get("r", 30.0)
			out.append(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0))
		elif t.has("demo"):
			var ends: Array = t["demo"].call()
			if ends[0] and is_instance_valid(ends[1]):
				out.append(Rect2(_to_screen(ends[0].global_position), Vector2.ZERO).expand(_to_screen(ends[1].global_position)).grow(40))
	return out


# Put the pop-up over the map where it covers none of the targets.
func _place_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	var map := Rect2(Vector2(450, 102), screen - Vector2(450, 102 + 64))
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	var margin := 24.0
	var spots := [
		map.get_center() - size / 2.0,
		Vector2(map.get_center().x - size.x / 2.0, map.position.y + margin),
		Vector2(map.get_center().x - size.x / 2.0, map.end.y - size.y - margin),
		Vector2(map.position.x + margin, map.get_center().y - size.y / 2.0),
		Vector2(map.end.x - size.x - margin, map.get_center().y - size.y / 2.0),
		Vector2(map.position.x + margin, map.end.y - size.y - margin),
		Vector2(map.end.x - size.x - margin, map.position.y + margin),
	]
	var rects := _target_rects()
	var choice: Vector2 = spots[0]
	for spot: Vector2 in spots:
		var r := Rect2(spot, size).grow(16)
		if not rects.any(func(t: Rect2) -> bool: return t.intersects(r)):
			choice = spot
			break
	_panel.position = choice
	_panel.modulate.a = 1.0


# --- Drawing highlights -------------------------------------------------------------

func _draw_marks() -> void:
	if not _panel.visible:
		return
	var beat := 0.5 + 0.5 * sin(_t * 5.0)
	var panel_rect := _panel.get_global_rect()
	for t: Dictionary in _targets:
		if t.has("demo"):
			_draw_demo(t["demo"].call())
			continue
		var centre: Vector2
		if t.has("ui"):
			var c: Control = t["ui"].call()
			if c == null or not c.is_visible_in_tree():
				continue
			var r := c.get_global_rect().grow(6.0 + 4.0 * beat)
			var box := StyleBoxFlat.new()
			box.draw_center = false
			box.border_color = ACCENT
			box.set_border_width_all(4)
			box.set_corner_radius_all(12)
			box.shadow_color = Color(ACCENT, 0.5 * beat)
			box.shadow_size = 10
			_marks.draw_style_box(box, r)
			centre = r.get_center()
			_pointer(panel_rect, r)
		else:
			centre = _to_screen(t["world"].call())
			var rad: float = t.get("r", 30.0) + 6.0 * beat
			_marks.draw_arc(centre, rad + 6.0, 0, TAU, 64, Color(ACCENT, 0.35 * beat), 10.0)
			_marks.draw_arc(centre, rad, 0, TAU, 64, ACCENT, 4.0)
			_pointer(panel_rect, Rect2(centre - Vector2(rad, rad), Vector2(rad, rad) * 2.0))


# A line from the pop-up's edge to just outside a target.
func _pointer(from: Rect2, to: Rect2) -> void:
	if from.intersects(to):
		return
	var a := _edge_point(from, to.get_center())
	var b := _edge_point(to, a)
	_marks.draw_line(a, b, Color(ACCENT, 0.9), 3.0, true)
	_marks.draw_circle(b, 5.0, ACCENT)


func _edge_point(r: Rect2, toward: Vector2) -> Vector2:
	var c := r.get_center()
	var d := toward - c
	if d.length() < 0.01:
		return c
	var sx := (r.size.x / 2.0) / absf(d.x) if d.x != 0.0 else INF
	var sy := (r.size.y / 2.0) / absf(d.y) if d.y != 0.0 else INF
	return c + d * minf(minf(sx, sy), 1.0)


# Animated demonstration: press on the station, trace the road route to
# the incident, let go on the pin. Loops every DEMO_SECONDS.
func _draw_demo(ends: Array) -> void:
	var st: Node2D = ends[0]
	var inc: Node2D = ends[1]
	if st == null or not is_instance_valid(inc):
		return
	var pts := _demo_route(st, inc)
	if pts.size() < 2:
		return
	var screen := PackedVector2Array()
	var total := 0.0
	for k in pts.size():
		screen.append(_to_screen(pts[k]))
		if k > 0:
			total += screen[k - 1].distance_to(screen[k])
	var phase := fmod(_t, DEMO_SECONDS) / DEMO_SECONDS
	var draw_t := clampf((phase - 0.15) / 0.65, 0.0, 1.0)   # press, trace, release, pause
	var want := total * draw_t
	var shown := PackedVector2Array([screen[0]])
	var cursor := screen[0]
	var run := 0.0
	for k in range(1, screen.size()):
		var seg := screen[k - 1].distance_to(screen[k])
		if run + seg >= want:
			cursor = screen[k - 1].lerp(screen[k], (want - run) / maxf(seg, 0.001))
			shown.append(cursor)
			break
		run += seg
		shown.append(screen[k])
		cursor = screen[k]
	var colour: Color = st.type.colour
	if shown.size() >= 2:
		_marks.draw_polyline(shown, Color.WHITE, 10.0, true)
		_marks.draw_polyline(shown, colour, 6.0, true)
	# Press ripple at the start, release ripple at the end.
	if phase < 0.2:
		_marks.draw_arc(screen[0], 10.0 + 60.0 * phase, 0, TAU, 32, Color(ACCENT, 1.0 - phase * 5.0), 3.0)
	if draw_t >= 1.0:
		var k := (phase - 0.8) / 0.2
		_marks.draw_arc(screen[screen.size() - 1], 10.0 + 30.0 * k, 0, TAU, 32, Color(ACCENT, 1.0 - k), 3.0)
	# The cursor: a hand-held dot, filled while the button is held.
	var held := phase >= 0.1 and draw_t < 1.0
	_marks.draw_circle(cursor, 11.0, Color(1, 1, 1, 0.9))
	_marks.draw_circle(cursor, 11.0, Color("1d2433"), false, 2.5, true)
	if held:
		_marks.draw_circle(cursor, 6.0, Color("1d2433"))


var _demo_cache := {}

func _demo_route(st: Node2D, inc: Node2D) -> PackedVector2Array:
	var key := [st.get_instance_id(), inc.get_instance_id()]
	if _demo_cache.has(key):
		return _demo_cache[key]
	var pts := PackedVector2Array([st.global_position])
	var a = RoadGraph.snap(st.global_position, 200.0)
	var b = RoadGraph.snap(inc.global_position, 200.0)
	if a != null and b != null:
		pts.append_array(RoadGraph.route(a, b).points)
	pts.append(inc.global_position)
	_demo_cache[key] = pts
	return pts


# What a new stage brings: its stations and the kinds of call it adds.
func _stage_page(s: int) -> Dictionary:
	var lines: Array[String] = []
	var targets := [{"ui": func() -> Control: return _hud_part("_run_bar")}]
	var stations := get_tree().get_first_node_in_group("station_manager")
	if stations:
		for st: Station in stations.get_stations():
			if Stage.stage_at(st.global_position) == s:
				lines.append("[color=#%s]■[/color] %s" % [st.type.colour.to_html(false), st.station_name])
				targets.append({"world": func() -> Vector2: return st.global_position, "r": 26.0})
	var calls: Array[String] = []
	var manager := get_tree().get_first_node_in_group("incident_manager")
	if manager:
		for t: IncidentType in manager.types:
			if t.min_stage == s and not calls.has(t.display_name):
				calls.append(t.display_name)
	var body := "The map has grown to [b]%s[/b], and more of it is under fog.\n\n" % Stage.stage_name(s)
	if not lines.is_empty():
		body += "[b]New stations[/b] (circled on the map)\n" + "\n".join(lines) + "\n\n"
	if not calls.is_empty():
		body += "[b]New kinds of call[/b]\n" + ", ".join(calls) + "\n\n"
	body += "Resolve %d calls to finish this stage. The bar at the top shows how far you've come." % Run.needed_this_stage()
	return _page("Stage %d" % s, body, targets)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.07, 0.1, 0.3)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.98, 0.99)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(28)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 12
	style.border_color = ACCENT
	style.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", Color("1d2433"))
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(WIDTH - 56, 0)
	_body.add_theme_font_size_override("normal_font_size", 20)
	_body.add_theme_font_size_override("bold_font_size", 20)
	_body.add_theme_color_override("default_color", Color(0.18, 0.2, 0.24))
	box.add_child(_body)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var skip := Button.new()
	skip.text = "Skip tips"
	skip.flat = true
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45))
	skip.pressed.connect(_skip)
	buttons.add_child(skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_next = Button.new()
	_next.add_theme_font_size_override("font_size", 22)
	_next.custom_minimum_size = Vector2(150, 48)
	_next.pressed.connect(_show_next)
	buttons.add_child(_next)
