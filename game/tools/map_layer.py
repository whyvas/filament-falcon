#!/usr/bin/env python3
"""Light vector map layer for the Commander AREAS map (scripts/ui/map_layer.gd): town / village
names, roads, rivers and lakes, from the cached Geofabrik extracts. Runs on the game PC (pyosmium;
osmium-tool pre-filters the tags first when installed, which is much faster). The AREAS runner
calls it after an area's OSM step, the map's BUILD MAP LAYER button runs it in the background
(`area_manager.py maplayer`), and so can you:

  python3 tools/map_layer.py [--pbf FILE ...] [--force]

For every osm/*.osm.pbf (default) it writes ~/.local/share/filament-falcon/maps/<extract>.ffml
(a few MB for a province), skipped while up to date. Zoom tiers (the map shows a tier below a
zoom threshold, coarse geometry first):
  roads   motorway/trunk 0, primary 1, secondary 2, tertiary 3
  rivers  by named length: > 80 km 0, > 20 km 1, other rivers / canals 2
  lakes   > 100 km2 0, > 10 km2 1, > 1 km2 2, > 0.05 km2 3 (outer rings; islands not cut out)
  places  city, town, village, hamlet / suburb (name, population), shown by zoom in the game
Each line / ring is stored at up to 3 Douglas-Peucker levels (0.006 deg, 0.001 deg, 0.0001 deg
tolerance), only the levels its tier can be seen at.

File (little endian): b"FFML", u32 version, u32 json length, JSON {"src", "bbox", "places":
[[name, kind, pop, lat, lon], ...], "counts"}, then records: u8 kind (0 road, 1 river, 2 lake),
u8 tier, u16 0, then 3 x (u32 n, n x (i32 lon*1e6, i32 lat*1e6)).
"""
import argparse, glob, json, math, os, shutil, struct, subprocess, sys, tempfile, time

DATA = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "filament-falcon")
OSM = os.path.join(DATA, "osm")
OUT = os.path.join(DATA, "maps")
VER = 1
ROAD_TIER = {"motorway": 0, "trunk": 0, "primary": 1, "secondary": 2, "tertiary": 3}
PLACE_KINDS = ("city", "town", "village", "hamlet", "suburb")
TOL = (0.006, 0.001, 0.0001)            # per level, degrees
TIER_MAX_DPP = (0.4, 0.05, 0.012, 0.003)   # scripts/ui/map_layer.gd: tier t drawn below this deg/px
LEVEL_MIN_DPP = (0.02, 0.003, 0.0)      # level l drawn at deg/px >= this


def log(*a):
    print("[map_layer]", *a, flush=True)


def levels_for(tier):
    return [l for l in range(3) if TIER_MAX_DPP[tier] > LEVEL_MIN_DPP[l]]


def simplify(pts, tol):
    """Douglas-Peucker on [(lon, lat)] (lon scaled by cos lat at the first point)."""
    n = len(pts)
    if n < 3:
        return pts
    k = math.cos(math.radians(pts[0][1]))
    keep = [False] * n
    keep[0] = keep[-1] = True
    st = [(0, n - 1)]
    t2 = tol * tol
    while st:
        i, j = st.pop()
        ax, ay = pts[i][0] * k, pts[i][1]
        bx, by = pts[j][0] * k, pts[j][1]
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        best, bi = -1.0, -1
        for m in range(i + 1, j):
            px, py = pts[m][0] * k - ax, pts[m][1] - ay
            if L > 0:
                t = max(0.0, min(1.0, (px * dx + py * dy) / L))
                ex, ey = px - t * dx, py - t * dy
            else:
                ex, ey = px, py
            d = ex * ex + ey * ey
            if d > best:
                best, bi = d, m
        if best > t2:
            keep[bi] = True
            st.append((i, bi))
            st.append((bi, j))
    return [p for p, kk in zip(pts, keep) if kk]


def length_km(pts):
    s = 0.0
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        s += math.hypot((x1 - x0) * 111.32 * math.cos(math.radians(y0)), (y1 - y0) * 110.54)
    return s


def area_km2(ring):
    if len(ring) < 3:
        return 0.0
    k = 111.32 * math.cos(math.radians(ring[0][1]))
    s = 0.0
    for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]):
        s += x0 * k * y1 * 110.54 - x1 * k * y0 * 110.54
    return abs(s) * 0.5


def read(pbf):
    import osmium
    src, tmp = pbf, None
    if shutil.which("osmium"):
        tmp = os.path.join(tempfile.gettempdir(), f"map_layer_{os.getpid()}.osm.pbf")
        r = subprocess.run(["osmium", "tags-filter", "--overwrite", "-o", tmp, pbf, "n/place", "w/highway=motorway,trunk,primary,secondary,tertiary",
                            "w/waterway=river,canal", "wr/natural=water", "wr/water", "wr/waterway=riverbank", "wr/landuse=reservoir,basin"],
                           capture_output=True)
        src = tmp if r.returncode == 0 else pbf
        log(f"{os.path.basename(pbf)}: " + ("tags pre-filtered by osmium-tool" if src == tmp else "osmium-tool failed, reading the whole file"))
    else:
        log(f"{os.path.basename(pbf)}: reading the whole file (apt install osmium-tool makes this much faster)")
    places, roads, rivers, lakes = [], [], [], []

    class H(osmium.SimpleHandler):
        def node(self, o):
            k = o.tags.get("place")
            if k in PLACE_KINDS and o.location.valid() and o.tags.get("name"):
                pop = o.tags.get("population", "")
                places.append([o.tags["name"], k, int(pop) if pop.isdigit() else 0, round(o.location.lat, 5), round(o.location.lon, 5)])

        def way(self, o):
            t = o.tags
            hw, ww = t.get("highway"), t.get("waterway")
            if hw not in ROAD_TIER and ww not in ("river", "canal"):
                return
            g = [(nd.lon, nd.lat) for nd in o.nodes if nd.location.valid()]
            if len(g) < 2:
                return
            if hw in ROAD_TIER:
                roads.append((ROAD_TIER[hw], g))
            else:
                rivers.append((ww, t.get("name", ""), g))

        def area(self, o):
            t = o.tags
            if not (t.get("natural") == "water" or "water" in t or t.get("waterway") == "riverbank" or t.get("landuse") in ("reservoir", "basin")):
                return
            for ring in o.outer_rings():
                r = [(nd.lon, nd.lat) for nd in ring if nd.location.valid()]
                if len(r) >= 4:
                    lakes.append(r[:-1] if r[0] == r[-1] else r)

    H().apply_file(src, locations=True, idx="flex_mem")
    if tmp and os.path.exists(tmp):
        os.remove(tmp)
    return places, roads, rivers, lakes


def build(pbf, out):
    t0 = time.time()
    places, roads, rivers, lakes = read(pbf)
    feats = []                                   # (kind, tier, pts)
    feats += [(0, t, g) for t, g in roads]
    named = {}
    for ww, nm, g in rivers:
        if nm:
            named[nm] = named.get(nm, 0.0) + length_km(g)
    for ww, nm, g in rivers:
        L = named.get(nm, 0.0) if nm else 0.0
        feats.append((1, 0 if L > 80 else (1 if L > 20 else 2), g))
    for r in lakes:
        a = area_km2(r)
        if a > 0.05:
            feats.append((2, 0 if a > 100 else (1 if a > 10 else (2 if a > 1 else 3)), r))
    rank = {k: i for i, k in enumerate(PLACE_KINDS)}
    places.sort(key=lambda p: (rank[p[1]], -p[2]))
    bb = [90.0, 180.0, -90.0, -180.0]
    body = bytearray()
    cnt = [0, 0, 0]
    for kind, tier, pts in feats:
        lv = levels_for(tier)
        recs = []
        for l in range(3):
            if l in lv:
                s = simplify(pts, TOL[l])
                if kind == 2 and len(s) < 3:
                    s = []
                recs.append(s)
            else:
                recs.append([])
        if not any(recs):
            continue
        cnt[kind] += 1
        body += struct.pack("<BBH", kind, tier, 0)
        for s in recs:
            body += struct.pack("<I", len(s))
            body += struct.pack("<%di" % (2 * len(s)), *[int(round(v * 1e6)) for p in s for v in p])
            for x, y in s:
                bb = [min(bb[0], y), min(bb[1], x), max(bb[2], y), max(bb[3], x)]
    for p in places:
        bb = [min(bb[0], p[3]), min(bb[1], p[4]), max(bb[2], p[3]), max(bb[3], p[4])]
    meta = {"src": src_key(pbf), "bbox": [round(v, 4) for v in bb], "places": places,
            "counts": {"roads": cnt[0], "rivers": cnt[1], "lakes": cnt[2], "places": len(places)}}
    js = json.dumps(meta, separators=(",", ":"), ensure_ascii=False).encode()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out + ".part", "wb") as f:
        f.write(b"FFML" + struct.pack("<II", VER, len(js)) + js + body)
    os.replace(out + ".part", out)
    log(f"{os.path.basename(out)}: {cnt[0]} roads, {cnt[1]} rivers, {cnt[2]} lakes, {len(places)} places, "
        f"{os.path.getsize(out) / 1e6:.1f} MB ({time.time() - t0:.0f} s)")


def src_key(pbf):
    return {"pbf": os.path.basename(pbf), "size": os.path.getsize(pbf), "mtime": int(os.path.getmtime(pbf)), "ver": VER}


def out_for(pbf):
    return os.path.join(OUT, os.path.basename(pbf).replace(".osm.pbf", "") + ".ffml")


def up_to_date(pbf):
    out = out_for(pbf)
    if not os.path.exists(out):
        return False
    try:
        with open(out, "rb") as f:
            hd = f.read(12)
            if hd[:4] != b"FFML":
                return False
            n = struct.unpack("<I", hd[8:12])[0]
            return json.loads(f.read(n)).get("src") == src_key(pbf)
    except (OSError, ValueError, struct.error):
        return False


def extracts():
    return sorted(p for p in glob.glob(os.path.join(OSM, "*.osm.pbf")) if ".cut_" not in p and "map_layer_" not in p)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pbf", action="append", help="extract(s) to convert (default: every osm/*.osm.pbf)")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    try:
        import osmium  # noqa: F401
    except ImportError:
        log("pyosmium missing: pip install --user --break-system-packages osmium")
        return 2
    pbfs = a.pbf or extracts()
    if not pbfs:
        log(f"no extracts in {OSM} yet (the AREAS OSM step or tools/fetch_assets.sh downloads them)")
        return 0
    for p in pbfs:
        if not a.force and up_to_date(p):
            log(f"{os.path.basename(out_for(p))}: up to date")
            continue
        build(p, out_for(p))
    return 0


if __name__ == "__main__":
    sys.exit(main())
