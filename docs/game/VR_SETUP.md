# VR spacewalks: Meta Quest 3 on Linux Mint 22 (WiVRn)

The fourth crew member goes **outside**: wearing a Meta Quest 3 and standing in a clear area *outside* the
cockpit frame, they do a spacewalk (EVA) around the Falcon while Pilot, Ops and the Commander watch them in
the window views and on the console cameras, and talk to them on the intercom.

- [Platform choice: WiVRn](#platform-choice-wivrn-not-alvr)
- [Architecture](#architecture-a-separate-vr-process)
- [Setup on Mint 22, step by step](#setup-on-linux-mint-22-step-by-step)
- [Playing](#playing)
- [Safety](#safety)
- [Performance](#performance-rx-6800-xt)
- [Troubleshooting](#troubleshooting)
- [What was tested and what still needs a headset](#what-was-tested-and-what-still-needs-a-headset)

## Platform choice: WiVRn (not ALVR)

| | **WiVRn** (chosen) | ALVR |
|---|---|---|
| OpenXR on Linux | Its own OpenXR runtime (Monado inside). Godot talks to it directly through the standard OpenXR loader. | Is a **SteamVR driver**: needs Steam + SteamVR running, and SteamVR on Linux (AMD) is the weakest link (reprojection bugs, frame-pacing problems, updates breaking it). |
| Install on Mint 22 | One Flatpak from Flathub (`io.github.wivrn.wivrn`), dashboard with a setup wizard; the headset app is in the Meta Store. | Steam, SteamVR, the ALVR launcher, the ALVR headset app (sideloaded or store). |
| USB cable | Supported: `adb reverse` over the cable, button in the dashboard. | Supported (adb forwarding). |
| Audio | Creates a **WiVRn** speaker and a **WiVRn(microphone)** source in PipeWire while connected, so our intercom can use them like a 4th headset. | Similar virtual devices, through SteamVR. |
| Launch | Lists `.desktop` files with `X-WiVRn-VR` in the headset's app launcher. | Through Steam. |
| Encoders on the RX 6800 XT | VA-API H.264/H.265/AV1 (RDNA2 encodes H.265 well), foveated encoding. | VA-API too. |

WiVRn is the shorter and more robust path for a **native Godot 4 OpenXR app on AMD + Linux**: no Steam in
the chain, one process less, and the OpenXR runtime is selected the standard way
(`~/.config/openxr/1/active_runtime.json`). The PPA builds only target Ubuntu 26.04, not Mint 22 (noble), so
use the **Flatpak**.

## Architecture: a separate VR process

```
 ┌────────────── cockpit game (godot --path game) ──────────────┐     UDP 127.0.0.1:47820      ┌──── EVA client (godot --xr-mode on -- --eva-client) ────┐
 │ 4 windows: LEFT / RIGHT windows, kids' console, Commander    │ ◄─── pose ~90 Hz ("st") ──── │ OpenXR (WiVRn) → Quest 3, 90 Hz                         │
 │ Ship physics, missions, robotic arm, Mission Control         │ ──── world 30 Hz + commands ─►│ runs the spacewalk sim locally (zero latency in the     │
 │ Eva autoload: mirrors the astronaut with a 45 ms             │      (ship state, arm, start/ │ headset), streams head/hands/body/events                │
 │ interpolation buffer, telemetry, events (knock, wave)        │       abort, mission)         │ audio → "WiVRn" speaker (suit sounds)                   │
 │ OpenXR NEVER loaded here                                     │                               │ no OpenXR runtime → flat window with keyboard/gamepad   │
 └──────────────────────────────────────────────────────────────┘                               └─────────────────────────────────────────────────────────┘
          ▲ falcon_ics.py: PILOT / OPS / COMMANDER USB headsets + SPACEWALKER = WiVRn speaker + mic (suit radio)
```

**Why not the same process?** The cockpit already drives four windows at 60–144 Hz, each with its own
off-axis frustum. Turning on OpenXR in that process would make the XR compositor's frame pacing (90 Hz,
blocking `xrWaitFrame`) drive the whole main loop: the four windows would stutter, a headset disconnect or
runtime crash would take the cockpit down with it, and Godot only allows one XR interface for the main
viewport. A second process of the **same project** is more robust:

- the cockpit stays exactly as smooth as before, with or without a headset;
- a WiVRn crash or headset unplug only stops the client: after 4 s without packets the spacewalker is
  recalled (the EVA ends, the crew keeps flying) and LAUNCH VR CLIENT + START EVA start a new one;
- the cockpit runs with `openxr/enabled=false` and never needs an OpenXR runtime;
- the same EVA code runs in both processes, so the flat mode is the same game.

**Pose sync.** The client sends one packet per rendered frame (~85–90 Hz measured, ≥ 60 Hz required):
head, both hands with grip/point state, body up, velocity, lamp, jet, tether, telemetry and events.
The cockpit buffers packets and renders 45 ms in the past, interpolating positions (lerp) and rotations
(slerp), so the astronaut moves smoothly in the 144 Hz/75 Hz windows even if a packet is late or lost
(the last pose is held). The test measures the stream rate and the largest frame-to-frame jump.

**Who sees the astronaut.** The avatar lives in the shared world, in the ship frame, so it appears in
every view that sees that spot: the LEFT/RIGHT window views (the near clip plane moves in to 0.2 m during an
EVA so a glove on the glass still renders), the docking camera, the arm camera, the chase view and the EVA
DRONE feed. The helmet is on its own render layer (`EVA_HEAD_LAYER`) and the torso/legs on another
(`EVA_BODY_LAYER`): the HELMET CAM and the VR headset hide them (you never see the inside of your own helmet),
but arms and gloves stay visible to the wearer.

**Avatar.** Procedural EMU-style suit: hard upper torso, PLSS backpack with the SAFER jetpack, display and
control module, flag patch, red stripes (EV1), helmet with a gold visor, two helmet lamps (real spot lights +
glow), gloves with curling fingers and a pointing index. Driven by head + both controller poses: two-bone IK
for the arms (shoulders from the inferred torso), the torso follows the head with lag, the legs trail in
zero-g and walk on the Moon. Waves (side-to-side hand motion), points (grip without the trigger touched) and
contacts with the canopy glass (knock = fast tap, palm = hand held on the glass) are detected and sent as
events: the crew hears the knock, sees a frost hand print fade on the glass, and the Commander gets a log line.

## Setup on Linux Mint 22, step by step

Do this once. Commands are for a terminal on the cockpit PC.

**1. Install WiVRn (Flatpak) and its prerequisites**

```bash
sudo apt update
sudo apt install flatpak android-tools-adb android-sdk-platform-tools-common avahi-daemon
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub io.github.wivrn.wivrn
sudo systemctl enable --now avahi-daemon
# only if ufw is on (sudo ufw status):
sudo ufw allow 5353/udp
sudo ufw allow 9757
```

`android-sdk-platform-tools-common` installs the udev rules that let `adb` see the Quest without root.
Log out and back in once so your user gets the `plugdev` permissions.

**2. Quest 3: developer mode (for the USB cable)**

1. In the **Meta Horizon** phone app: Menu → Devices → your Quest 3 → Headset settings → **Developer mode** ON
   (Meta asks you to create a free developer organization the first time).
2. Reboot the headset. Plug it into the PC with a USB-C cable (USB 3 port, a data cable, not a charge-only one).
3. In the headset, accept **Allow USB debugging** (tick "Always allow from this computer").
4. On the PC: `adb devices` must list the headset as `device` (not `unauthorized`).

**3. Install the WiVRn app on the Quest**

Easiest: the **WiVRn** app from the Meta Store (Quest 3 is supported). Or start the dashboard
(`flatpak run io.github.wivrn.wivrn`, or "WiVRn Server" in the Mint menu) and follow its **wizard**, which
can sideload the matching app over the cable (it then appears under *Unknown sources*). The headset app and
the PC server versions must match; the store and the Flatpak usually do.

**4. Connect over USB**

1. Start the dashboard on the PC: `flatpak run io.github.wivrn.wivrn` → **Start** the server.
2. In the dashboard press **Connect by USB** (it runs `adb reverse` and starts the headset app for you).
   By hand, the same thing is:
   ```bash
   adb reverse tcp:9757 tcp:9757
   adb shell am start -a android.intent.action.VIEW -d "wivrn+tcp://localhost" org.meumeu.wivrn
   ```
3. Turn the Quest's Wi-Fi off while using the cable, so the stream cannot fall back to Wi-Fi.
4. In the headset app, **Settings**: enable the **microphone** (needed for the intercom), and allow hand
   tracking if you want to play without controllers.

**5. Check the OpenXR runtime**

While the headset is connected, WiVRn makes itself the active OpenXR runtime:

```bash
ls -l ~/.config/openxr/1/active_runtime.json     # → points into ~/.local/share/flatpak/... or /var/lib/flatpak/.../wivrn
```

If another runtime (Monado, SteamVR) owns that file, either close it, or point the game at WiVRn only:
set `xr_runtime_json` in the `[eva]` section of `~/.local/share/filament-falcon/falcon_settings.cfg` to the
WiVRn manifest path (the game passes it as `XR_RUNTIME_JSON` to the VR client). Commander → SETUP and
Commander → EVA show what the game found ("OpenXR runtime: …").

**6. Audio devices (intercom seat 4)**

With the headset connected, `pactl list short sinks` shows a **WiVRn** sink and `pactl list short sources`
a **WiVRn(microphone)** source (only if the mic is enabled in the headset app). Do **not** make them the
system default devices (the WiVRn docs suggest it for games, but here the intercom routes them): the
intercom helper finds them by name and puts them on the **SPACEWALKER** seat automatically (Commander → ICS).
`python3 game/tools/falcon_ics.py --list` lists them as "Meta Quest 3 (WiVRn audio)".

**7. Optional: start the spacewalk from inside the headset**

```bash
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 game/tools/install_vr_launcher.sh
```

This adds "Filament Falcon - Spacewalk (VR)" (`Categories=…;X-WiVRn-VR;`) to `~/.local/share/applications`,
so WiVRn lists it in the headset's launcher when no VR app is running. `--remove` takes it out.

## Playing

1. Start the cockpit as usual: `game/run.sh`.
2. Put the Quest on, connected (step 4).
3. Commander → **EVA**: pick a spacewalk, **LAUNCH VR CLIENT** (or `game/run.sh --eva-vr` in a second
   terminal, or the headset launcher). The status line reads "VR client connected · <runtime> · <headset> · 90 Hz".
4. **START EVA** (driver AUTO picks the VR headset when the client reports one, else the on-screen mode).
   The SPACEWALK chip in the top bar and the console's **EVA** tab light up.

**Spacewalks** (which ones are offered depends on where the ship is):

| Spacewalk | Where | Tasks |
|---|---|---|
| WINDOW VISIT | in orbit | climb the handrails to the nose, wave at the crew, knock on the window, back in |
| ANTENNA SWAP | in orbit (docking) | take the new antenna from the cargo bay, carry it along the rails, swap the broken one at the mount, back in |
| ROCK SAMPLE + BEACON | asteroid field | jet to the boulder, take a sample, plant the blinking beacon |
| MOONWALK | landed on the Moon | climb down, plant the flag, collect three rocks (1/6 g hops), back up |
| CANADARM RESCUE | in orbit, cargo doors open | the jetpack is empty: **Ops** flies the arm to the drifting spacewalker, who grabs the foot restraint and rides to the hatch while the **Pilot** holds attitude (if the ship rotates, the voice calls "Pilot, hold attitude!" and the score drops) |

With **EVA IN MISSIONS** on, the missions add a spacewalk objective by themselves near the end of launch,
docking, asteroids and lunar (engines are locked out and time warp stays at 1× while someone is outside).

**VR controls (Touch controllers)**

| Control | Action |
|---|---|
| Grip (either hand) | grab a handrail, the arm's foot restraint, a tool or a sample. Pull with your arm to move along the rails. |
| Grip with your index off the trigger | point (visible from the windows) |
| Trigger | use: work the antenna latch, take a sample, plant the flag |
| Left stick | SAFER jetpack, gentle thrust relative to where you look (uses gas) |
| Right stick up/down | jet up/down; right stick left/right: snap turn (15/30/45°, Commander → EVA) |
| Left Y/B | stop (kill drift with the jetpack); right B: helmet lamp; right A: hop (Moon) |
| Left X | push-to-talk on the intercom (the seat can also be VOX) |
| Hold Menu 1 s | recenter |
| Hand tracking (controllers put down) | pinch or fist = grab, a pinch without a fist = use, fist with the index out = point |

A wrist display on the left glove shows O2, battery, gas, tether and the current task. Waving, pointing
and touching the window just work: move your real hands.

**On-screen mode (no headset).** Commander → EVA → driver ON SCREEN, START EVA, then click the helmet cam
to fly the spacewalker: `W A S D` move along rails / jet, `R F` up/down, mouse or `Q E` look, `Space` grab,
`Enter` use, `G` wave, `K` knock, `P` point, `L` lamp, `X` stop, `C` helmet cam / drone, `Esc` releases the
keyboard. A gamepad works too (sticks, A grab, X use, Y wave, B stop, LB knock, RB lamp, Back camera).
Near the window, **Enter** glides you to the window pose.

**Comfort.** No camera motion is ever forced on the wearer: only your own pulls and jetpack thrust move you;
ship rotation (while riding the arm) is shown with the vignette. Options on Commander → EVA: snap turn
angle, vignette OFF/LOW/MED/HIGH (narrows the view while you accelerate), STANDING/SEATED (seated adds the
height offset), tether 10/20/30 m.

## Safety

- **Clear 2 × 2 m of floor OUTSIDE the cockpit frame.** The spacewalker must never stand inside the frame,
  near the pod's swing path or the cradle actuator: the headset hides them.
- **Guardian / boundary ON** (stationary or room-scale boundary drawn around the clear area, not across the
  frame).
- A grown-up watches the spacewalker; the USB cable runs behind them, not across the cockpit entrance.
- The Commander can end the spacewalk at any time (ABORT EVA); taking the headset off is always fine.
- Short sessions (10–15 minutes) for kids; Meta's age guidance for Quest applies.

## Performance (RX 6800 XT)

- **90 Hz** refresh in the headset app (72 Hz if the PC is also driving the 144 Hz windows and frames drop).
- WiVRn dashboard: encoder **VA-API, H.265 (HEVC)**, bitrate **50–100 Mb/s** over USB, **foveated encoding
  ~0.5** (sharp centre, cheaper edges).
- The VR client uses its own graphics preset (Commander → EVA → VR QUALITY, default MED = the game's MEDIUM
  preset). The cockpit's four windows keep their own preset.
- With the cockpit on ULTRA, set VR QUALITY to LOW if the headset reports dropped frames.
- USB 3 port directly on the motherboard; Quest Wi-Fi off.

## Troubleshooting

| Problem | Try |
|---|---|
| Commander → EVA says "No OpenXR runtime (VR off)" | WiVRn not connected: start the dashboard server, connect the headset (step 4), then LAUNCH VR CLIENT again. `ls -l ~/.config/openxr/1/active_runtime.json` |
| The client starts as a flat window | Same as above (the client falls back to the desktop when OpenXR fails); its terminal prints the reason |
| `adb devices` shows `unauthorized` | Put the headset on and accept USB debugging; `adb kill-server; adb devices` |
| `adb devices` shows nothing | another cable/port; developer mode on; `sudo apt install android-sdk-platform-tools-common`, log out and in |
| Headset app can't find the PC | `systemctl status avahi-daemon`; ufw ports 5353/udp and 9757; or use Connect by USB |
| Black borders / smearing / high latency | Wi-Fi off on the headset when cabled; lower bitrate; H.265; VR QUALITY LOW |
| No SPACEWALKER audio in the ICS | `pactl list short sinks` must show WiVRn; enable the mic in the headset app (Settings); ICS → RESCAN. Fallback: plug a 4th USB headset and pick it for SPACEWALKER with ◀ ▶ |
| Crew can't see the astronaut | they are on the other side of the ship: the window views look forward/left/right, the console CAMERAS page has the docking and arm cameras, and the Commander has the DRONE feed |
| VR client lost (crash / unplug) | after 4 s the spacewalker is recalled ("Lost the VR headset link"); LAUNCH VR CLIENT, then START EVA again |
| Logs | WiVRn: `~/.var/app/io.github.wivrn.wivrn/.local/state/wivrn/`; game: the terminal, and the EVA log on Commander → EVA |

## What was tested and what still needs a headset

**Tested automatically (no headset, see `docs/game/README.md` section 9):**

- the cockpit starts with no OpenXR runtime installed, without errors, and shows the VR status;
- the VR client process started with `--xr-mode on` and **no runtime**: Godot's OpenXR loader fails, the
  client falls back to flat mode, connects to the cockpit, flies a spacewalk on autopilot and streams the
  pose at ~85–90 Hz; the cockpit's interpolated avatar moves without jumps (largest per-frame jump measured);
- every spacewalk run to completion in flat mode by a test bot (handrail traverse, the task, return through
  the hatch), including the Canadarm rescue flown with the real arm axes and the window visit, which checks
  that the astronaut is inside the LEFT window camera's frustum while waving and knocking;
- the intercom's 4th seat: WiVRn device detection and auto-assignment, suit-radio band and Quindar tones.

**Could not be tested here (needs the Quest 3 on the real PC):**

- the actual OpenXR session with WiVRn: controller bindings (`grip`, `trigger`, `ax_button`, `by_button`,
  thumbsticks), hand tracking, recenter, the real 90 Hz frame timing and foveation settings;
- the play-area height (standing vs seated) and the comfort vignette strength in a real headset;
- the WiVRn audio devices' exact names on Mint 22 (detection matches "wivrn" in the device name or
  description), mic quality and echo;
- the `.desktop` entry inside WiVRn's launcher;
- the Flatpak runtime path on Mint (`active_runtime.json` target).

## Troubleshooting: only stars, no ship or hands, controllers dead

- Every VR run writes a log to `~/.local/share/filament-falcon/eva_vr.log`. It records XR init, the action map, tracker names and profiles, and whether each controller is tracked (every 10 s). Paste `tail -n 30 ~/.local/share/filament-falcon/eva_vr.log` when asking for help.
- `XR init FAILED`: WiVRn isn't running or the Quest isn't connected. Start the WiVRn server, connect the headset, then run `./run.sh --eva-vr` again.
- `left_hand: MISSING` or `tracked=false`: wake the controllers (press a button). On a fresh clone, run `./run.sh` once so the project re-imports, which picks up `openxr_action_map.tres`.
- Controls: grip grabs handrails, the left stick moves the jetpack, the right stick goes up/down and snap-turns, the trigger uses the tool, and holding Menu for 1 s recenters.
- The log should show `near=0.10 far=100000`, then `session FOCUSED`, and controller lines like `c0 tracked=true pose=grip_pose has=[grip_pose(true) ...]`. `session visible only` means the Quest has the system menu open or the headset is off your face, and input pauses until it's FOCUSED again. A lot of `pose recentered (runtime)` lines come from the Quest itself (holding the Meta button), not from the game.

## WiVRn starts automatically

You don't need to open WiVRn yourself. When the VR client starts (`./run.sh --eva-vr`, or **Commander → EVA → LAUNCH VR CLIENT**), the game runs `tools/wivrn_up.sh start`, which:
1. runs `adb reverse tcp:9757 tcp:9757` when `adb` is installed and the Quest is plugged in over USB;
2. leaves an already-running WiVRn server alone. Otherwise it starts the native `wivrn-server`, or the Flatpak (`flatpak run --command=wivrn-server io.github.wivrn.wivrn`);
3. waits up to 20 s for the runtime (`WIVRN_TIMEOUT=40 ./run.sh --eva-vr` waits longer), then points `XR_RUNTIME_JSON` at WiVRn's `openxr_wivrn.json` unless you already set it.

A server the game started is stopped when the VR client or game exits. A server you started yourself is never stopped. Progress shows in the Commander EVA log and in `~/.local/share/filament-falcon/wivrn.log`. Run it by hand with `game/tools/wivrn_up.sh start` / `stop`.
