# The Filament Falcon - wooden frame (v0.1)

2x4 lumber + 18 mm (3/4") plywood. Two kid seats (6-12 yr) side by side in front,
the commander (adult) seat behind and centred. All three seats sit on one pivoting
platform that two 12 V linear actuators tilt up 9.2 deg into "flight position".
All dimensions in mm with inches in brackets. 2x4 = 38 x 89 mm (1.5" x 3.5").

| File | What |
|---|---|
| `drawings/frame_drawings.pdf` | all drawings in one PDF (A3 landscape) |
| `drawings/01_front_elevation.png/.svg` | front view: posts, monitor beam, actuator header, dash |
| `drawings/02_side_elevation.png/.svg` | side view, platform lowered + raised, eye heights, hinge, actuator line |
| `drawings/03_plan_view.png/.svg` | plan: seats, consoles, panel bays, actuators |
| `drawings/04_seat_lift_actuators.png/.svg` | pivot geometry, stroke/force estimate with assumptions, hardwired circuit, pinch-point rules |
| `drawings/05_panel_bay_detail.png/.svg` | how a printed panel bolts to the plywood rails (40 mm grid, M5 T-nuts) |
| `cut_list.md` / `cut_list.csv` | every piece, lumber board packing, sheet count |
| `BOM.md` | lumber, sheet goods, fasteners, actuators, switches, harness hardware |
| `frame_model.py` | the parametric model: edit numbers here and re-run (writes `generated/frame.scad`, `generated/geometry.json`, cut list) |
| `make_drawings.py` | regenerates `drawings/` from the model |

Regenerate: `python frame/frame_model.py && python frame/make_drawings.py`
(needs numpy + matplotlib), then `python cad/tools/build.py` for the 3D overview.

## Key dimensions

- Overall 1700 W x 2100 L x 1800 H mm (5' 6.9" x 6' 10.7" x 5' 10.9"). Fits through a door only in pieces: build it in the room.
- Dash: 18 mm ply sheets at 27 deg, front edge ~780 mm high. Each kid has a 400 x 120 mm panel bay (two 200 x 160 printed panels).
- Monitor beam: 2x4 on edge between the front posts, underside 1313 mm (4' 3.7"); monitors hang nearly vertical, centres 380 mm left/right of the centre line, ~1200 mm high (+-80 via the slotted hanger + tilt).
- Kid eye heights (seated, raised): ~1180 (6 yr) / ~1250 (9 yr) / ~1320 (12 yr) mm. Overhead console hangs on M8 rods (+-80 mm).
- Platform: hinge at the rear (20 mm shaft in two UCP204 pillow blocks on the sills, 2031 mm behind the front, 122 mm up), nose lifts ~300 mm. Kid cushion 422 -> 638 mm, commander cushion 652 -> 724 mm.
- Actuators: 1000 mm apart (x = +-500), 160 mm behind the front, top clevis on the doubled header (z 850), bottom clevis on the platform nose rim. They PULL to raise. 300 mm stroke, 440 -> 740 mm pin to pin.

## Assembly steps

1. **Cut** everything in `cut_list.md`. Label each piece. Check real 2x4 sizes and adjust `frame_model.py` if they differ.
2. **Base**: lay the two 2100 mm sills on edge, screw in the four base cross members (front, stop rail, hinge, rear) - check the diagonals are equal (square). Put the base on its final spot: it is heavy afterwards.
3. **Side frames**: on each side, screw the front post, knee post and mid post to the sill, then the top side rail on top of the front + mid posts and the short lower side rail between the front and knee posts. Add the 45 deg knee braces. Stand both sides up and join them with the top cross members (front, overhead front/rear, mid). Plumb + square, then screw.
4. **Actuator header**: glue + screw the two header 2x4s together (doubled), set it on the lower side rails between the front and knee posts, screw through the posts and add the steel angle brackets. This beam carries the full lift load (~1450 N) - do not skip the brackets.
5. **Monitor beam**: screw between the front posts at 1313 mm underside, back face flush with the posts.
6. **Dash**: screw the four dash cheeks to the header/side rails, then the two dash sheets on top at 27 deg. Cut the panel-bay openings (400 x 120 mm) and drill + press the M5 T-nuts on the 40 mm grid from the back (see `05_panel_bay_detail`). Press T-nuts with a bolt + washer, then tap in; a dab of epoxy stops spin-out.
7. **Platform**: build the platform on the floor upside down: two full-length outer joists (with the 21 mm hinge hole), nose rim, seat cross, dad cross, rear rim, and the segmented inner joists (joist hangers or pocket screws). Glue + screw the two deck sheets (every 150 mm). Add the toe board on the nose and the 6 mm platform skirts on both sides.
8. **Hinge**: bolt the two UCP204 pillow blocks to the sills (M10 coach screws), slide the 20 mm shaft through block - joist - joist - block, add the shaft collars. Lower the nose onto the stop rail.
9. **Seats and consoles**: build the seat boxes, seat backs (harness slots at three heights), centre console (touchscreen tray + Ops side console top), Pilot side console, Ops side console and the Commander console, and screw them to the deck from below. Panel bays use the same 40 mm grid + M5 T-nuts.
10. **Harness anchors**: 3/8" (M10) forged eye bolts with fender washers through the platform joists (lap belts) and through the seat-back frame / a 2x4 cross member behind each seat back (shoulder straps). Never anchor into plywood alone. Use bought, rated harnesses (see `BOM.md`); harness hardware is NOT printed.
11. **Actuators**: mount the steel brackets on the header underside and on the platform nose rim, both exactly at x = +-500 mm, so the actuators hang vertical. With the platform DOWN the actuators are fully EXTENDED (740 mm pin to pin); they pull the nose up. Set both to full extension on the bench (12 V, same time), fit them, then test.
12. **Limit switches**: screw the printed `limit_switch_mount` brackets to the knee post (DOWN switch hits the nose rim when lowered, UP switch at full lift, 5-10 mm before the actuators' own internal limits). Add the third "seat up" READ-only switch for Falcon Command.
13. **Wiring (hardwired)**: 12 V PSU -> 15 A fuse -> SEAT KEY -> SEAT STOP (E-stop, NC) -> SEAT LIFT DPDT (ON)-OFF-(ON) hold-to-run -> UP/DOWN limit switches (NC, each bridged by a 1N5408 diode so you can always drive back) -> both actuators in parallel. 14 AWG. All three controls are on CMD_B at the commander seat only. Test with nobody seated: release = stop, E-stop = stop, key out = no motion, limits stop at both ends.
14. **Skins and guards**: 12 mm front skin and side skins close the actuator bay; 6 mm fixed side skirts outside the moving platform skirts form the telescoping pinch guard (32 mm side gap, overlap at full lift). Check the ISO 13854 minimum gaps in `04_seat_lift_actuators` with the platform both up and down: no finger/hand/foot trap anywhere a child can reach.
15. **Overhead console**: hang the 12 mm ply box on four M8 rods from the overhead cross members; set height so the 12 yr old's head clears it with the platform up.
16. **Monitors**: printed beam brackets + VESA plates (or steel VESA tilt brackets), always with a steel safety cable from a VESA screw to the beam.
17. **Panels**: bolt the printed panels into the bays (see `docs/mechanical/README.md`), run the single WS2812B strip in label order (`shared/panel_labels.json`), clip cables with the printed clips.

## Safety rules (put a copy on the commander console)

- Seat lift ONLY from the commander seat, hold-to-run; letting go stops it. Key out when not flying.
- Everybody seated, hands on lap, harnesses fastened BEFORE "seats moving" (the game checklist shows it; honour system).
- Nobody under or beside the platform while it moves. The front/side skins and skirts stay on.
- Check eye bolts, harness webbing, actuator bolts and the hinge collars monthly.
