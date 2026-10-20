#!/usr/bin/env python3
"""Build a low-altitude detail region for The Filament Falcon from OpenStreetMap + a DEM.

    python3 tools/build_region.py --region fredericton          # preset (see --list)
    python3 tools/build_region.py --name NAME --bbox S,W,N,E     # anything inside the .pbf
            [--pbf-url URL] [--source pbf|overpass] [--osm file.json] [--jobs N] [--force]

OSM source (default): the Geofabrik New Brunswick extract (~65 MB), downloaded once into
~/.local/share/filament-falcon/osm/ and refreshed only when older than 30 days (If-Modified-
Since / Last-Modified check: unchanged = no re-download). Parsed locally with pyosmium
(sudo apt install python3-osmium osmium-tool, or pip install osmium); with osmium-tool the
region is first cut out of the .pbf in a second. Every city in the province builds from the
same file. --source overpass (or no pyosmium) falls back to the Overpass API.

Caches (all under ~/.local/share/filament-falcon/):
    osm/<file>.osm.pbf + .meta.json      the provincial extract
    osm/extract_<name>_<key>.json.gz     the region's features (per .pbf version + bbox)
    dem/terrarium/13/<x>_<y>.png         AWS Terrain Tiles (shared by all regions)
    assets/regions/<name>/               chunk JSON + manifest.json (build_key: inputs + BUILD_VER;
                                         an up-to-date region is not rebuilt)
Chunks are built in parallel (--jobs, default = CPU count). Output per chunk: terrain grid
(heights + per-vertex landuse class), buildings, trees, water, roads, rails, all in local
metres (x = east, z = south, y = up). The game (scripts/geo/region_view.gd) turns chunks into
meshes on worker threads and streams them by distance.
"""
import argparse, gzip, json, math, os, shutil, subprocess, sys, time, urllib.error, urllib.request, urllib.parse, io, hashlib
from email.utils import formatdate, parsedate_to_datetime

import numpy as np

BUILD_VER = 2          # bump when the chunk format / feature rules change (forces rebuilds)
DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "filament-falcon")
PBF_URL = "https://download.geofabrik.de/north-america/canada/new-brunswick-latest.osm.pbf"
MAX_AGE_DAYS = 30
# ~10 x 10 km around each centre (S, W, N, E)
PRESETS = {"fredericton": (45.915, -66.705, 46.005, -66.575), "moncton": (46.045, -64.865, 46.135, -64.735),
           "saint-john": (45.225, -66.125, 45.315, -65.995), "dieppe": (46.055, -64.775, 46.12, -64.665),
           "bathurst": (47.585, -65.715, 47.655, -65.595), "miramichi": (46.985, -65.635, 47.055, -65.505),
           "edmundston": (47.335, -68.385, 47.405, -68.265), "sackville": (45.875, -64.405, 45.925, -64.335),
           "campbellton": (47.975, -66.725, 48.025, -66.625), "oromocto": (45.81, -66.52, 45.87, -66.42)}
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
    """AWS Terrain Tiles (terrarium): elevation = R*256 + G + B/256 - 32768 metres. Tiles are cached
    once in ~/.local/share/filament-falcon/dem/terrarium/<z>/ and shared by every region."""

    def __init__(self, bbox, tile_dir, z=13):
        self.z, self.tiles, self.dir = z, {}, tile_dir
        os.makedirs(tile_dir, exist_ok=True)
        s, w, n, e = bbox
        x0, y0 = tile_xy(n, w, z)
        x1, y1 = tile_xy(s, e, z)
        got = 0
        for tx in range(int(x0), int(x1) + 1):
            for ty in range(int(y0), int(y1) + 1):
                self.tiles[(tx, ty)], new = self._load(tx, ty)
                got += new
        log(f"DEM: {len(self.tiles)} tiles ({got} downloaded, rest cached in {tile_dir})")

    def _load(self, tx, ty):
        p = os.path.join(self.dir, f"{tx}_{ty}.png")
        new = 0
        if not os.path.exists(p):
            url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{self.z}/{tx}/{ty}.png"
            try:
                data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
                open(p + ".part", "wb").write(data)
                os.replace(p + ".part", p)
                new = 1
            except Exception as ex:  # noqa: BLE001
                log("DEM tile missing", tx, ty, ex)
                return None, 0
        try:
            from PIL import Image
        except ImportError:
            sys.exit("Pillow needed for DEM tiles: sudo apt install python3-pil")
        a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float64)
        return a[:, :, 0] * 256.0 + a[:, :, 1] + a[:, :, 2] / 256.0 - 32768.0, new

    def heights(self, lats, lons):
        """Bilinear heights for arrays of lat/lon (vectorised per tile)."""
        lats, lons = np.asarray(lats, dtype=np.float64), np.asarray(lons, dtype=np.float64)
        n = 2 ** self.z
        x = (lons + 180.0) / 360.0 * n
        y = (1.0 - np.arcsinh(np.tan(np.radians(lats))) / np.pi) / 2.0 * n
        tx, ty = np.floor(x).astype(int), np.floor(y).astype(int)
        out = np.zeros(lats.shape)
        for key in set(zip(tx.ravel().tolist(), ty.ravel().tolist())):
            t = self.tiles.get(key)
            if t is None:
                continue
            m = (tx == key[0]) & (ty == key[1])
            px, py = (x[m] - key[0]) * 255.0, (y[m] - key[1]) * 255.0
            i, j = np.minimum(px.astype(int), 254), np.minimum(py.astype(int), 254)
            fx, fy = px - i, py - j
            out[m] = t[j, i] * (1 - fx) * (1 - fy) + t[j, i + 1] * fx * (1 - fy) + t[j + 1, i] * (1 - fx) * fy + t[j + 1, i + 1] * fx * fy
        return out

    def height(self, lat, lon):
        return float(self.heights(np.array([lat]), np.array([lon]))[0])


class FlatDem:
    def height(self, lat, lon):
        return 0.0

    def heights(self, lats, lons):
        return np.zeros(np.asarray(lats).shape)



# ------------------------------------------------------------------ OSM .pbf (Geofabrik) + pyosmium
def ensure_pbf(url, osm_dir, max_age_days=MAX_AGE_DAYS):
    """Download the provincial extract once; afterwards only when the copy is older than
    max_age_days AND the server has a newer one (If-Modified-Since / Last-Modified)."""
    os.makedirs(osm_dir, exist_ok=True)
    path = os.path.join(osm_dir, url.rsplit("/", 1)[-1])
    meta_p = path + ".meta.json"
    meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
    have = os.path.exists(path) and os.path.getsize(path) > 1000
    if have and time.time() - meta.get("checked", os.path.getmtime(path)) < max_age_days * 86400:
        log(f"OSM: {path} ({os.path.getsize(path) / 1e6:.0f} MB, checked {(time.time() - meta.get('checked', 0)) / 86400:.0f} d ago, refresh after {max_age_days} d)")
        return path
    hdr = dict(UA)
    if have:
        hdr["If-Modified-Since"] = meta.get("last_modified") or formatdate(os.path.getmtime(path), usegmt=True)
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=60)
        lm = r.headers.get("Last-Modified", "")
        if have and lm and lm == meta.get("last_modified"):
            r.close()
            raise urllib.error.HTTPError(url, 304, "same Last-Modified", None, None)
        total = int(r.headers.get("Content-Length", 0) or 0)
        log(f"OSM: downloading {url} ({total / 1e6:.0f} MB, once; cached in {osm_dir})")
        done, t0 = 0, time.time()
        with open(path + ".part", "wb") as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
                done += len(b)
                if total and time.time() - t0 > 2:
                    print(f"\r  {done / 1e6:.0f}/{total / 1e6:.0f} MB", end="", flush=True)
        print()
        if total and done < total:
            raise IOError(f"short download {done}/{total}")
        os.replace(path + ".part", path)
        meta = {"last_modified": lm, "size": done, "url": url}
    except urllib.error.HTTPError as ex:
        if ex.code != 304 or not have:
            if not have:
                sys.exit(f"OSM download failed: {ex}")
            log(f"OSM: refresh failed ({ex}), using the cached copy")
        else:
            log("OSM: server copy unchanged (304), keeping the cached file")
    except Exception as ex:  # noqa: BLE001
        if not have:
            sys.exit(f"OSM download failed (offline?): {ex}")
        log(f"OSM: offline ({ex}), using the cached copy")
    meta["checked"] = time.time()
    json.dump(meta, open(meta_p, "w"))
    return path


POLY_KEYS = ("building", "landuse", "natural", "leisure", "amenity", "waterway")


def _keep_area(t):
    return ("building" in t or "landuse" in t or t.get("natural") in ("water", "wood", "scrub", "wetland", "beach", "sand")
            or t.get("waterway") == "riverbank" or t.get("leisure") in ("park", "pitch", "golf_course", "recreation_ground")
            or t.get("amenity") == "parking")


def _keep_line(t):
    return t.get("highway") in ROAD_W or t.get("railway") == "rail" or t.get("waterway") in ("river", "stream", "canal")


def read_pbf(pbf, bbox):
    """Features inside bbox (with a margin) from a .pbf, in the same element format as Overpass
    `out geom` (+ type "area" with assembled outer rings for (multi)polygons)."""
    try:
        import osmium
    except ImportError:
        return None
    s, w, n, e = bbox
    mg = 0.01
    src = pbf
    tmp = None
    if shutil.which("osmium"):          # osmium-tool: cut the bbox out in C++ first (fast)
        tmp = pbf + f".cut_{abs(hash(tuple(bbox))) % 10**8}.osm.pbf"
        cmd = ["osmium", "extract", "-b", f"{w - mg},{s - mg},{e + mg},{n + mg}", "-s", "smart", "--overwrite", "-o", tmp, pbf]
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            src = tmp
        else:
            tmp = None
    log(f"OSM: parsing {os.path.basename(src)} with pyosmium{' (bbox cut by osmium-tool)' if tmp else ' (whole file; apt install osmium-tool makes this faster)'}")

    def inb(lat, lon):
        return s - mg <= lat <= n + mg and w - mg <= lon <= e + mg

    out = []

    class H(osmium.SimpleHandler):
        def node(self, o):
            if o.tags.get("natural") == "tree" and o.location.valid() and inb(o.location.lat, o.location.lon):
                out.append({"type": "node", "id": o.id, "lat": o.location.lat, "lon": o.location.lon, "tags": {t.k: t.v for t in o.tags}})

        def way(self, o):
            t = o.tags
            if not (t.get("highway") or t.get("railway") or t.get("waterway")):
                return
            tags = {x.k: x.v for x in t}
            if not _keep_line(tags):
                return
            g = [{"lat": nd.lat, "lon": nd.lon} for nd in o.nodes if nd.location.valid()]
            if any(inb(p["lat"], p["lon"]) for p in g):
                out.append({"type": "way", "id": o.id, "tags": tags, "geometry": g})

        def area(self, o):
            t = o.tags
            if not any(k in t for k in POLY_KEYS):
                return
            tags = {x.k: x.v for x in t}
            if not _keep_area(tags):
                return
            rings = []
            for ring in o.outer_rings():
                r = [[nd.lat, nd.lon] for nd in ring if nd.location.valid()]
                if len(r) >= 4 and any(inb(p[0], p[1]) for p in r):
                    rings.append(r)
            if rings:
                out.append({"type": "area", "id": o.orig_id(), "tags": tags, "rings": rings})

    H().apply_file(src, locations=True)
    if tmp and os.path.exists(tmp):
        os.remove(tmp)
    return {"elements": out}


def file_key(*parts):
    return hashlib.sha1(json.dumps(parts, sort_keys=True).encode()).hexdigest()[:12]


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


def grid_points_in_poly(xs, zs, poly):
    """Vectorised even-odd point-in-polygon for grid points (xs, zs arrays)."""
    c = np.zeros(xs.shape, dtype=bool)
    p = np.asarray(poly, dtype=np.float64)
    xj, zj = p[-1]
    for xi, zi in p:
        cond = ((zi > zs) != (zj > zs)) & (xs < (xj - xi) * (zs - zi) / ((zj - zi) or 1e-12) + xi)
        c ^= cond
        xj, zj = xi, zi
    return c


# Worker globals (fork: inherited, never pickled)
_G = {}


def _build_chunk(job):
    """Terrain heights + per-vertex landuse for one chunk, written as c_<ix>_<iz>.json."""
    ix, iz = job
    pj, dem, cs, gn, out = _G["pj"], _G["dem"], _G["cs"], _G["gn"], _G["out"]
    xs = ix * cs + np.arange(gn) * cs / (gn - 1)
    zs = iz * cs + np.arange(gn) * cs / (gn - 1)
    X, Z = np.meshgrid(xs, zs)
    lat, lon = pj.ll(X, Z)
    h = dem.heights(lat, lon)
    lg = np.zeros(X.shape, dtype=np.int16)
    x0, x1, z0, z1 = ix * cs, (ix + 1) * cs, iz * cs, (iz + 1) * cs
    for cls, bb, poly in _G["lu"]:     # every landuse polygon touching the chunk (not just its centroid's)
        if bb[0] > x1 or bb[2] < x0 or bb[1] > z1 or bb[3] < z0:
            continue
        lg[grid_points_in_poly(X, Z, poly)] = cls
    k = f"{ix}_{iz}"
    c = dict(_G["chunks"].get(k, {"b": [], "t": [], "w": [], "r": [], "rl": []}))
    c.pop("lu", None)
    c["o"] = [ix * cs, iz * cs]
    c["n"] = gn
    c["h"] = h.ravel().tolist()      # metres (rebased to the region base in finish())
    c["lg"] = lg.ravel().tolist()
    return k, c


def _write_chunk(args):
    k, c, base = args
    c["h"] = [int(round((v - base) * 10)) for v in c["h"]]   # decimetres above base
    json.dump(c, open(os.path.join(_G["out"], f"c_{k}.json"), "w"), separators=(",", ":"))
    return k


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", help="preset city: " + ", ".join(PRESETS))
    ap.add_argument("--name", help="region folder name (default: --region or 'fredericton')")
    ap.add_argument("--bbox", help="S,W,N,E (overrides the preset)")
    ap.add_argument("--list", action="store_true", help="list the presets")
    ap.add_argument("--source", choices=["pbf", "overpass"], default="pbf")
    ap.add_argument("--pbf-url", default=PBF_URL)
    ap.add_argument("--osm", help="Overpass JSON (out geom) to use instead of downloading")
    ap.add_argument("--dem-dir", help="terrarium tile cache dir (default: shared cache)")
    ap.add_argument("--flat-dem", action="store_true", help="no DEM (testing)")
    ap.add_argument("--out")
    ap.add_argument("--chunk", type=float, default=1000.0)
    ap.add_argument("--grid", type=float, default=30.0, help="terrain sample spacing, m")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--force", action="store_true", help="rebuild even when up to date")
    a = ap.parse_args()
    if a.list:
        for k, v in PRESETS.items():
            print(f"{k:12s} {','.join(str(x) for x in v)}")
        return
    name = a.name or a.region or "fredericton"
    if a.bbox:
        bbox = [float(v) for v in a.bbox.split(",")]
    elif (a.region or name) in PRESETS:
        bbox = list(PRESETS[a.region or name])
    else:
        sys.exit(f"unknown region '{a.region or name}': give --bbox S,W,N,E or one of {', '.join(PRESETS)}")
    s, w, n, e = bbox
    out = a.out or os.path.join(DATA, "assets", "regions", name)
    os.makedirs(out, exist_ok=True)
    t_start = time.time()
    lat0, lon0 = (s + n) / 2, (w + e) / 2
    pj = Proj(lat0, lon0)
    # ---- OSM features (cached per source version + bbox)
    osm_dir = os.path.join(DATA, "osm")
    if a.osm:
        src_id = ["file", os.path.abspath(a.osm), os.path.getmtime(a.osm)]
        loader = lambda: json.load(open(a.osm))  # noqa: E731
    elif a.source == "pbf":
        try:
            import osmium  # noqa: F401
            pbf = ensure_pbf(a.pbf_url, osm_dir)
            src_id = ["pbf", os.path.basename(pbf), os.path.getsize(pbf), int(os.path.getmtime(pbf))]
            loader = lambda: read_pbf(pbf, bbox)  # noqa: E731
        except ImportError:
            log("pyosmium missing (sudo apt install python3-osmium osmium-tool, or pip install osmium): falling back to Overpass")
            a.source = "overpass"
    if not a.osm and a.source == "overpass":
        src_id = ["overpass", time.strftime("%Y-%m")]          # re-query at most monthly
        loader = lambda: fetch_overpass(bbox)  # noqa: E731
    fkey = file_key(src_id, bbox, BUILD_VER)
    bkey = file_key(fkey, a.chunk, a.grid, a.flat_dem, BUILD_VER)
    mf = os.path.join(out, "manifest.json")
    if not a.force and os.path.exists(mf):
        old = json.load(open(mf))
        if old.get("build_key") == bkey and all(os.path.exists(os.path.join(out, f"c_{k}.json")) for k in old.get("chunks", [])):
            log(f"{name}: up to date ({len(old['chunks'])} chunks in {out}; --force rebuilds)")
            return
    os.makedirs(osm_dir, exist_ok=True)
    ex_path = os.path.join(osm_dir, f"extract_{name}_{fkey}.json.gz")
    if os.path.exists(ex_path):
        data = json.load(gzip.open(ex_path, "rt"))
        log(f"OSM: cached extract {ex_path}")
    else:
        data = loader()
        for f in os.listdir(osm_dir):          # drop stale extracts of this region
            if f.startswith(f"extract_{name}_") and f != os.path.basename(ex_path):
                os.remove(os.path.join(osm_dir, f))
        with gzip.open(ex_path + ".part", "wt") as f:
            json.dump(data, f, separators=(",", ":"))
        os.replace(ex_path + ".part", ex_path)
    t_osm = time.time()
    dem = FlatDem() if a.flat_dem else Dem(bbox, a.dem_dir or os.path.join(DATA, "dem", "terrarium", "13"))
    x0, z0 = pj.xz(n, w)
    x1, z1 = pj.xz(s, e)
    cs = a.chunk
    chunks = {}

    def chunk_of(x, z):
        k = f"{math.floor(x / cs)}_{math.floor(z / cs)}"
        if k not in chunks:
            chunks[k] = {"b": [], "t": [], "w": [], "r": [], "rl": []}
        return chunks[k]

    def geom(el):
        return [pj.xz(p["lat"], p["lon"]) for p in el.get("geometry", []) if p]

    big_water, lu_polys = [], []
    counts = {"buildings": 0, "trees": 0, "water": 0, "roads": 0, "rails": 0, "landuse": 0}
    for el in data.get("elements", []):
        t = el.get("tags", {})
        if el["type"] == "node":
            if t.get("natural") == "tree":
                x, z = pj.xz(el["lat"], el["lon"])
                chunk_of(x, z)["t"].append([round(x, 1), round(z, 1), 1 if t.get("leaf_type") == "needleleaved" else 0])
                counts["trees"] += 1
            continue
        if el["type"] == "area":
            polys = [[pj.xz(p[0], p[1]) for p in r] for r in el["rings"]]
            polys = [p if p[0] == p[-1] else p + [p[0]] for p in polys]
        elif el["type"] == "relation":
            outers = [[pj.xz(p["lat"], p["lon"]) for p in m.get("geometry", []) if p]
                      for m in el.get("members", []) if m.get("role") in ("outer", "") and m.get("type") == "way"]
            polys = stitch(outers)
        else:
            g = geom(el)
            polys = [g] if len(g) >= 4 and g[0] == g[-1] and not _keep_line(t) else []
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
                xs = [q[0] for q in p]
                zs = [q[1] for q in p]
                lu_polys.append((lu, (min(xs), min(zs), max(xs), max(zs)), p))
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
    # ---- chunks in parallel: terrain grid + landuse classes, then rebase heights and write
    ix0, ix1 = math.floor(x0 / cs), math.floor(x1 / cs)
    iz0, iz1 = math.floor(z0 / cs), math.floor(z1 / cs)
    gn = int(cs / a.grid) + 1
    _G.update(pj=pj, dem=dem, cs=cs, gn=gn, out=out, chunks=chunks, lu=lu_polys)
    jobs = [(ix, iz) for ix in range(ix0, ix1 + 1) for iz in range(iz0, iz1 + 1)]
    import multiprocessing as mp
    nj = max(1, min(a.jobs, len(jobs)))
    if nj > 1:
        with mp.get_context("fork").Pool(nj) as pool:
            built = pool.map(_build_chunk, jobs, chunksize=max(1, len(jobs) // (nj * 4)))
    else:
        built = [_build_chunk(j) for j in jobs]
    base = float(min(min(c["h"]) for _, c in built)) if built else 0.0
    for f in os.listdir(out):                 # stale chunks from an older build
        if f.startswith("c_") and f.endswith(".json"):
            os.remove(os.path.join(out, f))
    if nj > 1:
        with mp.get_context("fork").Pool(nj) as pool:
            names = pool.map(_write_chunk, [(k, c, base) for k, c in built])
    else:
        names = [_write_chunk((k, c, base)) for k, c in built]
    json.dump(big_water, open(os.path.join(out, "water.json"), "w"), separators=(",", ":"))
    man = {"name": name, "bbox": bbox, "lat0": lat0, "lon0": lon0, "chunk": cs, "base_elev": base,
           "extent": [x0, z0, x1, z1], "chunks": names, "counts": counts, "version": BUILD_VER, "build_key": bkey,
           "source": src_id[0]}
    json.dump(man, open(mf, "w"), indent=1)
    log(f"{name}: {len(names)} chunks, {counts} -> {out}  (OSM {t_osm - t_start:.1f} s, build {time.time() - t_osm:.1f} s, {nj} jobs)")


if __name__ == "__main__":
    main()
