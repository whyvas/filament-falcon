// ============================================================================
//  FALCON PILOT  (left seat, "Flight")  -  edit this file to match your wiring
// ============================================================================
// Matches cad/tools/layouts.py panels PILOT_DASH_A, PILOT_DASH_B, PILOT_SIDE.
// Joystick = roll (X) / pitch (Y) / yaw (twist) + trigger, throttle lever pot,
// 2 x 74HC165 (16 inputs, 12 used), 1 x EC11 (FLIGHT ASSIST mode, with push).
// PTT = headset push-to-talk for the intercom (ICS): a 16 mm momentary on the side
// console or the joystick base (the game forwards it to tools/falcon_ics.py).
#pragma once
#include "ff_types.h"
#include "board_pins.h"

#define FF_BOARD_NAME   "Falcon Pilot"
#define FF_SR_CHIPS     2     // number of 74HC165 in the chain (8 inputs each)

static const AxisCfg FF_AXES[] = {
  FF_AXIS(PIN_AX_X,     AX_X,      BIPOLAR,  false, 3, "roll"),
  FF_AXIS(PIN_AX_Y,     AX_Y,      BIPOLAR,  false, 3, "pitch"),
  FF_AXIS(PIN_AX_TWIST, AX_RZ,     BIPOLAR,  false, 5, "yaw"),
  FF_AXIS(PIN_AX_LEVER, AX_SLIDER, UNIPOLAR, false, 2, "throttle"),
};

static const EncoderCfg FF_ENCODERS[] = {
  FF_ENC(PIN_ENC0_A, PIN_ENC0_B, false, AX_NONE, 0, ""),   // encoder 0: FLIGHT ASSIST mode
};

static const ButtonCfg FF_BUTTONS[] = {
  FF_BTN(SRC_GPIO,    PIN_STICK_BTN, 0,  K_MOMENTARY, "pilot_trigger"),
  FF_BTN(SRC_SR,      0,             1,  K_TOGGLE,    "engine_arm"),        // guarded toggle
  FF_BTN(SRC_SR,      1,             2,  K_MOMENTARY, "ignition"),
  FF_BTN(SRC_SR,      2,             3,  K_MOMENTARY, "boost"),
  FF_BTN(SRC_SR,      3,             4,  K_TOGGLE,    "airbrake"),
  FF_BTN(SRC_SR,      4,             5,  K_TOGGLE,    "flaps_up"),          // ON-OFF-ON toggle, up side
  FF_BTN(SRC_SR,      5,             6,  K_TOGGLE,    "flaps_down"),        // ON-OFF-ON toggle, down side
  FF_BTN(SRC_SR,      6,             7,  K_TOGGLE,    "nav_lights"),
  FF_BTN(SRC_SR,      7,             8,  K_MOMENTARY, "horn"),
  FF_BTN(SRC_ENC_CW,  0,             9,  K_PULSE,     "assist_next"),       // OFF->STAB->PROGRADE->HOLD
  FF_BTN(SRC_ENC_CCW, 0,             10, K_PULSE,     "assist_prev"),
  FF_BTN(SRC_SR,      8,             11, K_MOMENTARY, "assist_push"),       // encoder push
  FF_BTN(SRC_SR,      9,             12, K_MOMENTARY, "view_cycle"),
  FF_BTN(SRC_SR,      10,            13, K_TOGGLE,    "landing_gear_down"), // gear lever switch
  FF_BTN(SRC_SR,      11,            14, K_MOMENTARY, "ptt_pilot"),         // intercom push-to-talk
};
