# Filament Falcon electronics

Three ESP32-S3 boards, each a real USB HID joystick (no drivers on Linux or Windows):

| Board | USB name | VID:PID | Where | Inputs | Extra |
|---|---|---|---|---|---|
| ESP32-S3-DevKitC-1 #1 | **Falcon Pilot** | 1209:0003 | left kid, PILOT | 3-axis stick + trigger, throttle pot, 2 x 74HC165 (11 used), 1 EC11 (FLIGHT ASSIST) | |
| ESP32-S3-DevKitC-1 #2 | **Falcon Ops** | 1209:0004 | right kid, OPS | 3-axis stick + trigger, 2 x 74HC165 (13 used), 1 EC11 (OPS MODE) | |
| ESP32-S3-DevKitC-1 #3 | **Falcon Command** | 1209:0005 | dad + overhead console | 4 x 74HC165 (21 used), 2 EC11 (MISSION, DIMMER knob), seat-up opto | USB CDC serial, drives the ONE WS2812B data line |

The control set matches the CAD panel layouts (`cad/tools/layouts.py`, `shared/panel_labels.json`):
flight-assist mode, ops mode and mission select are EC11 encoders with push (the game keeps the
selected mode and lights the matching label), the dimmer is an EC11 "virtual knob" (firmware keeps a
0-255 level, reports it as an axis and dims the strip), NAV TGT is a push button, FLAPS is an ON-OFF-ON toggle.

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
| [02_command_wiring.png](02_command_wiring.png) | Falcon Command full wiring (dad's panel + overhead chips, LED data, seat sense) |
| [03_ws2812_power.png](03_ws2812_power.png) | LED strip: 5 V PSU sizing, power injection, 1000 µF, 330 Ω, 74AHCT125 level shifter, common ground |
| [04_seat_actuator.png](04_seat_actuator.png) | Seat lift: key, E-stop, fuse, DPDT hold-to-run, limit switches with diodes, NO microcontroller; isolated read-only seat-up sense |

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
| Seat-up sense (Command) | 39 | PC817 collector, active LOW |
| On-board RGB status LED | 48 (v1.0) / 38 (v1.1) | see `PIN_STATUS_RGB` |

Avoided: GPIO0/3/45/46 (strapping), 19/20 (USB), 26-37 (flash/PSRAM), 43/44 (UART log).

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
| 6 | 10 kΩ resistors | opto pull-up, spares |
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
| 5 | EC11 rotary encoder with push + knob | FLIGHT ASSIST, OPS MODE, MISSION, DIMMER (+1) |
| 1 | 10 kΩ linear slide or rotary pot (B10K) | Pilot throttle lever |
| 1 | lever microswitch | landing gear lever (in the printed gear box) |
| 1 | 19 mm key switch, 2 position | MASTER POWER (game input) |
| 2 | your 3-axis joysticks with top button | Pilot, Ops |

### LED backlighting
| Qty | Part | Notes |
|---|---|---|
| 1 | WS2812B strip 5 V, 60 LED/m, 5 m reel (300 LEDs) | ~136 LEDs behind labels + ~60 lost in panel hops; 10 mm wide for the printed channels |
| 40 | 5 mm through-hole addressable LEDs, WS2812D-F5 (GRB) | the 32 status/indicator LED holes in the CAD panels, spliced into the same data line (`*_LED` ids) |
| 1 | 5 V 10 A (50 W) PSU, e.g. Mean Well LRS-50-5 | 238 LEDs x 60 mA = 14.3 A absolute worst case; firmware caps at 8 A |
| 1 | 1000 µF 10 V electrolytic | across 5 V/GND at the strip input |
| 32 | 100 nF ceramic | one at each 5 mm WS2812D-F5 (VDD-GND) |
| 1 | 10 A fuse + holder (blade or 5x20) | PSU output |
| - | 16 AWG red/black (trunk), 18 AWG (injection drops), 3-pin JST-SM pigtails | power injection at start, middle, end |

### Seat lift (hardwired, see diagram 04)
| Qty | Part | Notes |
|---|---|---|
| 2 | 12 V linear actuators (stroke/force per frame design), preferably with built-in limit switches | |
| 1 | 12 V PSU, >= 1.5 x total actuator running current (e.g. 12 V 10 A) | |
| 1 | DPDT momentary (ON)-OFF-(ON) switch rated >= stall current (e.g. 20 A rocker/toggle) | hold-to-run, only at dad's seat |
| 1 | key switch rated for the actuator current, or a small key switch + 12 V 30 A automotive relay | actuator master |
| 1 | NC mushroom E-stop | strongly recommended |
| 1 | blade fuse holder + fuse (~1.25 x running current, e.g. 7.5 A) | |
| 2 (per actuator set) | lever microswitches, NC contact rated >= motor current (e.g. 16 A V-type) | UP and DOWN limits |
| 2 (per set) | 6A10 diodes (6 A, 1000 V) | across the limit switches |
| 1 | small lever microswitch (NO) | seat-up sense |
| 1 | PC817 optocoupler + 2.2 kΩ ½ W + 10 kΩ | isolated seat-up sense to Falcon Command |
| - | 16 AWG wire for motor circuit | |

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
