#include "axes.h"
#include <Preferences.h>

namespace {
constexpr int kOversample = 16;     // ADC samples averaged per update
constexpr float kSmoothing = 0.35f; // EMA factor (1 = no smoothing)
constexpr float kEdgePct = 0.02f;   // last 2% of travel snaps to full scale

float smooth[FF_NUM_AXES > 0 ? FF_NUM_AXES : 1];
AxisCal cals[FF_NUM_AXES > 0 ? FF_NUM_AXES : 1];

uint16_t sampleRaw(uint8_t pin) {
  uint32_t acc = 0;
  for (int i = 0; i < kOversample; i++) acc += analogRead(pin);
  return acc / kOversample;
}
}  // namespace

namespace Axes {

void begin() {
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);  // ~0..3.1 V full scale; pot ends on 3V3/GND
  Preferences p;
  p.begin("ffcal", true);
  for (size_t i = 0; i < FF_NUM_AXES; i++) {
    pinMode(FF_AXES[i].pin, INPUT);
    uint16_t r = sampleRaw(FF_AXES[i].pin);
    smooth[i] = r;
    char key[8];
    snprintf(key, sizeof key, "ax%u", (unsigned)i);
    AxisCal c{};
    if (p.getBytes(key, &c, sizeof c) == sizeof c && c.valid) {
      cals[i] = c;
    } else {
      // No calibration yet: assume full pot travel and use the boot reading as
      // the centre (stick at rest). Good enough to test before calibrating.
      cals[i] = {120, FF_AXES[i].mode == BIPOLAR ? r : (uint16_t)2048, 3950, 0, 1};
    }
  }
  p.end();
}

void update() {
  for (size_t i = 0; i < FF_NUM_AXES; i++) {
    smooth[i] += kSmoothing * ((float)sampleRaw(FF_AXES[i].pin) - smooth[i]);
  }
}

uint16_t raw(size_t i) { return (uint16_t)(smooth[i] + 0.5f); }

static float shape(float x, float dz) {
  // x in -1..1 (BIPOLAR) -> deadzone in the middle + snap at the edges
  float a = fabsf(x);
  if (a < dz) return 0;
  a = (a - dz) / (1.0f - dz - kEdgePct);
  if (a > 1) a = 1;
  return x < 0 ? -a : a;
}

static float norm(size_t i) {
  const AxisCfg &cfg = FF_AXES[i];
  const AxisCal &c = cals[i];
  float v = smooth[i];
  float dz = cfg.deadzonePct / 100.0f;
  float out;
  if (cfg.mode == BIPOLAR) {
    if (v < c.center) out = -(c.center - v) / (float)max(1, c.center - c.min);
    else out = (v - c.center) / (float)max(1, c.max - c.center);
    out = constrain(out, -1.0f, 1.0f);
    out = shape(out, dz);
  } else {
    out = (v - c.min) / (float)max(1, c.max - c.min);  // 0..1
    out = constrain((out - dz) / (1.0f - 2 * dz), 0.0f, 1.0f);
    out = out * 2.0f - 1.0f;                           // -1..1
  }
  return cfg.invert ? -out : out;
}

int16_t value(size_t i) {
  if (!cals[i].present) return 0;
  return (int16_t)lroundf(norm(i) * 32767.0f);
}

float normalized01(size_t i) {
  if (!cals[i].present) return 1.0f;
  return (norm(i) + 1.0f) * 0.5f;
}

AxisCal &cal(size_t i) { return cals[i]; }

void saveCalibration() {
  Preferences p;
  p.begin("ffcal", false);
  for (size_t i = 0; i < FF_NUM_AXES; i++) {
    char key[8];
    snprintf(key, sizeof key, "ax%u", (unsigned)i);
    cals[i].valid = 1;
    p.putBytes(key, &cals[i], sizeof(AxisCal));
  }
  p.end();
}

}  // namespace Axes
