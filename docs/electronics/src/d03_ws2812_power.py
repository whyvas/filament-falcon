"""Diagram 03: WS2812B strip power, injection, level shifting."""
import json, pathlib
from diag_common import *

seg = json.loads((pathlib.Path(__file__).resolve().parents[3] / "shared" / "led_segments.json").read_text())
N = seg["strip"]["total_leds"]
worst = N * 0.060
fig, ax = new(22, 13, "03  WS2812B strip: 5 V power, injection, 3.3 V -> 5 V data, common ground")
V5, G = 100, 52     # +5V rail y, GND rail y
O, K, D = C["5v"], C["gnd"], C["data"]

# PSU
box(ax, 4, 66, 22, 24, "5 V  10 A PSU\n(50 W, e.g.\nMean Well LRS-50-5)\n\n+V        -V", fc="#fff3e0")
line(ax, [(10, 90.4), (10, V5)], O, 3)
fuse(ax, 10, V5, 26, V5, "fuse 10 A", O)
line(ax, [(26, V5), (212, V5)], O, 3)
ax.text(120, V5 + 1.5, "+5 V trunk: 16 AWG (18 AWG drops to each injection point)", color=O, fontsize=8.5, ha="center")
line(ax, [(20, 65.6), (20, G)], K, 3)
wire(ax, [(20, G), (212, G)], K, lw=3, hops=[55])
ground(ax, 20, G)
ax.text(120, G - 3.5, "GND trunk: same gauge as +5 V", color=K, fontsize=8.5, ha="center")

# Strip
sx0, sx1, sy0, sy1 = 58, 212, 70, 82
ax.add_patch(Rectangle((sx0, sy0), sx1 - sx0, sy1 - sy0, fc="#fafafa", ec="k", lw=1.2))
for i in range(40):
    x = sx0 + 3 + i * (sx1 - sx0 - 6) / 39
    ax.add_patch(Rectangle((x - 0.9, sy0 + 3.6), 1.8, 1.8, fc="#fff", ec="#999", lw=0.6))
ax.text((sx0 + sx1) / 2, sy1 - 2.5, f"ONE continuous WS2812B strip, {N} LEDs (60 LED/m), snakes behind every lettered label",
        ha="center", fontsize=9, weight="bold")
ax.text(sx0 + 2, sy0 + 1.2, "LED 0", fontsize=7)
ax.text((sx0 + sx1) / 2, sy0 + 1.2, f"LED ~{N//2}", fontsize=7, ha="center")
ax.text(sx1 - 2, sy0 + 1.2, f"LED {N-1}", fontsize=7, ha="right")
for x, lab in ((sx0 + 6, "5V/GND in\n(start)"), ((sx0 + sx1) / 2 + 6, "inject\n(middle)"), (sx1 - 14, "inject\n(end)")):
    line(ax, [(x, V5), (x, sy1)], O, 2.2)
    dot(ax, x, V5, O)
    line(ax, [(x + 2.5, G), (x + 2.5, sy0)], K, 2.2)
    dot(ax, x + 2.5, G, K)
    ax.text(x + 3.5, 90, lab, fontsize=7.5, va="center")
# bulk cap
cap(ax, 48, V5, G, "1000 µF\n10 V\n(at strip\ninput)", polar=True)
dot(ax, 48, V5, O)
dot(ax, 48, G, K)

# Data path
box(ax, 4, 18, 24, 22, "FALCON COMMAND\nESP32-S3-DevKitC-1\n\npowered by USB\nfrom the PC", fc="#e8f0fe")
ax.text(28.6, 34, "GPIO21", fontsize=7.5, ha="left", va="bottom")
ax.text(28.6, 22, "GND", fontsize=7.5, ha="left", va="bottom")
line(ax, [(28.4, 33.5), (36, 33.5)], D, 2.4)
tri = [(36, 37.5), (36, 29.5), (43, 33.5)]
ax.add_patch(Polygon(tri, closed=True, fc="white", ec="k", lw=1.6))
ax.text(42, 41, "74AHCT125 (1 of 4)\nVCC = +5 V, 1OE = GND\n100 nF VCC-GND", ha="center", fontsize=7.5)
line(ax, [(39.5, 39.5), (39.5, 36)], O, 1.4)
ax.text(40.3, 38.5, "5V", fontsize=6.5, color=O)
line(ax, [(43, 33.5), (44, 33.5)], D, 2.4)
resistor(ax, 44, 33.5, 53, 33.5, "330 Ω\n(at DIN)", D, side=-1)
line(ax, [(53, 33.5), (55, 33.5), (55, 76), (sx0, 76)], D, 2.4)
ax.text(sx0 + 0.5, 76.8, "DIN", fontsize=8, weight="bold", color=D)
line(ax, [(28.4, 21.5), (31, 21.5), (31, G)], K, 2.4)
dot(ax, 31, G, K)
ax.text(30.4, 46, "common GND\n(mandatory)", fontsize=7.5, ha="right")

note(ax, 76, 42, 136, (
    f"Sizing: {N} LEDs x 60 mA (full white) = {worst:.1f} A worst case. The firmware estimates current every frame and caps it at\n"
    "8 A (FF_LED_MAX_MILLIAMPS in config_command.h); lettered labels are rarely full white, so a 5 V 10 A (50 W) PSU is plenty.\n"
    "Power injection: feed +5 V and GND at the start, the middle and the end (about every 100 LEDs, or wherever the strip hops\n"
    "between panels). Never push the whole strip current through the thin strip copper, the ESP32, or its USB cable.\n"
    "The ESP32 is powered from the PC's USB. Do NOT also connect the PSU +5 V to its 5V pin. GND MUST be shared.\n"
    "74AHCT125 (or SN74AHCT1G125 / 74HCT245) shifts 3.3 V data to 5 V; tie the 3 unused inputs to GND.\n"
    "330 Ω in series right at DIN stops ringing; 1000 µF across +5 V/GND at the strip input absorbs the power-up surge.\n"
    "The 5 mm status LEDs (WS2812D-F5, ids *_LED) are spliced into the same DIN->DOUT chain at each panel, 100 nF at each.\n"
    "If the strip ever grows past ~300 LEDs, add a second PSU per section (join GNDs, do not join the +5 V outputs)."),
    title="Notes", fs=8)
save(fig, "03_ws2812_power")
