#!/usr/bin/env python3
"""Offline test for tools/map_layer.py: writes a tiny .osm.pbf (a town, a village, a motorway, a
tertiary road, a named river and a lake) into a throw-away XDG_DATA_HOME, converts it and reads
the .ffml back. Needs pyosmium.   python3 tools/test_map_layer.py"""
import json, os, struct, subprocess, sys, tempfile

try:
    import osmium
except ImportError:
    print("SKIP: pyosmium missing")
    sys.exit(0)

d = tempfile.mkdtemp()
osm = os.path.join(d, "filament-falcon", "osm")
os.makedirs(osm)
pbf = os.path.join(osm, "tiny-latest.osm.pbf")
w = osmium.SimpleWriter(pbf)
nid = [0]


def node(lat, lon, tags=None):
    nid[0] += 1
    w.add_node(osmium.osm.mutable.Node(id=nid[0], location=(lon, lat), tags=tags or {}, version=1))
    return nid[0]


town = node(45.96, -66.64, {"place": "town", "name": "Testville", "population": "60000"})
vil = node(45.90, -66.50, {"place": "village", "name": "Hamletton"})
mw = [node(45.9 + i * 0.01, -66.7 + i * 0.012) for i in range(20)]
tr = [node(45.95, -66.6 + i * 0.001) for i in range(5)]
rv = [node(45.95 + 0.001 * (i % 2), -66.9 + i * 0.05) for i in range(30)]   # ~110 km "river"
lk = [node(46.0 + a, -66.4 + b) for a, b in ((0, 0), (0, 0.2), (0.1, 0.2), (0.1, 0))]
ways = [(mw, {"highway": "motorway"}), (tr, {"highway": "tertiary"}), (rv, {"waterway": "river", "name": "Big River"}),
        (lk + [lk[0]], {"natural": "water"})]
for i, (nds, tags) in enumerate(ways):
    w.add_way(osmium.osm.mutable.Way(id=100 + i, nodes=nds, tags=tags, version=1))
w.close()
env = dict(os.environ, XDG_DATA_HOME=d)
here = os.path.dirname(os.path.abspath(__file__))
r = subprocess.run([sys.executable, os.path.join(here, "map_layer.py")], env=env, capture_output=True, text=True)
print(r.stdout.strip())
out = os.path.join(d, "filament-falcon", "maps", "tiny-latest.ffml")
ok = r.returncode == 0 and os.path.exists(out)
if ok:
    b = open(out, "rb").read()
    n = struct.unpack("<I", b[8:12])[0]
    meta = json.loads(b[12:12 + n])
    c = meta["counts"]
    ok = (b[:4] == b"FFML" and c == {"roads": 2, "rivers": 1, "lakes": 1, "places": 2} and meta["places"][0][0] == "Testville")
    # the river is > 80 km -> tier 0: all three levels present, level 2 keeps the zig-zag
    o = 12 + n
    tiers = []
    while o < len(b):
        kind, tier = b[o], b[o + 1]
        o += 4
        ns = []
        for _ in range(3):
            k = struct.unpack("<I", b[o:o + 4])[0]
            ns.append(k)
            o += 4 + 8 * k
        tiers.append((kind, tier, ns))
    print(tiers)
    ok = ok and any(k == 1 and t == 0 and ns[2] == 30 for k, t, ns in tiers) and any(k == 0 and t == 3 and ns[:2] == [0, 0] for k, t, ns in tiers)
    r2 = subprocess.run([sys.executable, os.path.join(here, "map_layer.py")], env=env, capture_output=True, text=True)
    ok = ok and "up to date" in r2.stdout
print("MAP LAYER TEST:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
