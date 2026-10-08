#include "board_config.h"
#if FF_HAS_LEDS
#include "leds.h"
#include <Adafruit_NeoPixel.h>
#include "inputs.h"
#include "led_segments_gen.h"

namespace {
enum Mode : uint8_t { M_OFF = 0, M_SOLID, M_BLINK, M_PULSE, M_FAST };
struct Px { uint8_t r, g, b; Mode mode; };

Adafruit_NeoPixel strip(FF_NUM_LEDS, PIN_LED_DATA, NEO_GRB + NEO_KHZ800);
Px px[FF_NUM_LEDS];
uint8_t brightness = FF_LED_DEFAULT_BRIGHTNESS;
bool ack = false;
bool hostActive = false;
int8_t seatState = -1;

enum Anim : uint8_t { A_NONE, A_BOOT, A_ALERT };
Anim anim = A_BOOT;
uint32_t animStart = 0;
uint32_t lastFrame = 0;

constexpr Px kIdle = {60, 50, 35, M_SOLID};  // warm white "panel lights" before the game connects

void fill(uint16_t start, uint16_t count, Px p) {
  for (uint32_t i = start; i < (uint32_t)start + count && i < FF_NUM_LEDS; i++) px[i] = p;
}
void idleGlow() {
  fill(0, FF_NUM_LEDS, {0, 0, 0, M_OFF});
  for (const auto &s : FF_LED_SEGMENTS) fill(s.start, s.count, kIdle);
}
const LedSegment *findSeg(const char *id) {
  for (const auto &s : FF_LED_SEGMENTS)
    if (strcasecmp(s.id, id) == 0) return &s;
  return nullptr;
}
bool parseMode(const char *t, Mode &m) {
  if (!t || !*t || !strcasecmp(t, "SOLID")) { m = M_SOLID; return true; }
  if (!strcasecmp(t, "BLINK")) { m = M_BLINK; return true; }
  if (!strcasecmp(t, "PULSE")) { m = M_PULSE; return true; }
  if (!strcasecmp(t, "FAST")) { m = M_FAST; return true; }
  if (!strcasecmp(t, "OFF")) { m = M_OFF; return true; }
  return false;
}
bool parseByte(const char *t, uint8_t &out) {
  if (!t) return false;
  char *end;
  long v = strtol(t, &end, 10);
  if (*end || v < 0 || v > 255) return false;
  out = (uint8_t)v;
  return true;
}
bool parseU16(const char *t, uint16_t &out) {
  if (!t) return false;
  char *end;
  long v = strtol(t, &end, 10);
  if (*end || v < 0 || v > 65535) return false;
  out = (uint16_t)v;
  return true;
}

// Level 0..255 for an animated mode at time t
uint8_t modeLevel(Mode m, uint32_t t) {
  switch (m) {
    case M_SOLID: return 255;
    case M_BLINK: return ((t / 500) & 1) ? 0 : 255;          // 1 Hz
    case M_FAST: return ((t / 125) & 1) ? 0 : 255;           // 4 Hz (alarms)
    case M_PULSE: {                                          // 0.5 Hz breathe
      float s = 0.5f - 0.5f * cosf((t % 2000) * (2.0f * PI / 2000.0f));
      return Adafruit_NeoPixel::gamma8((uint8_t)(30 + s * 225));
    }
    default: return 0;
  }
}

void render(uint32_t now) {
  static uint8_t buf[FF_NUM_LEDS][3];
  uint32_t ta = now - animStart;
  for (int i = 0; i < FF_NUM_LEDS; i++) {
    const Px &p = px[i];
    uint8_t l = modeLevel(p.mode, now);
    uint8_t r = p.r * l / 255, g = p.g * l / 255, b = p.b * l / 255;
    if (anim == A_BOOT) {
      // Phase 1 (0-1.4 s): cyan comet runs down the strip. Phase 2 (1.4-2.4 s):
      // every label flashes white and settles into its normal state.
      if (ta < 1400) {
        float head = ta / 1400.0f * (FF_NUM_LEDS + 12);
        float d = head - i;
        float k = (d >= 0 && d < 12) ? (1.0f - d / 12.0f) : 0;
        r = 0; g = 180 * k; b = 255 * k;
      } else if (ta < 2400) {
        float k = 1.0f - (ta - 1400) / 1000.0f;
        bool lit = p.mode != M_OFF;
        r = lit ? r + (255 - r) * k : 0;
        g = lit ? g + (255 - g) * k : 0;
        b = lit ? b + (255 - b) * k : 0;
      }
    } else if (anim == A_ALERT) {
      bool on = ((ta / 150) & 1) == 0;
      r = on ? 255 : 0; g = 0; b = 0;
    }
    buf[i][0] = r; buf[i][1] = g; buf[i][2] = b;
  }
  if (anim == A_BOOT && ta >= 2400) anim = A_NONE;
  if (anim == A_ALERT && ta >= 900) anim = A_NONE;

  // Global brightness x dimmer pot, then current limit.
  uint32_t scale = brightness;  // 0..255
#if FF_LED_DIMMER_SCALES_STRIP
  scale = scale * (0.05f + 0.95f * Inputs::knobLevel(FF_DIMMER_ENCODER_INDEX) / 255.0f);
#endif
  uint32_t sum = 0;
  for (int i = 0; i < FF_NUM_LEDS; i++) sum += buf[i][0] + buf[i][1] + buf[i][2];
  // WS2812B ~20 mA per channel at 255, ~1 mA idle per LED
  uint32_t ma = sum * scale / 255 * 20 / 255 + FF_NUM_LEDS;
  if (ma > FF_LED_MAX_MILLIAMPS) scale = scale * (FF_LED_MAX_MILLIAMPS - FF_NUM_LEDS) / (ma - FF_NUM_LEDS);
  for (int i = 0; i < FF_NUM_LEDS; i++)
    strip.setPixelColor(i, buf[i][0] * scale / 255, buf[i][1] * scale / 255, buf[i][2] * scale / 255);
  strip.show();
}

void ok(Print &out) { if (ack) out.println("OK"); }
void err(Print &out, const char *why) { out.print("ERR "); out.println(why); }
}  // namespace

namespace Leds {

void begin() {
  strip.begin();
  strip.setBrightness(255);  // we scale ourselves
  strip.clear();
  strip.show();
  idleGlow();
  anim = A_BOOT;
  animStart = millis();
}

void update(uint32_t now) {
  if (now - lastFrame >= 16) { lastFrame = now; render(now); }
}

void hostDisconnected() {
  if (hostActive) { hostActive = false; idleGlow(); }
}

void setSeatUp(bool up, Print &evt) {
  if (seatState != (int8_t)up) {
    if (seatState != -1) { evt.print("EVT SEAT "); evt.println(up ? "UP" : "DOWN"); }
    seatState = up;
  }
}

void handleLine(char *line, Print &out) {
  char *save = nullptr;
  char *cmd = strtok_r(line, " \t", &save);
  if (!cmd) return;
  char *a[6] = {};
  for (int i = 0; i < 6; i++) a[i] = strtok_r(nullptr, " \t", &save);
  hostActive = true;

  if (!strcasecmp(cmd, "SEG") || !strcasecmp(cmd, "ALL") || !strcasecmp(cmd, "IDX")) {
    bool isSeg = !strcasecmp(cmd, "SEG"), isIdx = !strcasecmp(cmd, "IDX");
    int base = isSeg ? 1 : (isIdx ? 2 : 0);
    uint16_t start = 0, count = FF_NUM_LEDS;
    if (isSeg) {
      const LedSegment *s = a[0] ? findSeg(a[0]) : nullptr;
      if (!s) return err(out, "unknown label");
      start = s->start; count = s->count;
    } else if (isIdx) {
      if (!parseU16(a[0], start) || !parseU16(a[1], count)) return err(out, "bad index");
    }
    Px p;
    Mode m;
    if (!parseByte(a[base], p.r) || !parseByte(a[base + 1], p.g) || !parseByte(a[base + 2], p.b))
      return err(out, "bad colour");
    if (!parseMode(a[base + 3], m)) return err(out, "bad mode");
    p.mode = m;
    fill(start, count, p);
    return ok(out);
  }
  if (!strcasecmp(cmd, "CLEAR")) { fill(0, FF_NUM_LEDS, {0, 0, 0, M_OFF}); return ok(out); }
  if (!strcasecmp(cmd, "IDLE")) { idleGlow(); return ok(out); }
  if (!strcasecmp(cmd, "BRIGHT")) {
    uint8_t v;
    if (!parseByte(a[0], v)) return err(out, "bad brightness");
    brightness = v;
    return ok(out);
  }
  if (!strcasecmp(cmd, "FIND")) {
    uint16_t i;
    if (!parseU16(a[0], i) || i >= FF_NUM_LEDS) return err(out, "bad index");
    fill(0, FF_NUM_LEDS, {0, 0, 0, M_OFF});
    px[i] = {255, 255, 255, M_SOLID};
    out.printf("FIND %u\n", i);
    return;
  }
  if (!strcasecmp(cmd, "ANIM")) {
    if (a[0] && !strcasecmp(a[0], "BOOT")) anim = A_BOOT;
    else if (a[0] && !strcasecmp(a[0], "ALERT")) anim = A_ALERT;
    else if (a[0] && !strcasecmp(a[0], "STOP")) anim = A_NONE;
    else return err(out, "unknown anim");
    animStart = millis();
    return ok(out);
  }
  if (!strcasecmp(cmd, "MAP?")) {
    for (const auto &s : FF_LED_SEGMENTS) out.printf("MAP %s %u %u\n", s.id, s.start, s.count);
    out.printf("END %u %u\n", (unsigned)FF_NUM_SEGMENTS, (unsigned)FF_NUM_LEDS);
    return;
  }
  if (!strcasecmp(cmd, "ID?")) {
    out.printf("ID FALCON_COMMAND %s LEDS %u SEGMENTS %u\n", FF_FW_VERSION, (unsigned)FF_NUM_LEDS,
               (unsigned)FF_NUM_SEGMENTS);
    return;
  }
  if (!strcasecmp(cmd, "STATE?")) {
    out.printf("STATE SEAT %s BRIGHT %u DIMMER %u\n", seatState == 1 ? "UP" : "DOWN", brightness,
               (unsigned)Inputs::knobLevel(FF_DIMMER_ENCODER_INDEX));
    return;
  }
  if (!strcasecmp(cmd, "PING")) { out.println("PONG"); return; }
  if (!strcasecmp(cmd, "ACK")) {
    ack = a[0] && !strcasecmp(a[0], "ON");
    out.println("OK");
    return;
  }
  err(out, "unknown command");
}

void poll(Stream &port, Print &reply) {
  static char buf[2][128];
  static uint8_t len[2];
  static bool discard[2];
  // two independent line buffers: index 0 = game CDC port, 1 = debug UART
  int slot = (&port == (Stream *)&Serial) ? 1 : 0;
  while (port.available()) {
    char c = port.read();
    if (c == '\r') continue;
    if (c == '\n') {
      buf[slot][len[slot]] = 0;
      if (len[slot] && !discard[slot]) handleLine(buf[slot], reply);
      len[slot] = 0;
      discard[slot] = false;
    } else if (discard[slot]) {
      // skipping the rest of an overlong line
    } else if (len[slot] < sizeof(buf[0]) - 1) {
      buf[slot][len[slot]++] = c;
    } else {
      discard[slot] = true;
      err(reply, "line too long");
    }
  }
}

}  // namespace Leds
#endif  // FF_HAS_LEDS
