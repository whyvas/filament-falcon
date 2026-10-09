# The Filament Falcon - mechanical (printed parts + panels)

Everything a person touches is printed and bolts to the wooden frame (`frame/`).
OpenSCAD sources live in `cad/`, ready-to-slice 3MF files in `cad/export/3mf/`,
renders in `cad/export/png/`. Units: mm (inches in brackets where useful).

![overview](../../cad/export/png/overview_raised.png)

## Folder map

| Path | What |
|---|---|
| `cad/lib/ff_lib.scad` | the parametric library: 40 mm grid, M5 holes, standard cut-outs, light boxes, seams, missile-switch guard |
| `cad/lib/ff_panel.scad` | panel builder (body, letters, inserts, previews) |
| `cad/tools/layouts.py` | **single source of truth** for every lettered panel (controls, labels, LED strip order) |
| `cad/tools/gen_panels.py` | layouts -> `cad/panels/*.scad` + `shared/panel_labels.json` + layout checks |
| `cad/tools/build.py` | exports every 3MF, validates it, renders every PNG + the assembled overview |
| `cad/tools/switch_bom.py` | writes `docs/mechanical/switch_bom.md` (bill of switches per panel) |
| `cad/parts/*.scad` | non-panel parts (throttle, gear lever, joystick housing, bezel, monitor mount, enclosures, clips, guards) |
| `cad/assembly/overview.scad` | whole cockpit (frame from `frame/generated/frame.scad` + all parts) |
| `cad/fonts/` | Barlow Condensed Black (SIL OFL) used for all lettering |
| `cad/export/validation_report.json` | per-file checks (watertight, volume, footprint, triangle counts, lib3mf read-back) |

Rebuild everything (OpenSCAD 2025+ with the Manifold backend recommended):

```
python cad/tools/gen_panels.py            # after editing layouts.py
python cad/tools/switch_bom.py
python frame/frame_model.py               # frame -> frame/generated/frame.scad
python cad/tools/build.py --openscad /path/to/openscad   # 3MF + PNG + checks
```

Python needs: trimesh, numpy, networkx, manifold3d, lib3mf, fonttools, shapely, matplotlib.

## Panels

All panels are 3 mm thick, dark body, white letters that go through the full
thickness. Panels are multiples of the 40 mm grid and printed 0.5 mm smaller
than nominal so neighbours never bind. The top and bottom 20 mm bands carry the
M5 holes (10 mm from the edge, every 40 mm) and sit flat on the plywood rails;
all light boxes, ribs and switch bodies are inside the 120 mm (or 80 / 160 mm)
bay opening.

| Panel | Size | Labels | Where |
|---|---|---|---|
| `PILOT_DASH_A` | 200 x 160 | 7 | Pilot dash, outboard half (left seat) |
| `PILOT_DASH_B` | 200 x 160 | 8 | Pilot dash, inboard half (joins A with 2 alignment pins) |
| `PILOT_SIDE` | 200 x 160 | 6 | Pilot outboard side console: THROTTLE + LANDING GEAR slots |
| `OPS_DASH_A` | 200 x 160 | 6 | Ops dash, inboard half: power toggles |
| `OPS_DASH_B` | 200 x 160 | 8 | Ops dash, outboard half: mode rotary + payload |
| `OPS_SIDE` | 200 x 160 | 4 | Ops inboard side console: JUMP ARM (guarded) + ENGAGE (collar) |
| `OVERHEAD_A/B/C` | 3 x 200 x 120 | 3/3/4 | overhead console, launch checklist row + lights + EJECT |
| `CMD_A` | 200 x 200 | 8 | commander: master power key, mission, start/pause, caution reset, PA, dimmer |
| `CMD_B` | 200 x 200 | 10 | commander: failure injection + **SEAT LIFT** (key, hold-to-run, E-stop) |

67 backlit labels in total; every one is listed (id, panel, text, position, strip
order) in `shared/panel_labels.json`. The bill of switches/buttons/LEDs per panel
is in [`switch_bom.md`](switch_bom.md).

Files per panel (in `cad/export/3mf/panels/`):

- `<ID>_multimaterial.3mf` - body (extruder 1, black) + letters (extruder 2, white) as two parts of one object. Opens with the colours/extruders already assigned in PrusaSlicer, OrcaSlicer and Bambu Studio. In other slicers: import, then assign the "letters" part to the white filament.
- `<ID>_single_body.3mf` - single-material fallback: the body with through-pockets where the letters go. Letters with closed counters (A, B, D, O, P, R, 0, 4, 6, 8, 9) use small 1.2 mm stencil bridges so the islands stay attached.
- `<ID>_single_letter_inserts_WHITE.3mf` - the matching white letters on a 0.8 mm carrier plaque per label. Push the letters into the pockets from the back (0.12 mm clearance per side); the plaque stays behind the panel inside the light box and acts as a diffuser. A drop of thin CA if loose.
- PNG: `cad/export/png/panels/<ID>_front.png` and `<ID>_back.png`.

### Back side: LED light boxes

Behind every label is a light box (1.6 mm walls, opaque) about 12.8 mm deep:
the 12 mm WS2812B strip (10 mm fits too) clicks in behind small ledges at 9 mm
from the panel face (stand-off for even light), with snap nubs to hold it. Each
box end wall has a notch for the strip or a 3-wire jumper. ONE strip snakes
through all panels in the order of `panel_order` in `shared/panel_labels.json`
(CMD_A -> CMD_B -> PILOT_SIDE -> OPS_SIDE -> OPS_DASH_A -> OPS_DASH_B -> OVERHEAD_C
-> OVERHEAD_B -> OVERHEAD_A -> PILOT_DASH_A -> PILOT_DASH_B); inside a panel, labels
are visited row by row in a snake. Between boxes and between panels, solder short
3-wire jumpers (strip cut on the copper pads). The perimeter rib has wire notches.
Real LED counts per label are measured later into `shared/led_segments.json`.

Light leak check: print black PETG/PLA at >= 3 walls; if light glows through the
body, paint the inside of the light boxes black or use a "blackout" filament.

### How a panel bolts to the frame

1. The bay in the 18 mm plywood is an opening (e.g. 400 x 120 mm for the dash) with rails above and below. See `frame/drawings/05_panel_bay_detail`.
2. Drill holes for the T-nut barrel (usually 7 mm; check yours) on the 40 mm grid, 10 mm from the opening edge, and press M5 four-prong T-nuts in from the BACK.
3. Fit the switches into the panel first (the switch nuts clamp on 3 mm), plug the LED strip into its boxes, then put the panel in the bay and bolt with M5 x 20 button-head screws + washers (M5 x 16 if the T-nut barrel is long).
4. Split panels (A + B) join with two 3 mm x 16 mm pins (`alignment_pins_x8.3mf`, or 3 mm steel dowels) in the seam bosses.
5. Prefer 1/4-20? Set `FF_M5_D = 6.9` in `ff_lib.scad` and rebuild.

## Other printed parts (`cad/export/3mf/parts/`)

| File | Qty | Colour | Notes |
|---|---|---|---|
| `toggle_guard_base.3mf` / `toggle_guard_lid_RED.3mf` | 3 each | black / red | missile-switch guard for ENG ARM, JUMP ARM, EJECT; hinge = 24 mm of 1.75 mm filament |
| `engage_button_collar.3mf` | 1 | black | collar around JUMP ENGAGE |
| `alignment_pins_x8.3mf` | 1 plate | black | seam pins (3 x 16 mm) |
| `throttle_housing.3mf`, `throttle_lever.3mf`, `throttle_grip.3mf` | 1 each | black / black / red | 10 k linear pot (16 mm, 6 mm D shaft), M6 x 30 pivot; housing screws into the side-console rails |
| `gear_lever_box.3mf`, `gear_lever_arm.3mf`, `gear_lever_wheel_knob.3mf` | 1 each | black / grey / white | 2 x KW11 micro switches, M4 x 40 pivot, hangs on 4 x M3 x 12 countersunk |
| `joystick_housing.3mf`, `joystick_adapter_plate.3mf` | 2 each | black / grey | 4 x M5 on the grid (120 mm); adapter has 8 radial slots r 22-44 mm + optional square pattern (`SQ_PITCH`) |
| `touchscreen_bezel_front_left/right`, `..._rear_left/right.3mf` | 1 each | black | 15.6" bezel in 4 half-lapped quadrants, countersunk M5 into the tray |
| `monitor_beam_bracket.3mf`, `monitor_vesa_plate.3mf` | 2 each | black | VESA 100 hanger, -20..+20 deg tilt, M8 pivot + M6 lock. **PETG/ASA, 6 walls, >= 60 % infill, plus a steel safety cable.** |
| `esp32_enclosure_base.3mf` | 3 | black | 70 x 90 perfboard carrier for an ESP32-S3-DevKitC-1, USB-C slot, M5 tabs 120 mm apart |
| `esp32_enclosure_lid_PILOT/OPS/COMMAND.3mf` | 1 each | black | engraved name |
| `cable_clips_set.3mf` | 3 plates | black | 6/10/16/24 mm bundle clips + flat LED-strip clip, one #8 screw each |
| `limit_switch_mount.3mf` | 3 | black | V-15 roller micro switch, slotted +-10 mm (seat UP, DOWN, READ-only) |

**Not printed:** harness hardware (webbing, buckles, adjusters, anchors) - use
rated 4-point harnesses and forged eye bolts (see `frame/BOM.md`); actuator
brackets (steel, from the actuator kit); hinge shaft and bearings.

## Print settings

| | Panels (bodies) | Letters / inserts | Mechanisms, mounts, enclosures |
|---|---|---|---|
| Material | PETG (preferred, tougher, no creep) or PLA; matte black | PETG/PLA **white** (natural/translucent white diffuses best) | PETG (ASA/PETG for the monitor mount) |
| Nozzle / layer | 0.4 mm / 0.2 mm (first layer 0.2) | 0.2 mm | 0.2 mm |
| Walls | 3 perimeters | 2 | 4 (monitor mount 6) |
| Infill | 30 % gyroid (body is solid anyway at 3 mm) | 100 % | 40 % gyroid (monitor mount >= 60 %) |
| Orientation | **face down** (the 3MF is already flipped) - smooth front from the bed, light boxes build up | as exported (plaque down) | as exported (flat faces down) |
| Supports | none | none | none (all parts designed support-free) |
| Bed | smooth PEI or glass gives a glossy face; textured PEI a matte face | | |

Multi-material: purge/prime tower on, "wipe into infill" off (letters must stay
pure white). On a single-nozzle MMU/AMS, the colour change happens only in the
3 mm panel layers (~15 layers), so prints stay fast.

Every part fits a 220 x 220 mm bed; the overhead, dash and commander panels are
split along the grid. Printing on a 250 mm+ bed changes nothing.

## Assumptions to check before printing

- Printer bed >= 220 x 220 mm, multi-material optional (fallback provided).
- Monitors: 27" 1440p, 1500R curve, VESA 100 (`cad/parts/monitor_mount.scad`).
- Touchscreen: 15.6" outline 359 x 225 x 9 mm, active area 345 x 195 mm - measure and set `SCR`, `ACTIVE`, `ACTIVE_OFF` in `touchscreen_bezel.scad`.
- Joystick mounting pattern unknown - measure, then set `SQ_PITCH` / `CENTER_D` in `joystick_housing.scad` (slots already cover bolt circles 44-88 mm).
- Switch bushings: 6 mm mini toggles, 12/16/19/22 mm buttons, EC11 (7 mm), 19 mm key switch. Hole sizes are in `FF_CUTS` in `ff_lib.scad`; hole compensation `FF_HOLE_COMP = 0.2`.
- LED strip 12 mm wide (10 mm fits), 60 LED/m; ~136 LEDs estimated for 67 labels.
