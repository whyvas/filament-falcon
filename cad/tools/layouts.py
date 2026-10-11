"""Panel layouts for The Filament Falcon - the single source of truth for every
lettered panel.  Run gen_panels.py after editing; it regenerates cad/panels/*.scad,
shared/panel_labels.json and checks the layout (overlaps, keep-outs, stroke width).

Panel coordinates: mm, origin at the bottom-left of the NOMINAL panel, x right,
y up, seen from the front.  Panels are multiples of the 40 mm grid.  The top and
bottom 20 mm (FF_BAND) sit on the plywood rails, so no back-side features there.
"""

CAP = 5.5        # standard label cap height (stroke ~1.4 mm in Barlow Condensed Black)
CAP_HEAD = 8.0   # headings

# label distance from control centre (label above), mm
LABEL_OFF = {"tog6": 18, "tog6g": 27, "tog12": 22, "btn12": 18, "btn16": 20, "arc19": 22,
             "arc22": 24, "estop22": 29, "led5": 12, "ec11": 21, "key19": 22, "pot7": 21, "m3cs": 6}
# guard front footprint relative to toggle centre (x0, y0, x1, y1)
GUARD_RECT = (-12, -25, 12, 21)


class Panel:
    def __init__(self, pid, title, w, h, where, seam_l=False, seam_r=False, notes=""):
        self.id, self.title, self.w, self.h, self.where = pid, title, w, h, where
        self.seam_l, self.seam_r, self.notes = seam_l, seam_r, notes
        self.cuts, self.labels, self.slots, self.grooves, self.keepouts = [], [], [], [], []
        self.controls = []   # human-readable bill of switches

    def label(self, lid, text, x, y, cap=CAP):
        self.labels.append(dict(id=lid, text=text, x=x, y=y, cap=cap))

    def ctrl(self, kind, x, y, lid=None, text=None, where="above", led=False, desc="", lab_dx=0):
        self.cuts.append((kind, x, y))
        self.controls.append(dict(kind=kind, x=x, y=y, label=text, id=lid, desc=desc))
        if lid:
            off = LABEL_OFF[kind]
            if where == "above":
                self.label(lid, text, x + lab_dx, y + off)
            elif where == "below":
                off = 33 if kind == "tog6g" else off
                self.label(lid, text, x + lab_dx, y - off)
        if led:
            ly = y - (16 if kind != "tog6g" else 0)
            lx = x if kind != "tog6g" else x + 20
            self.cuts.append(("led5", lx, ly))
            self.controls.append(dict(kind="led5", x=lx, y=ly, label=(text or "") + " status", id=None, desc="status LED"))

    def led(self, x, y, desc):
        self.cuts.append(("led5", x, y))
        self.controls.append(dict(kind="led5", x=x, y=y, label=desc, id=None, desc="indicator LED"))

    def slot(self, x, y, w, l, desc, keepout=None):
        self.slots.append((x, y, w, l))
        self.controls.append(dict(kind="slot", x=x, y=y, label=desc, id=None, desc=f"{w}x{l} mm lever slot"))
        if keepout:
            self.keepouts.append(keepout)


PANELS = []


def P(*a, **k):
    p = Panel(*a, **k)
    PANELS.append(p)
    return p


# ---------------------------------------------------------------- PILOT
p = P("PILOT_DASH_A", "Pilot dash, left piece", 200, 160, "pod lower band (drops down in front of the reclined crew), in front of the LEFT seat, outboard half", seam_r=True)
p.ctrl("tog6g", 40, 100, "ENG_ARM", "ENG ARM", led=True, desc="ENGINE ARM, guarded mini toggle SPST")
p.ctrl("arc22", 105, 100, "IGNITION", "IGNITION", desc="IGNITION 22 mm momentary (red)")
p.ctrl("arc22", 165, 100, "BOOST", "BOOST", desc="BOOST 22 mm momentary (yellow)")
p.ctrl("tog6", 30, 44, "AIRBRAKE", "AIRBRAKE", led=True, desc="AIRBRAKE mini toggle SPST")
p.ctrl("tog6", 80, 44, "FLAPS", "FLAPS", led=True, desc="FLAPS mini toggle ON-OFF-ON (SPDT centre off)")
p.ctrl("tog6", 130, 44, "NAV_LIGHTS", "NAV LIGHTS", led=True, desc="NAV LIGHTS mini toggle SPST")
p.ctrl("btn16", 176, 44, "HORN", "HORN", desc="HORN 16 mm momentary")

p = P("PILOT_DASH_B", "Pilot dash, right piece", 200, 160, "pod lower band in front of the LEFT seat, inboard half", seam_l=True)
p.ctrl("ec11", 42, 92, desc="FLIGHT ASSIST mode, EC11 encoder with push (game lights the active mode)")
p.label("ASSIST", "ASSIST", 42, 118)
for i, (lid, t) in enumerate([("ASSIST_OFF", "OFF"), ("ASSIST_STAB", "STAB"), ("ASSIST_PROGRADE", "PROGRADE"), ("ASSIST_HOLD", "HOLD")]):
    p.label(lid, t, 100, 116 - 16 * i)
p.ctrl("btn16", 165, 100, "VIEW", "VIEW", desc="VIEW cycle 16 mm momentary")
p.label("CAUTION", "CAUTION", 40, 56)
p.led(40, 38, "MASTER CAUTION (red)")
p.label("GEAR_LIGHTS", "GEAR", 155, 56)
for x in (135, 155, 175):
    p.led(x, 38, "gear down (green)")

p = P("PILOT_SIDE", "Pilot side console (throttle + gear)", 200, 160, "outboard LEFT side console of the reclining cradle, horizontal, top of panel = forward")
p.slot(45, 80, 14, 92, "THROTTLE lever slot (throttle quadrant mounts below)", keepout=(15, 20, 75, 140))
p.label("THR_MAX", "MAX", 95, 120)
p.label("THROTTLE", "THROTTLE", 100, 80)
p.label("THR_IDLE", "IDLE", 95, 40)
p.slot(160, 80, 12, 34, "LANDING GEAR lever slot (gear lever box mounts below)", keepout=(145, 44, 175, 116))
for gx, gy in ((150, 44), (170, 44), (150, 116), (170, 116)):
    p.cuts.append(("m3cs", gx, gy))
p.label("GEAR", "GEAR", 160, 131)
p.label("GEAR_UP", "UP", 186, 104)
p.label("GEAR_DN", "DN", 186, 56)
# intercom push-to-talk: the left hand lives on the throttle, so PTT sits right beside the grip
# path (thumb/fingers reach it without letting go) - like the PTT on a real throttle quadrant
p.ctrl("btn16", 122, 100, "PILOT_PTT", "PTT", desc="Intercom PUSH TO TALK 16 mm momentary (Falcon Pilot 74HC165 bit 11)")

# ---------------------------------------------------------------- OPS
p = P("OPS_DASH_A", "Ops dash, left piece (power)", 200, 160, "pod lower band in front of the RIGHT seat, inboard half", seam_r=True)
p.ctrl("tog6", 35, 100, "REACTOR", "REACTOR", led=True, desc="REACTOR power bus, mini toggle SPST")
p.ctrl("tog6", 100, 100, "LIFE_SUPPORT", "LIFE SUPPORT", led=True, desc="LIFE SUPPORT bus, mini toggle SPST")
p.ctrl("tog6", 165, 100, "SHIELDS", "SHIELDS", led=True, desc="SHIELDS bus, mini toggle SPST")
p.ctrl("tog6", 35, 44, "COMMS", "COMMS", led=True, desc="COMMS bus, mini toggle SPST")
p.ctrl("tog6", 100, 44, "SENSORS", "SENSORS", led=True, desc="SENSORS bus, mini toggle SPST")
p.ctrl("arc19", 165, 44, "FIRE_SUPPR", "FIRE SUPPR", desc="FIRE SUPPRESSION 19 mm momentary (red)")

p = P("OPS_DASH_B", "Ops dash, right piece (mode + payload)", 200, 160, "pod lower band in front of the RIGHT seat, outboard half", seam_l=True)
p.ctrl("ec11", 42, 92, desc="OPS MODE, EC11 encoder with push (game lights the active mode)")
p.label("MODE", "MODE", 42, 118)
for i, (lid, t) in enumerate([("MODE_RCS", "RCS"), ("MODE_ARM", "ARM"), ("MODE_SCANNER", "SCANNER")]):
    p.label(lid, t, 100, 116 - 16 * i)
p.ctrl("btn16", 165, 100, "SCAN_PING", "SCAN PING", desc="SCANNER PING 16 mm momentary")
p.ctrl("tog6", 40, 44, "CARGO_BAY", "CARGO BAY", led=True, desc="CARGO BAY DOORS mini toggle SPST")
p.ctrl("tog6", 105, 44, "DOCK_CLAMP", "DOCK CLAMP", led=True, desc="DOCKING CLAMP mini toggle SPST")
p.ctrl("btn16", 168, 44, "NAV_TGT", "NAV TGT", desc="NAV TARGET select 16 mm momentary (cycles targets)")

p = P("OPS_SIDE", "Ops side console (hyperspace)", 200, 160, "front pedestal of the reclining cradle, between the kids just ahead of the TD2220 touchscreen, horizontal, top of panel = forward")
p.label("HYPERSPACE", "HYPERSPACE", 100, 128, cap=CAP_HEAD)
p.ctrl("tog6g", 50, 92, "JUMP_ARM", "JUMP ARM", where="below", desc="JUMP ARM guarded mini toggle SPST")
p.ctrl("arc22", 145, 92, "ENGAGE", "ENGAGE", where="below", desc="JUMP ENGAGE 22 mm momentary (blue), use the printed button collar")
# intercom push-to-talk for OPS: the right hand stays on the stick (right side console), the
# LEFT hand rests here on the pedestal - PTT at the end nearest the OPS seat
p.ctrl("btn16", 182, 116, "OPS_PTT", "PTT", where="below", desc="Intercom PUSH TO TALK 16 mm momentary (Falcon Ops 74HC165 bit 13)")
p.label("CHARGE", "CHARGE", 26, 36)
for x in (60, 80, 100, 120, 140, 160):
    p.led(x, 36, "jump charge bar (blue)")

# ---------------------------------------------------------------- OVERHEAD
p = P("OVERHEAD_A", "Overhead console, left", 200, 120, "pod top band above the monitors, left third (faces the reclined crew, top of panel = up the pod)")
for x, lid, t in ((35, "BATTERY", "BATTERY"), (100, "FUEL_PUMPS", "FUEL PUMPS"), (165, "AVIONICS", "AVIONICS")):
    p.ctrl("tog6", x, 62, lid, t, led=True, desc=f"{t} checklist mini toggle SPST")
p = P("OVERHEAD_B", "Overhead console, centre", 200, 120, "pod top band above the monitors, centre third")
for x, lid, t in ((35, "APU_START", "APU START"), (100, "GUIDANCE", "GUIDANCE"), (165, "IGNITION_ARM", "IGNITION ARM")):
    p.ctrl("tog6", x, 62, lid, t, led=True, desc=f"{t} checklist mini toggle SPST")
p = P("OVERHEAD_C", "Overhead console, right", 200, 120, "pod top band above the monitors, right third")
for x, lid, t in ((30, "CABIN_LIGHTS", "CABIN LIGHTS"), (85, "BEACON", "BEACON"), (135, "STROBE", "STROBE")):
    p.ctrl("tog6", x, 62, lid, t, led=True, desc=f"{t} mini toggle SPST")
p.ctrl("tog6g", 176, 62, "EJECT", "EJECT", desc="EJECT guarded mini toggle (just for fun)")

# ---------------------------------------------------------------- COMMANDER (dad)
p = P("CMD_A", "Commander console, game controls", 200, 200, "dad's right-hand console on the fixed rear dais")
p.ctrl("key19", 38, 146, "MASTER_POWER", "MASTER POWER", desc="MASTER POWER 19 mm key switch (game input)")
p.ctrl("ec11", 105, 146, "MISSION", "MISSION", desc="MISSION select EC11 encoder with push")
p.ctrl("ec11", 165, 146, "LIGHTS_DIM", "DIMMER", desc="cockpit lights DIMMER EC11 encoder")
p.ctrl("arc22", 32, 92, "START", "START", desc="START 22 mm momentary (green)")
p.ctrl("arc22", 82, 92, "PAUSE", "PAUSE", desc="PAUSE 22 mm momentary (yellow)")
# dad's talk keys side by side under the right hand: INTERCOM = his push-to-talk, ALL-CALL = PA to both kids
p.ctrl("arc19", 130, 92, "INTERCOM", "INTERCOM", desc="INTERCOM 19 mm momentary (Commander push to talk, Falcon Command bit 5)")
p.ctrl("btn16", 175, 92, "CMD_ALL_CALL", "ALL-CALL", desc="ALL-CALL / PA 16 mm momentary (talk to both kids, ducks the game; Falcon Command 74HC165 bit 7)")
p.ctrl("arc22", 50, 40, "CAUTION_RESET", "CAUTION RESET", desc="MASTER CAUTION RESET 22 mm momentary (amber)")
p.label("CREW_READY", "CREW READY", 145, 58)
p.led(127, 38, "PILOT ready (green)")
p.led(163, 38, "OPS ready (green)")

p = P("CMD_B", "Commander console, failures + crew motion", 200, 200, "dad's right-hand console on the fixed rear dais, behind CMD_A")
p.label("FAILURES", "FAILURES", 100, 170, cap=CAP_HEAD)
p.ctrl("btn16", 55, 128, "ENGINE_FIRE", "ENGINE FIRE", desc="failure: ENGINE FIRE 16 mm momentary")
p.ctrl("btn16", 145, 128, "CABIN_LEAK", "CABIN LEAK", desc="failure: CABIN LEAK 16 mm momentary")
p.ctrl("btn16", 55, 86, "POWER_FAULT", "POWER FAULT", desc="failure: POWER FAULT 16 mm momentary")
p.ctrl("btn16", 145, 86, "SENSOR_GLITCH", "SENSOR GLITCH", desc="failure: SENSOR GLITCH 16 mm momentary")
p.grooves.append((6, 22, 194, 76))
p.ctrl("key19", 32, 38, "SEAT_KEY", "MOTION", desc="MOTION key switch (hardwired, actuator circuit only): recline + pod")
p.ctrl("tog12", 95, 38, "SEAT_LIFT", "CREW POS", desc="CREW POSITION hold-to-run (ON)-OFF-(ON) DPDT heavy toggle, 12 mm bushing (hardwired): UP = FLIGHT (recline, then pod down), DOWN = BOARD (pod up, then seats upright)")
p.label("SEAT_UP", "FLT", 127, 50)
p.label("SEAT_DN", "BRD", 127, 30)
p.ctrl("estop22", 165, 38, "SEAT_STOP", "STOP", desc="MOTION E-STOP 22 mm latching mushroom, NC (hardwired, cuts all 3 actuators: 2 cradle + 1 pod)")

# order in which the ONE WS2812B strip visits the panels
STRIP_ORDER = ["CMD_A", "CMD_B", "PILOT_SIDE", "OPS_SIDE", "OPS_DASH_A", "OPS_DASH_B",
               "OVERHEAD_C", "OVERHEAD_B", "OVERHEAD_A", "PILOT_DASH_A", "PILOT_DASH_B"]
