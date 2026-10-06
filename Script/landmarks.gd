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

const FOI_PATH := "res://Map/world/foi.json"
const INK := Color("33373d")
const LABEL_ZOOM := 0.75          # names appear at this zoom and closer

enum Glyph { MEDICAL, SCHOOL, SHOP, TREE, WORSHIP, CIVIC, HOUSE, INDUSTRY, STAR, TRAIN }
## Drawn by Stations instead.
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
		_places.append({"pos": p, "glyph": glyph, "name": f["name"]})


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and not is_equal_approx(cam.zoom.x, _zoom):
		_zoom = cam.zoom.x
		queue_redraw()


func _draw() -> void:
	if _zoom <= 0.0:
		return
	var s := clampf(1.0 / _zoom, 0.6, 1.8)    # constant-ish screen size
	var font := ThemeDB.fallback_font
	for place: Dictionary in _places:
		var c: Vector2 = place["pos"]
		draw_circle(c, 12.0 * s, Color.WHITE)
		draw_circle(c, 12.0 * s, INK, false, 2.0 * s)
		_draw_glyph(place["glyph"], c, 7.0 * s)
		if _zoom >= LABEL_ZOOM:
			var size := int(13 * s)
			var text: String = place["name"]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var at := c + Vector2(-w / 2.0, 26.0 * s)
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(4 * s), Color(1, 1, 1, 0.85))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)


# Pictograms drawn inside a box of half-size h around c.
func _draw_glyph(glyph: int, c: Vector2, h: float) -> void:
	match glyph:
		Glyph.MEDICAL:
			draw_rect(Rect2(c - Vector2(h * 0.3, h), Vector2(h * 0.6, h * 2)), INK)
			draw_rect(Rect2(c - Vector2(h, h * 0.3), Vector2(h * 2, h * 0.6)), INK)
		Glyph.SCHOOL:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.2), c + Vector2(0, -h * 0.8),
				c + Vector2(h, -h * 0.2), c + Vector2(0, h * 0.4)]), INK)
			draw_rect(Rect2(c + Vector2(-h * 0.55, 0), Vector2(h * 1.1, h * 0.7)), INK)
			draw_line(c + Vector2(h * 0.8, -h * 0.25), c + Vector2(h * 0.8, h * 0.6), INK, h * 0.18)
		Glyph.SHOP:
			draw_rect(Rect2(c + Vector2(-h * 0.8, -h * 0.3), Vector2(h * 1.6, h * 1.3)), INK)
			draw_arc(c + Vector2(0, -h * 0.3), h * 0.45, PI, TAU, 12, INK, h * 0.2)
		Glyph.TREE:
			draw_circle(c + Vector2(0, -h * 0.25), h * 0.75, INK)
			draw_rect(Rect2(c + Vector2(-h * 0.15, h * 0.3), Vector2(h * 0.3, h * 0.7)), INK)
		Glyph.WORSHIP:
			draw_rect(Rect2(c + Vector2(-h * 0.15, -h), Vector2(h * 0.3, h * 2)), INK)
			draw_rect(Rect2(c + Vector2(-h * 0.6, -h * 0.5), Vector2(h * 1.2, h * 0.3)), INK)
		Glyph.CIVIC:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.35), c + Vector2(0, -h),
				c + Vector2(h, -h * 0.35)]), INK)
			for i in 3:
				var x := -h * 0.65 + i * h * 0.55
				draw_rect(Rect2(c + Vector2(x, -h * 0.25), Vector2(h * 0.22, h * 0.95)), INK)
			draw_rect(Rect2(c + Vector2(-h, h * 0.7), Vector2(h * 2, h * 0.3)), INK)
		Glyph.HOUSE:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h, -h * 0.05), c + Vector2(0, -h),
				c + Vector2(h, -h * 0.05)]), INK)
			draw_rect(Rect2(c + Vector2(-h * 0.65, -h * 0.05), Vector2(h * 1.3, h * 1.0)), INK)
		Glyph.INDUSTRY:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-h, h), c + Vector2(-h, -h * 0.2),
				c + Vector2(-h * 0.35, -h * 0.65), c + Vector2(-h * 0.35, -h * 0.2), c + Vector2(h * 0.3, -h * 0.65),
				c + Vector2(h * 0.3, -h * 0.2), c + Vector2(h, -h * 0.65), c + Vector2(h, h)]), INK)
		Glyph.TRAIN:
			var body := StyleBoxFlat.new()
			body.bg_color = INK
			body.set_corner_radius_all(int(h * 0.35))
			draw_style_box(body, Rect2(c + Vector2(-h * 0.7, -h), Vector2(h * 1.4, h * 1.5)))
			draw_rect(Rect2(c + Vector2(-h * 0.45, -h * 0.75), Vector2(h * 0.9, h * 0.5)), Color.WHITE)
			draw_circle(c + Vector2(-h * 0.35, h * 0.2), h * 0.15, Color.WHITE)
			draw_circle(c + Vector2(h * 0.35, h * 0.2), h * 0.15, Color.WHITE)
			draw_line(c + Vector2(-h * 0.5, h * 0.55), c + Vector2(-h * 0.8, h), INK, h * 0.2)
			draw_line(c + Vector2(h * 0.5, h * 0.55), c + Vector2(h * 0.8, h), INK, h * 0.2)
		_:
			var star := PackedVector2Array()
			for i in 10:
				var r := h if i % 2 == 0 else h * 0.42
				var a := -PI / 2 + i * PI / 5
				star.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(star, INK)
