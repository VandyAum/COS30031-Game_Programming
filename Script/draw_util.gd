class_name DrawUtil
## Small drawing helpers shared by map markers.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Add a static helper that draws a dashed circle on any CanvasItem (centre,
#    radius, colour, line width, dash length in the same units as the radius,
#    and a phase offset so the dashes can slowly march around)."


static func dashed_circle(ci: CanvasItem, centre: Vector2, radius: float, colour: Color,
		width := 2.0, dash := 10.0, phase := 0.0) -> void:
	if radius <= 0.0:
		return
	var circumference := TAU * radius
	var count := maxi(8, int(circumference / (dash * 2.0)))
	var step := TAU / count
	for i in count:
		var a := i * step + phase / radius
		ci.draw_arc(centre, radius, a, a + step * 0.5, 6, colour, width)
