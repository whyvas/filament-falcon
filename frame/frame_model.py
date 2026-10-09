#!/usr/bin/env python3
"""The Filament Falcon - wooden frame model (single source of truth).

Generates:
  frame/generated/frame.scad      3D frame + seat platform + placement transforms (for renders)
  frame/generated/geometry.json   key numbers (actuator geometry, clearances) for the docs
  frame/cut_list.csv / .md        every wooden part with its size
  frame/BOM.md                    lumber, sheet goods, hardware, electrical
  frame/drawings/*.svg/.png/.pdf  dimensioned drawings (via make_drawings.py)

Conventions: mm.  x = to the kids' RIGHT, y = FORWARD (toward the monitors),
z = UP.  The front face of the frame is y = 0, the rear is y = -2100.
Internally we often use d = distance back from the front (y = -d).
Lumber: 2x4 = 38 x 89 mm (1.5" x 3.5"), plywood 18 mm (3/4"), 12 mm (1/2"), 6 mm (1/4").
"""
import json, math, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "generated")
T2, W2 = 38.0, 89.0          # 2x4 actual
PLY = 18.0

# ------------------------------------------------------------------ key dimensions
W = 1700.0                   # outside width
L = 2100.0                   # outside length
H = 1800.0                   # outside height
XO = W / 2                   # 850
XI = XO - T2                 # 812 (inner face of side members)

D_KNEE = 400.0               # knee posts (front of the side boarding opening)
D_MID = 1000.0               # mid posts (back of the boarding opening)
HEADER_Z = (850.0, 939.0)    # actuator header (doubled 2x4) and lower side rails
HEADER_D = (150.0, 226.0)
MON_BEAM_Z = (1313.0, 1402.0)
MON_BEAM_D = (51.0, 89.0)    # front face toward the kids at d = 89
TOP_Z = (H - W2, H)

# dash: front face plane through (d=380, z=780) .. (d=280, z=980)
DASH_P0 = (380.0, 780.0)
DASH_P1 = (280.0, 980.0)
DASH_X = [(-794.0, -246.0), (246.0, 794.0)]      # dash sheets (between cheeks)
DASH_PANEL_CX = [-460.0, 460.0]                  # pilot / ops panel group centres

# platform (lowered = deck horizontal)
PX = 780.0                    # platform half width
P_D = (170.0, 2050.0)         # platform front (nose) .. rear
J_Z = (95.0, 184.0)           # joists, on 6 mm rubber stops on the base
DECK_Z = 202.0                # deck top (lowered)
HINGE = (2031.0, 122.3)       # (d, z) pivot: 20 mm shaft in 2 x UCP204 pillow blocks on the sills
ACT_X = 500.0                 # actuators at x = +-500
ACT_D = 160.0                 # actuator line (d)
ACT_TOP_Z = HEADER_Z[0]       # upper clevis just under the header
ACT_BOT_Z = 110.0             # lower clevis on the platform nose (lowered)
STROKE = 300.0                # 12" stroke
RETRACT = 440.0               # pin-to-pin retracted (typical 12" actuator: 17.3")

# occupants / masses for the force estimate
MASSES = [  # (name, kg, d of centre of mass)
    ("two kids (2 x 45 kg, upper bound for 12 yr)", 90.0, 660.0),
    ("adult (dad)", 110.0, 1520.0),
    ("platform, deck, seats, consoles (estimate)", 110.0, 1150.0),
]

KID_SEAT_X = [-380.0, 380.0]
KID_SEAT = dict(w=340.0, d=(470.0, 850.0), h=220.0, back_h=850.0)
DAD_SEAT = dict(w=520.0, d=(1300.0, 1780.0), h=450.0, back_h=1250.0)


def y(d):
    return -d


# ------------------------------------------------------------------ actuator geometry
def rot_platform(theta, d, z):
    """Rotate a platform point (given in lowered coords) by theta (rad) about the hinge.
    Front goes up."""
    hd, hz = HINGE
    rd, rz = d - hd, z - hz       # rd negative for points in front of the hinge
    # front (rd < 0) rises with positive theta
    nd = hd + rd * math.cos(theta) + rz * math.sin(theta)
    nz = hz - rd * math.sin(theta) + rz * math.cos(theta)
    return nd, nz


def act_len(theta):
    nd, nz = rot_platform(theta, ACT_D, ACT_BOT_Z)
    return math.hypot(nd - ACT_D, ACT_TOP_Z - nz), nd, nz


def solve_theta_max():
    lo, hi = 0.0, math.radians(25)
    target = RETRACT
    for _ in range(60):
        mid = (lo + hi) / 2
        if act_len(mid)[0] > target:
            lo = mid
        else:
            hi = mid
    return lo


THETA_MAX = solve_theta_max()


def force_estimate():
    g = 9.81
    out = []
    for th in (0.0, THETA_MAX / 2, THETA_MAX):
        M = 0.0
        for _, m, d in MASSES:
            nd, _ = rot_platform(th, d, DECK_Z + 300)
            M += m * g * (HINGE[0] - nd) / 1000.0           # N*m
        Lc, nd, nz = act_len(th)
        # unit vector along the actuator from lower to upper clevis (d, z)
        ud, uz = (ACT_D - nd) / Lc, (ACT_TOP_Z - nz) / Lc
        rd, rz = (nd - HINGE[0]) / 1000.0, (nz - HINGE[1]) / 1000.0
        arm = abs(rd * uz - rz * ud)                         # m, moment arm about hinge
        F_total = M / arm
        out.append(dict(theta_deg=math.degrees(th), moment_Nm=M, arm_m=arm,
                        force_total_N=F_total, force_each_N=F_total / 2, length_mm=Lc))
    return out


# ------------------------------------------------------------------ members
class Part:
    def __init__(self, name, mat, group, box=None, poly=None, plane=None, thick=None, note="", color=None, xform=None, cut=None):
        self.name, self.mat, self.group = name, mat, group
        self.box, self.poly, self.plane, self.thick = box, poly, plane, thick
        self.note, self.color, self.xform, self.cut = note, color, xform, cut


PARTS = []


def lumber(name, group, x0, x1, d0, d1, z0, z1, note="", qty_tag=None):
    PARTS.append(Part(name, "2x4", group, box=(x0, y(d1), z0, x1, y(d0), z1), note=note))


def sheet(name, mat, group, x0, x1, d0, d1, z0, z1, note=""):
    PARTS.append(Part(name, mat, group, box=(x0, y(d1), z0, x1, y(d0), z1), note=note))


def side_profile(name, mat, group, x0, thick, pts_dz, note=""):
    """Plywood plate in a y-z plane at x = x0 .. x0 + thick, outline given as (d, z) points."""
    PARTS.append(Part(name, mat, group, poly=[(y(d), z) for d, z in pts_dz], plane=("x", x0), thick=thick, note=note))


# ---- fixed frame
for s, nm in ((-1, "L"), (1, "R")):
    xa, xb = (-XO, -XI) if s < 0 else (XI, XO)
    lumber(f"Sill {nm}", "fixed", xa, xb, 0, L, 0, W2, "on edge")
    lumber(f"Front post {nm}", "fixed", xa, xb, 0, W2, W2, TOP_Z[0])
    lumber(f"Knee post {nm}", "fixed", xa, xb, D_KNEE, D_KNEE + W2, W2, HEADER_Z[1])
    lumber(f"Mid post {nm}", "fixed", xa, xb, D_MID, D_MID + W2, W2, TOP_Z[0])
    lumber(f"Top side rail {nm}", "fixed", xa, xb, 0, D_MID + W2, TOP_Z[0], TOP_Z[1], "on edge, on top of the posts")
    lumber(f"Lower side rail {nm}", "fixed", xa, xb, W2, D_KNEE, HEADER_Z[0], HEADER_Z[1], "on edge, carries the actuator header")
for nm, d0 in (("Base cross, front", 0), ("Base cross, stop rail", D_MID), ("Base cross, hinge", 1962), ("Base cross, rear", L - T2)):
    lumber(nm, "fixed", -XI, XI, d0, d0 + T2, 0, W2, "on edge")
for nm, d0 in (("Top cross, front", 0), ("Top cross, overhead front", 300), ("Top cross, overhead rear", 600), ("Top cross, mid posts", D_MID + W2 - T2)):
    lumber(nm, "fixed", -XI, XI, d0, d0 + T2, TOP_Z[0], TOP_Z[1], "on edge between the top side rails")
lumber("Actuator header A", "fixed", -XI, XI, HEADER_D[0], HEADER_D[0] + T2, HEADER_Z[0], HEADER_Z[1], "doubled 2x4, glued + screwed")
lumber("Actuator header B", "fixed", -XI, XI, HEADER_D[0] + T2, HEADER_D[1], HEADER_Z[0], HEADER_Z[1], "doubled 2x4")
lumber("Monitor beam", "fixed", -XI, XI, MON_BEAM_D[0], MON_BEAM_D[1], MON_BEAM_Z[0], MON_BEAM_Z[1], "on edge, between the front posts")
# knee braces (45 deg, 300 mm long, both ends mitred) - modelled as small boxes for the drawings
for s, nm in ((-1, "L"), (1, "R")):
    x0 = -XO if s < 0 else XI
    for dpost, tag in ((W2, "front"), (D_MID, "mid")):
        dd = (dpost, dpost + 212) if tag == "front" else (dpost - 212, dpost)
        PARTS.append(Part(f"Knee brace {tag} {nm}", "2x4", "fixed", box=(x0, y(dd[1]), TOP_Z[0] - 212, x0 + T2, y(dd[0]), TOP_Z[0]),
                          note="45 deg brace, 300 mm long point-to-point", cut=300))
# dash cheeks + sheets
dash_dir = np.array([DASH_P1[0] - DASH_P0[0], DASH_P1[1] - DASH_P0[1]]); dash_len = np.linalg.norm(dash_dir); dash_u = dash_dir / dash_len
dash_n = np.array([dash_u[1], -dash_u[0]])  # (d, z) normal pointing to the kid (+d) and up
if dash_n[1] < 0:
    dash_n = -dash_n
back0 = np.array(DASH_P0) - dash_n * PLY
back1 = np.array(DASH_P1) - dash_n * PLY
cheek = [(HEADER_D[0], 760.0), (back0[0] - 8 * dash_u[0], 760.0), tuple(back0 - 10 * dash_u), tuple(back1 + 10 * dash_u), (HEADER_D[0], back1[1] + 10 * dash_u[1])]
for nm, x0 in (("Dash cheek, outer L", -XI), ("Dash cheek, inner L", -246.0), ("Dash cheek, inner R", 228.0), ("Dash cheek, outer R", XI - PLY)):
    side_profile(nm, "ply18", "fixed", x0, PLY, cheek, "screwed to the header and side rails")
for i, (xa, xb) in enumerate(DASH_X):
    nm = "Dash sheet, PILOT (left)" if i == 0 else "Dash sheet, OPS (right)"
    PARTS.append(Part(nm, "ply18", "fixed", xform=("dash", xa, xb, dash_len + 30), note="panel bay 400 x 120 opening + M5 T-nuts on the 40 mm grid"))
sheet("Front skin", "ply12", "fixed", -XO, XO, -12, 0, 0, HEADER_Z[1], "12 mm ply, braces the front + guards the actuators")
sheet("Side skin L", "ply12", "fixed", -XO - 12, -XO, 0, D_KNEE + W2, 0, HEADER_Z[1], "guards the actuator bay")
sheet("Side skin R", "ply12", "fixed", XO, XO + 12, 0, D_KNEE + W2, 0, HEADER_Z[1], "")
# overhead console box (hangs on 4 x M8 threaded rods from the overhead top crosses)
OH_C = (450.0, 1480.0); OH_TILT = math.radians(20)
PARTS.append(Part("Overhead console box", "ply12", "fixed", xform=("overhead",), note="640 x 220 face with 600 x 80 opening, 12 mm ply box, hangs on 4 x M8 rods (+-80 mm height adjust)"))
# base skirts (telescoping pinch guards along the sides of the platform)
def lift_at(d):
    return rot_platform(THETA_MAX, d, J_Z[0])[1] - J_Z[0]
for s, nm in ((-1, "L"), (1, "R")):
    x0 = -XO - 6 if s < 0 else XO
    side_profile(f"Fixed side skirt {nm}", "ply6", "fixed", x0, 6.0,
                 [(D_KNEE + W2, 0), (L, 0), (L, W2 + 40), (D_KNEE + W2, max(W2 + 40, lift_at(D_KNEE + W2) + 220))],
                 "6 mm ply/hardboard; outer half of the telescoping pinch guard")

# ---- platform (modelled lowered; rotated in the renders)
RIMS = (("Platform nose rim", P_D[0]), ("Platform cross, seats", 900.0), ("Platform cross, dad", 1700.0), ("Platform rear rim", 1974.0))
for nm, xa in (("Platform joist outer L", -PX), ("Platform joist outer R", PX - T2)):
    lumber(nm, "platform", xa, xa + T2, P_D[0], P_D[1], J_Z[0], J_Z[1], "on edge; 21 mm hinge-shaft hole 19 mm from the rear end, 27 mm up")
for nm, d0 in RIMS:
    lumber(nm, "platform", -PX + T2, PX - T2, d0, d0 + T2, J_Z[0], J_Z[1], "on edge, between the outer joists")
for nm, xa in (("Platform joist inner L", -ACT_X - T2 / 2), ("Platform joist centre", -T2 / 2), ("Platform joist inner R", ACT_X - T2 / 2)):
    for k in range(len(RIMS) - 1):
        a, b = RIMS[k][1] + T2, RIMS[k + 1][1]
        lumber(f"{nm} seg {k + 1}", "platform", xa, xa + T2, a, b, J_Z[0], J_Z[1], "between rims, joist hangers or pocket screws")
sheet("Deck L", "ply18", "platform", -PX, 0, P_D[0], P_D[1], J_Z[1], DECK_Z, "glued + screwed every 150 mm")
sheet("Deck R", "ply18", "platform", 0, PX, P_D[0], P_D[1], J_Z[1], DECK_Z, "")
for s, nm in ((-1, "L"), (1, "R")):
    x0 = -PX - 6 if s < 0 else PX
    sheet(f"Platform skirt {nm}", "ply6", "platform", x0, x0 + 6, P_D[0], P_D[1], 20, J_Z[1], "inner half of the telescoping pinch guard")
sheet("Toe board", "ply12", "platform", -PX, PX, 250, 262, DECK_Z, DECK_Z + 150, "keeps feet off the actuators; moves with the feet (no relative motion)")
# seats
for i, cx in enumerate(KID_SEAT_X):
    nm = "PILOT" if i == 0 else "OPS"
    w = KID_SEAT["w"]; d0, d1 = KID_SEAT["d"]
    sheet(f"Kid seat box {nm}", "ply18", "platform", cx - w / 2, cx + w / 2, d0, d1, DECK_Z, DECK_Z + KID_SEAT["h"], "18 mm ply box, foam cushion on top")
    sheet(f"Kid seat back {nm}", "ply18", "platform", cx - w / 2, cx + w / 2, d1, d1 + PLY, DECK_Z, DECK_Z + KID_SEAT["back_h"], "harness shoulder slots at 3 heights")
w = DAD_SEAT["w"]; d0, d1 = DAD_SEAT["d"]
sheet("Dad seat box", "ply18", "platform", -w / 2, w / 2, d0, d1, DECK_Z, DECK_Z + DAD_SEAT["h"], "")
sheet("Dad seat back", "ply18", "platform", -w / 2, w / 2, d1, d1 + PLY, DECK_Z, DECK_Z + DAD_SEAT["back_h"], "")
# consoles on the platform
CC_TOP = 400.0
sheet("Centre console box", "ply18", "platform", -210, 210, 240, 700, DECK_Z, CC_TOP, "touchscreen tray (front) + joystick / OPS_SIDE (rear)")
sheet("Pilot side console", "ply18", "platform", -770, -570, 480, 800, DECK_Z, 560, "PILOT_SIDE panel bay + throttle + gear lever")
sheet("Ops side console", "ply18", "platform", 570, 770, 480, 800, DECK_Z, 520, "Ops joystick housing on top")
sheet("Commander console", "ply18", "platform", 290, 530, 1290, 1710, DECK_Z, 852, "CMD_A + CMD_B panel bay, seat-lift switch here")


# ------------------------------------------------------------------ placements (for renders)
def mat_cols(xa, ya, za, origin):
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = xa, ya, za, origin
    return M


def dash_panel_M(i, piece):
    """Panel-local -> world for the dash panels (pilot i=0, ops i=1; piece 0=A left, 1=B right)."""
    cx = DASH_PANEL_CX[i]
    u = np.array([0, -dash_u[0], dash_u[1]])         # up the slope, toward the front
    n = np.array([0, -dash_n[0], dash_n[1]])         # out of the face (toward the kid)
    mid = (np.array(DASH_P0) + np.array(DASH_P1)) / 2
    c = np.array([cx, y(mid[0]), mid[1]])
    origin = c + np.array([-200 + 200 * piece, 0, 0]) - 80 * u + 3.0 * n   # panel sits ON the sheet
    return mat_cols(np.array([1, 0, 0]), u, n, origin)


def overhead_M(k):
    u = np.array([0, -math.cos(OH_TILT), math.sin(OH_TILT)])
    n = np.array([0, -math.sin(OH_TILT), -math.cos(OH_TILT)])
    c = np.array([0, y(OH_C[0]), OH_C[1]])
    origin = c + np.array([-300 + 200 * k, 0, 0]) - 60 * u + 3.0 * n
    return mat_cols(np.array([1, 0, 0]), u, n, origin)


def flat_M(x0, d_bottom, z):
    """Horizontal panel, top of text pointing forward; d_bottom = d of the panel's bottom edge."""
    return mat_cols(np.array([1, 0, 0]), np.array([0, 1, 0]), np.array([0, 0, 1]), np.array([x0, y(d_bottom), z + 3.0]))


PLACE = {
    "PILOT_DASH_A": ("fixed", dash_panel_M(0, 0)), "PILOT_DASH_B": ("fixed", dash_panel_M(0, 1)),
    "OPS_DASH_A": ("fixed", dash_panel_M(1, 0)), "OPS_DASH_B": ("fixed", dash_panel_M(1, 1)),
    "OVERHEAD_A": ("fixed", overhead_M(0)), "OVERHEAD_B": ("fixed", overhead_M(1)), "OVERHEAD_C": ("fixed", overhead_M(2)),
    "PILOT_SIDE": ("platform", flat_M(-770, 720, 560 + 0.5)),
    "OPS_SIDE": ("platform", flat_M(10, 690, CC_TOP + 0.5)),
    "CMD_A": ("platform", flat_M(310, 1490, 852 + 0.5)),
    "CMD_B": ("platform", flat_M(310, 1690, 852 + 0.5)),
}
PART_PLACE = {
    # name: (group, 4x4)
    "throttle": ("platform", flat_M(-770 + 45, 720 - 80, 560 + 0.5)),
    "gear": ("platform", flat_M(-770 + 160, 720 - 80, 560 + 0.5)),
    "joystick_pilot": ("platform", flat_M(-110, 610, CC_TOP)),
    "joystick_ops": ("platform", flat_M(670, 640, 520)),
    "bezel": ("platform", flat_M(0, 375, CC_TOP + 10)),
    "monitor_L": ("fixed", mat_cols(np.array([-1, 0, 0]), np.array([0, -1, 0]), np.array([0, 0, 1]), np.array([-380, y(MON_BEAM_D[1]), MON_BEAM_Z[0]]))),
    "monitor_R": ("fixed", mat_cols(np.array([-1, 0, 0]), np.array([0, -1, 0]), np.array([0, 0, 1]), np.array([380, y(MON_BEAM_D[1]), MON_BEAM_Z[0]]))),
}


# ------------------------------------------------------------------ clearance check (raised)
def part_corners(p, theta=0.0):
    pts = []
    if p.box:
        x0, y0, z0, x1, y1, z1 = p.box
        pts = [(x, yy, z) for x in (x0, x1) for yy in (y0, y1) for z in (z0, z1)]
    if p.group == "platform" and theta:
        out = []
        for x, yy, z in pts:
            nd, nz = rot_platform(theta, -yy, z)
            out.append((x, -nd, nz))
        pts = out
    return pts


def bbox(p):
    if p.box:
        return p.box
    if p.poly:
        ys = [a for a, b in p.poly]; zs = [b for a, b in p.poly]
        return (p.plane[1], min(ys), min(zs), p.plane[1] + p.thick, max(ys), max(zs))
    return None


def clearances():
    """Minimum vertical gap between raised platform parts and fixed parts above them (bbox test)."""
    res = []
    fixed = [type("B", (), dict(box=bbox(p), name=p.name))() for p in PARTS if p.group == "fixed" and bbox(p)]
    for p in PARTS:
        if p.group != "platform" or not p.box:
            continue
        pc = np.array(part_corners(p, THETA_MAX))
        px0, py0, pz0 = pc.min(0); px1, py1, pz1 = pc.max(0)
        for f in fixed:
            fx0, fy0, fz0, fx1, fy1, fz1 = f.box
            if px0 < fx1 and fx0 < px1 and py0 < fy1 and fy0 < py1:
                gap = fz0 - pz1 if fz0 >= pz0 else None
                if gap is not None and gap < 300:
                    res.append((gap, p.name, f.name))
    return sorted(res)[:6]


# ------------------------------------------------------------------ SCAD output
def scad_box(b):
    x0, y0, z0, x1, y1, z1 = b
    return f"translate([{x0:.1f},{y0:.1f},{z0:.1f}]) cube([{x1-x0:.1f},{y1-y0:.1f},{z1-z0:.1f}]);"


def scad_part(p):
    if p.box:
        return scad_box(p.box)
    if p.poly:
        pts = ",".join(f"[{a:.1f},{b:.1f}]" for a, b in p.poly)
        return f"translate([{p.plane[1]:.1f},0,0]) rotate([90,0,90]) linear_extrude({p.thick}) polygon([{pts}]);"
    if p.xform[0] == "dash":
        _, xa, xb, ln = p.xform
        M = dash_panel_M(0, 0)
        u, n = M[:3, 1], M[:3, 2]
        mid = (np.array(DASH_P0) + np.array(DASH_P1)) / 2
        o = np.array([xa, y(mid[0]), mid[1]]) - u * ln / 2 - n * PLY
        Mx = mat_cols(np.array([1, 0, 0]), u, n, o)
        mm = "[" + ",".join("[" + ",".join(f"{v:.4f}" for v in row) + "]" for row in Mx) + "]"
        cx = DASH_PANEL_CX[0] if xa < 0 else DASH_PANEL_CX[1]
        return (f"multmatrix({mm}) difference() {{ cube([{xb-xa:.1f},{ln:.1f},{PLY}]); "
                f"translate([{cx-200-xa+1:.1f},{ln/2-60:.1f},-1]) cube([398,120,{PLY+2}]); }}")
    if p.xform[0] == "overhead":
        M = overhead_M(0)
        mm = "[" + ",".join("[" + ",".join(f"{v:.4f}" for v in row) + "]" for row in M) + "]"
        return (f"multmatrix({mm}) translate([-20,-50,-12]) difference() {{ union() {{ cube([640,220,12]); translate([0,0,-150]) cube([12,220,150]); translate([628,0,-150]) cube([12,220,150]); translate([0,208,-150]) cube([640,12,150]); }} "
                f"translate([21,70,-1]) cube([598,80,14]); }}")
    return ""


COLORS = {"2x4": "#c8a165", "ply18": "#d9b98a", "ply12": "#e3c79c", "ply6": "#b89a6e"}


def mat_str(M):
    return "[" + ",".join("[" + ",".join(f"{v:.4f}" for v in row) + "]" for row in M) + "]"


def write_scad():
    os.makedirs(GEN, exist_ok=True)
    L_ = ["// GENERATED by frame/frame_model.py - do not edit by hand.",
          f"FRAME_THETA_MAX = {math.degrees(THETA_MAX):.3f};",
          f"FRAME_HINGE = [0, {y(HINGE[0]):.1f}, {HINGE[1]:.1f}];", ""]
    for grp in ("fixed", "platform"):
        L_.append(f"module ff_frame_{grp}(ghost = false) {{")
        for p in PARTS:
            if p.group == grp:
                L_.append(f"  color(\"{COLORS[p.mat]}\", ghost ? 0.25 : 1) {scad_part(p)}  // {p.name}")
        L_.append("}")
    L_.append("// rotate platform-mounted children to the seat angle (deg, 0 = lowered)")
    L_.append("module ff_platform_pose(a) { translate(FRAME_HINGE) rotate([a, 0, 0]) translate(-FRAME_HINGE) children(); }")
    for k, (grp, M) in list(PLACE.items()) + list(PART_PLACE.items()):
        L_.append(f"module at_{k}() multmatrix({mat_str(M)}) children();")
    L_.append("PLACE_GROUP = [" + ", ".join(f'["{k}", "{g}"]' for k, (g, _) in list(PLACE.items()) + list(PART_PLACE.items())) + "];")
    with open(os.path.join(GEN, "frame.scad"), "w") as f:
        f.write("\n".join(L_) + "\n")


# ------------------------------------------------------------------ cut list + BOM
def inch(mm):
    v = mm / 25.4
    return f'{v:.1f}"' if v < 24 else f"{int(v // 12)}' {v - 12 * int(v // 12):.1f}\""


def cut_rows():
    rows = []
    for p in PARTS:
        if p.mat == "2x4":
            if p.cut:
                ln = p.cut
            else:
                x0, y0, z0, x1, y1, z1 = p.box
                ln = max(x1 - x0, y1 - y0, z1 - z0)
            rows.append((p.group, p.name, "2x4 (38 x 89)", round(ln), None, p.note))
        else:
            if p.box:
                x0, y0, z0, x1, y1, z1 = p.box
                dims = sorted([x1 - x0, y1 - y0, z1 - z0], reverse=True)[:2]
            elif p.poly:
                ds = [a for a, b in p.poly]; zs = [b for a, b in p.poly]
                dims = sorted([max(ds) - min(ds), max(zs) - min(zs)], reverse=True)
            elif p.xform and p.xform[0] == "dash":
                dims = sorted([p.xform[2] - p.xform[1], p.xform[3]], reverse=True)
            else:
                dims = [640, 220]
            if p.box and ("box" in p.name or "console" in p.name) and "Overhead" not in p.name:
                x0, y0, z0, x1, y1, z1 = p.box
                a_, b_, c_ = round(x1 - x0), round(y1 - y0), round(z1 - z0)
                rows.append((p.group, p.name, "18 mm ply box", a_, b_,
                             f"outer {a_} x {b_} x {c_} (W x D x H): top {a_}x{b_}, 2 sides {b_}x{c_ - 18}, front+back {a_ - 36}x{c_ - 18}. " + p.note))
                continue
            rows.append((p.group, p.name, {"ply18": "18 mm ply", "ply12": "12 mm ply", "ply6": "6 mm ply/hardboard"}[p.mat], round(dims[0]), round(dims[1]), p.note))
    return rows


def lumber_buy(rows, stock=2438.0, kerf=4.0):
    lens = sorted([r[3] for r in rows if r[2].startswith("2x4")], reverse=True)
    boards = []
    for ln in lens:
        for b in boards:
            if sum(b) + len(b) * kerf + ln <= stock:
                b.append(ln)
                break
        else:
            boards.append([ln])
    return boards


def write_lists(geo):
    rows = cut_rows()
    import csv
    with open(os.path.join(HERE, "cut_list.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", "part", "material", "length_mm", "width_mm", "length_in", "width_in", "notes"])
        for g, n, m, a, b, note in rows:
            w.writerow([g, n, m, a, b if b else "", inch(a), inch(b) if b else "", note])
    boards8 = lumber_buy(rows)
    md = ["# Cut list (generated by `frame/frame_model.py`)", "",
          "All sizes in mm with inches in brackets. 2x4 = 38 x 89 mm actual (1.5\" x 3.5\").",
          "Check every length against your real lumber before cutting; 2x4 widths vary a little.", "",
          "| # | Group | Part | Material | Length | Width | Notes |", "|---|---|---|---|---|---|---|"]
    for i, (g, n, m, a, b, note) in enumerate(rows, 1):
        md.append(f"| {i} | {g} | {n} | {m} | {a} ({inch(a)}) | {'' if not b else f'{b} ({inch(b)})'} | {note} |")
    md += ["", f"**2x4 boards:** {len(rows and [r for r in rows if r[2].startswith('2x4')])} pieces from **{len(boards8)} x 8 ft (2438 mm)** boards "
           "(first-fit packing with 4 mm kerf; buy 2-3 spares). The two 2100 mm sills and the long joists need 8 ft boards; "
           "the 1880 mm joists leave short offcuts for the knee braces.", ""]
    md.append("Board packing:")
    for i, b in enumerate(boards8, 1):
        md.append(f"- board {i}: " + " + ".join(str(x) for x in b) + f"  (waste {2438 - sum(b) - 4 * len(b):.0f} mm)")
    with open(os.path.join(HERE, "cut_list.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    area = {}
    for g, n, m, a, b, note in rows:
        if m == "18 mm ply box":
            import re
            A, B, C = map(int, re.match(r"outer (\d+) x (\d+) x (\d+)", note).groups())
            area["18 mm ply"] = area.get("18 mm ply", 0) + (A * B + 2 * B * (C - 18) + 2 * (A - 36) * (C - 18)) / 1e6
        elif b:
            area[m] = area.get(m, 0) + a * b / 1e6
    sheet = 1.22 * 2.44
    md2 = ["", "**Sheet goods** (area incl. seat/console boxes; buy 4 x 8 ft = 1220 x 2440 mm sheets, ~30 % waste allowance):", ""]
    for k, v in sorted(area.items()):
        md2.append(f"- {k}: {v:.2f} m2 ({v * 10.764:.0f} sq ft) -> **{math.ceil(v * 1.3 / sheet)} sheet(s)**")
    with open(os.path.join(HERE, "cut_list.md"), "a") as f:
        f.write("\n".join(md2) + "\n")
    return len(boards8), area


def main():
    write_scad()
    fe = force_estimate()
    raised = {k: rot_platform(THETA_MAX, *v) for k, v in {
        "kid_cushion": (660.0, DECK_Z + KID_SEAT["h"]), "dad_cushion": (1540.0, DECK_Z + DAD_SEAT["h"]),
        "nose": (P_D[0], J_Z[0]), "console_top_front": (240.0, CC_TOP),
        "kid_knee": (KID_SEAT["d"][0], DECK_Z + KID_SEAT["h"] + 100), "toe_board_top": (256.0, DECK_Z + 150)}.items()}
    geo = dict(theta_max_deg=math.degrees(THETA_MAX), stroke_mm=STROKE, retracted_mm=RETRACT,
               extended_mm=act_len(0)[0], hinge=dict(d=HINGE[0], z=HINGE[1]),
               actuator=dict(x=ACT_X, d=ACT_D, top_z=ACT_TOP_Z, bottom_z_lowered=ACT_BOT_Z),
               forces=fe, masses=MASSES,
               raised_points={k: dict(d=round(v[0], 1), z=round(v[1], 1)) for k, v in raised.items()},
               lowered_points=dict(kid_cushion_z=DECK_Z + KID_SEAT["h"], dad_cushion_z=DECK_Z + DAD_SEAT["h"], deck_z=DECK_Z),
               clearances=[dict(gap_mm=round(g, 1), moving=a, fixed=b) for g, a, b in clearances()],
               dims=dict(W=W, L=L, H=H))
    nboards, area = write_lists(geo)
    geo["lumber_8ft_boards"] = nboards
    geo["sheet_area_m2"] = {k: round(v, 2) for k, v in area.items()}
    with open(os.path.join(GEN, "geometry.json"), "w") as f:
        json.dump(geo, f, indent=2)
    print(json.dumps({k: geo[k] for k in ("theta_max_deg", "extended_mm", "raised_points", "clearances", "lumber_8ft_boards", "sheet_area_m2")}, indent=1))
    for r in fe:
        print({k: round(v, 1) for k, v in r.items()})


if __name__ == "__main__":
    main()
