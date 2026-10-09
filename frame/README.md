# The Filament Falcon - wooden frame (v0.2: reclining seats + drop-down pod)

2x4 lumber + 12/18 mm plywood on a floor-level base (no raised platform).
Two kid seats (6-12 yr) side by side in front, dad's seat behind and centred on a
250 mm dais. All dimensions mm (inches in brackets). 2x4 = 38 x 89 mm (1.5" x 3.5").

![motion](../cad/export/png/overview_motion_sequence.png)

## How it moves

| Step | What moves | Drive | End stops / locks |
|---|---|---|---|
| 1 BOARDING | nothing: seats upright, pod parked UP over the kids (lowest point 1639 mm over the floor) | - | pod locked UP by spring pawls |
| 2 RECLINE (hold FLT) | the **cradle** (both kid seats, side consoles, sticks, throttle, gear lever, TD2220 centre console) tips back 35 deg about a 25 mm shaft at 840 mm behind the nose, 200 mm up | 2 x 12 V actuators, 10" (254 mm) stroke, in the nose box, PUSH to recline | rubber stop blocks on a steel-angle stop rail at 35 deg; rests on the front pads at 0 deg |
| 3 POD DOWN (keep holding FLT + release lever) | the **pod** (both monitors, 4 dash panels, 3 overhead panels) swings 55 deg down (95 -> 40 deg) about a 25 mm shaft at the reclined 12 yr's head centre (1375 mm behind the nose, 1005 mm up) | 2 x 12 V actuators, 12" stroke, inside the side casings, PULL to raise; 2 x gas struts make it near-neutral | 6 mm steel stop pins on each cheek; pawls drop into the DOWN notch |
| EXIT (hold BRD) | pod up first, then cradle upright | same | same |

Each motion takes ~35-40 s (slow on purpose, <= 10 mm/s at the actuator).

**Why the pod pivots on the head:** the pod pivot is the reclined 12 yr's head
centre, so every pod point moves on a circle *around* the head and can never
come closer to the face than at its parked positions. The screens stay 600 mm
from the pivot (~540 mm from the 12 yr's eyes, ~590 mm from the 6 yr's).

**Dad's seat does not recline and has no pod.** He is the safety observer: the
motion controls are only at his seat, hold-to-run, so he must see both kids'
heads, hands and the pod gap the whole time it moves. A reclining dad seat would
put his eyes below the pod's back and hide the kids; a third pod would need its own
actuators, interlock and clearance envelope next to the kids' pod (pinch point
between two moving bodies) for little gain. He keeps the CMD console (2 printed
panels) and gets a view over the kids at the front monitors (`overview_dad_view.png`);
add a small fixed 3rd display at the CMD console later if wanted (needs a GPU output,
see `docs/mechanical/displays.md`).

## Files

| File | What |
|---|---|
| `drawings/frame_drawings.pdf` | all drawings in one PDF |
| `drawings/01_front_elevation` | front view in FLIGHT: casings, pod, seats, monitor positions |
| `drawings/02_side_motion_geometry` | **side view with both motions**: cradle/pod pivots, arcs, actuators, struts, eye-to-screen, clearances |
| `drawings/03_plan_view` | plan: seats at x = +-460, consoles, casings, actuators, dad dais |
| `drawings/04_mechanism_interlock` | actuator/strut sizing, torque curves, hard stops, locks, hardwired interlock |
| `drawings/05_pinch_points_clearances` | every gap that changes with motion vs. ISO 13854 (finger 25, head 120 ... ) |
| `drawings/06_pod_cheek_template` | full-size outline of the pod cheeks (print tiled, trace on plywood) |
| `drawings/07_panel_bay_detail` | printed panel -> plywood rail (40 mm grid, M5 T-nuts) |
| `cut_list.md` / `.csv` | every piece, board packing, sheet count (generated) |
| `BOM.md` | lumber, hardware, actuators, struts, bearings, locks, interlock parts |
| `frame_model.py` | parametric model: geometry, mechanism searches (struts/actuators), clearance check; writes `generated/frame.scad`, `generated/geometry.json`, the cut list |
| `make_drawings.py` | regenerates `drawings/` from the model |

Regenerate: `python frame/frame_model.py && python frame/make_drawings.py`
(numpy, scipy, shapely, matplotlib), then `python cad/tools/build.py` for the 3D renders.

## Key numbers (from `generated/geometry.json`)

- Footprint 1960 W x 2450 L mm (6' 5" x 8' 0.5"); casings/towers 1112 mm high; **swept height 1828 mm (pod parked up) -> ceiling >= 1950 mm**.
- Seat centres x = +-460 mm (920 apart) so the 559 mm TD2220 trim fits between them.
- Pod: ~44 kg (model, incl. 7.2 kg monitors), CG 589 mm from its pivot. Gravity torque -204 .. +5 N m; with 2 gas struts (F1 590 N, progressive to ~885 N, ~61 mm used stroke, ~240 mm extended) net -48 .. +48 N m: it sits firmly on the DOWN stop when down and on the UP stop when up, and is easy to drive between.
- Pod actuators: 426 -> 700 mm pin-to-pin (12" stroke, ~415 mm retracted), peak 141 N each, 390 N each with both struts failed -> buy **1000 N self-locking**.
- Cradle: ~258 kg design load (2 x 50 kg kids + frame + consoles). Gravity torque -263 .. +270 N m (stable on both stops). Actuators 376 -> 607 mm (10" stroke, ~364 mm retracted), peak 775 N each -> buy **1500 N self-locking**.
- Clearances (worst case = 12 yr manikin, pod at every angle): pod chin to thighs 195 mm, shins 220, head >= 251, upper arm to cheek 157; kid arm to casing 35 (finger-safe 25+); seat back to casing 60; cradle to nose wall >= 30; cheek to inner wall / post 66 / 50.
- Eye -> screen centre: 12 yr 542 mm (gaze 40 deg up from horizontal), 6 yr 590 mm (55 deg) -> a 60-80 mm booster cushion for the 6 yr is recommended.

## Safety concept (heavy pod moving toward kids)

1. **Hard stops define the envelope, not the actuators.** Steel stop pins/blocks at both ends of both motions; the actuators' own limits are 2-3 mm beyond the external limit switches, and the stops are where the clearances above were measured.
2. **Near-neutral pod.** Gas struts carry ~75 % of the pod torque; if a strut fails, the self-locking actuators (rated 2.5 x the strut-failed load) still hold.
3. **Slow:** <= 10 mm/s actuators, ~35-40 s per motion.
4. **Mechanical locks both ends:** spring pawls in each casing drop into notches in a 6 mm steel latch plate on each cheek (UP and DOWN). They click in by themselves; a Bowden-cable lever LEFT of dad's seat lifts both. A micro switch on the lever is in series with the pod motors, so the pod moves only while dad holds the lever with one hand AND the hold-to-run toggle with the other (two-hand control).
5. **Hardwired interlock** (no microcontroller can move anything; the game only reads dry contacts):
   - FLIGHT: cradle reclines only while POD_UP_LOCKED; pod comes down only while CRADLE_RECLINED (both sides) AND lever held.
   - BOARD: pod goes up while lever held; cradle comes upright only while POD_UP AND latched.
   - => the pod can never come down unless the seats are fully reclined, and the seats never move under a lowered pod.
   - Key switch, 20 A fuse, latching E-stop (NC), NC roller limit switches each bridged by a 1N5408 so you can always drive back.
   - Pressure-sensitive safety edge (NC) along the pod chin in series with "pod DOWN".
6. **Pinch-point rules** (ISO 13854 style): every gap that opens/closes is either >= 120 mm (head/body) or <= 8 mm / covered (finger can't enter) or >= 25 mm at all times. The cheeks run in 48 mm slots in the casings closed with brush strips; a fixed 120 mm crush-zone ramp sits under the reclined seat backs so nothing can be trapped between seat back and floor; the nose-box actuator slots have brush strips. See `drawings/05_pinch_points_clearances`.
7. **Cables across pivots:** every bundle crossing a pivot gets two printed `pivot_cable_clamp`s (fixed side + moving side, <= 60 mm from the axis) with a 200 mm U service loop in braided sleeve.

## Assembly steps

1. **Cut** everything in `cut_list.md`; label each piece. Check real lumber sizes and adjust `frame_model.py`.
2. **Base**: sills + cross members (the nose-rear and cradle-front crosses are laid FLAT so the actuators pass over them). Square the diagonals. Build it where it will live.
3. **Nose box**: posts, front skin, rear wall with 2 actuator slots + brush strip, screwed-down lid (foot step).
4. **Towers and casings**: outer + inner tower posts each side carry the pod shaft (25 mm, UCF205 4-bolt flange bearings on 6 mm steel plates). Casing walls get the 48 mm cheek slot cut from the template (`06`), edged with brush strip.
5. **Cradle**: two rails on the 25 mm cradle shaft (2 x UCP205 pillow blocks on the base), seat boxes and backs (harness slots), side consoles, centre console with the TD2220 shelf. Fit the stop rail + rubber blocks.
6. **Cradle actuators** in the nose box (x = +-560, anchor 20 mm behind the nose, 30 mm up; pin on the cradle 360 mm back, 190 mm up). Bench-set both to the same length before fitting. Test the recline empty first.
7. **Pod**: two cheeks (2 layers 18 mm ply, glued, steel crank/latch plates bolted through), back sheet, dash lower band, overhead upper band. Hang it on the shaft with the pod parked UP and the pawls engaged.
8. **Gas struts**: fit with the pod UP (struts extended). Check: pod DOWN, released, must sit on its stop; pod UP must sit on its stop.
9. **Pod actuators** inside the casings; set length with the pod on the UP stop.
10. **Interlock wiring** per `drawings/04_mechanism_interlock`. Test with NOBODY seated: every limit, every lock, E-stop, key, lever released = no pod motion, safety edge = stop.
11. **Guards and skins**: brush strips, casing skins, crush-zone ramp, nose lid. Re-check every gap on `05` with a 25 mm dowel and a 120 mm ball at both ends of both motions.
12. **Monitors, panels, harness**: see `docs/mechanical/README.md` and `docs/mechanical/displays.md`.

## Safety rules (put a copy on the CMD console)

- Motion ONLY from dad's seat, hold-to-run + release lever (two hands). Let go = stop. Key out when not flying.
- Harnesses fastened, hands on lap, heads on the headrests BEFORE "FLT". The game checklist shows it; honour system.
- Nobody stands beside the casings or in front of the nose while anything moves.
- Monthly: strut force (with the actuator pins pulled, the pod should be movable by hand with <= ~7 kg (70 N) at the chin and drift only slowly toward the nearest stop), actuator bolts, pawls/notches, stop pins, safety cables on the monitors, harness webbing and eye bolts.
