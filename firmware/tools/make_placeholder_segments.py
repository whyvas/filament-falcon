#!/usr/bin/env python3
"""Write a PLACEHOLDER shared/led_segments.json.

Label ids come from shared/panel_labels.json (written by the CAD worker) if it
exists, otherwise from the built-in list below (the labels named in SPEC.md).
Each label gets LEDS_PER_LABEL LEDs back-to-back, with PANEL_GAP unused LEDs
where the strip jumps between panels. Re-run after measuring the real strip, or
just edit the JSON by hand (use the `FIND <index>` serial command to locate LEDs).

If cad/tools/layouts.py is available, the 5 mm status/indicator LED holes from
the CAD panels are added too, as single addressable LEDs (WS2812D-F5 / 5 mm
through-hole WS2812, GRB) spliced into the same data line right after their
panel's labels. Their ids end in _LED.

usage: python3 make_placeholder_segments.py [panel_labels.json] [cad/tools/layouts.py]
"""
import json, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "shared" / "led_segments.json"
LEDS_PER_LABEL = 3      # 60 LED/m strip -> ~50 mm label
PANEL_GAP = 6           # LEDs lost where the strip hops between panels
SPARE_AT_END = 10

# Strip order: Falcon Command board sits behind dad's seat, so the data line
# starts at dad's panel, goes up to the overhead console, then pilot, then ops.
BUILTIN = [
  ("command", [
    ("CMD_MASTER_POWER", "MASTER POWER"), ("CMD_MISSION", "MISSION"),
    ("CMD_MISSION_LAUNCH", "LAUNCH"), ("CMD_MISSION_DOCK", "DOCK"),
    ("CMD_MISSION_LUNAR", "LUNAR"), ("CMD_MISSION_ASTEROID", "ASTEROID"),
    ("CMD_MISSION_REENTRY", "REENTRY"), ("CMD_MISSION_SANDBOX", "SANDBOX"),
    ("CMD_START", "START"), ("CMD_PAUSE", "PAUSE"),
    ("CMD_MASTER_CAUTION", "MASTER CAUTION"),
    ("CMD_FAIL_ENGINE_FIRE", "ENGINE FIRE"), ("CMD_FAIL_CABIN_LEAK", "CABIN LEAK"),
    ("CMD_FAIL_POWER_FAULT", "POWER FAULT"), ("CMD_FAIL_SENSOR_GLITCH", "SENSOR GLITCH"),
    ("CMD_INTERCOM", "INTERCOM"), ("CMD_LIGHTS", "COCKPIT LIGHTS"),
    ("CMD_SEAT_LIFT", "SEAT LIFT")]),
  ("overhead", [
    ("OH_BATTERY", "BATTERY"), ("OH_FUEL_PUMPS", "FUEL PUMPS"),
    ("OH_AVIONICS", "AVIONICS"), ("OH_APU_START", "APU START"),
    ("OH_GUIDANCE", "GUIDANCE"), ("OH_IGNITION_ARM", "IGNITION ARM"),
    ("OH_CABIN_LIGHTS", "CABIN LIGHTS"), ("OH_BEACON", "BEACON"),
    ("OH_STROBE", "STROBE"), ("OH_EJECT", "EJECT")]),
  ("pilot", [
    ("PILOT_ENGINE_ARM", "ENGINE ARM"), ("PILOT_IGNITION", "IGNITION"),
    ("PILOT_GEAR", "GEAR"), ("PILOT_ASSIST", "FLIGHT ASSIST"),
    ("PILOT_ASSIST_OFF", "OFF"), ("PILOT_ASSIST_STAB", "STAB"),
    ("PILOT_ASSIST_PROGRADE", "PROGRADE"), ("PILOT_ASSIST_HOLD", "HOLD"),
    ("PILOT_AIRBRAKE", "AIRBRAKE"), ("PILOT_FLAPS", "FLAPS"),
    ("PILOT_BOOST", "BOOST"), ("PILOT_VIEW", "VIEW"), ("PILOT_HORN", "HORN"),
    ("PILOT_TRIM", "TRIM"), ("PILOT_THROTTLE", "THROTTLE")]),
  ("ops", [
    ("OPS_REACTOR", "REACTOR"), ("OPS_LIFE_SUPPORT", "LIFE SUPPORT"),
    ("OPS_SHIELDS", "SHIELDS"), ("OPS_COMMS", "COMMS"), ("OPS_SENSORS", "SENSORS"),
    ("OPS_MODE", "MODE"), ("OPS_MODE_RCS", "RCS"), ("OPS_MODE_ARM", "ARM"),
    ("OPS_MODE_SCANNER", "SCANNER"), ("OPS_CARGO_DOORS", "CARGO DOORS"),
    ("OPS_DOCK_CLAMP", "DOCK CLAMP"), ("OPS_SCAN_PING", "SCAN PING"),
    ("OPS_FIRE_SUPP", "FIRE SUPP"), ("OPS_NAV_TARGET", "NAV TARGET"),
    ("OPS_JUMP_ARM", "JUMP ARM"), ("OPS_JUMP_ENGAGE", "JUMP ENGAGE")]),
]


def from_panel_labels(path):
    """Accepts the CAD format (labels: list with id/panel/text/index/est_leds_60_per_m,
    panel_order) or a simple {id: {panel, text}} dict. Returns [(panel, [(id, text, leds)])]."""
    data = json.loads(pathlib.Path(path).read_text())
    labels = data.get("labels", data)
    if isinstance(labels, dict):
        items = [dict(id=k, **(v if isinstance(v, dict) else {"text": v})) for k, v in labels.items()]
    else:
        items = sorted(labels, key=lambda l: l.get("index", 0))
    groups = {p: [] for p in data.get("panel_order", [])} if isinstance(data, dict) else {}
    for it in items:
        leds = int(it.get("est_leds_60_per_m") or LEDS_PER_LABEL)
        groups.setdefault(it.get("panel", "misc"), []).append((it["id"], it.get("text", it["id"]), max(1, leds)))
    return [(p, l) for p, l in groups.items() if l]


def status_leds(layouts_path):
    """panel -> [(id, text, count)] for every 5 mm LED hole in cad/tools/layouts.py"""
    import importlib.util, re as _re
    spec = importlib.util.spec_from_file_location("ff_layouts", layouts_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    out = {}
    for p in mod.PANELS:
        segs, parent = {}, None
        for c in p.controls:
            if c["kind"] != "led5":
                parent = c
                continue
            if c["desc"] == "status LED" and parent and parent.get("id"):
                sid, text = parent["id"] + "_LED", (parent.get("label") or parent["id"]) + " status"
            else:
                base = _re.sub(r"\(.*?\)", "", c["label"]).strip()
                sid, text = _re.sub(r"[^A-Z0-9]+", "_", base.upper()).strip("_") + "_LED", c["label"]
            n = segs.get(sid, (text, 0))[1]
            segs[sid] = (text, n + 1)
        out[p.id] = [(k, t, n) for k, (t, n) in segs.items()]
    return out


def main():
    src = "SPEC.md built-in list"
    groups = [(p, [(i, t, LEDS_PER_LABEL) for i, t in l]) for p, l in BUILTIN]
    cand = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "shared" / "panel_labels.json")
    if cand.exists():
        groups, src = from_panel_labels(cand), "shared/panel_labels.json (CAD)"
    lay = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else ROOT / "cad" / "tools" / "layouts.py")
    extra = status_leds(lay) if lay.exists() else {}
    if extra:
        src += " + 5 mm LED holes from cad/tools/layouts.py"
    segs, idx = {}, 0
    for gi, (panel, labels) in enumerate(groups):
        if gi:
            idx += PANEL_GAP
        for lid, text, n in labels:
            segs[lid] = {"start": idx, "count": n, "panel": panel, "text": text}
            idx += n
        for lid, text, n in extra.get(panel, []):
            assert lid not in segs, lid
            segs[lid] = {"start": idx, "count": n, "panel": panel, "text": text, "type": "5mm WS2812D-F5"}
            idx += n
    total = idx + SPARE_AT_END
    out = {
        "_comment": ("PLACEHOLDER map until the real strip is installed and measured. "
                     "label id -> first LED index (0 = first LED after Falcon Command) + LED count. "
                     "Labels use est. LEDs at 60/m from CAD; *_LED entries are 5 mm through-hole WS2812D-F5 "
                     "spliced into the same data line. Edit freely, then rebuild/flash Falcon Command "
                     "(the firmware compiles this file in). "
                     f"Label ids from: {src}."),
        "strip": {"type": "WS2812B", "color_order": "GRB", "leds_per_meter": 60,
                  "total_leds": total, "driven_by": "Falcon Command GPIO21"},
        "segments": segs,
    }
    OUT.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {OUT} ({len(segs)} labels, {total} LEDs, ids from {src})")


if __name__ == "__main__":
    main()
