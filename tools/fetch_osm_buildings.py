#!/usr/bin/env python3
# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Prototype OpenStreetMap buildings as a second building source for the
#    greybox 3D city, to compare with the Vicmap parcel boxes. Write a
#    standard-library Python tool (certifi only if installed, because this
#    machine's certificate store is out of date) that downloads every OSM
#    building in build_world.FETCH_BOUNDS from the Overpass API in ONE
#    request (ways and multipolygon relations, tags and geometry), caches the
#    raw answer in tools/cache/osm_buildings_raw.json (git-ignored) so
#    reruns don't hit the public server again, and writes
#    Map/world/osm_buildings.json in the same game-pixel projection as
#    build_world.py (build_world.proj, simplify, rr). Keep only outlines
#    whose centre is inside the stage 3 rectangle. Per building store a
#    land-use kind matching buildings.bin (0 residential, 1 commercial,
#    2 public, 3 industrial), a height in metres and whether that height
#    came from the data: 'height' tag first, else building:levels (plus half
#    of roof:levels) at 3 m a storey plus 1 m, else an estimate from the
#    building type and footprint area. Use only the outer ring of
#    multipolygons (stitch outer ways that are split), skip building:part,
#    and do NOT store names or any other tags, so the fictional-names rule
#    still holds. Print counts of tagged vs estimated heights."
# Follow-up prompt (match Vicmap colours, stepped buildings, calibrated
#    estimates): "(1) Colour OSM buildings like the Vicmap boxes: take the
#    kind from the Vicmap planning zone under the building (build_world's
#    zone_kind / ZoneIndex on tools/cache/plan_zone.geojson), falling back
#    to the OSM building type only on park / road / unzoned land. (2) Also
#    download building:part ways. Where a building has parts, draw the parts
#    at their own heights (height / building:levels, from min_height /
#    building:min_level) and keep the outline only as a podium just under
#    the lowest part, so stepped buildings like the 14-storey apartment
#    block near the junction are not one solid 50 m slab. Store a base
#    height per record: [kind, base m, top m, from data 0/1, x0, y0, ...].
#    (3) Estimate untagged heights with the same storey rules as the Vicmap
#    boxes in city_3d.gd (measured from tagged OSM buildings: houses 1 or 2
#    storeys with two storeys likelier on bigger footprints, shops mostly
#    two), picked with a stable hash of the OSM id."
#
# Data: (c) OpenStreetMap contributors, ODbL 1.0
# (https://www.openstreetmap.org/copyright). The output file is a derived
# database, so it is also under ODbL; see ATTRIBUTIONS.md.
#
# Usage (from the project root):  python tools/fetch_osm_buildings.py [--force]
#   --force  download again instead of using the cached raw answer
# Needs tools/cache/plan_zone.geojson (python tools/fetch_vicmap.py) for colours.

import hashlib
import json
import os
import ssl
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_world import (FETCH_BOUNDS, JUNCTION, KIND_COMMERCIAL, KIND_INDUSTRIAL,  # noqa: E402
                         KIND_PUBLIC, KIND_RESIDENTIAL, PX_PER_M, STAGE_RECTS,
                         ZoneIndex, load, point_in_poly, proj, rings, rr,
                         signed_area, simplify, zone_kind)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "cache", "osm_buildings_raw.json")
OUT = os.path.join(ROOT, "Map", "world", "osm_buildings.json")
OVERPASS = "https://overpass-api.de/api/interpreter"

STOREY_M = 3.0
ROOF_M = 1.0
# OSM building=* values, used only where the planning zone gives no kind.
COMMERCIAL = {"commercial", "retail", "office", "supermarket", "hotel", "kiosk"}
PUBLIC = {"school", "university", "college", "kindergarten", "hospital", "church",
          "chapel", "cathedral", "public", "civic", "government", "fire_station",
          "train_station", "transportation", "library", "sports_centre", "pavilion",
          "sports_hall", "community_centre", "museum", "townhall"}
INDUSTRIAL = {"industrial", "warehouse", "factory", "manufacture", "service", "depot"}
SMALL = {"garage", "garages", "shed", "carport", "roof", "hut", "cabin", "greenhouse",
         "boathouse", "toilets", "bunker"}


def _ssl_context():
    try:
        import certifi  # not stdlib; fixes stale Windows/Python certificate stores
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def download():
    min_lon, min_lat, max_lon, max_lat = FETCH_BOUNDS
    bbox = f"{min_lat},{min_lon},{max_lat},{max_lon}"
    query = (f'[out:json][timeout:240];'
             f'(way["building"]({bbox});relation["building"]["type"="multipolygon"]({bbox});'
             f'way["building:part"]({bbox}););'
             f'out tags geom;')
    data = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request(OVERPASS, data=data,
                                 headers={"User-Agent": "COS30031 student game prototype (map extrusion)"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=300, context=_ssl_context()) as resp:
                return json.load(resp)
        except Exception as exc:  # busy server: back off politely
            print(f"  retry {attempt + 1} ({exc})")
            time.sleep(15 * (attempt + 1))
    raise RuntimeError("Overpass download failed")


def _num(text):
    """'12', '12.5 m', '12;14' -> 12.0; None if not a number."""
    if not text:
        return None
    try:
        return float(str(text).split(";")[0].replace("m", "").strip())
    except ValueError:
        return None


def _hash01(key):
    return int(hashlib.md5(str(key).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def tag_kind(tags):
    b = tags.get("building", tags.get("building:part", "yes"))
    if b in COMMERCIAL or "shop" in tags:
        return KIND_COMMERCIAL
    if b in PUBLIC or tags.get("amenity") in {"school", "place_of_worship", "hospital", "library",
                                               "community_centre", "kindergarten", "fire_station",
                                               "police", "townhall"}:
        return KIND_PUBLIC
    if b in INDUSTRIAL:
        return KIND_INDUSTRIAL
    return KIND_RESIDENTIAL


def tagged_top(tags):
    """Top height in metres from the tags, or None."""
    h = _num(tags.get("height"))
    if h and h > 1.0:
        return h
    levels = _num(tags.get("building:levels"))
    if levels and levels > 0:
        return (levels + (_num(tags.get("roof:levels")) or 0.0) * 0.5) * STOREY_M + ROOF_M
    return None


def tagged_base(tags):
    h = _num(tags.get("min_height"))
    if h is not None:
        return h
    lv = _num(tags.get("building:min_level"))
    return lv * STOREY_M if lv else 0.0


def estimate_top(tags, kind, area_m2, key, dist_m):
    """Same storey rules as the Vicmap boxes (Script/city_3d.gd _height_for)."""
    h, jitter = _hash01(key), _hash01(f"{key}j") * 0.8
    if tags.get("building") in SMALL:
        return 3.0
    if tags.get("building") in {"apartments", "flats"}:
        return 3 * STOREY_M + ROOF_M + jitter
    if kind == KIND_RESIDENTIAL:
        p2 = 0.30 if area_m2 < 200 else (0.41 if area_m2 < 300 else 0.48)
        if dist_m < 300:
            p2 = 0.66
        return (7.0 if h < p2 else 4.0) + jitter
    if kind == KIND_COMMERCIAL:
        return (4.5 if h < 0.33 else 8.0) + jitter
    if kind == KIND_PUBLIC:
        return 7.0 + h * 3.0
    return 6.0 + h * 3.0


def _stitch(ways):
    """Join open outer ways end to end into closed rings."""
    ways = [w[:] for w in ways if len(w) >= 2]
    out = []
    while ways:
        ring = ways.pop(0)
        changed = True
        while ring[0] != ring[-1] and changed:
            changed = False
            for i, w in enumerate(ways):
                if w[0] == ring[-1]:
                    ring += w[1:]
                elif w[-1] == ring[-1]:
                    ring += w[-2::-1]
                elif w[-1] == ring[0]:
                    ring = w[:-1] + ring
                elif w[0] == ring[0]:
                    ring = w[:0:-1] + ring
                else:
                    continue
                ways.pop(i)
                changed = True
                break
        if ring[0] == ring[-1] and len(ring) >= 4:
            out.append(ring)
    return out


def outer_rings(el):
    if el["type"] == "way":
        g = [(p["lon"], p["lat"]) for p in el.get("geometry", [])]
        return [g] if len(g) >= 4 and g[0] == g[-1] else []
    outers = [[(p["lon"], p["lat"]) for p in m.get("geometry", [])]
              for m in el.get("members", []) if m.get("role") == "outer" and m.get("type") == "way"]
    return _stitch(outers)


def _shape(ring):
    """Projected, simplified open polygon with its centre and area (m2), or None."""
    pts = simplify([proj(lon, lat) for lon, lat in ring][:-1], 0.4)
    if len(pts) < 3:
        return None
    area_m2 = abs(signed_area(pts)) / (PX_PER_M * PX_PER_M)
    if area_m2 < 4.0:
        return None
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return pts, (cx, cy), area_m2


def main():
    force = "--force" in sys.argv
    if force or not os.path.exists(RAW):
        print("Downloading OSM buildings and building parts from Overpass (one request)...")
        raw = download()
        os.makedirs(os.path.dirname(RAW), exist_ok=True)
        with open(RAW, "w", encoding="utf-8") as f:
            json.dump(raw, f)
    else:
        with open(RAW, encoding="utf-8") as f:
            raw = json.load(f)

    zones = ZoneIndex([(r, zone_kind(z["properties"]["zone_code"]))
                       for z in load("plan_zone") for r in rings(z["geometry"])])
    jx, jy = proj(*JUNCTION)

    x0, y0, x1, y1 = STAGE_RECTS[3]
    buildings, parts = [], []
    for el in raw["elements"]:
        tags = el.get("tags", {})
        is_part = "building:part" in tags and "building" not in tags
        if not is_part and tags.get("building") in (None, "no", "construction", "proposed", "demolished"):
            continue
        for ring in outer_rings(el):
            s = _shape(ring)
            if s is None:
                continue
            pts, (cx, cy), area_m2 = s
            if not (x0 <= cx <= x1 and y0 <= cy <= y1):
                continue
            zk = zones.kind_at(cx, cy)
            kind = zk if zk in (KIND_RESIDENTIAL, KIND_COMMERCIAL, KIND_PUBLIC, KIND_INDUSTRIAL) \
                and tags.get("building") not in PUBLIC else tag_kind(tags)
            rec = {"id": f"{el['type']}{el['id']}", "pts": pts, "c": (cx, cy), "area": area_m2,
                   "kind": kind, "tags": tags, "base": tagged_base(tags), "top": tagged_top(tags)}
            (parts if is_part else buildings).append(rec)

    # Attach parts to the building they stand in.
    for p in parts:
        for b in buildings:
            bx = [q[0] for q in b["pts"]]
            by = [q[1] for q in b["pts"]]
            if min(bx) <= p["c"][0] <= max(bx) and min(by) <= p["c"][1] <= max(by) \
                    and point_in_poly(p["c"][0], p["c"][1], b["pts"]):
                b.setdefault("parts", []).append(p)
                break

    out, tagged, estimated, n_parts = [], 0, 0, 0

    def emit(rec, kind, base, top, from_data):
        out.append([kind, round(base, 1), round(top, 1), 1 if from_data else 0]
                   + [c for q in rr(rec["pts"]) for c in q])

    for b in buildings:
        dist_m = ((b["c"][0] - jx) ** 2 + (b["c"][1] - jy) ** 2) ** 0.5 / PX_PER_M
        top = b["top"]
        from_data = top is not None
        if top is None:
            top = estimate_top(b["tags"], b["kind"], b["area"], b["id"], dist_m)
        tagged += from_data
        estimated += not from_data
        ps = b.get("parts", [])
        if not ps:
            emit(b, b["kind"], 0.0, top, from_data)
            continue
        part_tops = []
        for p in ps:
            ptop = p["top"] if p["top"] is not None else top
            if ptop > p["base"] + 0.5:
                emit(p, b["kind"], p["base"], ptop, p["top"] is not None)
                part_tops.append(ptop)
                n_parts += 1
        # The outline becomes a podium just under the lowest part (fills gaps
        # between parts without poking through their roofs).
        podium = min(part_tops) - 0.3 if part_tops else top
        emit(b, b["kind"], 0.0, max(podium, 3.0), from_data)

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "credit": "Buildings (c) OpenStreetMap contributors, ODbL 1.0",
            "licence_url": "https://opendatacommons.org/licenses/odbl/1-0/",
            "retrieved": time.strftime("%Y-%m-%d", time.gmtime(os.path.getmtime(RAW))),
            "format": "each record: [kind 0-3 (from the Vicmap planning zone), base m, top m, "
                      "height from data 0/1, x0, y0, x1, y1, ...] in map px",
            "buildings": out,
        }, f, separators=(",", ":"))
    n = tagged + estimated
    print(f"OSM buildings: {n} ({tagged} heights from data = {100 * tagged / max(n, 1):.0f}%, "
          f"{estimated} estimated), {n_parts} building parts drawn; wrote {os.path.relpath(OUT, ROOT)} "
          f"({os.path.getsize(OUT) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
