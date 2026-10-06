class_name IncidentType extends Resource
## One kind of incident (car crash, medical, house fire). Edit the .tres files
## in Data/incident_types/ to tune or add incidents; IncidentManager picks
## them up automatically.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Define incidents as data for the Godot 4.7 dispatch game: a Resource
#    class IncidentType with an id, display name, the crew type ids it needs
#    (an array so multi-crew incidents like a crash needing police AND an
#    ambulance can be added in milestone 3), how long the crew spends on
#    scene to resolve it, a time limit for the milestone 3 timer ring, a spawn
#    weight, and WHERE it can happen: either on a road (with allowed road
#    classes) or at a Feature of Interest (with allowed FOI types/subtypes).
#    Include description templates with a {place} token that the incident
#    panel shows, written like a caller would say it. Comment each field."
# Follow-up prompt (milestone 2): "Add blocks_road: road incidents such as
#    car crashes block the road they are on until resolved (spec: 'Car crash -
#    static, blocks its road')."
# Follow-up prompt (milestone 3): "Add min_stage so each stage introduces its
#    incidents as in the spec's run structure (tutorial: EMS; stage 1:
#    crashes; stage 2: fires). Car crashes need police AND an ambulance."

enum Where { ROAD, FOI }

@export var id: StringName
@export var display_name := ""
## Crew type ids needed. Milestone 1 uses the first entry.
@export var crew_types: Array[StringName] = []
## Seconds the crew spends on scene before the incident is resolved.
@export var resolve_seconds := 4.0
## Seconds before the incident fails (used by the milestone 3 timer ring).
@export var time_limit_seconds := 60.0
## First stage this incident can appear in (0 = tutorial).
@export var min_stage := 0
## Relative chance of this incident being picked by the spawner.
@export var weight := 1.0
## Where it happens.
@export var where := Where.ROAD
## For ROAD: the incident blocks its road until resolved (crews sent to it
## can still reach it).
@export var blocks_road := false
## For ROAD: allowed road classes (0 local, 1 collector, 2 arterial, 3 freeway).
@export var road_classes: Array[int] = [0, 1, 2]
## For FOI: allowed FOI feature_type or feature_subtype values.
@export var foi_types: Array[String] = []
## What the caller says. {place} becomes the road or landmark name.
@export var descriptions: Array[String] = ["Something is happening at {place}"]


func needs(crew_type_id: StringName) -> bool:
	return crew_types.has(crew_type_id)


func primary_crew_type() -> StringName:
	return crew_types[0] if not crew_types.is_empty() else &""
