#!/usr/bin/env python3
"""Generate game/config/virtual_panels.json from cad/tools/layouts.py (the single source of
truth for every panel), so the on-screen VIRTUAL PANELS look like the real ones: same
controls, same positions (mm), same printed legends.  Each control gets the game action it
drives (game/scripts/autoload/input_hub.gd ids).  Re-run after editing the CAD layouts:

    python3 game/tools/gen_virtual_panels.py          (writes game/config/virtual_panels.json)
    python3 game/tools/gen_virtual_panels.py --check  (exit 1 if the file is out of date)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "game", "config", "virtual_panels.json")
sys.path.insert(0, os.path.join(ROOT, "cad", "tools"))
import layouts  # noqa: E402

PILOT, OPS, CMD = "Falcon Pilot", "Falcon Ops", "Falcon Command"
BOARD = {"PILOT_DASH_A": PILOT, "PILOT_DASH_B": PILOT, "PILOT_SIDE": PILOT,
         "OPS_DASH_A": OPS, "OPS_DASH_B": OPS, "OPS_SIDE": OPS,
         "OVERHEAD_A": CMD, "OVERHEAD_B": CMD, "OVERHEAD_C": CMD, "CMD_A": CMD, "CMD_B": CMD}

# CAD control id -> game action.  Kinds: tog6 = switch, tog6g = guarded switch (two-step:
# lift the cover, then flip), arc/btn = momentary (held while touched), key19 = key switch.
ACTION = {
    "ENG_ARM": "engine_arm", "IGNITION": "ignition", "BOOST": "boost", "AIRBRAKE": "airbrake",
    "NAV_LIGHTS": "nav_lights", "HORN": "horn", "VIEW": "view_cycle",
    "REACTOR": "pwr_reactor", "LIFE_SUPPORT": "pwr_life", "SHIELDS": "pwr_shields", "COMMS": "pwr_comms",
    "SENSORS": "pwr_sensors", "FIRE_SUPPR": "fire_suppress", "SCAN_PING": "scanner_ping",
    "CARGO_BAY": "cargo_doors", "DOCK_CLAMP": "dock_clamp", "NAV_TGT": "nav_target",
    "JUMP_ARM": "jump_arm", "ENGAGE": "jump_engage",
    "BATTERY": "ovh_battery", "FUEL_PUMPS": "ovh_fuel_pumps", "AVIONICS": "ovh_avionics",
    "APU_START": "ovh_apu", "GUIDANCE": "ovh_guidance", "IGNITION_ARM": "ovh_ign_arm",
    "CABIN_LIGHTS": "cabin_lights", "BEACON": "beacon", "STROBE": "strobe", "EJECT": "eject",
    "MASTER_POWER": "master_power", "START": "start", "PAUSE": "pause", "INTERCOM": "ptt_commander",
    "CAUTION_RESET": "caution_reset", "ENGINE_FIRE": "fail_fire", "CABIN_LEAK": "fail_leak",
    "POWER_FAULT": "fail_power", "SENSOR_GLITCH": "fail_sensor",
}
# ON-OFF-ON toggles: up / down actions
THREE_WAY = {"FLAPS": ("flaps_up", "flaps_down")}
# encoders: by panel (they have no control id in the CAD) -> behaviour
ENCODERS = {
    "PILOT_DASH_B": {"next": "assist_next", "prev": "assist_prev", "push": "assist_push", "group": "fa",
                     "modes": ["ASSIST_OFF", "ASSIST_STAB", "ASSIST_PROGRADE", "ASSIST_HOLD"]},
    "OPS_DASH_B": {"next": "ops_mode_next", "prev": "ops_mode_prev", "push": "ops_mode_push", "group": "ops",
                   "modes": ["MODE_RCS", "MODE_ARM", "MODE_SCANNER"]},
    "MISSION": {"next": "mission_next", "prev": "mission_prev", "push": "mission_select"},
    "LIGHTS_DIM": {"axis": "dimmer", "push": "dimmer_push"},
}
# hardwired to the actuator circuit: drawn, never operable from the game
HARDWIRED = {"SEAT_KEY", "SEAT_LIFT", "SEAT_STOP"}
# indicator LEDs (no control id) -> game lamp name, matched on the CAD description
LAMPS = [("MASTER CAUTION", "caution"), ("gear down", "gear"), ("jump charge", "jump_charge"),
         ("PILOT ready", "pilot_ready"), ("OPS ready", "ops_ready")]


def lamp_for(desc):
    for key, name in LAMPS:
        if key.lower() in desc.lower():
            return name
    return ""


def build():
    out = {"_generated_by": "game/tools/gen_virtual_panels.py from cad/tools/layouts.py - do not edit",
           "panels": {}}
    for p in layouts.PANELS:
        ctrls = []
        charge_i = 0
        last_action = ""
        for c in p.controls:
            k, cid = c["kind"], c["id"]
            d = {"kind": k, "x": c["x"], "y": c["y"], "id": cid or "", "text": c["label"] or ""}
            if k == "led5":
                if (c["desc"] or "") == "status LED":
                    d["lamp"] = last_action[1:] if last_action.startswith("@") else "action:" + last_action
                else:
                    d["lamp"] = lamp_for(c["label"] or "")
                    if d["lamp"] == "jump_charge":
                        d["index"] = charge_i
                        charge_i += 1
            elif k == "slot":
                d["action"] = "throttle" if "THROTTLE" in c["label"] else "gear"
                sx, sy, sw, sl = next(s for s in p.slots if (s[0], s[1]) == (c["x"], c["y"]))
                d["w"], d["l"] = sw, sl
            elif k == "m3cs":
                continue
            elif cid in HARDWIRED:
                d["hardwired"] = True
            elif k == "ec11":
                key = cid if cid in ENCODERS else p.id
                d["enc"] = ENCODERS[key]
            elif cid in THREE_WAY:
                d["kind"] = "tog3"
                d["up"], d["down"] = THREE_WAY[cid]
                last_action = "@flaps"                           # lit in either ON position
            elif cid in ACTION:
                d["action"] = ACTION[cid]
                last_action = d["action"]
            else:
                raise SystemExit(f"{p.id}: control {cid} ({k}) has no game action - add it to ACTION")
            if k != "led5":
                d["desc"] = c["desc"]
            ctrls.append(d)
        mode_lights = {}
        for e in ENCODERS.values():
            for i, lid in enumerate(e.get("modes", [])):
                mode_lights[lid] = [e["group"], i]
        labels = []
        for lab in p.labels:
            L = dict(id=lab["id"], text=lab["text"], x=lab["x"], y=lab["y"], cap=lab["cap"])
            if lab["id"] in mode_lights:
                L["group"], L["value"] = mode_lights[lab["id"]]
            if lab["id"] in ("SEAT_UP", "SEAT_DN"):
                L["lamp"] = "pod_flt" if lab["id"] == "SEAT_UP" else "pod_brd"
            labels.append(L)
        out["panels"][p.id] = {"title": p.title, "w": p.w, "h": p.h, "board": BOARD[p.id],
                               "where": p.where, "controls": ctrls, "labels": labels,
                               "grooves": [list(g) for g in p.grooves]}
    return out


def main():
    data = json.dumps(build(), indent=1, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        cur = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if cur != data:
            print("virtual_panels.json is out of date: run python3 game/tools/gen_virtual_panels.py")
            return 1
        print("virtual_panels.json up to date")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(data)
    print("wrote", os.path.relpath(OUT, ROOT), "-", len(json.loads(data)["panels"]), "panels")
    return 0


if __name__ == "__main__":
    sys.exit(main())
