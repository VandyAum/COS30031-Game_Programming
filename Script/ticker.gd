extends Control
## Ticker: the black news strip along the bottom of the screen (Leah's
## concept art). Events scroll in from the right as they happen, stamped with
## the in-game time, with crew names in their colours. A ticking clock sits
## in the right-hand corner: one in-game minute per real second.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Build the bottom news ticker from Leah's concept art in Godot 4.7: a
#    full-width black strip along the bottom edge, with messages scrolling
#    right-to-left like a news crawl, e.g. '21:53: Hawthorn Fire returned. •
#    21:54: New incident! • 21:56: SES North is stuck!'. Each message starts
#    with the in-game time, crew names are coloured in their crew type's
#    colour, 'New incident!' in magenta and 'is stuck!' in yellow. New
#    messages queue up after the last one so nothing overlaps, and the crawl
#    speeds up if a backlog builds. On the right, on the same black strip, a
#    large clock showing Run.clock_text() (one in-game minute per second).
#    Listen to Events for new calls, dispatches, arrivals, resolutions,
#    blocked crews, returns, crews ready and Events.ticker_message. Keep the
#    crawl clipped so it never runs under the clock."
# Follow-up prompt (readable ticker): "The crawl often moves too fast to
#    read. Make the text a bit smaller and stop the constant scrolling:
#    messages sit still, and only move when a new one comes in - the new
#    message slides in at the right-hand end (next to the clock) and pushes
#    the older ones to the left, which drop off the left edge. Queue
#    messages that arrive together so each slide finishes and stays put for
#    a moment before the next. Keep each message's time from when it
#    happened. Make the colon in the clock flash once per in-game minute,
#    like a digital clock, without the digits shifting."
# Follow-up prompt: "Make the clock monospaced: use the project font with
#    its tabular-figures OpenType feature (tnum) so every digit is the same
#    width and the clock never jiggles."

const HEIGHT := 64.0
const GAP := 26.0
const FONT_SIZE := 22
const SLIDE_SECONDS := 0.45
## Pause after a message slides in before the next queued one follows.
const HOLD_SECONDS := 0.6
const NEW_COLOUR := "#ff4dff"
const STUCK_COLOUR := "#ffd23f"

var _lane: Control
var _clock: RichTextLabel
var _items: Array[RichTextLabel] = []
var _queue: Array[String] = []
var _busy := 0.0          # seconds until the next queued message may slide in


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -HEIGHT
	offset_bottom = 0.0

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_clock = RichTextLabel.new()
	_clock.bbcode_enabled = true
	_clock.scroll_active = false
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock.add_theme_font_size_override("normal_font_size", 40)
	var mono := FontVariation.new()
	mono.base_font = ThemeDB.fallback_font
	mono.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tabular_figures"): 1}
	_clock.add_theme_font_override("normal_font", mono)
	_clock.add_theme_color_override("default_color", Color.WHITE)
	_clock.anchor_left = 1.0
	_clock.anchor_right = 1.0
	_clock.anchor_bottom = 1.0
	_clock.offset_left = -150
	_clock.offset_right = -18
	_clock.offset_top = 6
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_clock)

	_lane = Control.new()
	_lane.clip_contents = true
	_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lane.anchor_right = 1.0
	_lane.anchor_bottom = 1.0
	_lane.offset_right = -175
	add_child(_lane)

	Events.incident_spawned.connect(func(i: Node) -> void:
		post("[color=%s]New incident![/color] %s on %s." % [NEW_COLOUR, i.title(), i.place]))
	Events.crew_dispatched.connect(func(c: Node, i: Node) -> void:
		post("%s dispatched to the %s." % [_crew(c), i.title().to_lower()]))
	Events.crew_arrived.connect(func(c: Node, i: Node) -> void:
		if i != null and is_instance_valid(i) and not i.is_finished():
			post("%s on scene." % _crew(c)))
	Events.incident_resolved.connect(func(i: Node) -> void:
		post("[color=#2fbf71]Resolved:[/color] %s on %s." % [i.title().to_lower(), i.place]))
	Events.crew_blocked.connect(func(c: Node, _e: int) -> void:
		post("%s [color=%s]is stuck![/color]" % [_crew(c), STUCK_COLOUR]))
	Events.crew_returned.connect(func(c: Node) -> void: post("%s returned." % _crew(c)))
	Events.crew_ready.connect(func(c: Node) -> void: post("%s is ready." % _crew(c)))
	Events.ticker_message.connect(post)


func _crew(c: Node) -> String:
	return "[color=#%s]%s[/color]" % [c.type.colour.lightened(0.15).to_html(false), c.callsign]


## Add a message (BBCode allowed). It is stamped with the time now and
## slides in when the ones before it have had their moment.
func post(text: String) -> void:
	_queue.append("[color=#9aa3b2]%s[/color]  %s" % [Run.clock_text(), text])


func _process(delta: float) -> void:
	# Flashing colon: visible for the first half of every in-game minute.
	var m := int(Run.minutes())
	var on := fmod(Knowledge.clock * Run.minutes_per_second, 1.0) < 0.5
	_clock.text = "%02d[color=%s]:[/color]%02d" % [(m / 60) % 24, "#ffffff" if on else "#ffffff00", m % 60]

	_busy -= delta
	if _busy <= 0.0 and not _queue.is_empty():
		_slide_in(_queue.pop_front())


func _slide_in(text: String) -> void:
	var item := RichTextLabel.new()
	item.bbcode_enabled = true
	item.fit_content = true
	item.autowrap_mode = TextServer.AUTOWRAP_OFF
	item.scroll_active = false
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	item.add_theme_color_override("default_color", Color.WHITE)
	item.text = text
	_lane.add_child(item)
	var w := item.get_content_width() + 4.0
	item.size = Vector2(w, HEIGHT)
	item.position = Vector2(_lane.size.x, (HEIGHT - item.get_content_height()) / 2.0)

	# Everything (including the newcomer) moves left by its width: the new
	# message ends up flush against the clock, the rest are pushed along.
	var shift := w + GAP
	# Free messages already off the left edge (before tweening them).
	while not _items.is_empty() and _items[0].position.x + _items[0].size.x < 0.0:
		_items.pop_front().queue_free()
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for old in _items:
		tween.tween_property(old, "position:x", old.position.x - shift, SLIDE_SECONDS)
	tween.tween_property(item, "position:x", _lane.size.x - w, SLIDE_SECONDS)
	_items.append(item)
	_busy = SLIDE_SECONDS + (HOLD_SECONDS if _queue.size() < 4 else 0.15)
