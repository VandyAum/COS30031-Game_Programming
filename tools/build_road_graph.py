#!/usr/bin/env python3
# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Our three map chunk SVGs (Camberwell, Hawthorn East, Surrey Hills) were
#    exported from OpenStreetMap and contain a <g id="road-fills"> group where
#    every road is a polyline path ('M x y L x y ...') and stroke-width encodes
#    the road class (8 = residential, 11-14 = collector, 17-19 = arterial).
#    Write an offline Python script (standard library only) that:
#      1. Reads each SVG and converts its road polylines into one shared world
#         coordinate frame (Camberwell's pixel frame; Hawthorn East sits at
#         x offset -927.455 and Surrey Hills at +2109, as stated in the SVG
#         metadata comments).
#      2. Avoids duplicating roads where chunks overlap by giving each chunk
#         ownership of an x-range and keeping only segments whose midpoint
#         falls in that range and inside the 0-1900 map height.
#      3. Snaps vertices to a small grid so shared OSM nodes become shared
#         graph nodes (intersections), and welds loose road ends across the
#         chunk seams so the three chunks join up.
#      4. Collapses chains of degree-2 vertices so graph nodes are only
#         intersections/dead ends, and each edge keeps its full polyline,
#         its pixel length and its road width class.
#      5. Drops small disconnected fragments (roads clipped at the map edge)
#         so every remaining node is reachable from every other.
#      6. Respects the team's greybox: each chunk scene (.tscn) has grey
#         Polygon2D 'covers' under MapCover hiding every street that is not
#         part of the playable network. Read those polygons from the scenes
#         and drop any road segment that is mostly hidden under a cover
#         (small tolerance at the cover edges), so the graph matches exactly
#         the white roads the player can see. Re-run after editing covers.
#         Then prune the short dead-end stubs this leaves behind (the first
#         few pixels of side streets poking out from under a cover).
#      7. Writes Map/road_graph.json for Godot to load at runtime.
#    Print a short summary (node/edge counts, connected components) so we can
#    sanity-check the result."
#
# Usage (from the project root):  python3 tools/build_road_graph.py

import json
import math
import os
import re
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP_DIR = os.path.join(ROOT, "Map")
OUT_PATH = os.path.join(MAP_DIR, "road_graph.json")

MAP_HEIGHT = 1900.0
SNAP = 1.0          # px grid used to merge identical OSM vertices
SEAM_WELD = 8.0     # px radius for joining dead ends across chunk seams
STUB_LEN = 30.0     # px: dead-end spurs shorter than this are removed

COVER_EDGE_TOLERANCE = 4.0  # px: points this close to a cover edge count as visible

# (svg file, chunk scene, x offset into world frame, owned world x-range)
# Offsets must match the chunk positions under MapChunk in main.tscn.
CHUNKS = [
    ("hawthorn_east_extension_aligned.svg", "hawthorn_east_map.tscn", -927.455, (-1e9, 0.0)),
    ("camberwell_game_map_roadclean.svg", "CamberwellMap.tscn", 0.0, (0.0, 2130.0)),
    ("surrey_hills_camberwell_extension_only.svg", "surrey_hill_Map.tscn", 2109.0, (2130.0, 1e9)),
]
SEAMS_X = [0.0, 2130.0]


def read_road_paths(svg_path):
    text = open(svg_path, encoding="utf-8").read()
    group = re.search(r'<g id="road-fills"[^>]*>(.*?)</g>', text, re.S)
    if not group:
        return []
    roads = []
    for tag in re.findall(r"<path[^>]*>", group.group(1)):
        d = re.search(r'd="([^"]+)"', tag)
        w = re.search(r'stroke-width="([\d.]+)"', tag)
        if not d:
            continue
        nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d.group(1))]
        pts = list(zip(nums[0::2], nums[1::2]))
        if len(pts) >= 2:
            roads.append((pts, float(w.group(1)) if w else 8.0))
    return roads


def read_covers(tscn_path, offset):
    """Grey cover polygons (MapCover children except 'Base') in world coords."""
    text = open(tscn_path, encoding="utf-8").read()
    covers = []
    for block in re.split(r"\n(?=\[)", text):
        if 'parent="MapCover"' not in block or 'name="Base"' in block:
            continue
        m = re.search(r"polygon = PackedVector2Array\(([^)]*)\)", block)
        if not m:
            continue
        nums = [float(n) for n in m.group(1).split(",")]
        covers.append([(x + offset, y) for x, y in zip(nums[0::2], nums[1::2])])
    return covers


def point_in_polygon(p, poly):
    x, y = p
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def dist_to_polygon_edge(p, poly):
    best = math.inf
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        ab = (b[0] - a[0], b[1] - a[1])
        l2 = ab[0] ** 2 + ab[1] ** 2
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / l2))
        best = min(best, math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t)))
    return best


def is_hidden(p, covers):
    for poly in covers:
        if point_in_polygon(p, poly) and dist_to_polygon_edge(p, poly) > COVER_EDGE_TOLERANCE:
            return True
    return False


def segment_mostly_hidden(a, b, covers):
    samples = max(2, int(math.dist(a, b) // 6) + 1)
    hidden = 0
    for i in range(samples):
        t = i / (samples - 1)
        if is_hidden((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), covers):
            hidden += 1
    return hidden * 2 > samples


def key(p):
    return (round(p[0] / SNAP), round(p[1] / SNAP))


def main():
    # vertex key -> position, adjacency as (neighbour key -> width)
    pos = {}
    adj = defaultdict(dict)

    covers = []
    for _, scene, offset, _ in CHUNKS:
        covers += read_covers(os.path.join(ROOT, scene), offset)

    hidden_segments = 0
    for fname, _, offset, (xmin, xmax) in CHUNKS:
        for pts, width in read_road_paths(os.path.join(MAP_DIR, fname)):
            world = [(x + offset, y) for x, y in pts]
            for a, b in zip(world, world[1:]):
                mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
                if not (xmin <= mx < xmax and 0 <= my <= MAP_HEIGHT):
                    continue
                ka, kb = key(a), key(b)
                if ka == kb:
                    continue
                if segment_mostly_hidden(a, b, covers):
                    hidden_segments += 1
                    continue
                pos.setdefault(ka, a)
                pos.setdefault(kb, b)
                adj[ka][kb] = max(width, adj[ka].get(kb, 0))
                adj[kb][ka] = max(width, adj[kb].get(ka, 0))

    # Weld dead ends that sit near a chunk seam to the nearest vertex on the
    # other side of that seam.
    welded = 0
    for k in list(adj.keys()):
        if k not in adj or len(adj[k]) != 1:
            continue
        p = pos[k]
        if min(abs(p[0] - s) for s in SEAMS_X) > SEAM_WELD * 2:
            continue
        best, best_d = None, SEAM_WELD
        for k2, p2 in pos.items():
            if k2 == k or k2 not in adj or k2 in adj[k]:
                continue
            d = math.dist(p, p2)
            if d < best_d:
                best, best_d = k2, d
        if best is not None:
            for nb, w in adj.pop(k).items():
                del adj[nb][k]
                if nb != best:
                    adj[best][nb] = w
                    adj[nb][best] = w
            welded += 1

    # Prune short dead-end stubs (repeat, since removing one can expose another).
    stubs = 0
    changed = True
    while changed:
        changed = False
        for k in list(adj.keys()):
            if k not in adj or len(adj[k]) != 1:
                continue
            chain, length, prev, cur = [k], 0.0, None, k
            while len(adj[cur]) <= 2:
                nxt = [n for n in adj[cur] if n != prev]
                if not nxt:
                    break
                length += math.dist(pos[cur], pos[nxt[0]])
                prev, cur = cur, nxt[0]
                if len(adj[cur]) != 2:
                    break
                chain.append(cur)
            if length < STUB_LEN and len(adj.get(cur, {})) >= 3:
                for c in chain:
                    for nb in adj.pop(c):
                        if nb in adj:
                            adj[nb].pop(c, None)
                stubs += 1
                changed = True

    # Graph nodes are every vertex that is not a simple pass-through.
    is_node = {k for k, nbs in adj.items() if len(nbs) != 2}
    node_index = {}
    nodes = []

    def node_id(k):
        if k not in node_index:
            node_index[k] = len(nodes)
            nodes.append([round(pos[k][0], 2), round(pos[k][1], 2)])
        return node_index[k]

    edges = []
    visited = set()

    def walk(start, nxt):
        chain = [start, nxt]
        width = adj[start][nxt]
        prev, cur = start, nxt
        while cur not in is_node:
            a, b = adj[cur].keys()
            step = b if a == prev else a
            width = max(width, adj[cur][step])
            prev, cur = cur, step
            chain.append(cur)
            if cur == start:  # closed loop with no junction
                break
        return chain, width

    for k in list(adj.keys()):
        if k not in is_node:
            continue
        for nb in adj[k]:
            if (k, nb) in visited:
                continue
            chain, width = walk(k, nb)
            for a, b in zip(chain, chain[1:]):
                visited.add((a, b))
                visited.add((b, a))
            pts = [pos[c] for c in chain]
            length = sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
            edges.append({
                "a": node_id(chain[0]),
                "b": node_id(chain[-1]),
                "w": width,
                "len": round(length, 1),
                "pts": [[round(x, 1), round(y, 1)] for x, y in pts],
            })

    # Connected components (for the summary only)
    parent = list(range(len(nodes)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for e in edges:
        parent[find(e["a"])] = find(e["b"])
    sizes = defaultdict(int)
    for i in range(len(nodes)):
        sizes[find(i)] += 1
    comps = sorted(sizes.values(), reverse=True)

    # Keep only the largest component and renumber nodes.
    main_root = max(sizes, key=sizes.get)
    remap = {}
    kept_nodes = []
    for i, n in enumerate(nodes):
        if find(i) == main_root:
            remap[i] = len(kept_nodes)
            kept_nodes.append(n)
    edges = [dict(e, a=remap[e["a"]], b=remap[e["b"]]) for e in edges if e["a"] in remap]
    nodes = kept_nodes

    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump({
            "source": "OSM road-fills from Map/*.svg via tools/build_road_graph.py",
            "frame": "Camberwell chunk pixels (MapChunk/Camberwell at 0,0)",
            "nodes": nodes,
            "edges": edges,
        }, f, separators=(",", ":"))

    print(f"covers={len(covers)} hidden_segments_dropped={hidden_segments} stubs_pruned={stubs}")
    print(f"nodes={len(nodes)} edges={len(edges)} seam_welds={welded}")
    print(f"components={len(comps)} largest={comps[:5]} (kept largest only)")
    print(f"wrote {os.path.relpath(OUT_PATH, ROOT)} ({os.path.getsize(OUT_PATH)//1024} KB)")


if __name__ == "__main__":
    main()
