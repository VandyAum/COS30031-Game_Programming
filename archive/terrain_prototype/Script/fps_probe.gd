extends CanvasLayer
## FpsProbe: frame-rate readout and a repeatable benchmark for the greybox
## 3D city. Shows live FPS, frame time, draw calls and triangles; runs a
## fly-around benchmark on start (and on B) and reports average FPS, 1% low
## and the worst frame. H hides the panel, F toggles shadows, V toggles
## vsync (desktop only; browsers always sync to the display).
##
## Results go to the panel, stdout and, on the web, window.cityBench (a JSON
## string) so a test harness can read them from the page.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 CanvasLayer FPS probe for the 3D city test scene.
#    Show a small panel with live FPS, average frame time over the last
#    second, draw calls and primitives per frame (RenderingServer rendering
#    info), the renderer, and the city's counts and build time from
#    City3D.stats. Add a benchmark: wait warmup_seconds for loading hitches
#    to settle, then drive the camera along City3DCamera.set_bench_angle()
#    for bench_seconds, recording every frame time; report frames, average
#    FPS, 1% low (FPS at the 99th-percentile frame time), worst frame in ms
#    and the vsync/refresh cap. Run it automatically on start (turn off with
#    the auto_bench export, '--no-bench', or '?bench=0'), rerun with B.
#    Print the result and, in a web export, store it as JSON in
#    window.cityBench and log it to the browser console. Keys: H hides the
#    panel, F toggles the sun's shadows, V toggles vsync. Works while the
#    tree is paused."
# Follow-up prompt: "Add a '--vsync=off' command-line flag so the desktop
#    benchmark measures headroom instead of the monitor's refresh cap."
# Follow-up prompt (OpenStreetMap prototype): "Show which building source
#    is visible (vicmap / osm / hybrid) and its OSM counts in the panel, list
#    O in the key help, and add '--shot=<path prefix>' (after the benchmark,
#    save <prefix>_near.png and <prefix>_far.png from fixed points on the
#    benchmark path so sources can be compared side by side) and '--quit'
#    (exit once the benchmark and screenshots are done) for scripted runs."
# Follow-up prompt (terrain): "Show whether terrain is on and the chase
#    car's speed and grade, list T (terrain) and C (chase) in the key help,
#    and with '--shot' also save <prefix>_chase.png from the chase camera
#    after a few seconds of driving."

@export var auto_bench := true
@export var warmup_seconds := 2.0
@export var bench_seconds := 20.0

var _label: Label
var _city: Node
var _camera: Camera3D
var _sun: DirectionalLight3D
var _times := PackedFloat32Array()      # benchmark frame times, seconds
var _state := "idle"                    # idle, warmup, running
var _clock := 0.0
var _window_time := 0.0
var _window_frames := 0
var _frame_ms := 0.0
var _result := ""
var _shot_prefix := ""                  # --shot=<prefix>
var _shots: Array = []                  # pending [bench t, file suffix]
var _shot_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_city = get_parent()
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	if not _city.is_node_ready():
		await _city.ready                 # the sun and stats exist once the city is built
	_camera = get_viewport().get_camera_3d()
	_sun = _city.get_node_or_null("Sun") as DirectionalLight3D
	if "--vsync=off" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_prefix = arg.get_slice("=", 1)
	var disabled := "--no-bench" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		disabled = disabled or str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('bench')")) == "0"
	if auto_bench and not disabled:
		start_bench()
	else:
		_after_bench()                  # --shot / --quit still work with --no-bench


func start_bench() -> void:
	_times.clear()
	_clock = 0.0
	_state = "warmup"


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_B:
			start_bench()
		KEY_H:
			_label.visible = not _label.visible
		KEY_F:
			if _sun:
				_sun.shadow_enabled = not _sun.shadow_enabled
		KEY_V:
			var on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if on else DisplayServer.VSYNC_ENABLED)


func _process(delta: float) -> void:
	_window_time += delta
	_window_frames += 1
	if _window_time >= 1.0:
		_frame_ms = _window_time / _window_frames * 1000.0
		_window_time = 0.0
		_window_frames = 0

	match _state:
		"warmup":
			_clock += delta
			if _camera and _camera.has_method("set_bench_angle"):
				_camera.set_bench_angle(0.0)
			if _clock >= warmup_seconds:
				_state = "running"
				_clock = 0.0
		"running":
			_clock += delta
			_times.append(delta)
			if _camera and _camera.has_method("set_bench_angle"):
				_camera.set_bench_angle(clampf(_clock / bench_seconds, 0.0, 1.0))
			if _clock >= bench_seconds:
				_state = "idle"
				_finish_bench()
				_after_bench()
		"shot":
			_take_shots()
	_label.text = _panel_text()


func _after_bench() -> void:
	if _shot_prefix != "":
		_shots = [[0.5, "_near"], [0.0, "_far"], [-1.0, "_chase"]]
		_shot_frames = 0
		_state = "shot"
	elif "--quit" in OS.get_cmdline_user_args():
		get_tree().quit()


# Moves the camera to each fixed point, lets a few frames settle (shadows),
# then saves the viewport.
func _take_shots() -> void:
	if _shots.is_empty():
		_state = "idle"
		if "--quit" in OS.get_cmdline_user_args():
			get_tree().quit()
		return
	var chase_shot: bool = _shots[0][0] < 0.0
	if chase_shot:
		if _shot_frames == 0 and _camera and _camera.has_method("start_chase"):
			_camera.start_chase()
	elif _camera and _camera.has_method("set_bench_angle"):
		_camera.set_bench_angle(_shots[0][0])
	_shot_frames += 1
	if _shot_frames < (240 if chase_shot else 6):   # let the chase car drive a while
		return
	var path: String = _shot_prefix + _shots[0][1] + ".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("CITY_SHOT ", path)
	_shots.pop_front()
	_shot_frames = 0


func _finish_bench() -> void:
	var n := _times.size()
	if n == 0:
		return
	var total := 0.0
	for t in _times:
		total += t
	var sorted := _times.duplicate()
	sorted.sort()
	var p99: float = sorted[mini(n - 1, int(n * 0.99))]
	var worst: float = sorted[n - 1]
	var data := {
		"platform": OS.get_name(),
		"web": OS.has_feature("web"),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"adapter": RenderingServer.get_video_adapter_name(),
		"viewport": str(get_viewport().get_visible_rect().size),
		"vsync": DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"shadows": _sun != null and _sun.shadow_enabled,
		"frames": n,
		"seconds": snappedf(total, 0.01),
		"avg_fps": snappedf(n / total, 0.1),
		"low_1pct_fps": snappedf(1.0 / p99, 0.1),
		"worst_frame_ms": snappedf(worst * 1000.0, 0.1),
		"city": _city.get("stats") if _city else {},
	}
	_result = "Benchmark: %.1f FPS avg, %.1f FPS 1%% low, worst frame %.1f ms (%d frames, vsync %s)" % [
		data["avg_fps"], data["low_1pct_fps"], data["worst_frame_ms"], n, "on" if data["vsync"] else "off"]
	var json := JSON.stringify(data)
	print("CITY_BENCH ", json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.cityBench = %s; console.log('CITY_BENCH', window.cityBench);" % JSON.stringify(json))


func _panel_text() -> String:
	var fps := Engine.get_frames_per_second()
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var s: Dictionary = _city.get("stats") if _city else {}
	var lines := [
		"%d FPS   %.1f ms   %d draw calls   %dk tris" % [fps, _frame_ms, calls, prims / 1000],
		"Cambermere greybox [%s%s]: %d Vicmap boxes, %d OSM (%d real heights), %d footprints, %d road segs, %dk tris, %d chunks, built in %d ms" % [
			s.get("source", "?"), ", terrain" if s.get("terrain", false) else "", s.get("buildings", 0), s.get("osm", 0), s.get("osm_tagged", 0), s.get("footprints", 0),
			s.get("roads", 0), s.get("triangles", 0) / 1000, s.get("chunks", 0), s.get("build_ms", 0)],
	]
	match _state:
		"warmup":
			lines.append("Benchmark: warming up...")
		"running":
			lines.append("Benchmark: running %d / %d s" % [int(_clock), int(bench_seconds)])
		_:
			if _result != "":
				lines.append(_result)
	var traffic := _city.get_node_or_null("Traffic") if _city else null
	if traffic and str(traffic.get("status")) != "":
		lines.append(str(traffic.get("status")))
	lines.append("Right-drag orbit · left-drag pan · wheel zoom · WASD · O buildings · T terrain · C chase · B bench · F shadows · V vsync · H hide")
	return "\n".join(lines)
