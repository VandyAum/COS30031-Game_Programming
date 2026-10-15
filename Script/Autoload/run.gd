extends Node
## Run (autoload): one play session. Lives, the in-game clock, progress
## through the stages (by incidents resolved), run statistics for the end
## screen, pausing, and starting again.
##
## Progress bar: tutorial bauble -> stage 1 -> stage 2 -> stage 3 -> "you win"
## bauble. Each stage advances after `resolved_to_advance[stage]` incidents.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 autoload 'Run' for the dispatch game's milestone 3:
#    three lives (lose_life(reason) emits Events.lives_changed and ends the
#    run at zero with 'Crews overwhelmed. Neighbouring councils are sending
#    help.'); an in-game clock where one real second is one minute, shown as
#    HH:MM from a start time; stage progression where the tutorial ends after
#    its single call and each later stage ends after a set number of resolved
#    incidents, moving Stage to the next stage, and finishing stage 3 wins;
#    progress() giving 0..1 along a bar with the tutorial bauble at 0, three
#    equal stage segments and the win bauble at 1; statistics for the end
#    screen (resolved, failed, lives lost, crews stopped by obstacles the map
#    didn't show, wrong crews sent, share of roads ever seen); Escape toggles
#    pause (which stops the game clock); and restart() that resets the other
#    autoloads and reloads the scene. Post short ticker messages through
#    Events.ticker_message for stage changes and lost lives."
# Follow-up prompt (all-ages tone): "Remove 'life lost' wording - don't
#    baby the player, but don't guilt them either. A missed incident is
#    'passed to a neighbouring crew' in the ticker; the hearts still show
#    how many more can be passed on before the run ends."
# Follow-up prompt (tutorial): "Add 'modal' (a tutorial tip is open, so Esc
#    mustn't toggle the pause) and remember which tips were shown and
#    whether the player skipped them, surviving 'Play again'."
# Follow-up prompt (font): "Map labels drawn in code use ThemeDB.fallback_font;
#    point it at the project theme's font (Atkinson Hyperlegible Next) so the
#    map and the HUD match."

const FAIL_LINE := "Crews overwhelmed. Neighbouring councils are sending help."

@export var start_lives := 3
## Clock shown at the start of a run (24 h, can be fractional).
@export var start_hour := 6.0
## In-game minutes per real second.
@export var minutes_per_second := 1.0
## Incidents to resolve to finish each stage (tutorial, 1, 2, 3).
@export var resolved_to_advance: Array[int] = [1, 5, 7, 9]

var lives := 3
var resolved_in_stage := 0
var over := false
var result := ""             # "won" / "lost"
var stats := {}
## A tutorial tip is open (it owns the pause).
var modal := false
## Tutorial tips already shown this session, and whether to skip the rest.
var tips_seen := {}
var skip_tips := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # so Escape works while paused
	var project_font := ThemeDB.get_project_theme().default_font if ThemeDB.get_project_theme() else null
	if project_font:
		ThemeDB.fallback_font = project_font
	_reset_state()
	Events.incident_resolved.connect(_on_resolved)
	Events.incident_failed.connect(func(_i: Node) -> void: stats["failed"] += 1)
	Events.crew_blocked.connect(func(c: Node, _e: int) -> void:
		stats["blocked"] += 1
		if not c.blocked_was_known:
			stats["blocked_unknown"] += 1)
	Events.incident_updated.connect(func(i: Node) -> void:
		if i.note.begins_with("Wrong crew") and i.get_meta("counted_note", "") != i.note:
			i.set_meta("counted_note", i.note)
			stats["wrong_crew"] += 1)
	Events.stage_changed.connect(func(s: int) -> void:
		resolved_in_stage = 0
		Events.progress_changed.emit()
		if s > 0:
			Events.ticker_message.emit("[color=#ffd166]The map grows: %s[/color]" % Stage.stage_name(s)))


func _reset_state() -> void:
	lives = start_lives
	resolved_in_stage = 0
	over = false
	result = ""
	stats = {"resolved": 0, "failed": 0, "lives_lost": 0, "blocked": 0, "blocked_unknown": 0, "wrong_crew": 0}


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and (event as InputEventKey).keycode == KEY_ESCAPE and not over and not modal:
		get_tree().paused = not get_tree().paused
		Events.paused_changed.emit(get_tree().paused)


func lose_life(reason: String) -> void:
	if over:
		return
	lives -= 1
	stats["lives_lost"] += 1
	Events.lives_changed.emit(lives)
	Events.ticker_message.emit("[color=#ffb347]Passed to a neighbouring crew:[/color] %s." % reason)
	if lives <= 0:
		_end("lost")


func _on_resolved(_inc: Node) -> void:
	if over:
		return
	stats["resolved"] += 1
	resolved_in_stage += 1
	Events.progress_changed.emit()
	if resolved_in_stage >= needed_this_stage():
		if Stage.current >= Stage.stage_count() - 1:
			_end("won")
		else:
			Stage.set_stage(Stage.current + 1)


func needed_this_stage() -> int:
	return resolved_to_advance[mini(Stage.current, resolved_to_advance.size() - 1)]


## 0 = tutorial bauble, 1 = win bauble, stages are equal thirds between.
func progress() -> float:
	if result == "won":
		return 1.0
	if Stage.current == 0:
		return 0.0
	var within := clampf(float(resolved_in_stage) / needed_this_stage(), 0.0, 1.0)
	return (Stage.current - 1 + within) / 3.0


func minutes() -> float:
	return start_hour * 60.0 + Knowledge.clock * minutes_per_second


func clock_text() -> String:
	var m := int(minutes())
	return "%02d:%02d" % [(m / 60) % 24, m % 60]


## Share of playable roads the player has ever seen.
func coverage() -> float:
	var seen := 0
	var total := 0
	for e in RoadGraph.edge_count():
		if RoadGraph.is_playable(e):
			total += 1
			if Knowledge.is_known(e):
				seen += 1
	return float(seen) / maxi(total, 1)


func _end(how: String) -> void:
	over = true
	result = how
	Events.ticker_message.emit("[color=#ffd166]%s[/color]" % ("All calls answered. Burrundara is safe!" if how == "won" else FAIL_LINE))
	Events.run_ended.emit(how)
	get_tree().paused = true


func restart() -> void:
	get_tree().paused = false
	modal = false
	_reset_state()
	Knowledge.reset()
	World.reset()
	Stage.reset()
	get_tree().reload_current_scene()
