<!-- AI-assisted (Claude Opus 5.5). Prompt: "Archive the terrain heights prototype (it didn't add
     much visually and caused clipping) with a note on what it was and how to bring it back." -->

# Terrain prototype (archived)

Real ground heights for the greybox 3D city, archived on 2026-10-29. It worked, but the
hills (about 74 m of relief over 3 km) added little to the view from above and caused
clipping. Godot ignores this folder (`archive/.gdignore`), so nothing here is loaded.

## What it did

- `tools/build_terrain.py` turned Vicmap Elevation's metro 1 m contours and spot heights
  into a 10 m height grid with a land-cover byte (ground, park, water, site). It also built
  a height profile every 5 m along every road in `roads.json`. The profiles were graded
  like real roads, pinned at junctions, and bridged over creeks and rail. The ground under
  each road was then flattened to the road's height.
- `data/terrain.bin` and `data/terrain.json` are that tool's output for the current map
  (about 2.8 MB).
- `Script/city_3d.gd` (terrain version) drew the ground as a grid mesh and draped roads on
  their profiles. Buildings stood on the lowest ground under them. T switched terrain on
  and off.
- `Script/city_3d_traffic.gd` (terrain version) took each car's height, tilt and speed
  from the road profile. It included `slope_speed_factor(grade)`: −20% per +10% climb,
  up to +8% downhill.
- `Script/city_3d_camera.gd` and `Script/fps_probe.gd` kept the camera above the ground
  and showed the terrain state.
- `tools/fetch_vicmap.py` (terrain version) also downloaded the `el_contour_1to5m` and
  `el_grnd_surface_point_1to5m` layers (about 25 MB).

## Design notes

Crews only move along roads, so terrain does not need 3D physics. Each vehicle's 2D state
(edge, distance along it) plus the shared road profile gives its height, tilt and slope
speed. To keep the 3D view and the simulation consistent, both must read the same
profiles. That covers drawing, crew speed (`crew.gd`) and route costs (`RoadGraph`). The
2D map, debris physics and fog of war could stay 2D.

## Bringing it back

1. Copy `tools/*` and `Script/*` over the current files, and merge them by hand where the
   current versions have moved on.
2. Run `python tools/fetch_vicmap.py`, then `python tools/build_terrain.py` (this needs
   numpy and scipy). You can also copy `data/terrain.*` into `Map/world/`.
3. Add "terrain (Vicmap Elevation contours)" to the Vicmap row in `ATTRIBUTIONS.md`. Same
   source and licence (CC BY 4.0).
