# Filament Falcon firmware (ESP32-S3, PlatformIO, Arduino + TinyUSB)

One codebase, three boards. Each board is a USB HID joystick with 8 x 16-bit axes and 64 buttons.
Falcon Command is also a USB CDC serial port that drives the single WS2812B strip.

```bash
pip install platformio          # or use a venv
cd firmware
pio run                         # builds falcon_pilot, falcon_ops, falcon_command
pio run -e falcon_pilot -t upload           # flash (plug the board's UART port, or BOOT+RESET on USB)
pio run -e falcon_joystick_test -t upload   # joystick-only test build (ignores shift registers)
pio device monitor -b 115200                # debug log on the UART port
```

| Env | USB product | PID | Notes |
|---|---|---|---|
| `falcon_pilot` | Falcon Pilot | 0x0003 | HID |
| `falcon_ops` | Falcon Ops | 0x0004 | HID |
| `falcon_command` | Falcon Command | 0x0005 | HID + CDC, WS2812B on GPIO21 |
| `falcon_joystick_test` | Falcon Pilot | 0x0003 | forced fallback: only the stick + top button |

## Layout
```
include/board_pins.h      default pin plan (same on all boards)
include/config_pilot.h    which switch/axis is which HID button/axis  <- EDIT THESE
include/config_ops.h
include/config_command.h
include/led_segments_gen.h  generated from ../shared/led_segments.json at every build
src/main.cpp              USB setup + main loop
src/falcon_hid.*          custom HID joystick descriptor (64 buttons, 8 x 16-bit axes)
src/axes.*                ADC oversampling, EMA smoothing, calibration, deadzone
src/inputs.*              74HC165 chain (with auto-detect), debouncing, EC11 encoders (interrupts)
src/calibration.*         hold-button-at-boot calibration, saved in NVS
src/leds.*                Falcon Command: strip rendering, effects, current limit, serial protocol
tools/gen_led_map.py      led_segments.json -> led_segments_gen.h (PlatformIO pre-script)
tools/gen_input_map.py    config_*.h -> ../shared/input_map.json (run after editing configs)
tools/make_placeholder_segments.py   rebuild the placeholder LED map (reads shared/panel_labels.json if present)
udev/99-filament-falcon.rules
```

## Behaviour
* **Axes**: ADC1, 11 dB attenuation, 16x oversampling, EMA smoothing, per-axis deadzone, edge snap.
  BIPOLAR axes (stick) map min/centre/max to -32767/0/+32767; UNIPOLAR (throttle, dimmer) map
  min/max to -32767/+32767. Axes that never moved during calibration report 0 ("not wired").
* **Buttons**: 74HC165 chain read at loop rate (~1-2 kHz), 6 ms debounce. Toggles are reported as
  held buttons while ON; each encoder click becomes a 35 ms button pulse (queued, so fast spins are not
  lost). An encoder whose `FF_ENC` has an axis (Command's DIMMER) is a virtual knob instead: a 0-255
  level, 8 per click, saved to flash 3 s after the last click, reported on that HID axis.
* **Fallback**: the last 74HC165's SER pin is tied to 3V3. If the firmware does not see those 1s after
  the chain, there is no chain, and it ignores shift-register buttons (joystick-only mode). It re-checks
  continuously, so you can wire the chain later without reflashing. Status LED: green = chain found,
  blue = fallback.
* **Report rate**: on change up to 1 kHz, plus a 100 ms keep-alive.
* **Calibration**: see docs/electronics/README.md.

## Adding or moving a switch
1. Wire it to a free 74HC165 input (or a free GPIO).
2. Add/edit one `FF_BTN(...)` line in the board's config header (HID index must be unique, 0-63).
3. `python3 tools/gen_input_map.py` (updates `shared/input_map.json` for the game) and
   `python3 ../docs/electronics/src/make_all.py` (updates the 02 diagrams).
4. `pio run -e <board> -t upload`.
