#pragma once
#include <Arduino.h>
namespace Calibration {
// Call once in setup(). If the joystick button (or the BOOT button) is held
// during the first ~2 s after power-up, runs the interactive calibration.
void checkAtBoot(Print &log, void (*keepAlive)());
}
