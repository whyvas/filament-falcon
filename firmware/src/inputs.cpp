#include "inputs.h"
#include <Preferences.h>

namespace {
constexpr uint32_t kDebounceMs = 6;      // a change must be stable this long
constexpr uint32_t kPulseOnMs = 35;      // encoder detent -> button pressed for 35 ms
constexpr uint32_t kPulseOffMs = 25;     // ...then released for 25 ms
constexpr uint16_t kChainSwitchReads = 200; // ~0.2 s of agreeing reads to change mode (hot-plug)
constexpr uint8_t kMaxQueued = 8;

struct BtnState { bool raw, stable; uint32_t changedAt; };
BtnState btn[FF_NUM_BUTTONS > 0 ? FF_NUM_BUTTONS : 1];
uint64_t hidBits = 0;
uint64_t chainBits = 0;  // 1 = pressed
bool chainOk = false;

// ---------------- EC11 encoders (interrupt driven) ----------------
struct EncState {
  volatile int8_t acc;        // transitions since last detent
  volatile int16_t detents;   // +cw / -ccw detents not yet emitted
  volatile uint8_t prev;      // previous AB state
  uint8_t pinA, pinB; bool reverse;
  int8_t pulseDir; uint32_t pulseAt; bool pulseOn;
  int16_t level; uint32_t levelChangedAt; bool levelDirty;  // virtual knob
};
EncState enc[FF_NUM_ENCODERS > 0 ? FF_NUM_ENCODERS : 1];

// Quadrature transition table: index = prev<<2 | cur
const int8_t kQuad[16] = {0, -1, 1, 0, 1, 0, 0, -1, -1, 0, 0, 1, 0, 1, -1, 0};

[[maybe_unused]] void IRAM_ATTR encIsr(void *arg) {
  EncState *e = (EncState *)arg;
  uint8_t cur = (digitalRead(e->pinA) << 1) | digitalRead(e->pinB);
  e->acc += kQuad[(e->prev << 2) | cur];
  e->prev = cur;
  // EC11: 4 transitions per detent, detent rests at AB=11 (pulled up)
  if (cur == 3 && (e->acc >= 3 || e->acc <= -3)) {
    int8_t d = (e->acc > 0) ? 1 : -1;
    if (e->reverse) d = -d;
    if (abs(e->detents) < kMaxQueued) e->detents += d;
    e->acc = 0;
  } else if (cur == 3) {
    e->acc = 0;
  }
}

// ---------------- 74HC165 chain ----------------
// Returns false if the chain is absent (sentinel bits not high).
[[maybe_unused]] bool readChain(uint64_t &pressed) {
#if FF_SR_CHIPS > 0
  digitalWrite(PIN_SR_LOAD, LOW);  // parallel load
  delayMicroseconds(2);
  digitalWrite(PIN_SR_LOAD, HIGH);
  delayMicroseconds(2);
  uint64_t p = 0;
  uint8_t sentinel = 0;
  for (int k = 0; k < FF_SR_BITS + 8; k++) {
    int v = digitalRead(PIN_SR_DATA);
    if (k < FF_SR_BITS) {
      int chip = k / 8, input = 7 - (k % 8);  // H comes out first, A last
      if (v == LOW) p |= (1ULL << (chip * 8 + input));  // switches pull to GND
    } else {
      sentinel = (sentinel << 1) | (v ? 1 : 0);
    }
    digitalWrite(PIN_SR_CLK, HIGH);
    delayMicroseconds(1);  // slow enough for a ~2 m cable to the overhead
    digitalWrite(PIN_SR_CLK, LOW);
    delayMicroseconds(1);
  }
  // Last chip's SER is tied to 3V3, so after all chips we shift in 1s.
  // With no chip the DATA pin's pull-down gives 0s.
  pressed = p;
  return sentinel == 0xFF;
#else
  pressed = 0;
  return false;
#endif
}

bool rawFor(size_t i, uint32_t now) {
  const ButtonCfg &b = FF_BUTTONS[i];
  switch (b.src) {
    case SRC_GPIO: return digitalRead(b.ref) == LOW;
    case SRC_GPIO_HIGH: return digitalRead(b.ref) == HIGH;
    case SRC_SR: return chainOk && b.ref < FF_SR_BITS && ((chainBits >> b.ref) & 1);
    case SRC_ENC_CW:
    case SRC_ENC_CCW: {
      if (b.ref >= FF_NUM_ENCODERS) return false;
      const EncState &e = enc[b.ref];
      int8_t want = (b.src == SRC_ENC_CW) ? 1 : -1;
      return e.pulseOn && e.pulseDir == want;
    }
  }
  return false;
}

constexpr uint32_t kKnobSaveMs = 3000;  // save a knob level to flash 3 s after the last click

void saveKnob(size_t i) {
  Preferences p;
  p.begin("ffknob", false);
  char key[6];
  snprintf(key, sizeof key, "k%u", (unsigned)i);
  p.putUChar(key, (uint8_t)enc[i].level);
  p.end();
}

[[maybe_unused]] void serviceEncoders(uint32_t now) {
  for (size_t i = 0; i < FF_NUM_ENCODERS; i++) {
    EncState &e = enc[i];
    if (FF_ENCODERS[i].axis != AX_NONE) {  // virtual knob: clicks change a 0..255 level
      if (e.detents != 0) {
        noInterrupts();
        int16_t d = e.detents;
        e.detents = 0;
        interrupts();
        e.level = constrain(e.level + d * (int)FF_ENCODERS[i].step, 0, 255);
        e.levelChangedAt = now;
        e.levelDirty = true;
      } else if (e.levelDirty && now - e.levelChangedAt > kKnobSaveMs) {
        e.levelDirty = false;
        saveKnob(i);
      }
      continue;
    }
    if (e.pulseOn) {
      if (now - e.pulseAt >= kPulseOnMs) { e.pulseOn = false; e.pulseAt = now; }
    } else if (now - e.pulseAt >= kPulseOffMs && e.detents != 0) {
      noInterrupts();
      int8_t d = e.detents > 0 ? 1 : -1;
      e.detents -= d;
      interrupts();
      e.pulseDir = d; e.pulseOn = true; e.pulseAt = now;
    }
  }
}
}  // namespace

namespace Inputs {

void begin() {
#if FF_SR_CHIPS > 0
  pinMode(PIN_SR_LOAD, OUTPUT);
  pinMode(PIN_SR_CLK, OUTPUT);
  pinMode(PIN_SR_DATA, INPUT_PULLDOWN);
  digitalWrite(PIN_SR_LOAD, HIGH);
  digitalWrite(PIN_SR_CLK, LOW);
#endif
  for (size_t i = 0; i < FF_NUM_BUTTONS; i++) {
    const ButtonCfg &b = FF_BUTTONS[i];
    if (b.src == SRC_GPIO) pinMode(b.ref, INPUT_PULLUP);
    if (b.src == SRC_GPIO_HIGH) pinMode(b.ref, INPUT_PULLDOWN);
  }
  pinMode(PIN_BOOT_BTN, INPUT_PULLUP);
  pinMode(PIN_STICK_BTN, INPUT_PULLUP);  // also the calibration button
#if !FF_FORCE_FALLBACK
  Preferences prefs;
  prefs.begin("ffknob", true);
  for (size_t i = 0; i < FF_NUM_ENCODERS; i++) {
    EncState &e = enc[i];
    char key[6];
    snprintf(key, sizeof key, "k%u", (unsigned)i);
    e.level = prefs.getUChar(key, 160);
    e.pinA = FF_ENCODERS[i].pinA; e.pinB = FF_ENCODERS[i].pinB; e.reverse = FF_ENCODERS[i].reverse;
    pinMode(e.pinA, INPUT_PULLUP);
    pinMode(e.pinB, INPUT_PULLUP);
    e.prev = (digitalRead(e.pinA) << 1) | digitalRead(e.pinB);
    attachInterruptArg(digitalPinToInterrupt(e.pinA), encIsr, &e, CHANGE);
    attachInterruptArg(digitalPinToInterrupt(e.pinB), encIsr, &e, CHANGE);
  }
  prefs.end();
#else
  for (size_t i = 0; i < FF_NUM_ENCODERS; i++) enc[i].level = 160;
#endif
  uint32_t now = millis();
  scan(now);
  for (size_t i = 0; i < FF_NUM_BUTTONS; i++) btn[i].stable = btn[i].raw;  // no debounce at boot
}

void scan(uint32_t now) {
#if !FF_FORCE_FALLBACK
  uint64_t bits;
  bool ok = readChain(bits);
  // Only switch modes after many consecutive agreeing reads (ignores glitches).
  static uint16_t disagree = 0;
  static bool first = true;
  disagree = (ok != chainOk) ? disagree + 1 : 0;
  if (disagree >= kChainSwitchReads || (first && ok != chainOk)) {
    chainOk = ok;
    disagree = 0;
    first = false;
    Serial.printf("[inputs] 74HC165 chain %s\n", ok ? "detected" : "NOT detected -> fallback (joystick-only) mode");
  }
  first = false;
  chainBits = chainOk ? bits : 0;
  serviceEncoders(now);
#endif
  uint64_t out = 0;
  for (size_t i = 0; i < FF_NUM_BUTTONS; i++) {
    bool r = rawFor(i, now);
    BtnState &s = btn[i];
    bool pulse = FF_BUTTONS[i].src == SRC_ENC_CW || FF_BUTTONS[i].src == SRC_ENC_CCW;
    if (r != s.raw) { s.raw = r; s.changedAt = now; }
    if (pulse || (s.stable != s.raw && now - s.changedAt >= kDebounceMs)) s.stable = s.raw;
    if (s.stable && FF_BUTTONS[i].hid < 64) out |= 1ULL << FF_BUTTONS[i].hid;
  }
  hidBits = out;
}

bool hidButton(uint8_t hidIndex) { return hidIndex < 64 && ((hidBits >> hidIndex) & 1); }
bool chainPresent() { return chainOk; }
uint64_t rawChain() { return chainBits; }
bool gpioHeld(uint8_t pin) { return digitalRead(pin) == LOW; }
uint8_t knobLevel(size_t i) { return i < FF_NUM_ENCODERS ? (uint8_t)enc[i].level : 255; }
}  // namespace Inputs
