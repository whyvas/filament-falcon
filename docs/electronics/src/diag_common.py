"""Shared helpers for the Filament Falcon wiring diagrams (matplotlib)."""
import pathlib
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle, Arc, Circle, Polygon

OUT = pathlib.Path(__file__).resolve().parents[1]
plt.rcParams.update({"font.family": "DejaVu Sans", "svg.fonttype": "none"})

# Wire colour ROLES used in every diagram (your joystick's own wire colours are unknown)
C = {
    "3v3": "#d62728", "gnd": "#222222", "5v": "#ff7f0e", "12v": "#c2185b",
    "x": "#e6b800", "y": "#2ca02c", "z": "#1f77b4", "lever": "#9467bd",
    "btn": "#8c564b", "data": "#17becf", "clk": "#e377c2", "load": "#7f7f7f",
}

# ESP32-S3-DevKitC-1 headers, top (antenna end) to bottom (USB end)
J1 = ["3V3", "3V3", "RST", "4", "5", "6", "7", "15", "16", "17", "18", "8", "3", "46",
      "9", "10", "11", "12", "13", "14", "5V", "GND"]
J3 = ["GND", "43", "44", "1", "2", "42", "41", "40", "39", "38", "37", "36", "35", "0",
      "45", "48", "47", "21", "20", "19", "GND", "GND"]


def new(w, h, title=None):
    fig, ax = plt.subplots(figsize=(w, h))
    ax.set_xlim(0, w * 10)
    ax.set_ylim(0, h * 10)
    ax.set_aspect("equal")
    ax.axis("off")
    if title:
        ax.text(w * 5, h * 10 - 3, title, ha="center", va="top", fontsize=17, weight="bold")
    return fig, ax


def save(fig, name):
    for ext in ("png", "svg"):
        fig.savefig(OUT / f"{name}.{ext}", dpi=150 if ext == "png" else None, bbox_inches="tight",
                    facecolor="white")
    plt.close(fig)
    print("wrote", OUT / f"{name}.png")


def devkit(ax, x, y, pitch=2.54 * 1.2, used=None, label="ESP32-S3-DevKitC-1"):
    """Draw the DevKitC-1 top view. Returns dict pin-name -> (x, y) for J1 (left)
    and J3 (right) pads. used = {pin_label: colour} highlights pins."""
    used = used or {}
    n = len(J1)
    h = (n + 3) * pitch
    w = 9 * pitch
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.5", fc="#1b4f8a", ec="black", lw=1.5))
    ax.add_patch(Rectangle((x + w * 0.25, y + h - 2.6 * pitch), w * 0.5, 2.2 * pitch, fc="#c9c9c9", ec="k"))
    ax.text(x + w / 2, y + h - 1.5 * pitch, "ESP32-S3\nmodule", ha="center", va="center", fontsize=7)
    ax.text(x + w / 2, y + h * 0.45, label, ha="center", va="center", rotation=90, color="white",
            fontsize=10, weight="bold")
    # USB ports at the bottom
    ax.add_patch(Rectangle((x + 0.8 * pitch, y - 0.9 * pitch), 2.4 * pitch, 1.4 * pitch, fc="#bbb", ec="k"))
    ax.add_patch(Rectangle((x + w - 3.2 * pitch, y - 0.9 * pitch), 2.4 * pitch, 1.4 * pitch, fc="#bbb", ec="k"))
    ax.text(x + 2 * pitch, y - 1.6 * pitch, "USB\n(native)\n-> PC", ha="center", va="top", fontsize=7, weight="bold")
    ax.text(x + w - 2 * pitch, y - 1.6 * pitch, "UART\n(flash/\ndebug)", ha="center", va="top", fontsize=7)
    pads = {}
    for i, (a, b) in enumerate(zip(J1, J3)):
        py = y + h - (i + 2.6) * pitch
        for side, name, px in (("L", a, x + 0.9 * pitch), ("R", b, x + w - 0.9 * pitch)):
            col = used.get(f"{side}:{name}") or used.get(name if side == "L" else None)
            ax.add_patch(Circle((px, py), 0.45 * pitch, fc=col or "#e8c66a", ec="k", lw=0.6))
            lab = name if not name.isdigit() else f"G{name}"
            ax.text(px + (1.0 if side == "L" else -1.0) * pitch, py, lab, ha="left" if side == "L" else "right",
                    va="center", fontsize=6.5, color="white", weight="bold" if col else "normal")
            pads.setdefault(f"{side}:{name}", (px, py))
    return pads


def wire(ax, pts, color, lw=2.6, hops=(), label=None):
    """Orthogonal polyline. hops = x positions where a horizontal segment hops
    over a vertical wire (little arc)."""
    r = 0.9
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        if y1 == y2 and hops:
            xs = sorted([h for h in hops if min(x1, x2) + r < h < max(x1, x2) - r], reverse=x1 > x2)
            cur = x1
            for hx in xs:
                s = 1 if x2 > x1 else -1
                ax.plot([cur, hx - s * r], [y1, y1], color=color, lw=lw, solid_capstyle="round")
                ax.add_patch(Arc((hx, y1), 2 * r, 2 * r, theta1=0, theta2=180, color=color, lw=lw))
                cur = hx + s * r
            ax.plot([cur, x2], [y1, y2], color=color, lw=lw, solid_capstyle="round")
        else:
            ax.plot([x1, x2], [y1, y2], color=color, lw=lw, solid_capstyle="round")
    if label:
        ax.text(*label[0], label[1], fontsize=7.5, color=color, ha="center", va="bottom", weight="bold")


def dot(ax, x, y, color="k"):
    ax.add_patch(Circle((x, y), 0.55, fc=color, ec=color, zorder=5))


def pot(ax, x, y, color_w, name, length=6):
    """Vertical potentiometer centred at (x, y). Returns (top, bottom, wiper) points;
    wiper exits to the right."""
    import numpy as np
    top, bot = (x, y + length / 2), (x, y - length / 2)
    zz = np.linspace(-length / 4, length / 4, 9)
    xs = [x] + [x + (1.0 if i % 2 else -1.0) for i in range(1, 8)] + [x]
    ax.plot([x, x], [y + length / 4, y + length / 2], color="k", lw=1.5)
    ax.plot([x, x], [y - length / 4, y - length / 2], color="k", lw=1.5)
    ax.plot(xs, zz[::-1] + y, color="k", lw=1.5)
    ax.annotate("", xy=(x + 1.2, y), xytext=(x + 3.2, y), arrowprops=dict(arrowstyle="-|>", color="k", lw=1.3))
    ax.text(x - 1.8, y, name, ha="right", va="center", fontsize=8)
    return top, bot, (x + 3.2, y)


def note(ax, x, y, w, text, fs=8.5, title=None, fc="#fffbe6", mono=False):
    lines = text.count("\n") + 1 + (2 if title else 0)
    h = lines * fs * 0.205 + 2
    ax.add_patch(FancyBboxPatch((x, y - h), w, h, boxstyle="round,pad=0.6", fc=fc, ec="#999"))
    ty = y - 1
    if title:
        ax.text(x + 1, ty, title, va="top", fontsize=fs + 1.5, weight="bold")
        ty -= fs * 0.42
    ax.text(x + 1, ty, text, va="top", fontsize=fs, family="DejaVu Sans Mono" if mono else "DejaVu Sans", linespacing=1.25)
    return h


# ---------------------------------------------------------------- symbols
import numpy as _np
from matplotlib.patches import Polygon as _Poly


def line(ax, pts, color="k", lw=2.0, ls="-"):
    xs, ys = zip(*pts)
    ax.plot(xs, ys, color=color, lw=lw, ls=ls, solid_capstyle="round")


def resistor(ax, x1, y1, x2, y2, label="", color="k", lw=1.6, side=1):
    """Zig-zag between two points (horizontal or vertical), body 4 units."""
    L = _np.hypot(x2 - x1, y2 - y1)
    ux, uy = (x2 - x1) / L, (y2 - y1) / L
    px, py = -uy, ux
    body = 4.0
    a = (L - body) / 2
    pts = [(x1, y1), (x1 + ux * a, y1 + uy * a)]
    for i in range(1, 8):
        t = a + body * i / 8
        o = 0.9 * (1 if i % 2 else -1)
        pts.append((x1 + ux * t + px * o, y1 + uy * t + py * o))
    pts += [(x1 + ux * (a + body), y1 + uy * (a + body)), (x2, y2)]
    line(ax, pts, color, lw)
    if label:
        mx, my = (x1 + x2) / 2 + px * 2.0 * side, (y1 + y2) / 2 + py * 2.0 * side
        ax.text(mx, my, label, ha="center", va="center", fontsize=8)


def fuse(ax, x1, y1, x2, y2, label="", color="k"):
    L = _np.hypot(x2 - x1, y2 - y1)
    ux, uy = (x2 - x1) / L, (y2 - y1) / L
    a = (L - 4) / 2
    p1 = (x1 + ux * a, y1 + uy * a)
    p2 = (x1 + ux * (a + 4), y1 + uy * (a + 4))
    line(ax, [(x1, y1), p1], color)
    line(ax, [p2, (x2, y2)], color)
    cxm, cym = (x1 + x2) / 2, (y1 + y2) / 2
    w, h = (4, 1.6) if uy == 0 else (1.6, 4)
    ax.add_patch(Rectangle((cxm - w / 2, cym - h / 2), w, h, fc="white", ec=color, lw=1.6))
    line(ax, [p1, p2], color, lw=1.0)
    if label:
        ax.text(cxm + (0 if uy == 0 else 2.3), cym + (2.2 if uy == 0 else 0), label,
                ha="center" if uy == 0 else "left", va="center", fontsize=8)


def cap(ax, x, y1, y2, label="", polar=False, color="k"):
    """Vertical capacitor from (x,y1) top to (x,y2) bottom."""
    m = (y1 + y2) / 2
    line(ax, [(x, y1), (x, m + 0.5)], color)
    line(ax, [(x, y2), (x, m - 0.5)], color)
    line(ax, [(x - 1.6, m + 0.5), (x + 1.6, m + 0.5)], color, 2.2)
    if polar:
        ax.add_patch(Arc((x, m - 1.6), 4.2, 2.2, theta1=40, theta2=140, color=color, lw=2.2))
        ax.text(x - 2.2, m + 1.4, "+", fontsize=9)
    else:
        line(ax, [(x - 1.6, m - 0.5), (x + 1.6, m - 0.5)], color, 2.2)
    if label:
        ax.text(x + 2.2, m, label, va="center", fontsize=8)


def diode(ax, x1, y1, x2, y2, label="", color="k", side=1):
    """Diode, current flows from (x1,y1) [anode] to (x2,y2) [cathode]."""
    L = _np.hypot(x2 - x1, y2 - y1)
    ux, uy = (x2 - x1) / L, (y2 - y1) / L
    px, py = -uy, ux
    cxm, cym = (x1 + x2) / 2, (y1 + y2) / 2
    a = (cxm - ux * 0.9, cym - uy * 0.9)
    k = (cxm + ux * 0.9, cym + uy * 0.9)
    line(ax, [(x1, y1), a], color)
    line(ax, [k, (x2, y2)], color)
    tri = [(a[0] + px * 1.0, a[1] + py * 1.0), (a[0] - px * 1.0, a[1] - py * 1.0), k]
    ax.add_patch(_Poly(tri, closed=True, fc=color, ec=color))
    line(ax, [(k[0] + px * 1.0, k[1] + py * 1.0), (k[0] - px * 1.0, k[1] - py * 1.0)], color, 2.2)
    if label:
        ax.text(cxm + px * 2.2 * side, cym + py * 2.2 * side, label, ha="center", va="center", fontsize=7.5)


def ground(ax, x, y, color="k"):
    line(ax, [(x, y), (x, y - 1)], color)
    for i, w in enumerate((1.6, 1.0, 0.4)):
        line(ax, [(x - w, y - 1 - i * 0.5), (x + w, y - 1 - i * 0.5)], color, 1.6)


def switch_no(ax, x1, y, x2, label="", color="k", closed=False, nc=False):
    """Horizontal SPST between (x1,y) and (x2,y). nc=True draws a normally-closed contact."""
    a, b = x1 + (x2 - x1) * 0.3, x1 + (x2 - x1) * 0.7
    line(ax, [(x1, y), (a, y)], color)
    line(ax, [(b, y), (x2, y)], color)
    ax.add_patch(Circle((a, y), 0.35, fc="white", ec=color, zorder=4))
    ax.add_patch(Circle((b, y), 0.35, fc="white", ec=color, zorder=4))
    if nc:
        line(ax, [(a, y), (b + 0.3, y - 0.9)], color)
        line(ax, [(b, y), (b, y - 1.0)], color, 1.4)
    else:
        line(ax, [(a, y), (b, y + (0 if closed else 1.6))], color)
    if label:
        ax.text((x1 + x2) / 2, y + 2.6, label, ha="center", va="bottom", fontsize=8)


def box(ax, x, y, w, h, text, fc="#eef3fb", fs=8.5, weight="bold"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.4", fc=fc, ec="k", lw=1.2))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, weight=weight)
