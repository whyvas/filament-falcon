# Falcon Command LED protocol (game -> Falcon Command)

Contract between `game/` and `firmware/`. Falcon Command enumerates as a composite USB device:
an HID joystick **plus** a USB CDC serial port. The game drives the single WS2812B strip through
that serial port with short text lines.

## Finding the port
| OS | Port |
|---|---|
| Linux | `/dev/falcon-command` (udev rule in `firmware/udev/`), else glob `/dev/serial/by-id/*Falcon_Command*`, else the `/dev/ttyACM*` whose USB VID:PID is `1209:0005` |
| Windows | the `COMx` whose hardware ID contains `VID_1209&PID_0005` |

Serial settings: 115200 8N1 (CDC ignores the baud rate, any value works). **Assert DTR** when opening
(most serial libraries do by default): the firmware treats DTR as "game connected". When the game closes
the port (DTR drops), the strip falls back to the idle glow.

## Framing
* ASCII, one command per line, terminated by `\n` (`\r\n` also accepted). Max 127 characters per line.
* Keywords and label ids are case-insensitive. Fields separated by single spaces.
* Colours are decimal `0..255`. The firmware applies global brightness, the dimmer pot and a current limit on top.
* Changes are rendered at 60 fps; there is no "show" command. Sending the same state again is harmless.
* By default the board stays silent on success (so the game can stream many lines per frame without
  reading). Errors always produce `ERR <reason>`. `ACK ON` makes every command answer `OK`.

## Commands
| Command | Effect | Reply |
|---|---|---|
| `SEG <LABEL_ID> <r> <g> <b> [MODE]` | set every LED of a label (ids in `shared/led_segments.json`: the CAD label ids from `shared/panel_labels.json`, plus `<ID>_LED` for the 5 mm status LEDs) | none / `OK` |
| `ALL <r> <g> <b> [MODE]` | set the whole strip | none / `OK` |
| `IDX <start> <count> <r> <g> <b> [MODE]` | set raw LED indices (for mapping / tests) | none / `OK` |
| `CLEAR` | all LEDs off | none / `OK` |
| `IDLE` | back to the idle glow (all labels warm white, dim) | none / `OK` |
| `BRIGHT <0-255>` | global brightness (default 96) | none / `OK` |
| `ANIM BOOT` / `ANIM ALERT` / `ANIM STOP` | play the boot sweep / 3 red flashes over everything, or stop | none / `OK` |
| `FIND <index>` | light ONLY LED `<index>` white (use it to measure the real segment map) | `FIND <index>` |
| `MAP?` | dump the compiled-in segment map | `MAP <ID> <start> <count>` per label, then `END <segments> <leds>` |
| `ID?` | identify | `ID FALCON_COMMAND <fw-version> LEDS <n> SEGMENTS <m>` |
| `STATE?` | seat sensor + brightness | `STATE SEAT UP\|DOWN BRIGHT <b> DIMMER <0-255>` |
| `PING` | liveness | `PONG` |
| `ACK ON` / `ACK OFF` | per-command `OK` replies on/off | `OK` |

`MODE` is one of:
| Mode | Look | Suggested use |
|---|---|---|
| `SOLID` (default) | steady | normal "on" / selected |
| `BLINK` | 1 Hz, 50 % | waiting for this input (checklist step) |
| `FAST` | 4 Hz | warnings, MASTER CAUTION, fire |
| `PULSE` | 0.5 Hz breathe | armed / standby (JUMP ARM, ENGINE ARM) |
| `OFF` | dark | label not available |

## Unsolicited events (board -> game)
| Line | Meaning |
|---|---|
| `EVT SEAT UP` / `EVT SEAT DOWN` | the seat-up sense switch changed (also HID button 15 on Falcon Command) |
| `ERR <reason>` | the previous line was rejected (`unknown label`, `bad colour`, `bad mode`, `bad index`, `line too long`, `unknown command`) |

## Boot / idle behaviour
1. Power-up: cyan comet sweeps from LED 0 to the end of the strip (1.4 s), then every label flashes
   white and fades into its current state (1 s).
2. Until the game sends anything: **idle glow** (all labels warm white, dim) so the panels are readable.
3. Game closes the port: idle glow again.

## Example session
```
> ID?
< ID FALCON_COMMAND 0.1.0 LEDS 238 SEGMENTS 92
> BRIGHT 120
> CLEAR
> SEG BATTERY 0 255 0
> SEG BATTERY_LED 0 255 0
> SEG FUEL_PUMPS 255 160 0 BLINK
> SEG ENG_ARM 255 0 0 PULSE
> SEG MASTER_CAUTION_LED 255 0 0 FAST
> SEG NOT_A_LABEL 1 2 3
< ERR unknown label
< EVT SEAT UP
```

## Quick manual test (Linux)
```
picocom -b 115200 --omap crlf --echo /dev/falcon-command     # type commands, Ctrl-A Ctrl-X to quit
```
Note: a one-shot `printf ... > /dev/falcon-command` opens and immediately closes the port, and closing
drops DTR, so the strip goes straight back to the idle glow. Keep the port open (picocom, the game).
The same protocol is also accepted on the board's UART debug port (the "UART" USB-C connector) for bench tests.
