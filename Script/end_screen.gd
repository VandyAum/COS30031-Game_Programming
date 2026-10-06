extends CanvasLayer
## EndScreen: the pause cover and the end-of-run screen (win or lose) with a
## short after-action summary tying the outcome to the map data.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 CanvasLayer that keeps working while the tree is
#    paused and shows two overlays. Pause (Events.paused_changed): an opaque
#    cover that hides the game world (the spec says pausing is a break, not
#    planning time) with 'Paused - press Esc to resume'. End of run
#    (Events.run_ended): a centred card that says either 'Crews overwhelmed.
#    Neighbouring councils are sending help.' or that every call was
#    answered, a basic after-action report from Run.stats (incidents
#    resolved and failed, lives lost, crews stopped by obstacles the map
#    didn't show, wrong crews sent, share of roads ever seen, time reached),
#    a one-line real-world note, the spec's closing reveal that the map you
#    just built is what Vicmap does for Victoria every day, and a 'Play
#    again' button that calls Run.restart(). Services are always heroes."
# Follow-up prompt: "Don't repeat 'Crews overwhelmed' under the heading, and
#    get singular/plural right in the report."
# Follow-up prompt (all-ages tone): "No 'lives' or 'failed' in the report:
#    say how many calls were passed to neighbouring crews and what time the
#    shift reached."
# Follow-up prompt (credits): "Add a 'Credits' button next to 'Play again'
#    on the end screen, and one on the pause screen, opening the credits
#    and licences overlay (Credits.make_overlay) with a Back button."

var _pause: Control
var _end: Control


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause = _cover(Color(0.13, 0.15, 0.2, 1.0))
	var label := Label.new()
	label.text = "Paused\npress Esc to resume"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color.WHITE)
	var pause_box := VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 28)
	pause_box.set_anchors_preset(Control.PRESET_CENTER)
	pause_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.add_child(pause_box)
	pause_box.add_child(label)
	pause_box.add_child(_credits_button())
	_pause.visible = false
	Events.paused_changed.connect(func(p: bool) -> void: _pause.visible = p and not Run.over)
	Events.run_ended.connect(_show_end)


func _cover(colour: Color) -> Control:
	var c := ColorRect.new()
	c.color = colour
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


func _show_end(how: String) -> void:
	_pause.visible = false
	_end = _cover(Color(0.08, 0.09, 0.12, 0.82))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.97, 0.98)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(36)
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(760, 0)
	_end.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	var won := how == "won"
	_line(box, "Every call answered" if won else "Crews overwhelmed", 46, Color("1d2433"))
	_line(box, "Burrundara is safe for another day. Brilliant dispatching." if won else "Neighbouring councils are sending help.",
		22, Color("3b4c6e"))

	var s: Dictionary = Run.stats
	var report := [
		"%s resolved, %d passed to neighbouring crews" % [_count(s["resolved"], "incident"), s["failed"]],
		"%s stopped by obstacles the map didn't show" % _count(s["blocked_unknown"], "crew"),
		"%s sent" % _count(s["wrong_crew"], "wrong crew"),
		"%d%% of roads seen by your crews" % int(Run.coverage() * 100.0),
		"Shift reached %s" % Run.clock_text(),
	]
	_line(box, "After-action report", 26, Color("1d2433"))
	for r in report:
		_line(box, "•  " + r, 20, Color(0.2, 0.2, 0.2))
	_line(box, "Real crews depend on knowing what is where: every stale road and wrong entry costs them minutes.",
		17, Color(0.35, 0.35, 0.35))
	_line(box, "Before Vicmap, someone had to build the map. Today, that was you. The map you just built and kept fresh is what Vicmap does for Victoria every day.",
		17, Color(0.35, 0.35, 0.35))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var again := Button.new()
	again.text = "Play again"
	again.add_theme_font_size_override("font_size", 26)
	again.custom_minimum_size = Vector2(220, 56)
	again.pressed.connect(Run.restart)
	buttons.add_child(again)
	buttons.add_child(_credits_button())


func _credits_button() -> Button:
	var b := Button.new()
	b.text = "Credits"
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size = Vector2(220, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_show_credits)
	return b


func _show_credits() -> void:
	var overlay: Control
	overlay = Credits.make_overlay(func() -> void: overlay.queue_free())
	add_child(overlay)


func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


func _line(parent: Control, text: String, size: int, colour: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(680, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
