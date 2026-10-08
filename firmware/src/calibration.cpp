// Interactive axis calibration, no PC software needed.
//   1. Hold the joystick top button (or the board's BOOT button) while plugging in.
//      Status LED: WHITE for 2 s; keep holding until it turns BLUE.
//   2. BLUE blinking: move every stick axis, the twist and the lever slowly to
//      both ends a few times. Then press the button.
//   3. YELLOW: let the stick spring back to centre (hands off). Press the button.
//   4. GREEN x3: saved to flash (NVS). Axes that never moved are marked "not wired".
// Progress is also printed on the debug serial port at 115200.
#include "calibration.h"
#include "axes.h"
#include "inputs.h"
#include "status_led.h"

namespace {
constexpr uint16_t kMinRange = 300;  // sweep smaller than this = axis not wired

bool anyCalButton() {
  return Inputs::gpioHeld(PIN_STICK_BTN) || Inputs::gpioHeld(PIN_BOOT_BTN);
}

void waitPress(void (*keepAlive)(), uint8_t r, uint8_t g, uint8_t b, bool blink,
               void (*each)() = nullptr) {
  while (anyCalButton()) { keepAlive(); delay(5); }   // wait for release
  uint32_t heldSince = 0;
  for (;;) {
    bool on = !blink || ((millis() / 250) & 1);
    statusLed(on ? r : 0, on ? g : 0, on ? b : 0);
    Axes::update();
    if (each) each();
    keepAlive();
    if (anyCalButton()) {
      if (!heldSince) heldSince = millis();
      if (millis() - heldSince > 40) break;
    } else {
      heldSince = 0;
    }
    delay(2);
  }
  while (anyCalButton()) { keepAlive(); delay(5); }
}

uint16_t lo[FF_NUM_AXES > 0 ? FF_NUM_AXES : 1], hi[FF_NUM_AXES > 0 ? FF_NUM_AXES : 1];

void track() {
  for (size_t i = 0; i < FF_NUM_AXES; i++) {
    uint16_t v = Axes::raw(i);
    lo[i] = min(lo[i], v);
    hi[i] = max(hi[i], v);
  }
}
}  // namespace

namespace Calibration {

void checkAtBoot(Print &log, void (*keepAlive)()) {
  if (FF_NUM_AXES == 0) return;
  statusLed(255, 255, 255);
  uint32_t t0 = millis(), held = 0;
  bool enter = false;
  while (millis() - t0 < 2000) {
    if (anyCalButton()) { if (!held) held = millis(); if (millis() - held > 1000) { enter = true; break; } }
    else held = 0;
    keepAlive();
    delay(5);
  }
  statusLed(0, 0, 0);
  if (!enter) return;

  log.println("[cal] CALIBRATION: move every axis to both ends, then press the button");
  for (size_t i = 0; i < FF_NUM_AXES; i++) { lo[i] = 4095; hi[i] = 0; }
  for (int k = 0; k < 20; k++) Axes::update();
  waitPress(keepAlive, 0, 0, 255, true, track);

  log.println("[cal] Let the stick centre itself (hands off), then press the button");
  waitPress(keepAlive, 255, 160, 0, false);
  for (int k = 0; k < 64; k++) { Axes::update(); delay(2); }

  for (size_t i = 0; i < FF_NUM_AXES; i++) {
    AxisCal &c = Axes::cal(i);
    c.min = lo[i];
    c.max = hi[i];
    c.center = constrain(Axes::raw(i), lo[i], hi[i]);
    c.present = (hi[i] > lo[i] && hi[i] - lo[i] >= kMinRange) ? 1 : 0;
    log.printf("[cal] axis %u (%s): min %u centre %u max %u %s\n", (unsigned)i, FF_AXES[i].action,
               c.min, c.center, c.max, c.present ? "" : "-> NOT WIRED, reported as 0");
  }
  Axes::saveCalibration();
  log.println("[cal] saved");
  for (int k = 0; k < 3; k++) { statusLed(0, 255, 0); delay(200); statusLed(0, 0, 0); delay(200); }
}

}  // namespace Calibration
