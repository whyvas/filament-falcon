"""Turn label text into polygons (mm) using the bundled Barlow Condensed Black font.

Two variants are produced for every label:
  full    - the letters exactly (multi-material print: white letters fill the holes)
  stencil - letters with 1.2 mm bridges cut through every closed counter (O, A, B, 8 ...)
            so the dark body islands stay attached in the single-material version.
"""
import os
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from shapely.geometry import Polygon, MultiPolygon, box
from shapely import affinity
from shapely.ops import unary_union

FONT = os.path.join(os.path.dirname(__file__), "..", "fonts", "BarlowCondensed-Black.ttf")
TRACKING = 0.10        # extra letter spacing, fraction of cap height (keeps body webs >= ~0.8 mm)
BRIDGE = 1.2
SPACE_FACTOR = 0.9


class _Pen(BasePen):
    def __init__(self, gs):
        super().__init__(gs)
        self.contours, self.cur = [], []

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _qCurveToOne(self, a, b):
        p0 = self.cur[-1]
        for i in range(1, 7):
            u = i / 6
            self.cur.append(tuple((1 - u) ** 2 * p0[k] + 2 * (1 - u) * u * a[k] + u * u * b[k] for k in (0, 1)))

    def _curveToOne(self, a, b, c):
        p0 = self.cur[-1]
        for i in range(1, 9):
            u = i / 8
            self.cur.append(tuple((1 - u) ** 3 * p0[k] + 3 * (1 - u) ** 2 * u * a[k]
                                  + 3 * (1 - u) * u * u * b[k] + u ** 3 * c[k] for k in (0, 1)))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


class Font:
    def __init__(self, path=FONT):
        self.tt = TTFont(path)
        self.gs = self.tt.getGlyphSet()
        self.cmap = self.tt.getBestCmap()
        self.upm = self.tt["head"].unitsPerEm
        self.cap = self.tt["OS/2"].sCapHeight / self.upm
        self._cache = {}

    def glyph(self, ch):
        """Glyph outline in em units (cap height = self.cap)."""
        if ch in self._cache:
            return self._cache[ch]
        name = self.cmap[ord(ch)]
        pen = _Pen(self.gs)
        self.gs[name].draw(pen)
        g = Polygon()
        for c in pen.contours:
            g = g.symmetric_difference(Polygon([(x / self.upm, y / self.upm) for x, y in c]).buffer(0))
        adv = self.gs[name].width / self.upm
        self._cache[ch] = (g, adv)
        return g, adv


_font = None


def font():
    global _font
    if _font is None:
        _font = Font()
    return _font


def _stencil(g, cap):
    """Cut vertical bridges through every hole of glyph g (already in mm)."""
    polys = list(g.geoms) if hasattr(g, "geoms") else [g]
    bars = []
    for p in polys:
        if p.is_empty:
            continue
        xs = sorted(h.centroid.x for h in (Polygon(i) for i in p.interiors))
        merged = []
        for x in xs:
            if merged and abs(x - merged[-1][-1]) < 2.5:
                merged[-1].append(x)
            else:
                merged.append([x])
        minx, miny, maxx, maxy = p.bounds
        for grp in merged:
            x = sum(grp) / len(grp)
            bars.append(box(x - BRIDGE / 2, miny - 1, x + BRIDGE / 2, maxy + 1))
    if not bars:
        return g
    out = g.difference(unary_union(bars))
    parts = [q for q in (out.geoms if hasattr(out, "geoms") else [out]) if q.area > 0.6]
    return unary_union(parts)


def text_shapes(text, cap, cx, cy):
    """Return (full, stencil, width, height) for text with given cap height, centred at cx, cy."""
    f = font()
    s = cap / f.cap
    x = 0.0
    full, sten = [], []
    for ch in text:
        if ch == " ":
            x += f.glyph(" ")[1] * s * SPACE_FACTOR + TRACKING * cap
            continue
        g, adv = f.glyph(ch)
        gm = affinity.translate(affinity.scale(g, s, s, origin=(0, 0)), x, 0)
        full.append(gm)
        sten.append(_stencil(gm, cap))
        x += adv * s + TRACKING * cap
    fu = unary_union(full)
    st = unary_union(sten)
    minx, miny, maxx, maxy = fu.bounds
    dx = cx - (minx + maxx) / 2
    dy = cy - cap / 2
    fu = affinity.translate(fu, dx, dy).simplify(0.01)
    st = affinity.translate(st, dx, dy).simplify(0.01)
    return fu, st, maxx - minx, cap


def to_scad_poly(geom):
    """shapely (Multi)Polygon -> (points, paths) for OpenSCAD polygon()."""
    pts, paths = [], []
    polys = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    for p in polys:
        if p.is_empty:
            continue
        p = p.buffer(0)
        for ring in [p.exterior] + list(p.interiors):
            coords = list(ring.coords)[:-1]
            start = len(pts)
            pts.extend((round(a, 3), round(b, 3)) for a, b in coords)
            paths.append(list(range(start, len(pts))))
    return pts, paths
