class_name DebrisType extends Resource
## One kind of physics debris (a tyre, glass, a branch...). Edit the .tres
## files in Data/debris_types/ to tune or add debris; ScenePhysics picks them
## up automatically. Incident types list which debris they scatter.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Add 2D physics to the Godot 4.7 dispatch game for the assessment: at
#    least four distinct PhysicsMaterials used on purpose, and collision
#    layers/masks configured so objects only touch what they should. Make it
#    part of the scenes the player already watches: crashes, fallen trees,
#    roadworks and storms scatter physical debris (RigidBody2D) that bounces
#    off concrete road barriers and each other, and crew vehicles shove it
#    aside when they arrive. Define the debris as data: a Resource
#    DebrisType with an id, a PhysicsMaterial (rubber tyres, glass, metal
#    panels, wooden branches, plastic cones/bins, absorbent sandbags, plus
#    concrete for the static barriers), a circle or box shape and size,
#    mass, linear/angular damping (the map is top-down, so damping stands in
#    for ground friction), colours to draw it with, the impact sound key and
#    whether hard hits throw sparks or glints."

enum Shape { CIRCLE, BOX }

@export var id: StringName
@export var display_name := ""
## How it bounces and slides (bounce, friction, rough, absorbent).
@export var physics_material: PhysicsMaterial
@export var shape := Shape.BOX
## Box size in world pixels; for a circle, x is the diameter.
@export var size := Vector2(8, 8)
@export var mass := 1.0
## Top-down "ground friction": higher stops sooner.
@export var linear_damp := 2.0
@export var angular_damp := 3.0
@export var colour := Color.GRAY
## Inner detail (tyre hub, cone stripe). Transparent = none.
@export var accent := Color(0, 0, 0, 0)
## Sfx key played when it hits something hard enough.
@export var impact_sound: StringName = &""
## Fx burst on a hard hit (&"sparks" for metal, &"glint" for glass), or empty.
@export var impact_fx: StringName = &""
