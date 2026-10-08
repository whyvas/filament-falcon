// ============================================================================
//  FALCON COMMAND  (dad's seat + overhead console)  -  edit to match wiring
// ============================================================================
// Composite USB device: HID joystick + CDC serial (LED protocol from the game).
// 4 x 74HC165 (32 inputs, 26 used): chips 1-2 at dad's panel, chips 3-4 in the
// overhead console (run CLK/LOAD/DATA/3V3/GND up a CAT5 cable).
// Cockpit lights dimmer pot, seat-up sense via optocoupler, ONE WS2812B line.
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
#define FF_LED_DIMMER_SCALES_STRIP 1     // 1 = the dimmer pot also scales strip brightness

static const AxisCfg FF_AXES[] = {
  FF_AXIS(PIN_AX_LEVER, AX_SLIDER, UNIPOLAR, false, 2, "cockpit_lights_dimmer"),
};

static const EncoderCfg FF_ENCODERS[] = {};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_SR,   0,              0,  K_TOGGLE,    "master_power"),
  FF_BTN(SRC_SR,   1,              1,  K_ROTARY,    "mission_launch"),
  FF_BTN(SRC_SR,   2,              2,  K_ROTARY,    "mission_dock"),
  FF_BTN(SRC_SR,   3,              3,  K_ROTARY,    "mission_lunar"),
  FF_BTN(SRC_SR,   4,              4,  K_ROTARY,    "mission_asteroid"),
  FF_BTN(SRC_SR,   5,              5,  K_ROTARY,    "mission_reentry"),
  FF_BTN(SRC_SR,   6,              6,  K_ROTARY,    "mission_sandbox"),
  FF_BTN(SRC_SR,   7,              7,  K_MOMENTARY, "start"),
  FF_BTN(SRC_SR,   8,              8,  K_MOMENTARY, "pause"),
  FF_BTN(SRC_SR,   9,              9,  K_MOMENTARY, "master_caution_reset"),
  FF_BTN(SRC_SR,   10,             10, K_MOMENTARY, "fail_engine_fire"),
  FF_BTN(SRC_SR,   11,             11, K_MOMENTARY, "fail_cabin_leak"),
  FF_BTN(SRC_SR,   12,             12, K_MOMENTARY, "fail_power_fault"),
  FF_BTN(SRC_SR,   13,             13, K_MOMENTARY, "fail_sensor_glitch"),
  FF_BTN(SRC_SR,   14,             14, K_MOMENTARY, "intercom"),
  FF_BTN(SRC_GPIO, PIN_SEAT_SENSE, 15, K_TOGGLE,    "seat_up"),
  FF_BTN(SRC_SR,   16,             16, K_TOGGLE,    "oh_battery"),
  FF_BTN(SRC_SR,   17,             17, K_TOGGLE,    "oh_fuel_pumps"),
  FF_BTN(SRC_SR,   18,             18, K_TOGGLE,    "oh_avionics"),
  FF_BTN(SRC_SR,   19,             19, K_TOGGLE,    "oh_apu_start"),
  FF_BTN(SRC_SR,   20,             20, K_TOGGLE,    "oh_guidance"),
  FF_BTN(SRC_SR,   21,             21, K_TOGGLE,    "oh_ignition_arm"),
  FF_BTN(SRC_SR,   22,             22, K_TOGGLE,    "oh_cabin_lights"),
  FF_BTN(SRC_SR,   23,             23, K_TOGGLE,    "oh_beacon"),
  FF_BTN(SRC_SR,   24,             24, K_TOGGLE,    "oh_strobe"),
  FF_BTN(SRC_SR,   25,             25, K_MOMENTARY, "oh_eject"),
};

// Helpers used by the LED/protocol code
#define FF_SEAT_UP_HID        15  // HID button index of "seat_up" (sent as EVT SEAT UP/DOWN too)
#define FF_DIMMER_AXIS_INDEX  0   // index into FF_AXES of the dimmer pot
