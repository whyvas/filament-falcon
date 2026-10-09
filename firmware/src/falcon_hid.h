// Custom USB HID joystick: 64 buttons + 8 x 16-bit axes.
// (The stock USBHIDGamepad only has 8-bit axes and 32 buttons.)
#pragma once
#include <Arduino.h>
#include "USB.h"
#include "USBHID.h"

#define FF_HID_REPORT_ID 1
#define FF_HID_BUTTONS   64
#define FF_HID_AXES      8

struct __attribute__((packed)) FalconReport {
  uint8_t buttons[FF_HID_BUTTONS / 8];  // bit n = button n+1 in HID terms
  int16_t axes[FF_HID_AXES];            // X Y Z Rx Ry Rz Slider Dial, -32767..32767
};

class FalconHID : public USBHIDDevice {
 public:
  FalconHID();
  void begin();
  bool ready();
  bool send(const FalconReport &r);
  uint16_t _onGetDescriptor(uint8_t *buffer) override;

 private:
  USBHID hid;
};
