// Selects the config header for the board being built (set by platformio.ini).
#pragma once
#if defined(FF_BOARD_PILOT)
#include "config_pilot.h"
#elif defined(FF_BOARD_OPS)
#include "config_ops.h"
#elif defined(FF_BOARD_COMMAND)
#include "config_command.h"
#else
#error "Define FF_BOARD_PILOT, FF_BOARD_OPS or FF_BOARD_COMMAND"
#endif

#ifndef FF_HAS_LEDS
#define FF_HAS_LEDS 0
#endif
#ifndef FF_HAS_CDC
#define FF_HAS_CDC 0
#endif
#ifndef FF_FORCE_FALLBACK
#define FF_FORCE_FALLBACK 0
#endif

#define FF_NUM_AXES     (sizeof(FF_AXES) / sizeof(FF_AXES[0]))
#define FF_NUM_BUTTONS  (sizeof(FF_BUTTONS) / sizeof(FF_BUTTONS[0]))
#define FF_NUM_ENCODERS (sizeof(FF_ENCODERS) / sizeof(FF_ENCODERS[0]))
#define FF_SR_BITS      (FF_SR_CHIPS * 8)
