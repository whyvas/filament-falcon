"""Diagram 04 (v0.3): hardwired crew-position circuit. Cradle recline (2 actuators) and kids'
pod (ONE actuator + torque tube), each driven by a 2-relay H-bridge; the coils are fed only through the
hold-to-run CREW POS toggle and the interlock contacts (locks, lever, safety edge). No
microcontroller can move anything: Falcon Command only READS three isolated sense contacts.
Matches frame/README.md "Safety concept" and frame/BOM.md "Hardwired interlock"."""
from diag_common import *

fig, ax = new(23, 19, "04  Crew position v0.3: cradle recline (2 act.) + pod (1 act.), hardwired relay H-bridges and interlock (NO software control)")
P12, G = C["12v"], C["gnd"]
CT = "#6a1b9a"          # control (coil) wiring
BUS = 176               # +12 V MOTION bus


def coil(x, y, name, sub):
    ax.add_patch(Rectangle((x, y - 3), 12, 6, fc="#fff3e0", ec="k", lw=1.4))
    line(ax, [(x, y - 3), (x + 12, y + 3)], "k", 1.0)
    ax.text(x + 6, y + 4.2, name, ha="center", va="bottom", fontsize=8.5, weight="bold")
    ax.text(x + 6, y - 4.2, sub, ha="center", va="top", fontsize=7)


def relay_contact(x, y, name, no_right=False):
    """SPDT relay contact: common at (x,y) on top, NO / NC below. Resting on NC (= GND)."""
    no = (x + 4, y - 8) if no_right else (x - 4, y - 8)
    nc = (x - 4, y - 8) if no_right else (x + 4, y - 8)
    for p in (no, nc):
        ax.add_patch(Circle(p, 0.5, fc="white", ec="k", zorder=4))
    ax.add_patch(Circle((x, y), 0.5, fc="white", ec="k", zorder=4))
    line(ax, [(x, y), (nc[0] * 0.85 + x * 0.15, nc[1] + 1.2)], "k", 2.0)
    ax.text(no[0], no[1] - 1.4, "NO", fontsize=6.5, ha="center", va="top")
    ax.text(nc[0], nc[1] - 1.4, "NC", fontsize=6.5, ha="center", va="top")
    ax.text(x + (-6 if no_right else 6), y + 0.5, name, fontsize=8, weight="bold",
            ha="right" if no_right else "left", va="center")
    line(ax, [nc, (nc[0], nc[1] - 4)], G, 1.8)
    ground(ax, nc[0], nc[1] - 4, G)
    return no


def limit(x1, y, label, diode_dir, w=14):
    x2 = x1 + w
    switch_no(ax, x1, y, x2, "", "k", nc=True)
    line(ax, [(x1, y), (x1, y - 6)], "k", 1.4)
    line(ax, [(x2, y), (x2, y - 6)], "k", 1.4)
    if diode_dir > 0:
        diode(ax, x1, y - 6, x2, y - 6, "", "k")
    else:
        diode(ax, x2, y - 6, x1, y - 6, "", "k")
    dot(ax, x1, y); dot(ax, x2, y)
    ax.text((x1 + x2) / 2, y + 2.2, label, ha="center", fontsize=7, va="bottom")
    ax.text((x1 + x2) / 2, y - 8.6, "1N5408", ha="center", fontsize=6.5, va="top")
    return x2


def bridge(y, kl, kr, lim, motors, title, n_mot=2):
    """One H-bridge: left relay contact at x=136, right at x=212, motor path between."""
    ax.text(174, y + 22, title, ha="center", fontsize=10, weight="bold")
    no_l = relay_contact(136, y, kl)
    line(ax, [no_l, (128, no_l[1])], P12, 2.2)
    dot(ax, 128, no_l[1], P12)
    no_r = relay_contact(212, y - 22, kr, no_right=True)
    line(ax, [no_r, (220, no_r[1])], P12, 2.2)
    dot(ax, 220, no_r[1], P12)
    ym = y + 6
    line(ax, [(136, y), (136, ym), (144, ym)], "k", 2.4)
    x = 144
    for lab, d in lim:
        x2 = limit(x, ym, lab, d)
        line(ax, [(x2, ym), (x2 + 3, ym)], "k", 2.4)
        x = x2 + 3
    line(ax, [(x, ym), (200 if n_mot == 2 else 193, ym)], "k", 2.4)
    yb = y - 16
    for i, mx in enumerate((186, 200)[:n_mot] if n_mot == 2 else (193,)):
        line(ax, [(mx, ym), (mx, y - 2)], "k", 2.0)
        ax.add_patch(Circle((mx, y - 6), 4, fc="white", ec="k", lw=2))
        ax.text(mx, y - 6, "M", ha="center", va="center", fontsize=11, weight="bold")
        line(ax, [(mx, y - 10), (mx, yb)], "k", 2.0)
        dot(ax, mx, ym); dot(ax, mx, yb)
    ax.text(165, y - 6, motors, ha="center", fontsize=6.8, va="top")
    line(ax, [(186 if n_mot == 2 else 193, yb), (212, yb), (212, y - 22)], "k", 2.4)
    ax.text(150, ym + 9, "M+", fontsize=7.5)
    ax.text(204, yb + 1, "M-", fontsize=7.5)


# ---------------------------------------------------------------- supply + MOTION relay K0
box(ax, 2, 160, 18, 20, "12 V DC PSU\n20 A, enclosed\nmains fused", fc="#fde7ef")
line(ax, [(11, 180.4), (11, 184), (16, 184), (16, BUS)], P12, 2.6)
fuse(ax, 16, BUS, 30, BUS, "", P12)
ax.text(23, BUS - 3.6, "F1 20 A", ha="center", fontsize=8, weight="bold")
dot(ax, 32, BUS, P12)
line(ax, [(30, BUS), (40, BUS)], P12, 2.6)
switch_no(ax, 40, BUS, 54, "K0 contact\n(30 A, MOTION)", P12)
line(ax, [(54, BUS), (220, BUS)], P12, 2.6)
ax.text(100, BUS + 1.2, "+12 V MOTION  (dead with the key out or the E-stop pressed)", color=P12, fontsize=8)
line(ax, [(11, 159.6), (11, 156)], G, 2.2)
ground(ax, 11, 156, G)
# K0 coil: key + E-stop
line(ax, [(32, BUS), (32, 166), (36, 166)], P12, 1.8)
switch_no(ax, 36, 166, 50, "MOTION key\n(CMD_B)", P12)
switch_no(ax, 50, 166, 66, "E-STOP NC\nlatching (CMD_B)", P12, nc=True)
coil(68, 166, "K0", "MOTION relay")
line(ax, [(80, 166), (84, 166), (84, 162)], G, 1.8)
ground(ax, 84, 162, G)

# ---------------------------------------------------------------- control: CREW POS + interlock
line(ax, [(110, BUS), (110, 170)], P12, 1.8)
dot(ax, 110, BUS, P12)
fuse(ax, 110, 170, 110, 160, "F2 1 A", CT)
line(ax, [(110, 160), (110, 157), (8, 157), (8, 141)], CT, 1.8)
ax.text(60, 158, "+12 V CTRL (coils only)", color=CT, fontsize=7.5)
# pole A
pa, fa, ba = (8, 141), (18, 146), (18, 136)
for p in (pa, fa, ba):
    ax.add_patch(Circle(p, 0.5, fc="white", ec="k", zorder=4))
line(ax, [pa, (16, 141.6)], "k", 2)
ax.text(19, 147.5, "FLT", fontsize=7.5, weight="bold")
ax.text(19, 132.5, "BRD", fontsize=7.5, weight="bold")
ax.text(2, 126, "CREW POS\nDPDT (ON)-OFF-(ON)\nhold-to-run (CMD_B)\npole A", fontsize=7, va="top")
# FLT bus x=28 (y 152..124), BRD bus x=24 (y 136..86)
line(ax, [fa, (28, 146)], CT, 2)
line(ax, [(28, 152), (28, 124)], CT, 2)
line(ax, [ba, (24, 136), (24, 88)], CT, 2)
YK1, YK3, YK2, YK4 = 152, 124, 106, 88
# K1 cradle RECLINE: FLT -> POD_UP_LOCKED
line(ax, [(28, YK1), (36, YK1)], CT, 1.8)
switch_no(ax, 36, YK1, 56, "POD UP + LOCKED\n(both pawls, NO, series)", CT)
line(ax, [(56, YK1), (100, YK1)], CT, 1.8)
coil(100, YK1, "K1", "cradle RECLINE")
# K3 pod DOWN: FLT -> CRADLE_RECLINED (L+R) -> LEVER -> SAFETY EDGE
line(ax, [(28, YK3), (32, YK3)], CT, 1.8)
switch_no(ax, 32, YK3, 50, "CRADLE RECLINED\n(L + R, NO, series)", CT)
switch_no(ax, 50, YK3, 68, "release LEVER\nheld (NO)", CT)
switch_no(ax, 68, YK3, 88, "SAFETY EDGE\npod chin (NC)", CT, nc=True)
line(ax, [(88, YK3), (100, YK3)], CT, 1.8)
coil(100, YK3, "K3", "pod DOWN")
for yy in (YK1, YK3):
    dot(ax, 28, yy, CT)
# K2 cradle UPRIGHT: BRD -> POD_UP_LOCKED (2nd contacts)
line(ax, [(24, YK2), (36, YK2)], CT, 1.8)
switch_no(ax, 36, YK2, 56, "POD UP + LOCKED\n(2nd contacts, NO)", CT)
line(ax, [(56, YK2), (100, YK2)], CT, 1.8)
coil(100, YK2, "K2", "cradle UPRIGHT")
# K4 pod UP: BRD -> LEVER (2nd contact)
line(ax, [(24, YK4), (50, YK4)], CT, 1.8)
switch_no(ax, 50, YK4, 68, "release LEVER\nheld (2nd contact)", CT)
line(ax, [(68, YK4), (100, YK4)], CT, 1.8)
coil(100, YK4, "K4", "pod UP")
dot(ax, 24, YK2, CT)
# coil returns -> pole B (both throws) -> GND
for yy in (YK1, YK3, YK2, YK4):
    line(ax, [(112, yy), (118, yy)], CT, 1.6)
    dot(ax, 118, yy, CT)
line(ax, [(118, YK1), (118, 74), (20, 74)], CT, 1.6)
pb, fb, bb = (8, 74), (18, 79), (18, 69)
for p in (pb, fb, bb):
    ax.add_patch(Circle(p, 0.5, fc="white", ec="k", zorder=4))
line(ax, [pb, (16, 74.6)], "k", 2)
line(ax, [fb, (20, 79), (20, 69), bb], CT, 1.6)
line(ax, [pb, (4, 74), (4, 70)], G, 1.8)
ground(ax, 4, 70, G)
ax.plot([8, 8], [72, 139], ls="--", color="#777", lw=1.0)
ax.text(10, 66, "pole B: coil return (a welded pole A\nstill can't run anything once you let go)", fontsize=6.8, va="top")
ax.text(60, 69.5, "every coil: 1N4007 flyback diode across it", fontsize=7, ha="center", style="italic")

# ---------------------------------------------------------------- H-bridges
line(ax, [(128, BUS), (128, 70)], P12, 2.2)
dot(ax, 128, BUS, P12)
line(ax, [(220, BUS), (220, 62)], P12, 2.2)
bridge(144, "K1", "K2", [("RECLINED limit\n(NC)", +1), ("UPRIGHT limit\n(NC)", -1)],
       "cradle actuators L + R\n10\" stroke, 1500 N,\nself-locking", "CRADLE  (K1 / K2)")
bridge(92, "K3", "K4", [("POD DOWN limit\n(NC, left cheek)", +1), ("POD UP limit\n(NC, left cheek)", -1)],
       "ONE pod actuator (left)\n12\" stroke, 1500 N,\nself-locking", "POD  (K3 / K4)", n_mot=1)
ax.text(174, 63, "Both relays off (or both on) = both motor leads on the same rail = stopped and braked.\n"
        "One relay on = one direction. No relay combination can short the supply.", ha="center", fontsize=7, va="top")

# ---------------------------------------------------------------- read-only senses
ax.text(2, 58, "READ-ONLY SENSES to Falcon Command (separate micro switches; the game can read, never drive)",
        fontsize=9, weight="bold")
rows = [(51, "CRADLE RECLINED", "GPIO39 · HID 15 · cradle_reclined"),
        (43, "POD DOWN + LOCKED (pawl in)", "GPIO40 · HID 26 · pod_down_locked"),
        (35, "POD UP + LOCKED (optional)", "GPIO41 · HID 27 · pod_up_locked")]
line(ax, [(4, 54), (4, 35)], P12, 1.6)
ax.text(5, 55, "+12 V from F1 (before the key, so the senses work with the key out)", color=P12, fontsize=7)
for y, name, gp in rows:
    line(ax, [(4, y), (8, y)], P12, 1.6)
    dot(ax, 4, y, P12)
    switch_no(ax, 8, y, 26, "", P12)
    ax.text(17, y + 1.6, name, ha="center", fontsize=6.8, va="bottom")
    resistor(ax, 26, y, 38, y, "", P12)
    ax.text(32, y - 2.6, "2.2 kΩ ½ W", ha="center", fontsize=6.5)
    ax.add_patch(Rectangle((40, y - 3), 14, 6, fc="#fafafa", ec="k", lw=1.2))
    ax.text(47, y, "PC817", ha="center", va="center", fontsize=7.5, weight="bold")
    line(ax, [(38, y), (40, y)], P12, 1.6)
    line(ax, [(54, y), (58, y)], "k", 1.4)
    ax.text(59, y, "C → " + gp + "  (10 kΩ pull-up to 3V3, LOW = closed);  E → ESP32 GND", fontsize=7, va="center")
ax.text(47, 30.5, "LED cathodes → 12 V GND  |  isolation  |  transistor side → ESP32", fontsize=6.5, ha="center", color="#666")

note(ax, 2, 27, 224, (
    "FLIGHT: key in, hold CREW POS at FLT. K1 reclines the cradle (only while the pod is UP and latched) until the RECLINED limit opens. Keep holding and pull the release lever: K3 "
    "brings the pod down (only while the\n"
    "cradle is fully reclined on BOTH sides, the lever is held and the safety edge is not pressed) until the pawls drop into the DOWN notch. BOARD: hold BRD + lever: K4 raises the pod; once it is UP and latched, K2 brings the seats upright.\n"
    "Let go of either hand = stop. E-stop or key out = K0 drops = no motor power at all. Each limit switch is bridged by a 1N5408 so you can always drive back off it (the diode carries the motor current only "
    "until the switch re-closes,\n"
    "~1 s; for actuators drawing > 3 A each use 6A10). Relays: 12 V 30 A automotive SPDT (Bosch type). Wire 14 AWG from the PSU to the bridges, 20 AWG for coils. Test with NOBODY seated: every limit, lock, "
    "lever, edge, E-stop, key.\n"
    "The game shows POD UP / MOVING / DOWN-LOCKED and SEATS UPRIGHT / MOVING / RECLINED from the three sense contacts and announces \"pod coming down\" over the intercom; it never drives a relay."),
    title="How it works (v0.3, frame/README.md safety concept; ONE pod limit set, 3 read-only senses)", fs=7.3)
ax.set_ylim(9, 190)
save(fig, "04_seat_actuator")
