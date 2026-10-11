#!/usr/bin/env python3
"""Dimensioned drawings of the Filament Falcon frame + motion -> frame/drawings/*.svg|png + frame_drawings.pdf
Run frame/frame_model.py first (it writes frame/generated/geometry.json)."""
import json, math, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MPoly, Rectangle, FancyArrowPatch, Circle, Arc
from matplotlib.backends.backend_pdf import PdfPages
import shapely.geometry as sg
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frame_model as F

OUT = os.path.join(F.HERE, "drawings")
os.makedirs(OUT, exist_ok=True)
GEO = json.load(open(os.path.join(F.GEN, "geometry.json")))
WOOD = {"2x4": "#d8b47c", "ply18": "#ecd3a6", "ply12": "#f1dfbd", "ply6": "#e0c8a0", "foam": "#b05050"}
EDGE = "#5b4325"
BLUE = "#1d4f91"
TH, AD, AU = F.RECLINE, F.ALPHA_DN, F.ALPHA_UP


def inch(mm):
    return f'{mm / 25.4:.1f}"' if abs(mm) < 610 else f"{int(mm / 25.4 // 12)}' {mm / 25.4 % 12:.1f}\""


def dim(ax, p0, p1, off, text=None, side=1, fs=7, color="#b0201e"):
    (x0, y0), (x1, y1) = p0, p1
    L = math.hypot(x1 - x0, y1 - y0)
    if L == 0:
        return
    nx, ny = -(y1 - y0) / L, (x1 - x0) / L
    a = (x0 + nx * off, y0 + ny * off); b = (x1 + nx * off, y1 + ny * off)
    ax.plot([x0, a[0]], [y0, a[1]], color=color, lw=0.4); ax.plot([x1, b[0]], [y1, b[1]], color=color, lw=0.4)
    ax.add_patch(FancyArrowPatch(a, b, arrowstyle="<|-|>", mutation_scale=6, color=color, lw=0.6))
    t = text or f"{L:.0f} ({inch(L)})"
    ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    if ang > 90 or ang < -90:
        ang += 180
    ax.text((a[0] + b[0]) / 2 + nx * 16 * side, (a[1] + b[1]) / 2 + ny * 16 * side, t, fontsize=fs, color=color,
            ha="center", va="center", rotation=ang, bbox=dict(fc="white", ec="none", pad=0.4, alpha=0.85))


def note(ax, xy, txt, xytext, fs=7):
    ax.annotate(txt, xy=xy, xytext=xytext, fontsize=fs, arrowprops=dict(arrowstyle="-", lw=0.5, color="#333"),
                bbox=dict(fc="#fffbe6", ec="#999", lw=0.4, pad=1.5))


def pose_M(group, th, al):
    return F.group_pose(group, th, al)


def corners3d(p):
    if p.kind == "box":
        sx, sy, sz = p.size
        c = np.array([(a, b, c_, 1) for a in (0, sx) for b in (0, sy) for c_ in (0, sz)], float)
        return (p.M @ c.T).T[:, :3]
    q = np.array(p.pts)
    out = []
    for x in (p.x0, p.x0 + p.thick):
        out += [(x, -d, z) for d, z in q]
    return np.array(out)


def proj2d(p, view, th, al):
    """2D outline of a part: side -> (y, z) [front at the right], front -> (x, z), top -> (x, y)."""
    M = pose_M(p.group, th, al)
    if p.kind == "xpoly" and view == "side":
        q = np.array([(0.0, -d, z) for d, z in p.pts])
        q = F.xf(M, q)
        return q[:, 1:3]
    c = F.xf(M, corners3d(p))
    idx = {"side": (1, 2), "front": (0, 2), "top": (0, 1)}[view]
    pts = c[:, idx]
    hull = sg.MultiPoint([tuple(v) for v in pts]).convex_hull
    if hull.geom_type != "Polygon":
        return None
    return np.array(hull.exterior.coords)[:-1]


def draw(ax, view, th, al, groups=("fixed", "cradle", "pod"), alpha=1.0, ls="-", ec=EDGE, skip=(), only=None, fc=None, lw=0.5, z=1):
    for p in F.PARTS:
        if p.group not in groups or any(s in p.name for s in skip) or (only and not any(o in p.name for o in only)):
            continue
        q = proj2d(p, view, th, al)
        if q is not None:
            ax.add_patch(MPoly(q, closed=True, fc=fc or WOOD.get(p.mat, "#ccc"), ec=ec, lw=lw, alpha=alpha, ls=ls, zorder=z))


def monitor_boxes(al):
    """corner sets of the 2 monitors (pod frame) at pod angle al."""
    out = []
    for k, m in (("monitor_L", (618.0, 363.5, 36.0, 26.5)), ("monitor_R", (616.5, 366.5, 38.6, 26.4))):
        g, M0 = F.PART_PLACE[k]
        W, H, back, sag = m
        c = np.array([(x, y, z, 1) for x in (-W / 2, W / 2) for y in (-H / 2, H / 2) for z in (-back, sag)], float)
        c = (F.R4(al - AD, F.PP) @ M0 @ c.T).T[:, :3]
        out.append((k, c))
    return out


def draw_monitors(ax, view, al, alpha=0.9, ls="-"):
    idx = {"side": (1, 2), "front": (0, 2), "top": (0, 1)}[view]
    for k, c in monitor_boxes(al):
        h = sg.MultiPoint([tuple(v) for v in c[:, idx]]).convex_hull
        ax.add_patch(MPoly(np.array(h.exterior.coords), closed=True, fc="#222", ec="k", lw=0.6, alpha=alpha, ls=ls, zorder=3))


def draw_manikin(ax, m, x, th, view="side", fc="#e8b27a", ec="#8a5a2b", alpha=0.55, ls="-", grp="cradle"):
    M = F.R4(th, F.CP) if grp == "cradle" else np.eye(4)
    polys = []
    for a, b, r in F.manikin_segments(m, x):
        a2, b2 = F.xf(M, a[None])[0], F.xf(M, b[None])[0]
        i = {"side": (1, 2), "front": (0, 2), "top": (0, 1)}[view]
        polys.append(sg.LineString([tuple(a2[list(i)]), tuple(b2[list(i)])]).buffer(r, 16) if np.linalg.norm(a2 - b2) > 1e-6 else sg.Point(tuple(a2[list(i)])).buffer(r, 16))
    from shapely.ops import unary_union
    u = unary_union(polys)
    for g in (u.geoms if hasattr(u, "geoms") else [u]):
        ax.add_patch(MPoly(np.array(g.exterior.coords), closed=True, fc=fc, ec=ec, lw=0.6, alpha=alpha, ls=ls, zorder=4))


def setup(title, w=16.5, h=11.7):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_aspect("equal"); ax.axis("off")
    fig.suptitle(title, fontsize=13, fontweight="bold", x=0.02, ha="left")
    fig.text(0.02, 0.015, "The Filament Falcon - frame v0.3 (recline + drop-down pod, single pod actuator)   |   all dimensions mm (inches)   |   2x4 = 38 x 89 mm, ply 18 mm unless noted   |   "
             "generated by frame/make_drawings.py from frame/frame_model.py", fontsize=7, color="#555")
    return fig, ax


def save(fig, name, pdf):
    for ext in ("svg", "png"):
        fig.savefig(os.path.join(OUT, f"{name}.{ext}"), dpi=110 if ext == "png" else None, bbox_inches="tight")
    pdf.savefig(fig, bbox_inches="tight")
    plt.close(fig)


def Y(d):
    return -d


# ------------------------------------------------------------------ sheets
def front(pdf):
    fig, ax = setup(f"1. Front elevation, FLIGHT position (cradle reclined {TH:.0f} deg, pod down) - nose box front skin removed")
    draw(ax, "front", TH, AD, groups=("fixed",), skip=("Nose box front skin", "Nose box lid", "Cushion dad", "Back cushion dad"))
    draw(ax, "front", TH, AD, groups=("cradle",), alpha=0.6)
    draw(ax, "front", TH, AD, groups=("pod",), alpha=0.45, skip=("bumper",))
    draw_monitors(ax, "front", AD, alpha=0.75)
    for nm, (k, x) in F.KID_SEATING.items():
        draw_manikin(ax, F.KIDS[k], x, TH, "front", alpha=0.35)
    W2_ = F.XSKIN
    dim(ax, (-W2_, 0), (W2_, 0), -120)
    dim(ax, (-W2_, 0), (-W2_, F.CASE["top"]), 110, f"towers {F.CASE['top']:.0f} ({inch(F.CASE['top'])})")
    hs = GEO["clearances"]["overall_height_swept"]
    dim(ax, (W2_, 0), (W2_, hs), -110, f"pod swept height {hs} ({inch(hs)}) - needs >= 1.95 m ceiling")
    dim(ax, (-F.SEAT_X, 160), (F.SEAT_X, 160), 0, f"seat / monitor centres {2 * F.SEAT_X:.0f} ({inch(2 * F.SEAT_X)})", fs=7)
    dim(ax, (-F.CI, 60), (F.CI, 60), 0, f"between casings {2 * F.CI:.0f} ({inch(2 * F.CI)})", fs=7)
    dim(ax, (-F.CC['x'], 640), (F.CC['x'], 640), 0, f"TD2220 console {2 * F.CC['x']:.0f}", fs=7)
    ax.text(-1500, 1950, "Pod (blue-grey) carries both monitors, the 4 dash panels (lower band) and the 3 overhead panels\n"
            "(top band). The cradle carries the seats, the TD2220 centre console, both side consoles and the sticks.\n"
            "Dad's dais (behind) is fixed.", fontsize=8, bbox=dict(fc="#eef4ff", ec="#88a"))
    ax.set_xlim(-1550, 1550); ax.set_ylim(-300, 2150)
    save(fig, "01_front_elevation", pdf)


def side(pdf):
    fig, ax = setup(f"2. Side elevation + MOTION GEOMETRY (from the right, front at the right).  Solid = BOARDING (upright, pod up {AU:.0f} deg), "
                    f"blue dashed = FLIGHT (recline {TH:.0f} deg, pod down {AD:.0f} deg)", 15, 14)
    skip_fixed = ("Side skin", "Casing inner wall R", "Casing front wall R", "Casing top R", "Casing back R", "Tower post outer R", "Casing post outer R",
                  "Strut anchor post R", "Nose post", "Casing tie R", "Cushion", "Back cushion")
    draw(ax, "side", 0, AU, groups=("fixed",), skip=skip_fixed + ("Casing", "Tower post outer L", "Casing post outer L"), alpha=0.9)
    # casing L ghost (behind)
    draw(ax, "side", 0, AU, groups=("fixed",), only=("Casing inner wall L",), alpha=0.15)
    # boarding pose
    draw(ax, "side", 0, AU, groups=("cradle",), alpha=0.75, skip=("Cushion", "Back cushion"))
    draw(ax, "side", 0, AU, groups=("pod",), alpha=0.6, skip=("bumper", "Pod cheek R"))
    draw_monitors(ax, "side", AU, alpha=0.6)
    draw_manikin(ax, F.KIDS["12yr"], -F.SEAT_X, 0, alpha=0.45)
    # flight pose
    draw(ax, "side", TH, AD, groups=("cradle",), alpha=0.25, ls="--", ec=BLUE, fc="#cfe0f5", skip=("Cushion", "Back cushion"), lw=0.8, z=2)
    draw(ax, "side", TH, AD, groups=("pod",), alpha=0.25, ls="--", ec=BLUE, fc="#cfe0f5", skip=("bumper", "Pod cheek R"), lw=0.8, z=2)
    draw_monitors(ax, "side", AD, alpha=0.5, ls="--")
    draw_manikin(ax, F.KIDS["12yr"], -F.SEAT_X, TH, fc="#9fc3ef", ec=BLUE, alpha=0.5, ls="--")
    draw_manikin(ax, F.KIDS["6yr"], F.SEAT_X, TH, fc="none", ec="#2a7", alpha=0.9, ls=":")
    draw_manikin(ax, F.DAD, 0.0, 0, grp="fixed", alpha=0.35)
    # pivots
    for (d, z), t in ((F.CP, f"CRADLE PIVOT\n25 mm shaft, 2 x UCP205\n({F.CP[0]:.0f}, {F.CP[1]:.0f})"), (F.PP, f"POD PIVOT = reclined\n12 yr head centre\n({F.PP[0]:.0f}, {F.PP[1]:.0f})")):
        ax.add_patch(Circle((Y(d), z), 20, fc=BLUE, ec="k", zorder=6))
        ax.text(Y(d) + 40, z - 120, t, fontsize=7, color=BLUE, zorder=7)
    # pod leading-edge arc + inner clearance circle
    lead = F.pod_pt(F.R_BAND[0], F.POD_T[0], AD)
    r_lead = math.hypot(lead[0] - F.PP[0], lead[1] - F.PP[1])
    a0 = math.degrees(math.atan2(lead[1] - F.PP[1], -(lead[0] - F.PP[0])))
    ax.add_patch(Arc((Y(F.PP[0]), F.PP[1]), 2 * r_lead, 2 * r_lead, theta1=a0, theta2=a0 + (AU - AD), color="#b0201e", lw=1.4, ls="-", zorder=6))
    ax.text(Y(F.PP[0]) + r_lead * math.cos(math.radians(a0 + 20)) + 30, F.PP[1] + r_lead * math.sin(math.radians(a0 + 20)),
            f"pod chin path (r {r_lead:.0f})\n{AU - AD:.0f} deg of travel", color="#b0201e", fontsize=7, zorder=7)
    r_in = F.R_SCREEN - 26
    ax.add_patch(Circle((Y(F.PP[0]), F.PP[1]), r_in, fc="none", ec="#2a7", lw=0.8, ls=":", zorder=5))
    ax.text(Y(F.PP[0]) - 40, F.PP[1] - r_in - 70, f"the pod body never enters this {r_in:.0f} mm radius around the pivot\n"
            "(it rotates AROUND the head - it cannot approach the face)", fontsize=7, color="#2a7", ha="center")
    # seat-back top arc
    sb = (F.SEAT_BACK["d"][1], F.SEAT_BACK["top"])
    r_sb = math.hypot(sb[0] - F.CP[0], sb[1] - F.CP[1]); a_sb = math.degrees(math.atan2(sb[1] - F.CP[1], -(sb[0] - F.CP[0])))
    ax.add_patch(Arc((Y(F.CP[0]), F.CP[1]), 2 * r_sb, 2 * r_sb, theta1=a_sb, theta2=a_sb + TH, color=BLUE, lw=1, ls="-.", zorder=6))
    # actuators + struts (both poses)
    def ram(anchor, pin0, pivot, rot, col, lw, lab=None):
        p = F.rot_dz(rot, pivot, *pin0)
        ax.plot([Y(anchor[0]), Y(p[0])], [anchor[1], p[1]], color=col, lw=lw, alpha=0.8, solid_capstyle="round", zorder=7)
        ax.plot([Y(anchor[0])], [anchor[1]], "o", color="k", ms=3, zorder=8)
    ca, pa, st = GEO["cradle"]["actuator"], GEO["pod"]["actuator"], GEO["pod"]["strut"]
    for rot, col in ((0, "#555"), (TH, BLUE)):
        ram(ca["anchor"], ca["pin"], F.CP, rot, col, 5)
    for rot, col in ((AU - AD, "#555"), (0, BLUE)):
        ram(pa["anchor"], pa["pin"], F.PP, rot, col, 5)
        ram(st["anchor"], st["pin"], F.PP, rot, "#111" if rot else BLUE, 2.5)
    note(ax, (Y(ca["anchor"][0] + 120), ca["anchor"][1] + 60), f"2 x cradle actuators in the nose box\n{ca['act_stroke_in']}\" stroke, travel {ca['travel']:.0f} mm,\n"
         f"{ca['Lmin']:.0f} -> {ca['Lmax']:.0f} pin-pin, PUSH to recline", (Y(ca["anchor"][0]) - 650, 900))
    note(ax, (Y(pa["anchor"][0]), pa["anchor"][1]), f"ONE pod actuator (LEFT casing only)\n{pa['act_stroke_in']}\" stroke, {pa['rating_N']} N self-locking, travel {pa['travel']:.0f} mm,\n"
         f"{pa['Lmin']:.0f} -> {pa['Lmax']:.0f} pin-pin, retract = pod up, extend = pod down", (Y(pa["anchor"][0]) - 200, 120))
    tt = GEO["pod"]["torque_tube"]
    tc = F.pod_pt(F.TT["r0"] + F.TT["side"] / 2, F.TT["t"])
    ax.add_patch(Rectangle((Y(tc[0]) - 25, tc[1] - 25), 50, 50, fc="#6d7680", ec="k", lw=0.8, zorder=9))
    tu = F.rot_dz(AU - AD, F.PP, *tc)
    ax.add_patch(Rectangle((Y(tu[0]) - 25, tu[1] - 25), 50, 50, fc="#6d7680", ec="k", lw=0.8, zorder=9))
    note(ax, (Y(tc[0]), tc[1]), "TORQUE TUBE 2x2x1/8\" steel, cheek to cheek\n(drives the right cheek; "
         f"{tt['stiffness_Nm_per_deg']:.0f} N*m/deg)", (Y(tc[0]) + 250, tc[1] + 330))
    note(ax, (Y(st["anchor"][0]), st["anchor"][1]), f"2 x gas struts, one per side ({st['F1']:.0f} N ext / ~{st['F2']:.0f} N compressed,\n"
         f"~{st['Lmax']:.0f} mm ext., >= {st['stroke'] + 10:.0f} mm stroke): pod LIFT-biased +{min(GEO['pod']['net_torque_with_struts_Nm']):.0f}..+{max(GEO['pod']['net_torque_with_struts_Nm']):.0f} N*m", (Y(st["anchor"][0]) - 150, 1600))
    # ramp
    r0, r1 = GEO["ramp"]["p0"], GEO["ramp"]["p1"]
    note(ax, (Y((r0[0] + r1[0]) / 2), (r0[1] + r1[1]) / 2), "fixed CRUSH-ZONE RAMP: 120 mm under the\nreclined seat backs, nothing can be trapped\nbetween seat backs and floor", (Y(1700), 420))
    cl = GEO["clearances"]
    kk = {(r["kid"], r["body"]): r for r in cl["pod_vs_reclined_kids"]}
    thigh = min(r["gap_mm"] for r in cl["pod_vs_reclined_kids"] if r["body"] in ("thigh", "shin"))
    head = min(r["gap_mm"] for r in cl["pod_vs_reclined_kids"] if r["body"] == "head")
    txt = (f"MOTION: hold FLIGHT -> cradle reclines 0 -> {TH:.0f} deg (~{GEO['cradle']['actuator']['travel'] / 6:.0f} s), then the pod swings down {AU:.0f} -> {AD:.0f} deg "
           f"(~{GEO['pod']['actuator']['travel'] / 8:.0f} s).  Hold BOARD -> pod up first, then seats upright.\n"
           f"Clearances at the hard stops (12 yr manikin = worst case): pod chin to thighs/shins {thigh} mm (ISO 13854 leg >= 180), pod to head {head} mm, "
           f"pod parked UP: lowest point over the seats z = {cl['pod_up_lowest_z_over_seats']} mm.\n"
           f"Eye -> screen centre: 12 yr {cl['eyes']['PILOT']['eye_to_screen_mm']} mm, 6 yr {cl['eyes']['OPS']['eye_to_screen_mm']} mm.  "
           f"Pod mass {GEO['pod']['mass_kg']:.0f} kg (model), CG {GEO['pod']['cg_radius']} mm from its pivot.")
    ax.text(Y(F.L) - 50, 2120, txt, fontsize=8, bbox=dict(fc="#eef4ff", ec="#88a"), va="top")
    dim(ax, (Y(F.L), 0), (0, 0), -110)
    dim(ax, (0, 0), (0, F.CASE["top"]), -90, f"towers {F.CASE['top']:.0f}")
    dim(ax, (Y(F.CP[0]), 0), (Y(F.CP[0]), F.CP[1]), 60, f"{F.CP[1]:.0f}", fs=6)
    dim(ax, (0, -60), (Y(F.CP[0]), -60), 0, f"{F.CP[0]:.0f}", fs=6)
    dim(ax, (0, -200), (Y(F.PP[0]), -200), 0, f"pod pivot {F.PP[0]:.0f} ({inch(F.PP[0])}) behind the front", fs=7)
    dim(ax, (Y(F.PP[0]) - 60, 0), (Y(F.PP[0]) - 60, F.PP[1]), 0, f"{F.PP[1]:.0f}", fs=7)
    dim(ax, (Y(F.DAIS["d"][0]), F.DAIS["z"]), (Y(F.DAIS["d"][0]), 0), -40, f"dais {F.DAIS['z']:.0f}", fs=6)
    ax.set_xlim(Y(F.L) - 120, 260); ax.set_ylim(-320, 2150)
    save(fig, "02_side_motion_geometry", pdf)


def top(pdf):
    fig, ax = setup("3. Plan view, BOARDING position (from above, front at the top; pod parked up shown dashed)")
    draw(ax, "top", 0, AU, groups=("fixed",), skip=("Casing top", "Nose box lid", "Cushion dad", "Back cushion dad"))
    draw(ax, "top", 0, AU, groups=("cradle",), alpha=0.9, skip=("Cushion", "Back cushion"))
    draw(ax, "top", 0, AU, groups=("pod",), alpha=0.12, ls="--", ec=BLUE, fc="#cfe0f5", skip=("bumper",))
    for nm, (k, x) in F.KID_SEATING.items():
        ax.text(x, Y(750), f"{nm}\nseat {F.SEAT_W:.0f} wide", ha="center", va="center", fontsize=7, fontweight="bold")
    labels = [((0, Y(750)), "TD2220\n21.5\" touch"), ((-170, Y(470)), "pilot\nstick"), ((130, Y(470)), "OPS_SIDE"),
              ((-730, Y(680)), "PILOT_SIDE\nthrottle\n+ gear"), ((730, Y(680)), "ops\nstick"), ((0, Y(2190)), "COMMANDER (dad)\nfixed, no recline"),
              ((420, Y(2000)), "CMD_A\nCMD_B"), ((-370, Y(2080)), "pod latch\nrelease\nlevers"), ((0, Y(140)), "NOSE BOX: 2 cradle actuators (lid = foot step)"),
              ((-820, Y(1600)), "casing L:\npod pivot,\nstrut, THE pod\nactuator,\nlatch"), ((820, Y(1600)), "casing R:\npivot, strut,\nlatch\n(no actuator)")]
    for (x, yy), t in labels:
        ax.text(x, yy, t, ha="center", va="center", fontsize=7)
    dim(ax, (-F.XSKIN, 0), (F.XSKIN, 0), 90)
    dim(ax, (-F.XSKIN, Y(F.L)), (-F.XSKIN, 0), 100)
    dim(ax, (-F.SEAT_X, Y(1000)), (F.SEAT_X, Y(1000)), 0, f"seat centres {2 * F.SEAT_X:.0f}", fs=7)
    dim(ax, (-290, Y(980)), (290, Y(980)), -40, "580 between seat boxes (TD2220 trim 559)", fs=6)
    ax.set_xlim(-1300, 1300); ax.set_ylim(Y(F.L) - 200, 250)
    save(fig, "03_plan_view", pdf)


def mechanism(pdf):
    fig = plt.figure(figsize=(18, 12.5))
    fig.suptitle("4. Mechanism sizing, locks, hard stops and the hardwired interlock", fontsize=13, fontweight="bold", x=0.02, ha="left")
    ca, pa, st, pod, cr = GEO["cradle"]["actuator"], GEO["pod"]["actuator"], GEO["pod"]["strut"], GEO["pod"], GEO["cradle"]
    L = [f"CRADLE (both kid seats, consoles, TD2220) - recline 0 -> {TH:.0f} deg about the 25 mm shaft at ({F.CP[0]:.0f}, {F.CP[1]:.0f})",
         f"  design load: 2 occupants x 50 kg + cradle ~{GEO['cradle']['mass_kg_design'] - 100:.0f} kg  -> gravity torque {min(cr['torque_Nm']):.0f} .. +{max(cr['torque_Nm']):.0f} N*m",
         "  (negative = wants to sit up: rests on the front rubber pads; positive = wants to lie back: rests on the recline stop blocks)",
         f"  2 actuators, {ca['act_stroke_in']}\" ({ca['act_stroke_in'] * 25.4:.0f} mm) stroke, retracted ~{ca['act_retracted_mm']:.0f} pin-pin; used travel {ca['Lmin']:.0f} -> {ca['Lmax']:.0f} mm",
         f"  peak force {ca['F_each_max']:.0f} N EACH (incl. +40 N*m friction) -> BUY 2 x 1500 N (330 lbf) 12 V, self-locking (acme), ~5-8 mm/s",
         "",
         f"POD (2 monitors, 7 panels, torque tube, ~{pod['mass_kg']:.0f} kg) - swings {AU:.0f} -> {AD:.0f} deg about ({F.PP[0]:.0f}, {F.PP[1]:.0f}) = the reclined 12 yr head centre",
         f"  gravity torque {min(pod['gravity_torque_Nm']):.0f} .. +{max(pod['gravity_torque_Nm']):.0f} N*m;  with the 2 gas struts: +{min(pod['net_torque_with_struts_Nm']):.0f} .. +{max(pod['net_torque_with_struts_Nm']):.0f} N*m",
         f"  -> LIFT-BIASED over the whole travel: if the actuator or its clevis pin fails the pod rises to the UP stop (away from the kids);",
         f"     at DOWN the spring pawls + the self-locking actuator hold it; at UP the struts press it on the stop and the pawls lock it.",
         f"  gas struts: 2 x ~{st['F1']:.0f} N (F1, extended, progression {1 + st['prog']:.1f}), ~{st['Lmax']:.0f} mm extended, >= {st['stroke'] + 10:.0f} mm stroke, M8 eye ends, rod DOWN, damped",
         f"  ONE pod actuator (left casing, x = {pa['x']:.0f}), {pa['act_stroke_in']}\" stroke (retracted ~{pa['act_retracted_mm']:.0f}), travel {pa['Lmin']:.0f} -> {pa['Lmax']:.0f} mm, pin ({pa['pin'][0]:.0f}, {pa['pin'][1]:.0f}), anchor ({pa['anchor'][0]:.0f}, {pa['anchor'][1]:.0f})",
         f"  force: normal (2 struts, +25 N*m friction) <= {pa['F_normal_max']:.0f} N;  one strut failed {pa['F_one_strut_failed']:.0f} N;  BOTH struts failed {pa['F_each_strut_failed']:.0f} N",
         f"  -> BUY 1 x {pa['rating_N']} N ({pa['rating_N'] / 4.448:.0f} lbf) 12 V self-locking, <= 10 mm/s (~{pa['travel'] / 10:.0f} s); margin {pa['margin_strut_failed']:.1f}x struts-failed, {pa['margin_normal']:.1f}x normal",
         f"  TORQUE TUBE {GEO['pod']['torque_tube']['section']}, {GEO['pod']['torque_tube']['length_mm']} mm cheek to cheek, J = {GEO['pod']['torque_tube']['J_mm4'] / 1e3:.0f}e3 mm4, "
         f"{GEO['pod']['torque_tube']['stiffness_Nm_per_deg']:.0f} N*m/deg:",
         *[f"    {k:<42s} {v['T_Nm']:>4.0f} N*m, twist {v['twist_deg']:.2f} deg, chin {v['chin_offset_mm']:>4.1f} mm, {v['shear_MPa']:.0f} MPa"
           for k, v in GEO['pod']['torque_tube']['cases'].items()],
         "    ends: welded 6 mm plates, 4 x M10 through each 36 mm cheek + 6 mm backing plate.",
         "    Set the RIGHT cheek's stops 1-2 mm 'later' than the left so the actuator never twists the tube",
         "    against a stop; the far side is carried by the tube, not by racking the cheeks.",
         "",
         "HARD STOPS (steel, bolted; they - not the actuators - define the end positions):",
         f"  cradle upright: rails on 6 mm rubber pads (z 114);  cradle reclined: seat boxes land on rubber stop blocks at {TH:.0f} deg (+0.5)",
         f"  pod DOWN: 6 mm steel stop pin on each cheek crank lands on a rubber-faced steel angle in the casing at {AD:.0f} deg",
         f"  pod UP: same pin on a second stop at {AU:.0f} deg.  External limit switches stop the actuators 2-3 mm before each stop.",
         "",
         "LOCKS (mechanical, both ends):",
         "  pod: spring-loaded steel pawl in each casing drops into a notch in a 6 mm steel latch plate on the cheek at UP and at DOWN",
         "       (ramped like a door latch: it clicks in by itself).  Dad releases both pawls with one Bowden-cable lever LEFT of his seat;",
         "       a micro switch on the lever is in series with the pod motors -> the pod can only move while dad holds the lever",
         "       AND the switch (two-hand hold-to-run).  'Pawl engaged' micro switches feed the interlock below.",
         "  cradle: self-locking actuators + stops; the pod interlock keeps it from moving under a lowered pod.",
         "",
         "HARDWIRED INTERLOCK (no microcontroller can move anything; the game only READS 3 isolated senses):",
         "  12V+ --[20A fuse]--[MOTION key]--[E-STOP NC]--+--CREW POS (ON)-OFF-(ON) hold-to-run DPDT (drives 4 relays)",
         "  ONE pod limit set: POD_UP + POD_DOWN roller switches on the LEFT (driven) cheek only; the right side has only its pawl switch.",
         "  FLIGHT (toggle up):",
         "    cradle RECLINE runs  while  POD_UP_LOCKED (both pawls)  AND  NOT CRADLE_RECLINED limit",
         "    pod DOWN runs        while  CRADLE_RECLINED (both sides) AND  release lever held  AND  NOT POD_DOWN limit",
         "  BOARD (toggle down):",
         "    pod UP runs          while  release lever held  AND  NOT POD_UP limit",
         "    cradle UPRIGHT runs  while  POD_UP limit AND POD_UP_LOCKED  AND  NOT CRADLE_UPRIGHT limit",
         "  => the pod can never come down unless the seats are fully reclined, and the seats never move under a lowered pod.",
         "  Pod chin carries a pressure-sensitive SAFETY EDGE (NC) in series with 'pod DOWN'.",
         "  Limit switches: roller-lever micro switches (NC) on the stops, 1N5408 diode across each so you can always reverse.",
         "  Relays: 4 x 30 A automotive SPDT (Bosch-type) wired as 2 H-bridges (cradle: 2 actuators in parallel; pod: 1 actuator); 12 V 20 A supply.",
         "  Position senses (READ-ONLY, 3 separate NO micro switches, PC817 optos -> Falcon Command GPIO39/40/41):",
         "    CRADLE_RECLINED, POD_DOWN_LOCKED (pawl in DOWN notch), POD_UP_LOCKED (optional). Never in the motor path.",
         ]
    fig.text(0.02, 0.95, "\n".join(L), family="monospace", fontsize=8.3, va="top")
    ax = fig.add_axes([0.66, 0.56, 0.32, 0.33])
    al = pod["alphas"]
    ax.plot(al, pod["gravity_torque_Nm"], label="pod gravity", color="#b0201e")
    ax.plot(al, pod["net_torque_with_struts_Nm"], label="gravity + 2 gas struts (lift bias)", color=BLUE, lw=2)
    ax.axhline(0, color="k", lw=0.5); ax.set_xlabel("pod angle (deg): 40 = down / flight, 95 = up / boarding"); ax.set_ylabel("N*m (+ = lifts)")
    ax.legend(fontsize=7, loc="lower right"); ax.grid(alpha=0.3); ax.set_title("pod counterbalance", fontsize=9)
    ax3 = ax.twinx()
    ax3.plot(al, pa["F_normal"], color="#2a7d2a", ls="--", label="actuator force, normal")
    ax3.plot(al, [abs(g / a) for g, a in zip(pod["gravity_torque_Nm"], pa["arm_m"])], color="#d07a00", ls=":", label="actuator force, both struts failed")
    ax3.axhline(pa["rating_N"], color="#2a7d2a", lw=0.8); ax3.text(al[0], pa["rating_N"] * 0.95, f"rating {pa['rating_N']} N", fontsize=7, va="top", color="#2a7d2a")
    ax3.set_ylabel("single actuator force (N)"); ax3.set_ylim(0, pa["rating_N"] * 1.1); ax3.legend(fontsize=7, loc="upper left")
    ax2 = fig.add_axes([0.66, 0.12, 0.32, 0.33])
    ax2.plot(cr["thetas"], cr["torque_Nm"], color="#b0201e", label="gravity (2 x 50 kg)")
    ax2.plot(cr["thetas"], [f * 2 * abs(a) for f, a in zip(ca["F_each"], ca["arm_m"])], color=BLUE, label="actuator capacity used (2 x F x arm)")
    ax2.axhline(0, color="k", lw=0.5); ax2.set_xlabel("recline (deg)"); ax2.set_ylabel("N*m"); ax2.legend(fontsize=7); ax2.grid(alpha=0.3)
    ax2.set_title("cradle torque", fontsize=9)
    fig.text(0.02, 0.015, "The Filament Falcon - frame v0.3 (single pod actuator) | numbers from frame/generated/geometry.json (frame_model.py) | ISO 13854 min. gaps: finger 25, hand/arm 100-120, foot 120, leg 180 mm",
             fontsize=7, color="#555")
    save(fig, "04_mechanism_interlock", pdf)


def clearances_sheet(pdf):
    fig = plt.figure(figsize=(16.5, 11.7))
    fig.suptitle("5. Pinch points, guards and computed clearances", fontsize=13, fontweight="bold", x=0.02, ha="left")
    cl = GEO["clearances"]
    L = ["Computed by frame_model.py from the CAD (manikins: 95th pct 12 yr / 50th pct 6 yr, capsule bodies).", "",
         "POD (sweeping 95 -> 40 deg) vs the RECLINED kids - closest approach anywhere in the travel:"]
    for r in cl["pod_vs_reclined_kids"][:10]:
        L.append(f"  {r['kid']:5s} {r['body']:9s} {r['gap_mm']:4d} mm  (pod at {r['pod_alpha']:5.1f} deg, {r['pod_part']})")
    L += ["", "CRADLE (reclining with the pod parked up) vs fixed structure / pod / dad:"]
    for r in cl["cradle_vs_structure"][:12]:
        L.append(f"  {r['gap_mm']:4d} mm  {r['moving']:28s} <-> {r['other']:32s} at {r['recline_deg']:4.1f} deg")
    L += ["", "POD vs structure:"]
    for r in cl["pod_vs_structure"][:5]:
        L.append(f"  {r['gap_mm']:4d} mm  {r['moving']} <-> {r['other']} at {r['pod_alpha']} deg")
    L += ["", f"Pod cheek in its casing slot: {cl['cheek_x_clearance_mm']['inner_wall']:.0f} mm to the inner post, {cl['cheek_x_clearance_mm']['tower_post']:.0f} mm to the outer post (strut lives there).",
          "", "HOW EACH PINCH POINT IS HANDLED:",
          "  1 pod chin vs knees/shins/hands : hard stop keeps >= 180 mm (leg); 25 mm foam + NC safety edge on the chin; slow (<= 10 mm/s)",
          "  2 pod vs heads                  : pivot = head centre -> constant radius, the pod cannot close on a head (>= 250 mm)",
          "  3 cheeks in the casing slots    : 48 mm slot, cheek 36 mm -> 6 mm each side (< finger) + brush strip both edges",
          "  4 struts / pod actuator         : fully inside the casings (12 mm ply, screwed lids); only the cheek crosses the slot",
          "  5 cradle front vs nose box      : >= 30 mm gap all the way (finger 25) + brush strip on the actuator slots",
          "  6 cradle sides vs floor         : 6 mm hardboard skirts on the cradle sides overlap the fixed base skins (telescoping guard)",
          "  7 under the reclining seat backs: fixed crush-zone ramp 120 mm below the reclined backs (arm); foam on top",
          "  8 seat backs vs casings         : 60 mm side gap, motion is parallel to the wall (no closing edge)",
          "  9 kids' arms vs casing front edge: arm-to-casing >= 35 mm laterally at full recline; 'hands on lap' + dad watches",
          " 10 dad                           : fixed seat, nothing moves within his reach except the pod back (>= 400 mm from his head)",
          " 11 cables across both pivots     : printed pivot clamps <= 60 mm from the axis + 200 mm U service loop in braided sleeve",
          ]
    fig.text(0.02, 0.95, "\n".join(L), family="monospace", fontsize=8.6, va="top")
    fig.text(0.02, 0.015, "The Filament Falcon - frame v0.3", fontsize=7, color="#555")
    save(fig, "05_pinch_points_clearances", pdf)


def cheek(pdf):
    fig, ax = setup("6. Pod cheek (2 per side, 18 mm ply, laminated) - cutting template coordinates, pivot at (0,0), screen axis to the left", 16.5, 11)
    a = math.radians(AD)
    e = np.array([-math.cos(a), math.sin(a)]); t = np.array([math.sin(a), math.cos(a)])
    def rt(dz):
        v = np.array(dz) - np.array(F.PP)
        return float(v @ e), float(v @ t)
    pts = [rt(p) for p in F.CHEEK]
    q = np.array([(-r, tt) for r, tt in pts])
    ax.add_patch(MPoly(q, closed=True, fc=WOOD["ply18"], ec=EDGE, lw=1))
    for i, (x_, y_) in enumerate(q):
        ax.plot(x_, y_, "o", ms=2, color="k")
        ax.text(x_ + 8, y_ + 8, f"{i}", fontsize=6)
    ax.add_patch(Circle((0, 0), 26, fc="white", ec="k")); ax.text(30, -40, "25 mm shaft\nUCF205 bearing", fontsize=7)
    for nm, p in (("strut eye bolt M8", GEO["pod"]["strut"]["pin"]), ("actuator clevis (LEFT cheek only)", GEO["pod"]["actuator"]["pin"])):
        r_, t_ = rt(p)
        ax.add_patch(Circle((-r_, t_), 9, fc="#888", ec="k")); ax.text(-r_ + 14, t_ - 6, nm, fontsize=7)
    for nm, (t0, t1, r0, r1) in (("lower band (dash)", (-395, -200, 610, 628)), ("top band", (200, 340, 610, 628)), ("back sheet", (-395, 340, 700, 712)),
                                         ("TORQUE TUBE 2x2\" + 6 mm end plate (4 x M10)", (F.TT["t"] - 25.4, F.TT["t"] + 25.4, F.TT["r0"], F.TT["r1"]))):
        ax.add_patch(Rectangle((-r1, t0), r1 - r0, t1 - t0, fc="none", ec=BLUE, ls="--", lw=0.8)); ax.text(-r1 - 5, (t0 + t1) / 2, nm, fontsize=7, ha="right", color=BLUE)
    tab = "vertex  r(mm, toward screen)  t(mm, up the screen)\n" + "\n".join(f"{i:3d}   {r_:8.0f}   {t_:8.0f}" for i, (r_, t_) in enumerate(pts))
    ax.text(250, 380, tab, family="monospace", fontsize=6.5, va="top")
    ax.text(-850, -560, "Latch plate (6 mm steel, bolted to the cheek, centred on the pivot): notches at the UP and DOWN angles.\n"
            "Stop pin (12 mm steel) through the crank lobe hits rubber-faced steel angles in the casing at both ends.\n"
            "Print this sheet 1:1 in tiles or transfer the coordinates; both cheeks of a side are glued + screwed together (36 mm).",
            fontsize=8, bbox=dict(fc="#fffbe6", ec="#999"))
    ax.set_xlim(-900, 700); ax.set_ylim(-620, 520)
    save(fig, "06_pod_cheek_template", pdf)


def bay(pdf):
    fig, ax = setup("7. Panel bay detail - how every printed panel bolts to the plywood bands (40 mm grid, M5 into T-nuts)", 16.5, 9)
    ox = 0
    ax.add_patch(Rectangle((ox, 0), 18, 60, fc=WOOD["ply18"], ec=EDGE)); ax.text(ox + 9, -12, "18 mm ply\nband", ha="center", va="top", fontsize=7)
    ax.add_patch(Rectangle((ox + 18, 20), 3, 160, fc="#2b2d33", ec="k")); ax.text(ox + 30, 185, "printed panel, 3 mm", fontsize=7)
    ax.add_patch(Rectangle((ox + 0, 120), 18, 60, fc=WOOD["ply18"], ec=EDGE))
    for zz in (30, 170):
        ax.add_patch(Rectangle((ox - 3, zz - 2.75), 26.5, 5.5, fc="#aaa", ec="k", lw=0.5))
        ax.add_patch(Rectangle((ox + 21, zz - 5), 2.5, 10, fc="#888", ec="k", lw=0.5))
        ax.add_patch(Rectangle((ox - 4, zz - 9.5), 1.5, 19, fc="#666", ec="k", lw=0.5))
    for zz in (70, 110):
        ax.add_patch(Rectangle((ox + 5.2, zz), 12.8, 18, fc="#40434b", ec="k", lw=0.4))
    ax.text(ox - 20, 100, "light boxes\n+ switches\nlive in the\nopening", fontsize=7, ha="right", va="center")
    ax.text(ox + 30, 30, "M5 x 20 button head + washer from the front,\n4-prong M5 T-nut pressed into the back of the band\n"
            "(the pod turns the panels face-DOWN when parked: use nyloc T-nuts or a drop of threadlocker)", fontsize=7, va="center")
    ax.text(ox + 30, 100, "Panel = n x 40 mm nominal (printed 0.5 mm smaller).\nTop + bottom 20 mm bands sit flat on the plywood.", fontsize=7, va="center")
    bx, bz = 330, 0
    ax.add_patch(Rectangle((bx - 30, bz - 40), 460, 240, fc=WOOD["ply18"], ec=EDGE))
    ax.add_patch(Rectangle((bx + 1, bz + 20), 398, 120, fc="white", ec=EDGE))
    ax.add_patch(Rectangle((bx, bz), 199.75, 160, fc="#2b2d33", ec="k", alpha=0.25))
    ax.add_patch(Rectangle((bx + 200.25, bz), 199.75, 160, fc="#2b2d33", ec="k", alpha=0.25))
    for x in range(20, 400, 40):
        for zz in (10, 150):
            ax.add_patch(Circle((bx + x, bz + zz), 3.5, fc="k"))
    dim(ax, (bx, bz - 40), (bx + 400, bz - 40), -25, "2 panels x 200 = 400 (15.7\")")
    dim(ax, (bx + 1, bz + 20), (bx + 399, bz + 20), 25, "opening 398 x 120 (jigsaw)", fs=7)
    dim(ax, (bx + 430, bz), (bx + 430, bz + 160), 0, "160", fs=7)
    ax.text(bx + 200, bz + 80, "PILOT_DASH_A | PILOT_DASH_B  (pod lower band)\nOVERHEAD_A|B|C: same idea, 600 x 120, pod top band", ha="center", fontsize=8)
    ax.set_xlim(-120, 820); ax.set_ylim(-170, 230)
    save(fig, "07_panel_bay_detail", pdf)


def main():
    for f in os.listdir(OUT):
        if f[:2].isdigit():
            os.remove(os.path.join(OUT, f))
    with PdfPages(os.path.join(OUT, "frame_drawings.pdf")) as pdf:
        front(pdf); side(pdf); top(pdf); mechanism(pdf); clearances_sheet(pdf); cheek(pdf); bay(pdf)
    print("drawings written to", OUT)


if __name__ == "__main__":
    main()
