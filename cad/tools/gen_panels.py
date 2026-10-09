#!/usr/bin/env python3
"""Generate cad/panels/<ID>.scad + shared/panel_labels.json from layouts.py, and
check every layout (label light boxes vs switch bodies, rails, seams, front nuts)."""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import layouts as L
import glyphs as G

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAD = os.path.join(ROOT, "cad")
WALL, BAND, GAP, SLOT, PAD = 1.6, 20, 0.5, 12.6, 3.0
CUT = {"tog6": (8, 6), "tog6g": (8, 6), "tog12": (13, 9), "btn12": (9, 8), "btn16": (11, 10), "arc19": (13, 12),
       "arc22": (15, 14), "estop22": (15, 21), "led5": (4.5, 4), "ec11": (9, 12), "key19": (14, 13), "pot7": (10, 12), "m3cs": (4, 3.5)}


def rect_circle(r, cx, cy, rad):
    x0, y0, x1, y1 = r
    dx = max(x0 - cx, 0, cx - x1)
    dy = max(y0 - cy, 0, cy - y1)
    return dx * dx + dy * dy < rad * rad - 1e-6


def rect_rect(a, b):
    return a[0] < b[2] - 1e-6 and b[0] < a[2] - 1e-6 and a[1] < b[3] - 1e-6 and b[1] < a[3] - 1e-6


def build(panel):
    errs, labs = [], []
    W, H = panel.w, panel.h
    for lb in panel.labels:
        full, sten, tw, th = G.text_shapes(lb["text"], lb["cap"], lb["x"], lb["y"])
        iw = round(tw + 2 * PAD, 2)
        ih = round(max(SLOT, lb["cap"] + 2 * PAD), 2)
        if ih > SLOT + 1.8:
            errs.append(f"{lb['id']}: light box {ih} too tall for strip ledges")
        holes = sum(len(p.interiors) for p in (sten.geoms if hasattr(sten, "geoms") else [sten]))
        if holes:
            errs.append(f"{lb['id']}: stencil still has {holes} islands")
        op = full.buffer(-0.6, join_style=2).buffer(0.6, join_style=2)
        loss = (full.area - op.area) / full.area
        labs.append(dict(lb, full=full, sten=sten, iw=iw, ih=ih, tw=tw, loss=loss,
                         inner=(lb["x"] - iw / 2, lb["y"] - ih / 2, lb["x"] + iw / 2, lb["y"] + ih / 2),
                         outer=(lb["x"] - iw / 2 - WALL, lb["y"] - ih / 2 - WALL, lb["x"] + iw / 2 + WALL, lb["y"] + ih / 2 + WALL)))
    seam_rects = []
    for side, on in ((-1, panel.seam_l), (1, panel.seam_r)):
        if on:
            for y in (30, H - 30):
                x0 = GAP / 2 if side < 0 else W - GAP / 2 - 10
                seam_rects.append((x0, y - 6, x0 + 10, y + 6))
    for a in labs:
        o = a["outer"]
        if o[0] < GAP / 2 or o[2] > W - GAP / 2 or o[1] < BAND or o[3] > H - BAND:
            errs.append(f"{a['id']}: light box {tuple(round(v,1) for v in o)} leaves the usable area")
        for b in labs:
            if a is not b and rect_rect(a["inner"], b["outer"]):
                errs.append(f"{a['id']}: light box overlaps {b['id']}")
        for c in panel.cuts:
            rb, rf = CUT[c[0]]
            if rect_circle(o, c[1], c[2], rb):
                errs.append(f"{a['id']}: light box hits back of {c[0]} at {c[1:]}")
            minx, miny, maxx, maxy = a["full"].bounds
            if rect_circle((minx, miny, maxx, maxy), c[1], c[2], rf):
                errs.append(f"{a['id']}: letters under front nut/knob of {c[0]} at {c[1:]}")
            if c[0] == "tog6g":
                gx0, gy0, gx1, gy1 = L.GUARD_RECT
                if rect_rect((minx, miny, maxx, maxy), (c[1] + gx0, c[2] + gy0, c[1] + gx1, c[2] + gy1)):
                    errs.append(f"{a['id']}: letters under the toggle guard at {c[1:]}")
        for k in panel.keepouts + seam_rects:
            if rect_rect(o, k):
                errs.append(f"{a['id']}: light box hits keep-out {k}")
    for i, c in enumerate(panel.cuts):
        rb = CUT[c[0]][0]
        if c[2] - rb < BAND + 2 or c[2] + rb > H - BAND - 2 or c[1] - rb < 2.5 or c[1] + rb > W - 2.5:
            errs.append(f"cut {c} too close to rail band / edge")
        for d in panel.cuts[i + 1:]:
            if math.hypot(c[1] - d[1], c[2] - d[2]) < rb + CUT[d[0]][0] - 1:
                errs.append(f"cut {c} collides with {d}")
            if c[0] == "tog6g":
                gx0, gy0, gx1, gy1 = L.GUARD_RECT
                if rect_circle((c[1] + gx0, c[2] + gy0, c[1] + gx1, c[2] + gy1), d[1], d[2], CUT[d[0]][1]):
                    errs.append(f"guard at {c[1:]} collides with {d}")
        for k in seam_rects + (panel.keepouts if c[0] != "m3cs" else []):
            if rect_circle(k, c[1], c[2], rb):
                errs.append(f"cut {c} hits keep-out {k}")
    return labs, errs


def scad_poly(geom):
    pts, paths = G.to_scad_poly(geom)
    return "[[" + ",".join(f"[{x},{y}]" for x, y in pts) + "],[" + ",".join("[" + ",".join(map(str, p)) + "]" for p in paths) + "]]"


def snake(labs):
    rows = {}
    for lb in labs:
        rows.setdefault(round(lb["y"] / 8), []).append(lb)
    out = []
    for i, k in enumerate(sorted(rows, reverse=True)):
        out += sorted(rows[k], key=lambda l: l["x"], reverse=bool(i % 2))
    return out


def main():
    os.makedirs(os.path.join(CAD, "panels"), exist_ok=True)
    all_errs, entries, worst = [], [], (0, "")
    built = {}
    for p in L.PANELS:
        labs, errs = build(p)
        built[p.id] = (p, labs)
        all_errs += [f"{p.id}: {e}" for e in errs]
        for lb in labs:
            if lb["loss"] > worst[0]:
                worst = (lb["loss"], lb["id"])
        out = [f"// GENERATED by cad/tools/gen_panels.py from cad/tools/layouts.py - edit the layout there.",
               f"// {p.title}: {p.where}", f"// Nominal {p.w} x {p.h} mm (printed {p.w - GAP} x {p.h - GAP}).",
               'PART = "preview";', f'PANEL_ID = "{p.id}";', f"W = {p.w};", f"H = {p.h};",
               f"SEAM_L = {'true' if p.seam_l else 'false'};", f"SEAM_R = {'true' if p.seam_r else 'false'};",
               "CUTS = [" + ", ".join(f'["{c[0]}", {c[1]}, {c[2]}]' for c in p.cuts) + "];",
               "SLOTS = [" + ", ".join(f"[{s[0]}, {s[1]}, {s[2]}, {s[3]}]" for s in p.slots) + "];",
               "GROOVES = [" + ", ".join("[" + ", ".join(map(str, g)) + "]" for g in p.grooves) + "];",
               "LABELS = ["]
        for lb in labs:
            out.append(f'  ["{lb["id"]}", {lb["x"]}, {lb["y"]}, {lb["iw"]}, {lb["ih"]},\n   {scad_poly(lb["full"])},\n   {scad_poly(lb["sten"])}],')
        out.append("];")
        out.append("include <../lib/ff_panel.scad>")
        out.append("ff_panel_part(PART);")
        with open(os.path.join(CAD, "panels", f"{p.id}.scad"), "w") as f:
            f.write("\n".join(out) + "\n")
    idx = 0
    for pid in L.STRIP_ORDER:
        p, labs = built[pid]
        for lb in snake(labs):
            entries.append(dict(index=idx, id=lb["id"], panel=pid, text=lb["text"],
                                x_mm=lb["x"], y_mm=lb["y"], box_w_mm=round(lb["iw"], 1),
                                cap_height_mm=lb["cap"], est_leds_60_per_m=max(1, round(lb["iw"] / 16.67))))
            idx += 1
    missing = set(built) - set(L.STRIP_ORDER)
    if missing:
        all_errs.append(f"panels missing from STRIP_ORDER: {missing}")
    ids = [e["id"] for e in entries]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        all_errs.append(f"duplicate label ids {dup}")
    doc = {
        "version": 1,
        "written_by": "cad/tools/gen_panels.py (edit cad/tools/layouts.py)",
        "units": "mm",
        "coordinates": "panel-local, origin bottom-left of the nominal panel seen from the front, x right, y up",
        "font": "Barlow Condensed Black (SIL OFL), letters cut through the full 3 mm panel",
        "strip": "ONE WS2812B strip (60 LED/m assumed) driven by Falcon Command. Labels are listed in the order the strip visits them; segment start/count go in shared/led_segments.json once measured.",
        "panel_order": L.STRIP_ORDER,
        "panels": [dict(id=p.id, title=p.title, location=p.where, nominal_w_mm=p.w, nominal_h_mm=p.h) for p in L.PANELS],
        "labels": entries,
    }
    with open(os.path.join(ROOT, "shared", "panel_labels.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    print(f"{len(L.PANELS)} panels, {len(entries)} labels, est. {sum(e['est_leds_60_per_m'] for e in entries)} LEDs; worst stroke loss {worst[0]:.2f} ({worst[1]})")
    for e in all_errs:
        print("ERROR", e)
    return 1 if all_errs else 0


if __name__ == "__main__":
    sys.exit(main())
