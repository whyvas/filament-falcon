# Linux Mint (and Windows) setup and verification

## 1. udev rules (once)
```bash
sudo cp firmware/udev/99-filament-falcon.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger
# unplug + replug the three boards
ls -l /dev/falcon-command /dev/serial/by-id/      # Falcon Command's CDC serial port
```
The rule gives everyone read/write on Falcon Command's serial port (so the Godot game can open it
without root or the `dialout` group), creates the stable name `/dev/falcon-command`, and stops
ModemManager from probing it. Alternative without the rule: `sudo usermod -aG dialout $USER` and log out/in.

## 2. Is it enumerating?
```bash
lsusb | grep 1209
#   ID 1209:0003 Filament Falcon Falcon Pilot
#   ID 1209:0004 Filament Falcon Falcon Ops
#   ID 1209:0005 Filament Falcon Falcon Command
dmesg -w            # plug a board in: "input: Filament Falcon Falcon Pilot as /devices/..." and for Command also "cdc_acm ... ttyACM0"
cat /proc/bus/input/devices | grep -A4 Falcon
```

## 3. Test the joystick
```bash
sudo apt install evtest joystick jstest-gtk
evtest                      # pick "Filament Falcon Falcon Pilot"; move the stick -> ABS_X / ABS_Y / ABS_RZ,
                            # throttle -> ABS_THROTTLE, top button -> BTN_TRIGGER (button 0)
jstest /dev/input/js0       # numbers: axis 0..7, button 0..63
jstest-gtk                  # GUI: shows all three Falcon devices with live bars
```
Axis/button numbering in jstest, SDL and Godot matches `shared/input_map.json`.
(Linux maps HID buttons 17+ to BTN_TRIGGER_HAPPY*, that's normal.)

## 4. Test Falcon Command's LEDs
```bash
sudo apt install picocom
picocom -b 115200 --omap crlf --echo /dev/falcon-command
ID?
ALL 0 0 255 PULSE
FIND 17
MAP?
```
See `shared/led_protocol.md` for every command.

## 5. Debug log
Each DevKitC-1 has a second USB-C port labelled **UART**. Plug it in too and run
`pio device monitor -b 115200` (or `picocom -b 115200 /dev/ttyUSB0`) to see boot messages,
calibration prompts and the "74HC165 chain detected / FALLBACK" message. Build with
`-DFF_DEBUG_DUMP` added to `build_flags` to stream raw axis values every 500 ms.

## 6. Flashing
* Easiest: plug the **UART** port and run `cd firmware && pio run -e falcon_pilot -t upload`.
* Native **USB** port only: hold **BOOT**, tap **RESET**, release BOOT (board enters ROM download
  mode and shows up as `/dev/ttyACM*`), run the upload, then tap RESET.
* Joystick-only test: `pio run -e falcon_joystick_test -t upload`.

## 7. Windows check
1. Plug in the board's **USB** port. No drivers needed (HID + the in-box `usbser` CDC driver).
2. `Win+R` -> `joy.cpl` -> "Falcon Pilot" / "Falcon Ops" / "Falcon Command" -> Properties.
   The test page shows X/Y axes, Z rotation (twist), Slider (throttle/dimmer) and buttons.
   joy.cpl only *displays* buttons 1-32; buttons 33-64 still work in games (DirectInput/SDL).
3. Device Manager -> Ports: "USB Serial Device (COMx)" is Falcon Command's LED port.
4. If you change the HID descriptor but keep the PID, Windows may cache the old layout: uninstall the
   device in Device Manager (View -> Show hidden devices) and replug.
