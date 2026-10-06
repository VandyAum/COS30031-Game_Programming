# Video script: The Race Against Time (recorded length 6:16, hard limit 10)

<!-- AI-assisted (Claude Opus 5.5). Prompt: "Write a 7-8 minute video script for the team to read: a player-facing showcase first, then evidence for each marking area with what to show on screen." -->

Speakers: **Leah**, **Vandy**, **Ishita**, **Jessie**. Swap lines to whoever
built that part, because the interviews check you can explain your own
work. Lines in *italics* are what to show on screen. Note your real
timestamps for the Marker Evidence Sheet as you record.

---

## Part 1: Showcase (0:00–1:40). No code, no editor.

**[0:00] Leah:** *Title screen, map of Burrundara.*
Hi, we're [team name], and this is *The Race Against Time*. Our client was
the Department of Transport and Planning, the team behind Vicmap. Their
brief: show why accurate, reliable map information matters when an
emergency is unfolding.

**[0:19] Vandy:** *First tutorial call appears.*
You're an emergency dispatcher. A call comes in: a pin with a ring that
fills up as time passes. You choose a crew and draw its route yourself,
road by road, from the station to the scene.

**[0:32] Ishita:** *Draw the route; the crew drives; the map lights up in colour around it.*
Here's the twist. The map starts grey. You only know what your crews have
actually seen: they reveal traffic as they drive. And that knowledge fades
back to grey within a couple of minutes.

**[0:45] Jessie:** *Crew hits a roadblock and stops with the red countdown; barrier and debris visible.*
So the map lies, not on purpose, but because it's out of date. This road
looked clear when we last saw it. Now our crew is stuck, the call's timer
is still running, and we have to redraw a new route before the countdown
runs out.

**[1:01] Leah:** *Redraw, arrive, green sparkle, "resolved" sound.*
Every delay you see here is caused by stale information. Resolve calls to
move through three stages. Each one opens up more of the city and brings
bigger incidents: crashes needing police and an ambulance, house fires,
storm damage for the SES.

**[1:20] Vandy:** *Stage transition: camera and fog glide out.*
Let three calls slip and the run ends. Neighbouring councils step in.

**[1:25] Ishita:** *End screen / after-action report.*
At the end, the after-action report connects your result to the data: how
many crews were stopped by obstacles the map didn't show. And the reveal:
before Vicmap, someone had to build the map. Today, that was you.

---

## Part 2: Assessment evidence (1:40–6:16)

### Challenge response (1:40–2:34), Leah

*Show the map's Vicmap credit, then the FOI landmarks.*
The world is built from real Vicmap open data, using roads, buildings, land
use and the Features of Interest extract for Boroondara, with every name
made fictional so we never depict a real emergency. The brief's four key
messages are carried by mechanics:
- **Knowing what is where:** you draw every route yourself.
- **Reliable information matters:** fading knowledge and hidden roadblocks
  cost you time.
- **Features of Interest are meaningful places:** stations, hospitals and
  schools are real FOI, and where a call happens decides who's needed.
- **Authoritative data has value:** the after-action report says so.

The brief also wants incorrectly located and misclassified data. Ours shows
*outdated* data now. A hospital that isn't where the map says is our first
Assessment 3 feature.

### Core gameplay and progression (2:34–3:15), Vandy

*Play: select → send → draw → arrive → resolve. Point at hearts, the
progress bar, the clock and the ticker.*
The loop: a call arrives, you select it, pick a crew and draw a route. The
crew follows it, resolves the call, drives home and cools down. Progress is
the bar at the top: tutorial, three stages, then the win bauble.

*Press F4 to jump stages, or show clips.*
Stage 1 is Cambermere: police crashes, break-ins, car fires. Stage 2 adds
two suburbs, house fires and SES storm calls. Stage 3 is all of Burrundara,
with serious crashes needing all three services and more roadblocks. Fail
by letting three timer rings fill; win by clearing stage 3.

### Physics and collisions (3:15–4:14), Leah

*In game, zoom right in on a crash: debris scatters; a crew drives through
it and shoves it aside. Then a roadblock: debris bouncing between barriers.*
Incidents scatter real physics debris: glass, tyres, panels, branches,
cones, bins and sandbags. Roadblocks get concrete barriers the debris
bounces off, and crew vehicles physically push it out of the way.

*Editor: Project Settings → Layer Names → 2D Physics.*
We named five collision layers: barriers, vehicles, debris, incident zones
and crew sensors.

*Open `Scenes/debris_piece.tscn`, then the Collision layer/mask grid.*
Debris sits on the debris layer and only collides with barriers, vehicles
and other debris. Crews' sensors only detect incident zones. That overlap
is what lets a crew park and walk in when the road ahead is blocked, so
crews never interact with each other.

*Open `Data/physics_materials/`, click rubber, glass, sandbag.*
Seven physics materials:
- Rubber tyres bounce.
- Glass slides with no bounce.
- Metal is heavy.
- Wood is rough.
- Plastic is springy.
- Sandbags are absorbent.
- The concrete barriers are firm.

You can see the difference: tyres ricochet, glass skates, sandbags just
thud.

### Modular systems (4:14–5:00), Ishita

*Open `Script/Autoload/events.gd`, then the FileSystem `Data/` folder.*
Our first system is an **event bus**. Every system emits and listens to
signals here. Sound, particles, the ticker and the HUD all react to the same
events without knowing about each other.

Second, **data-driven types**: incidents, crews and debris are resources.
There are 13 incident types; adding one is duplicating a `.tres` file.
*Click `car_crash.tres` and show its debris and crew fields.*

Third, **truth versus knowledge**: `World` holds what's true, `Knowledge`
holds what the player has seen and when. Crews, the map, roadblocks and the
end report all use it.

Fourth, the **crew state machine**, shared by every crew. And our timers
and cooldowns are reused across incidents, crews and stations.

### Animation, feedback and player experience (5:00–5:56), Jessie

*Show each as you say it.*
- **Timer rings:** they fill from orange to red, and pins pulse faster as
  time runs out. At three-quarters there's a warning sound.
- **Obstacle:** a red alert burst, an error sound, and a countdown dial
  on the crew.
- **Resolved:** a green sparkle and a chime. **Passed on:** a grey puff
  and a heart lost.
- **Fires:** animated flames on the pin. Storms have rain, and burst
  mains spray water.
- **The map itself is feedback:** colour means fresh, grey means stale.
- **The ticker** narrates every event, and tutorial tips highlight what
  they describe.
- **Sound:** a city ambience bed and an engine hum that grows with the
  number of crews on the road. Dispatches get a short siren, and crews
  pull back into their station with a car-passing sound.
- Every button clicks, and **M** mutes.

### Technical delivery (5:56–6:16), Vandy

*itch.io page, README, ATTRIBUTIONS.md, GitHub history.*
The game is playable in the browser on itch.io. The README covers controls,
how to run and build it, our systems and known issues. Every third-party
asset is credited in `ATTRIBUTIONS.md`: Vicmap data, fonts, icons and
Kenney's CC0 sounds. Thanks for watching!
