# Filament Falcon electronics

Three ESP32-S3 boards, each a real USB HID joystick (no drivers on Linux or Windows):

| Board | USB name | VID:PID | Where | Inputs | Extra |
|---|---|---|---|---|---|
| ESP32-S3-DevKitC-1 #1 | **Falcon Pilot** | 1209:0003 | left kid, PILOT | 3-axis stick + trigger, throttle pot, 2 x 74HC165 (12 used, incl. PTT), 1 EC11 (FLIGHT ASSIST) | |
| ESP32-S3-DevKitC-1 #2 | **Falcon Ops** | 1209:0004 | right kid, OPS | 3-axis stick + trigger, 2 x 74HC165 (14 used, incl. PTT), 1 EC11 (OPS MODE) | |
| ESP32-S3-DevKitC-1 #3 | **Falcon Command** | 1209:0005 | dad + overhead console | 4 x 74HC165 (22 used, incl. INTERCOM PTT + ALL-CALL), 2 EC11 (MISSION, DIMMER knob), 3 read-only crew-position optos (GPIO39/40/41) | USB CDC serial, drives the ONE WS2812B data line |

The control set matches the CAD panel layouts (`cad/tools/layouts.py`, `shared/panel_labels.json`):
flight-assist mode, ops mode and mission select are EC11 encoders with push (the game keeps the
selected mode and lights the matching label), the dimmer is an EC11 "virtual knob" (firmware keeps a
0-255 level, reports it as an axis and dims the strip), NAV TGT is a push button, FLAPS is an ON-OFF-ON toggle.

Intercom push-to-talk (v0.2): each kid has a PTT button (Pilot 74HC165 bit 11 -> HID button 14 `ptt_pilot`, Ops
bit 13 -> HID 16 `ptt_ops`); dad's INTERCOM button is his PTT (HID 7 `ptt_commander`) and a new ALL-CALL / PA
button sits on Falcon Command bit 7 (HID 13 `all_call`). These three extra buttons are 16 mm momentaries with backlit
labels on the CAD panels: `PILOT_PTT` on PILOT_SIDE right beside the throttle (left hand), `OPS_PTT` on OPS_SIDE at the
end nearest the Ops seat (left hand; the right hand stays on the stick), `CMD_ALL_CALL` on CMD_A next to INTERCOM. The audio itself is USB headsets on the PC (`docs/game/README.md`, Intercom).

Why ESP32-S3: it has a native USB port, so it enumerates as a genuine HID joystick and (for
Falcon Command) also a serial port at the same time. The ESP8266 and the original ESP32 have no
native USB and would need a USB-serial bridge plus PC-side software. The S3 also has 10 ADC1 pins,
enough RAM and 240 MHz dual core, more than enough to poll 32 switches at 1 kHz and render a 200+ LED strip at 60 fps.

The firmware is in [`../../firmware`](../../firmware) (PlatformIO). Which switch is which button
lives in `firmware/include/config_*.h`, the single source of truth; `shared/input_map.json` and the
`02_*` diagrams are generated from those headers.

## Diagrams (PNG + SVG; regenerate with `python docs/electronics/src/make_all.py`)
| File | What |
|---|---|
| [01_simple_joystick.png](01_simple_joystick.png) | **Start here.** One 3-axis joystick + button straight to a DevKitC-1, plus how to identify the unlabeled wires with a multimeter |
| [02_pilot_wiring.png](02_pilot_wiring.png) | Falcon Pilot full wiring: 74HC165 chain with every switch named, joystick, throttle, encoder |
| [02_ops_wiring.png](02_ops_wiring.png) | Falcon Ops full wiring |
| [02_command_wiring.png](02_command_wiring.png) | Falcon Command full wiring (dad's panel + overhead chips, LED data, the three crew-position senses) |
| [03_ws2812_power.png](03_ws2812_power.png) | LED strip: 5 V PSU sizing, power injection, 1000 µF, 330 Ω, 74AHCT125 level shifter, common ground |
| [04_seat_actuator.png](04_seat_actuator.png) | Crew position v0.3 (cradle recline: 2 actuators, pod: ONE actuator + torque tube): 20 A fuse, key + E-stop -> MOTION relay, 4 relays as 2 H-bridges, hold-to-run FLT/BRD, lock / lever / limit switches (1N5408 across each limit), pod-chin safety edge, NO microcontroller; three isolated read-only senses |

Also: [linux_setup.md](linux_setup.md) (udev, evtest/jstest-gtk, flashing, Windows joy.cpl), and
[`shared/led_protocol.md`](../../shared/led_protocol.md) (game -> LED serial protocol).

## Simple joystick test (today, no shift registers)
| Joystick wire | DevKitC-1 pin |
|---|---|
| X pot wiper | GPIO4 |
| Y pot wiper | GPIO5 |
| Twist pot wiper | GPIO6 |
| Throttle pot wiper (optional) | GPIO7 |
| Top button (one side) | GPIO15 (internal pull-up) |
| Top button (other side) | GND |
| One end of each pot | 3V3 (**never 5 V**) |
| Other end of each pot | GND |

Flash `pio run -e falcon_joystick_test -t upload` (or the normal `falcon_pilot`, which detects the
missing 74HC165 chain on its own and runs in fallback mode). Plug the **USB** port (not UART) into
the PC: it appears as "Falcon Pilot".

**Calibrate** (stored in flash, survives reflashing the same board): hold the top button (or the
board's BOOT button) while plugging in, keep holding ~1 s until the on-board LED turns **blue**
-> move every axis to both ends -> press -> **yellow**: let go of the stick -> press -> **green** x3 = saved.
Without calibration the firmware assumes full pot travel and takes the resting position at power-up as centre.

## Common pin plan (all three boards)
| Function | GPIO | Notes |
|---|---|---|
| Stick X / Y / twist | 4 / 5 / 6 | ADC1, pot ends on 3V3/GND |
| Throttle lever pot (Pilot) | 7 | ADC1 |
| Spare analog | 1, 2 | ADC1 |
| Stick top button | 15 | to GND, internal pull-up; also the calibration button |
| 74HC165 SH/LD (load) | 16 | all chips |
| 74HC165 CLK | 17 | all chips |
| 74HC165 QH data in | 18 | from chip #1; chip #k QH -> chip #(k-1) SER; last SER -> 3V3 |
| EC11 encoder 0 A / B | 11 / 12 | C pin to GND |
| EC11 encoder 1 A / B | 13 / 14 | Command: DIMMER knob |
| WS2812B data (Command) | 21 | via 74AHCT125 + 330 Ω |
| CRADLE_RECLINED sense (Command) | 39 | PC817 collector, active LOW, HID button 15 |
| POD_DOWN_LOCKED sense (Command) | 40 | PC817 collector, active LOW, HID button 26 |
| POD_UP_LOCKED sense (Command, optional) | 41 | PC817 collector, active LOW, HID button 27; leave open if not fitted |
| On-board RGB status LED | 48 (v1.0) / 38 (v1.1) | see `PIN_STATUS_RGB` |

Avoided: GPIO0/3/45/46 (strapping), 19/20 (USB), 26-37 (flash/PSRAM), 43/44 (UART log). GPIO39-41 are the
JTAG pins; they are free because the boards use the native USB port (no external JTAG).

## Parts list
### Controllers and logic
| Qty | Part | Notes |
|---|---|---|
| 3 | ESP32-S3-DevKitC-1 (N8 or N8R8) | must be the S3 with the "USB" + "UART" ports |
| 3 | USB-C data cables (1-2 m) | from each board's **USB** port to the PC; a powered USB 3 hub is fine |
| 10 (+2 spare) | 74HC165 DIP-16 + sockets | 3 Pilot, 3 Ops, 4 Command |
| 12 | 10 kΩ bussed resistor network, 9-pin SIP (e.g. 4609X-101-103) | one per 74HC165 (8 pull-ups); or 96 x 10 kΩ resistors |
| 20 | 100 nF ceramic capacitors | one per chip + spares |
| 5 | 10 µF electrolytic/ceramic | at each board and at the far end of the overhead cable |
| 1 | 74AHCT125 DIP-14 (or SN74AHCT1G125) | 3.3 V -> 5 V LED data |
| 2 | 330 Ω resistors | LED data series resistor (+1 spare) |
| 2 | 100 Ω resistors | series on CLK for the long overhead cable |
| 8 | 10 kΩ resistors | 3 opto pull-ups (cradle reclined, pod down-locked, pod up-locked), spares |
| 3 | perfboard / protoboard 7 x 9 cm, pin headers, Dupont + JST-XH connectors | one carrier per DevKitC-1 |
| 1 | CAT5/CAT6 patch cable | Falcon Command -> overhead console chain (CLK, LOAD, DATA, 3V3, GND pairs) |

### Panel controls (from the CAD layouts; counts include ~20 % spares)
| Qty | Part | Used for |
|---|---|---|
| 22 | 6 mm mini toggle ON-OFF (SPST/SPDT) | Pilot AIRBRAKE, NAV LIGHTS; Ops 5 power buses, CARGO BAY, DOCK CLAMP; overhead 9 checklist/lights |
| 2 | 6 mm mini toggle ON-OFF-ON (SPDT centre off) | Pilot FLAPS (+1 spare) |
| 4 | 6 mm mini toggle for printed guards | ENG ARM, JUMP ARM, EJECT (+1) |
| 8 | 22 mm arcade momentary (colours per CAD) | IGNITION, BOOST, ENGAGE, START, PAUSE, CAUTION RESET (+2) |
| 3 | 19 mm momentary | FIRE SUPPR, INTERCOM (+1) |
| 10 | 16 mm momentary | HORN, VIEW, SCAN PING, NAV TGT, 4 failures (+2) |
| 3 | 16 mm momentary (intercom, on the CAD panels since v0.3) | PILOT PTT (PILOT_SIDE), OPS PTT (OPS_SIDE), ALL-CALL / PA (CMD_A) |
| 3 | USB headsets with microphone (any brand; a serial number helps tell identical ones apart) | intercom, on the PC (not the boards) |
| 5 | EC11 rotary encoder with push + knob | FLIGHT ASSIST, OPS MODE, MISSION, DIMMER (+1) |
| 1 | 10 kΩ linear slide or rotary pot (B10K) | Pilot throttle lever |
| 1 | lever microswitch | landing gear lever (in the printed gear box) |
| 1 | 19 mm key switch, 2 position | MASTER POWER (game input) |
| 2 | your 3-axis joysticks with top button | Pilot, Ops |

### LED backlighting
| Qty | Part | Notes |
|---|---|---|
| 1 | WS2812B strip 5 V, 60 LED/m, 5 m reel (300 LEDs) | ~140 LEDs behind labels + ~60 lost in panel hops; 10 mm wide for the printed channels |
| 40 | 5 mm through-hole addressable LEDs, WS2812D-F5 (GRB) | the 32 status/indicator LED holes in the CAD panels, spliced into the same data line (`*_LED` ids) |
| 1 | 5 V 10 A (50 W) PSU, e.g. Mean Well LRS-50-5 | 242 LEDs x 60 mA = 14.5 A absolute worst case; firmware caps at 8 A |
| 1 | 1000 µF 10 V electrolytic | across 5 V/GND at the strip input |
| 32 | 100 nF ceramic | one at each 5 mm WS2812D-F5 (VDD-GND) |
| 1 | 10 A fuse + holder (blade or 5x20) | PSU output |
| - | 16 AWG red/black (trunk), 18 AWG (injection drops), 3-pin JST-SM pigtails | power injection at start, middle, end |

### Crew position v0.2: cradle recline + pod (hardwired, see diagram 04 and `frame/BOM.md`)
| Qty | Part | Notes |
|---|---|---|
| 2 | 12 V linear actuators, 10" stroke, >= 1500 N, self-locking, <= 10 mm/s | cradle (PUSH to recline) |
| 1 | 12 V linear actuator, 12" (300 mm) stroke, >= 1500 N, self-locking, <= 10 mm/s, 420 mm retracted | pod, left casing, drives both cheeks through a steel torque tube (EXTEND to lower, RETRACT to raise; lift-biased gas struts) |
| 1 | 12 V 20 A PSU, enclosed, mains fused | |
| 1 | 20 A blade fuse + holder (F1) | at the PSU |
| 1 | 1 A blade fuse + holder (F2) | relay coil supply |
| 1 | 19 mm key switch, 2 position (MOTION) | drives the MOTION relay coil; key out = no motion |
| 1 | 22 mm mushroom E-stop, NC, latching, twist release | on CMD_B, in series with the key |
| 5 | 12 V 30 A automotive relays SPDT (Bosch type) + sockets | K0 MOTION, K1/K2 cradle H-bridge, K3/K4 pod H-bridge |
| 5 | 1N4007 | flyback diode across each relay coil |
| 1 | DPDT (ON)-OFF-(ON) momentary toggle, 12 mm bushing | CREW POS FLT / BRD hold-to-run on CMD_B (switches coil current only) |
| 8 | V-15 roller-lever micro switches 15 A + printed `limit_switch_mount` | motor path: cradle UPRIGHT / RECLINED limits, ONE pod limit set UP / DOWN (left, driven cheek), CRADLE_RECLINED interlock (L + R), POD_UP_LOCKED (both pawls), release lever |
| 8 | 1N5408 diodes (3 A, 200 A surge) | across each motor-path limit switch, so you can always drive back (use 6A10 if each actuator draws > 3 A) |
| 1 | pressure-sensitive safety edge, NC, ~900 mm, with profile | pod chin, in series with the pod DOWN coil |
| 3 | lever micro switches (NO; V-15 roller + `limit_switch_mount`) | READ-ONLY position senses (3): cradle reclined, pod down + locked (pawl in the DOWN notch), pod up + locked (optional) |
| 3 | PC817 optocoupler + 2.2 kΩ ½ W | isolated senses to Falcon Command GPIO39 / 40 / 41 (10 kΩ pull-ups above) |
| - | 14 AWG wire PSU -> relays -> actuators, 20 AWG coils / senses | |

## Assumptions to confirm
* "3-way" joysticks are three **potentiometers** (X, Y, twist) + one button. If they turn out to be
  switch (digital) sticks, wire each direction to a 74HC165 input or spare GPIO instead and map them
  as buttons in the config header.
* Pot values 5-100 kΩ are all fine at 3.3 V.
* DevKitC-1 v1.0 has its RGB LED on GPIO48 (v1.1: GPIO38, change `PIN_STATUS_RGB`).
* USB IDs 1209:0003/0004/0005 are pid.codes *test* PIDs: fine for a private build, not for products.
* LED segment map is a placeholder: label ids and order from CAD's `shared/panel_labels.json`
  (LED count = CAD's estimate at 60/m), 6-LED gaps between panels, and each panel's 5 mm status LEDs
  right after its labels. Measure the real strip with `FIND <index>` and edit `shared/led_segments.json`
  (or re-run `firmware/tools/make_placeholder_segments.py`), then rebuild Falcon Command.
* The 5 mm status LED holes in the CAD panels are driven as WS2812D-F5 addressable LEDs on the same
  data line (no extra firmware outputs). If you prefer plain LEDs, they would need a 74HC595 chain instead.
