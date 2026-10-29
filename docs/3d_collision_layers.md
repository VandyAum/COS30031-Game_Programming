# 3D Collision Layers and Masks

This is the shared collision-layer plan for the 3D city port. The existing 2D
layers remain unchanged. A collision layer identifies what an object is; a
collision mask identifies which layers it checks for collisions or overlap.

## Layer assignments

| 3D layer | Bit value | Name | Typical objects |
| --- | ---: | --- | --- |
| 1 | 1 | World | Ground and city surface |
| 2 | 2 | Barriers | Buildings and solid obstacles |
| 3 | 4 | Vehicles | Crew vehicle collision bodies |
| 4 | 8 | Debris | Rigid-body debris |
| 5 | 16 | Incident Zones | Areas that crews can respond to |
| 6 | 32 | Crew Sensors | Areas attached to crews to detect incidents |
| 7 | 64 | Click Targets | Pickable objects for the mouse raycast |

## Initial masks

| Object | Collision layer | Collision mask | Reason |
| --- | ---: | ---: | --- |
| Ground / world | 1 | 0 | Static surface; other bodies include World in their masks |
| Barrier | 2 | 0 | Static obstacle; vehicles and debris include Barriers in their masks |
| Crew vehicle | 4 | 11 (World + Barriers + Debris) | Moves on the city and reacts to obstacles and debris |
| Debris | 8 | 15 (World + Barriers + Vehicles + Debris) | Rigid debris rests on the world and interacts with obstacles, vehicles, and other debris |
| Incident zone | 16 | 0 | Detectable area; it does not need to scan for other bodies |
| Crew sensor | 32 | 16 (Incident Zones) | Detects incident areas only |
| Click target | 64 | 0 | Selection-only collider; it does not participate in physical collisions |

The mouse ray query should use mask **64** so it only hits Click Targets. Click
target colliders should be placed on layer 7 even when their visible model is
on another layer. Keep the click target shape separate from the physical body
when its selection bounds need to differ from its collision bounds.

These names are configured in Project Settings under **Layer Names > 3D
Physics**. Assign the object layers and masks when the corresponding 3D
collision nodes are added to scenes. The current project has no 3D physics
nodes yet, so this document records the initial matrix for the 3D port.
