# Displays, mounts and video cabling

Owner's real displays (dimensions from the makers' spec pages, monitor bodies
**without stand**; measure yours before printing, kits vary by +-1 mm):

| | Sceptre C275B-144R | Sceptre C275W-1920RN | ViewSonic TD2220 |
|---|---|---|---|
| Use | PILOT window (left kid), in the pod | OPS window (right kid), in the pod | centre console touchscreen, in the cradle |
| Panel | 27" 1920 x 1080, up to 144 Hz | 27" 1920 x 1080, 75 Hz | 21.5" 1920 x 1080, 60 Hz, optical 2-point touch (USB-B) |
| Size W x H x D (no stand) | 618 x 363.5 x 62.5 mm | 616.5 x 366.5 x 65 mm | 511.5 x 310.4 x 66.5 mm |
| Mass (no stand) | 3.80 kg | 3.40 kg | 4.0 kg |
| Curve | 1800R | 1800R | flat |
| VESA | 100 x 100, M4 | **75 x 75**, M4 | 100 x 100, M4 |
| Video inputs | HDMI, DisplayPort, DVI | **HDMI + VGA only** | **VGA + DVI-D only** (no HDMI/DP) |
| Active area | ~598 x 336 | ~598 x 336 | ~476 x 268 |

All three have VESA holes, so **no printed cradle is needed**. (If a VESA insert is
ever stripped, `monitor_mount.scad` can grow a lip cradle, but a steel VESA plate
is the better fix.)

## Monitor mounts (pod)

`cad/parts/monitor_mount.scad` -> `monitor_standoff_C275B_vesa100.3mf` and
`monitor_standoff_C275W_vesa75.3mf`: one printed hat-channel standoff per monitor,
bolted through the pod's 12 mm back sheet with 4 x M6 carriage bolts. The plate has
both VESA 75 and VESA 100 hole patterns; only the height differs (64.0 / 61.4 mm)
so both screen centres sit exactly 600 mm from the pod pivot (~540 mm from the
12 yr's eyes in flight). Screws: M4 x 20 (C275B), M4 x 16 (C275W) - check the
insert depth first, do not bottom out.

**The pod parks the monitors face-down above the kids** (pod UP = 95 deg), so each
monitor gets a 2 mm steel safety cable from a VESA screw to an eye screw in the
back sheet (<= 50 mm slack). PETG/ASA, 6 perimeters, 50 % gyroid. A steel VESA plate
on 64 mm spacers is an equal substitute.

## TD2220 centre console

The TD2220 lies (near) flat in the cradle's centre console between the kids
(console x = +-280 mm, seat centres +-460 mm), on a printed VESA 100 riser
(`td2220_vesa100_riser.3mf`, 190 x 140 x 40 mm, `TILT` parameter, default 0)
screwed to a plywood shelf inside the console. Because the console reclines with
the cradle, "flat" in the cradle ends up tilted 35 deg toward the reclined kids in
flight - the screen faces them (screen normal ~55 deg from horizontal).

The **trim ring** (outer 558.5 x 357.4 mm) closes the gap between the screen edge
and the plywood cut-out and **never overlaps the screen**: the TD2220's optical
touch sensors look across the glass from the bezel, so anything raised over the
bezel would block touches. The ring top sits 1 mm below the glass. Six pieces,
all <= 220 mm: 4 corners `td2220_trim_corner_*` (200 x 179 / 195 mm) and 2 straight
middles `td2220_trim_middle_*` (190.5 mm incl. laps), half-lapped, one countersunk
M4 wood screw through every lap. Ports are on the rear edge (toward dad).

Fit between the kids' seats: trim 558.5 mm wide in a console 560 mm wide; seat
boxes are 340 mm wide at +-460 -> 290 mm inner edges -> 10 mm side clearance
between console and seat boxes. Kids' hands reach it reclined (it rides with them).

## GPU outputs and cabling (RX 6800 XT)

The reference RX 6800 XT has **2 x DisplayPort 1.4, 1 x HDMI 2.1, 1 x USB-C (DP alt
mode)** and drives at most **4 displays at once**.

| GPU port | Cable | Display | Mode |
|---|---|---|---|
| DP 1 | DP 1.4 cable, 3-5 m | C275B-144R (PILOT) DP in | 1920 x 1080 @ 144 Hz |
| HDMI 2.1 | HDMI cable, 3-5 m | C275W-1920RN (OPS) HDMI in (its only digital input) | 1920 x 1080 @ 75 Hz |
| DP 2 | **DP -> DVI-D single-link** adapter or cable (passive is fine: DP++) | TD2220 DVI-D in | 1920 x 1080 @ 60 Hz |
| USB-A (PC) | USB-A -> USB-B, <= 5 m (or active extension) | TD2220 touch | HID touch |
| USB-C | USB-C -> DP/HDMI | 4th display: the COMMANDER monitor (31.5" 1080p at dad's seat) | 1920 x 1080 @ 60 Hz |

All four heads are now in use. The actual cabling may differ from this plan. The game
assigns screen roles by xrandr output name and physical size, not by port. On the owner's
rig (v0.3) the outputs are DisplayPort-2 = left window, DisplayPort-1 = right window,
DisplayPort-0 = TD2220 and HDMI-A-0 = 31.5" Commander (see `docs/game/README.md`,
"The four screens").

Alternative for the TD2220: USB-C -> DVI-D adapter, keeping DP 2 free. Avoid VGA
(analog, soft picture). Mixed refresh rates (144/75/60) are fine with Godot's four
windows: the game caps at 75 fps and uses MAILBOX vsync on every window.

Routing: the two monitor cables + power cross the **pod pivot**, the TD2220 DVI +
USB + power cross the **cradle pivot**. Each bundle gets 2 printed
`pivot_cable_clamp`s (one on the fixed side, one on the moving side, <= 60 mm from
the axis) and a 200 mm U service loop in braided sleeve. Use cables with molded
strain relief and screw-lock (DVI) or latching (DP) connectors.

## To confirm by Yves

- Which monitor is PILOT (left) vs OPS (right). The renders assume C275B (144 Hz, DP) left, C275W right.
- Actual VESA depth/screw length on both Sceptres; C275W is VESA **75**.
- TD2220 adapter choice (DP -> DVI-D passive or USB-C -> DVI-D) and cable lengths from the PC location.
