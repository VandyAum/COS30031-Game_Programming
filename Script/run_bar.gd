extends Control
## RunBar: lives and run progress for the top bar, after Leah's concept
## sketch: a line with a bauble at each end (tutorial / you win), tick marks
## splitting it into the three stages, the travelled part in yellow, a
## marker at the current position, and three hearts above the marker
## (red = life left, black broken heart = lost).

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 Control that draws the run progress bar from Leah's
#    sketch, to sit in Jessie's top navigation bar: a horizontal line with a
#    circle 'bauble' at each end (left = tutorial, right = you win), two tick
#    marks dividing it into three equal stages, the completed part painted
#    thick yellow up to Run.progress(), a small circle marker at the current
#    position, and above the marker three hearts drawn with primitives: red
#    for lives left and a black broken heart (split down a zigzag) for each
#    life lost. Fill the baubles once reached. Light colours so it reads on
#    the dark navigation bar. Redraw on Events.lives_changed,
#    progress_changed and stage_changed, and animate the marker smoothly."
# Follow-up prompt (licensed icons): "Draw the hearts with Mapbox's Maki
#    heart icon (CC0) instead of the hand-made heart curve: a slightly
#    larger white copy behind for the outline, red for lives left, black
#    with the zigzag crack for lives lost."

const LINE := Color(0.92, 0.94, 0.97)
const FILL := Color("f5c400")
const HEART := Color("e63946")
const LOST := Color("111111")

var _shown := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(620, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for sig in [Events.lives_changed, Events.progress_changed, Events.stage_changed, Events.run_ended]:
		sig.connect(func(_a = null) -> void: queue_redraw())


func _process(delta: float) -> void:
	var target := Run.progress()
	if not is_equal_approx(_shown, target):
		_shown = move_toward(_shown, target, delta * 0.5)
		queue_redraw()


func _draw() -> void:
	var y := size.y * 0.72
	var left := 26.0
	var right := size.x - 26.0
	var r := 16.0
	var x_at := func(t: float) -> float: return lerpf(left + r, right - r, t)

	# Track, ticks, travelled part.
	draw_line(Vector2(left + r, y), Vector2(right - r, y), LINE, 3.0)
	for i in [1, 2]:
		var x: float = x_at.call(i / 3.0)
		draw_line(Vector2(x, y - 9), Vector2(x, y + 9), LINE, 3.0)
	var mx: float = x_at.call(_shown)
	draw_line(Vector2(left + r, y), Vector2(mx, y), FILL, 7.0)

	# Baubles: tutorial (left) and win (right).
	var tutorial_done := Stage.current > 0 or Run.result == "won"
	draw_circle(Vector2(left, y), r, FILL if tutorial_done else Color(0, 0, 0, 0))
	draw_arc(Vector2(left, y), r, 0, TAU, 32, LINE, 3.0)
	draw_circle(Vector2(right, y), r, FILL if Run.result == "won" else Color(0, 0, 0, 0))
	draw_arc(Vector2(right, y), r, 0, TAU, 32, LINE, 3.0)

	# Current position marker.
	if Stage.current > 0 and Run.result != "won":
		draw_circle(Vector2(mx, y), 8.0, Color("3b4c6e"))
		draw_arc(Vector2(mx, y), 8.0, 0, TAU, 24, LINE, 3.0)

	# Hearts above the marker (or above the bauble during the tutorial).
	var hx := mx if Stage.current > 0 else left + 40.0
	for i in Run.start_lives:
		var c := Vector2(hx + (i - (Run.start_lives - 1) / 2.0) * 34.0, y - 40.0)
		_heart(c, 13.0, i < Run.lives)


const HEART_ICON := preload("res://UI/Icons/map/heart.svg")


func _heart(c: Vector2, s: float, alive: bool) -> void:
	var colour := HEART if alive else LOST
	var outline := Rect2(c - Vector2(s, s) * 1.2, Vector2(s, s) * 2.4)
	draw_texture_rect(HEART_ICON, outline, false, Color(1, 1, 1, 0.9))
	draw_texture_rect(HEART_ICON, Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), false, colour)
	if not alive:
		# Broken: a zigzag crack down the middle.
		var crack := PackedVector2Array([c + Vector2(1, -s * 0.55), c + Vector2(-3, -s * 0.15),
			c + Vector2(3, s * 0.2), c + Vector2(-1, s * 0.75)])
		draw_polyline(crack, Color(0.85, 0.85, 0.85), 2.5)
