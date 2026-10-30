# 3D city scene structure and asset pipeline

**Status:** Implemented in the `Main3D` prototype following Leah's project direction.

## What the project does today

- `tools/build_world.py` generates `Map/world/roads.json`, `areas.json`,
  `buildings.bin`, `foi.json`, `world_meta.json`, and `ATTRIBUTION.md`.
- `world_meta.json` records the world dimensions and a scale of `0.75` map
  pixels per metre. Generated map coordinates start at the top-left; X increases
  east and Y increases south.
- `Script/world_map.gd` currently reads those outputs and draws the world with
  2D nodes. It does not generate a 3D city yet.
- The live game root and gameplay logic for incidents, crews, and stations are
  currently 2D. The isolated 3D collision/raycast scene and `IncidentView3D`
  are prototypes and are not instantiated by the live game.

## Scene hierarchy

Keep the map as a separate scene and instance it beneath one 3D root. The live
2D game remains the startup scene while this prototype is developed:

```text
Main3D (Node3D)
├── CityMap3D (instance of Scenes/city_map_3d.tscn)
├── Gameplay3D (Node3D)
│   ├── Incidents (Node3D)
│   ├── Crews (Node3D)
│   └── Stations (Node3D)
├── CameraRig (Node3D)
├── Lighting (Node3D)
└── UI (CanvasLayer)
```

`CityMap3D` owns generated static map geometry. Gameplay logic stays separate
from its 3D view. Incident and crew views use `Area3D` targets on the named
`click_targets` layer (layer 7); road picking uses a static collider on that
layer. The 2D `Main` scene remains untouched while the 3D view is developed.

## Coordinate convention

Use **1 Godot unit = 1 metre**. Convert map pixels to metres using
`world_meta.px_per_m`. Cambermere Junction is the 3D origin, the ground is at
`y = 0`, map east becomes positive X, map south becomes positive Z, and height
is positive Y. The generated data does not store a named junction coordinate;
the current greybox uses the centre of the tutorial stage rectangle as the
Cambermere Junction anchor. For a map point `(px, py)` and origin `(ox, oy)`:

```text
x = (px - ox) / px_per_m
z = (py - oy) / px_per_m
y = height in metres
```

This keeps the generated data as the source of truth. The full-map ground is
positioned to match that origin; roads and area layers use small height offsets
to avoid z-fighting.

## Asset and build pipeline

1. Keep `tools/build_world.py` as the canonical map-data builder. Do not hand-edit
   generated files under `Map/world/`.
2. `Scenes/city_map_3d.tscn` loads the generated JSON and binary files and builds
   batched Godot `ArrayMesh` geometry for roads, areas, and buildings at runtime.
   This leaves the current 2D renderer intact.
3. Building heights are deterministic greybox placeholders by land-use kind;
   the source data contains footprints and kinds, not real heights.
4. Use `.glb` (glTF 2.0), metres, `+Y` up, and the vehicle front facing `-Z` for
   authored reusable models. Keep them in `Assets/3D/` and instance them from
   scenes.
5. Keep attribution and source-data metadata with the generated map outputs.

The `Main3D` scaffold and generated-map greybox remain separate from the live 2D
startup scene while the 3D view is developed.
