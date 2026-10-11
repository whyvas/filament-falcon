// Default pin plan, identical on all three ESP32-S3 DevKitC-1 boards so the
// wiring is the same everywhere. Each config_*.h can override any of these by
// #defining it BEFORE including this file.
//
// ESP32-S3 DevKitC-1 pins we deliberately AVOID:
//   GPIO0, 3, 45, 46  strapping pins (boot mode / JTAG / VDD_SPI)
//   GPIO19, 20        native USB D-/D+ (that is the HID/CDC USB port)
//   GPIO26..32        SPI flash; GPIO33..37 octal PSRAM on N8R8/N16R8 modules
//   GPIO43, 44        UART0 TX/RX (debug log on the "UART" USB-C port)
//   GPIO38 / 48       onboard RGB LED (48 on board v1.0, 38 on v1.1)
// ADC: only ADC1 (GPIO1..GPIO10) is used for analog; ADC2 conflicts with Wi-Fi.
#pragma once

// ---- Analog (ADC1) ------------------------------------------------------
#ifndef PIN_AX_X
#define PIN_AX_X        4   // joystick X wiper  (ADC1_CH3)
#endif
#ifndef PIN_AX_Y
#define PIN_AX_Y        5   // joystick Y wiper  (ADC1_CH4)
#endif
#ifndef PIN_AX_TWIST
#define PIN_AX_TWIST    6   // joystick twist wiper (ADC1_CH5)
#endif
#ifndef PIN_AX_LEVER
#define PIN_AX_LEVER    7   // throttle lever / dimmer pot wiper (ADC1_CH6)
#endif
#ifndef PIN_AX_SPARE1
#define PIN_AX_SPARE1   1   // spare analog (ADC1_CH0)
#endif
#ifndef PIN_AX_SPARE2
#define PIN_AX_SPARE2   2   // spare analog (ADC1_CH1)
#endif

// ---- Direct buttons -----------------------------------------------------
#ifndef PIN_STICK_BTN
#define PIN_STICK_BTN   15  // joystick top button to GND (internal pull-up)
#endif
#ifndef PIN_BOOT_BTN
#define PIN_BOOT_BTN    0   // on-board BOOT button (only read after boot)
#endif

// ---- 74HC165 shift-register chain ---------------------------------------
#ifndef PIN_SR_LOAD
#define PIN_SR_LOAD     16  // -> SH/LD (pin 1) of every 74HC165
#endif
#ifndef PIN_SR_CLK
#define PIN_SR_CLK      17  // -> CLK (pin 2) of every 74HC165
#endif
#ifndef PIN_SR_DATA
#define PIN_SR_DATA     18  // <- QH (pin 9) of the FIRST 74HC165 (nearest the ESP32)
#endif
// CLK INH (pin 15) of every chip -> GND. The LAST chip's SER (pin 10) -> 3V3:
// that is the "chain present" sentinel the firmware uses for auto-fallback.

// ---- EC11 encoders --------------------------------------------------------
#ifndef PIN_ENC0_A
#define PIN_ENC0_A      11
#endif
#ifndef PIN_ENC0_B
#define PIN_ENC0_B      12
#endif
#ifndef PIN_ENC1_A
#define PIN_ENC1_A      13
#endif
#ifndef PIN_ENC1_B
#define PIN_ENC1_B      14
#endif

// ---- Command board extras -------------------------------------------------
#ifndef PIN_LED_DATA
#define PIN_LED_DATA    21  // WS2812B data -> 74AHCT125 -> 330R -> strip DIN
#endif
// Read-only position senses (PC817 collector + 10k pull-up to 3V3, active LOW = contact
// closed). GPIO39-41 are the JTAG pins; free because we use native USB, not USB-JTAG.
#ifndef PIN_SEAT_SENSE
#define PIN_SEAT_SENSE  39  // CRADLE_RECLINED contact: LOW = cradle fully reclined
#endif
#ifndef PIN_POD_DOWN_SENSE
#define PIN_POD_DOWN_SENSE 40  // POD_DOWN contact: LOW = pod down on its stop and latched
#endif
#ifndef PIN_POD_UP_SENSE
#define PIN_POD_UP_SENSE   41  // optional POD_UP_LOCKED contact: LOW = pod parked up, latched
#endif

// ---- Status LED -----------------------------------------------------------
#ifndef PIN_STATUS_RGB
#ifdef RGB_BUILTIN
#define PIN_STATUS_RGB  RGB_BUILTIN // core's choice (GPIO48 on v1.0). Set 38 for board v1.1.
#else
#define PIN_STATUS_RGB  48
#endif
#endif
