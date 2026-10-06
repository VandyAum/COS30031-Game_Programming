# COS30031-Game_Programming
Game_Programming course

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Add a short team-facing section
     to the README explaining how the map data is built from Vicmap, which
     autoloads exist and what each is for, how to test with the debug keys,
     and the export note for the raw data files."
     Follow-up prompt: "Update for rectangular stages, fictional names, the
     colour reveal, and add a data attribution / licence section."
     Follow-up prompt: "Document the milestone 1 systems: stations, crews,
     incidents as data, the HUD, and how to add a new incident type." -->

## Map & systems (prototype)

The map is **one world** built from real Vicmap open data, with every place,
road and facility name replaced by a fictional one. Stages are rectangles
that reveal more of it: 0 a small tutorial around the junction → 1 halfway
to stage 2 → 2 roughly three suburbs → 3 exactly double stage 2.

The map is monochrome until a crew looks at it: crews reveal roads (traffic
colours) and the map's colours within their sight radius, and both fade
back to grey over `Knowledge.fade_seconds`.

**Rebuilding the map data** (only needed if you change the build scripts):

```
python3 tools/fetch_vicmap.py   # downloads raw Vicmap layers to tools/cache (git-ignored)
python3 tools/build_world.py    # writes the game data (fictional names) to Map/world/
```

Stage rectangles live at the top of `tools/build_world.py` (`STAGE_RECTS_M`).

**Autoloads** (talk through `Events`, don't reach into each other's nodes):

| Autoload | Job |
| --- | --- |
| `Events` | Shared signal list: incidents, crews, routes, roads, stage, lives |
| `Stage` | Current stage rectangle, `stage_at(pos)`, `is_playable(pos)`, `geo_to_world(lon, lat)` |
| `RoadGraph` | Road network: `snap(pos)`, `route(a, b)`, street names, road classes |
| `World` | What is TRUE: traffic/blockages per road. Crews feel this |
| `Knowledge` | What the PLAYER knows: last-seen traffic + age, `sight(pos)` for crew sightings |

**Gameplay nodes** (in `main.tscn`):

| Node / file | Job |
| --- | --- |
| `Stations` (`Script/station_manager.gd`) | Creates a `Station` at every police/ambulance/fire FOI, each with its `Crew`s |
| `Crew` (`Script/crew.gd`) | Available → en route → on scene → returning (pathfinds home) → cooldown |
| `Incidents` (`Script/incident_manager.gd`) | Spawns incidents on a fixed schedule (per-stage interval and cap) |
| `Incident` (`Script/incident.gd`) | Reported → crew en route → on scene (resolve timer) → resolved; wrong crew type is sent home |
| `Drawing` (`Script/drawing.gd`) | Map input: select incidents, draw routes, dispatch |
| `UI/HUD` (`Script/hud.gd` on Jessie's `UI/HUD.tscn`) | Incident cards, tabs, "Send" buttons, crew list |

**Data:** crew types live in `Data/crew_types/*.tres` and incident types in
`Data/incident_types/*.tres`. To add an incident, duplicate a `.tres` in the
FileSystem dock, change its id, name, crew type, location rules and caller
descriptions in the inspector. It is picked up automatically.

**Testing** (run `main.tscn`): click an incident pin or card, press
"Send ..." (or press on a station square), then hold the left mouse at the
station and drag along the roads; release on the incident. Right-drag pans,
wheel zooms. F1 debug HUD · F2 road network · F3 reveal all roads ·
F4 next stage · F5 spawn an incident now.

**Exporting:** add `*.json, *.bin` to the export preset's "non-resource files"
filter so `Map/world/` is included in builds.

## Data attribution

Map data: Vicmap © State of Victoria (Department of Transport and Planning);
PARKRES © State of Victoria (Department of Energy, Environment and Climate
Action). Licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The data has been modified (reprojected, simplified, stylised, names made
fictional); no endorsement by the State of Victoria is implied. The exact
datasets, layers and retrieval dates are listed in
[Map/world/ATTRIBUTION.md](Map/world/ATTRIBUTION.md), and the credit line is
shown in-game bottom-right.
