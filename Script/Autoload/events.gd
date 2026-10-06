extends Node
## Events (autoload): the shared signal bus. Systems emit and listen here
## instead of holding references to each other, so the map, crews, incidents
## and UI can be built (and owned) separately.
##
## Usage:  Events.crew_arrived.emit(crew, incident)
##         Events.crew_arrived.connect(_on_crew_arrived)

# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Create a Godot 4.7 autoload 'Events' that is only a list of typed
#    signals, acting as the agreed communication contract between systems in
#    our dispatch game (map knowledge, crews, incidents, run state/UI). Cover
#    the whole first-playable loop and the next milestones from our dev list:
#    incidents spawning/selected/resolved/failed, crew dispatched/arrived/
#    blocked by an obstacle/returned/ready after cooldown, road knowledge
#    changing, lives and end of run. Group and comment them so teammates know
#    who emits each one. Use 'Variant'/Node parameters so the crew and incident
#    classes can be written later without editing this file."
# Follow-up prompt (milestone 1): "Add signals the incidents panel and crew
#    list need: an incident's details changed (status, assigned crew, wrong
#    crew sent), a crew changed state, and the player chose a crew to send."
# Follow-up prompt (audio): "Add incident_urgent, emitted once when an
#    incident's timer ring passes three-quarters, so Sfx can warn the player."
@warning_ignore_start("unused_signal")

# --- Map knowledge (emitted by Knowledge / World) ---
## The player's knowledge of a road changed (crew drove it, intel, etc.).
signal road_observed(edge: int)
## The true state of a road changed (traffic, blockage). Player is NOT told.
signal road_truth_changed(edge: int)

# --- Incidents (emitted by the incident system) ---
signal incident_spawned(incident: Node)
signal incident_selected(incident: Node)
signal incident_resolved(incident: Node)
signal incident_failed(incident: Node)
## Status, assigned crew or progress changed (panel should refresh).
signal incident_updated(incident: Node)
## The timer ring just passed three-quarters full (emitted once).
signal incident_urgent(incident: Node)

# --- Crews (emitted by crews / stations) ---
signal crew_dispatched(crew: Node, incident: Node)
signal crew_arrived(crew: Node, incident: Node)
## Crew hit an obstacle the player didn't know about and has stopped.
signal crew_blocked(crew: Node, edge: int)
signal crew_returned(crew: Node)
signal crew_ready(crew: Node)
## Any change of crew state (available, en route, on scene, returning, cooldown).
signal crew_state_changed(crew: Node)
## The player picked a crew to send (from the panel or by pressing its station).
signal crew_selected(crew: Node)

# --- Route drawing ---
signal route_drawing_started(crew: Node)
signal route_committed(crew: Node, points: PackedVector2Array, edges: Array)

# --- Run state ---
## The playable area grew (or changed). Emitted by Stage.
signal stage_changed(stage: int)
signal lives_changed(lives: int)
## Resolved incidents toward the next stage changed (Run.progress()).
signal progress_changed()
signal paused_changed(paused: bool)
## "won" or "lost".
signal run_ended(reason: String)
## Free-form line for the bottom news ticker (BBCode allowed).
signal ticker_message(text: String)

@warning_ignore_restore("unused_signal")
