extends Control
## HUD controller for Jessie's UI/HUD.tscn design. Fills the incidents panel
## with one card per live incident (using the design's card as a template),
## filters by the tab bar, lets the player select an incident and pick a
## crew to send, and lists every crew with its current status.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a Godot 4.7 script for the root of our HUD scene (UI/HUD.tscn,
#    designed by Jessie: a top navigation bar and a left IncidentPanel with a
#    TabBar 'All / Fire / Medical / Police' and one example incident card:
#    a Panel with an icon TextureRect, a title Label, a description Label and
#    a ProgressBar). Don't redesign it - use the example card as a template:
#    remove it from the tree and duplicate it for every live incident in a
#    scrolling list under the tabs. Each card shows the crew type icon tinted
#    in that crew type's colour, the incident title, the caller's description
#    (word-wrapped), a status line, and the progress bar showing on-scene
#    progress. Tabs filter by needed crew type. Clicking a card selects the
#    incident (IncidentManager.select) and pans the camera to it; selecting on
#    the map highlights the card. The selected card also shows 'Send ...'
#    buttons for every available crew in play, needed type first, which emit
#    Events.crew_selected so the route drawer starts a route from that crew's
#    station. Below the list add a 'Crews' section listing each crew in play
#    with its station and status (available, en route, on scene, returning,
#    cooldown with seconds). Refresh from Events rather than every frame
#    (plus a light timer for countdowns), and make the root ignore the mouse
#    so the map underneath still gets clicks."
# Follow-up prompt: "Crew rows were wider than the 450 px panel and pushed
#    the layout off screen. Clip long crew/station names and keep every row
#    and button grid inside the panel width."
# Follow-up prompt: "Long status lines and the second 'Send' button still ran
#    off the card. Wrap the status text, flow the Send buttons onto as many
#    rows as needed, and size each card's height to fit its contents."
# Follow-up prompt: "That made cards grow forever (wrapped labels report a
#    huge height before they have a width). Give the text column a fixed
#    width so wrapping is known up front, and re-fit the card height on
#    every panel refresh (the first fit can run before layout settles)."
# Follow-up prompt: "Timing-based fitting still flickers. Put each card's
#    contents in a PanelContainer with the design's card style so the card
#    sizes itself to its contents automatically; remove the manual fitting."
# Follow-up prompt (milestone 2 - obstacle alerts):
#   "When a crew stops at an unexpected obstacle, show an attention-grabbing
#    red alert banner under the navigation bar for as long as it is stuck:
#    'Police 1 stopped: roadworks on Burkett Road. Drag from the crew to
#    redraw its route.' Clicking it pans the camera to the crew. Also show the
#    incident card's status in red while its crew is blocked."
# Follow-up prompt: "Long crew statuses ('BLOCKED: roadworks on ...') widened
#    the whole panel. Clip crew-row text with an ellipsis so rows never grow
#    past the panel; the full text shows as a tooltip and on the card."

const TAB_FILTER: Array[StringName] = [&"", &"fire", &"ambulance", &"police"]
const SELECTED_BORDER := Color("1f6fd8")
## Width of a card's text column (panel content width minus icon and margins).
const TEXT_WIDTH := 225.0

@onready var _tabs: TabBar = $IncidentPanel/MarginContainer/VBoxContainer/MarginContainer/TabBar
@onready var _column: VBoxContainer = $IncidentPanel/MarginContainer/VBoxContainer
@onready var _template: Panel = $IncidentPanel/MarginContainer/VBoxContainer/Panel

var _list: VBoxContainer
var _crew_list: VBoxContainer
var _alerts: VBoxContainer
var _alert_key := ""
var _cards := {}          # Incident -> card (PanelContainer)
var _refresh_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$IncidentPanel/MarginContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.remove_child(_template)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	var heading := Label.new()
	heading.text = "Crews"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	_column.add_child(heading)
	_crew_list = VBoxContainer.new()
	_crew_list.add_theme_constant_override("separation", 4)
	_column.add_child(_crew_list)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 16)
	_column.add_child(pad)

	_alerts = VBoxContainer.new()
	_alerts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alerts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alerts.position = Vector2(0, 116)
	_alerts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_alerts)

	_tabs.tab_changed.connect(func(_t: int) -> void: _rebuild())
	for sig in [Events.incident_spawned, Events.incident_updated, Events.incident_resolved,
			Events.incident_selected, Events.crew_state_changed, Events.stage_changed]:
		sig.connect(func(_a = null) -> void: _rebuild.call_deferred())
	_rebuild.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_template):
		_template.free()   # held outside the tree as a template


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.25
		_update_progress()
		_rebuild_crews()
		_rebuild_alerts()


func _manager() -> Node:
	return get_tree().get_first_node_in_group("incident_manager")


func _stations() -> Node:
	return get_tree().get_first_node_in_group("station_manager")


# --- Incident cards ----------------------------------------------------------

func _rebuild() -> void:
	var manager := _manager()
	if manager == null:
		return
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	var filter := TAB_FILTER[_tabs.current_tab]
	var shown := 0
	for inc: Incident in manager.incidents():
		if filter != &"" and not inc.type.needs(filter):
			continue
		var card := _make_card(inc, inc == manager.selected)
		_list.add_child(card)
		_cards[inc] = card
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "No open incidents. Calls will come in shortly."
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		empty.add_theme_font_size_override("font_size", 18)
		_list.add_child(empty)
	_rebuild_crews()


func _make_card(inc: Incident, is_selected: bool) -> PanelContainer:
	# Same look as the design's card, but a container so it fits its content.
	var source: Panel = _template.duplicate()
	var card := PanelContainer.new()
	var hbox: HBoxContainer = source.get_node("HBoxContainer")
	source.remove_child(hbox)
	source.free()
	card.add_child(hbox)
	var style: StyleBoxFlat = (_template.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	var box: VBoxContainer = card.get_node("HBoxContainer/MarginContainer/VBoxContainer")
	box.custom_minimum_size.x = TEXT_WIDTH
	var icon: TextureRect = card.get_node("HBoxContainer/TextureRect")
	icon.texture = inc.crew_type.icon
	icon.self_modulate = inc.crew_type.colour
	var title: Label = box.get_node("Label")
	title.text = inc.title()
	title.add_theme_font_size_override("font_size", 28)
	var desc: Label = box.get_node("Label2")
	desc.text = inc.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = TEXT_WIDTH
	var status := Label.new()
	status.name = "Status"
	status.text = inc.status_text()
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color("b3261e") if inc.note != "" else Color(0.25, 0.25, 0.25))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = TEXT_WIDTH
	box.add_child(status)
	box.move_child(status, 2)
	var bar: ProgressBar = box.get_node("MarginContainer/ProgressBar")
	bar.value = inc.progress * 100.0
	(box.get_node("MarginContainer") as MarginContainer).add_theme_constant_override("margin_top", 8)

	if is_selected:
		style.border_color = SELECTED_BORDER
		style.set_border_width_all(4)
		if inc.is_open():
			box.add_child(_crew_buttons(inc))
	card.custom_minimum_size = Vector2(0, 150)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(inc))
	return card


func _crew_buttons(inc: Incident) -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var crews: Array = _stations().crews_in_play().filter(func(c: Crew) -> bool: return c.is_available())
	crews.sort_custom(func(a: Crew, b: Crew) -> bool: return inc.type.needs(a.type.id) and not inc.type.needs(b.type.id))
	if crews.is_empty():
		var none := Label.new()
		none.text = "No crews available"
		none.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		grid.add_child(none)
	for c: Crew in crews:
		var b := Button.new()
		b.text = "Send " + c.callsign
		b.icon = c.type.icon
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22)
		b.custom_minimum_size = Vector2(0, 38)
		if not inc.type.needs(c.type.id):
			b.modulate = Color(1, 1, 1, 0.55)
			b.tooltip_text = "Wrong crew type for this incident"
		b.pressed.connect(func() -> void: Events.crew_selected.emit(c))
		grid.add_child(b)
	return grid


func _on_card_input(event: InputEvent, inc: Incident) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_manager().select(inc)
		var cam := get_viewport().get_camera_2d()
		if cam and cam.has_method("focus_on"):
			cam.focus_on(inc.global_position)


func _update_progress() -> void:
	for inc: Incident in _cards:
		if not is_instance_valid(inc):
			continue
		var card: PanelContainer = _cards[inc]
		var box := card.get_node("HBoxContainer/MarginContainer/VBoxContainer")
		(box.get_node("MarginContainer/ProgressBar") as ProgressBar).value = inc.progress * 100.0
		var status: Label = box.get_node("Status")
		status.text = inc.status_text()
		status.add_theme_color_override("font_color",
			Color("b3261e") if inc.note != "" or inc.is_crew_blocked() else Color(0.25, 0.25, 0.25))


# --- Obstacle alerts ---------------------------------------------------------

func _rebuild_alerts() -> void:
	var stations := _stations()
	if stations == null:
		return
	var blocked: Array = stations.all_crews().filter(func(c: Crew) -> bool: return c.state == Crew.State.BLOCKED)
	var key := ",".join(blocked.map(func(c: Crew) -> String: return c.callsign + str(c.blocked_edge)))
	if key == _alert_key:
		return
	_alert_key = key
	for a in _alerts.get_children():
		a.queue_free()
	for c: Crew in blocked:
		var b := Button.new()
		var road: String = RoadGraph.edge_name[c.blocked_edge]
		b.text = "  %s stopped: %s%s. Drag from the crew to redraw its route.  " % [
			c.callsign, World.block_reason(c.blocked_edge).to_lower(), (" on " + road) if road != "" else ""]
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("c1121f")
		style.set_corner_radius_all(10)
		style.set_content_margin_all(10)
		style.shadow_size = 8
		style.shadow_color = Color(0, 0, 0, 0.3)
		b.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color("e01e2b")
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(func() -> void:
			var cam := get_viewport().get_camera_2d()
			if cam and cam.has_method("focus_on") and is_instance_valid(c):
				cam.focus_on(c.global_position))
		_alerts.add_child(b)


# --- Crew list -------------------------------------------------------------------

func _rebuild_crews() -> void:
	var stations := _stations()
	if stations == null:
		return
	var crews: Array[Crew] = stations.crews_in_play()
	# Reuse rows when the crew list hasn't changed, just update the text.
	if _crew_list.get_child_count() == crews.size():
		for i in crews.size():
			var row: HBoxContainer = _crew_list.get_child(i)
			var st: Label = row.get_node("Status")
			st.text = crews[i].status_text()
			st.tooltip_text = st.text
			st.add_theme_color_override("font_color", Color("b3261e") if crews[i].state == Crew.State.BLOCKED else Color(0.3, 0.3, 0.3))
		return
	for c in _crew_list.get_children():
		c.queue_free()
	for crew in crews:
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = crew.type.icon
		icon.self_modulate = crew.type.colour
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(26, 26)
		row.add_child(icon)
		var label := Button.new()
		label.text = "%s  ·  %s" % [crew.callsign, crew.station.station_name]
		label.flat = true
		label.clip_text = true
		label.custom_minimum_size = Vector2(60, 0)
		label.alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
		label.tooltip_text = "Click, then drag from the station to an incident"
		label.pressed.connect(func() -> void: Events.crew_selected.emit(crew))
		row.add_child(label)
		var status := Label.new()
		status.name = "Status"
		status.text = crew.status_text()
		status.clip_text = true
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.custom_minimum_size = Vector2(60, 0)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		status.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
		row.add_child(status)
		_crew_list.add_child(row)
