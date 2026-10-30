extends Node3D
class_name CrewView3D

## Pickable greybox vehicle proxy for existing Crew logic.
## AI-assisted: prototype crew picking view; prompt: "Create a simple 3D
## crew proxy on click_targets layer 7, expose its Crew logic, and show a ring
## when Events.crew_selected selects it. Do not add movement logic."

const CLICK_TARGET_LAYER := 1 << 6

@onready var vehicle: MeshInstance3D = $Vehicle
@onready var cabin: MeshInstance3D = $Cabin
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var click_area: Area3D = $ClickTarget

var crew_logic: Node
var _vehicle_material: StandardMaterial3D
var _cabin_material: StandardMaterial3D


func _ready() -> void:
	_vehicle_material = StandardMaterial3D.new()
	_vehicle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vehicle.material_override = _vehicle_material
	_cabin_material = StandardMaterial3D.new()
	_cabin_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cabin_material.albedo_color = Color("e8edf2")
	cabin.material_override = _cabin_material
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color.WHITE
	selection_ring.material_override = ring_material
	click_area.collision_layer = CLICK_TARGET_LAYER
	click_area.collision_mask = 0
	selection_ring.visible = false
	Events.crew_selected.connect(_on_crew_selected)
	_refresh_from_logic()


func setup(logic: Node, world_position: Vector3) -> void:
	crew_logic = logic
	global_position = world_position
	if is_node_ready():
		_refresh_from_logic()


func get_crew_logic() -> Node:
	return crew_logic


func _refresh_from_logic() -> void:
	if crew_logic == null or _vehicle_material == null:
		return
	var crew_type: CrewType = crew_logic.get("type")
	if crew_type != null:
		_vehicle_material.albedo_color = crew_type.colour


func _on_crew_selected(selected_crew: Node) -> void:
	selection_ring.visible = selected_crew == crew_logic
