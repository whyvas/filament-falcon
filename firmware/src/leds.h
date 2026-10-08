// Falcon Command: the single WS2812B strip + the game's serial LED protocol
// (see shared/led_protocol.md).
#pragma once
#include <Arduino.h>

namespace Leds {
void begin();
void update(uint32_t nowMs);                 // render at ~60 fps
void handleLine(char *line, Print &reply);   // one protocol line (no newline)
void poll(Stream &port, Print &reply);       // read bytes, dispatch full lines
void hostDisconnected();                     // game closed the port -> idle glow
void setSeatUp(bool up, Print &evt);         // emits EVT SEAT UP|DOWN on change
}
