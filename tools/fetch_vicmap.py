#!/usr/bin/env python3
# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a standard-library Python script that downloads the Vicmap open
#    datasets our Boroondara dispatch game needs from the Victorian Government
#    open data WFS (https://opendata.maps.vic.gov.au/geoserver/wfs) as GeoJSON
#    in GDA94 lon/lat (EPSG:4283), clipped to a bounding box around the City of
#    Boroondara with a small margin. Layers: the Boroondara LGA boundary,
#    suburb (locality) boundaries, the Vicmap Transport road network (tr_road,
#    with names, class, direction and from/to node ids), rail and tram lines,
#    land parcels (parcel_view, geometry only, for building boxes), Vicmap
#    building footprints, planning zones (for land-use colours), parks/reserves
#    and waterways (watercourse lines + water area polygons for the Yarra).
#    Page through results with startIndex/count sorted by a stable key so large
#    layers like parcels download completely, only request the attributes we
#    use to keep files small, skip layers already downloaded unless --force,
#    and save each layer to tools/cache/<layer>.geojson (git-ignored; the
#    processed game data is built from these by build_world.py)."
#
# Follow-up prompt: "Stages are now rectangles and stage 3 reaches past the
#    council boundary, so take the download box from build_world.FETCH_BOUNDS
#    (stage 3 + margin) instead of hard-coding Boroondara's extent, and drop
#    the council boundary layer, which is no longer used."
# Follow-up prompt: "Also fetch railway station locations (tr_rail_infrastructure,
#    rail_station points) and every emergency facility from the full Vicmap
#    FOI point layer (foi_point), which has more police/ambulance/fire
#    stations than the unit's FOI extract."
#
# Data: Vicmap (c) State of Victoria (Department of Transport and Planning);
# PARKRES (c) State of Victoria (DEECA). Licensed CC BY 4.0.
# See Map/world/ATTRIBUTION.md.
#
# Usage (from the project root):  python3 tools/fetch_vicmap.py [--force]

import json
import os
import sys
import time
import urllib.parse
import urllib.request

WFS = "https://opendata.maps.vic.gov.au/geoserver/wfs"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "cache")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_world import FETCH_BOUNDS  # noqa: E402  (stage 3 rectangle + margin)

MIN_LON, MIN_LAT, MAX_LON, MAX_LAT = FETCH_BOUNDS
PAGE = 5000

# layer -> (attributes to request (None = all), sort key, extra CQL filter)
LAYERS = {
    "locality_polygon": (["locality_name", "geom"], "ufi", None),
    "tr_road": ([
        "ufi", "ezi_road_name_label", "class_code", "direction_code",
        "feature_type_code", "road_status", "vehicular_access",
        "from_ufi", "to_ufi", "geom"], "ufi", None),
    "tr_rail": (["ufi", "feature_type_code", "geom"], "ufi", None),
    "parcel_view": (["ufi", "geom"], "ufi", None),
    "building_polygon": (["ufi", "feature_subtype", "geom"], "ufi", None),
    "plan_zone": (["ufi", "zone_code", "zone_description", "geom"], "ufi", None),
    "parkres": (["prims_id", "name_short", "area_type", "geom"], "prims_id", None),
    "hy_watercourse": (["ufi", "name", "feature_type_code", "geom"], "ufi", None),
    "hy_water_area_polygon": (["ufi", "name", "feature_type_code", "geom"], "ufi", None),
    "tr_rail_infrastructure": (["ufi", "feature_type_code", "geom"], "ufi", "feature_type_code='rail_station'"),
    "foi_point": (["ufi", "feature_type", "feature_subtype", "name_label", "geom"], "ufi",
                  "feature_type='emergency facility'"),
}


def fetch_page(layer, props, sort_key, cql, start):
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": f"open-data-platform:{layer}",
        "outputFormat": "application/json",
        "srsName": "EPSG:4283",
        "count": str(PAGE),
        "startIndex": str(start),
        "sortBy": sort_key,
    }
    if props:
        params["propertyName"] = ",".join(props)
    # CQL BBOX with an 'EPSG:' code takes lon/lat (x/y) order.
    bbox = f"BBOX(geom,{MIN_LON},{MIN_LAT},{MAX_LON},{MAX_LAT},'EPSG:4283')"
    params["CQL_FILTER"] = f"{bbox} AND {cql}" if cql else bbox
    url = WFS + "?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=180) as resp:
                return json.load(resp)
        except Exception as exc:  # network hiccup: back off and retry
            print(f"    retry {attempt + 1} ({exc})")
            time.sleep(2 + attempt * 3)
    raise RuntimeError(f"failed to fetch {layer} at {start}")


def fetch_layer(layer, props, sort_key, cql):
    features = []
    start = 0
    while True:
        page = fetch_page(layer, props, sort_key, cql, start)
        batch = page.get("features", [])
        features.extend(batch)
        print(f"  {layer}: {len(features)}")
        if len(batch) < PAGE:
            break
        start += PAGE
    return {"type": "FeatureCollection", "layer": layer, "features": features}


def main():
    force = "--force" in sys.argv
    os.makedirs(CACHE, exist_ok=True)
    for layer, (props, sort_key, cql) in LAYERS.items():
        out = os.path.join(CACHE, f"{layer}.geojson")
        if os.path.exists(out) and not force:
            print(f"skip {layer} (cached)")
            continue
        print(f"fetch {layer}")
        data = fetch_layer(layer, props, sort_key, cql)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))
        print(f"  saved {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
