#!/usr/bin/env python3
# AI-assisted (Claude Opus 5.5). Prompt used:
#   "Write a standard-library Python build step that turns the raw Vicmap
#    GeoJSON in tools/cache (downloaded by fetch_vicmap.py) into compact data
#    for ONE large Godot world around the City of Boroondara, replacing our
#    three hand-made suburb SVG chunks. Requirements:
#      - Project GDA94 lon/lat to game pixels with a local equirectangular
#        projection (0.75 px per metre, y pointing south) and record the
#        projection so other lon/lat data can be placed in Godot.
#      - STAGES (from the game spec): 0 tutorial, 1 Camberwell, 2 + Hawthorn
#        East and Surrey Hills, 3 all of Boroondara. Tag every road with the
#        first stage it is fully inside.
#      - ROADS from Vicmap Transport tr_road: keep open roads that vehicles can
#        use (drop trails, footbridges, proposed/closed roads), use the real
#        from_ufi/to_ufi intersection ids for topology, merge simple
#        pass-through chains, keep the street name, road class, one-way flag
#        and length. Playable roads form the routing graph (largest connected
#        component only); roads outside every stage are kept for drawing only.
#      - BUILDINGS: one stylised box per land parcel (parcel_view): the
#        parcel's minimum-area oriented rectangle shrunk toward its centre,
#        classified by the planning zone under it (residential / commercial /
#        public / industrial) for colour; skip parks, road reserves and tiny
#        parcels. Also keep the real Vicmap building footprints.
#      - AREAS: parks (park zones + Parks Victoria reserves), water bodies,
#        waterway lines (Yarra wider than creeks), railway and tram lines and
#        suburb outlines with names. Simplify all geometry (Douglas-Peucker
#        ~1.5 px) to keep files small.
#      - Write everything to Map/world/ and print a summary."
#
# Follow-up prompt (rectangular stages, building fix, names, attribution):
#   "Rework the build: (1) Stages are now plain axis-aligned rectangles in
#    metres around Camberwell Junction, not suburb shapes: a small tutorial
#    rectangle, stage 2 the size of the old Camberwell + Hawthorn East +
#    Surrey Hills extent, stage 1 halfway between stage 0 and stage 2 in both
#    size and position, and stage 3 exactly double stage 2's width and height
#    about the same centre. Derive the world extent (and the download box used
#    by fetch_vicmap.py) from the stage 3 rectangle plus a margin, write the
#    rectangles to world_meta.json and drop the raster stage mask. (2) Some
#    building boxes were far too big and spilled over roads where parcels are
#    large or L-shaped: clip each box to its own parcel outline, only make
#    boxes for normal-sized lots, and draw big sites (schools, shopping
#    centres) as a pale site tint instead, relying on the real Vicmap
#    footprints for their buildings. Triangulate here and store triangles so
#    Godot can load them straight into a mesh. (3) Fold in the one-off name
#    fictionalising script (tools/fictionalise_names.py, now deleted) as the
#    final step, so every rebuild outputs the same fictional suburb, road,
#    facility and stage names and no real names are written to Map/world.
#    (4) Record exactly which datasets were used (official data.vic titles,
#    WFS layer names, custodians, licence, retrieval dates and the changes we
#    made) in world_meta.json and a generated Map/world/ATTRIBUTION.md."
#
# Usage (from the project root):  python3 tools/build_world.py

import datetime
import hashlib
import json
import math
import os
import random
import re
import struct
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "cache")
OUT = os.path.join(ROOT, "Map", "world")
FOI_JSON = os.path.join(ROOT, "Map", "boroondara_foi_game_data.json")

# --- Stages & projection ----------------------------------------------------
JUNCTION = (145.0583, -37.8305)     # Camberwell Junction (lon, lat)
PX_PER_M = 0.75
M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(JUNCTION[1]))

# Stage rectangles in metres from the junction: (west, north, east, south),
# east and south positive.
_S0 = (-620.0, -330.0, 380.0, 330.0)                 # tutorial
_S2 = (-1633.0, -1999.0, 3913.0, 2300.0)             # old 3-suburb extent


def _lerp_rect(a, b, t):
    """Rectangle part-way (t) between a and b in both size and centre."""
    ca = ((a[0] + a[2]) / 2, (a[1] + a[3]) / 2)
    cb = ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
    w = (a[2] - a[0]) + ((b[2] - b[0]) - (a[2] - a[0])) * t
    h = (a[3] - a[1]) + ((b[3] - b[1]) - (a[3] - a[1])) * t
    cx, cy = ca[0] + (cb[0] - ca[0]) * t, ca[1] + (cb[1] - ca[1]) * t
    return (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)


def _scale_rect(r, k):
    cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
    hw, hh = (r[2] - r[0]) / 2 * k, (r[3] - r[1]) / 2 * k
    return (cx - hw, cy - hh, cx + hw, cy + hh)


STAGE_RECTS_M = [_S0, _lerp_rect(_S0, _S2, 0.5), _S2, _scale_rect(_S2, 2.0)]
STAGE_NAMES = ["Tutorial: Camberwell Junction", "Camberwell",
               "Camberwell, Hawthorn East & Surrey Hills", "Greater Boroondara"]
MARGIN_M = 400.0

# World origin = top-left of stage 3 plus margin.
_W0 = STAGE_RECTS_M[3][0] - MARGIN_M
_N0 = STAGE_RECTS_M[3][1] - MARGIN_M
LON0 = JUNCTION[0] + _W0 / M_PER_DEG_LON
LAT0 = JUNCTION[1] - _N0 / M_PER_DEG_LAT
LON1 = JUNCTION[0] + (STAGE_RECTS_M[3][2] + MARGIN_M) / M_PER_DEG_LON
LAT1 = JUNCTION[1] - (STAGE_RECTS_M[3][3] + MARGIN_M) / M_PER_DEG_LAT
WORLD_W = int(math.ceil((LON1 - LON0) * M_PER_DEG_LON * PX_PER_M))
WORLD_H = int(math.ceil((LAT0 - LAT1) * M_PER_DEG_LAT * PX_PER_M))
# Download box for fetch_vicmap.py (min lon, min lat, max lon, max lat).
FETCH_BOUNDS = (LON0, LAT1, LON1, LAT0)


def proj(lon, lat):
    return ((lon - LON0) * M_PER_DEG_LON * PX_PER_M, (LAT0 - lat) * M_PER_DEG_LAT * PX_PER_M)


def _rect_px(r):
    return ((r[0] - _W0) * PX_PER_M, (r[1] - _N0) * PX_PER_M,
            (r[2] - _W0) * PX_PER_M, (r[3] - _N0) * PX_PER_M)


STAGE_RECTS = [_rect_px(r) for r in STAGE_RECTS_M]
OUTSIDE = 255


def stage_of(x, y):
    for s, (x0, y0, x1, y1) in enumerate(STAGE_RECTS):
        if x0 <= x <= x1 and y0 <= y <= y1:
            return s
    return OUTSIDE


# --- Data sources (for attribution) -----------------------------------------
VICMAP = "© State of Victoria (Department of Transport and Planning)"
DEECA = "© State of Victoria (Department of Energy, Environment and Climate Action)"
LICENCE = "Creative Commons Attribution 4.0 International (CC BY 4.0)"
LICENCE_URL = "https://creativecommons.org/licenses/by/4.0/"
SOURCES = [
    # (cache layer, data.vic title, data.vic id, custodian, used for)
    ("tr_road", "Vicmap Transport - Road Line", "vicmap-transport-road-line", VICMAP,
     "road network, street names, road classes"),
    ("tr_rail", "Vicmap Transport - Railway Line", "vicmap-transport-railway-line", VICMAP,
     "railway and tram lines"),
    ("parcel_view", "Vicmap Property - Parcel Polygon", "vicmap-property-parcel-polygon", VICMAP,
     "stylised building boxes and site areas"),
    ("building_polygon", "Vicmap Features - Building Polygon", "vicmap-features-building-polygon",
     VICMAP, "building footprints"),
    ("plan_zone", "Vicmap Planning - Planning Scheme Zone Polygon",
     "vicmap-planning-planning-scheme-zone-polygon", VICMAP, "land-use colours, parks"),
    ("hy_watercourse", "Vicmap Hydro - Watercourse Line", "vicmap-hydro-watercourse-line", VICMAP,
     "rivers and creeks"),
    ("hy_water_area_polygon", "Vicmap Hydro - Water Polygon", "vicmap-hydro-water-polygon", VICMAP,
     "lakes, wetlands, river areas"),
    ("locality_polygon", "Vicmap Admin - Locality Polygon", "vicmap-admin", VICMAP,
     "suburb outlines and labels"),
    ("parkres", "Parks and Conservation Reserves (PARKRES)", "parks-and-conservation-reserves-parkres",
     DEECA, "state parks and reserves"),
]
FOI_SOURCE = ("Vicmap Features of Interest", "vicmap-features-of-interest", VICMAP,
              "Features of Interest (supplied as the unit's Boroondara student game extract "
              "of FOI_INDEX_EXTENT)")
CHANGES = ("Reprojected to a local game grid, clipped to the play area, simplified and "
           "stylised (parcels drawn as building boxes), and all place, road and facility "
           "names replaced with fictional names. This is a game, not an emergency map.")

# --- Roads ------------------------------------------------------------------
# Vicmap class_code: 0 freeway, 1 highway, 2 arterial, 3 sub-arterial,
# 4 collector, 5 local, 6 minor/lane, 9 track. Game class: 0 local .. 3 freeway.
GAME_CLASS = {0: 3, 1: 3, 2: 2, 3: 2, 4: 1, 5: 0, 6: 0}
DRIVABLE_TYPES = {"road", "bridge", "tunnel", "connector"}

# --- Buildings --------------------------------------------------------------
KIND_RESIDENTIAL, KIND_COMMERCIAL, KIND_PUBLIC, KIND_INDUSTRIAL = 0, 1, 2, 3
SITE = 4                      # kind + SITE = pale site tint for big parcels
BOX_MAX_M2 = 2500             # bigger parcels become sites, not boxes
SIMPLIFY = 1.5


def load(layer):
    with open(os.path.join(CACHE, f"{layer}.geojson"), encoding="utf-8") as f:
        return json.load(f)["features"]


def rings(geom, outer_only=True):
    """Yield projected rings/lines from any GeoJSON geometry."""
    t, c = geom["type"], geom["coordinates"]
    if t == "LineString":
        yield [proj(*p) for p in c]
    elif t == "MultiLineString":
        for line in c:
            yield [proj(*p) for p in line]
    elif t == "Polygon":
        for ring in (c[:1] if outer_only else c):
            yield [proj(*p) for p in ring]
    elif t == "MultiPolygon":
        for poly in c:
            for ring in (poly[:1] if outer_only else poly):
                yield [proj(*p) for p in ring]


def simplify(pts, tol=SIMPLIFY):
    if len(pts) < 3:
        return pts
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        best, idx = 0.0, -1
        for i in range(a + 1, b):
            px, py = pts[i]
            if l2 == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / math.sqrt(l2)
            if d > best:
                best, idx = d, i
        if best > tol:
            keep[idx] = True
            stack += [(a, idx), (idx, b)]
    return [p for p, k in zip(pts, keep) if k]


def clip_convex(poly, clip):
    """Sutherland-Hodgman: clip any polygon by a convex polygon (same winding)."""
    out = poly
    for i in range(len(clip)):
        a, b = clip[i - 1], clip[i]
        inp, out = out, []
        if not inp:
            break

        def inside(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

        def cut(p, q):
            dx1, dy1 = q[0] - p[0], q[1] - p[1]
            dx2, dy2 = b[0] - a[0], b[1] - a[1]
            den = dx1 * dy2 - dy1 * dx2
            if den == 0:
                return q
            t = ((a[0] - p[0]) * dy2 - (a[1] - p[1]) * dx2) / den
            return (p[0] + dx1 * t, p[1] + dy1 * t)

        for j in range(len(inp)):
            cur, prev = inp[j], inp[j - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(cut(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(cut(prev, cur))
    return out


def signed_area(pts):
    return sum(pts[i - 1][0] * pts[i][1] - pts[i][0] * pts[i - 1][1] for i in range(len(pts))) / 2


def poly_area(pts):
    return abs(signed_area(pts))


def ccw(pts):
    """Consistent winding (positive signed area) for clipping/triangulating."""
    return pts if signed_area(pts) > 0 else list(reversed(pts))


WORLD_POLY = None   # set in main() once ccw() exists


def centroid(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return sum(xs) / len(xs), sum(ys) / len(ys)


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def point_in_tri(p, a, b, c):
    def s(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def triangulate(poly):
    """Ear clipping. poly must have positive signed area. Returns triangles."""
    pts = [p for i, p in enumerate(poly) if i == 0 or math.dist(p, poly[i - 1]) > 0.05]
    if len(pts) > 1 and math.dist(pts[0], pts[-1]) <= 0.05:
        pts.pop()
    if len(pts) < 3:
        return []
    tris = []
    idx = list(range(len(pts)))
    while len(idx) > 3:
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 0:
                continue  # reflex corner
            if any(point_in_tri(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((a, b, c))
            idx.pop(k)
            break
        else:
            break  # degenerate outline; keep what we have
    if len(idx) == 3:
        tris.append(tuple(pts[i] for i in idx))
    return tris


def rr(pts):
    return [[round(x, 1), round(y, 1)] for x, y in pts]


# --- Fictional names ----------------------------------------------------------
# Ported from the one-off tools/fictionalise_names.py so rebuilds never write
# real names. Deterministic: the same input always yields the same names.
PLACES = {
    # suburbs / localities
    "Surrey Hills": "Sorrel Hills", "Glen Iris": "Glen Wattle",
    "Hawthorn": "Hawkthorne", "Camberwell": "Cambermere",
    "Canterbury": "Canterbrook", "Abbotsford": "Abbotsmere",
    "Ashburton": "Ashmarra", "Balwyn": "Balmoor", "Deepdene": "Deepdale",
    "Boroondara": "Burrundara", "Burwood": "Burrwick", "Kew": "Kewnell",
    "Hartwell": "Harrowell", "Studley": "Studmoor", "Tooronga": "Toorangal",
    "Melbourne": "Marlbourne", "Swinburne": "Swinford", "Yarra Bend": "Yarrow Bend",
    "Yarra": "Yarrow", "Solway": "Solmere", "Inglesby": "Ingleford",
    "Whitehorse": "Whitemare", "Glenferrie": "Glenferrin", "Koonung": "Kooranung",
    "Abercrombie": "Abernant", "Doncaster": "Doncliffe", "Bulleen": "Bullarra",
    "Toorak": "Toorabin", "Riversdale": "Rivermead", "Burke": "Burkett",
    "Mont Albert": "Mont Alvern", "Cotham": "Cothorne", "Warrigal": "Warrabin",
    "Chandler": "Chandry", "Monash": "Marlow", "Eastern": "Orient",
    "Thompsons": "Thomlins", "Citylink": "Metrolink", "Victoria Park": "Regent Park",
    "Ferndale": "Fernmoor", "Auburn": "Ashburn", "Barkers": "Barlowes",
    "Belmore": "Belmara", "Union": "Unity", "Highfield": "Highmeade",
    "Prospect Hill": "Lookout Hill", "Kilby": "Kilbarra", "Winmalee": "Winmarra",
    "Yarrbat": "Yarrabil", "Camberwell Junction": "Cambermere Junction",
    # suburbs that only appear now the world reaches further east/south
    "Box Hill": "Bark Hill", "Blackburn": "Blackmoor", "Malvern": "Malmoor",
    "Chadstone": "Chadwell", "Ashwood": "Ashgrove", "Mount Waverley": "Mount Wavell",
    "Kooyong": "Kooranga", "Richmond": "Richmere", "Ivanhoe": "Ivanmere",
    "Alphington": "Alphmoor", "Fairfield": "Fairmead", "Nunawading": "Nunamarra",
    "Mitcham": "Mitchmoor", "Forest Hill": "Forest Rise", "Vermont": "Vermere",
    "Templestowe": "Templemoor", "Clifton Hill": "Clifton Rise", "Burnley": "Burnmere",
    "Cremorne": "Cremwell", "Armadale": "Armmere", "Hughesdale": "Hughmoor",
    "Prahran": "Prahmere", "South Yarra": "South Yarrow", "Windsor": "Windmere",
    # facilities
    "Beckett Park": "Beckwith Park", "Cascade Park": "Cataract Park",
    "Glenburn Bend Park": "Glenmoor Bend Park", "Kate Campbell": "Kitty Campion",
    "Nott": "Nettle", "Maranoa": "Marrawa", "Strathcona": "Strathwyn", "Bialik": "Bellwood",
    "Epworth": "Ellsworth", "Nazareth": "Bethany", "Faversham": "Farnsham",
    "Monnington": "Marrington", "Bellevue": "Bellmont", "Yongala": "Yungalla",
    "Caritas Christi": "Sacred Mercy", "Leonda": "Lenora", "Aveo": "Avalon",
    "Condare": "Cordare", "Probus": "Prowse", "Collins": "Colwell",
    "Anderson": "Andersley", "Mcc": "Mrc", "Villa Alba": "Villa Aurora",
}
FOI_NAMES = {
    "Grace Court Special Accomodation": "Gracemere Court Special Accommodation",
    "Michael Chamberlain Court": "Martin Chalmers Court",
    "St Catherines Village": "St Cecilias Village",
    "The Heights Retirement Village": "The Highlands Retirement Village",
    "Giant Steps Melbourne": "Long Strides Marlbourne",
    "Leo Baeck Centre": "Leon Bachman Centre",
    "Holy Trinity Early Learning Centre": "Holy Redeemer Early Learning Centre",
    "Teamkids - Solway Primary": "Kidscrew - Solmere Primary",
    "National Guide Dog And Mobility Centre": "National Assistance Dog And Mobility Centre",
    "Chris Cross Garden Supplies": "Cliff Crossley Garden Supplies",
    "Iris Manor": "Wattle Manor",
    "Playground - Kate Campbell Reserve": "Playground - Kitty Campion Reserve",
    "Mcc Croquet Section Inc": "Mrc Croquet Section Inc",
}
KEEP_BASES = {
    "High", "Bridge", "Victory", "Power", "Through", "Church", "Station",
    "School", "Park", "Railway", "Princess", "Queen", "King", "Centre",
    "Garden", "Walnut", "Fairview", "Highview", "Unnamed", "Pin Oak",
    "Arbour", "Cypress", "Stringybark", "Sun Rise", "Summerhill",
    "Mountain View", "Mount View", "Great Valley", "River", "Bella Vista",
    "Belle Vue", "Bon Vue", "Bona Vista", "Jolie Vue", "Grandview",
}
ROAD_TYPES = {
    "Street", "Avenue", "Road", "Court", "Grove", "Place", "Crescent", "Lane",
    "Drive", "Parade", "Close", "Way", "Terrace", "Rise", "Boulevard",
    "Highway", "Freeway", "Broadway", "Arcade", "Glen", "View", "Walk", "Hill",
    "Retreat", "Circuit", "Mews", "Moor", "Nook", "Pines", "Ridge", "Point",
    "Gardens", "Belvedere", "Ramp",
}
TAILS = {"N", "S", "Ex", "On", "Of", "In", "Out"}
LEADS = {"The", "St", "Sir", "Lady", "Mount", "Mont", "Little", "Old", "Upper",
         "Lower", "Great", "Avenue"}
SURNAMES = """Abbott Ainsley Alder Armitage Ashworth Atwell Bannister Barrow Beckett
Bellamy Bingham Blakely Bolton Bramwell Brennan Brodie Buckley Burgess Cadell
Calder Carew Chalmers Charlton Clegg Cobden Colby Corbett Crawley Cullen
Dalby Darcy Dawson Delaney Denholm Dowling Drummond Dunmore Eastwood Elwood
Emmett Everett Fairley Farrell Fenwick Finch Fleming Forrest Fraser Gallagher
Garrick Gilmour Gower Grafton Greer Haddon Halloran Hanley Harcourt Hartnett
Hastings Hayden Heffernan Hobart Holloway Hudson Ingram Jarrett Kellett
Kendall Kerr Kirkby Lacey Langley Lawson Leighton Lockhart Lomax Lyle Mabbott
Maddox Marsden Maynard McBride Merrick Mitchell Moffat Munro Napier Nash
Neville Nolan Norris Oakley Orrell Osborne Palmer Parnell Pascoe Pearce
Pemberton Quinn Radford Rawson Redmond Renshaw Rowley Rutledge Sanders
Seymour Sheridan Sinclair Slade Stanton Sutton Tennant Thornley Tierney
Tolland Trevor Tyler Underwood Vance Wadley Walden Wallace Warwick Weston
Whitlam Wilder Winslow Yates Yeoman Zane""".split()
ROOTS = """Ash Bell Birch Black Bright Brook Cedar Clay Clover Cobb Cress Dun Elm
Fern Fox Gum Hazel Heath Holly Iron Jar Kell Lark Lime Marsh Mill Moss Oak
Pine Quarry Red Reed Rose Sand Silver Stone Thorn Wattle Wren Yew""".split()
ENDINGS = ["ton", "vale", "field", "wick", "ridge", "brook", "hurst", "mont",
           "dale", "ford", "by", "ham", "ley", "wood", "moor", "mere", "bourne"]
ABORIG_A = ["Wa", "Ka", "Ya", "Bi", "Tu", "Mi", "Ba", "Nu", "Ko", "Gu", "Wi",
            "Jar", "Mun", "Boo", "Kal", "Nar", "Tar", "Won", "Yam", "Bin", "Dja",
            "Mur", "Pin", "Ca", "Lu", "Ma", "Ra", "Ta"]
ABORIG_B = ["ra", "ri", "ru", "li", "ma", "nga", "ba", "ka", "wa", "rin",
            "lum", "bi", "ngi", "dun", "ly", "ro", "bin", "gil"]
ABORIG_C = ["wee", "bin", "lah", "nna", "rra", "ga", "da", "ra", "la", "ngi",
            "bah", "rie", "lee", "mbi", "ooka"]
SAINTS = """Aidans Agathas Alphonsus Bernards Brendans Bridgets Clements Colms
Cuthberts Dunstans Edmunds Elmos Fabians Gabriels Hilarys Ignatius Isidores
Jeromes Kilians Lukes Margarets Martins Nicholas Olafs Patricks Quentins
Raphaels Sebastians Theodores Ursulas Vincents Winifreds""".split()


class Namer:
    def __init__(self, real_road_names):
        rng = random.Random(7)
        pool = list(SURNAMES) + [r + e for r in ROOTS for e in ENDINGS]
        for _ in range(5000):
            pool.append(rng.choice(ABORIG_A) + rng.choice(ABORIG_B) + rng.choice(ABORIG_C))
        self.pool = sorted(set(pool))
        self.used = set()
        self.base_cache = {}
        # Never generate a word that is part of a real road name or a mapping.
        for n in real_road_names:
            self.used.update(n.split())
        for v in PLACES.values():
            self.used.update(v.split())
        self._pat = re.compile(r"\b(" + "|".join(
            re.escape(k) for k in sorted(PLACES, key=len, reverse=True)) + r")\b", re.I)
        self._lower = {k.lower(): v for k, v in PLACES.items()}

    def _pick(self, key, pool):
        rng = random.Random(int(hashlib.md5(key.encode()).hexdigest(), 16))
        same = [p for p in pool if p[0].lower() == key[0].lower()]
        cands = same if len(same) > 20 and rng.random() < 0.7 else pool
        if all(c in self.used for c in pool):
            raise RuntimeError("name pool exhausted")
        for i in range(4000):
            c = rng.choice(cands if i < 100 else pool)
            if c not in self.used:
                self.used.add(c)
                return c
        raise RuntimeError("name pool exhausted")

    def place(self, text):
        def rep(m):
            dst = self._lower[m.group(0).lower()]
            return dst.upper() if m.group(0).isupper() else dst
        return self._pat.sub(rep, text)

    def road(self, name):
        if not name or name == "R O W Y":
            return name
        out = self.place(name)
        if out != name:
            return out
        toks = name.split()
        tail = []
        while len(toks) > 1 and toks[-1] in TAILS:
            tail.insert(0, toks.pop())
        typ = []
        if len(toks) > 1 and toks[-1] in ROAD_TYPES:
            typ = [toks.pop()]
        lead = []
        while len(toks) > 1 and toks[0] in LEADS:
            lead.append(toks.pop(0))
        base = " ".join(toks)
        if toks == ["The"] or (lead == ["The"] and not typ) or base in KEEP_BASES:
            return name
        if lead and lead[0] == "St":
            key = "St " + base
            if key not in self.base_cache:
                # The bigger world has more "St ..." roads than saint names;
                # fall back to a possessive from the general pool.
                try:
                    self.base_cache[key] = self._pick(key, SAINTS)
                except RuntimeError:
                    self.base_cache[key] = self._pick(key, self.pool) + "s"
            new = self.base_cache[key]
        else:
            if base not in self.base_cache:
                self.base_cache[base] = self._pick(base, self.pool)
            new = self.base_cache[base]
        return " ".join(lead + [new] + typ + tail)

    def foi(self, name):
        return FOI_NAMES.get(name) or self.place(name)


# --- Roads ------------------------------------------------------------------
def build_roads():
    segs = []   # [from, to, pts, class, name, oneway]
    for f in load("tr_road"):
        p = f["properties"]
        if p["feature_type_code"] not in DRIVABLE_TYPES or p["road_status"] != "O":
            continue
        if p["vehicular_access"] != "1" or p["class_code"] not in GAME_CLASS:
            continue
        pts = next(rings(f["geometry"]))
        if len(pts) < 2:
            continue
        segs.append([p["from_ufi"], p["to_ufi"], pts, GAME_CLASS[p["class_code"]],
                     p["ezi_road_name_label"] or "", p["direction_code"] == "F"])

    node_pos = {}
    for a, b, pts, *_ in segs:
        node_pos.setdefault(a, pts[0])
        node_pos.setdefault(b, pts[-1])

    # Merge pass-through chains (a node shared by exactly two segments with
    # the same name/class is not a real intersection).
    by_node = defaultdict(list)
    for i, s in enumerate(segs):
        by_node[s[0]].append(i)
        by_node[s[1]].append(i)
    alive = [True] * len(segs)
    for node, idxs in list(by_node.items()):
        live = [i for i in idxs if alive[i]]
        if len(live) != 2:
            continue
        i, j = live
        if i == j or segs[i][3:6] != segs[j][3:6] or segs[i][5]:
            continue
        si, sj = segs[i], segs[j]
        pi = si[2] if si[1] == node else list(reversed(si[2]))
        pj = sj[2] if sj[0] == node else list(reversed(sj[2]))
        start = si[0] if si[1] == node else si[1]
        end = sj[1] if sj[0] == node else sj[0]
        if start == end:
            continue
        si[0], si[1], si[2] = start, end, pi + pj[1:]
        alive[j] = False
        by_node[end] = [i if k == j else k for k in by_node[end]]
    segs = [s for s, a in zip(segs, alive) if a]

    # A road belongs to the first stage that contains ALL of it.
    for s in segs:
        s.append(max(stage_of(x, y) for x, y in s[2]))

    play = [s for s in segs if s[6] != OUTSIDE]
    parent = {}

    def find(n):
        parent.setdefault(n, n)
        while parent[n] != n:
            parent[n] = parent[parent[n]]
            n = parent[n]
        return n

    for s in play:
        parent[find(s[0])] = find(s[1])
    size = defaultdict(int)
    for s in play:
        size[find(s[0])] += 1
    main_root = max(size, key=size.get)
    play = [s for s in play if find(s[0]) == main_root]

    index, nodes, edges = {}, [], []
    for a, b, pts, cls, name, oneway, stage in play:
        for n in (a, b):
            if n not in index:
                index[n] = len(nodes)
                x, y = node_pos[n]
                nodes.append([round(x, 1), round(y, 1)])
        edges.append({"a": index[a], "b": index[b], "c": cls, "n": name,
                      "o": 1 if oneway else 0, "s": stage, "pts": rr(simplify(pts, 0.6))})
    played = {id(s) for s in play}
    decor = [{"c": s[3], "pts": rr(simplify(s[2], 0.8))} for s in segs if id(s) not in played]
    return nodes, edges, decor, len(segs)


# --- Zones & buildings ------------------------------------------------------
def zone_kind(code):
    if code.startswith(("PPRZ", "PCRZ")):
        return "park"
    if code.startswith(("TRZ", "RDZ")):
        return "road"
    if code.startswith(("C1Z", "C2Z", "C3Z", "MUZ", "ACZ", "CCZ", "CDZ", "PZ")):
        return KIND_COMMERCIAL
    if code.startswith(("PUZ", "SUZ", "CA")):
        return KIND_PUBLIC
    if code.startswith("IN"):
        return KIND_INDUSTRIAL
    if code.startswith("UFZ"):
        return None
    return KIND_RESIDENTIAL


class ZoneIndex:
    CELL = 200.0

    def __init__(self, zones):
        self.zones = zones
        self.grid = defaultdict(list)
        for i, (poly, _) in enumerate(zones):
            xs = [p[0] for p in poly]
            ys = [p[1] for p in poly]
            for gx in range(int(min(xs) // self.CELL), int(max(xs) // self.CELL) + 1):
                for gy in range(int(min(ys) // self.CELL), int(max(ys) // self.CELL) + 1):
                    self.grid[(gx, gy)].append(i)

    def kind_at(self, x, y):
        for i in self.grid.get((int(x // self.CELL), int(y // self.CELL)), ()):
            poly, kind = self.zones[i]
            if point_in_poly(x, y, poly):
                return kind
        return KIND_RESIDENTIAL


def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_area_rect(pts):
    hull = convex_hull(pts)
    if len(hull) < 3:
        return None
    best = None
    for i in range(len(hull)):
        x1, y1 = hull[i]
        x2, y2 = hull[(i + 1) % len(hull)]
        ang = math.atan2(y2 - y1, x2 - x1)
        c, s = math.cos(ang), math.sin(ang)
        us = [px * c + py * s for px, py in hull]
        vs = [-px * s + py * c for px, py in hull]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            best = (area, c, s, min(us), max(us), min(vs), max(vs))
    _, c, s, u0, u1, v0, v1 = best
    return [(u * c - v * s, u * s + v * c) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]


def pack_tris(out, kind, tris):
    """Record: u8 kind, u16 triangle count, then 6 x int16 per triangle."""
    if not tris:
        return 0
    out += struct.pack("<BH", kind, len(tris))
    for tri in tris:
        for x, y in tri:
            out += struct.pack("<hh", max(-32768, min(32767, int(round(x)))),
                               max(-32768, min(32767, int(round(y)))))
    return 1


def build_buildings(zindex):
    sites, boxes = bytearray(), bytearray()
    seen = set()
    n_sites = n_boxes = 0
    for f in load("parcel_view"):
        for ring in rings(f["geometry"]):
            if len(ring) < 4:
                continue
            cx, cy = centroid(ring)
            if not (0 <= cx <= WORLD_W and 0 <= cy <= WORLD_H):
                continue
            area_m2 = poly_area(ring) / (PX_PER_M ** 2)
            if area_m2 < 40:
                continue
            key = (round(cx / 2), round(cy / 2))
            if key in seen:          # stacked strata parcels: draw once
                continue
            seen.add(key)
            kind = zindex.kind_at(cx, cy)
            if kind in ("park", "road", None):
                continue
            parcel = ccw(simplify(ring[:-1], 0.5))
            if len(parcel) < 3:
                continue
            if area_m2 > BOX_MAX_M2:
                n_sites += pack_tris(sites, kind + SITE, triangulate(parcel))
                continue
            rect = min_area_rect(ring)
            if rect is None:
                continue
            w = math.dist(rect[0], rect[1])
            h = math.dist(rect[1], rect[2])
            shrink = 0.7 if min(w, h) < 30 else max(0.55, 1 - 18 / min(w, h))
            rcx, rcy = centroid(rect)
            box = ccw([(rcx + (x - rcx) * shrink, rcy + (y - rcy) * shrink) for x, y in rect])
            # Never spill outside the parcel (L-shaped / skewed lots).
            shape = clip_convex(parcel, box)
            if len(shape) >= 3 and poly_area(shape) > 4:
                n_boxes += pack_tris(boxes, kind, triangulate(ccw(shape)))
    return sites + boxes, n_sites, n_boxes


# --- Main -------------------------------------------------------------------
def main():
    global WORLD_POLY
    WORLD_POLY = ccw([(0, 0), (WORLD_W, 0), (WORLD_W, WORLD_H), (0, WORLD_H)])
    os.makedirs(OUT, exist_ok=True)
    for stale in ("stage_mask.bin", "stage_mask_preview.png", "stage_mask_preview.png.import"):
        if os.path.exists(os.path.join(OUT, stale)):
            os.remove(os.path.join(OUT, stale))
    print(f"world {WORLD_W} x {WORLD_H} px; stage rects px: "
          f"{[tuple(round(v) for v in r) for r in STAGE_RECTS]}")

    nodes, edges, decor, raw_roads = build_roads()
    namer = Namer([e["n"] for e in edges])
    for e in edges:
        e["n"] = namer.road(e["n"])
    with open(os.path.join(OUT, "roads.json"), "w", encoding="utf-8") as f:
        json.dump({"nodes": nodes, "edges": edges, "decor": decor}, f, separators=(",", ":"))

    zones, parks = [], []
    for z in load("plan_zone"):
        kind = zone_kind(z["properties"]["zone_code"])
        for ring in rings(z["geometry"]):
            zones.append((ring, kind))
            if kind == "park":
                c = clip_convex(ccw(simplify(ring[:-1])), WORLD_POLY)
                if len(c) >= 3:
                    parks.append(rr(c))
    for p in load("parkres"):
        for ring in rings(p["geometry"]):
            c = clip_convex(ccw(simplify(ring[:-1], 2.0)), WORLD_POLY)
            if len(c) >= 3:
                parks.append(rr(c))
    zindex = ZoneIndex(zones)

    blob, n_sites, n_boxes = build_buildings(zindex)
    with open(os.path.join(OUT, "buildings.bin"), "wb") as f:
        f.write(blob)

    footprints = []
    for b in load("building_polygon"):
        for ring in rings(b["geometry"]):
            footprints.append(rr(simplify(ring, 0.8)))

    water = []
    for w in load("hy_water_area_polygon"):
        for r in rings(w["geometry"]):
            c = simplify(clip_convex(ccw(simplify(r[:-1], 2.5)), WORLD_POLY), 2.5)
            if len(c) >= 3:
                water.append(rr(c))
    waterways = []
    for w in load("hy_watercourse"):
        name = w["properties"]["name"] or ""
        width = 34 if name == "YARRA RIVER" else (8 if "CREEK" in name else 4)
        for line in rings(w["geometry"]):
            waterways.append({"w": width, "pts": rr(simplify(line))})
    rail, tram = [], []
    for r in load("tr_rail"):
        t = r["properties"]["feature_type_code"]
        if t in ("rail_dismantled", "rail_siding"):
            continue
        for line in rings(r["geometry"]):
            (tram if t == "tramway" else rail).append(rr(simplify(line)))

    suburbs = []
    for f in load("locality_polygon"):
        for ring in rings(f["geometry"]):
            cx, cy = centroid(ring)
            if 0 <= cx <= WORLD_W and 0 <= cy <= WORLD_H:
                suburbs.append({"name": namer.place(f["properties"]["locality_name"].title()),
                                "pts": rr(simplify(ring, 3))})

    with open(os.path.join(OUT, "areas.json"), "w", encoding="utf-8") as f:
        json.dump({"suburbs": suburbs, "parks": parks, "water": water, "waterways": waterways,
                   "rail": rail, "tram": tram, "footprints": footprints}, f, separators=(",", ":"))

    fois = []
    for feat in json.load(open(FOI_JSON, encoding="utf-8"))["features"]:
        x, y = proj(feat["longitude"], feat["latitude"])
        fois.append({"id": feat["id"], "name": namer.foi(feat["name"]), "type": feat["feature_type"],
                     "subtype": feat["feature_subtype"], "x": round(x, 1), "y": round(y, 1),
                     "s": stage_of(x, y)})
    with open(os.path.join(OUT, "foi.json"), "w", encoding="utf-8") as f:
        json.dump(fois, f, indent=1)

    # Attribution: what we used, from where, when, and what we changed.
    sources = []
    for layer, title, slug, custodian, used_for in SOURCES:
        path = os.path.join(CACHE, f"{layer}.geojson")
        retrieved = datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()
        sources.append({"title": title, "url": f"https://discover.data.vic.gov.au/dataset/{slug}",
                        "wfs_layer": f"open-data-platform:{layer}", "custodian": custodian,
                        "licence": LICENCE, "retrieved": retrieved, "used_for": used_for})
    sources.append({"title": FOI_SOURCE[0],
                    "url": f"https://discover.data.vic.gov.au/dataset/{FOI_SOURCE[1]}",
                    "wfs_layer": "(supplied extract) Map/boroondara_foi_game_data.json",
                    "custodian": FOI_SOURCE[2], "licence": LICENCE, "retrieved": "supplied by unit",
                    "used_for": FOI_SOURCE[3]})
    credit = ("Map data: Vicmap © State of Victoria (Department of Transport and Planning); "
              "PARKRES © State of Victoria (DEECA). CC BY 4.0. Modified: stylised, names fictional.")
    with open(os.path.join(OUT, "world_meta.json"), "w", encoding="utf-8") as f:
        json.dump({
            "size": [WORLD_W, WORLD_H],
            "px_per_m": PX_PER_M,
            "projection": {"lon0": LON0, "lat0": LAT0, "m_per_deg_lon": M_PER_DEG_LON,
                           "m_per_deg_lat": M_PER_DEG_LAT},
            "stage_names": [namer.place(n) for n in STAGE_NAMES],
            "stage_rects": [[round(v, 1) for v in r] for r in STAGE_RECTS],
            "fictional_names": True,
            "credit": credit,
            "licence_url": LICENCE_URL,
            "changes": CHANGES,
            "data_sources": sources,
        }, f, indent=1)
    with open(os.path.join(OUT, "ATTRIBUTION.md"), "w", encoding="utf-8") as f:
        f.write("# Map data attribution\n\n")
        f.write("Generated by `tools/build_world.py`. Do not edit by hand.\n\n")
        f.write(f"On-screen credit: *{credit}*\n\n")
        f.write(f"Licence: [{LICENCE}]({LICENCE_URL}). No endorsement by the State of "
                "Victoria is implied.\n\n")
        f.write(f"**Changes made:** {CHANGES}\n\n")
        f.write("| Dataset | Custodian | WFS layer | Retrieved | Used for |\n"
                "| --- | --- | --- | --- | --- |\n")
        for s in sources:
            f.write(f"| [{s['title']}]({s['url']}) | {s['custodian']} | `{s['wfs_layer']}` | "
                    f"{s['retrieved']} | {s['used_for']} |\n")

    stage_fois = defaultdict(int)
    for x in fois:
        stage_fois[x["s"]] += 1
    stage_edges = defaultdict(int)
    for e in edges:
        stage_edges[e["s"]] += 1
    print(f"roads: {raw_roads} segments, graph {len(nodes)} nodes / {len(edges)} edges "
          f"(per stage {dict(sorted(stage_edges.items()))}), {len(decor)} decor")
    print(f"buildings: {n_boxes} boxes, {n_sites} sites, {len(footprints)} footprints; "
          f"parks {len(parks)}, water {len(water)}")
    print(f"FOI per stage: {dict(sorted(stage_fois.items()))}")
    for name in sorted(os.listdir(OUT)):
        print(f"  Map/world/{name}: {os.path.getsize(os.path.join(OUT, name)) // 1024} KB")


if __name__ == "__main__":
    main()
