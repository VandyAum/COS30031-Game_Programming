extends Node
## Sfx (autoload): every sound in the game. Game events are heard by
## listening to Events (nothing else needs to know audio exists); debris
## impacts call Sfx.play_at(). Every button click is wired up automatically.
## M mutes. Sounds: Kenney "Interface Sounds" and "Impact Sounds" (CC0),
## plus ambience, engine, siren and pass-by loops from Freesound (CC0, see
## Assets/Audio/FREESOUND_CREDITS.txt).

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'Sfx' for the dispatch game using the CC0
#    Kenney sounds in Assets/Audio. A table of named sounds (each a list of
#    files to vary between, with a base volume), a small pool of
#    AudioStreamPlayers, play(key, volume_db, pitch) that skips the same key
#    played within 60 ms, and play_at(key, world_pos) that only plays for
#    things on screen, with a little pitch variation. Hook game events
#    through Events: new call, incident selected, route drawing started,
#    crew dispatched, arrived, wrong crew sent, obstacle hit, call urgent
#    (ring three-quarters full), resolved, passed on, crew ready again, the
#    map growing, pause, win and lose. Connect every BaseButton that enters
#    the tree to a click. M toggles mute with a ticker message. Keep working
#    while the game is paused."
# Follow-up prompt (ambience and travel): "Add CC0 Freesound loops: a quiet
#    city ambience bed, an engine hum while crews are driving (louder with
#    more crews out, fading smoothly), a short siren burst from a random
#    point in the siren recording when a crew is dispatched, and a car
#    passing when a crew gets back to its station. Loops pause with the
#    game. Make M mute the master bus so the loops go quiet too."

const DIR := "res://Assets/Audio/"
## key -> [[files...], base volume dB]
const TABLE := {
	&"call": [["bong_001"], -6.0],
	&"select": [["select_002"], -8.0],
	&"click": [["click_002"], -10.0],
	&"draw": [["tick_002"], -8.0],
	&"dispatch": [["confirmation_001"], -6.0],
	&"arrive": [["drop_002"], -6.0],
	&"wrong": [["error_002"], -6.0],
	&"blocked": [["error_004"], -3.0],
	&"urgent": [["question_002"], -8.0],
	&"resolved": [["confirmation_002"], -4.0],
	&"passed_on": [["error_006"], -4.0],
	&"ready": [["switch_002"], -14.0],
	&"stage": [["maximize_006"], -3.0],
	&"pause": [["toggle_002"], -8.0],
	&"win": [["confirmation_004"], 0.0],
	&"lose": [["minimize_008"], 0.0],
	&"pass_by": [["fs_car_passing_hinzebeat_171447"], -14.0],
	# Debris impacts (DebrisType.impact_sound)
	&"hit_rubber": [["impactSoft_medium_000", "impactSoft_medium_001"], -10.0],
	&"hit_glass": [["impactGlass_light_000", "impactGlass_light_001"], -12.0],
	&"hit_metal": [["impactMetal_light_000", "impactMetal_light_001"], -12.0],
	&"hit_wood": [["impactWood_light_000", "impactWood_light_001"], -10.0],
	&"hit_plastic": [["impactPlate_light_000", "impactPlate_light_001"], -12.0],
	&"hit_soft": [["impactSoft_heavy_000", "impactSoft_heavy_001"], -10.0],
}
const POOL_SIZE := 12
const AMBIENCE := "fs_city_loop_qubodup_223093"
const ENGINE := "fs_engine_loop_qubodup_54909"
const SIREN := "fs_emergency_siren_onderwish_470504"
## Ambience bed volume, engine hum range (one crew .. four or more), siren.
const AMBIENCE_DB := -24.0
const ENGINE_DB := Vector2(-30.0, -20.0)
const SIREN_DB := -17.0
## Seconds of siren per dispatch.
const SIREN_SECONDS := 2.4

var muted := false
var _streams := {}            # key -> Array[AudioStream]
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _ambience: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _siren: AudioStreamPlayer
var _siren_tween: Tween
var _engine_target := -80.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in TABLE:
		var list: Array[AudioStream] = []
		for f in TABLE[key][0]:
			list.append(load(DIR + f + ".ogg"))
		_streams[key] = list
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	Events.incident_spawned.connect(func(_i: Node) -> void: play(&"call"))
	Events.incident_selected.connect(func(i: Node) -> void:
		if i != null:
			play(&"select"))
	Events.route_drawing_started.connect(func(_c: Node) -> void: play(&"draw"))
	Events.route_committed.connect(func(_c: Node, _p: PackedVector2Array, _e: Array) -> void: play(&"dispatch"))
	Events.crew_arrived.connect(func(_c: Node, _i: Node) -> void: play(&"arrive"))
	Events.crew_blocked.connect(func(_c: Node, _e: int) -> void: play(&"blocked"))
	Events.crew_ready.connect(func(_c: Node) -> void: play(&"ready"))
	Events.incident_urgent.connect(func(_i: Node) -> void: play(&"urgent"))
	Events.incident_resolved.connect(func(_i: Node) -> void: play(&"resolved"))
	Events.incident_failed.connect(func(_i: Node) -> void: play(&"passed_on"))
	Events.incident_updated.connect(_on_incident_updated)
	Events.stage_changed.connect(func(s: int) -> void:
		if s > 0:
			play(&"stage"))
	Events.paused_changed.connect(func(_p: bool) -> void: play(&"pause"))
	Events.run_ended.connect(func(how: String) -> void: play(&"win" if how == "won" else &"lose"))
	get_tree().node_added.connect(_on_node_added)

	_ambience = _loop_player(AMBIENCE, AMBIENCE_DB)
	_ambience.play()
	_engine = _loop_player(ENGINE, -80.0)
	_siren = _loop_player(SIREN, SIREN_DB)
	Events.crew_dispatched.connect(func(_c: Node, _i: Node) -> void: _siren_burst())
	Events.crew_returned.connect(func(_c: Node) -> void: play(&"pass_by"))
	Events.crew_state_changed.connect(func(_c: Node) -> void: _update_engine())
	Events.run_ended.connect(func(_how: String) -> void:
		_engine_target = -80.0
		_siren.stop())


func _process(delta: float) -> void:
	# Engine hum eases towards its target so crews setting off don't click.
	_engine.volume_db = move_toward(_engine.volume_db, _engine_target, 30.0 * delta)
	if _engine.volume_db <= -79.0 and _engine.playing:
		_engine.stop()
	elif _engine.volume_db > -79.0 and not _engine.playing:
		_engine.play()


# A looping player that pauses along with the game.
func _loop_player(file: String, volume_db: float) -> AudioStreamPlayer:
	var stream: AudioStreamOggVorbis = load(DIR + file + ".ogg")
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	return p


func _update_engine() -> void:
	var driving := get_tree().get_nodes_in_group("crews").filter(func(c: Node) -> bool:
		return c.state == Crew.State.EN_ROUTE or c.state == Crew.State.RETURNING).size()
	_engine_target = -80.0 if driving == 0 else lerpf(ENGINE_DB.x, ENGINE_DB.y, clampf((driving - 1) / 3.0, 0.0, 1.0))


# A couple of seconds of siren from a random point, fading out.
func _siren_burst() -> void:
	if _siren_tween:
		_siren_tween.kill()
	_siren.volume_db = SIREN_DB
	_siren.play(randf_range(0.0, _siren.stream.get_length() - SIREN_SECONDS - 1.0))
	_siren_tween = create_tween()
	_siren_tween.tween_interval(SIREN_SECONDS * 0.6)
	_siren_tween.tween_property(_siren, "volume_db", -60.0, SIREN_SECONDS * 0.4)
	_siren_tween.tween_callback(_siren.stop)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(0, muted)
		Events.ticker_message.emit("Sound %s (M)" % ("off" if muted else "on"))


func play(key: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(key):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(key, -1000)) < 60:
		return
	_last_played[key] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key].pick_random()
	p.volume_db = TABLE[key][1] + volume_db
	p.pitch_scale = pitch
	p.play()


## For things in the world: only heard if on screen.
func play_at(key: StringName, world_pos: Vector2, volume_db := 0.0) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam:
		var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
		if not Rect2(cam.get_screen_center_position() - half, half * 2.0).has_point(world_pos):
			return
	play(key, volume_db, randf_range(0.9, 1.12))


# A wrong crew turned away: Incident sets a "Wrong crew" note (count once).
func _on_incident_updated(i: Node) -> void:
	if i.note.begins_with("Wrong crew") and i.get_meta("sfx_note", "") != i.note:
		i.set_meta("sfx_note", i.note)
		play(&"wrong")


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(play.bind(&"click"))
