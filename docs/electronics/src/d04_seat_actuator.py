"""Diagram 04: hardwired seat-lift actuator circuit (no microcontroller in the loop)
plus the optional isolated seat-up sense input to Falcon Command."""
from diag_common import *

fig, ax = new(22, 14, "04  Seat lift: hardwired hold-to-run actuator circuit (NO microcontroller control)")
P12, G = C["12v"], C["gnd"]
TOP, BOT = 112, 40

# Supply chain along the top
box(ax, 2, 60, 20, 22, "12 V DC PSU\n(>= 1.5 x total\nactuator current,\ne.g. 12 V 10 A)\n\n+           -", fc="#fde7ef")
line(ax, [(8, 82.4), (8, TOP), (14, TOP)], P12, 2.6)
switch_no(ax, 14, TOP, 28, "E-STOP\n(NC mushroom,\nrecommended)", P12, nc=True)
switch_no(ax, 28, TOP, 42, "KEY switch\nMASTER\n(at dad's seat)", P12)
fuse(ax, 42, TOP, 56, TOP, "", P12)
ax.text(49, TOP + 2.5, "FUSE\n(see notes)", ha="center", va="bottom", fontsize=8)
line(ax, [(56, TOP), (84, TOP)], P12, 2.6)
ax.text(70, TOP + 1.2, "+12 V switched", color=P12, fontsize=8, ha="center")
line(ax, [(16, 59.6), (16, BOT), (200, BOT)], G, 2.6)
ground(ax, 16, BOT)
ax.text(100, BOT - 3.5, "12 V GND (keep separate from the PC/ESP32 ground)", fontsize=8, ha="center")

# DPDT hold-to-run switch drawn as two SPDT poles, center-off, spring return
def spdt(xc, yc, label):
    xt = xc - 10
    up, dn = (xt, yc + 5), (xt, yc - 5)
    for p in (up, dn):
        ax.add_patch(Circle(p, 0.5, fc="white", ec="k", zorder=4))
    ax.add_patch(Circle((xc, yc), 0.5, fc="white", ec="k", zorder=4))
    line(ax, [(xc, yc), (xc - 6, yc + 1.2)], "k", 2)  # lever resting in the middle (OFF)
    ax.text(xt - 1, up[1] + 1.4, "UP", fontsize=7.5, ha="right")
    ax.text(xt - 1, dn[1] - 1.4, "DOWN", fontsize=7.5, ha="right", va="top")
    ax.text(xc + 1, yc + 1.5, label, fontsize=8, weight="bold")
    return up, dn, (xc, yc)

ua, da, ca = spdt(100, 92, "pole A")
ub, db, cb = spdt(100, 62, "pole B")
line(ax, [(96, 93), (96, 63)], "#666", 1.2, "--")
ax.text(48, 77, "DPDT momentary\n(ON)-OFF-(ON)\nHOLD-TO-RUN,\nrated >= motor\nstall current", fontsize=8,
        ha="center", va="center", bbox=dict(fc="#f4f4f4", ec="#aaa"))
# throws: A-UP +12, A-DOWN GND ; B-UP GND, B-DOWN +12
line(ax, [(84, TOP), (88, TOP), (88, ua[1]), ua], P12, 2.2)
line(ax, [(84, TOP), (84, db[1]), db], P12, 2.2)
dot(ax, 84, TOP, P12)
wire(ax, [da, (80.5, da[1])], G, lw=2.2, hops=[84])
line(ax, [(80.5, da[1]), (80.5, BOT)], G, 2.2)
dot(ax, 80.5, BOT, G)
wire(ax, [ub, (74, ub[1])], G, lw=2.2, hops=[84, 80.5])
line(ax, [(74, ub[1]), (74, BOT)], G, 2.2)
dot(ax, 74, BOT, G)
# crossings: A-DOWN line crosses the +12 drop at x=84 -> hop
ax.text(90, 99, "+12", color=P12, fontsize=7)
ax.text(79.5, BOT + 2, "GND", color=G, fontsize=7, ha="right")

# limit-switch chain on the M+ line
YM = 92
line(ax, [ca, (112, YM)], "k", 2.4)
def limit(x1, x2, label, diode_dir):
    switch_no(ax, x1, YM, x2, "", "k", nc=True)
    line(ax, [(x1, YM), (x1, YM - 7)], "k", 1.6)
    line(ax, [(x2, YM), (x2, YM - 7)], "k", 1.6)
    if diode_dir > 0:
        diode(ax, x1, YM - 7, x2, YM - 7, "", "k")
    else:
        diode(ax, x2, YM - 7, x1, YM - 7, "", "k")
    dot(ax, x1, YM); dot(ax, x2, YM)
    ax.text((x1 + x2) / 2, YM + 2.5, label, ha="center", fontsize=7.5, va="bottom")

limit(112, 126, "UP limit\n(NC, opens at top)", -1)
limit(130, 144, "DOWN limit\n(NC, opens at bottom)", +1)
line(ax, [(126, YM), (130, YM)], "k", 2.4)
ax.text(119, YM - 10.5, "D1", ha="center", fontsize=7.5)
ax.text(137, YM - 10.5, "D2", ha="center", fontsize=7.5)
ax.text(128, YM - 14.5, "D1, D2: 6A10 (6 A) or\n1N5400-series >= motor current", ha="center", fontsize=7)
line(ax, [(144, YM), (160, YM)], "k", 2.4)
# two actuators in parallel
for i, x in enumerate((160, 176)):
    line(ax, [(x, YM), (x, 81)], "k", 2.2)
    ax.add_patch(Circle((x, 77), 4, fc="white", ec="k", lw=2))
    ax.text(x, 77, "M", ha="center", va="center", fontsize=12, weight="bold")
    ax.text(x + 4.6, 77, f"actuator\n{i+1}", fontsize=7.5, va="center")
    line(ax, [(x, 73), (x, ub[1] - 5 + 0), (x, 57)], "k", 2.2)
    dot(ax, x, YM)
    dot(ax, x, 57)
line(ax, [(176, YM), (176, YM)], "k")
line(ax, [cb, (112, 62), (112, 57), (176, 57)], "k", 2.4)
ax.text(150, 59, "M- line", fontsize=7.5)
ax.text(150, YM + 1, "M+ line", fontsize=7.5)

# Seat-up sense via optocoupler
sx = 150
line(ax, [(84, TOP), (84, TOP + 0)], P12)
line(ax, [(56, TOP), (56, 122), (150, 122)], P12, 1.8)
dot(ax, 56, TOP, P12)
switch_no(ax, 150, 122, 162, "SEAT-UP sense microswitch (NO, closes at top;\nseparate contact, or 2nd pole of the UP limit)", P12)
resistor(ax, 162, 122, 174, 122, "2.2 kΩ ½ W", P12)
# opto box
ox, oy = 176, 104
ax.add_patch(Rectangle((ox, oy), 18, 22, fc="#fafafa", ec="k", lw=1.4))
ax.text(ox + 9, oy + 23, "PC817 optocoupler", ha="center", fontsize=8, weight="bold")
line(ax, [(174, 122), (ox + 4, 122), (ox + 4, 117)], P12, 1.8)
diode(ax, ox + 4, 117, ox + 4, 110, "", "k")
line(ax, [(ox + 4, 110), (ox + 4, 100), (200, 100), (200, BOT)], G, 1.8)
dot(ax, 200, BOT, G)
for k in range(2):
    ax.annotate("", xy=(ox + 10.5, 114 - k * 2.5), xytext=(ox + 6.5, 115.5 - k * 2.5),
                arrowprops=dict(arrowstyle="->", lw=1))
line(ax, [(ox + 12, 118), (ox + 12, 109)], "k", 2)
line(ax, [(ox + 12, 115.5), (ox + 15, 119), (ox + 15, 124), (ox + 18, 124)], "k", 1.4)
line(ax, [(ox + 12, 111.5), (ox + 15, 108), (ox + 15, 106), (ox + 18, 106)], "k", 1.4)
ax.text(ox + 18.5, 124, "C (pin 4) -> Falcon Command GPIO39\n   + 10 kΩ pull-up to 3V3\n   (button 15 'seat_up', LOW = up)",
        fontsize=7.5, va="center")
ax.text(ox + 18.5, 106, "E (pin 3) -> Falcon Command GND", fontsize=7.5, va="center")
ax.plot([ox + 9, ox + 9], [oy + 0.5, oy + 30], ls=":", color="#888", lw=1)
ax.text(ox + 9.5, oy + 0.8, "isolation\n12 V | 3.3 V", fontsize=6.5, color="#666")

note(ax, 2, 32, 216, (
    "How it works: hold the switch UP -> pole A feeds +12 V into the M+ line, pole B grounds the M- line -> seats rise. At the top the UP limit "
    "opens; D1 blocks the UP current\n"
    "so the motors stop, but D1 still conducts the opposite (DOWN) current, so you can always drive back down. The DOWN limit + D2 work the "
    "same way at the bottom. Let go -> the switch\n"
    "springs to OFF and both motor leads float -> seats stop instantly. The key switch and E-stop kill everything. Nothing here is controlled by "
    "software; the game can only READ the sense input.\n"
    "Fuse: ~1.25 x the sum of both actuators' rated running current and below the wire's rating (e.g. 2 x 3 A -> 7.5 A blade fuse, 16 AWG). If "
    "the key switch is rated for less\n"
    "than that current, let it switch the coil of a 12 V 30 A automotive relay instead. Mount the hold-to-run switch where only dad's seat can reach it "
    "and the kids' seats are in view.\n"
    "Prefer actuators with BUILT-IN limit switches; these external limits then set the real travel inside that range. If the two actuators are not "
    "tied to one rigid frame, give each\n"
    "actuator its own UP/DOWN limit pair + diodes. Diodes must carry the full motor current. Add pinch-point guards; seat up only after harnesses are fastened."),
    title="Notes", fs=7.6)
save(fig, "04_seat_actuator")
