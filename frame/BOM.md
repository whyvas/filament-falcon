# Frame bill of materials (v0.2: reclining cradle + drop-down pod)

Metric first, imperial in brackets. Lumber and sheet quantities come from
`frame_model.py` (see `cut_list.md` for every piece and the board packing).
Printed parts are listed in `docs/mechanical/README.md`; switches per panel in
`docs/mechanical/switch_bom.md`; displays and video cables in
`docs/mechanical/displays.md`.

## Lumber and sheet goods

| Qty | Item | Notes |
|---|---|---|
| 24 | 2x4 stud, 2438 mm (8 ft), straight, kiln dried | 22 used by the packing in `cut_list.md` + 2 spares (38 x 89 mm actual) |
| 2 | 2x4, 3048 mm (10 ft) | the two 2450 mm sills |
| 6 | 18 mm (3/4") plywood, 1220 x 2440 mm | seat boxes/backs, consoles, cradle deck, pod cheeks (2 layers each), pod bands, dais (13.5 m2 net) |
| 4 | 12 mm (1/2") plywood, 1220 x 2440 mm | casings, skins, nose box, pod back sheet + chin, crush-zone ramp (9.2 m2 net) |
| 1 | 6 mm hardboard, 1220 x 2440 mm | small covers / templates |

## Pivots, shafts, bearings

| Qty | Item | Use |
|---|---|---|
| 2 | 25 mm bright steel round bar (h9), ~1000 mm | cradle shaft (one per side, or one 1750 mm through-shaft), pod shaft stubs |
| 2 | 25 mm round bar, ~250 mm | pod shaft stubs (one per side, tower post outer -> inner) |
| 6 | SHF25 shaft supports | cradle shaft on the 2 pivot pedestals; pod shaft on the inner tower posts (+2 spare positions) |
| 2 | UCP205 pillow blocks (25 mm) | under the rear ends of the cradle rails |
| 2 | UCF205 4-bolt flange bearings (25 mm) | in the pod cheeks |
| 4 | 25 mm shaft collars | stop the shafts walking |
| 4 | 6 mm steel plate 120 x 120 with 4 holes | under the pod bearings / supports on the tower posts |
| 1 box | M10 x 90 coach screws + washers, M8 x 60 bolts + nylocks | bearings, actuator clevises (use your actuators' pin size) |

## Motion drive

| Qty | Item | Notes |
|---|---|---|
| 2 | **Cradle actuators**: 12 V DC linear actuator, 10" (254 mm) stroke, >= 1500 N (330 lbf), self-locking (acme/worm), ~364 mm (14.3") retracted pin-to-pin, <= 10 mm/s, internal limits | PUSH to recline; worst case ~775 N each (model). Retracted length must be 364 +-10 mm, else move the anchor in `frame_model.py` and re-run |
| 2 | **Pod actuators**: 12 V DC, 12" (305 mm) stroke, >= 1000 N (225 lbf), self-locking, ~415 mm (16.3") retracted, <= 10 mm/s | PULL to raise; 141 N each normally, 390 N each if both struts fail |
| 2 | **Gas struts** (lift supports), 10 mm rod / 22 mm body, ~240 mm extended, >= 70 mm stroke, F1 = 590 N (progressive ~1.5) with ball-stud ends | buy 550-600 N, or an adjustable-valve strut (bleed down to the right force). Fit with the pod UP |
| 4 | Steel angle brackets 50 x 50 x 5 mm with M8 hole | strut and actuator anchors on the tower posts / casings |
| 2 | 6 mm steel latch plates (laser cut / filed from the cheek template `06`), with UP and DOWN notches | bolted to the cheeks |
| 2 | Spring-loaded steel pawls (gate latch / barrel bolt with spring) | engage the latch plates, one per casing |
| 2 | Bowden cable + lever (bicycle brake lever + inner/outer cable) | release both pawls from the lever box left of dad's seat |
| 4 | Steel stop pins 12 mm + rubber bumpers | pod UP / DOWN hard stops (on the cheeks, hitting steel angles) |
| 2 | Rubber stop blocks 10 mm on 2x4 | cradle recline hard stop; 2 x 6 mm rubber pads for the upright stop |

## Hardwired interlock (no microcontroller)

| Qty | Item | Notes |
|---|---|---|
| 1 | 12 V 20 A power supply (enclosed, mains fused) | |
| 1 | 20 A blade fuse + holder | at the PSU |
| 1 | Key switch (2-position) driving a 30 A relay | MOTION key on CMD_B: key out = no motion |
| 1 | 22 mm mushroom E-stop, NC, latching, twist release | on CMD_B |
| 1 | DPDT (ON)-OFF-(ON) momentary toggle, 12 mm bushing | FLT / BRD hold-to-run on CMD_B |
| 4 | 12 V 30 A automotive relays SPDT (Bosch type) | wired as 2 H-bridges (cradle, pod) |
| 8 | V-15 roller-lever micro switches 15 A (NC used) + printed `limit_switch_mount` | CRADLE_UPRIGHT, CRADLE_RECLINED (x2, one per side, in series), POD_UP, POD_DOWN, POD_UP_LOCKED (x2 on the pawls), lever switch |
| 2 | Extra micro switches | dry contacts READ by Falcon Command (cradle reclined, pod down) |
| 8 | 1N5408 diodes | across each motor-path limit switch so you can always drive back |
| 1 | Pressure-sensitive safety edge (NC), ~900 mm, with mounting profile | along the pod chin, in series with "pod DOWN" |
| 20 m | 14 AWG (2.5 mm2) red/black stranded, plus 18 AWG for switch circuits | |
| - | Ring terminals, heat shrink, braided sleeve, printed cable clips | |

## Guards, cable strain relief

| Qty | Item | Notes |
|---|---|---|
| 4 m | Brush strip (strip brush) 25 mm, aluminium holder | cheek slots in the casings (2 edges each) |
| 1 m | Brush strip | nose-box actuator slots |
| 2 m | 25 mm foam + vinyl | pod chin (behind the safety edge) and pod lower edges |
| 8 | printed `pivot_cable_clamp` (base + cap) + M4 x 25 + M4 inserts | 2 per bundle per pivot: pod L, pod R, cradle L, cradle R |
| 5 m | braided sleeve 25-30 mm | the 200 mm U service loops |

## Fasteners and general hardware

| Qty | Item | Use |
|---|---|---|
| 1 box | Construction screws 5 x 80 mm (#10 x 3") | 2x4 joints |
| 1 box | Wood screws 4 x 40 mm and 4 x 25 mm | ply to 2x4, skins, clips, limit-switch brackets |
| 1 | PVA wood glue 1 l | cheek laminations, boxes |
| 200 | M5 four-prong T-nuts + M5 x 20 button head screws | panel bays (40 mm grid) |
| 8 | M6 x 50 carriage bolts + fender washers + nylocks | 2 monitor standoffs to the pod back sheet |
| 4 + 4 | M4 x 20 (C275B, VESA 100) / M4 x 16 (C275W, VESA 75) | monitors to the printed standoffs (check thread depth, max ~10 mm engaged) |
| 2 | 2 mm steel safety cable 300 mm with eyes + eye screws | one per monitor (REQUIRED: the pod parks the monitors face-down) |
| 4 | M4 x 12 + washers | TD2220 to the printed VESA 100 riser |
| 30 | M4 x 25 countersunk wood screws | TD2220 trim ring laps |

## Seats and harnesses

| Qty | Item | Notes |
|---|---|---|
| 2 | Kid harness: 25 mm (1") polyester webbing (>= 700 kg rated), buckle kit (amazon.ca B0B3J1GCVQ: 4 x female + male per seat), printed `harness_hub` | see the safety note in `docs/mechanical/README.md`: positioning harness only |
| 2 | Welded steel O-rings 50 mm OD, 6 mm wire (rated) | harness hub load ring |
| 1 | Dad: lap belt (bought) | fixed seat, no recline |
| 10 | 3/8" (M10) forged eye bolts + fender washers + nylocks | harness anchors through the cradle rails / seat-back frames (never plywood alone) |
| 3 | High-density foam cushions + vinyl; 1 x 60-80 mm booster for the 6 yr | |

## Electronics enclosures and cabling (printed parts listed in docs/mechanical)

| Qty | Item |
|---|---|
| 3 | 70 x 90 mm perfboard + female headers (one per ESP32-S3-DevKitC-1) |
| 12 | M2.5 x 6 self-tapping screws (perfboard to enclosure standoffs) |
| 12 | M3 x 10 self-tapping screws (enclosure lids) |
| 1 | WS2812B strip 12 mm, 60 LED/m, 5 m - ~136 LEDs used |
| 1 | 5 V 10 A power supply for the LED strip |
| - | Video/USB cables: see `docs/mechanical/displays.md` |
