// ============================================================================
//  FALCON OPS  (right seat, "Systems/Commander")  -  edit to match your wiring
// ============================================================================
// Joystick = RCS translate X / Y / Z(twist) + trigger (also drives the robotic
// arm, tractor beam and scanner camera depending on the MODE rotary),
// 3 x 74HC165 (24 inputs, 15 used), 1 x EC11 nav-target encoder.
#pragma once
#include "ff_types.h"
#include "board_pins.h"

#define FF_BOARD_NAME   "Falcon Ops"
#define FF_SR_CHIPS     3

static const AxisCfg FF_AXES[] = {
  FF_AXIS(PIN_AX_X,     AX_X,  BIPOLAR, false, 4, "translate_x"),
  FF_AXIS(PIN_AX_Y,     AX_Y,  BIPOLAR, false, 4, "translate_y"),
  FF_AXIS(PIN_AX_TWIST, AX_RZ, BIPOLAR, false, 6, "translate_z"),
};

static const EncoderCfg FF_ENCODERS[] = {
  {PIN_ENC0_A, PIN_ENC0_B, false},   // encoder 0: nav target select
};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_GPIO,    PIN_STICK_BTN, 0,  K_MOMENTARY, "ops_trigger"),
  FF_BTN(SRC_SR,      0,             1,  K_TOGGLE,    "power_reactor"),
  FF_BTN(SRC_SR,      1,             2,  K_TOGGLE,    "power_life_support"),
  FF_BTN(SRC_SR,      2,             3,  K_TOGGLE,    "power_shields"),
  FF_BTN(SRC_SR,      3,             4,  K_TOGGLE,    "power_comms"),
  FF_BTN(SRC_SR,      4,             5,  K_TOGGLE,    "power_sensors"),
  FF_BTN(SRC_SR,      5,             6,  K_ROTARY,    "ops_mode_rcs"),
  FF_BTN(SRC_SR,      6,             7,  K_ROTARY,    "ops_mode_arm"),
  FF_BTN(SRC_SR,      7,             8,  K_ROTARY,    "ops_mode_scanner"),
  FF_BTN(SRC_SR,      8,             9,  K_TOGGLE,    "cargo_doors"),
  FF_BTN(SRC_SR,      9,             10, K_TOGGLE,    "docking_clamp"),
  FF_BTN(SRC_SR,      10,            11, K_MOMENTARY, "scanner_ping"),
  FF_BTN(SRC_SR,      11,            12, K_MOMENTARY, "fire_suppression"),
  FF_BTN(SRC_ENC_CW,  0,             13, K_PULSE,     "nav_target_next"),
  FF_BTN(SRC_ENC_CCW, 0,             14, K_PULSE,     "nav_target_prev"),
  FF_BTN(SRC_SR,      12,            15, K_MOMENTARY, "nav_target_select"),
  FF_BTN(SRC_SR,      13,            16, K_TOGGLE,    "jump_arm"),
  FF_BTN(SRC_SR,      14,            17, K_MOMENTARY, "jump_engage"),
};
