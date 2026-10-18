#!/usr/bin/env python3
"""Build a low-altitude detail region for The Filament Falcon from OpenStreetMap + a DEM.

    python3 tools/build_region.py --name fredericton --bbox 45.915,-66.705,46.005,-66.575
            [--osm region.osm.json] [--dem-dir tiles/] [--out DIR] [--chunk 1000]

Region-agnostic: any bbox (S,W,N,E, degrees). Without --osm it downloads the area from the
Overpass API; without --dem-dir it downloads AWS Terrain Tiles (terrarium PNG, SRTM/NED 30 m
class, z13). Output (default ~/.local/share/filament-falcon/assets/regions/NAME/):
    manifest.json      bbox, centre, chunk size, base elevation, chunk list
    c_<ix>_<iz>.json   one chunk: terrain grid (heights + landuse), buildings, trees, water,
                       roads, rails, all in local metres (x = east, z = south, y = up)
The game (scripts/geo/region_view.gd) turns chunks into meshes at runtime and streams them by
distance. Needs python3 + numpy (+ Pillow for the DEM tiles); no GIS stack.
"""
import argparse, json, math, os, sys, urllib.request, urllib.parse, io, hashlib

import numpy as np

UA = {"User-Agent": "FilamentFalcon/1.0 (home cockpit sim; github.com/whyvas/filament-falcon)"}
ROAD_W = {"motorway": 14, "trunk": 12, "primary": 10, "secondary": 9, "tertiary": 8, "unclassified": 6,
          "residential": 6, "living_street": 5, "service": 4, "motorway_link": 7, "trunk_link": 7,
          "primary_link": 7, "secondary_link": 6, "tertiary_link": 6, "track": 3, "cycleway": 2,
          "footway": 1.6, "path": 1.4, "pedestrian": 4}
# landuse class -> index (the game colours the terrain with these)
LANDUSE = {"grass": 1, "meadow": 1, "park": 1, "recreation_ground": 1, "pitch": 1, "golf_course": 1, "cemetery": 1,
           "farmland": 2, "farmyard": 2, "orchard": 2, "allotments": 2,
           "forest": 3, "wood": 3, "scrub": 3,
           "residential": 4, "commercial": 5, "retail": 5, "industrial": 6, "railway": 6, "construction": 6,
           "water": 7, "wetland": 8, "sand": 9, "beach": 9, "parking": 10}


def log(*a):
    print("[region]", *a, flush=True)


# ------------------------------------------------------------------ download
def fetch_overpass(bbox):
    s, w, n, e = bbox
    q = f"""[out:json][timeout:180];
(way["building"]({s},{w},{n},{e}); relation["building"]({s},{w},{n},{e});
 way["highway"]({s},{w},{n},{e}); way["railway"="rail"]({s},{w},{n},{e});
 way["natural"~"water|wood|scrub|wetland|beach|sand"]({s},{w},{n},{e}); relation["natural"="water"]({s},{w},{n},{e});
 way["waterway"~"riverbank|river|stream|canal"]({s},{w},{n},{e});
 way["landuse"]({s},{w},{n},{e}); relation["landuse"]({s},{w},{n},{e});
 way["leisure"~"park|pitch|golf_course|recreation_ground"]({s},{w},{n},{e}); way["amenity"="parking"]({s},{w},{n},{e});
 node["natural"="tree"]({s},{w},{n},{e}););
out geom;"""
    for url in ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"):
        try:
            log("Overpass:", url)
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
            return json.loads(urllib.request.urlopen(req, timeout=240).read())
        except Exception as ex:  # noqa: BLE001
            log("  failed:", ex)
    sys.exit("Overpass download failed (offline?)")


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n
    return x, y


class Dem:
    """AWS Terrain Tiles (terrarium): elevation = R*256 + G + B/256 - 32768 metres."""

    def __init__(self, bbox, tile_dir, z=13):
        self.z, self.tiles, self.dir = z, {}, tile_dir
        os.makedirs(tile_dir, exist_ok=True)
        s, w, n, e = bbox
        x0, y0 = tile_xy(n, w, z)
        x1, y1 = tile_xy(s, e, z)
        for tx in range(int(x0), int(x1) + 1):
            for ty in range(int(y0), int(y1) + 1):
                self.tiles[(tx, ty)] = self._load(tx, ty)

    def _load(self, tx, ty):
        p = os.path.join(self.dir, f"{self.z}_{tx}_{ty}.png")
        if not os.path.exists(p):
            url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{self.z}/{tx}/{ty}.png"
            try:
                data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
                open(p, "wb").write(data)
            except Exception as ex:  # noqa: BLE001
                log("DEM tile missing", tx, ty, ex)
                return None
        try:
            from PIL import Image
        except ImportError:
            sys.exit("Pillow needed for DEM tiles: sudo apt install python3-pil")
        a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float64)
        return a[:, :, 0] * 256.0 + a[:, :, 1] + a[:, :, 2] / 256.0 - 32768.0

    def height(self, lat, lon):
        x, y = tile_xy(lat, lon, self.z)
        t = self.tiles.get((int(x), int(y)))
        if t is None:
            return 0.0
        px, py = (x - int(x)) * 255.0, (y - int(y)) * 255.0
        i, j = min(int(px), 254), min(int(py), 254)
        fx, fy = px - i, py - j
        return float(t[j, i] * (1 - fx) * (1 - fy) + t[j, i + 1] * fx * (1 - fy) + t[j + 1, i] * (1 - fx) * fy + t[j + 1, i + 1] * fx * fy)


class FlatDem:
    def height(self, lat, lon):
        return 0.0


# ------------------------------------------------------------------ geometry helpers
class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))
        self.kz = 110540.0

    def xz(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * self.kz)

    def ll(self, x, z):
        return (self.lat0 - z / self.kz, self.lon0 + x / self.kx)


def area(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        a += x1 * z2 - x2 * z1
    return a * 0.5


def inside(pt, poly):
    x, z = pt
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / ((zj - zi) or 1e-12) + xi:
            c = not c
        j = i
    return c


def stitch(ways):
    """Join way geometries (lists of points) into closed rings by matching endpoints."""
    rings, open_ = [], [list(w) for w in ways if len(w) > 1]
    while open_:
        r = open_.pop()
        changed = True
        while changed and r[0] != r[-1]:
            changed = False
            for k, w in enumerate(open_):
                if w[0] == r[-1]:
                    r += w[1:]
                elif w[-1] == r[-1]:
                    r += w[::-1][1:]
                elif w[-1] == r[0]:
                    r = w[:-1] + r
                elif w[0] == r[0]:
                    r = w[::-1][:-1] + r
                else:
                    continue
                open_.pop(k)
                changed = True
                break
        if len(r) >= 4:
            rings.append(r)
    return rings


def rnd(seed, k=0):
    h = hashlib.md5(f"{seed}:{k}".encode()).digest()
    return int.from_bytes(h[:4], "little") / 2 ** 32


# ------------------------------------------------------------------ feature extraction
def num(v, default=None):
    try:
        return float(str(v).replace("m", "").replace(",", ".").split(";")[0].strip())
    except (TypeError, ValueError):
        return default


def building(el, poly, cdist):
    """Height / roof / material with Atlantic Canada defaults when tags are missing."""
    t = el.get("tags", {})
    kind = t.get("building", "yes")
    a = abs(area(poly))
    r = rnd(el["id"])
    levels = num(t.get("building:levels"))
    h = num(t.get("height"))
    roof = t.get("roof:shape", "")
    mat = t.get("building:material", "")
    if kind in ("church", "cathedral", "chapel") or t.get("amenity") == "place_of_worship":
        levels, roof, mat = levels or 3, roof or "gabled", mat or "brick"
        kind = "church"
    elif kind in ("house", "detached", "semidetached_house", "bungalow", "cabin", "residential", "terrace") or (
            kind == "yes" and a < 220 and cdist > 700):
        levels = levels or (1.0 if r < 0.35 else 2.0)
        roof, mat, kind = roof or ("gabled" if r < 0.85 else "hipped"), mat or "wood", "house"
    elif kind in ("garage", "garages", "shed", "carport", "roof"):
        levels, roof, mat = levels or 1, roof or "flat", mat or "wood"
    elif cdist < 900 and kind in ("yes", "commercial", "retail", "office", "apartments", "hotel", "civic", "public"):
        levels = levels or (3 + int(r * 4))           # downtown: 3-6 storey brick blocks
        roof, mat = roof or "flat", mat or "brick"
    elif kind in ("industrial", "warehouse", "retail", "supermarket", "commercial"):
        levels, roof, mat = levels or (1.5 if a > 1500 else 2), roof or "flat", mat or "metal"
    elif kind in ("apartments", "school", "university", "hospital", "college"):
        levels, roof, mat = levels or (3 + int(r * 2)), roof or "flat", mat or "brick"
    else:
        levels = levels or (2 if a < 400 else 3)
        roof, mat = roof or ("gabled" if a < 300 else "flat"), mat or ("wood" if a < 300 else "brick")
    wall = h if h else levels * 3.0 + 0.5
    if h and roof not in ("flat", ""):
        wall = h * 0.75
    out = {"p": [[round(x, 1), round(z, 1)] for x, z in poly], "h": round(wall, 1), "roof": roof, "mat": mat, "kind": kind}
    if kind == "church" and t.get("building") != "yes":
        out["steeple"] = True
    if t.get("building:colour"):
        out["col"] = t["building:colour"]
    return out


def scatter(poly, density, seed, cap=4000):
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    a = abs(area(poly))
    n = min(cap, int(a * density))
    pts, k = [], 0
    while len(pts) < n and k < n * 4:
        x = min(xs) + rnd(seed, 2 * k) * (max(xs) - min(xs))
        z = min(zs) + rnd(seed, 2 * k + 1) * (max(zs) - min(zs))
        k += 1
        if inside((x, z), poly):
            pts.append((x, z))
    return pts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", default="fredericton")
    ap.add_argument("--bbox", default="45.915,-66.705,46.005,-66.575", help="S,W,N,E")
    ap.add_argument("--osm", help="Overpass JSON (out geom); downloaded when missing")
    ap.add_argument("--dem-dir", help="terrarium tile cache dir")
    ap.add_argument("--flat-dem", action="store_true", help="no DEM (testing)")
    ap.add_argument("--out")
    ap.add_argument("--chunk", type=float, default=1000.0)
    ap.add_argument("--grid", type=float, default=30.0, help="terrain sample spacing, m")
    a = ap.parse_args()
    bbox = [float(v) for v in a.bbox.split(",")]
    s, w, n, e = bbox
    base_dir = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "filament-falcon", "assets", "regions")
    out = a.out or os.path.join(base_dir, a.name)
    os.makedirs(out, exist_ok=True)
    lat0, lon0 = (s + n) / 2, (w + e) / 2
    pj = Proj(lat0, lon0)
    osm_path = a.osm or os.path.join(out, "osm.json")
    if os.path.exists(osm_path):
        data = json.load(open(osm_path))
    else:
        data = fetch_overpass(bbox)
        json.dump(data, open(osm_path, "w"))
    dem = FlatDem() if a.flat_dem else Dem(bbox, a.dem_dir or os.path.join(out, "dem"))
    x0, z0 = pj.xz(n, w)
    x1, z1 = pj.xz(s, e)
    cs = a.chunk
    chunks = {}

    def chunk_of(x, z):
        k = f"{math.floor(x / cs)}_{math.floor(z / cs)}"
        if k not in chunks:
            chunks[k] = {"b": [], "t": [], "w": [], "r": [], "rl": [], "lu": []}
        return chunks[k]

    def geom(el):
        return [pj.xz(p["lat"], p["lon"]) for p in el.get("geometry", []) if p]

    big_water = []
    counts = {"buildings": 0, "trees": 0, "water": 0, "roads": 0, "rails": 0, "landuse": 0}
    for el in data.get("elements", []):
        t = el.get("tags", {})
        if el["type"] == "node":
            if t.get("natural") == "tree":
                x, z = pj.xz(el["lat"], el["lon"])
                chunk_of(x, z)["t"].append([round(x, 1), round(z, 1), 1 if t.get("leaf_type") == "needleleaved" else 0])
                counts["trees"] += 1
            continue
        if el["type"] == "relation":
            outers = [[pj.xz(p["lat"], p["lon"]) for p in m.get("geometry", []) if p]
                      for m in el.get("members", []) if m.get("role") in ("outer", "") and m.get("type") == "way"]
            polys = stitch(outers)
        else:
            g = geom(el)
            polys = [g] if len(g) >= 4 and g[0] == g[-1] else []
            line = g
        polys = [p[:-1] for p in polys if len(p) >= 4]
        if "building" in t:
            for p in polys:
                cx = sum(q[0] for q in p) / len(p)
                cz = sum(q[1] for q in p) / len(p)
                chunk_of(cx, cz)["b"].append(building(el, p, math.hypot(cx, cz)))
                counts["buildings"] += 1
            continue
        water = t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin")
        lu = LANDUSE.get(t.get("landuse") or t.get("natural") or t.get("leisure") or ("parking" if t.get("amenity") == "parking" else ""), 0)
        if water and polys:
            for p in polys:
                pr = [[round(x, 1), round(z, 1)] for x, z in p]
                if abs(area(p)) > cs * cs * 0.25:
                    big_water.append(pr)      # river / lakes: one shared file, always drawn
                else:
                    chunk_of(sum(q[0] for q in p) / len(p), sum(q[1] for q in p) / len(p))["w"].append(pr)
                counts["water"] += 1
            continue
        if lu and polys:
            for p in polys:
                cx = sum(q[0] for q in p) / len(p)
                cz = sum(q[1] for q in p) / len(p)
                chunk_of(cx, cz)["lu"].append([lu, [[round(x, 1), round(z, 1)] for x, z in p]])
                counts["landuse"] += 1
                if lu == 3 or (lu == 1 and t.get("leisure") == "park"):
                    dens = 1 / 70.0 if lu == 3 else 1 / 500.0
                    con = {"needleleaved": 1.0, "broadleaved": 0.0}.get(t.get("leaf_type"), 0.55 if lu == 3 else 0.2)
                    for k, (x, z) in enumerate(scatter(p, dens, el["id"])):
                        chunk_of(x, z)["t"].append([round(x, 1), round(z, 1), 1 if rnd(el["id"], 9000 + k) < con else 0])
                        counts["trees"] += 1
            continue
        if el["type"] != "way":
            continue
        line = geom(el)
        if len(line) < 2:
            continue
        hw = t.get("highway")
        if hw in ROAD_W or t.get("railway") == "rail" or t.get("waterway") in ("river", "stream", "canal"):
            if t.get("railway") == "rail":
                key, rec = "rl", {"w": 3.0}
                counts["rails"] += 1
            elif hw:
                lanes = num(t.get("lanes"))
                width = num(t.get("width")) or (lanes * 3.4 if lanes else ROAD_W[hw])
                key, rec = "r", {"w": round(width, 1), "c": hw}
                if t.get("bridge") in ("yes", "viaduct"):
                    rec["br"] = int(num(t.get("layer"), 1) or 1)
                counts["roads"] += 1
            else:
                if t.get("waterway") == "river":
                    continue        # rivers come from their area polygons
                key, rec = "r", {"w": 3.0, "c": "stream"}
            # split the line per chunk (consecutive segments that share a chunk)
            cur, ck = [], None
            for i in range(len(line) - 1):
                mx = (line[i][0] + line[i + 1][0]) / 2
                mz = (line[i][1] + line[i + 1][1]) / 2
                k = f"{math.floor(mx / cs)}_{math.floor(mz / cs)}"
                if k != ck and cur:
                    chunks[ck][key].append(dict(rec, p=cur))
                    cur = []
                if not cur:
                    cur = [[round(line[i][0], 1), round(line[i][1], 1)]]
                chunk_of(mx, mz)
                ck = k
                cur.append([round(line[i + 1][0], 1), round(line[i + 1][1], 1)])
            if cur:
                chunks[ck][key].append(dict(rec, p=cur))
    # terrain grid per chunk (every chunk inside the bbox, even empty ones)
    ix0, ix1 = math.floor(x0 / cs), math.floor(x1 / cs)
    iz0, iz1 = math.floor(z0 / cs), math.floor(z1 / cs)
    gn = int(cs / a.grid) + 1
    heights = {}
    for ix in range(ix0, ix1 + 1):
        for iz in range(iz0, iz1 + 1):
            g = np.zeros((gn, gn))
            for j in range(gn):
                for i in range(gn):
                    lat, lon = pj.ll(ix * cs + i * cs / (gn - 1), iz * cs + j * cs / (gn - 1))
                    g[j, i] = dem.height(lat, lon)
            heights[(ix, iz)] = g
    base = float(min(np.min(g) for g in heights.values())) if heights else 0.0
    names = []
    for (ix, iz), g in heights.items():
        k = f"{ix}_{iz}"
        c = chunks.get(k, {"b": [], "t": [], "w": [], "r": [], "rl": [], "lu": []})
        c["o"] = [ix * cs, iz * cs]
        c["n"] = gn
        c["h"] = [int(round((v - base) * 10)) for v in g.flatten()]   # decimetres above base
        json.dump(c, open(os.path.join(out, f"c_{k}.json"), "w"), separators=(",", ":"))
        names.append(k)
    json.dump(big_water, open(os.path.join(out, "water.json"), "w"), separators=(",", ":"))
    man = {"name": a.name, "bbox": bbox, "lat0": lat0, "lon0": lon0, "chunk": cs, "base_elev": base,
           "extent": [x0, z0, x1, z1], "chunks": names, "counts": counts, "version": 1}
    json.dump(man, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    log(f"{a.name}: {len(names)} chunks, {counts} -> {out}")


if __name__ == "__main__":
    main()
