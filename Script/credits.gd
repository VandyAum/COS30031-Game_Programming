class_name Credits
## Credits and licences: who made the game, and the attribution every
## third-party asset needs (map data, font, icons). Shown from the end
## screen and the pause screen; README.md carries the same information.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Add a credits screen off the end screen (and the pause screen) with all
#    relevant licence and attribution info: the team and what each person
#    built, a note that code was AI-assisted with prompts kept as comments,
#    the Vicmap / PARKRES map data under CC BY 4.0 with the on-screen credit
#    line, the changes we made and every dataset used (read from
#    world_meta.json so it always matches the build), Atkinson Hyperlegible
#    Next (SIL OFL 1.1), Mapbox Maki icons (CC0), the Phosphor hard-hat
#    icon (MIT, (c) 2023 Phosphor Icons), the Google Material Symbols crew
#    icons (Apache 2.0) and the police car sprite. Write it as BBCode
#    for a RichTextLabel, plus a helper that builds a scrollable credits
#    card with a Back button."
# Follow-up prompt: "The car isn't team-drawn: it's 'Police car free sprite'
#    by SomeGame_Dev (grilledgamingyt) on itch.io, which asks for credit."

const WIDTH := 820.0


static func bbcode() -> String:
	var t := ""
	t += "[font_size=40][b]Credits[/b][/font_size]\n\n"
	t += "[b]The Race Against Time[/b], a COS30031 Game Programming team project.\n\n"

	t += "[font_size=26][b]Team[/b][/font_size]\n"
	t += "Vandy: route drawing, stations and crews\n"
	t += "Ishita: map panning and zoom, incident data, incident panel\n"
	t += "Jessie: HUD design\n"
	t += "Leah: Vicmap world, game systems\n"
	t += "Code was written with AI assistance (Claude, by Anthropic); the prompts are kept as comments in the source.\n\n"

	t += "[font_size=26][b]Map data[/b][/font_size]\n"
	t += Stage.credit() + "\n"
	t += "Licensed under Creative Commons Attribution 4.0 International ([url]%s[/url]). No endorsement by the State of Victoria is implied.\n" % Stage.meta.get("licence_url", "https://creativecommons.org/licenses/by/4.0/")
	t += "[b]Changes:[/b] %s\n" % Stage.meta.get("changes", "")
	for src: Dictionary in Stage.meta.get("data_sources", []):
		t += "•  %s, %s (retrieved %s): %s\n" % [src["title"], src["custodian"], src["retrieved"], src["used_for"]]
	t += "\n"

	t += "[font_size=26][b]Font[/b][/font_size]\n"
	t += "Atkinson Hyperlegible Next, (c) 2020-2024 The Atkinson Hyperlegible Next Project Authors. SIL Open Font License 1.1 (UI/Fonts/OFL.txt).\n\n"

	t += "[font_size=26][b]Icons[/b][/font_size]\n"
	t += "Map landmark icons and hearts: Maki by Mapbox, CC0 1.0 (recoloured).\n"
	t += "SES hard hat: Phosphor Icons, (c) 2023 Phosphor Icons, MIT License (recoloured).\n"
	t += "Crew icons: Material Symbols by Google, Apache License 2.0.\n"
	t += "Crew car: \"Police car free sprite\" by SomeGame_Dev (grilledgamingyt), [url]https://grilledgamingyt.itch.io/police-car-free-sprite[/url] (free, credit required)\n\n"
	t += "Full licence texts are in the game folder: UI/Fonts/OFL.txt, UI/Icons/map/MAKI_LICENSE.txt, UI/Icons/PHOSPHOR_LICENSE.txt, Map/world/ATTRIBUTION.md."
	return t


## A full-screen credits overlay with a scrollable card and a Back button.
static func make_overlay(on_back: Callable) -> Control:
	var cover := ColorRect.new()
	cover.color = Color(0.08, 0.09, 0.12, 0.92)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.97, 0.98)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(32)
	card.add_theme_stylebox_override("panel", style)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(WIDTH, 760)
	cover.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(WIDTH - 90, 0)
	text.add_theme_font_size_override("normal_font_size", 18)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.add_theme_color_override("default_color", Color(0.18, 0.2, 0.24))
	text.text = bbcode()
	text.meta_clicked.connect(func(m: Variant) -> void: OS.shell_open(str(m)))
	scroll.add_child(text)

	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 24)
	back.custom_minimum_size = Vector2(200, 52)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(on_back)
	box.add_child(back)
	return cover
