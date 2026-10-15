extends StaticBody2D
## A concrete road barrier closing a blocked road. Static, with the concrete
## PhysicsMaterial, so debris rebounds off it. Layer 1 "barriers"; it has
## no mask (static bodies don't need to detect anything). Crew vehicles
## don't collide with it (their mask is debris only), so a crew sent onto
## the road the player knew was closed isn't physically jammed.

# AI-assisted (Claude Opus 5.5): written from the prompt in
# Script/Data/debris_type.gd, plus: "A barrier scene: StaticBody2D with a
#    box shape, concrete material, setup(length) resizing the shape, drawn
#    as a red-and-white striped road closure board."

const THICKNESS := 5.0

var length := 26.0


func setup(barrier_length: float) -> void:
	length = barrier_length
	var r := RectangleShape2D.new()
	r.size = Vector2(length, THICKNESS)
	($Shape as CollisionShape2D).shape = r
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(-length * 0.5, -THICKNESS * 0.5), Vector2(length, THICKNESS))
	draw_rect(rect, Color.WHITE)
	var stripe := THICKNESS * 1.2
	var x := -length * 0.5
	var i := 0
	while x < length * 0.5:
		if i % 2 == 0:
			draw_rect(Rect2(Vector2(x, -THICKNESS * 0.5), Vector2(minf(stripe, length * 0.5 - x), THICKNESS)), Color("d62828"))
		x += stripe
		i += 1
	draw_rect(rect, Color(0.2, 0.1, 0.1), false, 1.0)
