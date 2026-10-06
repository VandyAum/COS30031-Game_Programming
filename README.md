# COS30031-Game_Programming
Game_Programming course

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Add a short team-facing section
     to the README explaining how the map data is built from Vicmap, which
     autoloads exist and what each is for, how to test with the debug keys,
     and the export note for the raw data files."
     Follow-up prompt: "Update for rectangular stages, fictional names, the
     colour reveal, and add a data attribution / licence section."
     Follow-up prompt: "Document the milestone 1 systems: stations, crews,
     incidents as data, the HUD, and how to add a new incident type."
     Follow-up prompt: "Add the milestone 2 systems (changing truth,
     blockages, obstacle stops, redraws, fog of war, landmarks, patterns)
     and the new debug key."
     Follow-up prompt: "Add milestone 3: lives, clock, ticker, progress bar,
     timer rings, failure, multi-crew incidents, pause and the end screen."
     Follow-up prompt: "Add the playtest fixes: tutorial tips, incident
     variety and pacing, SES, animated stages, the step ticker, softer
     wording for passed-on calls, and the T-junction repair."
     Follow-up prompt: "Add the second round: tutorial highlights and route
     demo, road-name labels, coloured landmark icons, station cooldown
     dials, route clean-up, parking rules and the 100 m blockage buffer."
     Follow-up prompt: "Add every licence and attribution (team, AI
     assistance, map data, font, icons) in a Credits & licences section,
     matching the in-game credits screen." -->

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

**Milestone 2 (information decays):** `World` keeps changing: traffic drifts
on every road and random blockages appear and clear (car crashes also block
their own road). Crews reveal roads and map colour within their sight
radius; it fades over `Knowledge.fade_seconds`, and never-seen areas sit
under a light fog. A crew that reaches a blocked road it didn't know about
stops with a red alert; press on the crew and drag a new route from where it
is (it waits while you draw). Land use is shown by patterns (stripes =
shops, cross-hatch = public, dots = industrial) and Features of Interest by
pictograms, because colour is reserved for what crews have seen.

**Milestone 3 (pressure and failure):** the `Run` autoload holds three
lives (hearts in the top bar), the clock (one in-game minute per second, in
the ticker corner) and progress: the tutorial call, then each stage after a
set number of resolved incidents (`Run.resolved_to_advance`), then the win
bauble. Each incident has a timer ring that fills while unattended, slows
while a crew is en route and pauses once every crew it needs is on scene
(some calls need several crews, e.g. a crash with injuries needs police and
an ambulance). When a ring fills, the call is passed to a neighbouring crew
and a heart goes; the same happens when a blocked crew's countdown dial runs
out. Events slide in along the bottom ticker. Esc pauses (and hides the
map). Use up all the hearts (or finish stage 3) for the end screen and
after-action report.

**Playtest fixes:** first-time tutorial tips pause the game and explain the
controls (`Script/tutorial.gd`; shown once per session, "Skip tips" turns
them off). Stages open with the camera and fog gliding out together
(`Stage.transition_seconds`). Calls are paced so a crew type never has more
open calls than crews in play (`IncidentManager.overload_by_stage` allows
extra in stage 3), and each stage adds variety: police-only crashes,
break-ins and disturbances, car and grass fires from stage 1, house and
building fires, plus SES calls (tree down, storm damage) from stage 2, and
serious crashes needing all three services in stage 3. Stations keep
watching their area, seen traffic fades over 120 s, random blockages stay
100 m clear of incidents and stations, and a crew blocked within 60 m of
its incident parks and walks in (otherwise it drives all the way). The
world build repairs side streets that end on a main road without a
junction node and drops tiny unnamed service-lane loops
(`tools/build_world.py`). Drawn routes are cleaned of any out-and-back
spurs after every step (`_despur` in `drawing.gd`).

Tutorial tips highlight what they describe (pulsing outlines on the HUD,
rings on the map) and the dispatch tip plays an animated route-drawing demo.
Street names follow the roads (`Script/road_labels.gd`): main roads when
zoomed out, collectors and then local streets as you zoom in. Landmark
pictograms have a colour per kind of place (never a crew colour), and
stations show a countdown dial for each crew resting after a job.

**Data:** crew types live in `Data/crew_types/*.tres` and incident types in
`Data/incident_types/*.tres`. To add an incident, duplicate a `.tres` in the
FileSystem dock, change its id, name, crew type, location rules and caller
descriptions in the inspector. It is picked up automatically.

**Testing** (run `main.tscn`): click an incident pin or card, press
"Send ..." (or press on a station square), then hold the left mouse at the
station and drag along the roads; release on the incident. Right-drag pans,
wheel zooms. F1 debug HUD (hidden by default) · F2 road network · F3 reveal all roads ·
F4 next stage · F5 spawn an incident now · F6 block the road under the mouse ·
Esc pause.

**Exporting:** add `*.json, *.bin, *.txt` to the export preset's "non-resource files"
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

## Credits & licences

The same information is shown in-game: **Credits** on the end screen and
the pause screen (`Script/credits.gd`).

**Team:** Vandy (route drawing, stations and crews), Ishita (map panning
and zoom, incident data, incident panel), Jessie (HUD design), Leah (Vicmap
world, game systems). Code was written with AI assistance (Claude, by
Anthropic); the prompts are kept as comments in the source.

| Asset | Source | Licence | Files |
| --- | --- | --- | --- |
| Map data | Vicmap © State of Victoria (DTP); PARKRES © State of Victoria (DEECA) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), modified | `Map/world/`, see [ATTRIBUTION.md](Map/world/ATTRIBUTION.md) |
| Font: Atkinson Hyperlegible Next | [Google Fonts](https://github.com/google/fonts/tree/main/ofl/atkinsonhyperlegiblenext), © 2020-2024 The Atkinson Hyperlegible Next Project Authors | [SIL OFL 1.1](UI/Fonts/OFL.txt) | `UI/Fonts/`, `UI/game_theme.tres` |
| Landmark icons and hearts | [Maki](https://github.com/mapbox/maki) by Mapbox | [CC0 1.0](UI/Icons/map/MAKI_LICENSE.txt), recoloured white | `UI/Icons/map/` |
| SES hard hat | [Phosphor Icons](https://github.com/phosphor-icons/core), © 2023 Phosphor Icons | [MIT](UI/Icons/PHOSPHOR_LICENSE.txt), recoloured white | `UI/Icons/hard-hat-fill.svg` |
| Crew icons (police, ambulance, fire) | [Material Symbols](https://fonts.google.com/icons) by Google | Apache 2.0 | `UI/Icons/local_*_128dp.svg` |
| Crew car | ["Police car free sprite"](https://grilledgamingyt.itch.io/police-car-free-sprite) by SomeGame_Dev (grilledgamingyt) on itch.io | Free to use with credit (no formal licence stated) | `Assets/Police car.svg` |

