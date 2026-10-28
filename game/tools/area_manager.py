#!/usr/bin/env python3
"""Area manager for The Filament Falcon's real-size Earth: pick areas, see what they cost,
pre-download and pre-generate them on THIS PC, check the cache, cancel, delete.

    python3 tools/area_manager.py presets                       # built-in areas
    python3 tools/area_manager.py estimate fredericton          # sizes before downloading
    python3 tools/area_manager.py estimate --center 45.96,-66.64 --radius 8
    python3 tools/area_manager.py add fredericton [--steps dem,imagery,osm,build] [--run]
    python3 tools/area_manager.py add --id home --center 45.96,-66.64 --radius 5 --run
    python3 tools/area_manager.py add --id cape --bbox 28.40,-80.78,28.66,-80.52
    python3 tools/area_manager.py status [--json]               # areas, state, progress, disk use
    python3 tools/area_manager.py run [--json]                  # start the background runner (checks it started)
    python3 tools/area_manager.py run --wait                    # work the queue in this terminal
    python3 tools/area_manager.py cancel ID | delete ID [--purge-tiles]
    python3 tools/area_manager.py maplayer [--json]             # AREAS map roads / rivers / names (tools/map_layer.py, background)
    python3 tools/area_manager.py add --id nb --bbox 45.5,-67.3,46.4,-66.0 --fit split   # > 120 km

Area selection: a preset (tools/area_presets.json), an existing area id (any id you created,
e.g. from the Commander map: area_45_964_-66_643), --bbox S,W,N,E, or --center LAT,LON
--radius KM (the Commander AREAS page also lets you drag a box on the map). Ids are normalised
(lower case, anything but letters / digits / - / _ becomes _), so "area_45.964_-66.643" and
"area_45_964_-66_643" are the same area. Areas larger than 120 km a side: --fit clamp (a 120 km
box around the centre) or --fit split (tiled into <=120 km areas <id>_r<row>c<col>, all queued).
`cancel` and `delete` are idempotent (deleting a gone area is fine; deleting a running area
cancels it and the runner removes it when the step stops).


Steps (default: all four):
  dem      AWS Terrain Tiles (terrarium, zoom 13, ~20 m) -> areas/<id>/dem.bin (int16, 0.5 m units)
  imagery  EOX Sentinel-2 cloudless (zoom <= 13, ~10-20 m) -> areas/<id>/image.jpg
           ("Sentinel-2 cloudless - https://s2maps.eu by EOX IT Services GmbH (Contains modified
           Copernicus Sentinel data)", CC BY-NC-SA 4.0: personal / non-commercial use)
  osm      the smallest Geofabrik regional extract that contains the area (NOT the planet file),
           found in Geofabrik's index-v1.json; shared by every area inside it, refreshed monthly
  build    tools/build_region.py on that extract -> assets/regions/<id>/ (the full 3D detail:
           buildings, roads, trees, water) + the water mask areas/<id>/water.bin

The game reads finished areas on the fly: areas/<id>/area.json ("pack") + dem.bin + water.bin
+ image.jpg give the planet terrain real heights, water and imagery anywhere (even without the
OSM build); a built region adds the 3D detail when you fly low over it. Ungenerated places fall
back to the global DEM + Blue Marble imagery from tools/fetch_assets.sh.

Everything lives under ~/.local/share/filament-falcon/:
    areas/<id>/area.json, status.json, dem.bin, water.bin, image.jpg   per-area pack + job state
    areas/queue/<time>_<id>.json                                      pending jobs
    dem/terrarium/13/, imagery/s2cloudless/<z>/                         shared tile caches
    osm/<extract>.osm.pbf, osm/geofabrik-index.json                     extracts (shared)
    assets/regions/<id>/                                                built 3D regions
Jobs run one at a time in a single background runner (`run --wait`; areas/runner.lock is
flock()ed while it lives, so a killed runner never leaves a stale lock; runner.json = its job /
step / bytes / heartbeat, runner.log = its output; jobs a dead runner left 'running' are resumed
first; `status` says why a queued job is not moving); `cancel` stops the
running step within a few seconds, `delete` removes the pack + region (the shared tile and
extract caches stay; --purge-tiles also drops this area's tiles that no other area uses).
"""
import argparse, fcntl, glob, io, json, math, os, shutil, signal, subprocess, sys, time, urllib.error, urllib.request
from email.utils import formatdate

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:                     # numpy is needed by the jobs, not by status / run / cancel (those report it missing)
    import numpy as np  # noqa: E402
except ImportError:      # pragma: no cover
    np = None

DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "filament-falcon")
AREAS = os.path.join(DATA, "areas")
QUEUE = os.path.join(AREAS, "queue")
REGIONS = os.path.join(DATA, "assets", "regions")
DEM_DIR = os.path.join(DATA, "dem", "terrarium", "13")
IMG_DIR = os.path.join(DATA, "imagery", "s2cloudless")
OSM_DIR = os.path.join(DATA, "osm")
PACK_VER = 1                    # scripts/geo/earth_terrain.gd PACK_VER
STEPS = ["dem", "imagery", "osm", "build"]
GEOFABRIK_INDEX = "https://download.geofabrik.de/index-v1.json"
EOX_URL = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2020_3857/default/g/{z}/{y}/{x}.jpg"
TERRARIUM_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/13/{x}/{y}.png"
UA = {"User-Agent": "FilamentFalcon/1.0 (home cockpit sim; github.com/whyvas/filament-falcon)"}
# average bytes per tile (for estimates before downloading)
AVG_DEM_TILE, AVG_IMG_TILE = 95_000, 32_000
MAX_KM = 120.0                  # largest side of one area (bigger = split it)
IMG_MAX_TILES = 1600
ATTRIB = "Sentinel-2 cloudless - https://s2maps.eu by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2020), CC BY-NC-SA 4.0"


def log(*a):
    print(time.strftime("%H:%M:%S"), "[area]", *a, flush=True)


# ------------------------------------------------------------------ dependencies
DEP_HINT = {"numpy": "sudo apt install python3-numpy", "PIL": "sudo apt install python3-pil",
            "osmium": "pip install --user --break-system-packages osmium (or ./setup.sh)",
            "osmium_tool": "sudo apt install osmium-tool"}
STEP_NEEDS = {"dem": ["numpy", "PIL"], "imagery": ["numpy", "PIL"], "osm": [], "build": ["numpy"]}


def deps():
    """{module: importable} for what the jobs use (+ the osmium command line tool)."""
    d = {}
    for m in ("numpy", "PIL", "osmium"):
        try:
            __import__(m)
            d[m] = True
        except Exception:  # noqa: BLE001
            d[m] = False
    d["osmium_tool"] = bool(shutil.which("osmium"))
    return d


def missing_for(steps, d=None):
    d = d or deps()
    return sorted({m for st in steps for m in STEP_NEEDS.get(st, []) if not d.get(m)})


def dep_msg(miss):
    return "missing python module(s): " + ", ".join(miss) + " (" + "; ".join(DEP_HINT[m] for m in miss) + ")"


def presets():
    return json.load(open(os.path.join(HERE, "area_presets.json")))


def tile_xy(lat, lon, z):
    n = 2 ** z
    return ((lon + 180.0) / 360.0 * n, (1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)


def tiles_for(bbox, z):
    s, w, n, e = bbox
    x0, y0 = tile_xy(n, w, z)
    x1, y1 = tile_xy(s, e, z)
    return [(x, y) for x in range(int(x0), int(x1) + 1) for y in range(int(y0), int(y1) + 1)]


def bbox_km(bbox):
    s, w, n, e = bbox
    return (e - w) * 111.32 * math.cos(math.radians((s + n) / 2)), (n - s) * 110.54


def img_zoom(bbox):
    z = 13
    while z > 8 and len(tiles_for(bbox, z)) > IMG_MAX_TILES:
        z -= 1
    return z


def norm_id(aid):
    return "".join(c if c.isalnum() or c in "-_" else "_" for c in str(aid).strip().lower())


def area_json(aid):
    try:
        return json.load(open(os.path.join(AREAS, aid, "area.json")))
    except Exception:  # noqa: BLE001
        return None


def parse_area(a, fit=None):
    """(id, name, bbox) from an existing area id, a preset name or --bbox / --center + --radius."""
    if a.preset and not a.bbox and not a.center:
        m = area_json(norm_id(a.preset))
        if m is not None and "bbox" in m:       # the registry first: custom ids (map boxes, --id) work everywhere
            return norm_id(a.preset), m.get("name", a.preset), list(m["bbox"])
    if a.bbox:
        bbox = [float(v) for v in a.bbox.split(",")]
        aid, name = a.id or a.preset or "area_%.3f_%.3f" % ((bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2), a.name
    elif a.center:
        lat, lon = (float(v) for v in a.center.split(","))
        r = float(a.radius or 5.0)
        dlat, dlon = r / 110.54, r / (111.32 * max(math.cos(math.radians(lat)), 0.05))
        bbox = [lat - dlat, lon - dlon, lat + dlat, lon + dlon]
        aid, name = a.id or a.preset or "area_%.3f_%.3f" % (lat, lon), a.name
    elif a.preset:
        p = presets().get(a.preset) or presets().get(norm_id(a.preset))
        if p is None:
            known = sorted(set(presets()) | set(existing()))
            sys.exit(f"unknown area '{a.preset}': one of {', '.join(known)}, or --bbox / --center")
        bbox, aid, name = list(p["bbox"]), a.id or a.preset, a.name or p["name"]
    else:
        sys.exit("give a preset name, --bbox S,W,N,E or --center LAT,LON --radius KM")
    bbox = [round(v, 5) for v in bbox]
    s, w, n, e = bbox
    if not (-85 < s < n < 85 and -180 <= w < e <= 180):
        sys.exit(f"bad bbox {bbox}")
    aid = norm_id(aid)
    return aid, name or aid, bbox


def fit_area(aid, name, bbox, fit):
    """[(id, name, bbox)] no side over MAX_KM: as is, clamped around the centre, or tiled."""
    wkm, hkm = bbox_km(bbox)
    if max(wkm, hkm) <= MAX_KM + 0.01:
        return [(aid, name, bbox)]
    s, w, n, e = bbox
    if fit == "clamp":
        cl, cn = (s + n) / 2, (w + e) / 2
        dl = min(n - s, MAX_KM / 110.54) / 2
        dn = min(e - w, MAX_KM / (111.32 * max(math.cos(math.radians(cl)), 0.05))) / 2
        return [(aid, name, [round(cl - dl, 5), round(cn - dn, 5), round(cl + dl, 5), round(cn + dn, 5)])]
    if fit == "split":
        nc, nr = math.ceil(wkm / MAX_KM), math.ceil(hkm / MAX_KM)
        if nc * nr > 64:
            sys.exit(f"area too big to split ({wkm:.0f} x {hkm:.0f} km = {nc * nr} tiles, max 64)")
        out = []
        for r in range(nr):
            for c in range(nc):
                bb = [round(s + (n - s) * r / nr, 5), round(w + (e - w) * c / nc, 5),
                      round(s + (n - s) * (r + 1) / nr, 5), round(w + (e - w) * (c + 1) / nc, 5)]
                out.append((f"{aid}_r{r}c{c}", f"{name} [{r},{c}]", bb))
        return out
    sys.exit(f"area too big ({max(wkm, hkm):.0f} km side, max {MAX_KM:.0f}): add --fit clamp "
             f"(a {MAX_KM:.0f} km box around the centre) or --fit split "
             f"({math.ceil(wkm / MAX_KM) * math.ceil(hkm / MAX_KM)} areas of <= {MAX_KM:.0f} km)")


def existing():
    if not os.path.isdir(AREAS):
        return []
    return sorted(d for d in os.listdir(AREAS) if os.path.exists(os.path.join(AREAS, d, "area.json")))


# ------------------------------------------------------------------ Geofabrik extract
def _point_in_ring(x, y, ring):
    c = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-300) + xi:
            c = not c
        j = i
    return c


def _in_geom(lon, lat, geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    for poly in polys:
        if _point_in_ring(lon, lat, poly[0]) and not any(_point_in_ring(lon, lat, h) for h in poly[1:]):
            return True
    return False


def geofabrik_index(offline=False):
    p = os.path.join(OSM_DIR, "geofabrik-index.json")
    if os.path.exists(p) and (offline or time.time() - os.path.getmtime(p) < 30 * 86400):
        return json.load(open(p))
    if offline:
        return None
    try:
        log("Geofabrik index:", GEOFABRIK_INDEX)
        data = urllib.request.urlopen(urllib.request.Request(GEOFABRIK_INDEX, headers=UA), timeout=60).read()
        os.makedirs(OSM_DIR, exist_ok=True)
        open(p + ".part", "wb").write(data)
        os.replace(p + ".part", p)
        return json.loads(data)
    except Exception as ex:  # noqa: BLE001
        if os.path.exists(p):
            return json.load(open(p))
        log("Geofabrik index unavailable:", ex)
        return None


def pick_extracts(bbox, offline=False):
    """The Geofabrik extract(s) for an area: the smallest one that contains the whole box, unless
    the box straddles a border (e.g. the Bay of Fundy: New Brunswick + Nova Scotia), where that
    would be a whole country (Canada ~4 GB): then the small extracts that cover its land, with the
    points only a country covers treated as open sea (no OSM features to build there)."""
    idx = geofabrik_index(offline)
    if not idx:
        return []
    s, w, n, e = bbox
    G = 5
    pts = [(w + (e - w) * i / (G - 1), s + (n - s) * j / (G - 1)) for i in range(G) for j in range(G)]
    feats = []
    for f in idx.get("features", []):
        g, pr = f.get("geometry"), f.get("properties", {})
        url = pr.get("urls", {}).get("pbf")
        if not g or not url:
            continue
        coords = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        xs = [c[0] for poly in coords for c in poly[0]]
        ys = [c[1] for poly in coords for c in poly[0]]
        if min(xs) > e or max(xs) < w or min(ys) > n or max(ys) < s:
            continue
        feats.append(((max(xs) - min(xs)) * (max(ys) - min(ys)), g, {"id": pr.get("id"), "name": pr.get("name"), "url": url}))
    feats.sort(key=lambda t: t[0])
    smallest = []               # per sample point: the smallest extract that contains it
    for x, y in pts:
        smallest.append(next(((a, ex["id"]) for a, g, ex in feats if _in_geom(x, y, g)), None))
    whole = next((ex for a, g, ex in feats if all(_in_geom(x, y, g) for x, y in pts)), None)
    hit = [p for p in smallest if p]
    if not hit:
        return [whole] if whole else []
    amin = min(a for a, _ in hit)
    small = []
    for a, i in hit:
        if a <= 25 * amin and i not in small:
            small.append(i)
    wa = next((a for a, g, ex in feats if ex is whole), None) if whole else None
    if whole and (len(small) == 1 and small[0] == whole["id"] or wa is not None and wa <= 25 * amin):
        return [whole]          # one extract has it all and is not much bigger than the pieces
    if len(small) > 4:
        return [whole] if whole else []
    byid = {ex["id"]: ex for _, _, ex in feats}
    return [byid[i] for i in small]


def pick_extract(bbox, offline=False):
    """First of pick_extracts() (older callers)."""
    ex = pick_extracts(bbox, offline)
    return ex[0] if ex else None


def extract_path(ex):
    return os.path.join(OSM_DIR, ex["url"].rsplit("/", 1)[-1])


def extract_fresh(path, max_age=30 * 86400):
    """Cached .pbf younger than max_age (by the last check, or the file date when it was put
    there by tools/fetch_assets.sh / build_region.py without our .meta.json)."""
    if not os.path.exists(path) or os.path.getsize(path) < 1000:
        return False
    try:
        meta = json.load(open(path + ".meta.json"))
    except Exception:  # noqa: BLE001
        meta = {}
    return time.time() - meta.get("checked", os.path.getmtime(path)) < max_age


def head_size(url):
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, method="HEAD", headers=UA), timeout=20)
        return int(r.headers.get("Content-Length", 0) or 0)
    except Exception:  # noqa: BLE001
        return 0


# ------------------------------------------------------------------ estimate / status
def estimate(bbox, online=True):
    wkm, hkm = bbox_km(bbox)
    dem_t = tiles_for(bbox, 13)
    z = img_zoom(bbox)
    img_t = tiles_for(bbox, z)
    dem_new = sum(1 for x, y in dem_t if not os.path.exists(os.path.join(DEM_DIR, f"{x}_{y}.png")))
    img_new = sum(1 for x, y in img_t if not os.path.exists(os.path.join(IMG_DIR, str(z), f"{x}_{y}.jpg")))
    exs = pick_extracts(bbox, offline=not online)
    ex_size, ex_cached = 0, bool(exs)
    for x in exs:
        path = extract_path(x)
        c = os.path.exists(path)
        ex_cached = ex_cached and c
        ex_size += os.path.getsize(path) if c else (head_size(x["url"]) if online else 0)
    ex = ({"id": "+".join(x["id"] for x in exs), "name": " + ".join(x["name"] for x in exs), "url": exs[0]["url"]}
          if len(exs) > 1 else (exs[0] if exs else None))
    chunks = math.ceil(wkm) * math.ceil(hkm)
    return {"bbox": bbox, "km": [round(wkm, 1), round(hkm, 1)], "km2": round(wkm * hkm, 1),
            "dem_tiles": len(dem_t), "dem_new": dem_new, "dem_mb": round(dem_new * AVG_DEM_TILE / 1e6, 1),
            "img_zoom": z, "img_tiles": len(img_t), "img_new": img_new, "img_mb": round(img_new * AVG_IMG_TILE / 1e6, 1),
            "osm_extract": ex, "osm_extracts": exs, "osm_mb": round(ex_size / 1e6, 1), "osm_cached": ex_cached,
            "region_chunks": chunks, "region_mb": round(chunks * 0.12, 1),
            "pack_mb": round(wkm * hkm * (1000 / 22) ** 2 * 3 / 1e6 + len(img_t) * 0.02, 1)}


def du(path):
    t = 0
    if os.path.isfile(path):
        return os.path.getsize(path)
    for root, _, files in os.walk(path):
        for f in files:
            try:
                t += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return t


def read_status(aid):
    p = os.path.join(AREAS, aid, "status.json")
    try:
        return json.load(open(p))
    except Exception:  # noqa: BLE001
        return {}


def write_status(aid, **kw):
    d = os.path.join(AREAS, aid)
    if not os.path.isdir(d):
        return              # deleted meanwhile: never resurrect an area as a bare status file
    st = read_status(aid)
    st.update(kw)
    st["updated"] = time.time()
    p = os.path.join(d, "status.json")
    json.dump(st, open(p + ".part", "w"))
    os.replace(p + ".part", p)


def write_area(aid, **kw):
    d = os.path.join(AREAS, aid)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "area.json")
    m = json.load(open(p)) if os.path.exists(p) else {}
    m.update(kw)
    json.dump(m, open(p + ".part", "w"), indent=1)
    os.replace(p + ".part", p)
    return m


def status_all():
    out = []
    for aid in existing():
        m = area_json(aid)
        if m is None or "bbox" not in m:
            continue        # being deleted / half written
        st = read_status(aid)
        reg = os.path.join(REGIONS, aid)
        man = os.path.join(reg, "manifest.json")
        rv = json.load(open(man)).get("version", 0) if os.path.exists(man) else 0
        out.append({"id": aid, "name": m.get("name", aid), "bbox": m["bbox"], "steps": m.get("steps", STEPS),
                    "state": st.get("state", "new"), "step": st.get("step", ""), "progress": st.get("progress", 0.0),
                    "msg": st.get("msg", ""), "pack": bool(m.get("pack")), "region": rv,
                    "bytes": st.get("bytes", 0), "updated": st.get("updated", 0), "error": st.get("error", ""),
                    "disk_mb": round((du(os.path.join(AREAS, aid)) + du(reg)) / 1e6, 1)})
    return out


# ------------------------------------------------------------------ jobs
class Cancelled(Exception):
    pass


class Job:
    def __init__(self, aid):
        self.aid = aid
        self.bytes = 0
        self.dir = os.path.join(AREAS, aid)
        self.area = json.load(open(os.path.join(self.dir, "area.json")))
        self.bbox = self.area["bbox"]

    def check(self):
        if os.path.exists(os.path.join(self.dir, "cancel")):
            raise Cancelled()

    def prog(self, step, frac, msg=""):
        write_status(self.aid, state="running", step=step, progress=round(frac, 3), msg=msg, bytes=self.bytes)
        runner_state(job=self.aid, step=step, progress=round(frac, 3), msg=msg, bytes=self.bytes)

    def fetch_tiles(self, step, tiles, url, folder, ext, frac0, frac1):
        os.makedirs(folder, exist_ok=True)
        miss = 0
        for i, (x, y) in enumerate(tiles):
            self.check()
            p = os.path.join(folder, f"{x}_{y}.{ext}")
            if not os.path.exists(p):
                try:
                    data = urllib.request.urlopen(urllib.request.Request(url.format(x=x, y=y, z=self.z), headers=UA), timeout=60).read()
                    self.bytes += len(data)
                    open(p + ".part", "wb").write(data)
                    os.replace(p + ".part", p)
                except Exception as ex:  # noqa: BLE001
                    miss += 1
                    log(f"{step}: tile {x},{y} failed: {ex}")
                    if miss > max(10, len(tiles) // 5):
                        raise RuntimeError(f"{step}: too many tiles failed (offline?)")
            if i % 8 == 0:
                self.prog(step, frac0 + (frac1 - frac0) * (i + 1) / len(tiles), f"{i + 1}/{len(tiles)} tiles")

    def grid(self):
        """Pack grid: lat/lon-linear, rows north -> south, ~22 m, at most 4096 a side."""
        s, w, n, e = self.bbox
        wkm, hkm = bbox_km(self.bbox)
        dw = int(min(4096, max(64, wkm * 1000 / 22)))
        dh = int(min(4096, max(64, hkm * 1000 / 22)))
        lats = np.linspace(n, s, dh)
        lons = np.linspace(w, e, dw)
        return dw, dh, lats, lons

    def step_dem(self):
        import build_region as br
        self.z = 13
        self.fetch_tiles("dem", tiles_for(self.bbox, 13), TERRARIUM_URL, DEM_DIR, "png", 0.0, 0.8)
        dem = br.Dem(self.bbox, DEM_DIR)
        dw, dh, lats, lons = self.grid()
        la, lo = np.meshgrid(lats, lons, indexing="ij")
        h = dem.heights(la.ravel(), lo.ravel()).reshape(dh, dw)
        q = np.clip(np.round(h * 2.0), -32767, 32767).astype("<i2")
        p = os.path.join(self.dir, "dem.bin")
        q.tofile(p + ".part")
        os.replace(p + ".part", p)
        # water before OSM: the sea (DEM <= 0); the OSM build refines it
        if not os.path.exists(os.path.join(self.dir, "water.bin")):
            self.write_water((h <= 0.0).astype(np.uint8) * 255)
        write_area(self.aid, dem_w=dw, dem_h=dh)

    def write_water(self, wm):
        p = os.path.join(self.dir, "water.bin")
        np.ascontiguousarray(wm, dtype=np.uint8).tofile(p + ".part")
        os.replace(p + ".part", p)

    def step_imagery(self):
        from PIL import Image
        z = self.z = img_zoom(self.bbox)
        tiles = tiles_for(self.bbox, z)
        folder = os.path.join(IMG_DIR, str(z))
        self.fetch_tiles("imagery", tiles, EOX_URL, folder, "jpg", 0.0, 0.85)
        self.prog("imagery", 0.9, "mosaic")
        xs = sorted({t[0] for t in tiles})
        ys = sorted({t[1] for t in tiles})
        mos = Image.new("RGB", (len(xs) * 256, len(ys) * 256), (40, 60, 40))
        for x, y in tiles:
            p = os.path.join(folder, f"{x}_{y}.jpg")
            if os.path.exists(p):
                try:
                    mos.paste(Image.open(p).convert("RGB").resize((256, 256)), ((x - xs[0]) * 256, (y - ys[0]) * 256))
                except Exception:  # noqa: BLE001
                    pass
        # Web Mercator mosaic -> lat/lon-linear image over the bbox (what the planet shader samples)
        s, w, n, e = self.bbox
        wkm, hkm = bbox_km(self.bbox)
        mpp = 156543.03 * math.cos(math.radians((s + n) / 2)) / 2 ** z
        ow = int(min(8192, max(256, wkm * 1000 / mpp)))
        oh = int(min(8192, max(256, hkm * 1000 / mpp)))
        lats = np.linspace(n, s, oh)
        lons = np.linspace(w, e, ow)
        px = ((lons + 180.0) / 360.0 * 2 ** z - xs[0]) * 256.0
        py = ((1.0 - np.arcsinh(np.tan(np.radians(lats))) / np.pi) / 2.0 * 2 ** z - ys[0]) * 256.0
        src = np.asarray(mos)
        ix = np.clip(px.astype(int), 0, src.shape[1] - 1)
        iy = np.clip(py.astype(int), 0, src.shape[0] - 1)
        out = src[iy[:, None], ix[None, :]]
        p = os.path.join(self.dir, "image.jpg")
        Image.fromarray(out).save(p + ".part.jpg", quality=88)
        os.replace(p + ".part.jpg", p)
        write_area(self.aid, image="image.jpg", image_attrib=ATTRIB)

    def step_osm(self):
        exs = pick_extracts(self.bbox)
        if not exs:
            raise RuntimeError("no Geofabrik extract contains this area (offline: no geofabrik-index.json yet? open sea?)")
        write_area(self.aid, extract=exs[0], extracts=exs)
        log(self.aid, "OSM extract(s):", ", ".join(f"{x['name']} ({x['url'].rsplit('/', 1)[-1]})" for x in exs))
        for k, ex in enumerate(exs):
            self.fetch_extract(ex, k / len(exs), (k + 1) / len(exs))
        self.map_layer([extract_path(ex) for ex in exs])

    def map_layer(self, pbfs):
        """Refresh the AREAS map's roads / rivers / names layer (maps/*.ffml) for these extracts.
        Best effort: never fails the job (needs pyosmium; skipped when up to date)."""
        pbfs = [p for p in pbfs if os.path.exists(p)]
        if not pbfs:
            return
        self.prog("osm", 1.0, "map layer (roads / rivers / names)")
        try:
            cmd = [sys.executable, os.path.join(HERE, "map_layer.py")] + [f"--pbf={p}" for p in pbfs]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
            for ln in (r.stdout + r.stderr).strip().splitlines()[-4:]:
                log(self.aid, ln)
            if r.returncode == 2:
                log(self.aid, "map layer skipped: pip install osmium (the AREAS map works without it)")
        except Exception as ex:  # noqa: BLE001
            log(self.aid, f"map layer failed (ignored): {ex}")

    def fetch_extract(self, ex, f0, f1):
        url = ex["url"]
        path = extract_path(ex)
        meta_p = path + ".meta.json"
        if extract_fresh(path):
            log(self.aid, f"OSM: using the cached {os.path.basename(path)} ({os.path.getsize(path) / 1e6:.0f} MB)")
            self.prog("osm", f1, f"{ex['name']}: cached")
            return
        try:
            meta = json.load(open(meta_p))
        except Exception:  # noqa: BLE001
            meta = {}
        have = os.path.exists(path) and os.path.getsize(path) > 1000
        hdr = dict(UA)
        if have:
            hdr["If-Modified-Since"] = meta.get("last_modified") or formatdate(os.path.getmtime(path), usegmt=True)
        self.prog("osm", f0, f"{ex['name']} extract: connecting")
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers=hdr), timeout=60)
        except urllib.error.HTTPError as hx:
            if hx.code == 304 and have:
                log(self.aid, f"OSM: {os.path.basename(path)} unchanged on the server, keeping it")
                meta["checked"] = time.time()
                json.dump(meta, open(meta_p, "w"))
                return
            raise
        except Exception as ux:  # noqa: BLE001
            if have:
                log(self.aid, f"OSM: offline ({ux}), using the cached {os.path.basename(path)}")
                return
            raise RuntimeError(f"OSM download failed ({ux})") from ux
        total = int(r.headers.get("Content-Length", 0) or 0)
        log(self.aid, f"OSM: downloading {url} ({total / 1e6:.0f} MB)")
        done, t0 = 0, 0.0
        os.makedirs(OSM_DIR, exist_ok=True)
        with open(path + ".part", "wb") as f:
            while True:
                self.check()
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
                done += len(b)
                self.bytes += len(b)
                if time.time() - t0 > 1.0:
                    t0 = time.time()
                    fr = done / total if total else 0.5
                    self.prog("osm", f0 + (f1 - f0) * fr, f"{ex['name']}: {done / 1e6:.0f}/{total / 1e6:.0f} MB" if total else f"{ex['name']}: {done / 1e6:.0f} MB")
        if total and done < total:
            raise RuntimeError(f"short download {done}/{total}")
        os.replace(path + ".part", path)
        json.dump({"last_modified": r.headers.get("Last-Modified", ""), "size": done, "url": url, "checked": time.time()}, open(meta_p, "w"))

    def step_build(self):
        a = json.load(open(os.path.join(self.dir, "area.json")))
        exs = a.get("extracts") or ([a["extract"]] if a.get("extract") else [])
        if not exs:
            self.step_osm()
            a = json.load(open(os.path.join(self.dir, "area.json")))
            exs = a.get("extracts") or [a["extract"]]
        s, w, n, e = self.bbox
        cmd = [sys.executable, os.path.join(HERE, "build_region.py"), "--name", self.aid, "--bbox", f"{s},{w},{n},{e}",
               "--out", os.path.join(REGIONS, self.aid)]
        for ex in exs:
            cmd += ["--pbf-url", ex["url"]]
        if not deps()["osmium"] and self.area.get("source") != "overpass":
            log(self.aid, "build: pyosmium missing -> the builder falls back to the slower Overpass API (" + DEP_HINT["osmium"] + ")")
        if self.area.get("source") == "overpass":
            cmd += ["--source", "overpass"]
        self.prog("build", 0.05, "building the 3D region")
        logf = open(os.path.join(self.dir, "build.log"), "w")
        pr = subprocess.Popen(cmd, stdout=logf, stderr=subprocess.STDOUT, start_new_session=True)
        while pr.poll() is None:
            time.sleep(1.0)
            try:
                self.check()
            except Cancelled:
                os.killpg(pr.pid, signal.SIGTERM)
                pr.wait()
                raise
            tail = open(os.path.join(self.dir, "build.log")).read().strip().splitlines()[-1:] or [""]
            self.prog("build", 0.5, tail[0][-120:])
        if pr.returncode != 0:
            raise RuntimeError("build_region.py failed (see areas/%s/build.log)" % self.aid)
        self.prog("build", 0.95, "water mask")
        self.water_from_region()
        self.prog("build", 0.98, "nav map overlay")
        r = subprocess.run([sys.executable, os.path.join(HERE, "nav_overlay.py"), "--region", self.aid], capture_output=True, text=True)
        if r.returncode != 0:      # a nicety: the area works without it
            log(self.aid, "nav overlay failed: " + (r.stderr or r.stdout).strip()[-300:])

    def water_from_region(self):
        """Pack water mask (water.bin) from the built region's chunk water levels + the sea."""
        reg = os.path.join(REGIONS, self.aid)
        man = json.load(open(os.path.join(reg, "manifest.json")))
        a = json.load(open(os.path.join(self.dir, "area.json")))
        if "dem_w" not in a:
            return
        dw, dh, lats, lons = self.grid()
        s, w, n, e = man["bbox"]
        lat0, lon0 = man["lat0"], man["lon0"]
        kx, kz = 111320.0 * math.cos(math.radians(lat0)), 110540.0
        wm = np.zeros((dh, dw), np.uint8)
        dem = np.fromfile(os.path.join(self.dir, "dem.bin"), "<i2").reshape(dh, dw)
        wm[dem <= 0] = 255
        cs = man["chunk"]
        X = (lons[None, :] - lon0) * kx
        Z = -(lats[:, None] - lat0) * kz
        X = np.broadcast_to(X, (dh, dw))
        Z = np.broadcast_to(Z, (dh, dw))
        for k in man["chunks"]:
            c = json.load(open(os.path.join(reg, f"c_{k}.json")))
            if "wl" not in c:
                continue
            nn = c["n"]
            ox, oz = c["o"]
            stp = cs / (nn - 1)
            wl = np.array(c["wl"]).reshape(nn, nn) > -32768
            m = (X >= ox) & (X < ox + cs) & (Z >= oz) & (Z < oz + cs)
            i = np.clip(np.round((X[m] - ox) / stp).astype(int), 0, nn - 1)
            j = np.clip(np.round((Z[m] - oz) / stp).astype(int), 0, nn - 1)
            wm[m] = np.maximum(wm[m], wl[j, i].astype(np.uint8) * 255)
        self.write_water(wm)

    def run(self):
        steps = [s for s in STEPS if s in self.area.get("steps", STEPS)]
        miss = missing_for(steps)
        if miss:
            write_status(self.aid, state="error", step="", msg=dep_msg(miss), error="deps")
            log(self.aid, "error:", dep_msg(miss))
            return
        try:
            for k, st in enumerate(steps):
                self.check()
                write_status(self.aid, state="running", step=st, progress=0.0, msg="", steps_done=steps[:k], error="")
                runner_state(job=self.aid, step=st, progress=0.0, msg="", bytes=self.bytes)
                log(self.aid, "step", st)
                getattr(self, "step_" + st)()
                if st in ("dem", "build") and os.path.exists(os.path.join(self.dir, "dem.bin")):
                    # usable as soon as the DEM is in (imagery / water refine it later)
                    a = json.load(open(os.path.join(self.dir, "area.json")))
                    write_area(self.aid, pack={"version": PACK_VER, "dem_w": a["dem_w"], "dem_h": a["dem_h"],
                                               "image": "image.jpg"}, region=self.aid if st == "build" else a.get("region", ""))
            write_status(self.aid, state="done", step="", progress=1.0, msg="ready", steps_done=steps)
            log(self.aid, "done")
        except Cancelled:
            try:
                os.remove(os.path.join(self.dir, "cancel"))
            except OSError:
                pass
            write_status(self.aid, state="cancelled", msg="cancelled")
            log(self.aid, "cancelled")
        except Exception as ex:  # noqa: BLE001
            write_status(self.aid, state="error", msg=str(ex)[:300], error="job")
            log(self.aid, "error:", repr(ex))
        if os.path.exists(os.path.join(self.dir, "delete")):   # `delete` while running: finish it now
            remove_area(self.aid)
            log(self.aid, "deleted (after cancel)")


def drop_queued(aid):
    n = 0
    for f in os.listdir(QUEUE) if os.path.isdir(QUEUE) else []:
        if f.endswith(f"_{aid}.json"):
            try:
                os.remove(os.path.join(QUEUE, f))
                n += 1
            except OSError:
                pass
    return n


def remove_area(aid):
    shutil.rmtree(os.path.join(AREAS, aid), ignore_errors=True)
    shutil.rmtree(os.path.join(REGIONS, aid), ignore_errors=True)
    for ext in (".png", ".json"):      # its nav map overlay (tools/nav_overlay.py)
        p = os.path.join(os.path.dirname(REGIONS), "overlays", aid + ext)
        if os.path.exists(p):
            os.remove(p)


LOCK = os.path.join(AREAS, "runner.lock")      # flock()ed by the live runner: the kernel drops it when it dies
PIDF = os.path.join(AREAS, "runner.pid")
RSTATE = os.path.join(AREAS, "runner.json")    # what the runner is doing (job / step / bytes / heartbeat)
RLOG = os.path.join(AREAS, "runner.log")
_lock_fd = None


def _lock_held():
    """True while a runner holds the lock. A crashed / killed runner can't leave a stale lock."""
    if _lock_fd is not None:
        return True
    try:
        os.makedirs(AREAS, exist_ok=True)
        fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    except OSError:
        return False
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    except OSError:
        return True
    finally:
        os.close(fd)


def runner_alive():
    """pid of the live runner (1 if it holds the lock but its pid file is unreadable), else 0."""
    if not _lock_held():
        return 0
    try:
        return int(open(PIDF).read().strip()) or 1
    except Exception:  # noqa: BLE001
        return 1


def runner_info():
    try:
        return json.load(open(RSTATE))
    except Exception:  # noqa: BLE001
        return {}


def runner_state(**kw):
    if _lock_fd is None:
        return
    st = runner_info()
    st.update(kw)
    st["pid"] = os.getpid()
    st["heartbeat"] = time.time()
    try:
        json.dump(st, open(RSTATE + ".part", "w"))
        os.replace(RSTATE + ".part", RSTATE)
    except OSError:
        pass


def log_tail(n=12):
    try:
        with open(RLOG, "rb") as f:
            f.seek(max(0, os.path.getsize(RLOG) - 16000))
            return [ln for ln in f.read().decode("utf-8", "replace").splitlines() if ln.strip()][-n:]
    except OSError:
        return []


def queue_files():
    return sorted(f for f in os.listdir(QUEUE) if f.endswith(".json")) if os.path.isdir(QUEUE) else []


def queued_ids():
    out = []
    for f in queue_files():
        try:
            out.append(json.load(open(os.path.join(QUEUE, f)))["id"])
        except Exception:  # noqa: BLE001
            pass
    return out


def enqueue(aid, first=False):
    os.makedirs(QUEUE, exist_ok=True)
    drop_queued(aid)
    json.dump({"id": aid}, open(os.path.join(QUEUE, "%d_%s.json" % (0 if first else time.time() * 1000, aid)), "w"))


def recover_stale():
    """Runner start (we hold the lock, so nobody else is working): jobs left 'running' by a dead
    runner and 'queued' areas whose queue file is gone go back into the queue."""
    q = set(queued_ids())
    for aid in existing():
        st = read_status(aid)
        state = st.get("state")
        if state == "running":
            enqueue(aid, first=True)
            write_status(aid, state="queued", msg="resuming (the previous runner stopped mid-job)")
            log(aid, "was 'running' under a dead runner: re-queued first")
        elif state == "queued" and aid not in q:
            enqueue(aid)
            log(aid, "was 'queued' without a queue entry: re-queued")


def run_queue():
    global _lock_fd
    os.makedirs(QUEUE, exist_ok=True)
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        log("a runner is already working (pid %d)" % runner_alive())
        return 0
    _lock_fd = fd
    open(PIDF, "w").write(str(os.getpid()))
    json.dump({"pid": os.getpid(), "started": time.time(), "heartbeat": time.time(), "job": "", "step": ""}, open(RSTATE, "w"))
    log(f"runner started (pid {os.getpid()}, python {sys.executable}, data {DATA})")
    rc = 0
    try:
        d = deps()
        log("deps:", ", ".join(f"{k}={'ok' if v else 'MISSING'}" for k, v in d.items()))
        recover_stale()
        while True:
            jobs = queue_files()
            if not jobs:
                break
            jp = os.path.join(QUEUE, jobs[0])
            try:
                aid = json.load(open(jp))["id"]
            except Exception as ex:  # noqa: BLE001
                log("bad queue entry", jobs[0], ex)
                os.remove(jp)
                continue
            if os.path.exists(os.path.join(AREAS, aid, "area.json")):
                log("job:", aid)
                runner_state(job=aid, step="", progress=0.0, msg="", bytes=0)
                try:
                    Job(aid).run()
                except Exception as ex:  # noqa: BLE001  (a broken area must not stop the queue)
                    write_status(aid, state="error", msg=f"job failed to start: {ex!r}"[:300], error="job")
                    log(aid, "job failed to start:", repr(ex))
            try:
                os.remove(jp)      # only now: a killed runner leaves the job in the queue
            except OSError:
                pass
        log("queue empty: runner stops")
    except Exception as ex:  # noqa: BLE001
        log("runner crashed:", repr(ex))
        import traceback
        traceback.print_exc(file=sys.stdout)
        rc = 1
    finally:
        runner_state(job="", step="", stopped=time.time())
        for p in (PIDF,):
            try:
                os.remove(p)
            except OSError:
                pass
        _lock_fd = None
        os.close(fd)
    return rc


def spawn_runner(wait_s=4.0):
    """Start the background runner (`run --wait`, detached, logging to areas/runner.log) and
    check that it really started. Returns {"ok", "pid", "msg"/"error", "log"}."""
    pid = runner_alive()
    if pid:
        return {"ok": True, "pid": pid, "msg": "runner already working (pid %d)" % pid}
    os.makedirs(AREAS, exist_ok=True)
    try:
        if os.path.getsize(RLOG) > 2_000_000:
            os.replace(RLOG, RLOG + ".1")
    except OSError:
        pass
    env = dict(os.environ)
    env["HOME"] = env.get("HOME") or os.path.expanduser("~")
    env["PATH"] = (env.get("PATH") or "") + ":/usr/local/bin:/usr/bin:/bin"
    env["PYTHONUNBUFFERED"] = "1"
    lf = open(RLOG, "a")
    lf.write(f"\n{time.strftime('%Y-%m-%d %H:%M:%S')} === start requested: {sys.executable} {os.path.abspath(__file__)} run --wait ===\n")
    lf.flush()
    try:
        p = subprocess.Popen([sys.executable, "-u", os.path.abspath(__file__), "run", "--wait"], cwd=HERE, env=env,
                             stdin=subprocess.DEVNULL, stdout=lf, stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
    except OSError as ex:
        lf.write(f"could not start the runner: {ex}\n")
        return {"ok": False, "pid": 0, "error": f"could not start the runner: {ex}", "log": log_tail()}
    finally:
        lf.close()
    t0 = time.time()
    while time.time() - t0 < wait_s:
        if _lock_held():
            return {"ok": True, "pid": p.pid, "msg": "runner started (pid %d)" % p.pid}
        rc = p.poll()
        if rc is not None:
            if rc == 0:
                return {"ok": True, "pid": 0, "msg": "runner already finished (queue done or empty; see the log)", "log": log_tail(6)}
            return {"ok": False, "pid": 0, "error": f"runner exited at once (code {rc}): see areas/runner.log", "log": log_tail()}
        time.sleep(0.1)
    return {"ok": True, "pid": p.pid, "msg": "runner starting (pid %d)" % p.pid}


MLOG = os.path.join(AREAS, "map_layer.log")
MPID = os.path.join(AREAS, "map_layer.pid")


def spawn_map_layer():
    """BUILD MAP LAYER: run tools/map_layer.py detached (log areas/map_layer.log)."""
    try:
        pid = int(open(MPID).read().strip() or 0)
        os.kill(pid, 0)
        return {"ok": True, "pid": pid, "msg": "map layer already building (pid %d)" % pid}
    except (OSError, ValueError):
        pass
    pbfs = [p for p in glob.glob(os.path.join(OSM_DIR, "*.osm.pbf")) if ".cut_" not in p]
    if not pbfs:
        return {"ok": False, "error": "no OSM extract downloaded yet: queue and run an area first"}
    try:
        import osmium  # noqa: F401
    except ImportError:
        return {"ok": False, "error": "pyosmium missing: pip install osmium (osmium-tool: faster)"}
    os.makedirs(AREAS, exist_ok=True)
    lf = open(MLOG, "a")
    lf.write(f"\n{time.strftime('%Y-%m-%d %H:%M:%S')} === map layer ===\n")
    lf.flush()
    try:
        p = subprocess.Popen([sys.executable, "-u", os.path.join(HERE, "map_layer.py")], cwd=HERE, stdin=subprocess.DEVNULL,
                             stdout=lf, stderr=subprocess.STDOUT, start_new_session=True, close_fds=True)
    except OSError as ex:
        return {"ok": False, "error": f"could not start map_layer.py: {ex}"}
    finally:
        lf.close()
    open(MPID, "w").write(str(p.pid))
    return {"ok": True, "pid": p.pid, "msg": "building map layer from %d extract(s) (pid %d, log areas/map_layer.log)" % (len(pbfs), p.pid)}


def why_waiting(areas, pid, d):
    """Fill 'why' for areas that are not moving."""
    q = queued_ids()
    cur = runner_info().get("job", "") if pid else ""
    for a in areas:
        miss = missing_for(a["steps"], d)
        if a["state"] == "queued":
            if miss:
                a["why"] = "blocked: " + dep_msg(miss)
            elif a["id"] not in q:
                a["why"] = "not in the queue file list: RUN NOW (or `area_manager.py run`) re-queues it"
            elif not pid:
                a["why"] = "waiting: the background runner is NOT running -> RUN NOW (or `python3 tools/area_manager.py run`)"
            elif cur and cur != a["id"]:
                k = q.index(a["id"]) if a["id"] in q else -1
                a["why"] = f"waiting behind '{cur}' (#{k + 1} in the queue)"
            else:
                a["why"] = "starting"
        elif a["state"] == "running" and not pid:
            a["state"] = "stalled"
            a["why"] = "the runner stopped mid-job (killed / crashed): RUN NOW resumes it"
        elif a["state"] == "running":
            a["why"] = ""
        elif a["state"] == "error" and miss:
            a["why"] = dep_msg(miss)
    return areas


def status_doc():
    d = deps()
    pid = runner_alive()
    areas = why_waiting(status_all(), pid, d)
    probs = []
    if not d["numpy"]:
        probs.append("python3-numpy missing: no area job can run (" + DEP_HINT["numpy"] + ")")
    if not d["PIL"]:
        probs.append("python3-pil missing: DEM + imagery steps can't run (" + DEP_HINT["PIL"] + ")")
    if not d["osmium"]:
        probs.append("pyosmium missing: 3D builds use the slow Overpass API (" + DEP_HINT["osmium"] + ")")
    waiting = sum(1 for a in areas if a["state"] in ("queued", "stalled"))
    if waiting and not pid:
        probs.append(f"{waiting} job(s) waiting but the background runner is not running")
    ri = runner_info()
    if pid and ri.get("heartbeat") and time.time() - ri["heartbeat"] > 600 and ri.get("step") != "build":
        probs.append("runner has not reported progress for %d min (stuck download?)" % ((time.time() - ri["heartbeat"]) // 60))
    return {"areas": areas, "runner": pid, "runner_info": ri if pid else {}, "queue": queued_ids(), "deps": d,
            "problems": probs, "log_tail": log_tail(), "log": RLOG, "python": sys.executable}


# ------------------------------------------------------------------ commands
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["presets", "estimate", "add", "status", "run", "cancel", "delete", "maplayer"])
    ap.add_argument("preset", nargs="?", help="preset or existing area id")
    ap.add_argument("--id")
    ap.add_argument("--name")
    ap.add_argument("--bbox", help="S,W,N,E degrees")
    ap.add_argument("--center", help="LAT,LON")
    ap.add_argument("--radius", type=float, help="km (with --center)")
    ap.add_argument("--steps", default=",".join(STEPS))
    ap.add_argument("--source", choices=["pbf", "overpass"], default="pbf")
    ap.add_argument("--run", action="store_true", help="start the background runner")
    ap.add_argument("--wait", action="store_true", help="run: in the foreground")
    ap.add_argument("--offline", action="store_true", help="estimate: no network")
    ap.add_argument("--purge-tiles", action="store_true", help="delete: also the area's DEM / imagery tiles")
    ap.add_argument("--fit", choices=["none", "clamp", "split"], default="none",
                    help="areas over 120 km a side: clamp to 120 km around the centre, or split into tiles")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    if a.cmd == "presets":
        p = presets()
        if a.json:
            print(json.dumps(p))
        else:
            for k, v in p.items():
                print(f"{k:14s} {v['name']:28s} {','.join(str(x) for x in v['bbox'])}")
    elif a.cmd == "estimate":
        aid, name, bbox0 = parse_area(a)
        if max(bbox_km(bbox0)) > MAX_KM + 0.01 and a.fit == "none" and a.json:
            wkm, hkm = bbox_km(bbox0)
            print(json.dumps({"error": "too_big", "km": [round(wkm, 1), round(hkm, 1)], "max_km": MAX_KM,
                              "split_tiles": math.ceil(wkm / MAX_KM) * math.ceil(hkm / MAX_KM)}))
            return
        parts = fit_area(aid, name, bbox0, a.fit)
        bbox = parts[0][2] if len(parts) == 1 else bbox0
        est = estimate(bbox, online=not a.offline)
        est["parts"] = len(parts)
        est["fit"] = a.fit if bbox != bbox0 or len(parts) > 1 else "none"
        if a.json:
            print(json.dumps(est))
        else:
            ex = est["osm_extract"]
            print(f"{name}: {est['km'][0]} x {est['km'][1]} km ({est['km2']} km2)\n"
                  f"  DEM      {est['dem_tiles']} tiles, {est['dem_new']} to download (~{est['dem_mb']} MB)\n"
                  f"  imagery  zoom {est['img_zoom']}, {est['img_tiles']} tiles, {est['img_new']} to download (~{est['img_mb']} MB)\n"
                  f"  OSM      {ex['name'] + ' extract' if ex else '?'} ({est['osm_mb']} MB{', cached' if est['osm_cached'] else ''})\n"
                  f"  region   ~{est['region_chunks']} chunks (~{est['region_mb']} MB)")
    elif a.cmd == "add":
        if np is None:
            log("note: " + dep_msg(["numpy"]) + ": the job is queued but can't run until it is installed")
        aid0, name0, bbox0 = parse_area(a)
        parts = fit_area(aid0, name0, bbox0, a.fit)
        if len(parts) > 1 or parts[0][2] != bbox0:
            w0, h0 = bbox_km(bbox0)
            log(f"{aid0}: {w0:.0f} x {h0:.0f} km is over {MAX_KM:.0f} km a side -> " +
                (f"split into {len(parts)} areas" if len(parts) > 1 else f"clamped to {MAX_KM:.0f} km around the centre"))
        steps = [s for s in a.steps.split(",") if s in STEPS]
        for aid, name, bbox in parts:
            write_area(aid, name=name, bbox=bbox, steps=steps, source=a.source, created=time.time())
            for flag in ("cancel", "delete"):
                try:
                    os.remove(os.path.join(AREAS, aid, flag))
                except OSError:
                    pass
            enqueue(aid)
            write_status(aid, state="queued", step="", progress=0.0, msg="queued", bytes=0, error="")
            log(f"queued {aid} ({name}) {bbox} steps={','.join(steps)}")
        if a.run:
            r = spawn_runner()
            if a.json:
                print(json.dumps(r))
            else:
                log(r.get("msg") or r.get("error"))
            if not r["ok"]:
                sys.exit(1)
    elif a.cmd == "status":
        doc = status_doc()
        if a.json:
            print(json.dumps(doc))
        else:
            ri = doc["runner_info"]
            print("runner: " + (f"RUNNING pid {doc['runner']}" + (f"  job {ri.get('job')} {ri.get('step')} {float(ri.get('progress', 0)) * 100:.0f}%"
                                                                   f"  {ri.get('bytes', 0) / 1e6:.1f} MB downloaded  (heartbeat {time.time() - ri.get('heartbeat', time.time()):.0f} s ago)"
                                                                   if ri.get("job") else "") if doc["runner"] else "NOT RUNNING"))
            print("deps:   " + ", ".join(f"{k} {'ok' if v else 'MISSING'}" for k, v in doc["deps"].items()) + f"   (python {doc['python']})")
            for p in doc["problems"]:
                print("  ! " + p)
            for s in doc["areas"]:
                print(f"{s['id']:16s} {s['state']:9s} {s['step']:8s} {s['progress'] * 100:5.1f}%  {s['bytes'] / 1e6:6.1f} MB dl  pack={'Y' if s['pack'] else '-'} "
                      f"region=v{s['region']}  {s['disk_mb']:7.1f} MB  {s['msg']}")
                if s.get("why"):
                    print(f"{'':16s} -> {s['why']}")
            if doc["log_tail"]:
                print(f"runner.log ({doc['log']}), last lines:")
                for ln in doc["log_tail"][-6:]:
                    print("  | " + ln)
    elif a.cmd == "run":
        if a.wait:
            sys.exit(run_queue())
        # retry: jobs that failed on missing modules that are there now go back in
        d = deps()
        for aid in existing():
            st = read_status(aid)
            if st.get("state") == "error" and st.get("error") == "deps" and not missing_for((area_json(aid) or {}).get("steps", STEPS), d):
                enqueue(aid)
                write_status(aid, state="queued", msg="queued (dependencies now installed)", error="")
        r = spawn_runner()
        if a.json:
            print(json.dumps(r))
        else:
            log(r.get("msg") or r.get("error"))
            for ln in r.get("log", []):
                print("  | " + ln)
        if not r["ok"]:
            sys.exit(1)
    elif a.cmd == "maplayer":
        r = spawn_map_layer()
        print(json.dumps(r) if a.json else (r.get("msg") or r.get("error")))
        if not r["ok"]:
            sys.exit(1)
    elif a.cmd == "cancel":
        aid = norm_id(a.preset or a.id or "")
        if drop_queued(aid):
            write_status(aid, state="cancelled", msg="cancelled")
        if read_status(aid).get("state") == "running" and runner_alive():
            open(os.path.join(AREAS, aid, "cancel"), "w").close()
        elif read_status(aid).get("state") == "running":    # runner died mid-job
            write_status(aid, state="cancelled", msg="cancelled (runner not running)")
        log("cancel", aid)
    elif a.cmd == "delete":
        aid = norm_id(a.preset or a.id or "")
        if not aid:
            sys.exit("delete: which area?")
        d = os.path.join(AREAS, aid)
        drop_queued(aid)
        if not os.path.isdir(d) and not os.path.isdir(os.path.join(REGIONS, aid)):
            log("already deleted", aid)
            return
        if read_status(aid).get("state") == "running" and runner_alive():
            open(os.path.join(d, "delete"), "w").close()
            open(os.path.join(d, "cancel"), "w").close()
            write_status(aid, msg="deleting (cancelling the running step)")
            log("delete", aid, "(running: cancelling, the runner removes it)")
            return
        if a.purge_tiles and os.path.exists(os.path.join(d, "area.json")):
            bbox = json.load(open(os.path.join(d, "area.json")))["bbox"]
            others = [json.load(open(os.path.join(AREAS, o, "area.json")))["bbox"] for o in existing() if o != aid]
            z = img_zoom(bbox)
            for folder, ext, zz in ((DEM_DIR, "png", 13), (os.path.join(IMG_DIR, str(z)), "jpg", z)):
                keep = {t for ob in others for t in tiles_for(ob, zz)}
                for t in tiles_for(bbox, zz):
                    if t not in keep:
                        try:
                            os.remove(os.path.join(folder, f"{t[0]}_{t[1]}.{ext}"))
                        except OSError:
                            pass
        remove_area(aid)
        log("deleted", aid)


if __name__ == "__main__":
    main()
