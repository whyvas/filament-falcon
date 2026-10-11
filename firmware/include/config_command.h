// ============================================================================
//  FALCON COMMAND  (dad's seat + overhead console)  -  edit to match wiring
// ============================================================================
// Matches cad/tools/layouts.py panels CMD_A, CMD_B, OVERHEAD_A/B/C.
// Composite USB device: HID joystick + CDC serial (LED protocol from the game).
// 4 x 74HC165 (32 inputs, 22 used): chips 1-2 at dad's console, chips 3-4 in the
// overhead console (run CLK/LOAD/DATA/3V3/GND up a CAT5 cable).
// INTERCOM is the Commander's push-to-talk; ALL-CALL (PA to both kids, ducks everything
// else) is an extra 16 mm momentary next to it. Both go to the intercom helper via the game.
// MISSION = EC11 with push (clicks -> buttons). DIMMER = EC11 used as a virtual
// knob: level 0..255 reported on the Slider axis and applied to strip brightness.
// MOTION key / CREW POS / STOP on CMD_B are hardwired (diagram 04), NOT inputs here.
// The game only READS position contacts through PC817 optocouplers (isolated 12 V side):
//   GPIO39 cradle_reclined   CRADLE_RECLINED read contact (closed = cradle on the recline stop)
//   GPIO40 pod_down_locked   POD_DOWN read contact (closed = pod on its DOWN stop, pawls in)
//   GPIO41 pod_up_locked     optional POD_UP_LOCKED read contact (closed = pod parked UP and
//                            latched); without it the game infers UP vs MOVING from timing.
#pragma once
#include "ff_types.h"
#include "board_pins.h"

#define FF_BOARD_NAME   "Falcon Command"
#define FF_SR_CHIPS     4
#define FF_HAS_LEDS     1
#define FF_HAS_CDC      1

// Strip limits (see docs/electronics/03_ws2812_power.png)
#define FF_LED_DEFAULT_BRIGHTNESS  96    // 0..255 at power-up
#define FF_LED_MAX_MILLIAMPS       8000  // firmware current cap; PSU is 5 V 10 A
#define FF_LED_DIMMER_SCALES_STRIP 1     // 1 = the DIMMER knob also scales strip brightness

static const AxisCfg FF_AXES[] = {};     // no analog inputs on this board

static const EncoderCfg FF_ENCODERS[] = {
  FF_ENC(PIN_ENC0_A, PIN_ENC0_B, false, AX_NONE,   0, ""),                       // 0: MISSION select
  FF_ENC(PIN_ENC1_A, PIN_ENC1_B, false, AX_SLIDER, 8, "cockpit_lights_dimmer"),  // 1: DIMMER knob
};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_SR,      0,              0,  K_TOGGLE,    "master_power"),      // key switch
  FF_BTN(SRC_ENC_CW,  0,              1,  K_PULSE,     "mission_next"),
  FF_BTN(SRC_ENC_CCW, 0,              2,  K_PULSE,     "mission_prev"),
  FF_BTN(SRC_SR,      1,              3,  K_MOMENTARY, "mission_select"),    // encoder push
  FF_BTN(SRC_SR,      2,              4,  K_MOMENTARY, "dimmer_push"),       // DIMMER encoder push
  FF_BTN(SRC_SR,      3,              5,  K_MOMENTARY, "start"),
  FF_BTN(SRC_SR,      4,              6,  K_MOMENTARY, "pause"),
  FF_BTN(SRC_SR,      5,              7,  K_MOMENTARY, "ptt_commander"),     // INTERCOM button = Commander PTT
  FF_BTN(SRC_SR,      6,              8,  K_MOMENTARY, "master_caution_reset"),
  FF_BTN(SRC_SR,      7,              13, K_MOMENTARY, "all_call"),          // ALL-CALL / PA
  FF_BTN(SRC_SR,      8,              9,  K_MOMENTARY, "fail_engine_fire"),
  FF_BTN(SRC_SR,      9,              10, K_MOMENTARY, "fail_cabin_leak"),
  FF_BTN(SRC_SR,      10,             11, K_MOMENTARY, "fail_power_fault"),
  FF_BTN(SRC_SR,      11,             12, K_MOMENTARY, "fail_sensor_glitch"),
  FF_BTN(SRC_GPIO,    PIN_SEAT_SENSE, 15, K_TOGGLE,    "cradle_reclined"),   // opto, read-only
  FF_BTN(SRC_SR,      16,             16, K_TOGGLE,    "oh_battery"),        // overhead chips 3-4
  FF_BTN(SRC_SR,      17,             17, K_TOGGLE,    "oh_fuel_pumps"),
  FF_BTN(SRC_SR,      18,             18, K_TOGGLE,    "oh_avionics"),
  FF_BTN(SRC_SR,      19,             19, K_TOGGLE,    "oh_apu_start"),
  FF_BTN(SRC_SR,      20,             20, K_TOGGLE,    "oh_guidance"),
  FF_BTN(SRC_SR,      21,             21, K_TOGGLE,    "oh_ignition_arm"),
  FF_BTN(SRC_SR,      22,             22, K_TOGGLE,    "oh_cabin_lights"),
  FF_BTN(SRC_SR,      23,             23, K_TOGGLE,    "oh_beacon"),
  FF_BTN(SRC_SR,      24,             24, K_TOGGLE,    "oh_strobe"),
  FF_BTN(SRC_SR,      25,             25, K_TOGGLE,    "oh_eject"),          // guarded toggle
  FF_BTN(SRC_GPIO,    PIN_POD_DOWN_SENSE, 26, K_TOGGLE, "pod_down_locked"),  // opto, read-only
  FF_BTN(SRC_GPIO,    PIN_POD_UP_SENSE,   27, K_TOGGLE, "pod_up_locked"),    // opto, optional
};

// Helpers used by the LED/protocol code
#define FF_CRADLE_RECLINED_HID  15  // HID button of "cradle_reclined" (EVT SEAT DOWN = reclined, UP = not)
#define FF_DIMMER_ENCODER_INDEX 1   // index into FF_ENCODERS of the DIMMER knob
