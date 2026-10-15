# Marker Evidence Sheet: The Race Against Time

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Draft the one-page Marker Evidence Sheet mapping each marking area to evidence, a video timestamp and where to test it." -->

Team: _[group name]_ · itch.io: _[link]_ · Video: _[YouTube link]_ · Repo: VandyAum/COS30031-Game_Programming

**Replace the timestamps with the ones from your final video.**

| Marking area | Evidence in the game | Video | Where to test |
| --- | --- | --- | --- |
| **Challenge Brief** | Map built from real Vicmap data (roads, FOI, land use, fictional names). Knowledge fades to grey; hidden roadblocks stop crews; FOI type decides the crew. After-action report links data quality to the result. | 1:40 | Any stage; end screen |
| **Core Gameplay & Progression** | Select call → choose crew → draw route → resolve → crew returns and cools down. Hearts, timer rings, progress bar, clock, ticker. Tutorial then 3 stages: bigger map, new incident types, multi-crew calls, more roadblocks. Win by clearing stage 3; lose at 0 hearts. | 2:34 | Tutorial → Stages 1–3 (F4 skips a stage in debug builds) |
| **Physics & Interactions** | RigidBody2D debris at crashes, storms, fallen trees and roadworks. Static concrete barriers on roadblocks. Kinematic crew bumpers push debris. Area2D crew sensors and incident zones (park and walk in). 5 named layers; 7 PhysicsMaterials (rubber, glass, metal, wood, plastic, sandbag, concrete). | 3:15 | Stage 1+ crashes; zoom in on any roadblock. Editor: Project Settings → Layer Names; `Scenes/debris_piece.tscn`; `Data/physics_materials/` |
| **Modular Programming** | (1) Event bus `Events`. (2) Data-driven `IncidentType` / `CrewType` / `DebrisType` resources. (3) `World` truth vs `Knowledge` player view. (4) Crew state machine. (5) Timers and cooldowns. (6) `Sfx` and `Fx` feedback driven by events. | 4:14 | `Script/Autoload/`, `Data/`, `Script/crew.gd` |
| **Animation & Feedback** | Pulsing pins and filling rings; urgent warning sound; obstacle alert burst, sound and countdown dial; resolve sparkle and chime; passed-on puff; fire, rain and water particles; colour vs grey map; ticker; tutorial highlights; button clicks; win/lose sounds; city ambience, engine hum while crews drive, siren on dispatch. | 5:00 | Any call; blocked crew; fires (stage 1+) |
| **Technical Delivery** | itch.io web build (no threads). README (2 pages). ATTRIBUTIONS.md. In-game Credits. Zipped project in `Submission/`. Known issues listed in the README. | 5:56 | itch.io · README.md · ATTRIBUTIONS.md |
