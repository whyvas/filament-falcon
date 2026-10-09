#pragma once
#include <Arduino.h>
#include "board_config.h"

struct AxisCal {
  uint16_t min, center, max;
  uint8_t valid;    // 1 = loaded from NVS / calibration
  uint8_t present;  // 0 = not wired (range too small during calibration)
};

namespace Axes {
void begin();                    // loads calibration, auto-centres if none stored
void update();                   // oversample + smooth all axes
uint16_t raw(size_t i);          // smoothed raw ADC value 0..4095
int16_t value(size_t i);         // calibrated HID value -32767..32767
float normalized01(size_t i);    // 0..1 (for UNIPOLAR axes such as the dimmer)
AxisCal &cal(size_t i);
void saveCalibration();
}  // namespace Axes
