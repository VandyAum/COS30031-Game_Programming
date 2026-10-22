class_name CrewType extends Resource
## One kind of emergency crew (police, ambulance, fire). Edit the .tres files
## in Data/crew_types/ in the inspector to tune them; no code changes needed.

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Define our crew types as data for the Godot 4.7 dispatch game: a
#    Resource class CrewType with an id, display name, the Vicmap FOI
#    subtype of the station it lives at (e.g. 'police station'), a colour,
#    an icon texture, driving speed in metres per second, cooldown seconds
#    after a job, and how many crews each station starts with (the spec says
#    one, upgradable later). Comment each field for designers."

## Short id used to match incidents to crews ("police", "ambulance", "fire").
@export var id: StringName
@export var display_name := ""
## Stations are created at every FOI with this feature_subtype.
@export var station_subtype := ""
@export var colour := Color.WHITE
@export var icon: Texture2D
## Driving speed at clear traffic, metres per (game) second. Game-paced, not real.
@export var speed_mps := 150.0
## Seconds a crew rests at its station after returning from a job.
@export var cooldown_seconds := 8.0
## Crews per station at the start of a run.
@export var crews_per_station := 1
