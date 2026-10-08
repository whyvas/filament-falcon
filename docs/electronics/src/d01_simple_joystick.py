"""Diagram 01: one 3-axis joystick + top button straight to an ESP32-S3-DevKitC-1."""
from diag_common import *
from matplotlib.patches import FancyBboxPatch

fig, ax = new(22, 12.5, "01  Simplest test: one 3-axis joystick + button -> ESP32-S3-DevKitC-1")
bx, by = 112, 18
used = {"L:3V3": C["3v3"], "L:4": C["x"], "L:5": C["y"], "L:6": C["z"], "L:15": C["btn"],
        "L:GND": C["gnd"], "L:7": C["lever"]}
pads = devkit(ax, bx, by, used=used)
p3v3, pgnd = pads["L:3V3"], pads["L:GND"]

# Joystick body
ax.add_patch(FancyBboxPatch((6, 16), 34, 82, boxstyle="round,pad=1", fc="#f2f2f2", ec="k", lw=1.5))
ax.text(23, 95, "JOYSTICK (wires sticking out)", ha="center", va="top", fontsize=10, weight="bold")
ax.text(23, 91.5, "3 pots (X, Y, twist) + top button", ha="center", va="top", fontsize=8)
XA, XG = 50, 57           # 3V3 bus / GND bus lanes
axes_def = [("X  (left/right)", 80, C["x"], "4"), ("Y  (fwd/back)", 60, C["y"], "5"),
            ("TWIST", 40, C["z"], "6")]
lanes = {"4": 96, "5": 90, "6": 84}
for name, yc, col, pin in axes_def:
    top, bot, wip = pot(ax, 20, yc, col, name, length=8)
    ya, yb = yc + 6, yc - 6
    wire(ax, [top, (20, ya), (40, ya)], "k", lw=1.2)
    wire(ax, [bot, (20, yb), (40, yb)], "k", lw=1.2)
    wire(ax, [wip, (40, yc)], "k", lw=1.2)
    for yy in (ya, yc, yb):
        ax.plot(40, yy, "o", color="k", ms=3)
    # end A -> 3V3 bus, end B -> GND bus, wiper -> GPIO
    wire(ax, [(40, ya), (XA, ya)], C["3v3"])
    dot(ax, XA, ya, C["3v3"])
    wire(ax, [(40, yb), (XG, yb)], C["gnd"], hops=[XA] if yb > 47 else [])
    dot(ax, XG, yb, C["gnd"])
    py = pads["L:" + pin][1]
    hops = [h for h, lo, hi in ((XA, 46, 86), (XG, 19, 74)) if lo <= yc <= hi]
    wire(ax, [(40, yc), (lanes[pin], yc), (lanes[pin], py), pads["L:" + pin]], col, hops=hops)
    ax.text(41.5, yc + 0.6, "wiper", fontsize=6.5, va="bottom")
    ax.text(41.5, ya + 0.6, "end", fontsize=6.5, va="bottom")
    ax.text(41.5, yb + 0.6, "end", fontsize=6.5, va="bottom")
    ax.text(lanes[pin] - 0.8, (py + yc) / 2, f"GPIO{pin}", rotation=90, ha="right", va="center",
            fontsize=8, color=col, weight="bold")

# Button
by1, by2 = 26, 21
ax.plot([20, 20], [by1, by1 - 1.5], "k", lw=1.5)
ax.plot([20, 20], [by2, by2 + 1.5], "k", lw=1.5)
ax.plot([18, 22], [by1 - 1.0, by1 - 1.0], "k", lw=1.5)
ax.plot([20, 20], [by1 - 1.0, by1 + 0.0], "k", lw=1.5)
ax.plot([17, 21.5], [by2 + 1.5, by2 + 3.8], "k", lw=1.5)
ax.text(16, (by1 + by2) / 2, "TOP\nBUTTON", ha="right", va="center", fontsize=8)
wire(ax, [(20, by1), (20, by1 + 1), (40, by1 + 1)], "k", lw=1.2)
wire(ax, [(20, by2), (20, by2 - 1), (40, by2 - 1)], "k", lw=1.2)
pb = pads["L:15"]
wire(ax, [(40, by1 + 1), (78, by1 + 1), (78, pb[1]), pb], C["btn"], hops=[XG])
ax.text(77.2, 45, "GPIO15", rotation=90, ha="right", va="center", fontsize=8, color=C["btn"], weight="bold")
wire(ax, [(40, by2 - 1), (XG, by2 - 1)], C["gnd"])
dot(ax, XG, by2 - 1, C["gnd"])

# Buses to the board
wire(ax, [(XA, 46), (XA, 86), (XA, p3v3[1] + 6), (104, p3v3[1] + 6), (104, p3v3[1]), p3v3], C["3v3"])
ax.text(XA - 1, 88, "3V3 bus", rotation=90, ha="right", va="bottom", fontsize=8, color=C["3v3"], weight="bold")
wire(ax, [(XG, 74), (XG, pgnd[1]), pgnd], C["gnd"])
ax.text(XG + 1, 76, "GND bus", rotation=90, ha="left", va="bottom", fontsize=8, color=C["gnd"], weight="bold")

# Notes
note(ax, 146, 106, 72, (
    "Joystick wire          -> DevKitC-1 pin (left header J1)\n"
    "X pot wiper            -> GPIO4   (J1 pin 4)\n"
    "Y pot wiper            -> GPIO5   (J1 pin 5)\n"
    "Twist pot wiper        -> GPIO6   (J1 pin 6)\n"
    "Throttle wiper (opt.)  -> GPIO7   (J1 pin 7)\n"
    "Top button, one wire   -> GPIO15  (J1 pin 8, internal pull-up)\n"
    "Top button, other wire -> GND     (J1 pin 22)\n"
    "One END of every pot   -> 3V3     (J1 pin 1)   NEVER 5V!\n"
    "Other END of every pot -> GND     (J1 pin 22)\n"
    "USB-C 'USB' port (native) -> PC: shows up as 'Falcon Pilot'"),
    title="Pin table", fs=7.6, mono=True)
note(ax, 146, 70, 72, (
    "Meter on resistance (20k range), joystick unplugged:\n"
    "1. Find the 3 wires of one pot: two of them (the ENDS) read a fixed\n"
    "   value (typ. 5k or 10k) that does NOT change when you move the stick.\n"
    "2. The 3rd wire is the WIPER: its reading to either end CHANGES as you\n"
    "   move one axis. The axis that changes it tells you X, Y or twist.\n"
    "3. Button: continuity mode; the 2 wires that beep ONLY while the top\n"
    "   button is pressed. Either way round is fine.\n"
    "4. Fewer wires than 11? Pots share a common END wire: it reads the\n"
    "   fixed value to the other ends of 2-3 pots. Wire it to GND or 3V3.\n"
    "5. Which end goes to 3V3 vs GND doesn't matter. If an axis is backwards,\n"
    "   swap its two END wires (or set invert=true in config_pilot.h).\n"
    "6. ~0 ohm / open only (no in-between)? It is a switch joystick, not\n"
    "   pots: wire each direction as a button to GND instead."),
    title="Identify the unlabeled wires with a multimeter", fs=8)
note(ax, 146, 25.5, 72, (
    "Flash env 'falcon_joystick_test' (or falcon_pilot: it auto-detects\n"
    "the missing 74HC165s). Calibrate: hold the top button while plugging\n"
    "in -> LED blue: move all axes to the ends, press -> yellow: let go,\n"
    "press -> green = saved."), title="Then", fs=8, fc="#eef7ee")
ax.text(4, 6, "Wire colours are ROLES (red 3V3, black GND, yellow/green/blue wipers, brown button), "
        "not the colours of your joystick's wires.", fontsize=8, style="italic")
save(fig, "01_simple_joystick")
