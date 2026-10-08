// Buttons: direct GPIOs, 74HC165 chain (debounced) and EC11 encoders.
#pragma once
#include <Arduino.h>
#include "board_config.h"

namespace Inputs {
void begin();
void scan(uint32_t nowMs);          // call every loop (>= 1 kHz)
bool hidButton(uint8_t hidIndex);   // debounced state of HID button n
bool chainPresent();                // false = fallback (joystick-only) mode
uint64_t rawChain();                // raw 74HC165 bits, 1 = pressed (for debugging)
bool gpioHeld(uint8_t pin);         // raw read of an active-low GPIO (boot-time checks)
uint8_t knobLevel(size_t enc);      // 0..255 level of a virtual-knob encoder (axis != AX_NONE)
}
