"""Diagram 02: full per-board wiring (74HC165 chain, joystick, encoders) generated
from the firmware config headers."""
from diag_common import *
from matplotlib.patches import Rectangle, FancyBboxPatch
import boards

HC165_LEFT = ["A (11)", "B (12)", "C (13)", "D (14)", "E (3)", "F (4)", "G (5)", "H (6)"]
HC165_RIGHT = [("SH/LD (1)", "load"), ("CLK (2)", "clk"), ("CLK INH (15)", "gnd"),
               ("QH (9)", "qh"), ("SER (10)", "ser"), ("VCC (16)", "3v3"), ("GND (8)", "gnd")]


class Router:
    """Keeps track of vertical wires so horizontal wires hop over them automatically."""
    def __init__(self, ax):
        self.ax, self.v = ax, []

    def run(self, pts, col, lw=1.8):
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            if x1 == x2:
                self.v.append((x1, min(y1, y2), max(y1, y2)))
        segs = []
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            hops = []
            if y1 == y2:
                hops = [x for x, lo, hi in self.v if lo + 0.3 < y1 < hi - 0.3 and min(x1, x2) < x < max(x1, x2)]
            wire(self.ax, [(x1, y1), (x2, y2)], col, lw=lw, hops=hops)


def draw(key):
    B = boards.board(boards.BOARDS[key])
    n = B["chips"]
    chip_h, gap = 27, 9
    H = max(130, n * (chip_h + gap) + 40)
    fig, ax = new(23, H / 10, f"02  {B['name']}: full wiring ({n} x 74HC165, generated from config_{key}.h)")
    # ---- ESP32 board
    P = B["pins"]
    used = {f"L:{P['PIN_SR_LOAD']}": C["load"], f"L:{P['PIN_SR_CLK']}": C["clk"],
            f"L:{P['PIN_SR_DATA']}": C["data"], "L:3V3": C["3v3"], "L:GND": C["gnd"]}
    ann = {}
    axcol = [C["x"], C["y"], C["z"], C["lever"]]
    for i, (pin, slot, mode, act) in enumerate(B["axes"]):
        used[f"L:{pin}"] = axcol[i % 4]
        ann[f"L:{pin}"] = (f"{act.upper()} pot wiper", axcol[i % 4])
    for pin, (act, hid, kind) in B["gpio"].items():
        side = "L" if str(pin) in J1 else "R"
        used[f"{side}:{pin}"] = C["btn"]
        extra = " (opto, see 04)" if act == "seat_up" else " to GND"
        ann[f"{side}:{pin}"] = (f"{act.upper()}{extra}  [btn {hid}]", C["btn"])
    for ei, (pa, pb, slot, knob) in enumerate(B["enc"]):
        names = knob + " knob -> axis" if slot != "AX_NONE" else ", ".join(f"{a}" for s, a, h in B["enc_btn"].get(ei, []))
        used[f"L:{pa}"] = used[f"L:{pb}"] = "#555"
        ann[f"L:{pa}"] = (f"ENC{ei} A  ({names})", "#444")
        ann[f"L:{pb}"] = (f"ENC{ei} B   C(mid pin) -> GND", "#444")
    if key == "command":
        used["R:21"] = C["data"]
        ann["R:21"] = ("WS2812B DATA -> 74AHCT125 -> 330R -> strip (see 03)", C["data"])
    bx, by = 140, H - 110
    pads = devkit(ax, bx, by, used=used)
    for k, (txt, col) in ann.items():
        x, y = pads[k]
        if k.startswith("L:"):
            ax.plot([x - 1.6, x - 6], [y, y], color=col, lw=2)
            ax.text(x - 6.5, y, txt, ha="right", va="center", fontsize=6.8, color=col, weight="bold")
        else:
            ax.plot([x + 1.6, x + 8], [y, y], color=col, lw=2)
            ax.text(x + 8.5, y, txt, ha="left", va="center", fontsize=6.8, color=col, weight="bold")

    # ---- 74HC165 chain
    cx, cw = 40, 22
    lane = {"load": 70, "clk": 74, "3v3": 78, "gnd": 82}
    chips = []
    top = H - 14
    for c in range(n):
        y0 = top - c * (chip_h + gap) - chip_h
        ax.add_patch(Rectangle((cx, y0), cw, chip_h, fc="#333", ec="k"))
        ax.text(cx + cw / 2, y0 + chip_h / 2, f"74HC165\n#{c+1}\n\nbits\n{c*8}-{c*8+7}", ha="center",
                va="center", color="white", fontsize=7.5, weight="bold")
        ax.text(cx + cw / 2, y0 + chip_h + 0.8, "100nF VCC-GND at each chip", ha="center", fontsize=5.5)
        rows = {}
        for i, lab in enumerate(HC165_LEFT):
            y = y0 + chip_h - 2.5 - i * 3.1
            bit = c * 8 + i
            act = B["sr"].get(bit)
            txt = f"bit {bit:2d}  " + (f"{act[0].upper()}  [btn {act[1]}]" if act else "spare")
            ax.plot([cx - 4, cx], [y, y], color=C["btn"] if act else "#aaa", lw=1.8)
            ax.text(cx + 0.6, y, lab.split()[0], color="white", fontsize=5.5, va="center")
            ax.text(cx - 4.5, y, txt, ha="right", va="center", fontsize=6.3,
                    color="k" if act else "#999", weight="bold" if act else "normal")
        for i, (lab, role) in enumerate(HC165_RIGHT):
            y = y0 + chip_h - 2.5 - i * 3.6
            rows[role if role not in rows else role + "2"] = y
            ax.text(cx + cw - 0.6, y, lab, color="white", fontsize=5.5, va="center", ha="right")
            ax.plot([cx + cw, cx + cw + 3], [y, y], color="#666", lw=1)
        chips.append(rows)
    R = Router(ax)
    # pre-register every vertical so all horizontals hop correctly
    allv = []
    # buses
    dx, lk = 66, 68
    q1 = chips[0]["qh"]
    pd = pads[f"L:{P['PIN_SR_DATA']}"]
    targets = {"load": pads[f"L:{P['PIN_SR_LOAD']}"], "clk": pads[f"L:{P['PIN_SR_CLK']}"],
               "3v3": pads["L:3V3"], "gnd": pads["L:GND"]}
    sl = chips[-1]["ser"]
    stubs = {}
    for role in ("load", "clk", "3v3", "gnd"):
        ys = [y for rows in chips for rk, y in rows.items() if rk.rstrip("2") == role]
        if role == "3v3":
            ys.append(sl)
        stubs[role] = ys
        R.v.append((lane[role], min(ys + [targets[role][1]]), max(ys + [targets[role][1]])))
    R.v.append((dx, q1, top + 4))
    R.v.append((88, pd[1], top + 4))
    for c in range(1, n):
        R.v.append((lk, chips[c]["qh"], chips[c - 1]["ser"]))
    for role in ("load", "clk", "3v3", "gnd"):
        col = C[role]
        for y in stubs[role]:
            R.run([(cx + cw + 3, y), (lane[role], y)], col)
            dot(ax, lane[role], y, col)
        t = targets[role]
        ys = stubs[role] + [t[1]]
        wire(ax, [(lane[role], min(ys)), (lane[role], max(ys))], col, lw=1.8)
        R.run([(lane[role], t[1]), t], col)
    R.run([(cx + cw + 3, q1), (dx, q1)], C["data"])
    wire(ax, [(dx, q1), (dx, top + 4), (88, top + 4), (88, pd[1])], C["data"], lw=1.8)
    R.run([(88, pd[1]), pd], C["data"])
    ax.text(89, top + 4.5, "QH #1 -> DATA (GPIO%d)" % P["PIN_SR_DATA"], fontsize=6.5, color=C["data"])
    for c in range(1, n):
        q, s_ = chips[c]["qh"], chips[c - 1]["ser"]
        R.run([(cx + cw + 3, q), (lk, q)], C["data"], lw=1.5)
        wire(ax, [(lk, q), (lk, s_)], C["data"], lw=1.5)
        R.run([(lk, s_), (cx + cw + 3, s_)], C["data"], lw=1.5)
    ax.text(cx + cw / 2, top - n * (chip_h + gap) + gap - 2,
            f"QH #k -> SER #(k-1);  SER of the last chip (#{n}) -> 3V3 = sentinel that lets the firmware detect the chain",
            fontsize=6, color=C["data"], ha="center", va="top")
    note(ax, 2, 30 if n > 3 else 24, 60, (
        "EVERY 74HC165 input A-H:\n"
        "  3V3 --[10k]--+-- input pin\n"
        "               |\n"
        "             switch --- GND   (pressed/ON = LOW)\n"
        "Use 9-pin 10k bussed resistor networks (one per chip).\n"
        "Encoder push switches and lever switches are inputs too.\n"
        "Spare inputs keep their 10k pull-up (never leave floating).\n"
        "Labels and 5 mm status LEDs are all on the WS2812B line (03)."), title="Inputs", fs=7, mono=True)
    note(ax, 182, H - 14, 41, (
        "LOAD = GPIO%d, CLK = GPIO%d, DATA = GPIO%d\n"
        "Chain to a remote panel (e.g. overhead)\n"
        "over CAT5: pair CLK & LOAD with GND,\n"
        "100R in series at the ESP32 end of CLK,\n"
        "100nF + 10uF at the far end.\n"
        "Joystick pots: ends to 3V3/GND, see 01.\n"
        "Encoders: EC11 A/B to the GPIOs, middle\n"
        "pin C to GND (internal pull-ups);\n"
        "optional 10nF A->GND, B->GND.\n"
        "Push switch of the encoder = a normal\n"
        "74HC165 input." % (P["PIN_SR_LOAD"], P["PIN_SR_CLK"], P["PIN_SR_DATA"])),
        title="Notes", fs=6.8)
    save(fig, f"02_{key}_wiring")


for k in boards.BOARDS:
    draw(k)
