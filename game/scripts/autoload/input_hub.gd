extends Node
## Every game action, mapped to the Falcon HID boards (matched by USB product name via
## Input.get_joy_name) with keyboard fallbacks. Bindings come from ../shared/input_map.json
## (written by the firmware folder); built-in defaults are used for anything missing.

signal devices_changed

const DEV_PILOT := "Falcon Pilot"
const DEV_OPS := "Falcon Ops"
const DEV_CMD := "Falcon Command"

# type: axis (-1..1), throttle (0..1), button (momentary), switch (maintained), pos (rotary position)
# keys: axis = [negative, positive]; others = [key]. Default binding = [device, "axis"/"button", index, invert]
const DEVICE_PIDS := {DEV_PILOT: 0x0003, DEV_OPS: 0x0004, DEV_CMD: 0x0005}
const USB_VID := 0x1209

# type: axis (-1..1), throttle (0..1), button (momentary/pulse), switch (maintained), pos (rotary
# position, keyboard/touch only: the real boards use encoders -> *_next / *_prev pulses).
# keys: axis = [negative, positive]; others = [key]. Default binding = [device, "axis"/"button", index, invert]
# Defaults match firmware/shared/input_map.json (v0.1); that file overrides them when present.
const ACTIONS := [
	# ---------------- PILOT (left seat)
	{"id": "pitch", "role": "PILOT", "type": "axis", "label": "Pitch (pull = nose up)", "keys": ["W", "S"], "bind": [DEV_PILOT, "axis", 1, false]},
	{"id": "roll", "role": "PILOT", "type": "axis", "label": "Roll", "keys": ["Q", "E"], "bind": [DEV_PILOT, "axis", 0, false]},
	{"id": "yaw", "role": "PILOT", "type": "axis", "label": "Yaw (twist)", "keys": ["A", "D"], "bind": [DEV_PILOT, "axis", 5, false]},
	{"id": "throttle", "role": "PILOT", "type": "throttle", "label": "Throttle lever", "keys": ["Shift", "Ctrl"], "bind": [DEV_PILOT, "axis", 6, false]},
	{"id": "pilot_trigger", "role": "PILOT", "type": "button", "label": "Trigger (laser)", "keys": ["F"], "bind": [DEV_PILOT, "button", 0]},
	{"id": "engine_arm", "role": "PILOT", "type": "switch", "label": "ENGINE ARM (covered)", "keys": ["T"], "bind": [DEV_PILOT, "button", 1]},
	{"id": "ignition", "role": "PILOT", "type": "button", "label": "IGNITION", "keys": ["Space"], "bind": [DEV_PILOT, "button", 2]},
	{"id": "boost", "role": "PILOT", "type": "button", "label": "BOOST", "keys": ["Tab"], "bind": [DEV_PILOT, "button", 3]},
	{"id": "airbrake", "role": "PILOT", "type": "switch", "label": "AIRBRAKE", "keys": ["B"], "bind": [DEV_PILOT, "button", 4]},
	{"id": "flaps_up", "role": "PILOT", "type": "switch", "label": "FLAPS UP (3-way)", "keys": ["Comma"], "bind": [DEV_PILOT, "button", 5]},
	{"id": "flaps_down", "role": "PILOT", "type": "switch", "label": "FLAPS DOWN (3-way)", "keys": ["Period"], "bind": [DEV_PILOT, "button", 6]},
	{"id": "nav_lights", "role": "PILOT", "type": "switch", "label": "NAV LIGHTS", "keys": ["Semicolon"], "bind": [DEV_PILOT, "button", 7], "default": true},
	{"id": "horn", "role": "PILOT", "type": "button", "label": "HORN", "keys": ["Y"], "bind": [DEV_PILOT, "button", 8]},
	{"id": "assist_next", "role": "PILOT", "type": "button", "label": "ASSIST knob >", "keys": ["Equal"], "bind": [DEV_PILOT, "button", 9]},
	{"id": "assist_prev", "role": "PILOT", "type": "button", "label": "ASSIST knob <", "keys": ["Minus"], "bind": [DEV_PILOT, "button", 10]},
	{"id": "assist_push", "role": "PILOT", "type": "button", "label": "ASSIST knob push", "keys": [], "bind": [DEV_PILOT, "button", 11]},
	{"id": "view_cycle", "role": "PILOT", "type": "button", "label": "VIEW", "keys": ["V"], "bind": [DEV_PILOT, "button", 12]},
	{"id": "gear", "role": "PILOT", "type": "switch", "label": "LANDING GEAR DOWN", "keys": ["G"], "bind": [DEV_PILOT, "button", 13]},
	{"id": "fa_off", "role": "PILOT", "type": "pos", "group": "fa", "value": 0, "label": "ASSIST: OFF", "keys": ["1"], "bind": []},
	{"id": "fa_stab", "role": "PILOT", "type": "pos", "group": "fa", "value": 1, "label": "ASSIST: STAB", "keys": ["2"], "bind": []},
	{"id": "fa_prograde", "role": "PILOT", "type": "pos", "group": "fa", "value": 2, "label": "ASSIST: PROGRADE", "keys": ["3"], "bind": []},
	{"id": "fa_hold", "role": "PILOT", "type": "pos", "group": "fa", "value": 3, "label": "ASSIST: HOLD", "keys": ["4"], "bind": []},
	# ---------------- OPS (right seat)
	{"id": "tx", "role": "OPS", "type": "axis", "label": "RCS left/right", "keys": ["J", "L"], "bind": [DEV_OPS, "axis", 0, false]},
	{"id": "ty", "role": "OPS", "type": "axis", "label": "RCS down/up", "keys": ["K", "I"], "bind": [DEV_OPS, "axis", 1, false]},
	{"id": "tz", "role": "OPS", "type": "axis", "label": "RCS back/forward (twist)", "keys": ["N", "H"], "bind": [DEV_OPS, "axis", 5, false]},
	{"id": "ops_trigger", "role": "OPS", "type": "button", "label": "Trigger (stage / grab / ping)", "keys": ["Enter"], "bind": [DEV_OPS, "button", 0]},
	{"id": "pwr_reactor", "role": "OPS", "type": "switch", "label": "REACTOR", "keys": ["5"], "bind": [DEV_OPS, "button", 1], "default": true},
	{"id": "pwr_life", "role": "OPS", "type": "switch", "label": "LIFE SUPPORT", "keys": ["6"], "bind": [DEV_OPS, "button", 2], "default": true},
	{"id": "pwr_shields", "role": "OPS", "type": "switch", "label": "SHIELDS", "keys": ["7"], "bind": [DEV_OPS, "button", 3]},
	{"id": "pwr_comms", "role": "OPS", "type": "switch", "label": "COMMS", "keys": ["8"], "bind": [DEV_OPS, "button", 4], "default": true},
	{"id": "pwr_sensors", "role": "OPS", "type": "switch", "label": "SENSORS", "keys": ["9"], "bind": [DEV_OPS, "button", 5]},
	{"id": "fire_suppress", "role": "OPS", "type": "button", "label": "FIRE SUPPRESSION", "keys": ["R"], "bind": [DEV_OPS, "button", 6]},
	{"id": "ops_mode_next", "role": "OPS", "type": "button", "label": "MODE knob >", "keys": ["0"], "bind": [DEV_OPS, "button", 7]},
	{"id": "ops_mode_prev", "role": "OPS", "type": "button", "label": "MODE knob <", "keys": [], "bind": [DEV_OPS, "button", 8]},
	{"id": "ops_mode_push", "role": "OPS", "type": "button", "label": "MODE knob push", "keys": [], "bind": [DEV_OPS, "button", 9]},
	{"id": "scanner_ping", "role": "OPS", "type": "button", "label": "SCANNER PING", "keys": ["P"], "bind": [DEV_OPS, "button", 10]},
	{"id": "cargo_doors", "role": "OPS", "type": "switch", "label": "CARGO DOORS", "keys": ["O"], "bind": [DEV_OPS, "button", 11]},
	{"id": "dock_clamp", "role": "OPS", "type": "switch", "label": "DOCK CLAMP", "keys": ["U"], "bind": [DEV_OPS, "button", 12]},
	{"id": "nav_target", "role": "OPS", "type": "button", "label": "NAV TGT", "keys": ["M"], "bind": [DEV_OPS, "button", 13]},
	{"id": "jump_arm", "role": "OPS", "type": "switch", "label": "JUMP ARM (covered)", "keys": ["BracketLeft"], "bind": [DEV_OPS, "button", 14]},
	{"id": "jump_engage", "role": "OPS", "type": "button", "label": "JUMP ENGAGE", "keys": ["BracketRight"], "bind": [DEV_OPS, "button", 15]},
	{"id": "mode_rcs", "role": "OPS", "type": "pos", "group": "ops", "value": 0, "label": "MODE: RCS", "keys": ["Z"], "bind": []},
	{"id": "mode_arm", "role": "OPS", "type": "pos", "group": "ops", "value": 1, "label": "MODE: ARM", "keys": ["X"], "bind": []},
	{"id": "mode_scanner", "role": "OPS", "type": "pos", "group": "ops", "value": 2, "label": "MODE: SCANNER", "keys": ["C"], "bind": []},
	# ---------------- COMMANDER (rear seat, Falcon Command board)
	{"id": "dimmer", "role": "CMDR", "type": "throttle", "label": "COCKPIT LIGHT DIMMER", "keys": [], "bind": [DEV_CMD, "axis", 6, false], "default": 0.7},
	{"id": "master_power", "role": "CMDR", "type": "switch", "label": "MASTER POWER (key)", "keys": ["F12"], "bind": [DEV_CMD, "button", 0], "default": true},
	{"id": "mission_next", "role": "CMDR", "type": "button", "label": "MISSION knob >", "keys": ["PageDown"], "bind": [DEV_CMD, "button", 1]},
	{"id": "mission_prev", "role": "CMDR", "type": "button", "label": "MISSION knob <", "keys": ["PageUp"], "bind": [DEV_CMD, "button", 2]},
	{"id": "mission_select", "role": "CMDR", "type": "button", "label": "MISSION knob push", "keys": ["Insert"], "bind": [DEV_CMD, "button", 3]},
	{"id": "dimmer_push", "role": "CMDR", "type": "button", "label": "DIMMER push", "keys": [], "bind": [DEV_CMD, "button", 4]},
	{"id": "start", "role": "CMDR", "type": "button", "label": "START", "keys": ["F9"], "bind": [DEV_CMD, "button", 5]},
	{"id": "pause", "role": "CMDR", "type": "button", "label": "PAUSE", "keys": ["Pause"], "bind": [DEV_CMD, "button", 6]},
	{"id": "intercom", "role": "CMDR", "type": "button", "label": "INTERCOM / PA", "keys": ["QuoteLeft"], "bind": [DEV_CMD, "button", 7]},
	{"id": "caution_reset", "role": "CMDR", "type": "button", "label": "MASTER CAUTION RESET", "keys": ["Backspace"], "bind": [DEV_CMD, "button", 8]},
	{"id": "fail_fire", "role": "CMDR", "type": "button", "label": "FAIL: ENGINE FIRE", "keys": ["Ctrl+1"], "bind": [DEV_CMD, "button", 9]},
	{"id": "fail_leak", "role": "CMDR", "type": "button", "label": "FAIL: CABIN LEAK", "keys": ["Ctrl+2"], "bind": [DEV_CMD, "button", 10]},
	{"id": "fail_power", "role": "CMDR", "type": "button", "label": "FAIL: POWER FAULT", "keys": ["Ctrl+3"], "bind": [DEV_CMD, "button", 11]},
	{"id": "fail_sensor", "role": "CMDR", "type": "button", "label": "FAIL: SENSOR GLITCH", "keys": ["Ctrl+4"], "bind": [DEV_CMD, "button", 12]},
	{"id": "seat_up", "role": "CMDR", "type": "switch", "label": "SEATS UP (sense switch)", "keys": ["Home"], "bind": [DEV_CMD, "button", 15], "default": true},
	# ---------------- OVERHEAD (shared, wired to Falcon Command)
	{"id": "ovh_battery", "role": "OVERHEAD", "type": "switch", "label": "BATTERY", "keys": ["F1"], "bind": [DEV_CMD, "button", 16]},
	{"id": "ovh_fuel_pumps", "role": "OVERHEAD", "type": "switch", "label": "FUEL PUMPS", "keys": ["F2"], "bind": [DEV_CMD, "button", 17]},
	{"id": "ovh_avionics", "role": "OVERHEAD", "type": "switch", "label": "AVIONICS", "keys": ["F3"], "bind": [DEV_CMD, "button", 18]},
	{"id": "ovh_apu", "role": "OVERHEAD", "type": "switch", "label": "APU START", "keys": ["F4"], "bind": [DEV_CMD, "button", 19]},
	{"id": "ovh_guidance", "role": "OVERHEAD", "type": "switch", "label": "GUIDANCE", "keys": ["F5"], "bind": [DEV_CMD, "button", 20]},
	{"id": "ovh_ign_arm", "role": "OVERHEAD", "type": "switch", "label": "IGNITION ARM", "keys": ["F6"], "bind": [DEV_CMD, "button", 21]},
	{"id": "cabin_lights", "role": "OVERHEAD", "type": "switch", "label": "CABIN LIGHTS", "keys": ["F7"], "bind": [DEV_CMD, "button", 22], "default": true},
	{"id": "beacon", "role": "OVERHEAD", "type": "switch", "label": "BEACON", "keys": ["F8"], "bind": [DEV_CMD, "button", 23]},
	{"id": "strobe", "role": "OVERHEAD", "type": "switch", "label": "STROBE", "keys": ["F10"], "bind": [DEV_CMD, "button", 24]},
	{"id": "eject", "role": "OVERHEAD", "type": "switch", "label": "EJECT (covered)", "keys": ["F11"], "bind": [DEV_CMD, "button", 25]},
]

## firmware action name (shared/input_map.json) -> game action id
const FW_ALIASES := {
	"landing_gear_down": "gear", "translate_x": "tx", "translate_y": "ty", "translate_z": "tz",
	"power_reactor": "pwr_reactor", "power_life_support": "pwr_life", "power_shields": "pwr_shields",
	"power_comms": "pwr_comms", "power_sensors": "pwr_sensors", "fire_suppression": "fire_suppress",
	"docking_clamp": "dock_clamp", "nav_target_next": "nav_target", "cockpit_lights_dimmer": "dimmer",
	"master_caution_reset": "caution_reset", "fail_engine_fire": "fail_fire", "fail_cabin_leak": "fail_leak",
	"fail_power_fault": "fail_power", "fail_sensor_glitch": "fail_sensor", "oh_battery": "ovh_battery",
	"oh_fuel_pumps": "ovh_fuel_pumps", "oh_avionics": "ovh_avionics", "oh_apu_start": "ovh_apu",
	"oh_guidance": "ovh_guidance", "oh_ignition_arm": "ovh_ign_arm", "oh_cabin_lights": "cabin_lights",
	"oh_beacon": "beacon", "oh_strobe": "strobe", "oh_eject": "eject",
}
const FA_COUNT := 4
const OPS_MODE_COUNT := 3

var actions := {}          # id -> action dict (with resolved binding list)
var value := {}            # id -> float, current
var prev := {}             # id -> float, previous frame
var latch := {}            # id -> float (keyboard / touchscreen state for switches & throttle)
var groups := {"fa": 1, "ops": 0}   # rotary latched values
var pulses := {}           # id -> frames left (virtual presses from the touchscreen)
var joy_by_name := {}      # device name -> joy id
var map_source := "built-in defaults"
var map_errors: Array[String] = []
var _key_prev := {}
var _group_sources := {}   # group -> last value from a device


func _ready() -> void:
	process_priority = -100
	for a in ACTIONS:
		var d: Dictionary = a.duplicate(true)
		var b: Array = d["bind"]
		d["bindings"] = [_bind_from_array(b)] if b.size() > 0 else []
		actions[d["id"]] = d
		value[d["id"]] = 0.0
		prev[d["id"]] = 0.0
		if d.has("default"):
			latch[d["id"]] = float(d["default"])
	_load_input_map()
	Input.joy_connection_changed.connect(func(_id: int, _c: bool) -> void: _scan_devices())
	_scan_devices()


func _bind_from_array(b: Array) -> Dictionary:
	var out := {"device": b[0]}
	if b[1] == "axis":
		out["axis"] = int(b[2])
		out["invert"] = bool(b[3]) if b.size() > 3 else false
	else:
		out["button"] = int(b[2])
	return out


func input_map_path() -> String:
	return Settings.shared_file("input_map.json")


func _load_input_map() -> void:
	var path := input_map_path()
	if not FileAccess.file_exists(path):
		map_source = "built-in defaults (no shared/input_map.json)"
		return
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		map_errors.append("input_map.json is not valid JSON; using defaults")
		map_source = "built-in defaults (parse error)"
		return
	var acts: Variant = data.get("actions", {})
	if typeof(acts) != TYPE_DICTIONARY:
		map_errors.append("input_map.json has no 'actions' object")
		return
	var n := 0
	for fw_id in acts:
		var id: String = FW_ALIASES.get(fw_id, fw_id)
		if not actions.has(id):
			map_errors.append("unknown action '%s' in input_map.json" % fw_id)
			continue
		var entry: Variant = acts[fw_id]
		var list: Array = entry if typeof(entry) == TYPE_ARRAY else [entry]
		var binds := []
		for e in list:
			if typeof(e) != TYPE_DICTIONARY or not e.has("device"):
				continue
			var bd := {"device": str(e["device"])}
			if e.has("axis"):
				bd["axis"] = int(e["axis"])
				bd["invert"] = bool(e.get("invert", false))
				bd["deadzone"] = float(e.get("deadzone", 0.04))
				bd["unipolar"] = str(e.get("mode", "unipolar")) == "unipolar" or bool(e.get("unipolar", false))
			elif e.has("button"):
				bd["button"] = int(e["button"])
				bd["invert"] = bool(e.get("invert", false))
			else:
				continue
			binds.append(bd)
		if binds.size() > 0:
			actions[id]["bindings"] = binds
			n += 1
	map_source = "shared/input_map.json (%d actions)" % n


func _scan_devices() -> void:
	joy_by_name.clear()
	for id in Input.get_connected_joypads():
		var nm := Input.get_joy_name(id)
		var info := Input.get_joy_info(id)
		var vid := int(info.get("vendor_id", -1))
		var pid := int(info.get("product_id", -1))
		for dev in [DEV_PILOT, DEV_OPS, DEV_CMD]:
			if joy_by_name.has(dev):
				continue
			# Linux: "Filament Falcon Falcon Pilot", Windows: "Falcon Pilot" -> substring match, or USB ids
			if nm.findn(dev) >= 0 or (vid == USB_VID and pid == DEVICE_PIDS[dev]):
				joy_by_name[dev] = id
	devices_changed.emit()


func device_connected(dev: String) -> bool:
	return joy_by_name.has(dev)


func connected_joypads() -> Array:
	var out := []
	for id in Input.get_connected_joypads():
		out.append("%d: %s" % [id, Input.get_joy_name(id)])
	return out


func _key_down(spec: String) -> bool:
	var parts := spec.split("+")
	var main_key := parts[parts.size() - 1]
	var need_ctrl := parts.size() > 1 and parts[0].to_lower() == "ctrl"
	if main_key.is_valid_int() and need_ctrl != Input.is_key_pressed(KEY_CTRL):
		return false
	var kc := OS.find_keycode_from_string(main_key)
	if kc == KEY_NONE:
		return false
	return Input.is_key_pressed(kc)


func _key_edge(spec: String) -> bool:
	var down := _key_down(spec)
	var was: bool = _key_prev.get(spec, false)
	_key_prev[spec] = down
	return down and not was


func _read_binding(bd: Dictionary, kind: String) -> Variant:
	var dev: String = bd["device"]
	if not joy_by_name.has(dev):
		return null
	var jid: int = joy_by_name[dev]
	if bd.has("axis"):
		var v := Input.get_joy_axis(jid, bd["axis"])
		if bd.get("invert", false):
			v = -v
		if kind == "throttle":
			return clampf((v + 1.0) * 0.5, 0.0, 1.0) if bd.get("unipolar", true) else clampf(v, 0.0, 1.0)
		var dz: float = bd.get("deadzone", 0.05)
		if absf(v) < dz:
			return 0.0
		return signf(v) * (absf(v) - dz) / (1.0 - dz)
	var pressed := Input.is_joy_button_pressed(jid, bd["button"])
	if bd.get("invert", false):
		pressed = not pressed
	return 1.0 if pressed else 0.0


func _process(dt: float) -> void:
	for id in value:
		prev[id] = value[id]
	var keyboard_ok := not _text_focus()
	for id in actions:
		var a: Dictionary = actions[id]
		var kind: String = a["type"]
		var keys: Array = a["keys"]
		var dev_val: Variant = null
		for bd in a["bindings"]:
			var r: Variant = _read_binding(bd, kind)
			if r == null:
				continue
			if dev_val == null:
				dev_val = r
			elif kind == "axis":
				dev_val = float(dev_val) + float(r)
			else:
				dev_val = maxf(float(dev_val), float(r))
		var v := 0.0
		match kind:
			"axis":
				var k := 0.0
				if keyboard_ok and keys.size() == 2:
					k = (1.0 if _key_down(keys[1]) else 0.0) - (1.0 if _key_down(keys[0]) else 0.0)
				v = clampf((float(dev_val) if dev_val != null else 0.0) + k + float(latch.get(id, 0.0)), -1.0, 1.0)
			"throttle":
				var t: float = latch.get(id, 0.0)
				if keyboard_ok and keys.size() == 2:
					if _key_down(keys[0]):
						t += dt * 0.6
					if _key_down(keys[1]):
						t -= dt * 0.6
				if id == "throttle" and keyboard_ok:
					if _key_edge("Z") and Input.is_key_pressed(KEY_SHIFT):
						t = 1.0
				t = clampf(t, 0.0, 1.0)
				latch[id] = t
				v = float(dev_val) if dev_val != null else t
			"button":
				var kb := keyboard_ok and keys.size() > 0 and _key_down(keys[0])
				v = 1.0 if (kb or (dev_val != null and float(dev_val) > 0.5) or pulses.get(id, 0) > 0 or float(latch.get(id, 0.0)) > 0.5) else 0.0
			"switch":
				if keyboard_ok and keys.size() > 0 and _key_edge(keys[0]):
					latch[id] = 0.0 if float(latch.get(id, 0.0)) > 0.5 else 1.0
				if dev_val != null:
					v = float(dev_val)
				else:
					v = float(latch.get(id, 0.0))
			"pos":
				var grp: String = a["group"]
				if keyboard_ok and keys.size() > 0 and _key_edge(keys[0]):
					groups[grp] = int(a["value"])
				if dev_val != null and float(dev_val) > 0.5:
					if _group_sources.get(grp, -1) != int(a["value"]):
						groups[grp] = int(a["value"])
					_group_sources[grp] = int(a["value"])
				v = 1.0 if groups[grp] == int(a["value"]) else 0.0
		value[id] = v
	# Rotary encoders (firmware sends ~35 ms pulses per click): track the selected position here.
	if just_pressed("assist_next"):
		groups["fa"] = (int(groups["fa"]) + 1) % FA_COUNT
	if just_pressed("assist_prev"):
		groups["fa"] = posmod(int(groups["fa"]) - 1, FA_COUNT)
	if just_pressed("ops_mode_next"):
		groups["ops"] = (int(groups["ops"]) + 1) % OPS_MODE_COUNT
	if just_pressed("ops_mode_prev"):
		groups["ops"] = posmod(int(groups["ops"]) - 1, OPS_MODE_COUNT)
	for id in pulses.keys():
		pulses[id] -= 1
		if pulses[id] <= 0:
			pulses.erase(id)


func _text_focus() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var f := vp.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


# ---------------------------------------------------------------- public API
func axis(id: String) -> float:
	return float(value.get(id, 0.0))


func on(id: String) -> bool:
	return float(value.get(id, 0.0)) > 0.5


func just_pressed(id: String) -> bool:
	return float(value.get(id, 0.0)) > 0.5 and float(prev.get(id, 0.0)) <= 0.5


func just_released(id: String) -> bool:
	return float(value.get(id, 0.0)) <= 0.5 and float(prev.get(id, 0.0)) > 0.5


func group(grp: String) -> int:
	return int(groups.get(grp, 0))


## Touchscreen / test: momentary press for a few frames.
func pulse(id: String, frames: int = 3) -> void:
	pulses[id] = frames


## Touchscreen / test: set a switch or rotary state (only effective without the hardware board).
func set_switch(id: String, on_state: bool) -> void:
	latch[id] = 1.0 if on_state else 0.0


func set_group(grp: String, v: int) -> void:
	groups[grp] = v


func set_axis_override(id: String, v: float) -> void:
	latch[id] = v


func has_hardware_for(id: String) -> bool:
	if not actions.has(id):
		return false
	for bd in actions[id]["bindings"]:
		if joy_by_name.has(bd["device"]):
			return true
	return false


func binding_text(id: String) -> String:
	var a: Dictionary = actions[id]
	var parts := []
	for bd in a["bindings"]:
		if bd.has("axis"):
			parts.append("%s axis %d%s" % [bd["device"], bd["axis"], " inv" if bd.get("invert", false) else ""])
		else:
			parts.append("%s btn %d" % [bd["device"], bd["button"]])
	var keys: Array = a["keys"]
	if keys.size() > 0:
		parts.append("key " + "/".join(keys))
	return ", ".join(parts)


## Writes the current binding table as a JSON template (for the firmware folder to copy).
func export_template() -> String:
	var acts := {}
	for id in actions:
		var a: Dictionary = actions[id]
		var arr := []
		for bd in a["bindings"]:
			arr.append(bd)
		acts[id] = arr[0] if arr.size() == 1 else arr
	return JSON.stringify({"version": 1, "devices": [DEV_PILOT, DEV_OPS, DEV_CMD], "actions": acts}, "  ")
