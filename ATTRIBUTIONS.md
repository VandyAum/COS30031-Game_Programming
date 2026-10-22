# Attributions

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Write ATTRIBUTIONS.md listing every third-party asset (source, author, licence) and the team-created assets, matching the in-game credits."
     Follow-up prompt: "Make sure all audio is listed, including the Freesound ambience and travel sounds." -->

Every asset in **The Race Against Time**, who made it and under what licence.
The same credits are shown in-game (**Credits** on the pause and end screens).

## Third-party assets

| Asset | Files | Source | Author / creator | Licence |
| --- | --- | --- | --- | --- |
| Map data: roads, rail, parcels, buildings, land use, water, suburbs, Features of Interest | `Map/world/*`, `Map/boroondara_foi_game_data.json` | [Vicmap](https://discover.data.vic.gov.au/) via DataVic; FOI extract supplied by the unit | © State of Victoria (Department of Transport and Planning) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), **modified** (reprojected, simplified, stylised, all names made fictional). Full dataset list: [Map/world/ATTRIBUTION.md](Map/world/ATTRIBUTION.md) |
| Map data: parks and reserves (PARKRES) | `Map/world/*` | [DataVic](https://discover.data.vic.gov.au/dataset/parks-and-conservation-reserves-parkres) | © State of Victoria (DEECA) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), modified |
| Font: Atkinson Hyperlegible Next | `UI/Fonts/` | [Google Fonts](https://github.com/google/fonts/tree/main/ofl/atkinsonhyperlegiblenext) | The Atkinson Hyperlegible Next Project Authors (Braille Institute) | [SIL OFL 1.1](UI/Fonts/OFL.txt) |
| Landmark icons and hearts | `UI/Icons/map/*.svg` | [Maki](https://github.com/mapbox/maki) | Mapbox | [CC0 1.0](UI/Icons/map/MAKI_LICENSE.txt), recoloured |
| SES hard-hat icon | `UI/Icons/hard-hat-fill.svg` | [Phosphor Icons](https://github.com/phosphor-icons/core) | © 2023 Phosphor Icons | [MIT](UI/Icons/PHOSPHOR_LICENSE.txt), recoloured |
| Crew icons (police, ambulance, fire) | `UI/Icons/local_*_128dp.svg` | [Material Symbols](https://fonts.google.com/icons) | Google | [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) |
| Crew vehicle sprite | `Assets/Police car.svg` | ["Police car free sprite"](https://grilledgamingyt.itch.io/police-car-free-sprite) on itch.io | SomeGame_Dev (grilledgamingyt) | Free to use with credit (no formal licence named on the page) |
| UI sound effects (16 sounds: new call, select, dispatch, arrival, obstacle, wrong crew, urgent, resolved, passed on, stage, pause, win, lose...) | `Assets/Audio/*_00*.ogg` (non-`impact`) | ["Interface Sounds"](https://kenney.nl/assets/interface-sounds) | Kenney (kenney.nl) | [CC0 1.0](Assets/Audio/KENNEY_INTERFACE_LICENSE.txt) |
| Debris impact sounds (12 sounds: rubber, glass, metal, wood, plastic, sandbag) | `Assets/Audio/impact*.ogg` | ["Impact Sounds"](https://kenney.nl/assets/impact-sounds) | Kenney (kenney.nl) | [CC0 1.0](Assets/Audio/KENNEY_IMPACT_LICENSE.txt) |
| City ambience loop | `Assets/Audio/fs_city_loop_qubodup_223093.ogg` | ["Seamless City Loop"](https://freesound.org/people/qubodup/sounds/223093/) on Freesound | qubodup | [CC0 1.0](Assets/Audio/FREESOUND_CREDITS.txt) |
| Siren (short burst on dispatch) | `Assets/Audio/fs_emergency_siren_onderwish_470504.ogg` | ["Emergency Siren"](https://freesound.org/people/onderwish/sounds/470504/) on Freesound | onderwish | [CC0 1.0](Assets/Audio/FREESOUND_CREDITS.txt) |
| Engine hum while crews drive | `Assets/Audio/fs_engine_loop_qubodup_54909.ogg` | ["Bus Motor/Engine Sound Loop"](https://freesound.org/people/qubodup/sounds/54909/) on Freesound | qubodup | [CC0 1.0](Assets/Audio/FREESOUND_CREDITS.txt) |
| Car passing (crew back at station) | `Assets/Audio/fs_car_passing_hinzebeat_171447.ogg` | ["Car passing by.wav"](https://freesound.org/people/hinzebeat/sounds/171447/) on Freesound | hinzebeat | [CC0 1.0](Assets/Audio/FREESOUND_CREDITS.txt) |
| Game engine | n/a | [Godot Engine 4.7](https://godotengine.org) | Godot Engine contributors | MIT |

## Team-created assets

| Asset | Files | Made by |
| --- | --- | --- |
| HUD layout and incident-panel design | `UI/HUD.tscn`, `UI/game_theme.tres` | Jessie |
| Stylised map rendering: monochrome base, colour reveal, land-use patterns (stripes, cross-hatch, dots), fog of war | `Script/world_map.gd`, `Script/road_overlay.gd` | Leah |
| Incident pins, timer rings, crew badges, station cooldown dials, route line | drawn in code: `Script/incident.gd`, `Script/crew.gd`, `Script/station.gd`, `Script/drawing.gd` | Team |
| Debris art (tyres, glass, panels, branches, cones, bins, sandbags) and striped road barriers | drawn in code: `Script/debris_piece.gd`, `Script/barrier.gd` | Team |
| Physics materials and debris definitions | `Data/physics_materials/*.tres`, `Data/debris_types/*.tres` | Team |
| Particle effects (fire, rain, water, sparkles, sparks, dust, alerts) | `Script/fx.gd` | Team |
| Fictional place, road and facility names; incident caller lines | `tools/build_world.py`, `Data/incident_types/*.tres` | Team |
| Tutorial tips, ticker messages, end-screen report, credits screen | `Script/tutorial.gd`, `Script/ticker.gd`, `Script/end_screen.gd`, `Script/credits.gd` | Team |

## AI assistance

Code and data files were written with AI assistance (Claude, by Anthropic), as
permitted by the unit outline. The prompts and follow-up prompts are kept as
comments at the top of each script and data file.
