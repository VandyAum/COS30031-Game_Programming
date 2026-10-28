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
#
# Data: (c) OpenStreetMap contributors, ODbL 1.0
# (https://www.openstreetmap.org/copyright). The output file is a derived
# database, so it is also under ODbL; see ATTRIBUTIONS.md.
#
# Usage (from the project root):  python tools/fetch_osm_buildings.py [--force]
#   --force  download again instead of using the cached raw answer

import json
import math
import os
import ssl
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_world import (FETCH_BOUNDS, PX_PER_M, STAGE_RECTS, proj,  # noqa: E402
                         rr, signed_area, simplify)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "cache", "osm_buildings_raw.json")
OUT = os.path.join(ROOT, "Map", "world", "osm_buildings.json")
OVERPASS = "https://overpass-api.de/api/interpreter"

STOREY_M = 3.0
# OSM building=* values folded into our four land-use kinds.
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
             f'(way["building"]({bbox});relation["building"]["type"="multipolygon"]({bbox}););'
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


def kind_of(tags):
    b = tags.get("building", "yes")
    if b in COMMERCIAL or "shop" in tags:
        return 1
    if b in PUBLIC or tags.get("amenity") in {"school", "place_of_worship", "hospital", "library",
                                               "community_centre", "kindergarten", "fire_station",
                                               "police", "townhall"}:
        return 2
    if b in INDUSTRIAL:
        return 3
    return 0


def height_of(tags, area_m2):
    """(metres, True if it came from the data)."""
    h = _num(tags.get("height"))
    if h and h > 1.0:
        return h, True
    levels = _num(tags.get("building:levels"))
    if levels and levels > 0:
        roof = _num(tags.get("roof:levels")) or 0.0
        return (levels + roof * 0.5) * STOREY_M + 1.0, True
    b = tags.get("building", "yes")
    if b in SMALL:
        return 3.0, False
    if b in {"apartments", "flats"}:
        return 3 * STOREY_M + 1.0, False
    if kind_of(tags) == 2 or area_m2 > 1500:
        return 2 * STOREY_M + 2.0, False
    if kind_of(tags) in (1, 3):
        return 2 * STOREY_M + 1.0, False
    return (STOREY_M + 1.5) if area_m2 < 300 else (2 * STOREY_M + 1.0), False


def _stitch(ways):
    """Join open outer ways end to end into closed rings."""
    ways = [w[:] for w in ways if len(w) >= 2]
    rings = []
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
            rings.append(ring)
    return rings


def outer_rings(el):
    if el["type"] == "way":
        g = [(p["lon"], p["lat"]) for p in el.get("geometry", [])]
        return [g] if len(g) >= 4 and g[0] == g[-1] else []
    outers = [[(p["lon"], p["lat"]) for p in m.get("geometry", [])]
              for m in el.get("members", []) if m.get("role") == "outer" and m.get("type") == "way"]
    return _stitch(outers)


def main():
    force = "--force" in sys.argv
    if force or not os.path.exists(RAW):
        print("Downloading OSM buildings from Overpass (one request)...")
        raw = download()
        os.makedirs(os.path.dirname(RAW), exist_ok=True)
        with open(RAW, "w", encoding="utf-8") as f:
            json.dump(raw, f)
    else:
        with open(RAW, encoding="utf-8") as f:
            raw = json.load(f)

    x0, y0, x1, y1 = STAGE_RECTS[3]
    out, tagged, estimated, skipped = [], 0, 0, 0
    for el in raw["elements"]:
        tags = el.get("tags", {})
        if tags.get("building") in (None, "no", "construction", "proposed", "demolished"):
            continue
        for ring in outer_rings(el):
            pts = simplify([proj(lon, lat) for lon, lat in ring][:-1], 0.4)
            if len(pts) < 3:
                skipped += 1
                continue
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            if not (x0 <= cx <= x1 and y0 <= cy <= y1):
                continue
            area_m2 = abs(signed_area(pts)) / (PX_PER_M * PX_PER_M)
            if area_m2 < 4.0:
                skipped += 1
                continue
            h, from_data = height_of(tags, area_m2)
            tagged += from_data
            estimated += not from_data
            flat = [c for p in rr(pts) for c in p]
            out.append([kind_of(tags), round(h, 1), 1 if from_data else 0] + flat)

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({
            "credit": "Buildings (c) OpenStreetMap contributors, ODbL 1.0",
            "licence_url": "https://opendatacommons.org/licenses/odbl/1-0/",
            "retrieved": time.strftime("%Y-%m-%d", time.gmtime(os.path.getmtime(RAW))),
            "format": "each building: [kind 0-3, height m, height from data 0/1, x0, y0, x1, y1, ...] in map px",
            "buildings": out,
        }, f, separators=(",", ":"))
    n = len(out)
    print(f"OSM buildings: {n} kept ({tagged} heights from data = {100 * tagged / max(n, 1):.0f}%, "
          f"{estimated} estimated), {skipped} skipped; wrote {os.path.relpath(OUT, ROOT)} "
          f"({os.path.getsize(OUT) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
