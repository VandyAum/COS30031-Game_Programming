extends Node2D
## Landmarks: every Feature of Interest from the Vicmap FOI data drawn as a
## monochrome pictogram (colour is reserved for what crews have seen), with
## its name once zoomed in. Emergency stations are drawn by Stations instead.
## This is also the start of the "Register" of known places (milestone 4).

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Colour on our map now means 'recently seen by a crew', so location types
#    need a non-colour visual language. Write a Godot 4.7 Node2D that reads
#    Map/world/foi.json and draws every Feature of Interest inside the world
#    as a small white disc with a dark outline and a simple pictogram drawn
#    with primitives (no image assets): a cross for hospitals and care
#    facilities, a mortarboard for schools and childcare, a shopping bag for
#    shops, a tree for parks, sports and recreation, a church cross for
#    places of worship, a columned building for libraries, halls, galleries
#    and council offices, a house for residential buildings such as
#    retirement villages, a factory for depots and utilities, and a star for
#    other landmarks. Keep markers a constant size on screen, show the place
#    name underneath once zoomed in, and skip emergency stations (Stations
#    draws those). Redraw only when the zoom changes."
# Follow-up prompt (legible from a distance): "PoI icons and names are too
#    small when zoomed out to a big stage. Keep the pictograms the same size
#    on screen at every zoom (scale up to 4.5x), make them a little bigger
#    with a thicker outline and a soft shadow, and always show names at a
#    fixed on-screen size: when zoomed out, label the most useful landmarks
#    first (railway stations, hospitals, shopping centres, schools) and skip
#    any label that would overlap one already drawn, so it never turns into
#    clutter."
# Follow-up prompt: "Label scaling was janky (font sizes jumping in whole
#    pixels as the zoom changes). Draw icons and labels at a fixed size
#    through a scaling transform instead, so they scale smoothly. And swap
#    the black ink on each icon for a distinctive colour per kind of place,
#    avoiding the crew/station colours (police blue, ambulance red, fire
#    orange, SES gold) and the traffic greens/reds."
# Follow-up prompt (licensed icons): "Swap the hand-drawn pictograms for
#    Mapbox's Maki icons (CC0, UI/Icons/map/, recoloured white so they can
#    be tinted), keeping the coloured rings and per-kind colours. Credit
#    them in the README and the credits screen."

const FOI_PATH := "res://Map/world/foi.json"
const INK := Color("33373d")
const MAX_SCALE := 4.5            # markers stay this many times bigger at most
const ICON_R := 14.0              # marker radius in screen px
const LABEL_SIZE := 15            # label font size in screen px

enum Glyph { MEDICAL, SCHOOL, SHOP, TREE, WORSHIP, CIVIC, HOUSE, INDUSTRY, STAR, TRAIN }
## Drawn by Stations instead.
## Ink colour per pictogram (not crew colours, not traffic colours).
const GLYPH_COLOURS := {
	Glyph.MEDICAL: Color("8e44ad"),   # purple
	Glyph.SCHOOL: Color("c2185b"),    # magenta
	Glyph.SHOP: Color("6d4c41"),      # brown
	Glyph.TREE: Color("2e6b30"),      # forest green
	Glyph.WORSHIP: Color("827717"),   # olive
	Glyph.CIVIC: Color("546e7a"),     # blue-grey
	Glyph.HOUSE: Color("a1765f"),     # tan
	Glyph.INDUSTRY: Color("616161"),  # grey
	Glyph.STAR: Color("37474f"),      # charcoal
	Glyph.TRAIN: Color("00838f"),     # cyan
}
## Maki icon per pictogram (CC0, Mapbox; white so the ink colour tints it).
const GLYPH_ICONS := {
	Glyph.MEDICAL: preload("res://UI/Icons/map/hospital.svg"),
	Glyph.SCHOOL: preload("res://UI/Icons/map/school.svg"),
	Glyph.SHOP: preload("res://UI/Icons/map/shop.svg"),
	Glyph.TREE: preload("res://UI/Icons/map/park.svg"),
	Glyph.WORSHIP: preload("res://UI/Icons/map/place-of-worship.svg"),
	Glyph.CIVIC: preload("res://UI/Icons/map/town-hall.svg"),
	Glyph.HOUSE: preload("res://UI/Icons/map/home.svg"),
	Glyph.INDUSTRY: preload("res://UI/Icons/map/industry.svg"),
	Glyph.STAR: preload("res://UI/Icons/map/star.svg"),
	Glyph.TRAIN: preload("res://UI/Icons/map/rail.svg"),
}
const STATION_SUBTYPES := ["police station", "ambulance station", "fire station"]

## feature_type -> glyph (subtypes checked first, below).
const TYPE_GLYPHS := {
	"hospital": Glyph.MEDICAL, "care facility": Glyph.MEDICAL,
	"education centre": Glyph.SCHOOL,
	"commercial facility": Glyph.SHOP,
	"sport facility": Glyph.TREE, "recreational resource": Glyph.TREE, "reserve": Glyph.TREE,
	"place of worship": Glyph.WORSHIP,
	"cultural centre": Glyph.CIVIC, "community venue": Glyph.CIVIC, "admin facility": Glyph.CIVIC,
	"residential building": Glyph.HOUSE,
	"storage facility": Glyph.INDUSTRY, "dumping ground": Glyph.INDUSTRY, "communication service": Glyph.INDUSTRY,
	"transport terminal": Glyph.TRAIN,
}
const SUBTYPE_GLYPHS := {"child care": Glyph.SCHOOL, "aged care": Glyph.MEDICAL}

var _places: Array = []   # [{pos, glyph, name}]
var _zoom := -1.0


func _ready() -> void:
	add_to_group("landmarks")
	var fois: Array = JSON.parse_string(FileAccess.get_file_as_string(FOI_PATH))
	var world := Rect2(Vector2.ZERO, Stage.world_size)
	for f: Dictionary in fois:
		var p := Vector2(f["x"], f["y"])
		if STATION_SUBTYPES.has(f["subtype"]) or not world.has_point(p):
			continue
		var glyph: int = SUBTYPE_GLYPHS.get(f["subtype"], TYPE_GLYPHS.get(f["type"], Glyph.STAR))
		_places.append({"pos": p, "glyph": glyph, "name": f["name"], "rank": _rank(glyph, f["subtype"])})
	# Most useful landmarks get their labels first.
	_places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rank"] < b["rank"])


func _rank(glyph: int, subtype: String) -> int:
	if glyph == Glyph.TRAIN:
		return 0
	if subtype in ["general hospital", "shopping centre"]:
		return 1
	if glyph == Glyph.SCHOOL or glyph == Glyph.SHOP:
		return 2
	return 3


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and not is_equal_approx(cam.zoom.x, _zoom):
		_zoom = cam.zoom.x
		queue_redraw()


func _draw() -> void:
	if _zoom <= 0.0:
		return
	var s := clampf(1.0 / _zoom, 0.6, MAX_SCALE)    # constant screen size
	var font := ThemeDB.fallback_font
	# Everything is drawn at its screen size around each place, scaled by s
	# through the transform so it grows and shrinks smoothly.
	for place: Dictionary in _places:
		var ink: Color = GLYPH_COLOURS.get(place["glyph"], INK)
		draw_set_transform(place["pos"], 0.0, Vector2(s, s))
		draw_circle(Vector2(0, 2), ICON_R, Color(0, 0, 0, 0.18))   # shadow
		draw_circle(Vector2.ZERO, ICON_R, Color.WHITE)
		draw_circle(Vector2.ZERO, ICON_R, ink, false, 2.5)
		_draw_glyph(place["glyph"], Vector2.ZERO, 9.0, ink)
	# Labels on top of every marker, skipping any that would overlap.
	var taken: Array[Rect2] = []
	for place: Dictionary in _places:
		var c: Vector2 = place["pos"]
		var text: String = place["name"]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var at := Vector2(-w / 2.0, ICON_R + 16.0)
		var box := Rect2(c + (at - Vector2(4, LABEL_SIZE)) * s, Vector2(w + 8, LABEL_SIZE * 1.3) * s)
		if taken.any(func(r: Rect2) -> bool: return r.intersects(box)):
			continue
		taken.append(box)
		var ink: Color = GLYPH_COLOURS.get(place["glyph"], INK)
		draw_set_transform(c, 0.0, Vector2(s, s))
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 5, Color(1, 1, 1, 0.92))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, ink.darkened(0.35))
	draw_set_transform(Vector2.ZERO)


# Pictogram (a Maki icon tinted with the ink colour) in a box of half-size h around c.
func _draw_glyph(glyph: int, c: Vector2, h: float, ink := INK) -> void:
	var tex: Texture2D = GLYPH_ICONS.get(glyph, GLYPH_ICONS[Glyph.STAR])
	draw_texture_rect(tex, Rect2(c - Vector2(h, h), Vector2(h, h) * 2.0), false, ink)
