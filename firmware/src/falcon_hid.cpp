#include "falcon_hid.h"

static const uint8_t kReportDescriptor[] = {
  0x05, 0x01,              // Usage Page (Generic Desktop)
  0x09, 0x04,              // Usage (Joystick)
  0xA1, 0x01,              // Collection (Application)
  0x85, FF_HID_REPORT_ID,  //   Report ID
  0x05, 0x09,              //   Usage Page (Button)
  0x19, 0x01,              //   Usage Minimum (1)
  0x29, FF_HID_BUTTONS,    //   Usage Maximum (64)
  0x15, 0x00,              //   Logical Minimum (0)
  0x25, 0x01,              //   Logical Maximum (1)
  0x75, 0x01,              //   Report Size (1)
  0x95, FF_HID_BUTTONS,    //   Report Count (64)
  0x81, 0x02,              //   Input (Data,Var,Abs)
  0x05, 0x01,              //   Usage Page (Generic Desktop)
  0x09, 0x30,              //   Usage (X)
  0x09, 0x31,              //   Usage (Y)
  0x09, 0x32,              //   Usage (Z)
  0x09, 0x33,              //   Usage (Rx)
  0x09, 0x34,              //   Usage (Ry)
  0x09, 0x35,              //   Usage (Rz)
  0x09, 0x36,              //   Usage (Slider)
  0x09, 0x37,              //   Usage (Dial)
  0x16, 0x01, 0x80,        //   Logical Minimum (-32767)
  0x26, 0xFF, 0x7F,        //   Logical Maximum (32767)
  0x75, 0x10,              //   Report Size (16)
  0x95, FF_HID_AXES,       //   Report Count (8)
  0x81, 0x02,              //   Input (Data,Var,Abs)
  0xC0                     // End Collection
};

FalconHID::FalconHID() : hid() {
  static bool initialized = false;
  if (!initialized) {
    initialized = true;
    hid.addDevice(this, sizeof(kReportDescriptor));
  }
}

uint16_t FalconHID::_onGetDescriptor(uint8_t *buffer) {
  memcpy(buffer, kReportDescriptor, sizeof(kReportDescriptor));
  return sizeof(kReportDescriptor);
}

void FalconHID::begin() { hid.begin(); }

bool FalconHID::ready() { return hid.ready(); }

bool FalconHID::send(const FalconReport &r) {
  return hid.SendReport(FF_HID_REPORT_ID, &r, sizeof(r), 5);
}
