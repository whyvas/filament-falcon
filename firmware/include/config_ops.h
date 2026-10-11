// ============================================================================
//  FALCON OPS  (right seat, "Systems/Commander")  -  edit to match your wiring
// ============================================================================
// Matches cad/tools/layouts.py panels OPS_DASH_A, OPS_DASH_B, OPS_SIDE.
// Joystick = RCS translate X / Y / Z(twist) + trigger (also drives the robotic
// arm, tractor beam and scanner camera depending on MODE),
// 2 x 74HC165 (16 inputs, 14 used), 1 x EC11 (OPS MODE, with push).
// PTT = headset push-to-talk for the intercom (ICS), 16 mm momentary.
#pragma once
#include "ff_types.h"
#include "board_pins.h"

#define FF_BOARD_NAME   "Falcon Ops"
#define FF_SR_CHIPS     2

static const AxisCfg FF_AXES[] = {
  FF_AXIS(PIN_AX_X,     AX_X,  BIPOLAR, false, 4, "translate_x"),
  FF_AXIS(PIN_AX_Y,     AX_Y,  BIPOLAR, false, 4, "translate_y"),
  FF_AXIS(PIN_AX_TWIST, AX_RZ, BIPOLAR, false, 6, "translate_z"),
};

static const EncoderCfg FF_ENCODERS[] = {
  FF_ENC(PIN_ENC0_A, PIN_ENC0_B, false, AX_NONE, 0, ""),   // encoder 0: OPS MODE (RCS/ARM/SCANNER)
};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_GPIO,    PIN_STICK_BTN, 0,  K_MOMENTARY, "ops_trigger"),
  FF_BTN(SRC_SR,      0,             1,  K_TOGGLE,    "power_reactor"),
  FF_BTN(SRC_SR,      1,             2,  K_TOGGLE,    "power_life_support"),
  FF_BTN(SRC_SR,      2,             3,  K_TOGGLE,    "power_shields"),
  FF_BTN(SRC_SR,      3,             4,  K_TOGGLE,    "power_comms"),
  FF_BTN(SRC_SR,      4,             5,  K_TOGGLE,    "power_sensors"),
  FF_BTN(SRC_SR,      5,             6,  K_MOMENTARY, "fire_suppression"),
  FF_BTN(SRC_ENC_CW,  0,             7,  K_PULSE,     "ops_mode_next"),     // RCS->ARM->SCANNER
  FF_BTN(SRC_ENC_CCW, 0,             8,  K_PULSE,     "ops_mode_prev"),
  FF_BTN(SRC_SR,      6,             9,  K_MOMENTARY, "ops_mode_push"),     // encoder push
  FF_BTN(SRC_SR,      7,             10, K_MOMENTARY, "scanner_ping"),
  FF_BTN(SRC_SR,      8,             11, K_TOGGLE,    "cargo_doors"),
  FF_BTN(SRC_SR,      9,             12, K_TOGGLE,    "docking_clamp"),
  FF_BTN(SRC_SR,      10,            13, K_MOMENTARY, "nav_target_next"),   // NAV TGT button cycles
  FF_BTN(SRC_SR,      11,            14, K_TOGGLE,    "jump_arm"),          // guarded toggle
  FF_BTN(SRC_SR,      12,            15, K_MOMENTARY, "jump_engage"),
  FF_BTN(SRC_SR,      13,            16, K_MOMENTARY, "ptt_ops"),           // intercom push-to-talk
};
