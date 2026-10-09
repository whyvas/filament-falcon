# The Filament Falcon: master spec (v0.1)

A three-seat home spaceship cockpit: two small front seats (kids) side by side, one larger seat behind and centered (dad). Everything that a person touches is 3D printed and bolts to a wooden frame. This file is the single source of truth that the CAD, electronics, and game folders all follow. If something here has to change, change it here too.

## Computer
Linux Mint, AMD Ryzen 9 5900X (12c/24t), Radeon RX 6800 XT (16 GB, Vulkan/Mesa RADV), 32 GB RAM.
Three displays on the 6800 XT (2 x DP 1.4, 1 x HDMI 2.1, 1 x USB-C; max 4 heads), all 1920 x 1080 (updated on the `cad` branch; details in `docs/mechanical/displays.md`):
- Left kid's window (PILOT): Sceptre C275B-144R, 27" 1800R curved, up to 144 Hz, VESA 100, on DP.
- Right kid's window (OPS): Sceptre C275W-1920RN, 27" 1800R curved, 75 Hz, VESA 75, HDMI only.
- Center console: ViewSonic TD2220, 21.5" optical touch (USB-B), VESA 100, DVI-D/VGA only -> DP (or USB-C) to DVI-D adapter. It lies flat in the reclining center console between the kids and faces them when reclined.
- The USB-C output stays free (one extra display or projector later; see `docs/mechanical/projector_dome_study.md`).

## Seats and motion
(Changed on the `cad` branch, v0.2: the swinging/raised seat platform is gone. Details in `frame/README.md`.)
- The seats sit on a floor-level frame. Flight sequence: (1) the kids' seat cradle (both kid seats, side consoles, sticks, center touchscreen) reclines 35 deg backwards, astronaut launch-style; (2) then the instrument POD (both monitors, dash panels, overhead panels) rotates down from its parked position above the kids into place in front of them. Exit = reverse order (pod up first, then seats upright).
- Both motions use 12 V self-locking linear actuators (2 for the cradle, 2 for the pod), slow (~35-40 s per motion). The pod is counterbalanced with gas struts to near-neutral, its pivot is the reclined head centre so it cannot approach the faces, steel hard stops set the end positions with measured clearances (>= 195 mm to the thighs, >= 250 mm to the head), and spring pawls lock it mechanically both UP and DOWN.
- Hardwired sequencing with limit switches: the pod can only come down when the seats are fully reclined, and the seats can only move while the pod is up and locked.
- Controls only at dad's seat, hardwired (no microcontroller in the loop): key switch, E-stop, a momentary hold-to-run FLT/BRD toggle, plus a latch-release lever that must be held for any pod motion (two-hand control). The software may READ cradle/pod positions (separate dry contacts) but never drives the actuators.
- Dad's seat is fixed (no recline, no pod): he is the safety observer and must see the kids while anything moves.
- Homemade 4-point harnesses through a printed hub that houses the kit's own buckles (positioning harness, not crash-rated; load path through webbing and a steel ring). Motion only after the "harnesses fastened" step of the checklist (honour system, game shows it).

## Roles (designed to be equally fun)
- Left seat, PILOT ("Flight"): rotation and main engine. Joystick = pitch/roll/yaw + trigger. Throttle lever. Engine arm (covered toggle), ignition button, landing gear lever, flight-assist mode rotary (OFF / STAB / PROGRADE / HOLD), airbrake/flaps, boost, view cycle, horn.
- Right seat, OPS ("Systems/Commander"): translation, systems, and payload. Joystick = RCS translate X/Y + Z(twist) + trigger (also drives the robotic arm, tractor beam, and sensor camera depending on mode). Power distribution toggles (REACTOR, LIFE SUPPORT, SHIELDS, COMMS, SENSORS), mode rotary (RCS / ARM / SCANNER), cargo bay doors, docking clamp, scanner ping, fire suppression, nav target select, jump/warp arm + engage (covered).
- Each mission gives both seats a hero moment (e.g. Pilot flies the launch and landing; Ops does the docking translation, arm capture, and hyperspace jump).
- Rear seat, COMMANDER / MISSION CONTROL (dad): crew-motion hold switch + pod release lever (hardwired), key switch MASTER POWER, mission select rotary, START / PAUSE, MASTER CAUTION reset, failure-injection buttons (ENGINE FIRE, CABIN LEAK, POWER FAULT, SENSOR GLITCH), intercom/PA button, cockpit lights dimmer.
- Overhead console (shared, above the kids): launch checklist switch row (BATTERY, FUEL PUMPS, AVIONICS, APU START, GUIDANCE, IGNITION ARM), cabin lights, beacon, strobe, EJECT (covered, just for fun), each with a backlit label and status LED.
- Center touchscreen (game UI): nav map/orbit view, systems/power page, checklists, camera feeds, mission briefing.

## Panels
- Dark panel body, white letters that go all the way through the panel so LEDs behind shine through them. Multi-material 3MF (body + letters as separate parts with their own extruder/colour); also provide a single-material fallback with white press-fit letter inserts.
- A WS2812B strip channel on the back directly behind each lettered label, with light-blocking walls between labels. ONE continuous WS2812B strip snakes through every panel; segments are mapped later in `shared/led_segments.json`.
- Every panel uses one mounting standard: a 40 mm grid, M5 bolts into M5 T-nuts (or 1/4-20 if the owner prefers) pressed into 18 mm (3/4") plywood rails. Max part size 220 x 220 mm so it fits most printer beds; bigger panels split along the grid with alignment pins.
- Standard holes: 6.2 mm mini toggle, 12 mm and 16 mm momentary buttons, 19 mm/22 mm arcade buttons, 5 mm LED, EC11 rotary encoder (7 mm), key switch (19 mm), plus printed toggle covers (missile-switch guards).

## Electronics
- Microcontroller: ESP32-S3 (DevKitC-1 or equivalent with the native USB port). Reason: native USB so it enumerates as a real HID joystick on Linux and Windows with no drivers; the ESP8266 and classic ESP32 have no native USB.
- Three boards, each its own USB HID gamepad with a distinct product name: "Falcon Pilot" (left), "Falcon Ops" (right), "Falcon Command" (dad + overhead). Falcon Command is a composite device (HID + USB CDC serial) and also drives the single WS2812B data line.
- Lots of switches go through 74HC165 shift registers or MCP23017 expanders; analog axes go to ADC1 pins (3.3 V reference).
- The game sends LED state to Falcon Command over the CDC serial port using the protocol in `shared/led_protocol.md`.

## Shared files (contracts between folders)
- `shared/panel_labels.json`: every backlit label id, its panel, and its text (written by CAD).
- `shared/input_map.json`: every game action -> device name + button index or axis (written by firmware; the game loads it and falls back to built-in defaults).
- `shared/led_segments.json`: label id -> start index + LED count on the one strip (placeholder until the owner measures the real strip).
- `shared/led_protocol.md`: serial protocol from game to Falcon Command.

## Game
Godot 4 (latest stable 4.x), Forward+ renderer on Vulkan, three windows (one per display), GDScript. Missions: launch to orbit, dock with a space station, lunar landing, asteroid-field rescue/mining, reentry and runway landing, plus a free-flight sandbox.

## Folders
- `cad/` 3D models (OpenSCAD source + exported 3MF + PNG renders); `frame/` wooden frame drawings, cut list, BOM.
- `firmware/` ESP32-S3 code; `docs/electronics/` wiring diagrams.
- `game/` Godot project; `docs/game/` design notes.
