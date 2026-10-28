#!/usr/bin/env python3
# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Build terrain for the game world from Vicmap Elevation's metro 1 m
#    contours and spot heights (tools/cache/el_contour_1to5m.geojson and
#    el_grnd_surface_point_1to5m.geojson, fetched by fetch_vicmap.py), in the
#    same projection as build_world.py, without changing any other
#    Map/world file. Outputs:
#      (1) a height grid every CELL_M metres over the whole world (linear
#          interpolation over a triangulation of the densified contour
#          vertices, then a light Gaussian blur so 1 m contour steps don't
#          show as terraces);
#      (2) a height PROFILE for every road in roads.json (playable 'edges'
#          and 'decor'), sampled every ROAD_STEP_M along the polyline: the
#          single source of truth for road height, meant to be shared by
#          the 3D view (where vehicles are drawn) and the simulation (slope
#          speed and routing cost). Smooth each profile like a graded road
#          (cut and fill), pin both ends to the same smoothed ground height
#          so roads meeting at a junction agree, and carry the road across
#          creeks, rivers and rail lines it crosses (the contours come from
#          bare-earth lidar, so bridges are missing) by never letting the
#          road dip below a straight line across the crossing;
#      (3) the grid flattened to the road height under each road, so the
#          ground never buries a road, except on bridge spans;
#      (4) a land-cover byte per grid point (ground, park, water, large
#          site) so the 3D ground can be tinted without separate slabs.
#    Write Map/world/terrain.bin (uint16 heights in decimetres, then uint8
#    cover, row-major) and Map/world/terrain.json (grid size, scale, road
#    profiles in decimetres, credit). Print the height range, the bridges
#    found and the steepest road grade."
#
# Data: Vicmap Elevation (c) State of Victoria (Department of Transport and
# Planning), CC BY 4.0.
#
# Usage (from the project root):  python tools/build_terrain.py
# Needs numpy and scipy.

import json
import math
import os
import struct
import sys

import numpy as np
from scipy.interpolate import LinearNDInterpolator, NearestNDInterpolator
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_world import PX_PER_M, WORLD_H, WORLD_W, load, proj  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Map", "world")
CELL_M = 10.0               # height grid spacing
ROAD_STEP_M = 5.0           # road profile spacing
ROAD_SMOOTH_M = 20.0        # +- window of the graded-road moving average
ROAD_HALF_W = [4.5, 6.0, 8.0, 10.0]   # metres by road class (as the 3D view)
BRIDGE_SPAN_M = {"water": 25.0, "rail": 18.0}
SITE = 4                    # buildings.bin kinds >= 4 are flat sites


def grid_shape():
    nx = int(math.ceil(WORLD_W / PX_PER_M / CELL_M)) + 1
    ny = int(math.ceil(WORLD_H / PX_PER_M / CELL_M)) + 1
    return nx, ny


def build_grid():
    pts, zs = [], []
    for f in load("el_contour_1to5m"):
        z = f["properties"]["altitude"]
        g = f["geometry"]
        lines = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
        for line in lines:
            xy = [np.array(proj(lon, lat)) / PX_PER_M for lon, lat in line]
            for a, b in zip(xy, xy[1:]):
                n = max(1, int(np.linalg.norm(b - a) / CELL_M))
                for t in range(n):
                    pts.append(a + (b - a) * (t / n))
                    zs.append(z)
    for f in load("el_grnd_surface_point_1to5m"):
        c = f["geometry"]["coordinates"]
        c = c[0] if f["geometry"]["type"] == "MultiPoint" else c
        pts.append(np.array(proj(*c)) / PX_PER_M)
        zs.append(f["properties"]["altitude"])
    pts, zs = np.array(pts), np.array(zs, dtype=float)
    nx, ny = grid_shape()
    gx, gy = np.meshgrid(np.arange(nx) * CELL_M, np.arange(ny) * CELL_M)
    grid = LinearNDInterpolator(pts, zs)(gx, gy)
    holes = np.isnan(grid)
    if holes.any():
        grid[holes] = NearestNDInterpolator(pts, zs)(gx[holes], gy[holes])
    print(f"terrain: {len(zs)} contour/spot samples -> {nx} x {ny} grid at {CELL_M:.0f} m")
    return gaussian_filter(grid, 1.2)


def sample(grid, x_m, y_m):
    """Bilinear height at metres (x east, y south) from the grid origin."""
    ny, nx = grid.shape
    fx = min(max(x_m / CELL_M, 0.0), nx - 1.001)
    fy = min(max(y_m / CELL_M, 0.0), ny - 1.001)
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    return (grid[j, i] * (1 - tx) * (1 - ty) + grid[j, i + 1] * tx * (1 - ty)
            + grid[j + 1, i] * (1 - tx) * ty + grid[j + 1, i + 1] * tx * ty)


def anchor(grid, p_m):
    """Smoothed ground height used to pin road ends (same everywhere for one point)."""
    return float(np.mean([sample(grid, p_m[0] + dx, p_m[1] + dy)
                          for dx in (-8, 0, 8) for dy in (-8, 0, 8)]))


class SegIndex:
    CELL = 50.0

    def __init__(self):
        self.segs, self.grid = [], {}

    def add(self, pts_m, kind):
        for a, b in zip(pts_m, pts_m[1:]):
            k = len(self.segs)
            self.segs.append((a, b, kind))
            for cx in range(int(min(a[0], b[0]) // self.CELL), int(max(a[0], b[0]) // self.CELL) + 1):
                for cy in range(int(min(a[1], b[1]) // self.CELL), int(max(a[1], b[1]) // self.CELL) + 1):
                    self.grid.setdefault((cx, cy), []).append(k)

    def crossings(self, a, b):
        """[(t along a-b, kind)] where segment a-b crosses an indexed line."""
        out, seen = [], set()
        for cx in range(int(min(a[0], b[0]) // self.CELL), int(max(a[0], b[0]) // self.CELL) + 1):
            for cy in range(int(min(a[1], b[1]) // self.CELL), int(max(a[1], b[1]) // self.CELL) + 1):
                for k in self.grid.get((cx, cy), ()):
                    if k in seen:
                        continue
                    seen.add(k)
                    p, q, kind = self.segs[k]
                    r = (b[0] - a[0], b[1] - a[1])
                    s = (q[0] - p[0], q[1] - p[1])
                    den = r[0] * s[1] - r[1] * s[0]
                    if abs(den) < 1e-9:
                        continue
                    t = ((p[0] - a[0]) * s[1] - (p[1] - a[1]) * s[0]) / den
                    u = ((p[0] - a[0]) * r[1] - (p[1] - a[1]) * r[0]) / den
                    if 0 <= t <= 1 and 0 <= u <= 1:
                        out.append((t, kind))
        return out


def road_profile(grid, pts_px, crossings_index):
    """Heights every ROAD_STEP_M along a polyline, graded and bridged."""
    pts = [np.array(p) / PX_PER_M for p in pts_px]
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + float(np.linalg.norm(b - a)))
    total = cum[-1]
    n = max(2, int(math.ceil(total / ROAD_STEP_M)) + 1)
    ds = np.linspace(0.0, total, n)
    xy, seg = [], 0
    for d in ds:
        while seg < len(pts) - 2 and cum[seg + 1] < d:
            seg += 1
        span = max(cum[seg + 1] - cum[seg], 1e-9)
        xy.append(pts[seg] + (pts[seg + 1] - pts[seg]) * ((d - cum[seg]) / span))
    raw = np.array([sample(grid, p[0], p[1]) for p in xy])
    # Graded road: moving average, then pin the ends to the shared anchor.
    w = max(1, int(ROAD_SMOOTH_M / ROAD_STEP_M))
    padded = np.pad(raw, w, mode="edge")
    prof = np.convolve(padded, np.ones(2 * w + 1) / (2 * w + 1), mode="valid")
    z0, z1 = anchor(grid, pts[0]), anchor(grid, pts[-1])
    ramp = ds / total if total > 0 else ds * 0
    prof = prof + (z0 - prof[0]) * (1 - ramp) + (z1 - prof[-1]) * ramp
    # Bridges: never dip below a straight line across a crossing.
    bridged = np.zeros(n, dtype=bool)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        for t, kind in crossings_index.crossings(a, b):
            dc = cum[i] + t * (cum[i + 1] - cum[i])
            span = BRIDGE_SPAN_M[kind]
            lo = int(np.searchsorted(ds, dc - span))
            hi = min(n - 1, int(np.searchsorted(ds, dc + span)))
            if hi - lo < 2:
                continue
            line = np.linspace(prof[lo], prof[hi], hi - lo + 1)
            dip = line - prof[lo:hi + 1]
            if dip.max() > 0.5:                      # a real dip: bridge it
                prof[lo:hi + 1] = np.maximum(prof[lo:hi + 1], line)
                bridged[lo:hi + 1] = True
    return ds, np.array(xy), prof, bridged


def carve(grid, xy, prof, bridged, half_w):
    """Flatten grid points under the road to the road height (not on bridges)."""
    ny, nx = grid.shape
    r = half_w + 3.0
    for p, z, br in zip(xy, prof, bridged):
        if br:
            continue
        i0, i1 = int((p[0] - r) // CELL_M), int((p[0] + r) // CELL_M) + 1
        j0, j1 = int((p[1] - r) // CELL_M), int((p[1] + r) // CELL_M) + 1
        for j in range(max(j0, 0), min(j1, ny - 1) + 1):
            for i in range(max(i0, 0), min(i1, nx - 1) + 1):
                if math.hypot(i * CELL_M - p[0], j * CELL_M - p[1]) <= r:
                    grid[j, i] = z


def _fill_poly(cover, poly_m, value):
    ny, nx = cover.shape
    xs = [p[0] for p in poly_m]
    ys = [p[1] for p in poly_m]
    i0, i1 = max(0, int(min(xs) // CELL_M)), min(nx - 1, int(max(xs) // CELL_M) + 1)
    j0, j1 = max(0, int(min(ys) // CELL_M)), min(ny - 1, int(max(ys) // CELL_M) + 1)
    if i1 < i0 or j1 < j0:
        return
    gx, gy = np.meshgrid(np.arange(i0, i1 + 1) * CELL_M, np.arange(j0, j1 + 1) * CELL_M)
    inside = np.zeros(gx.shape, dtype=bool)
    n = len(poly_m)
    for k in range(n):
        x1, y1 = poly_m[k]
        x2, y2 = poly_m[(k + 1) % n]
        if y1 == y2:
            continue
        cond = (y1 > gy) != (y2 > gy)
        xcross = x1 + (gy - y1) * (x2 - x1) / (y2 - y1)
        inside ^= cond & (gx < xcross)
    sub = cover[j0:j1 + 1, i0:i1 + 1]
    sub[inside] = value


def build_cover(shape):
    cover = np.zeros(shape, dtype=np.uint8)
    areas = json.load(open(os.path.join(OUT, "areas.json")))
    blob = open(os.path.join(OUT, "buildings.bin"), "rb").read()
    i = 0
    while i + 3 <= len(blob):
        kind = blob[i]
        n = struct.unpack_from("<H", blob, i + 1)[0]
        i += 3
        v = struct.unpack_from(f"<{n * 6}h", blob, i)
        i += n * 12
        if kind >= SITE:
            for t in range(n):
                _fill_poly(cover, [(v[t * 6 + 2 * k] / PX_PER_M, v[t * 6 + 2 * k + 1] / PX_PER_M)
                                   for k in range(3)], 3)
    for poly in areas["parks"]:
        _fill_poly(cover, [(x / PX_PER_M, y / PX_PER_M) for x, y in poly], 1)
    for poly in areas["water"]:
        _fill_poly(cover, [(x / PX_PER_M, y / PX_PER_M) for x, y in poly], 2)
    return cover


def main():
    grid = build_grid()
    areas = json.load(open(os.path.join(OUT, "areas.json")))
    roads = json.load(open(os.path.join(OUT, "roads.json")))
    crossings = SegIndex()
    for w in areas["waterways"]:
        crossings.add([(x / PX_PER_M, y / PX_PER_M) for x, y in w["pts"]], "water")
    for line in areas["rail"]:
        pts = line["pts"] if isinstance(line, dict) else line
        crossings.add([(x / PX_PER_M, y / PX_PER_M) for x, y in pts], "rail")

    profiles = {"edges": [], "decor": []}
    carves, n_bridges, steepest = [], 0, 0.0
    ground = grid.copy()                       # profiles read the uncarved ground
    for key in ("edges", "decor"):
        for e in roads[key]:
            ds, xy, prof, bridged = road_profile(ground, e["pts"], crossings)
            profiles[key].append([int(round(z * 10)) for z in prof])
            carves.append((xy, prof, bridged, ROAD_HALF_W[min(3, int(e["c"]))]))
            n_bridges += int(np.any(bridged))
            if len(prof) > 2:
                grade = np.abs(np.diff(prof)) / np.maximum(np.diff(ds), 1e-6)
                steepest = max(steepest, float(grade.max()))
    # Carve smaller roads first so bigger roads win where they meet.
    for xy, prof, bridged, half_w in sorted(carves, key=lambda c: c[3]):
        carve(grid, xy, prof, bridged, half_w)

    cover = build_cover(grid.shape)
    ny, nx = grid.shape
    zmin, zmax = float(grid.min()), float(grid.max())
    with open(os.path.join(OUT, "terrain.bin"), "wb") as f:
        f.write(np.clip(np.round(grid * 10), 0, 65535).astype("<u2").tobytes())
        f.write(cover.tobytes())
    with open(os.path.join(OUT, "terrain.json"), "w", encoding="utf-8") as f:
        json.dump({
            "credit": "Terrain: Vicmap Elevation (c) State of Victoria (Department of Transport and Planning), "
                      "CC BY 4.0. Modified: interpolated to a grid, smoothed, flattened under roads.",
            "licence_url": "https://creativecommons.org/licenses/by/4.0/",
            "format": "terrain.bin: nx*ny uint16 heights (decimetres, row-major, y south), then nx*ny uint8 "
                      "cover (0 ground, 1 park, 2 water, 3 site). Grid point (i, j) is at map px "
                      "(i, j) * cell_m * px_per_m. Road profiles: decimetres every road_step_m along each "
                      "roads.json polyline, same order as 'edges' and 'decor'.",
            "cell_m": CELL_M, "nx": nx, "ny": ny, "z_scale": 0.1, "px_per_m": PX_PER_M,
            "z_min": round(zmin, 1), "z_max": round(zmax, 1), "road_step_m": ROAD_STEP_M,
            "roads": profiles,
        }, f, separators=(",", ":"))
    print(f"terrain: heights {zmin:.1f}-{zmax:.1f} m, {n_bridges} roads with bridged crossings, "
          f"steepest graded road {100 * steepest:.0f}%; wrote terrain.bin "
          f"({os.path.getsize(os.path.join(OUT, 'terrain.bin')) / 1e6:.1f} MB) and terrain.json "
          f"({os.path.getsize(os.path.join(OUT, 'terrain.json')) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
