// ============================================================================
//  FALCON COMMAND  (dad's seat + overhead console)  -  edit to match wiring
// ============================================================================
// Matches cad/tools/layouts.py panels CMD_A, CMD_B, OVERHEAD_A/B/C.
// Composite USB device: HID joystick + CDC serial (LED protocol from the game).
// 4 x 74HC165 (32 inputs, 21 used): chips 1-2 at dad's console, chips 3-4 in the
// overhead console (run CLK/LOAD/DATA/3V3/GND up a CAT5 cable).
// MISSION = EC11 with push (clicks -> buttons). DIMMER = EC11 used as a virtual
// knob: level 0..255 reported on the Slider axis and applied to strip brightness.
// SEAT KEY / SEAT LIFT / STOP on CMD_B are hardwired (diagram 04), NOT inputs here;
// only the opto seat-up sense is read.
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
  FF_BTN(SRC_SR,      5,              7,  K_MOMENTARY, "intercom"),
  FF_BTN(SRC_SR,      6,              8,  K_MOMENTARY, "master_caution_reset"),
  FF_BTN(SRC_SR,      8,              9,  K_MOMENTARY, "fail_engine_fire"),
  FF_BTN(SRC_SR,      9,              10, K_MOMENTARY, "fail_cabin_leak"),
  FF_BTN(SRC_SR,      10,             11, K_MOMENTARY, "fail_power_fault"),
  FF_BTN(SRC_SR,      11,             12, K_MOMENTARY, "fail_sensor_glitch"),
  FF_BTN(SRC_GPIO,    PIN_SEAT_SENSE, 15, K_TOGGLE,    "seat_up"),           // opto, read-only
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
};

// Helpers used by the LED/protocol code
#define FF_SEAT_UP_HID          15  // HID button index of "seat_up" (sent as EVT SEAT UP/DOWN too)
#define FF_DIMMER_ENCODER_INDEX 1   // index into FF_ENCODERS of the DIMMER knob
