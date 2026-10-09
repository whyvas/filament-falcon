# Frame bill of materials (v0.1)

Metric first, imperial in brackets. Lumber and sheet quantities come from
`frame_model.py` (see `cut_list.md` for every piece and the board packing).
Printed parts are listed in `docs/mechanical/README.md`; switches per panel in
`docs/mechanical/switch_bom.md`.

## Lumber and sheet goods

| Qty | Item | Notes |
|---|---|---|
| 26 | 2x4 stud, 2438 mm (8 ft), straight, kiln dried | 24 needed by the packing in `cut_list.md` + 2 spares. Pick straight boards; actual size 38 x 89 mm (1.5" x 3.5"). |
| 4 | 18 mm (3/4") plywood, 1220 x 2440 mm (4 x 8 ft) | decks, dash sheets/cheeks, seat + console boxes, seat backs, panel-bay rails (8.7 m2 net) |
| 2 | 12 mm (1/2") plywood, 1220 x 2440 mm | front skin, side skins, toe board, overhead box (2.9 m2 net) |
| 1 | 6 mm (1/4") plywood or hardboard, 1220 x 2440 mm | telescoping side skirts = pinch guards (2.1 m2 net) |

## Fasteners and frame hardware

| Qty | Item | Use |
|---|---|---|
| 1 box | Construction screws 5 x 80 mm (#10 x 3") | 2x4 to 2x4 joints (2 per joint min., pre-drill near ends) |
| 1 box | Wood screws 4 x 40 mm (#8 x 1-1/2") | plywood to 2x4, boxes, cheeks |
| 1 box | Wood screws 4 x 25 mm (#8 x 1") | skins/skirts, cable clips, limit-switch brackets, throttle housing |
| 1 | Wood glue (PVA), 500 ml | doubled header, deck to joists, boxes |
| 8 | Steel angle brackets 40 x 40 x 40 mm, 2 mm (heavy L-bracket) | actuator header to side rails, header to mid/knee posts |
| 4 | Steel joist hangers for 2x4 (or pocket screws) | segmented inner platform joists |
| 200 | M5 four-prong T-nuts (tee nuts), 8 mm barrel | panel bays, bezel, joystick housings, ESP32 enclosures (~150 used) |
| 200 | M5 x 20 button-head hex screws, black (+ washers) | panels: 3 mm panel + 18 mm ply; T-nut barrel must engage. Use M5x16 where the barrel is short |
| 30 | M5 x 25 countersunk screws, black | touchscreen bezel (countersunk holes) |
| 4 | M8 threaded rod 1 m + 16 nuts + 16 washers | overhead console hangers (+-80 mm height adjust) |
| 1 | 20 mm steel round bar, 1750 mm (bright steel, h9) | platform hinge shaft |
| 2 | UCP204 pillow-block bearings (20 mm bore) + 4 x M10x90 coach screws | hinge, bolted to the sills |
| 2 | 20 mm shaft collars | keep the hinge shaft from walking |
| 4 | M8 x 60 bolts + nylocks + washers | actuator clevises (use the pin size of your actuators) |
| 4 | Steel actuator mounting brackets (usually included with the actuator) | header (top) + platform nose rim (bottom) |
| 4 | M6 x 60 lag screws (or #12 x 2-1/2") | monitor beam brackets |
| 2 | Steel safety cable 3 mm, 300 mm, with eyes + screws | one per monitor, VESA screw to beam (REQUIRED) |
| 2 | Steel VESA 100 tilt brackets (optional) | substitute for the printed monitor hanger |
| 8 | M4 x 12 screws | VESA plates to monitors |
| 1 m | Self-adhesive foam strip 10 x 3 mm | touchscreen pads |

## Seats and harnesses (NOT printed)

Harness hardware must never be printed. Use rated parts only.

| Qty | Item | Notes |
|---|---|---|
| 3 | 4-point harness, 50 mm (2") polyester webbing, metal camlock/latch buckle | buy a complete go-kart / sim-rig 4-point harness (or rated webbing >= 15 kN + rated metal buckles and adjusters if you sew your own; follow the maker's stitch pattern) |
| 12 | 3/8" (M10) forged eye bolts + fender washers + nylocks | harness anchors THROUGH the platform joists / seat-back frame, never into plywood alone |
| 3 | Foam cushions (high density, 50-80 mm) + vinyl cover | kid 340 x 380, dad 520 x 480 |

## Seat-lift drive (hardwired, no microcontroller)

| Qty | Item | Notes |
|---|---|---|
| 2 | 12 V DC linear actuator, 300 mm (12") stroke, >= 1500 N (330 lbf) rated in PULL, 440 mm (17.3") retracted pin-to-pin, built-in limit switches, 10-15 mm/s | same model for both; calculated worst case ~725 N each (see `drawings/04_seat_lift_actuators`) |
| 1 | 12 V 20 A power supply (enclosed, with mains fuse) | or 12 V 30 A for margin |
| 1 | Inline blade fuse holder + 15 A fuse | right at the PSU |
| 1 | Key switch, 2-position, >= 15 A (or key switch driving a 30 A automotive relay) | SEAT KEY - key out = no motion |
| 1 | 22 mm mushroom E-stop, NC, latching, twist release | SEAT STOP, within reach of the commander |
| 1 | DPDT (ON)-OFF-(ON) momentary toggle, >= 15 A @ 12 V DC, 12 mm bushing | SEAT LIFT hold-to-run |
| 2 | V-15 roller-lever micro switch 15 A (NC used) + printed `limit_switch_mount` | UP and DOWN end-of-travel |
| 1 | Extra micro switch (or 2nd contact) | dry contact to Falcon Command: READ "seat up" only |
| 2 | 1N5408 diodes (3 A, 1000 V) | across each limit switch so you can always drive back |
| 2 | 30 A automotive relays SPDT (optional) | if the toggle/key are only rated for signal current |
| 10 m | 14 AWG (2.5 mm2) red/black stranded wire | power path |
| - | Ring terminals, heat shrink, wire loom, cable clips (printed) | |

## Electronics enclosures and cabling (printed parts listed in docs/mechanical)

| Qty | Item |
|---|---|
| 3 | 70 x 90 mm perfboard + female headers (one per ESP32-S3-DevKitC-1) |
| 12 | M2.5 x 6 self-tapping screws (perfboard to enclosure standoffs) |
| 12 | M3 x 10 self-tapping screws (enclosure lids, 4 each) |
| 1 | WS2812B strip, 12 mm wide (10 mm fits too), 60 LED/m, 5 m reel, IP30 (no silicone sleeve) - ~140 LEDs used |
| 1 | 5 V 10 A power supply for the LED strip (inject power at both ends) |
