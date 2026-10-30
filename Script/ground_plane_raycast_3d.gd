extends Node3D

## Small isolated prototype for ground-plane coordinates and click-target
## picking on the named 3D click_targets collision layer.

const GROUND_HEIGHT := 0.5
const CLICK_TARGET_MASK := 1 << 6 # Layer 7 is bit 6 (value 64).
const RAY_LENGTH := 1000.0
const TEST_INCIDENT_TYPE := preload("res://Data/incident_types/medical.tres")
const TEST_CREW_TYPE := preload("res://Data/crew_types/ambulance.tres")

@onready var camera: Camera3D = $Camera3D
@onready var marker: MeshInstance3D = $RaycastMarker
@onready var incident_views: Node3D = $IncidentViews

var _pending_click_position := Vector2.ZERO
var _has_pending_click := false
var _test_incident: Incident


func _ready() -> void:
	camera.look_at(Vector3(0.0, GROUND_HEIGHT, 0.0), Vector3.UP)
	_test_incident = Incident.new()
	_test_incident.name = "RaycastTestIncident"
	_test_incident.type = TEST_INCIDENT_TYPE
	_test_incident.crew_type = TEST_CREW_TYPE
	_test_incident.needed_types = [TEST_CREW_TYPE]
	_test_incident.place = "Raycast Test"
	_test_incident.description = "Test incident for 3D click picking."
	_test_incident.create_3d_view(incident_views, Vector3(0.0, GROUND_HEIGHT, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pending_click_position = event.position
		_has_pending_click = true


func _physics_process(_delta: float) -> void:
	if not _has_pending_click:
		return
	_has_pending_click = false

	var ray_origin := camera.project_ray_origin(_pending_click_position)
	var ray_direction := camera.project_ray_normal(_pending_click_position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * RAY_LENGTH,
		CLICK_TARGET_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var target := result["collider"] as Node
		var target_view := target.get_parent()
		if target_view and target_view.has_method("get_incident_logic"):
			var incident_logic: Node = target_view.call("get_incident_logic")
			if incident_logic:
				var incident_manager := get_tree().get_first_node_in_group("incident_manager")
				if incident_manager and incident_manager.has_method("select"):
					incident_manager.call("select", incident_logic)
				else:
					incident_logic.set("selected", true)
					Events.incident_selected.emit(incident_logic)
				var incident_title: String = (
					str(incident_logic.call("title"))
					if incident_logic.has_method("title")
					else str(incident_logic.name)
				)
				print("Picked incident: ", incident_title)
				marker.global_position = result["position"] + Vector3.UP * 0.2
				marker.visible = true
				return
		print("Clicked target: ", target.name)
		marker.global_position = result["position"] + Vector3.UP * 0.2
		marker.visible = true
		return

	var ground_plane := Plane(Vector3.UP, GROUND_HEIGHT)
	var hit: Variant = ground_plane.intersects_ray(ray_origin, ray_direction)
	if hit == null:
		print("No click target or ground point under the mouse.")
		return

	var world_point: Vector3 = hit
	marker.global_position = world_point + Vector3.UP * 0.2
	marker.visible = true
	print("Ground point: ", world_point)
