#!/usr/bin/env python3
"""Rasterize the cached OSM extracts into nav-map overlays (the GROUND close-up on the NAV /
ORBIT MAP page, scripts/ui/nav_map.gd). Run on the game PC: tools/fetch_assets.sh and the AREAS
builder (tools/area_manager.py) call it after a region build; it is cheap (seconds) because it
only reads the per-region extract build_region.py already cut out (osm/extract_<id>_*.json.gz).

For every built region (assets/regions/<id>/manifest.json) whose extract exists:
    assets/overlays/<id>.png    RGBA, north-up equirect over the region bbox (<= --px px):
                                water / coast (+ the area pack's water mask when there is one),
                                built-up areas, buildings, parks / woods, rivers, rail, roads
    assets/overlays/<id>.json   {"bbox": [S, W, N, E], "image": "<id>.png", "places": [...]}
"places" = OSM place=city/town/village/suburb nodes in the bbox, read from the cached .osm.pbf
extract(s) with pyosmium (osmium-tool cuts the bbox first when installed); skipped without them.
Up-to-date overlays are skipped (--force redraws).

  python3 tools/nav_overlay.py [--region ID ...] [--px 2048] [--force] [--no-places]
"""
import argparse, glob, gzip, json, math, os, shutil, subprocess, sys, tempfile, time

DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "filament-falcon")
ASSETS = os.path.join(DATA, "assets")
REGIONS = os.path.join(ASSETS, "regions")
OUT = os.path.join(ASSETS, "overlays")
OSM = os.path.join(DATA, "osm")
AREAS = os.path.join(DATA, "areas")
VER = 1
PLACE_KINDS = ("city", "town", "village", "suburb", "hamlet")

WATER = (40, 105, 200, 190)
COAST = (150, 210, 255, 235)
ROADS = [  # (highway values, width at 2048 px over ~25 km (scaled), RGBA)
    (("motorway", "trunk", "motorway_link", "trunk_link"), 4.0, (255, 160, 50, 240)),
    (("primary", "primary_link"), 3.0, (255, 205, 90, 230)),
    (("secondary", "secondary_link"), 2.4, (255, 235, 150, 220)),
    (("tertiary", "tertiary_link"), 1.8, (245, 245, 245, 200)),
    (("residential", "unclassified", "living_street", "service", "road"), 1.0, (225, 225, 225, 150)),
]


def log(*a):
    print("[nav_overlay]", *a, flush=True)


def newest_extract(rid):
    fs = glob.glob(os.path.join(OSM, f"extract_{rid}_*.json.gz"))
    return max(fs, key=os.path.getmtime) if fs else None


def pbfs_for(rid):
    """The .osm.pbf extracts an area was built from (area.json), else every cached one < 800 MB."""
    a = os.path.join(AREAS, rid, "area.json")
    if os.path.exists(a):
        m = json.load(open(a))
        exs = m.get("extracts") or ([m["extract"]] if m.get("extract") else [])
        ps = [os.path.join(OSM, ex["url"].rsplit("/", 1)[-1]) for ex in exs if ex.get("url")]
        ps = [p for p in ps if os.path.exists(p)]
        if ps:
            return ps
    return [p for p in glob.glob(os.path.join(OSM, "*.osm.pbf")) if ".cut_" not in p and os.path.getsize(p) < 800e6]


def read_places(pbfs, bbox):
    try:
        import osmium
    except ImportError:
        log("places: pyosmium missing (pip install osmium) -> no town labels")
        return []
    s, w, n, e = bbox
    out, seen = [], set()
    for pbf in pbfs:
        src, tmp = pbf, None
        if shutil.which("osmium"):
            tmp = os.path.join(tempfile.gettempdir(), f"nav_overlay_{os.getpid()}.osm.pbf")
            r = subprocess.run(["osmium", "extract", "-b", f"{w},{s},{e},{n}", "--overwrite", "-o", tmp, pbf], capture_output=True)
            src = tmp if r.returncode == 0 else pbf
        elif os.path.getsize(pbf) > 800e6:
            log(f"places: {os.path.basename(pbf)} is big; apt install osmium-tool to read it quickly")
            continue

        class H(osmium.SimpleHandler):
            def node(self, o):
                k = o.tags.get("place")
                if k in PLACE_KINDS and o.location.valid() and s <= o.location.lat <= n and w <= o.location.lon <= e:
                    nm = o.tags.get("name")
                    if nm and (nm, k) not in seen:
                        seen.add((nm, k))
                        out.append({"name": nm, "kind": k, "lat": round(o.location.lat, 5), "lon": round(o.location.lon, 5),
                                    "pop": int(o.tags.get("population", "0") or 0) if str(o.tags.get("population", "0")).isdigit() else 0})
        H().apply_file(src)
        if tmp and os.path.exists(tmp):
            os.remove(tmp)
    rank = {k: i for i, k in enumerate(PLACE_KINDS)}
    out.sort(key=lambda p: (rank[p["kind"]], -p["pop"]))
    return out[:400]


def render(rid, ex_path, bbox, px):
    from PIL import Image, ImageDraw
    s, w, n, e = bbox
    latc = math.radians((s + n) * 0.5)
    wkm = (e - w) * 111.32 * math.cos(latc)
    hkm = (n - s) * 110.54
    if wkm >= hkm:
        W, H = px, max(16, int(round(px * hkm / wkm)))
    else:
        W, H = max(16, int(round(px * wkm / hkm))), px
    ss = 2                                          # supersample, then downscale (anti-aliasing)
    SW, SH = W * ss, H * ss
    m_px = wkm * 1000.0 / W                         # metres per output pixel
    lw = max(0.6, min(3.0, 12.0 / max(m_px, 1.0))) * ss   # thinner roads on big regions

    def xy(lat, lon):
        return ((lon - w) / (e - w) * SW, (n - lat) / (n - s) * SH)

    img = Image.new("RGBA", (SW, SH), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img, "RGBA")
    # sea / coast from the area pack's water mask (DEM <= 0 + built water), when there is one
    pack = os.path.join(AREAS, rid, "area.json")
    if os.path.exists(pack):
        try:
            import numpy as np
            a = json.load(open(pack))
            pk = a.get("pack") or {}
            wb = os.path.join(AREAS, rid, "water.bin")
            dw, dh = int(a.get("dem_w", pk.get("dem_w", 0))), int(a.get("dem_h", pk.get("dem_h", 0)))
            if dw and dh and os.path.exists(wb) and os.path.getsize(wb) == dw * dh:
                ab = a.get("bbox", bbox)
                wm = (np.fromfile(wb, np.uint8).reshape(dh, dw) > 127)
                er = wm.copy()
                er[1:, :] &= wm[:-1, :]; er[:-1, :] &= wm[1:, :]; er[:, 1:] &= wm[:, :-1]; er[:, :-1] &= wm[:, 1:]
                rgba = np.zeros((dh, dw, 4), np.uint8)
                rgba[wm] = WATER
                rgba[wm & ~er] = COAST
                layer = Image.fromarray(rgba, "RGBA")
                x0, y0 = xy(ab[2], ab[1])
                x1, y1 = xy(ab[0], ab[3])
                layer = layer.resize((max(1, int(x1 - x0)), max(1, int(y1 - y0))), Image.NEAREST)
                img.alpha_composite(layer, (int(x0), int(y0)))
        except Exception as ex:      # the overlay is a nicety: never fail the build over it
            log(f"{rid}: pack water mask skipped ({ex})")
    data = json.load(gzip.open(ex_path, "rt"))
    els = data.get("elements", [])

    def rings_of(el):
        if el["type"] == "area":
            for outer, holes in el.get("rings", []):
                yield [xy(p[0], p[1]) for p in outer], [[xy(p[0], p[1]) for p in h] for h in holes]
        elif el["type"] == "way" and el.get("geometry"):
            g = [xy(p["lat"], p["lon"]) for p in el["geometry"] if p]
            if len(g) >= 4 and g[0] == g[-1]:
                yield g, []

    def fill(el, col):
        for outer, holes in rings_of(el):
            if len(outer) >= 3:
                dr.polygon(outer, fill=col)
                for h in holes:
                    if len(h) >= 3:
                        dr.polygon(h, fill=(0, 0, 0, 0))

    layers = [
        (lambda t: t.get("landuse") in ("residential", "commercial", "retail", "industrial"), (170, 160, 150, 70)),
        (lambda t: t.get("natural") in ("wood",) or t.get("landuse") in ("forest",), (40, 110, 50, 60)),
        (lambda t: t.get("leisure") in ("park", "pitch", "golf_course", "recreation_ground") or t.get("landuse") in ("grass", "meadow"), (80, 170, 80, 80)),
        (lambda t: t.get("natural") in ("water",) or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin"), WATER),
        (lambda t: "building" in t, (235, 220, 195, 170)),
    ]
    for test, col in layers:
        for el in els:
            if el["type"] in ("area", "way") and test(el.get("tags", {})):
                fill(el, col)
    lines = [el for el in els if el["type"] == "way" and el.get("geometry")]
    for el in lines:
        t = el.get("tags", {})
        ww = {"river": 3.0, "canal": 2.2, "stream": 0.9}.get(t.get("waterway"))
        if ww:
            dr.line([xy(p["lat"], p["lon"]) for p in el["geometry"] if p], fill=WATER[:3] + (230,), width=max(1, int(ww * lw)))
    for el in lines:
        if el.get("tags", {}).get("railway") == "rail":
            dr.line([xy(p["lat"], p["lon"]) for p in el["geometry"] if p], fill=(190, 170, 230, 200), width=max(1, int(1.2 * lw)))
    for kinds, wdt, col in reversed(ROADS):
        for el in lines:
            if el.get("tags", {}).get("highway") in kinds:
                pts = [xy(p["lat"], p["lon"]) for p in el["geometry"] if p]
                if len(pts) > 1:
                    dr.line(pts, fill=col, width=max(1, int(round(wdt * lw))), joint="curve")
    return img.resize((W, H), Image.LANCZOS), len(els)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--region", action="append", help="region / area id (default: every built region)")
    ap.add_argument("--px", type=int, default=2048, help="longest side of the overlay image")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-places", action="store_true", help="don't read town names from the .osm.pbf")
    a = ap.parse_args()
    ids = a.region or sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(REGIONS, "*", "manifest.json")))
    os.makedirs(OUT, exist_ok=True)
    done = 0
    for rid in ids:
        mf = os.path.join(REGIONS, rid, "manifest.json")
        if not os.path.exists(mf):
            log(f"{rid}: not built (no {mf})")
            continue
        bbox = json.load(open(mf))["bbox"]
        ex = newest_extract(rid)
        if not ex:
            log(f"{rid}: no cached OSM extract (osm/extract_{rid}_*.json.gz); build the region first")
            continue
        js, png = os.path.join(OUT, rid + ".json"), os.path.join(OUT, rid + ".png")
        src = {"extract": os.path.basename(ex), "mtime": int(os.path.getmtime(ex)), "px": a.px, "ver": VER}
        if not a.force and os.path.exists(js) and os.path.exists(png):
            try:
                if json.load(open(js)).get("src") == src:
                    log(f"{rid}: up to date")
                    continue
            except ValueError:
                pass
        t0 = time.time()
        img, nel = render(rid, ex, bbox, a.px)
        img.save(png + ".part.png", optimize=True)
        os.replace(png + ".part.png", png)
        places = [] if a.no_places else read_places(pbfs_for(rid), bbox)
        json.dump({"name": rid, "bbox": bbox, "image": rid + ".png", "size": list(img.size), "src": src, "places": places},
                  open(js + ".part", "w"), indent=1)
        os.replace(js + ".part", js)
        log(f"{rid}: {img.size[0]}x{img.size[1]} px from {nel} features, {len(places)} places ({time.time() - t0:.1f} s) -> {png}")
        done += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
