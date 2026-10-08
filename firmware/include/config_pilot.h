// ============================================================================
//  FALCON PILOT  (left seat, "Flight")  -  edit this file to match your wiring
// ============================================================================
// Joystick = roll (X) / pitch (Y) / yaw (twist) + trigger, throttle lever,
// 3 x 74HC165 (24 inputs, 13 used), 1 x EC11 trim encoder.
#pragma once
#include "ff_types.h"
#include "board_pins.h"

#define FF_BOARD_NAME   "Falcon Pilot"
#define FF_SR_CHIPS     3     // number of 74HC165 in the chain (8 inputs each)

static const AxisCfg FF_AXES[] = {
  FF_AXIS(PIN_AX_X,     AX_X,      BIPOLAR,  false, 3, "roll"),
  FF_AXIS(PIN_AX_Y,     AX_Y,      BIPOLAR,  false, 3, "pitch"),
  FF_AXIS(PIN_AX_TWIST, AX_RZ,     BIPOLAR,  false, 5, "yaw"),
  FF_AXIS(PIN_AX_LEVER, AX_SLIDER, UNIPOLAR, false, 2, "throttle"),
};

static const EncoderCfg FF_ENCODERS[] = {
  {PIN_ENC0_A, PIN_ENC0_B, false},   // encoder 0: pitch trim
};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_GPIO,    PIN_STICK_BTN, 0,  K_MOMENTARY, "pilot_trigger"),
  FF_BTN(SRC_SR,      0,             1,  K_TOGGLE,    "engine_arm"),
  FF_BTN(SRC_SR,      1,             2,  K_MOMENTARY, "ignition"),
  FF_BTN(SRC_SR,      2,             3,  K_TOGGLE,    "landing_gear_down"),
  FF_BTN(SRC_SR,      3,             4,  K_ROTARY,    "assist_off"),
  FF_BTN(SRC_SR,      4,             5,  K_ROTARY,    "assist_stab"),
  FF_BTN(SRC_SR,      5,             6,  K_ROTARY,    "assist_prograde"),
  FF_BTN(SRC_SR,      6,             7,  K_ROTARY,    "assist_hold"),
  FF_BTN(SRC_SR,      7,             8,  K_TOGGLE,    "airbrake"),
  FF_BTN(SRC_SR,      8,             9,  K_TOGGLE,    "flaps"),
  FF_BTN(SRC_SR,      9,             10, K_MOMENTARY, "boost"),
  FF_BTN(SRC_SR,      10,            11, K_MOMENTARY, "view_cycle"),
  FF_BTN(SRC_SR,      11,            12, K_MOMENTARY, "horn"),
  FF_BTN(SRC_ENC_CW,  0,             13, K_PULSE,     "trim_up"),
  FF_BTN(SRC_ENC_CCW, 0,             14, K_PULSE,     "trim_down"),
  FF_BTN(SRC_SR,      12,            15, K_MOMENTARY, "trim_reset"),
};
