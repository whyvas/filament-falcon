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
    python3 tools/area_manager.py run [--wait]                  # process the job queue (background)
    python3 tools/area_manager.py cancel ID | delete ID [--purge-tiles]
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
Jobs run one at a time in a single background runner (areas/runner.pid); `cancel` stops the
running step within a few seconds, `delete` removes the pack + region (the shared tile and
extract caches stay; --purge-tiles also drops this area's tiles that no other area uses).
"""
import argparse, io, json, math, os, shutil, signal, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np  # noqa: E402

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
    print("[area]", *a, flush=True)


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


def pick_extract(bbox, offline=False):
    """Smallest Geofabrik extract whose boundary contains the bbox corners + centre."""
    idx = geofabrik_index(offline)
    if not idx:
        return None
    s, w, n, e = bbox
    pts = [(w, s), (w, n), (e, s), (e, n), ((w + e) / 2, (s + n) / 2)]
    best = None
    for f in idx.get("features", []):
        g, pr = f.get("geometry"), f.get("properties", {})
        url = pr.get("urls", {}).get("pbf")
        if not g or not url:
            continue
        coords = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        xs = [c[0] for poly in coords for c in poly[0]]
        ys = [c[1] for poly in coords for c in poly[0]]
        if min(xs) > w or max(xs) < e or min(ys) > s or max(ys) < n:
            continue
        if all(_in_geom(x, y, g) for x, y in pts):
            area = (max(xs) - min(xs)) * (max(ys) - min(ys))
            if best is None or area < best[0]:
                best = (area, pr.get("id"), pr.get("name"), url)
    return {"id": best[1], "name": best[2], "url": best[3]} if best else None


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
    ex = pick_extract(bbox, offline=not online)
    ex_size, ex_cached = 0, False
    if ex:
        path = os.path.join(OSM_DIR, ex["url"].rsplit("/", 1)[-1])
        ex_cached = os.path.exists(path)
        ex_size = os.path.getsize(path) if ex_cached else (head_size(ex["url"]) if online else 0)
    chunks = math.ceil(wkm) * math.ceil(hkm)
    return {"bbox": bbox, "km": [round(wkm, 1), round(hkm, 1)], "km2": round(wkm * hkm, 1),
            "dem_tiles": len(dem_t), "dem_new": dem_new, "dem_mb": round(dem_new * AVG_DEM_TILE / 1e6, 1),
            "img_zoom": z, "img_tiles": len(img_t), "img_new": img_new, "img_mb": round(img_new * AVG_IMG_TILE / 1e6, 1),
            "osm_extract": ex, "osm_mb": round(ex_size / 1e6, 1), "osm_cached": ex_cached,
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
                    "disk_mb": round((du(os.path.join(AREAS, aid)) + du(reg)) / 1e6, 1)})
    return out


# ------------------------------------------------------------------ jobs
class Cancelled(Exception):
    pass


class Job:
    def __init__(self, aid):
        self.aid = aid
        self.dir = os.path.join(AREAS, aid)
        self.area = json.load(open(os.path.join(self.dir, "area.json")))
        self.bbox = self.area["bbox"]

    def check(self):
        if os.path.exists(os.path.join(self.dir, "cancel")):
            raise Cancelled()

    def prog(self, step, frac, msg=""):
        write_status(self.aid, state="running", step=step, progress=round(frac, 3), msg=msg)

    def fetch_tiles(self, step, tiles, url, folder, ext, frac0, frac1):
        os.makedirs(folder, exist_ok=True)
        miss = 0
        for i, (x, y) in enumerate(tiles):
            self.check()
            p = os.path.join(folder, f"{x}_{y}.{ext}")
            if not os.path.exists(p):
                try:
                    data = urllib.request.urlopen(urllib.request.Request(url.format(x=x, y=y, z=self.z), headers=UA), timeout=60).read()
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
        ex = pick_extract(self.bbox)
        if not ex:
            raise RuntimeError("no Geofabrik extract contains this area (offline, or open sea?)")
        write_area(self.aid, extract=ex)
        url = ex["url"]
        path = os.path.join(OSM_DIR, url.rsplit("/", 1)[-1])
        meta_p = path + ".meta.json"
        meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
        if os.path.exists(path) and time.time() - meta.get("checked", 0) < 30 * 86400:
            return
        self.prog("osm", 0.0, f"{ex['name']} extract")
        r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60)
        total = int(r.headers.get("Content-Length", 0) or 0)
        done = 0
        os.makedirs(OSM_DIR, exist_ok=True)
        with open(path + ".part", "wb") as f:
            while True:
                self.check()
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
                done += len(b)
                if total:
                    self.prog("osm", done / total, f"{ex['name']}: {done / 1e6:.0f}/{total / 1e6:.0f} MB")
        if total and done < total:
            raise RuntimeError(f"short download {done}/{total}")
        os.replace(path + ".part", path)
        json.dump({"last_modified": r.headers.get("Last-Modified", ""), "size": done, "url": url, "checked": time.time()}, open(meta_p, "w"))

    def step_build(self):
        ex = self.area.get("extract") or (json.load(open(os.path.join(self.dir, "area.json"))).get("extract"))
        if not ex:
            self.step_osm()
            ex = json.load(open(os.path.join(self.dir, "area.json")))["extract"]
        s, w, n, e = self.bbox
        cmd = [sys.executable, os.path.join(HERE, "build_region.py"), "--name", self.aid, "--bbox", f"{s},{w},{n},{e}",
               "--pbf-url", ex["url"], "--out", os.path.join(REGIONS, self.aid)]
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
        try:
            for k, st in enumerate(steps):
                self.check()
                write_status(self.aid, state="running", step=st, progress=0.0, msg="", steps_done=steps[:k])
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
            write_status(self.aid, state="error", msg=str(ex)[:300])
            log(self.aid, "error:", ex)
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


def runner_alive():
    p = os.path.join(AREAS, "runner.pid")
    try:
        pid = int(open(p).read())
        os.kill(pid, 0)
        return pid
    except Exception:  # noqa: BLE001
        return 0


def run_queue():
    os.makedirs(QUEUE, exist_ok=True)
    if runner_alive() and runner_alive() != os.getpid():
        log("a runner is already working (pid %d)" % runner_alive())
        return
    pidp = os.path.join(AREAS, "runner.pid")
    open(pidp, "w").write(str(os.getpid()))
    try:
        while True:
            jobs = sorted(f for f in os.listdir(QUEUE) if f.endswith(".json"))
            if not jobs:
                break
            jp = os.path.join(QUEUE, jobs[0])
            aid = json.load(open(jp))["id"]
            os.remove(jp)
            if os.path.exists(os.path.join(AREAS, aid, "area.json")):
                log("job:", aid)
                Job(aid).run()
    finally:
        try:
            os.remove(pidp)
        except OSError:
            pass


def spawn_runner():
    if runner_alive():
        return
    os.makedirs(AREAS, exist_ok=True)
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "run"], start_new_session=True,
                     stdout=open(os.path.join(AREAS, "runner.log"), "a"), stderr=subprocess.STDOUT)


# ------------------------------------------------------------------ commands
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["presets", "estimate", "add", "status", "run", "cancel", "delete"])
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
            os.makedirs(QUEUE, exist_ok=True)
            drop_queued(aid)
            json.dump({"id": aid}, open(os.path.join(QUEUE, "%d_%s.json" % (time.time() * 1000, aid)), "w"))
            write_status(aid, state="queued", step="", progress=0.0, msg="queued")
            log(f"queued {aid} ({name}) {bbox} steps={','.join(steps)}")
        if a.run:
            spawn_runner()
    elif a.cmd == "status":
        st = status_all()
        if a.json:
            print(json.dumps({"areas": st, "runner": runner_alive()}))
        else:
            print(f"runner: {'pid %d' % runner_alive() if runner_alive() else 'idle'}")
            for s in st:
                print(f"{s['id']:16s} {s['state']:9s} {s['step']:8s} {s['progress'] * 100:5.1f}%  pack={'Y' if s['pack'] else '-'} "
                      f"region=v{s['region']}  {s['disk_mb']:7.1f} MB  {s['msg']}")
    elif a.cmd == "run":
        if a.wait:
            run_queue()
        else:
            spawn_runner()
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
