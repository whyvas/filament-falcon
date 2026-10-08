// On-board RGB LED used for status / calibration prompts.
#pragma once
#include <Arduino.h>
#include "board_config.h"

inline void statusLed(uint8_t r, uint8_t g, uint8_t b) {
  neopixelWrite(PIN_STATUS_RGB, r / 4, g / 4, b / 4);  // the on-board LED is very bright
}
