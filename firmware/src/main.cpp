// The Filament Falcon - cockpit controller firmware (ESP32-S3, native USB)
// One codebase, three boards: Falcon Pilot, Falcon Ops, Falcon Command.
// Board-specific wiring lives in include/config_*.h.
#include <Arduino.h>
#include "USB.h"
#include "board_config.h"
#include "falcon_hid.h"
#include "axes.h"
#include "inputs.h"
#include "calibration.h"
#include "status_led.h"
#if FF_HAS_CDC
#include "USBCDC.h"
#endif
#if FF_HAS_LEDS
#include "leds.h"
#endif

FalconHID joystick;
#if FF_HAS_CDC
USBCDC GameSerial;  // shows up as /dev/ttyACM* (Linux) / COMx (Windows)
#endif

static FalconReport report, lastSent;
static uint32_t lastSendMs = 0;

static void buildReport() {
  memset(&report, 0, sizeof report);
  for (size_t i = 0; i < FF_NUM_AXES; i++) report.axes[FF_AXES[i].slot] = Axes::value(i);
  for (size_t i = 0; i < FF_NUM_ENCODERS; i++)  // virtual knobs: 0..255 -> -32767..32767
    if (FF_ENCODERS[i].axis < AX_COUNT)
      report.axes[FF_ENCODERS[i].axis] = (int16_t)((int32_t)Inputs::knobLevel(i) * 65534 / 255 - 32767);
  for (uint8_t b = 0; b < FF_HID_BUTTONS; b++)
    if (Inputs::hidButton(b)) report.buttons[b / 8] |= 1 << (b % 8);
}

static void sendIfNeeded(uint32_t now) {
  bool changed = memcmp(&report, &lastSent, sizeof report) != 0;
  // send on change (max 1 kHz) and a keep-alive every 100 ms
  if ((changed && now - lastSendMs >= 1) || now - lastSendMs >= 100) {
    if (joystick.ready() && joystick.send(report)) {
      lastSent = report;
      lastSendMs = now;
    }
  }
}

// Keeps USB fed while calibration blocks setup()
static void keepAlive() {
  uint32_t now = millis();
  Inputs::scan(now);
  buildReport();
  sendIfNeeded(now);
}

void setup() {
  Serial.begin(115200);  // debug log on the "UART" USB-C port (UART0)
  statusLed(0, 0, 40);

  Inputs::begin();
  Axes::begin();

  joystick.begin();
#if FF_HAS_CDC
  GameSerial.begin(115200);
#endif
  // USB identity from platformio.ini (FF_USB_*). Must be set before USB.begin().
  // (The core's pins_arduino.h hard-codes USB_VID/USB_PID, so we set them at runtime.)
  USB.VID(FF_USB_VID);
  USB.PID(FF_USB_PID);
  USB.manufacturerName(FF_USB_MANUFACTURER);
  USB.productName(FF_USB_PRODUCT);
  USB.serialNumber(FF_USB_SERIAL);
  USB.begin();

  Serial.printf("\n%s firmware %s  (%u axes, %u buttons, %u x 74HC165, %u encoders)\n", FF_BOARD_NAME,
                FF_FW_VERSION, (unsigned)FF_NUM_AXES, (unsigned)FF_NUM_BUTTONS, (unsigned)FF_SR_CHIPS,
                (unsigned)FF_NUM_ENCODERS);
  if (FF_FORCE_FALLBACK || !Inputs::chainPresent())
    Serial.println("FALLBACK MODE: shift registers/encoders ignored; joystick axes + top button only");

  Calibration::checkAtBoot(Serial, keepAlive);

#if FF_HAS_LEDS
  Leds::begin();
#endif
  statusLed(0, Inputs::chainPresent() ? 40 : 0, Inputs::chainPresent() ? 0 : 40);  // green = chain found, blue = fallback
}

void loop() {
  uint32_t now = millis();
  Inputs::scan(now);
  Axes::update();
  buildReport();
  sendIfNeeded(now);

#if FF_HAS_LEDS
  Leds::poll(GameSerial, GameSerial);
  Leds::poll(Serial, Serial);  // same protocol on the debug UART for bench tests
  static bool wasConnected = false;
  bool connected = (bool)GameSerial;  // DTR asserted = game has the port open
  if (wasConnected && !connected) Leds::hostDisconnected();
  wasConnected = connected;
  Leds::setSeatUp(!Inputs::hidButton(FF_CRADLE_RECLINED_HID), GameSerial);  // SEAT UP = not reclined
  Leds::update(now);
#endif

  // Optional: live debug dump on the UART port, every 500 ms
#ifdef FF_DEBUG_DUMP
  static uint32_t lastDump = 0;
  if (now - lastDump > 500) {
    lastDump = now;
    for (size_t i = 0; i < FF_NUM_AXES; i++) Serial.printf("%s=%u/%d ", FF_AXES[i].action, Axes::raw(i), Axes::value(i));
    Serial.printf("chain=%llx\n", (unsigned long long)Inputs::rawChain());
  }
#endif
}
