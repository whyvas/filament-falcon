#!/usr/bin/env python3
"""The Filament Falcon - wooden frame + motion model (single source of truth).

Motion concept ("launch recline + drop-down pod"):
  1. RECLINE: both kid seats sit on one shared CRADLE that pivots on a 25 mm shaft
     just behind/below the seats and leans back 35 deg (astronaut launch pose).
  2. POD: the instrument pod (both monitors, dash panels, overhead strip) is a
     curved-ish box on two side cheeks that pivot on the side towers.  The pivot
     axis goes through the head centre of the reclined (12 yr) kid, so every point
     of the pod moves on a circle AROUND the kid's head and can never approach it.
     Pod UP = parked over/behind the heads for boarding, pod DOWN = 35 deg in front
     of the reclined faces.  Hard stops limit it in both directions.
  Dad (COMMANDER) sits on a fixed raised dais behind; he does not recline and has
  no pod (see frame/README.md for the reasoning).

Generates:
  frame/generated/frame.scad      fixed / cradle / pod groups + poses + placements
  frame/generated/geometry.json   key numbers (mechanism, forces, clearances) for the docs
  frame/cut_list.csv / .md        every wooden part with its size
Run frame/make_drawings.py afterwards for the drawings.

Conventions: mm.  x = to the kids' RIGHT, y = FORWARD, z = UP.  Front of the frame
is y = 0; d = -y = distance back from the front.  Lumber: 2x4 = 38 x 89 mm,
plywood 18 / 12 / 6 mm.
"""
import csv, json, math, os, re
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
T2, W2 = 38.0, 89.0
G = 9.81
RHO = {"2x4": 480.0, "ply18": 600.0, "ply12": 600.0, "ply6": 750.0}    # kg/m3

# ------------------------------------------------------------------ main layout
L = 2450.0                    # base length (front nose .. dais rear)
XS = (930.0, 968.0)           # side sill / tower x range (each side, mirrored)
CI = 690.0                    # casing inner wall (kid side face)
XSKIN = 980.0                 # outside of the side skins
SEAT_X = 460.0                # kid seat centre lines (+-); between seats: TD2220 console
SEAT_W = 340.0
CP = (840.0, 200.0)           # cradle pivot (d, z): 25 mm shaft
RECLINE = 35.0                # deg
ALPHA_DN, ALPHA_UP = 40.0, 95.0   # pod elevation (deg) of the screen axis: down (flight) / up (boarding)
R_SCREEN = 600.0              # pod pivot -> monitor face (screen centre)

# kid manikins in CRADLE coords (upright pose): (d, z) of joints, radii.  Rough
# 95th-percentile 12 yr (150 cm, 45 kg) and 50th-percentile 6 yr (116 cm, 21 kg).
KIDS = {
    "12yr": dict(head=(815.0, 1165.0), head_r=95.0, neck=(830.0, 1040.0), shoulder=(845.0, 960.0), hip=(820.0, 560.0),
                 knee=(406.0, 677.0), ankle=(420.0, 300.0), toe=(372.0, 265.0), elbow=(830.0, 720.0), hand=(640.0, 640.0),
                 r=dict(torso=115.0, thigh=75.0, shin=50.0, foot=45.0, arm=45.0, neck=50.0), sh_half=150.0, mass=45.0),
    "6yr": dict(head=(825.0, 1015.0), head_r=85.0, neck=(840.0, 915.0), shoulder=(850.0, 860.0), hip=(840.0, 545.0),
                knee=(545.0, 560.0), ankle=(505.0, 300.0), toe=(450.0, 245.0), elbow=(850.0, 690.0), hand=(700.0, 600.0),
                r=dict(torso=85.0, thigh=55.0, shin=38.0, foot=35.0, arm=33.0, neck=38.0), sh_half=110.0, mass=21.0),
}
KID_SEATING = {"PILOT": ("12yr", -SEAT_X), "OPS": ("6yr", SEAT_X)}     # who sits where in the renders (either works)
DAD = dict(head=(2265.0, 1460.0), head_r=105.0, neck=(2280.0, 1330.0), shoulder=(2290.0, 1240.0), hip=(2280.0, 790.0),
           knee=(1855.0, 790.0), ankle=(1810.0, 330.0), toe=(1720.0, 270.0), elbow=(2230.0, 990.0), hand=(1980.0, 860.0),
           r=dict(torso=150.0, thigh=90.0, shin=60.0, foot=50.0, arm=55.0, neck=60.0), sh_half=210.0, mass=110.0)

# dad dais / seat / console (fixed)
DAIS = dict(x=600.0, d=(1700.0, L), z=250.0)
DAD_SEAT = dict(w=520.0, d=(1960.0, 2410.0), top=670.0, back_top=1560.0)
CMD = dict(x=(300.0, 540.0), d=(1800.0, 2200.0), top=950.0)

# cradle (upright coords)
RAIL_X = (770.0, 808.0)
CR_D = (320.0, 880.0)         # rail front .. rear (rear end at the pivot)
CR_Z = (120.0, 209.0)         # rails (rest on rubber pads on the base crosses, top at z 120)
FOOT_Z = 227.0                # footrest top
SEAT_BOX = dict(d=(560.0, 940.0), top=420.0)
SEAT_BACK = dict(d=(940.0, 958.0), top=1300.0)
CC = dict(x=280.0, d=(560.0, 940.0), z_rear=560.0, z_front=600.0)    # centre (TD2220) console
FP = dict(x=280.0, d=(380.0, 560.0), top=470.0)                      # front pedestal (joystick + OPS_SIDE)
SIDE_C = dict(x=(630.0, 830.0), d=(560.0, 800.0), top=600.0)         # side consoles

DEG = math.radians


def rot_dz(phi_deg, pivot, d, z):
    """rotate([+phi,0,0]) about a pivot, in (d, z): points above the pivot go rearward (+d)."""
    c, s = math.cos(DEG(phi_deg)), math.sin(DEG(phi_deg))
    rd, rz = d - pivot[0], z - pivot[1]
    return pivot[0] + rd * c + rz * s, pivot[1] - rd * s + rz * c


def R4(phi_deg, pivot_dz):
    """4x4 world transform for rotate([phi,0,0]) about the x-parallel axis through (d, z)."""
    c, s = math.cos(DEG(phi_deg)), math.sin(DEG(phi_deg))
    P = np.array([0.0, -pivot_dz[0], pivot_dz[1]])
    R = np.eye(4); R[1, 1], R[1, 2], R[2, 1], R[2, 2] = c, -s, s, c
    T = np.eye(4); T[:3, 3] = P
    Ti = np.eye(4); Ti[:3, 3] = -P
    return T @ R @ Ti


def recline_pt(p, th=RECLINE):
    return rot_dz(th, CP, *p)


# pod pivot = reclined 12 yr head centre (rounded)
_h = recline_pt(KIDS["12yr"]["head"])
PP = (round(_h[0] / 5) * 5, round(_h[1] / 5) * 5)


def e_dir(alpha):   # unit (d, z) along the screen axis (pivot -> screen)
    return np.array([-math.cos(DEG(alpha)), math.sin(DEG(alpha))])


def t_dir(alpha):   # unit (d, z) "up the screen"
    return np.array([math.sin(DEG(alpha)), math.cos(DEG(alpha))])


def pod_pt(r, t, alpha=ALPHA_DN):
    """pod local (r along the screen axis, t up the screen) -> world (d, z)."""
    return tuple(np.array(PP) + r * e_dir(alpha) + t * t_dir(alpha))


# ------------------------------------------------------------------ parts
class Part:
    """kind 'box': M (local->world, pose 0) + size; kind 'xpoly': plate in a y-z plane,
    pts = [(d, z)] at pose 0, x0..x0+thick."""
    def __init__(self, name, mat, group, note="", M=None, size=None, pts=None, x0=None, thick=None, cut=True, color=None):
        self.name, self.mat, self.group, self.note = name, mat, group, note
        self.M, self.size, self.pts, self.x0, self.thick = M, size, pts, x0, thick
        self.cut, self.color = cut, color

    @property
    def kind(self):
        return "box" if self.M is not None else "xpoly"


PARTS = []


def mat_cols(a, b, c, o):
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = a, b, c, o
    return M


def add_box(name, mat, group, x0, x1, d0, d1, z0, z1, note="", **k):
    M = mat_cols([1, 0, 0], [0, 1, 0], [0, 0, 1], [x0, -d1, z0])
    PARTS.append(Part(name, mat, group, note, M=M, size=(x1 - x0, d1 - d0, z1 - z0), **k))


def add_xpoly(name, mat, group, x0, thick, pts, note="", **k):
    PARTS.append(Part(name, mat, group, note, pts=[tuple(map(float, p)) for p in pts], x0=x0, thick=thick, **k))


def add_seg(name, mat, group, x0, x1, p0, p1, h=W2, note="", **k):
    """Board between two (d, z) points, h wide (in the y-z plane), spanning x0..x1 (thickness)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    u = (p1 - p0) / np.linalg.norm(p1 - p0)
    n = np.array([-u[1], u[0]])
    q = [p0 + n * h / 2, p1 + n * h / 2, p1 - n * h / 2, p0 - n * h / 2]
    add_xpoly(name, mat, group, x0, x1 - x0, q, note, **k)


def add_pod_box(name, mat, x0, x1, r0, r1, t0, t1, note="", **k):
    """Box in pod coords (down pose): x, r (screen axis), t (up the screen)."""
    e, t = e_dir(ALPHA_DN), t_dir(ALPHA_DN)
    ew = np.array([0, -e[0], e[1]]); tw = np.array([0, -t[0], t[1]])
    o = np.array([x0, -PP[0], PP[1]]) + r0 * ew + t0 * tw
    # columns (t, x, r) are right-handed: t x x = r
    M = mat_cols(tw, [1, 0, 0], ew, o)
    PARTS.append(Part(name, mat, "pod", note, M=M, size=(t1 - t0, x1 - x0, r1 - r0), **k))


def both(fn, name, *a, **k):
    """mirror helper for parts defined by an (x0, x1) range on the right side."""
    pass


SIDES = ((-1, "L"), (1, "R"))


def xr(s, a, b):
    return (min(s * a, s * b), max(s * a, s * b))


# ---- FIXED: base
for s, nm in SIDES:
    add_box(f"Sill {nm}", "2x4", "fixed", *xr(s, *XS), 0, L, 0, W2, "on edge, full length")
add_box("Base cross, nose rear", "2x4", "fixed", -XS[0], XS[0], 222.0, 311.0, 0.0, T2, "2x4 laid FLAT (actuators pass over it)")
add_box("Base cross, cradle front", "2x4", "fixed", -XS[0], XS[0], 400.0, 489.0, 0.0, T2, "2x4 laid FLAT; carries the cradle rest pads")
for nm, d0 in (("Base cross, nose front", 0.0),
               ("Base cross, cradle pivot", CP[0] - T2 / 2), ("Base cross, casing front", 1262.0), ("Base cross, dais front", DAIS["d"][0]),
               ("Base cross, dais mid", 2080.0), ("Base cross, rear", L - T2)):
    add_box(nm, "2x4", "fixed", -XS[0], XS[0], d0, d0 + T2, 0, W2, "on edge between the sills")
for s, nm in SIDES:   # rubber-padded rests for the cradle rails (upright hard stop)
    add_box(f"Cradle rest pad {nm}", "2x4", "fixed", *xr(s, RAIL_X[0] - 10, RAIL_X[1] + 10), 400.0, 489.0, T2, CR_Z[0] - 6,
            "2x4 offcut on the cradle-front base cross + 6 mm rubber: upright hard stop", cut=False)
# cradle pivot pedestals (outboard of the rails) with SHF25 shaft supports
for s, nm in SIDES:
    add_box(f"Cradle pivot pedestal {nm}", "2x4", "fixed", *xr(s, 815.0, 904.0), CP[0] - 44.5, CP[0] + 44.5, W2, CP[1] - 18,
            "2 x 2x4 offcuts laminated (89 x 76) on the pivot cross; SHF25 shaft support on top", cut=False)
    add_box(f"Cradle pivot pedestal {nm} (block)", "2x4", "fixed", *xr(s, 815.0, 904.0), CP[0] - 44.5, CP[0] + 44.5, W2, W2 + 1,
            "", cut=False)
# recline hard stop (under the seat-back foot)
for s, nm in SIDES:
    add_box(f"Recline stop block {nm}", "2x4", "fixed", *xr(s, 380.0, 540.0), 905.0, 994.0, W2, 125.0,
            "2x4 offcut + 10 mm rubber on the pivot/casing cross area; seat box rear bottom lands here at 35 deg", cut=False)
for nm, d0 in (("Base cross, recline stops", 905.0),):
    add_box(nm, "2x4", "fixed", -XS[0], XS[0], d0, d0 + W2, 0, W2 - 51, "2x4 laid FLAT (38 high) between the sills", cut=True)

# ---- FIXED: nose box (houses the 2 cradle actuators) - closed 12 mm ply box
NOSE = dict(d=(0.0, 300.0), z=470.0)
for s, nm in SIDES:
    add_box(f"Nose post front {nm}", "2x4", "fixed", *xr(s, XS[0] - T2, XS[0]), 0.0, W2, W2, NOSE["z"] - 12, "corner post")
    add_box(f"Nose post rear {nm}", "2x4", "fixed", *xr(s, XS[0] - T2, XS[0]), 179.0, 268.0, W2, NOSE["z"] - 12, "corner post")
add_box("Nose box front skin", "ply12", "fixed", -XSKIN, XSKIN, -12.0, 0.0, 0.0, NOSE["z"], "12 mm ply, full width")
add_box("Nose box lid", "ply12", "fixed", -XS[1], XS[1], 0.0, NOSE["d"][1], NOSE["z"] - 12, NOSE["z"], "screwed down (service lid), carpet on top = foot step")
add_box("Nose box rear wall", "ply12", "fixed", -XS[0], XS[0], NOSE["d"][1] - 32, NOSE["d"][1] - 20, W2, NOSE["z"] - 12,
        "2 slots 80 x 360 for the actuators + brush strip; >= 30 mm gap to the cradle front")

# ---- FIXED: side towers + casings (pod pivots, struts, actuators, latches live inside)
CASE = dict(d=(1262.0, 1960.0), x_in=CI, top=1112.0)
for s, nm in SIDES:
    add_box(f"Tower post outer {nm}", "2x4", "fixed", *xr(s, *XS), PP[0] - 44.5, PP[0] + 44.5, W2, CASE["top"] - 12,
            "pod pivot: 25 mm shaft in a 4-bolt flange bearing / SHF25 + 6 mm steel plate on the post")
    add_box(f"Tower post inner {nm}", "2x4", "fixed", *xr(s, CI + 12, CI + 50), PP[0] - 44.5, PP[0] + 44.5, W2, CASE["top"] - 12,
            "inner shaft support (the 25 mm pod shaft is carried at both ends)")
    for dd in (CASE["d"][0], CASE["d"][1] - T2):
        add_box(f"Casing post {nm} d{int(dd)}", "2x4", "fixed", *xr(s, CI + 12, CI + 50), dd, dd + T2, W2, CASE["top"] - 12, "casing corner post")
        add_box(f"Casing post outer {nm} d{int(dd)}", "2x4", "fixed", *xr(s, *XS), dd, dd + T2, W2, CASE["top"] - 12, "casing corner post")
    add_box(f"Casing tie {nm}", "2x4", "fixed", *xr(s, CI + 50, XS[0]), CASE["d"][1] - 89 - T2, CASE["d"][1] - T2, CASE["top"] - 50, CASE["top"] - 12,
            "top tie inner/outer posts")
    add_box(f"Side skin (casing) {nm}", "ply12", "fixed", *xr(s, XS[1], XSKIN), CASE["d"][0], CASE["d"][1], 0.0, CASE["top"], "12 mm ply outer skin")
    add_box(f"Casing back {nm}", "ply12", "fixed", *xr(s, CI, XS[1]), CASE["d"][1], CASE["d"][1] + 12, 0.0, CASE["top"], "")
    add_box(f"Side skin (nose) {nm}", "ply12", "fixed", *xr(s, XS[1], XSKIN), 0.0, NOSE["d"][1], 0.0, NOSE["z"], "")
# casing inner wall / front wall / top are added after the pod sweep is known (window cut-outs)

# ---- FIXED: crush-zone ramp behind the kid seats (keeps a >= 120 mm gap under the reclined seat backs)
_bot = recline_pt((SEAT_BACK["d"][1], CR_Z[1]))
_top = recline_pt((SEAT_BACK["d"][1], SEAT_BACK["top"]))
_u = np.array(_top) - np.array(_bot); _u /= np.linalg.norm(_u)
_n = np.array([_u[1], -_u[0]])            # away from the seat back (rearward / down)
RAMP_GAP = 120.0
_ra = np.array(_bot) + _n * (RAMP_GAP + 18)
_rb = np.array(_top) + _n * (RAMP_GAP + 18) - _u * 60
_r0 = _ra + _u * ((18.0 - _ra[1]) / _u[1])          # extend to the floor (z = 18)
RAMP = dict(p0=tuple(_r0), p1=tuple(_rb))
for i, xx in enumerate((-640.0, 640.0 - 18)):
    add_xpoly(f"Ramp cheek {'L' if i == 0 else 'R'}", "ply18", "fixed", xx, 18.0,
              [_r0, _rb, (_rb[0], 0.0), (_r0[0], 0.0)], "triangular ply cheek under the ramp, screwed to the base")
add_xpoly("Ramp cheek centre", "ply18", "fixed", -9.0, 18.0, [_r0, _rb, (_rb[0], 0.0), (_r0[0], 0.0)], "centre support")
add_seg("Crush-zone ramp", "ply18", "fixed", -640.0, 640.0, tuple(_r0 + _n * (-0.0)), tuple(_rb), h=18.0,
        note="18 mm ply sloping sheet, parallel to the reclined seat backs, 120 mm below them; foam on top")

# ---- FIXED: dad dais + seat + console
for nm, xx in (("Dais joist L", -DAIS["x"]), ("Dais joist C", -T2 / 2), ("Dais joist R", DAIS["x"] - T2)):
    add_box(nm, "2x4", "fixed", xx, xx + T2, DAIS["d"][0], DAIS["d"][1], W2, DAIS["z"] - 18 - 0, "2x4 on edge on the base crosses + 72 mm block-up", cut=True)
add_box("Dais deck", "ply18", "fixed", -DAIS["x"], DAIS["x"], DAIS["d"][0], DAIS["d"][1], DAIS["z"] - 18, DAIS["z"], "")
add_box("Dais front skin", "ply12", "fixed", -DAIS["x"], DAIS["x"], DAIS["d"][0] - 12, DAIS["d"][0], 0.0, DAIS["z"], "")
w = DAD_SEAT["w"]
add_box("Dad seat box", "ply18", "fixed", -w / 2, w / 2, DAD_SEAT["d"][0], DAD_SEAT["d"][1], DAIS["z"], DAD_SEAT["top"], "18 mm ply box, foam cushion")
add_box("Dad seat back", "ply18", "fixed", -w / 2, w / 2, DAD_SEAT["d"][1], DAD_SEAT["d"][1] + 18, DAIS["z"], DAD_SEAT["back_top"], "")
add_box("Commander console", "ply18", "fixed", *CMD["x"], *CMD["d"], DAIS["z"], CMD["top"], "CMD_A + CMD_B bay; motion switch + key + E-stop on CMD_B")
add_box("Pod release lever box", "ply12", "fixed", -w / 2 - 110, -w / 2 - 10, 2000.0, 2160.0, DAIS["z"], 760.0,
        "left of dad's seat: 2 Bowden-cable latch release levers (second hand for the pod motion)")

# ---- CRADLE (modelled upright)
for s, nm in SIDES:
    add_box(f"Cradle rail {nm}", "2x4", "cradle", *xr(s, *RAIL_X), *CR_D, *CR_Z, "on edge; UCP205 pillow block bolted under the rear end (pivot)")
add_box("Cradle cross, front", "2x4", "cradle", -RAIL_X[0], RAIL_X[0], CR_D[0], CR_D[0] + W2, CR_Z[1] - T2, CR_Z[1], "2x4 laid FLAT under the deck edge (actuators pass under it)")
for nm, d0 in (("Cradle cross, actuator", 421.0), ("Cradle cross, seats", SEAT_BOX["d"][0] - T2), ("Cradle cross, rear", CR_D[1] - 100)):
    add_box(nm, "2x4", "cradle", -RAIL_X[0], RAIL_X[0], d0, d0 + T2, *CR_Z, "on edge between the rails")
for nm, xx in (("Cradle joist L", -SEAT_X - T2 / 2), ("Cradle joist C", -T2 / 2), ("Cradle joist R", SEAT_X - T2 / 2)):
    add_box(nm, "2x4", "cradle", xx, xx + T2, CR_D[0] + W2, CR_D[1] - 100, *CR_Z, "between the crosses (pocket screws)")
add_box("Cradle deck", "ply18", "cradle", -RAIL_X[1], RAIL_X[1], CR_D[0], CR_D[1], CR_Z[1], FOOT_Z, "footrest + seat base, glued + screwed")
add_box("Cradle toe lip", "ply12", "cradle", -RAIL_X[1], RAIL_X[1], CR_D[0], CR_D[0] + 12, FOOT_Z, FOOT_Z + 70, "keeps feet on the cradle")
for s, nm in SIDES:
    add_box(f"Cradle skirt {nm}", "ply6", "cradle", *xr(s, RAIL_X[1], RAIL_X[1] + 6), CR_D[0] + 60, CR_D[1] - 40, 50.0, CR_Z[1],
            "inner half of the telescoping side pinch guard")
for nm, (pk, cx) in KID_SEATING.items():
    x0, x1 = cx - SEAT_W / 2, cx + SEAT_W / 2
    add_box(f"Kid seat box {nm}", "ply18", "cradle", x0, x1, *SEAT_BOX["d"], FOOT_Z, SEAT_BOX["top"], "18 mm ply box, foam cushion on top")
    add_box(f"Kid seat back {nm}", "ply18", "cradle", x0, x1, *SEAT_BACK["d"], FOOT_Z, SEAT_BACK["top"],
            "harness shoulder slots at 3 heights + headrest wings; the harness hub anchors to the cradle deck")
    for s in (-1, 1):
        add_box(f"Headrest wing {nm} {'in' if s * cx < 0 else 'out'}", "ply18", "cradle", *(sorted((cx + s * (SEAT_W / 2 - 18), cx + s * SEAT_W / 2))),
                SEAT_BACK["d"][0] - 130, SEAT_BACK["d"][0], 900.0, SEAT_BACK["top"], "side wings: head stays on the seat centre line")
add_box("Centre console (TD2220)", "ply18", "cradle", -CC["x"], CC["x"], *CC["d"], FOOT_Z, CC["z_rear"],
        "TD2220 drops into a 530 x 328 cut-out in the top, on a printed VESA riser + internal ply shelf; printed trim ring")
add_box("Front pedestal", "ply18", "cradle", -FP["x"], FP["x"], *FP["d"], FOOT_Z, FP["top"], "pilot joystick + OPS_SIDE panel")
for s, nm in SIDES:
    add_box(f"Side console {'PILOT' if s < 0 else 'OPS'}", "ply18", "cradle", *xr(s, *SIDE_C["x"]), *SIDE_C["d"], CR_Z[1], SIDE_C["top"],
            "PILOT_SIDE + throttle + gear" if s < 0 else "Ops joystick")
# cushions (render only)
for nm, (pk, cx) in KID_SEATING.items():
    add_box(f"Cushion {nm}", "foam", "cradle", cx - 160, cx + 160, SEAT_BOX["d"][0] + 10, SEAT_BOX["d"][1] - 30, SEAT_BOX["top"], SEAT_BOX["top"] + 60, cut=False)
    add_box(f"Back cushion {nm}", "foam", "cradle", cx - 150, cx + 150, SEAT_BACK["d"][0] - 30, SEAT_BACK["d"][0], SEAT_BOX["top"] + 60, SEAT_BACK["top"] - 20, cut=False)
add_box("Cushion dad", "foam", "fixed", -240, 240, DAD_SEAT["d"][0] + 10, DAD_SEAT["d"][1] - 30, DAD_SEAT["top"], DAD_SEAT["top"] + 70, cut=False)
add_box("Back cushion dad", "foam", "fixed", -230, 230, DAD_SEAT["d"][1] - 40, DAD_SEAT["d"][1], DAD_SEAT["top"] + 70, DAD_SEAT["back_top"] - 20, cut=False)

# ---- POD (modelled DOWN, alpha = ALPHA_DN)
POD_X = 806.0                  # inner face of the cheeks
CHEEK_X = (806.0, 842.0)       # 2 x 18 mm ply laminated
POD_T = (-407.0, 352.0)        # pod extent "up the screen"
R_BAND = (610.0, 628.0)        # panel bands (front face at r = 610)
R_BACK = (700.0, 712.0)        # back sheet (monitors hang on it)
add_pod_box("Pod back sheet", "ply12", -POD_X, POD_X, *R_BACK, -395.0, 340.0, "monitors' VESA adapters bolt through it")
add_pod_box("Pod lower band (dash)", "ply18", -POD_X, POD_X, *R_BAND, -395.0, -200.0, "2 dash bays 400 x 160 + M5 T-nuts on the 40 mm grid")
add_pod_box("Pod top band (overhead)", "ply18", -POD_X, POD_X, *R_BAND, 200.0, 340.0, "overhead bay 600 x 120")
add_pod_box("Pod chin plate", "ply12", -POD_X, POD_X, R_BAND[0], R_BACK[1], POD_T[0], -395.0, "leading edge; safety edge + 25 mm foam on its front")
add_pod_box("Pod top cap", "ply12", -POD_X, POD_X, R_BAND[0], R_BACK[1], 340.0, POD_T[1], "")
for i, (t0, t1) in enumerate(((-150.0, -61.0), (61.0, 150.0))):
    add_pod_box(f"Pod stiffener rail {i + 1}", "2x4", -POD_X, POD_X, R_BACK[1], R_BACK[1] + T2, t0, t1, "2x4 flat behind the back sheet")
# cheeks: (r, t) outline + crank lobe (filled in after the mechanism search)
CHEEK_RT = [(-95.0, -95.0), (95.0, -150.0), (R_BAND[0], POD_T[0]), (R_BACK[1] + T2, POD_T[0]), (R_BACK[1] + T2, POD_T[1]),
            (R_BAND[0], POD_T[1]), (95.0, 150.0), (-95.0, 95.0)]
for s, nm in SIDES:
    add_pod_box(f"Pod bumper {nm}", "foam", *xr(s, CHEEK_X[1], CHEEK_X[1] + 1), R_BAND[0], R_BACK[1], POD_T[0], POD_T[1], cut=False)

# ------------------------------------------------------------------ masses
KG_PER_DISPLAY = {"C275B-144R": 3.80, "C275W-1920RN": 3.40}


def part_volume(p):
    if p.kind == "box":
        return p.size[0] * p.size[1] * p.size[2]
    a = 0.0
    q = p.pts
    for i in range(len(q)):
        a += q[i][0] * q[(i + 1) % len(q)][1] - q[(i + 1) % len(q)][0] * q[i][1]
    return abs(a) / 2 * p.thick


def part_centroid_dz(p):
    if p.kind == "box":
        c = p.M @ np.array([p.size[0] / 2, p.size[1] / 2, p.size[2] / 2, 1])
        return (-c[1], c[2])
    q = np.array(p.pts)
    return tuple(q.mean(0))


def group_mass(group, extra=()):
    m, md, mz = 0.0, 0.0, 0.0
    for p in PARTS:
        if p.group == group and p.mat in RHO:
            mm = part_volume(p) * 1e-9 * RHO[p.mat]
            d, z = part_centroid_dz(p)
            m += mm; md += mm * d; mz += mm * z
    for _, mm, (d, z) in extra:
        m += mm; md += mm * d; mz += mm * z
    return m, (md / m, mz / m)


# ------------------------------------------------------------------ pod mechanism (struts + actuators)
POD_EXTRA = [("2 monitors (C275B-144R 3.80 + C275W-1920RN 3.40 kg)", 7.2, pod_pt(645, 0)),
             ("VESA adapters, rails, cables", 2.5, pod_pt(705, 0)),
             ("7 printed panels + switches + 2 ESP32 boxes", 4.5, pod_pt(640, -150)),
             ("cheek steel: bearings, crank plates, latch plates", 6.0, pod_pt(60, 0)),
             ("foam + safety edge + trim", 1.5, pod_pt(650, -300))]


def pod_moment(alpha, mass, cg_dz):
    """Gravity torque about the pod pivot (N*m), + = tends to raise the pod."""
    cg = rot_dz(alpha - ALPHA_DN, PP, *cg_dz)
    # torque_x = (y - yP) * Fz = -(d - dP) * (-m g) = m g (d - dP)
    return mass * G * (cg[0] - PP[0]) / 1000.0


def lever(pin_dz0, anchor_dz, alpha, pivot=PP, pose0=ALPHA_DN):
    """Return (length, moment arm in m) of a two-force member between a fixed anchor and
    a pin on the moving body (pin given at the pose0 pose).  arm sign: + if PUSHING raises."""
    pd, pz = rot_dz(alpha - pose0, pivot, *pin_dz0)
    ld, lz = pd - anchor_dz[0], pz - anchor_dz[1]
    Lm = math.hypot(ld, lz)
    # force on the pin when pushing: along (pin - anchor) / L, in (y, z) = (-ld, lz)/L
    fy, fz = -ld / Lm, lz / Lm
    ry, rz = -(pd - pivot[0]) / 1000, (pz - pivot[1]) / 1000
    return Lm, ry * fz - rz * fy


def part_points(p, step=20.0, surface=True):
    """sample points on the part surface (pose 0, world)."""
    if p.kind == "box":
        sx, sy, sz = p.size
        def lin(a):
            return np.linspace(0, a, max(2, int(math.ceil(a / step)) + 1))
        X, Y, Z = lin(sx), lin(sy), lin(sz)
        pts = []
        for a in (0, sx):
            yy, zz = np.meshgrid(Y, Z); pts.append(np.c_[np.full(yy.size, a), yy.ravel(), zz.ravel()])
        for b in (0, sy):
            xx, zz = np.meshgrid(X, Z); pts.append(np.c_[xx.ravel(), np.full(xx.size, b), zz.ravel()])
        for c in (0, sz):
            xx, yy = np.meshgrid(X, Y); pts.append(np.c_[xx.ravel(), yy.ravel(), np.full(xx.size, c)])
        q = np.vstack(pts)
        q = (p.M @ np.c_[q, np.ones(len(q))].T).T[:, :3]
        return q
    import shapely.geometry as sg
    poly = sg.Polygon(p.pts)
    b = poly.bounds
    xs = np.linspace(p.x0, p.x0 + p.thick, max(2, int(math.ceil(p.thick / step)) + 1))
    out = []
    # outline
    ring = poly.exterior
    n = max(8, int(ring.length / step))
    o = np.array([ring.interpolate(i / n, normalized=True).coords[0] for i in range(n)])
    for x in xs:
        out.append(np.c_[np.full(len(o), x), -o[:, 0], o[:, 1]])
    gd, gz = np.meshgrid(np.arange(b[0], b[2], step), np.arange(b[1], b[3], step))
    g = np.c_[gd.ravel(), gz.ravel()]
    from shapely import contains_xy
    g = g[contains_xy(poly, g[:, 0], g[:, 1])]
    for x in (p.x0, p.x0 + p.thick):
        out.append(np.c_[np.full(len(g), x), -g[:, 0], g[:, 1]])
    return np.vstack(out)


def xf(M, pts):
    return (M @ np.c_[pts, np.ones(len(pts))].T).T[:, :3]


_PT_CACHE = {}


def cached_points(p):
    if id(p) not in _PT_CACHE:
        _PT_CACHE[id(p)] = part_points(p)
    return _PT_CACHE[id(p)]


STRUT_PROG = (0.3, 0.5)          # F2/F1 - 1 of the gas spring (catalogue struts: 1.3 .. 1.5)


def search_pod():
    """Gas-strut counterbalance: one strut per side, pins on the cheeks, anchors in the
    casings.  Minimise the worst residual torque over the travel, with the pod still
    resting on the DOWN stop at the bottom and on the UP stop at the top (>= 8 N*m)."""
    mass, cg = group_mass("pod", [(n, m, p) for n, m, p in POD_EXTRA])
    alphas = np.linspace(ALPHA_DN, ALPHA_UP, 25)
    Mg = np.array([pod_moment(a, mass, cg) for a in alphas])           # negative (pod wants to fall down)
    best = None
    pins = [(r, t) for r in np.arange(-320, 321, 20) for t in np.arange(-320, 321, 20) if math.hypot(r, t) >= 100]
    A = np.array([(d, z) for d in np.arange(CASE["d"][0] + 60, CASE["d"][1] - 40, 20) for z in np.arange(110, CASE["top"] - 50, 20)])
    Fs = np.linspace(50, 1500, 146)
    for pk in STRUT_PROG:
        for (r, t) in pins:
            pin = pod_pt(r, t)
            P = np.array([rot_dz(a - ALPHA_DN, PP, *pin) for a in alphas])
            if P[:, 0].min() < CASE["d"][0] + 40 or P[:, 0].max() > CASE["d"][1] - 40 or P[:, 1].max() > CASE["top"] - 50 or P[:, 1].min() < 100:
                continue
            ld = P[None, :, 0] - A[:, None, 0]; lz = P[None, :, 1] - A[:, None, 1]
            Lm = np.hypot(ld, lz)
            fy, fz = -ld / Lm, lz / Lm
            ry, rz = -(P[:, 0] - PP[0]) / 1000, (P[:, 1] - PP[1]) / 1000
            arm = ry[None] * fz - rz[None] * fy
            Lmin, Lmax = Lm.min(1), Lm.max(1)
            st = Lmax - Lmin
            ok = (Lmin >= st + 90) & (Lmax <= 600) & (arm.min(1) > 0.01) & (st > 60)
            for i in np.nonzero(ok)[0]:
                tp = arm[i] * (1 + pk * (Lmax[i] - Lm[i]) / st[i])
                net = Mg[None, :] + 2 * Fs[:, None] * tp[None, :]
                res = np.abs(net).max(1)
                res[(net[:, 0] > -8) | (net[:, -1] < 8)] = 1e9
                k = res.argmin()
                if res[k] < 1e8 and (best is None or res[k] < best["residual"] - 0.5):
                    best = dict(residual=float(res[k]), F1=float(Fs[k]), F2=float(Fs[k] * (1 + pk)), prog=pk, pin_rt=(float(r), float(t)),
                                anchor=tuple(map(float, A[i])), Lmin=float(Lmin[i]), Lmax=float(Lmax[i]), stroke=float(st[i]))
    pin = pod_pt(*best["pin_rt"])
    net = []
    for a, mg in zip(alphas, Mg):
        Lm, arm = lever(pin, best["anchor"], a)
        net.append(mg + 2 * best["F1"] * (1 + best["prog"] * (best["Lmax"] - Lm) / best["stroke"]) * arm)
    return mass, cg, alphas, Mg, best, np.array(net)


STD_ACT = [(int(n), n * 25.4) for n in (4, 6, 8, 10, 12)]
ACT_DEAD = 110.0     # retracted pin-to-pin = stroke + ~110 mm for typical 12 V actuators (check the real one)


def search_actuator(pivot, pose0, pins, anchors, angles, net_torque, n_act, lim, max_len=800.0, obstacles=None, radius=30.0):
    """Pick pin + anchor so the travel fits INSIDE a standard actuator stroke (10 mm spare
    at each end for the external limit switches); minimise the peak force.  obstacles(angle)
    returns world (d, z) points of everything in the actuator's x-band at that pose; the
    actuator body (capsule, radius) must stay clear of them."""
    cands = []
    A = np.array(anchors)
    for pin in pins:
        P = np.array([rot_dz(a - pose0, pivot, *pin) for a in angles])
        if not lim(P):
            continue
        ld = P[None, :, 0] - A[:, None, 0]; lz = P[None, :, 1] - A[:, None, 1]
        Lm = np.hypot(ld, lz)
        mono = np.all(np.diff(Lm, axis=1) > 0, axis=1) | np.all(np.diff(Lm, axis=1) < 0, axis=1)
        Lmin, Lmax = Lm.min(1), Lm.max(1)
        fy, fz = -ld / Lm, lz / Lm
        ry, rz = -(P[:, 0] - pivot[0]) / 1000, (P[:, 1] - pivot[1]) / 1000
        arm = ry[None] * fz - rz[None] * fy
        for inch_, S in STD_ACT:
            Lr = S + ACT_DEAD
            ok = mono & (Lmin >= Lr + 10) & (Lmax <= Lr + S - 10) & (np.abs(arm).min(1) > 0.03) & (Lmax <= max_len)
            for i in np.nonzero(ok)[0]:
                F = np.abs(net_torque / arm[i]) / n_act
                score = F.max() * (1 + 0.15 * (inch_ / 4))
                cands.append((float(score), dict(score=float(score), pin=tuple(map(float, P[0])), anchor=tuple(map(float, A[i])), Lmin=float(Lmin[i]),
                              Lmax=float(Lmax[i]), travel=float(Lmax[i] - Lmin[i]), act_stroke_in=inch_, act_retracted_mm=float(Lr),
                              F_each_max=float(F.max()), F_each=[float(v) for v in F], arm_m=[float(v) for v in arm[i]],
                              extends_to_raise=bool(Lm[i, -1] > Lm[i, 0])), P))
    cands.sort(key=lambda c: c[0])
    if obstacles is None:
        return cands[0][1] if cands else None
    obs = {float(a): obstacles(a) for a in angles[::3]}
    for score, c, P in cands[:4000]:
        good = True
        an = np.array(c["anchor"])
        for k, a in enumerate(angles[::3]):
            Q = obs[float(a)]
            p = P[3 * k]
            # ignore obstacle points within 45 mm of the two pins (brackets)
            m = (np.hypot(*(Q - p).T) > 45) & (np.hypot(*(Q - an).T) > 45)
            ab = p - an; L2 = ab @ ab
            t = np.clip((Q[m] - an) @ ab / L2, 0, 1)
            dd = np.hypot(*(Q[m] - (an + t[:, None] * ab)).T)
            if dd.size and dd.min() < radius:
                good = False
                break
        if good:
            c["clearance_checked"] = True
            return c
    return None


def band_points(groups_poses, x, half):
    """(d, z) points of all parts whose x-range overlaps [x-half, x+half], for given group poses."""
    out = []
    for p in PARTS:
        if p.group not in groups_poses or p.mat not in RHO or "slot" in p.note:
            continue
        q = cached_points(p)
        q = q[np.abs(q[:, 0] - x) <= half]
        if len(q):
            out.append(xf(groups_poses[p.group], q))
    q = np.vstack(out)
    return np.c_[-q[:, 1], q[:, 2]]


POD_ACT_X = (CI + 50 + CHEEK_X[0]) / 2
STRUT_X = CHEEK_X[1] + 28.0
CR_ACT_X = 560.0
POD_MASS, POD_CG, ALPHAS, MG, STRUT, NET = search_pod()
STRUT["pin"] = pod_pt(*STRUT["pin_rt"])

# pod actuator: inboard of the cheek, pins on the cheek, anchors in the casing
_pins = [pod_pt(r, t) for r in np.arange(-260, 161, 20) for t in np.arange(-260, 261, 20) if math.hypot(r, t) >= 110]
_anc = [(d, z) for d in np.arange(CASE["d"][0] + 60, CASE["d"][1] - 40, 20) for z in np.arange(110, CASE["top"] - 50, 20)]
# design torque: |net| + 25 N*m (friction, strut tolerance), 2 actuators
_net_design = np.abs(NET) + 25.0
POD_ACT = search_actuator(PP, ALPHA_DN, _pins, _anc, ALPHAS, _net_design, 2,
                          lambda P: P[:, 0].min() > CASE["d"][0] + 50 and P[:, 0].max() < CASE["d"][1] - 50 and P[:, 1].max() < CASE["top"] - 50 and P[:, 1].min() > 110,
                          obstacles=lambda a: band_points({"fixed": np.eye(4), "pod": R4(a - ALPHA_DN, PP)}, POD_ACT_X, 30.0), radius=28.0)
# worst case: both gas struts gone -> actuators must hold the full gravity torque
POD_ACT["F_each_strut_failed"] = float(np.max(np.abs(MG / np.array(POD_ACT["arm_m"]))) / 2)

# ------------------------------------------------------------------ cradle mechanism
def cradle_masses():
    m, (d, z) = group_mass("cradle")
    items = [("cradle wood (model)", m, (d, z)), ("TD2220 + trim + wedge", 5.0, (750.0, 590.0)),
             ("controls, ESP32s, cables on the cradle", 4.0, (600.0, 520.0)), ("harnesses + hubs + cushions", 4.0, (860.0, 700.0))]
    # design occupants: 2 x 50 kg (both seats, growth margin), CG ~ 200 above the hip
    for nm, (pk, cx) in KID_SEATING.items():
        h = KIDS["12yr"]["hip"]
        items.append((f"occupant {nm} (design 50 kg)", 50.0, (h[0] - 20, h[1] + 200)))
    return items


CR_ITEMS = cradle_masses()
CR_MASS = sum(m for _, m, _ in CR_ITEMS)
CR_THETAS = np.linspace(0, RECLINE, 15)


def cradle_torque(th, items=None):
    t = 0.0
    for _, m, p in (items or CR_ITEMS):
        d, z = recline_pt(p, th)
        t += m * G * (d - CP[0]) / 1000.0
    return t     # + = tends to recline further (rear goes down)


CR_TORQUE = np.array([cradle_torque(t) for t in CR_THETAS])
CR_TORQUE_EMPTY = np.array([cradle_torque(t, [i for i in CR_ITEMS if not i[0].startswith("occupant")]) for t in CR_THETAS])
_cpins = [(d, z) for d in np.arange(300.0, 600.0, 10.0) for z in np.arange(100.0, 271.0, 10.0)]
_canc = [(d, z) for d in np.arange(20, 260, 10) for z in (30.0, 45.0, 60.0, 80.0, 100.0)]
CR_ACT = search_actuator(CP, 0.0, _cpins, _canc, CR_THETAS, np.maximum(np.abs(CR_TORQUE), np.abs(CR_TORQUE_EMPTY)) + 40.0, 2, lambda P: True,
                        obstacles=lambda a: band_points({"fixed": np.eye(4), "cradle": R4(a, CP)}, CR_ACT_X, 30.0), radius=28.0)

# ------------------------------------------------------------------ cheek outline + casing walls (need the mechanism)
def cheek_outline():
    pts = [pod_pt(r, t) for r, t in CHEEK_RT]
    extra = [STRUT["pin"], POD_ACT["pin"]]
    import shapely.geometry as sg
    poly = sg.Polygon(pts)
    lobes = sg.MultiPoint(list(extra) + [PP]).convex_hull.buffer(45, 16)
    poly = poly.union(lobes).union(sg.Point(PP).buffer(110, 32))
    poly = poly.simplify(0.5)
    return [tuple(p) for p in list(poly.exterior.coords)[:-1]]


CHEEK = cheek_outline()
for s, nm in SIDES:
    add_xpoly(f"Pod cheek {nm}", "ply18", "pod", xr(s, *CHEEK_X)[0], CHEEK_X[1] - CHEEK_X[0], CHEEK,
              "2 x 18 mm ply laminated (glue + screws); UCF205 flange bearing at the pivot, crank pins for strut + actuator")


def swept_cheek(alphas=None):
    import shapely.geometry as sg
    from shapely.ops import unary_union
    alphas = np.linspace(ALPHA_DN, ALPHA_UP, 31) if alphas is None else alphas
    polys = [sg.Polygon([rot_dz(a - ALPHA_DN, PP, *p) for p in CHEEK]) for a in alphas]
    return unary_union(polys)


SWEEP = swept_cheek()
import shapely.geometry as _sg
# casing front wall top: below the swept cheek at the front wall plane minus 40 mm
_line = _sg.LineString([(CASE["d"][0], 0), (CASE["d"][0], 3000)])
_front_hit = SWEEP.intersection(_sg.box(CASE["d"][0] - 1, 0, CASE["d"][0] + 13, 3000))
FRONT_TOP = min(980.0, _front_hit.bounds[1] - 40) if not _front_hit.is_empty else 980.0
_top_hit = SWEEP.intersection(_sg.box(0, CASE["top"] - 12, 4000, CASE["top"]))
TOP_FROM = (_top_hit.bounds[2] + 40) if not _top_hit.is_empty else CASE["d"][0]
SLOT_X = (CHEEK_X[0] - 6.0, CHEEK_X[1] + 6.0)     # cheek slot through the casing top / front wall (brush-sealed)
for s, nm in SIDES:
    add_box(f"Casing inner wall {nm}", "ply12", "fixed", *xr(s, CI, CI + 12), CASE["d"][0], CASE["d"][1], 0.0, CASE["top"],
            "12 mm ply between kid and mechanism (full height)")
    add_box(f"Casing front wall {nm} (inner)", "ply12", "fixed", *xr(s, CI, SLOT_X[0]), CASE["d"][0] - 12, CASE["d"][0], 0.0, CASE["top"],
            "slot for the cheek next to it, brush strip on both slot edges")
    add_box(f"Casing front wall {nm} (outer)", "ply12", "fixed", *xr(s, SLOT_X[1], XS[1]), CASE["d"][0] - 12, CASE["d"][0], 0.0, CASE["top"], "")
    add_box(f"Casing front wall {nm} (below slot)", "ply12", "fixed", *xr(s, *SLOT_X), CASE["d"][0] - 12, CASE["d"][0], 0.0, FRONT_TOP,
            "slot bottom = lowest cheek edge - 40 mm")
    add_box(f"Casing top {nm} (inner)", "ply12", "fixed", *xr(s, CI, SLOT_X[0]), CASE["d"][0] - 12, CASE["d"][1], CASE["top"] - 12, CASE["top"],
            "lift-off service lid")
    add_box(f"Casing top {nm} (outer)", "ply12", "fixed", *xr(s, SLOT_X[1], XS[1]), CASE["d"][0] - 12, CASE["d"][1], CASE["top"] - 12, CASE["top"], "")
    add_box(f"Casing top {nm} (behind slot)", "ply12", "fixed", *xr(s, *SLOT_X), TOP_FROM, CASE["d"][1], CASE["top"] - 12, CASE["top"], "")
    # anchor supports
    sd = STRUT["anchor"][0]
    add_box(f"Strut anchor post {nm}", "2x4", "fixed", *xr(s, XS[0] - T2, XS[0]), sd - 44.5, sd + 44.5, W2, CASE["top"] - 12,
            "gas-strut lower ball stud on a steel angle bracket")
    ad = POD_ACT["anchor"][0]
    if abs(ad - PP[0]) > 60:
        add_box(f"Pod actuator anchor post {nm}", "2x4", "fixed", *xr(s, CI + 12, CI + 50), ad - 44.5, ad + 44.5, W2, CASE["top"] - 12,
                "pod actuator rear clevis bracket")
WINDOW = dict(front_wall_slot_bottom=FRONT_TOP, top_slot_to_d=TOP_FROM, slot_x=SLOT_X)

# ------------------------------------------------------------------ placements
def pod_frame(x0, t0, r_face):
    """panel-local -> world in the DOWN pose: X = +x, Y = up the screen (t), Z = toward the kids (-e)."""
    e, t = e_dir(ALPHA_DN), t_dir(ALPHA_DN)
    ew = np.array([0, -e[0], e[1]]); tw = np.array([0, -t[0], t[1]])
    o = np.array([x0, -PP[0], PP[1]]) + r_face * ew + t0 * tw
    return mat_cols([1, 0, 0], tw, -ew, o)


def flat_M(x0, d_bottom, z, tilt=0.0):
    """Panel lying on a top surface, text 'up' = forward; tilt (deg) raises the front edge."""
    c, s = math.cos(DEG(tilt)), math.sin(DEG(tilt))
    return mat_cols([1, 0, 0], [0, c, s], [0, -s, c], [x0, -d_bottom, z + 3.0])


DASH_T0 = -375.0
DASH_CX = [-SEAT_X, SEAT_X]
PLACE = {
    "PILOT_DASH_A": ("pod", pod_frame(-SEAT_X - 200, DASH_T0, R_BAND[0] - 3)),
    "PILOT_DASH_B": ("pod", pod_frame(-SEAT_X, DASH_T0, R_BAND[0] - 3)),
    "OPS_DASH_A": ("pod", pod_frame(SEAT_X - 200, DASH_T0, R_BAND[0] - 3)),
    "OPS_DASH_B": ("pod", pod_frame(SEAT_X, DASH_T0, R_BAND[0] - 3)),
    "OVERHEAD_A": ("pod", pod_frame(-300, 210.0, R_BAND[0] - 3)),
    "OVERHEAD_B": ("pod", pod_frame(-100, 210.0, R_BAND[0] - 3)),
    "OVERHEAD_C": ("pod", pod_frame(100, 210.0, R_BAND[0] - 3)),
    "PILOT_SIDE": ("cradle", flat_M(SIDE_C["x"][0] * -1 - 200 + 0, SIDE_C["d"][1] - 10, SIDE_C["top"] + 0.5)),
    "OPS_SIDE": ("cradle", flat_M(30.0, FP["d"][1] - 10, FP["top"] + 0.5)),
    "CMD_A": ("fixed", flat_M(CMD["x"][0] + 20, CMD["d"][0] + 200, CMD["top"] + 0.5)),
    "CMD_B": ("fixed", flat_M(CMD["x"][0] + 20, CMD["d"][0] + 395, CMD["top"] + 0.5)),
}
PLACE["PILOT_SIDE"] = ("cradle", flat_M(-SIDE_C["x"][1], SIDE_C["d"][1] - 10, SIDE_C["top"] + 0.5))
TD_TILT = 0.0
PART_PLACE = {
    "throttle": ("cradle", flat_M(-SIDE_C["x"][1] + 45, SIDE_C["d"][1] - 10 - 170, SIDE_C["top"] + 0.5)),
    "gear": ("cradle", flat_M(-SIDE_C["x"][1] + 150, SIDE_C["d"][1] - 10 - 170, SIDE_C["top"] + 0.5)),
    "joystick_pilot": ("cradle", flat_M(-170.0, FP["d"][0] + 100, FP["top"])),
    "joystick_ops": ("cradle", flat_M(SIDE_C["x"][0] + 100, 680.0, SIDE_C["top"])),
    # TD2220 trim: origin = centre of the active area on the glass, wedge tilted 10 deg (front up)
    "bezel": ("cradle", flat_M(0.0, (CC["d"][0] + CC["d"][1]) / 2, CC["z_rear"] - 3.0, TD_TILT)),
    # monitors: origin = screen centre on the face, Y up the screen, Z toward the viewer
    "monitor_L": ("pod", pod_frame(-SEAT_X, 0.0, R_SCREEN)),
    "monitor_R": ("pod", pod_frame(SEAT_X, 0.0, R_SCREEN)),
}

# ------------------------------------------------------------------ poses + sampled geometry
def group_pose(group, th, al):
    if group == "cradle":
        return R4(th, CP)
    if group == "pod":
        return R4(al - ALPHA_DN, PP)
    return np.eye(4)


def manikin_segments(m, x_c, frame="cradle"):
    """capsules (p0, p1, r) in pose-0 world coordinates (3D)."""
    r = m["r"]
    def P(name, dx=0.0):
        d, z = m[name]
        return np.array([x_c + dx, -d, z])
    segs = [(P("head"), P("head"), m["head_r"]), (P("neck"), P("head"), r["neck"]),
            (P("shoulder"), P("hip"), r["torso"])]
    for s in (-1, 1):
        lx = s * (r["thigh"] + 10)
        segs += [(P("hip", lx), P("knee", lx), r["thigh"]), (P("knee", lx), P("ankle", lx), r["shin"]), (P("ankle", lx), P("toe", lx), r["foot"])]
        ax = s * m["sh_half"]
        segs += [(P("shoulder", ax), P("elbow", ax), r["arm"]), (P("elbow", ax), P("hand", s * (m["sh_half"] - 40)), r["arm"] - 5)]
    return segs


def seg_dist(pts, a, b, r):
    ab = b - a
    L2 = float(ab @ ab)
    if L2 < 1e-9:
        return np.linalg.norm(pts - a, axis=1) - r
    t = np.clip((pts - a) @ ab / L2, 0, 1)
    return np.linalg.norm(pts - (a + t[:, None] * ab), axis=1) - r


def clearance_report():
    from scipy.spatial import cKDTree
    out = {}
    kids = [(nm, KIDS[k], x) for nm, (k, x) in KID_SEATING.items()]
    pod_parts = [p for p in PARTS if p.group == "pod"]
    pod_pts = np.vstack([cached_points(p) for p in pod_parts])
    pod_lab = np.concatenate([[i] * len(cached_points(p)) for i, p in enumerate(pod_parts)])
    cr_parts = [p for p in PARTS if p.group == "cradle"]
    cr_pts = np.vstack([cached_points(p) for p in cr_parts])
    cr_lab = np.concatenate([[i] * len(cached_points(p)) for i, p in enumerate(cr_parts)])
    fx_parts = [p for p in PARTS if p.group == "fixed"]
    fx_pts = np.vstack([cached_points(p) for p in fx_parts])
    fx_lab = np.concatenate([[i] * len(cached_points(p)) for i, p in enumerate(fx_parts)])
    fx_tree = cKDTree(fx_pts)
    # 1) pod (all alpha) vs reclined kids (each body segment)
    rows = []
    for nm, m, x in kids:
        segs = manikin_segments(m, x)
        Mc = R4(RECLINE, CP)
        for a in np.linspace(ALPHA_DN, ALPHA_UP, 25):
            Q = xf(R4(a - ALPHA_DN, PP), pod_pts)
            for (s0, s1, r), segname in zip(segs, ["head", "neck", "torso"] + [f"{lim}" for _ in (0, 1) for lim in ("thigh", "shin", "foot", "upper arm", "forearm")]):
                a0, a1 = xf(Mc, s0[None])[0], xf(Mc, s1[None])[0]
                dd = seg_dist(Q, a0, a1, r)
                i = int(dd.argmin())
                rows.append((float(dd[i]), nm, segname, float(a), pod_parts[pod_lab[i]].name))
    rows.sort()
    best = {}
    for g, nm, seg, a, part in rows:
        k = (nm, seg)
        if k not in best:
            best[k] = dict(kid=nm, body=seg, gap_mm=round(g), pod_alpha=round(a, 1), pod_part=part)
    out["pod_vs_reclined_kids"] = sorted(best.values(), key=lambda r: r["gap_mm"])
    # at the down stop (alpha = ALPHA_DN) only
    rows = []
    for nm, m, x in kids:
        segs = manikin_segments(m, x)
        Mc = R4(RECLINE, CP)
        Q = pod_pts
        for (s0, s1, r), segname in zip(segs, ["head", "neck", "torso"] + [f"{lim}" for _ in (0, 1) for lim in ("thigh", "shin", "foot", "upper arm", "forearm")]):
            a0, a1 = xf(Mc, s0[None])[0], xf(Mc, s1[None])[0]
            dd = seg_dist(Q, a0, a1, r)
            i = int(dd.argmin())
            rows.append(dict(kid=nm, body=segname, gap_mm=round(float(dd[i])), pod_part=pod_parts[pod_lab[i]].name))
    out["pod_down_vs_kids"] = sorted(rows, key=lambda r: r["gap_mm"])[:8]
    # eye -> screen distance
    eyes = {}
    for nm, m, x in kids:
        hd = recline_pt(m["head"]); eye = np.array(hd) + 0.6 * m["head_r"] * e_dir(ALPHA_DN)
        scr = np.array(pod_pt(R_SCREEN, 0))
        eyes[nm] = dict(eye_dz=[round(v) for v in eye], eye_to_screen_mm=round(float(np.linalg.norm(scr - eye))),
                        gaze_elev_deg=round(math.degrees(math.atan2(scr[1] - eye[1], eye[0] - scr[0])), 1))
    out["eyes"] = eyes
    # 2) pod sweep vs fixed + cradle(reclined)
    rows = []
    cr_rec = xf(R4(RECLINE, CP), cr_pts)
    cr_tree = cKDTree(cr_rec)
    skip_fixed = ("Tower post", "Casing", "Side skin (casing)")      # the pod shares the casing (pivot + window, checked separately)
    for a in np.linspace(ALPHA_DN, ALPHA_UP, 25):
        Q = xf(R4(a - ALPHA_DN, PP), pod_pts)
        d, i = fx_tree.query(Q)
        for k in np.argsort(d)[:400]:
            fp = fx_parts[fx_lab[i[k]]]
            pp = pod_parts[pod_lab[k]]
            if pp.name.startswith("Pod cheek") and any(fp.name.startswith(s) for s in skip_fixed):
                continue
            rows.append((float(d[k]), pp.name, fp.name, float(a)))
            break
        d2, i2 = cr_tree.query(Q)
        k = int(d2.argmin())
        rows.append((float(d2[k]), pod_parts[pod_lab[k]].name, "(cradle reclined) " + cr_parts[cr_lab[i2[k]]].name, float(a)))
    rows.sort()
    seen = set(); res = []
    for g, a, b, al in rows:
        if (a, b) in seen:
            continue
        seen.add((a, b)); res.append(dict(gap_mm=round(g), moving=a, other=b, pod_alpha=round(al, 1)))
    out["pod_vs_structure"] = res[:10]
    # cheek vs casing walls: the cheek must stay inside the casing slot (between inner wall and tower post)
    out["cheek_x_clearance_mm"] = dict(inner_wall=CHEEK_X[0] - CI - 50, tower_post=XS[0] - T2 - CHEEK_X[1])
    # 3) cradle sweep (pod UP) vs fixed + pod-up + dad
    rows = []
    pod_up = xf(R4(ALPHA_UP - ALPHA_DN, PP), pod_pts)
    pod_tree = cKDTree(pod_up)
    skip_c = ("Cradle rest pad", "Recline stop block", "Cradle pivot pedestal", "Base cross, recline stops", "Base cross, cradle")
    dad_segs = manikin_segments(DAD, 0.0)
    for th in np.linspace(0, RECLINE, 15):
        Q = xf(R4(th, CP), cr_pts)
        d, i = fx_tree.query(Q)
        order = np.argsort(d)
        for k in order[:2000]:
            fp = fx_parts[fx_lab[i[k]]]
            if any(fp.name.startswith(s) for s in skip_c):
                continue
            rows.append((float(d[k]), cr_parts[cr_lab[k]].name, fp.name, float(th)))
            break
        d2, i2 = pod_tree.query(Q)
        k = int(d2.argmin())
        rows.append((float(d2[k]), cr_parts[cr_lab[k]].name, "(pod UP) " + pod_parts[pod_lab[i2[k]]].name, float(th)))
        for (s0, s1, r), segname in zip(dad_segs, ["head", "neck", "torso"] + [f"{lim}" for _ in (0, 1) for lim in ("thigh", "shin", "foot", "upper arm", "forearm")]):
            dd = seg_dist(Q, s0, s1, r)
            k = int(dd.argmin())
            rows.append((float(dd[k]), cr_parts[cr_lab[k]].name, f"dad {segname}", float(th)))
        # kids' heads vs fixed (casing walls etc.)
        for nm, m, x in kids:
            for (s0, s1, r), segname in zip(manikin_segments(m, x), ["head", "neck", "torso"] + [f"{lim}" for _ in (0, 1) for lim in ("thigh", "shin", "foot", "upper arm", "forearm")]):
                a0, a1 = xf(R4(th, CP), s0[None])[0], xf(R4(th, CP), s1[None])[0]
                dd = seg_dist(fx_pts, a0, a1, r)
                k = int(dd.argmin())
                rows.append((float(dd[k]), f"{nm} kid {segname}", fx_parts[fx_lab[k]].name, float(th)))
                dd = seg_dist(pod_up, a0, a1, r)
                k = int(dd.argmin())
                rows.append((float(dd[k]), f"{nm} kid {segname}", "(pod UP) " + pod_parts[pod_lab[k]].name, float(th)))
    rows.sort()
    seen = set(); res = []
    for g, a, b, th in rows:
        if (a, b) in seen:
            continue
        seen.add((a, b)); res.append(dict(gap_mm=round(g), moving=a, other=b, recline_deg=round(th, 1)))
    out["cradle_vs_structure"] = res[:14]
    # 4) boarding headroom: lowest point of the pod (UP) over the cradle footprint
    lowest = pod_up[(pod_up[:, 1] > -1150) & (np.abs(pod_up[:, 0]) < 640)]
    out["pod_up_lowest_z_over_seats"] = round(float(lowest[:, 2].min()))
    out["pod_up_lowest_point_d"] = round(float(-lowest[lowest[:, 2].argmin(), 1]))
    allp = np.vstack([xf(R4(a - ALPHA_DN, PP), pod_pts) for a in np.linspace(ALPHA_DN, ALPHA_UP, 13)])
    out["overall_height_swept"] = round(float(allp[:, 2].max()))
    out["pod_rear_most_d"] = round(float(-allp[:, 1].min()))
    return out


# ------------------------------------------------------------------ SCAD output
COLORS = {"2x4": "#c8a165", "ply18": "#d9b98a", "ply12": "#e3c79c", "ply6": "#b89a6e", "foam": "#7a1f1f"}


def mat_str(M):
    return "[" + ",".join("[" + ",".join(f"{v:.4f}" for v in row) + "]" for row in M) + "]"


def scad_part(p):
    if p.kind == "box":
        return f"multmatrix({mat_str(p.M)}) cube([{p.size[0]:.1f},{p.size[1]:.1f},{p.size[2]:.1f}]);"
    pts = ",".join(f"[{-d:.1f},{z:.1f}]" for d, z in p.pts)
    return f"translate([{p.x0:.1f},0,0]) rotate([90,0,90]) linear_extrude({p.thick}) polygon([{pts}]);"


def v3(d, z, x=0.0):
    return f"[{x:.1f},{-d:.1f},{z:.1f}]"


def write_scad(clr):
    os.makedirs(GEN, exist_ok=True)
    S = ["// GENERATED by frame/frame_model.py - do not edit by hand.",
         f"FF_RECLINE = {RECLINE};", f"FF_ALPHA_DN = {ALPHA_DN};", f"FF_ALPHA_UP = {ALPHA_UP};",
         f"FF_CP = {v3(*CP)};", f"FF_PP = {v3(*PP)};", ""]
    for grp in ("fixed", "cradle", "pod"):
        S.append(f"module ff_frame_{grp}(ghost = false) {{")
        for p in PARTS:
            if p.group == grp:
                S.append(f"  color(\"{p.color or COLORS[p.mat]}\", ghost ? 0.25 : 1) {scad_part(p)}  // {p.name}")
        S.append("}")
    S.append("module ff_cradle_pose(th) { translate(FF_CP) rotate([th, 0, 0]) translate(-FF_CP) children(); }")
    S.append("module ff_pod_pose(al) { translate(FF_PP) rotate([al - FF_ALPHA_DN, 0, 0]) translate(-FF_PP) children(); }")
    S.append("function ff_rot(p, c, a) = [p[0], c[1] + (p[1]-c[1])*cos(a) - (p[2]-c[2])*sin(a), c[2] + (p[1]-c[1])*sin(a) + (p[2]-c[2])*cos(a)];")
    # actuators / struts between fixed anchors and moving pins
    S.append("module ff_ram(a, b, d_body, d_rod, body_len, col = \"#9aa0a6\") {\n"
             "  v = b - a; L = norm(v);\n"
             "  color(col) hull() { translate(a) sphere(d = d_body); translate(a + v * min(body_len, L - 20) / L) sphere(d = d_body); }\n"
             "  color(\"#d0d0d0\") hull() { translate(a + v * min(body_len, L - 20) / L) sphere(d = d_rod); translate(b) sphere(d = d_rod); }\n}")
    S.append("module ff_mechanisms(th, al) {")
    for s in (-1, 1):
        x = s * CR_ACT_X
        S.append(f"  ff_ram({v3(*CR_ACT['anchor'], x)}, ff_rot({v3(*CR_ACT['pin'], x)}, FF_CP, th), 55, 22, {CR_ACT['Lmin'] - 40:.0f}, \"#3b5b8a\");")
        xa = s * POD_ACT_X
        S.append(f"  ff_ram({v3(*POD_ACT['anchor'], xa)}, ff_rot({v3(*POD_ACT['pin'], xa)}, FF_PP, al - FF_ALPHA_DN), 55, 22, {POD_ACT['Lmin'] - 40:.0f}, \"#3b5b8a\");")
        xs = s * STRUT_X
        S.append(f"  ff_ram({v3(*STRUT['anchor'], xs)}, ff_rot({v3(*STRUT['pin'], xs)}, FF_PP, al - FF_ALPHA_DN), 28, 12, {STRUT['Lmin'] - 30:.0f}, \"#222\");")
        # shafts
    S.append(f"  color(\"#999\") translate({v3(*CP, -906)}) rotate([0,90,0]) cylinder(d = 25, h = 1812);")
    S.append(f"  for (s = [-1, 1]) color(\"#999\") translate({v3(*PP, 0)} + [s > 0 ? 650 : -950, 0, 0]) rotate([0,90,0]) cylinder(d = 25, h = 300);")
    S.append("}")
    # manikins
    def man(name, m, x):
        segs = manikin_segments(m, x)
        S.append(f"module {name}() {{")
        for a, b, r in segs:
            S.append(f"  hull() {{ translate([{a[0]:.1f},{a[1]:.1f},{a[2]:.1f}]) sphere(r = {r:.0f}); translate([{b[0]:.1f},{b[1]:.1f},{b[2]:.1f}]) sphere(r = {r:.0f}); }}")
        S.append("}")
    for nm, (k, x) in KID_SEATING.items():
        man(f"ff_kid_{nm}", KIDS[k], x)
    man("ff_dad", DAD, 0.0)
    for k, (grp, M) in list(PLACE.items()) + list(PART_PLACE.items()):
        S.append(f"module at_{k}() multmatrix({mat_str(M)}) children();")
    S.append("PLACE_GROUP = [" + ", ".join(f'["{k}", "{g}"]' for k, (g, _) in list(PLACE.items()) + list(PART_PLACE.items())) + "];")
    with open(os.path.join(GEN, "frame.scad"), "w") as f:
        f.write("\n".join(S) + "\n")


# ------------------------------------------------------------------ cut list
def inch(mm):
    v = mm / 25.4
    return f'{v:.1f}"' if v < 24 else f"{int(v // 12)}' {v - 12 * int(v // 12):.1f}\""


def part_dims(p):
    if p.kind == "box":
        return sorted(p.size, reverse=True)
    q = np.array(p.pts)
    ext = q.max(0) - q.min(0)
    if p.name == "Crush-zone ramp":
        ln = float(np.linalg.norm(q[1] - q[0]))
        return [ln, 1280.0, 18.0]
    return sorted([ext[0], ext[1], p.thick], reverse=True)


MATNAME = {"ply18": "18 mm ply", "ply12": "12 mm ply", "ply6": "6 mm ply/hardboard"}


def cut_rows():
    rows = []
    for p in PARTS:
        if not p.cut or p.mat not in RHO:
            continue
        dims = part_dims(p)
        if p.mat == "2x4":
            rows.append((p.group, p.name, "2x4 (38 x 89)", round(dims[0]), None, p.note))
        elif ("box" in p.name.lower() or "console" in p.name.lower() or "pedestal" in p.name.lower()) and p.kind == "box" and p.mat == "ply18":
            sx, sy, sz = (round(v) for v in p.size)
            rows.append((p.group, p.name, "18 mm ply box", sx, sy,
                         f"outer {sx} x {sy} x {sz} (W x D x H): top {sx}x{sy}, 2 sides {sy}x{sz - 18}, front+back {sx - 36}x{sz - 18}. " + p.note))
        else:
            shape = " (profile: see drawing 04)" if p.kind == "xpoly" and "cheek" in p.name.lower() else ""
            rows.append((p.group, p.name, MATNAME[p.mat], round(dims[0]), round(dims[1]), p.note + shape))
    return rows


def lumber_buy(rows, stock=2438.0, kerf=4.0):
    lens = sorted([r[3] for r in rows if r[2].startswith("2x4")], reverse=True)
    boards = []
    for ln in lens:
        st = 3048.0 if ln > stock else stock
        for b in boards:
            if b[0] == st and sum(b[1]) + len(b[1]) * kerf + ln <= st:
                b[1].append(ln)
                break
        else:
            boards.append((st, [ln]))
    return boards


def write_lists():
    rows = cut_rows()
    with open(os.path.join(HERE, "cut_list.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", "part", "material", "length_mm", "width_mm", "length_in", "width_in", "notes"])
        for g, n, m, a, b, note in rows:
            w.writerow([g, n, m, a, b if b else "", inch(a), inch(b) if b else "", note])
    boards = lumber_buy(rows)
    n8 = sum(1 for st, _ in boards if st < 3000); n10 = len(boards) - n8
    md = ["# Cut list (generated by `frame/frame_model.py`)", "",
          "All sizes in mm with inches in brackets. 2x4 = 38 x 89 mm actual (1.5\" x 3.5\").",
          "Groups: **fixed** = base, nose box, towers/casings, ramp, dad dais; **cradle** = the reclining kid-seat frame; "
          "**pod** = the rotating instrument pod. Check every length against your real lumber before cutting.", "",
          "| # | Group | Part | Material | Length | Width | Notes |", "|---|---|---|---|---|---|---|"]
    for i, (g, n, m, a, b, note) in enumerate(rows, 1):
        md.append(f"| {i} | {g} | {n} | {m} | {a} ({inch(a)}) | {'' if not b else f'{b} ({inch(b)})'} | {note} |")
    n2x4 = len([r for r in rows if r[2].startswith('2x4')])
    md += ["", f"**2x4 boards:** {n2x4} pieces from **{n8} x 8 ft (2438 mm)**" + (f" + **{n10} x 10 ft (3048 mm)**" if n10 else "") +
           " boards (first-fit packing, 4 mm kerf; buy 3 spares). The 2450 mm sills need 10 ft boards (or 2 x 8 ft spliced over a base cross).", "",
           "Board packing:"]
    for i, (st, b) in enumerate(boards, 1):
        md.append(f"- board {i} ({'10' if st > 3000 else '8'} ft): " + " + ".join(str(x) for x in b) + f"  (waste {st - sum(b) - 4 * len(b):.0f} mm)")
    area = {}
    for g, n, m, a, b, note in rows:
        if m == "18 mm ply box":
            A, B, C = map(int, re.match(r"outer (\d+) x (\d+) x (\d+)", note).groups())
            area["18 mm ply"] = area.get("18 mm ply", 0) + (A * B + 2 * B * (C - 18) + 2 * (A - 36) * (C - 18)) / 1e6
        elif b:
            k = "18 mm ply" if m.startswith("18") else m
            fac = 2.0 if "Pod cheek" in n else 1.0
            area[k] = area.get(k, 0) + fac * a * b / 1e6 * (0.6 if "cheek" in n.lower() else 1.0)
    sheet = 1.22 * 2.44
    md += ["", "**Sheet goods** (area incl. seat/console boxes; 4 x 8 ft = 1220 x 2440 mm sheets, ~30 % waste allowance; "
           "the pod cheeks are 2 layers each):", ""]
    for k, v in sorted(area.items()):
        md.append(f"- {k}: {v:.2f} m2 ({v * 10.764:.0f} sq ft) -> **{math.ceil(v * 1.3 / sheet)} sheet(s)**")
    with open(os.path.join(HERE, "cut_list.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    return n8, n10, {k: round(v, 2) for k, v in area.items()}


# ------------------------------------------------------------------ main
def main():
    clr = clearance_report()
    write_scad(clr)
    n8, n10, area = write_lists()
    geo = dict(
        dims=dict(L=L, W=2 * XSKIN, tower_top=CASE["top"], swept_height=clr["overall_height_swept"]),
        cradle=dict(pivot_dz=CP, recline_deg=RECLINE, mass_kg_design=round(CR_MASS, 1),
                    items=[(n, round(m, 1), [round(v) for v in p]) for n, m, p in CR_ITEMS],
                    torque_Nm=[round(v, 1) for v in CR_TORQUE], thetas=[round(v, 1) for v in CR_THETAS],
                    actuator=dict(CR_ACT, x=CR_ACT_X)),
        pod=dict(pivot_dz=PP, alpha_down=ALPHA_DN, alpha_up=ALPHA_UP, r_screen=R_SCREEN, mass_kg=round(POD_MASS, 1),
                 cg_dz=[round(v) for v in POD_CG], cg_radius=round(float(np.hypot(POD_CG[0] - PP[0], POD_CG[1] - PP[1]))),
                 extra=[(n, m) for n, m, _ in POD_EXTRA],
                 alphas=[round(float(a), 1) for a in ALPHAS], gravity_torque_Nm=[round(float(v), 1) for v in MG],
                 net_torque_with_struts_Nm=[round(float(v), 1) for v in NET],
                 strut=STRUT, actuator=POD_ACT, cheek_pts=[[round(a, 1), round(b, 1)] for a, b in CHEEK], window=WINDOW),
        ramp=RAMP, clearances=clr, lumber=dict(boards_8ft=n8, boards_10ft=n10), sheet_area_m2=area,
        kids_reclined={nm: {j: [round(v) for v in recline_pt(KIDS[k][j])] for j in ("head", "hip", "knee", "toe")} for nm, (k, x) in KID_SEATING.items()},
    )
    with open(os.path.join(GEN, "geometry.json"), "w") as f:
        json.dump(geo, f, indent=1, default=float)
    print(json.dumps(dict(PP=PP, pod_mass=geo["pod"]["mass_kg"], cg=geo["pod"]["cg_dz"], strut=STRUT, pod_act={k: v for k, v in POD_ACT.items() if k not in ("F_each", "arm_m")},
                          cr_act={k: v for k, v in CR_ACT.items() if k not in ("F_each", "arm_m")}, cr_torque=geo["cradle"]["torque_Nm"],
                          net=geo["pod"]["net_torque_with_struts_Nm"], gravity=geo["pod"]["gravity_torque_Nm"], window=WINDOW), indent=1, default=float))
    print(json.dumps(clr, indent=1))


if __name__ == "__main__":
    main()
