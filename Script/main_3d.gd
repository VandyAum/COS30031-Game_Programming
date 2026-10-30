extends Node3D

## Small integration prototype: one real Incident logic object, represented by
## its 3D view and selectable through the dedicated click-target layer.
## AI-assisted prompt: "Connect layer-7 3D ray picking to one Incident, one
## Crew, and the generated road graph; keep it isolated from the live 2D game."

const CLICK_TARGET_MASK := 1 << 6 # Layer 7: click_targets.
const RAY_LENGTH := 10000.0
const ROAD_SNAP_TOLERANCE_PX := 18.0
const TEST_INCIDENT_TYPE := preload("res://Data/incident_types/medical.tres")
const TEST_CREW_TYPE := preload("res://Data/crew_types/ambulance.tres")
const TEST_POLICE_TYPE := preload("res://Data/crew_types/police.tres")

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var city_map: Node3D = $CityMap3D
@onready var incident_views: Node3D = $Gameplay3D/Incidents
@onready var crew_views: Node3D = $Gameplay3D/Crews

var _incident_logic: Incident
var _selected_road_edge := -1


func _ready() -> void:
	_create_test_incident()
	_create_test_crew()


func _create_test_incident() -> void:
	_incident_logic = Incident.new()
	_incident_logic.name = "Main3DTestIncident"
	_incident_logic.type = TEST_INCIDENT_TYPE
	_incident_logic.crew_type = TEST_CREW_TYPE
	_incident_logic.needed_types = [TEST_CREW_TYPE]
	_incident_logic.place = "Cambermere Junction"
	_incident_logic.description = "3D click-picking prototype."
	_incident_logic.position = city_map.call("map_origin_position")
	var world_position: Vector3 = city_map.call(
		"map_position_to_world", _incident_logic.position
	)
	var incident_view := _incident_logic.create_3d_view(incident_views, world_position)
	incident_view.scale = Vector3.ONE * 4.5
	print("Main3D: test incident created at ", world_position)


func _create_test_crew() -> void:
	var crew_logic := Crew.new()
	crew_logic.name = "Main3DTestCrew"
	crew_logic.type = TEST_POLICE_TYPE
	crew_logic.callsign = "Police Test"
	var map_position: Vector2 = _incident_logic.position + Vector2(150.0, 0.0)
	var road_position = RoadGraph.snap(map_position, 100.0)
	if road_position != null:
		map_position = road_position.point
	crew_logic.position = map_position
	var world_position: Vector3 = city_map.call("map_position_to_world", map_position)
	var crew_view := crew_logic.create_3d_view(crew_views, world_position)
	crew_view.scale = Vector3.ONE * 4.5
	print("Main3D: test crew created at ", world_position)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var ray_origin := camera.project_ray_origin(event.position)
	var ray_direction := camera.project_ray_normal(event.position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * RAY_LENGTH,
		CLICK_TARGET_MASK
	)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		var ground_hit: Variant = Plane(Vector3.UP, 0.09).intersects_ray(ray_origin, ray_direction)
		if ground_hit != null:
			var ground_point: Vector3 = ground_hit
			_pick_road(ground_point)
		else:
			print("Main3D: click ray missed the roads and ground plane.")
		return
	var target := result["collider"] as Node
	if target.name == "RoadClickTarget":
		_pick_road(result["position"])
		return
	var view := target.get_parent()
	if view == null:
		return
	if view.has_method("get_incident_logic"):
		var picked_incident: Node = view.call("get_incident_logic")
		if picked_incident != null:
			picked_incident.set("selected", true)
			Events.incident_selected.emit(picked_incident)
			print("Picked 3D incident: ", picked_incident.call("title"))
		return
	if view.has_method("get_crew_logic"):
		var picked_crew: Node = view.call("get_crew_logic")
		if picked_crew != null:
			Events.crew_selected.emit(picked_crew)
			print("Picked 3D crew: ", picked_crew.get("callsign"))


func _pick_road(world_point: Vector3) -> void:
	var map_point: Vector2 = city_map.call("world_position_to_map", world_point)
	var road_position = RoadGraph.snap(map_point, ROAD_SNAP_TOLERANCE_PX)
	if road_position == null:
		print("Main3D: clicked point is not within %.0f map pixels of a playable road." % ROAD_SNAP_TOLERANCE_PX)
		return
	_selected_road_edge = road_position.edge
	print("Picked 3D road edge ", _selected_road_edge, ": ", RoadGraph.edge_name[_selected_road_edge])
