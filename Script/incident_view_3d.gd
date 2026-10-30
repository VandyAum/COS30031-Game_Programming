extends Node3D
class_name IncidentView3D

## 3D presentation and click target for an existing Incident logic node.
## Keep this view in a 3D scene; pass the logic node and its 3D position
## through setup() when the 3D gameplay scene is assembled.

const CLICK_TARGET_LAYER := 1 << 6 # Named click_targets layer 7.

@onready var beacon: MeshInstance3D = $Beacon
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var click_area: Area3D = $ClickTarget

var incident_logic: Node
var _beacon_material: StandardMaterial3D


func _ready() -> void:
	_beacon_material = StandardMaterial3D.new()
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.albedo_color = Color("e34252")
	beacon.material_override = _beacon_material

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color.WHITE
	selection_ring.material_override = ring_material
	selection_ring.visible = incident_logic != null and bool(incident_logic.get("selected"))

	click_area.collision_layer = CLICK_TARGET_LAYER
	click_area.collision_mask = 0
	_refresh_from_logic()
	Events.incident_updated.connect(_on_incident_updated)
	Events.incident_selected.connect(_on_incident_selected)
	Events.incident_resolved.connect(_on_incident_finished)
	Events.incident_failed.connect(_on_incident_finished)


func setup(logic: Node, world_position: Vector3) -> void:
	incident_logic = logic
	global_position = world_position
	if is_node_ready():
		_refresh_from_logic()
		selection_ring.visible = incident_logic != null and bool(incident_logic.get("selected"))


func get_incident_logic() -> Node:
	return incident_logic


func _refresh_from_logic() -> void:
	if incident_logic == null or _beacon_material == null:
		return
	var crew_type: Resource = incident_logic.get("crew_type")
	if crew_type != null:
		var crew_colour: Variant = crew_type.get("colour")
		if crew_colour is Color:
			_beacon_material.albedo_color = crew_colour


func _on_incident_updated(changed_incident: Node) -> void:
	if changed_incident == incident_logic:
		_refresh_from_logic()


func _on_incident_selected(selected_incident: Node) -> void:
	selection_ring.visible = selected_incident == incident_logic


func _on_incident_finished(finished_incident: Node) -> void:
	if finished_incident == incident_logic:
		queue_free()
