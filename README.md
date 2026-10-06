# The Race Against Time

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Rewrite the README to the
     assessment's two-page limit: game description, connection to the DTP
     Vicmap challenge, controls, how to play, how to run the build, key
     programming systems, team contributions and known issues. Move the
     long developer notes to docs/DEVELOPMENT.md."
     Follow-up prompt: "Update team contributions from the commit history
     (camera pan/zoom was Vandy's); list Ishita in the team." -->

**Play in the browser:** _itch.io link goes here_ · **Engine:** Godot 4.7 (2D) ·
**Team:** Vandy, Ishita, Jessie, Leah (COS30031, Semester 2 2026)

You are an emergency dispatcher in Burrundara, a fictional suburb built from
real Vicmap data. Calls come in, and you draw each crew's route along the
roads. But your map only knows what your crews have seen, and everything they
see fades back to grey. Old traffic and roadblocks may no longer be true, and
new ones won't show until someone drives past. Pick routes, react when a crew
hits an obstacle the map didn't show, and keep every call from running out of
time.

## The challenge: DTP "Vicmap: The Race Against Time"

The brief asks for a game showing that **accurate, reliable spatial
information** helps people make better decisions in a developing emergency.
In our game that idea is the core mechanic, not a text box:

- **Knowing what is where matters.** Every dispatch is a route you draw
  yourself, using the roads, street names and Features of Interest on the map.
- **Reliable information matters.** The map goes stale. A route through a road
  that *looked* clear can stop a crew at a roadblock, while the call's timer
  keeps running.
- **Features of Interest are meaningful places.** Stations, hospitals,
  schools and shops come from the Vicmap FOI data. Calls happen at them, and
  the type of place decides which crew is needed.
- **Authoritative data has public value.** The after-action report ties
  your result to stale data ("crews stopped by obstacles the map didn't
  show"), ending with *"Before Vicmap, someone had to build the map. Today,
  that was you."*

## How to play

1. A call arrives: a pin with a timer ring appears, and a card shows in the
   incident panel on the left.
2. Click the pin or card, then press **Send ...** for a crew, or press on a
   station square.
3. **Hold the left mouse button** at the station and **drag along the roads**
   to the incident, then release on it. The crew drives your route exactly.
4. If the crew hits a road blocked since you last saw it, it stops with a red
   countdown. **Press on the crew and drag a new route** before the countdown
   runs out.
5. Crews resolve the call, drive home and rest. Calls left too long are
   passed to a neighbouring crew and cost a heart. Lose three hearts and the
   run ends.

**Progress:** a tutorial call, then three stages. Each stage reveals a larger
part of the map, brings more and harder calls (multi-crew crashes, fires,
storm damage) and more roadblocks. Resolve every stage to win.

### Controls

| Action | Input |
| --- | --- |
| Select incident / choose crew | Left click (pin, card, "Send" button or station) |
| Draw a route | Hold left mouse and drag along roads |
| Undo the last part of a route / clear it | **R** / **Space** |
| Pan / zoom | Right-drag / mouse wheel |
| Pause (hides the map) | **Esc** |
| Mute sound | **M** |

## Running the game

- **Browser:** open the itch.io link above (Chrome, Edge or Firefox). Click
  once to start audio.
- **From source:** install Godot **4.7**, open `project.godot` and press
  **F5** (main scene `main.tscn`).
- **Building the web version:** install the Godot 4.7.2 export templates,
  then *Project → Export → Web* (preset included in `export_presets.cfg`, no
  threads, so it runs on itch.io without extra headers). Zip `build/web/`
  and upload it as an HTML game. The preset already includes the
  non-resource map files (`*.json, *.bin, *.txt`).
- A zipped copy of the project is in `Submission/`.

## Key programming systems

| System | Where | Reused by |
| --- | --- | --- |
| **Event bus** (observer pattern) | `Script/Autoload/events.gd` | Every system emits and listens here: HUD, ticker, sound, particles, physics, stats |
| **Truth vs knowledge** | `World` (what is true), `Knowledge` (what the player has seen, fading) | Crews, map overlay, roadblocks, fog, end report |
| **Data-driven types** (Resources) | `IncidentType`, `CrewType`, `DebrisType`; `.tres` files in `Data/` | 13 incident types, 4 crew types, 7 debris types, 7 physics materials |
| **Crew state machine** | `Script/crew.gd` | All crews: available → en route → blocked → on scene → returning → cooldown |
| **Timers and cooldowns** | Incident timer rings, crew cooldown, blocked countdown | Incidents, crews, stations, HUD bars |
| **Spawning and pacing** | `Script/incident_manager.gd`, `World` | Incidents and random roadblocks per stage |
| **2D physics scenes** | `Script/scene_physics.gd`, `Scenes/*.tscn` | Incident debris, roadblocks, crew bumpers and sensors |
| **Feedback** | `Sfx` autoload, `Fx` particles, ticker | Driven by events, so any new event gets sound and effects in one line |

**Physics and collisions.** Crashes, storms, fallen trees and roadworks
scatter `RigidBody2D` debris that bounces off concrete barriers and each
other, and crews' kinematic bumpers shove it aside. Collision layers are
named in the project settings (barriers, vehicles, debris, incident zones,
crew sensors). Debris collides only with barriers, vehicles and debris.
Crews' `Area2D` sensors detect only incident zones, which decide when a crew
can park and walk in. There are seven `PhysicsMaterial`s in
`Data/physics_materials/`:

| Material | Behaviour |
| --- | --- |
| Rubber (tyres) | Bouncy |
| Glass | Slides, no bounce |
| Metal | Heavy, dull bounce |
| Wood (branches) | Rough, high friction |
| Plastic (cones, bins) | Springy |
| Sandbag | Absorbent |
| Concrete (barriers) | Firm, static |

## Team contributions

- **Vandy:** route drawing, camera panning and zoom, stations and crews,
  crew movement and returns.
- **Jessie:** HUD and UI design, incident cards.
- **Leah:** Vicmap world pipeline and map rendering, incidents as data, game
  systems (knowledge decay, obstacles, timers, stages, tutorial), physics,
  sound and particles.
- **Ishita:** team member.

Code was written with AI assistance (Claude, by Anthropic); prompts are kept
as comments in every script. Asset credits: [ATTRIBUTIONS.md](ATTRIBUTIONS.md).
Developer notes and debug keys: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Known issues

- **Only one kind of bad data.** Features of Interest are always correct in
  this prototype, and only live road information goes stale. Moved, missing
  and misclassified places (such as a hospital that isn't where the map says)
  are planned for Assessment 3.
- **One vehicle sprite.** All crew types share it, tinted by colour.
- **Debris is hard to see zoomed out.** At very low zoom, debris and barriers are
  small. Zoom in to see the physics.
- **Browser audio.** Sound starts only after the first click, a browser
  rule.
