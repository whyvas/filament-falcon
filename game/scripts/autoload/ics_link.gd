extends Node
## Intercom (ICS) link. The multi-headset audio runs in tools/falcon_ics.py (Godot can only
## open one audio device); the game talks to it over localhost UDP, like the LED bridge:
##   game -> helper :47810  hello / cfg / state (PTT, ALL-CALL, mutes) / ident / rescan
##   helper -> game :47811  status (~15 Hz: levels, gate open, devices), devices list
## run.sh starts the helper before the game; if nothing answers, the game starts it itself.
## When the helper reports its "falcon_game" sink, the game moves its audio output there so
## engine, alarms and callouts reach every headset (and the room speakers, if enabled).
## Voice callouts go to the "falcon_mc" sink = the MISSION CONTROL channel (radio effect).
## Everything fails soft: no python3/numpy/pactl -> no intercom, the game runs as before.

signal status_changed
signal devices_changed

const SEATS := ["pilot", "ops", "commander"]
const SEAT_NAMES := {"pilot": "PILOT", "ops": "OPS", "commander": "COMMANDER"}
const PTT_ACTION := {"pilot": "ptt_pilot", "ops": "ptt_ops", "commander": "ptt_commander"}

var enabled := false
var mock := false
var helper_pid := -1
var status := {}               # last status from the helper
var devices: Array = []        # [{id, label, product, serial, path, sink, source}]
var assign := {}               # seat -> device id
var touch_ptt := {"pilot": false, "ops": false, "commander": false}
var touch_allcall := false
var mute := {"pilot": false, "ops": false, "commander": false}
var state_text := "off"
var _rx := PacketPeerUDP.new()
var _tx := PacketPeerUDP.new()
var _last_rx := -100.0
var _hello_t := 0.0
var _state_t := 0.0
var _sent_state := ""
var _start_tried := false
var _t0 := 0.0
var _routed := false
var _prev_device := "Default"
var _demo := false


func _ready() -> void:
	Settings.changed.connect(func(sec: String) -> void:
		if sec != "ics" or _demo:
			return
		var want := bool(Settings.get_v("ics", "enabled"))
		if want and not enabled:
			start(mock)                      # INTERCOM switched on at runtime
		elif not want and enabled:
			stop()
			state_text = "disabled"
		elif enabled:
			_send({"cmd": "cfg", "values": config_values()}))
	if bool(Settings.get_v("ics", "enabled")):
		start(Settings.cli.has("ics-mock"))
	else:
		state_text = "disabled"


## Bind the reply port and start talking to the helper (run.sh's, or our own after 1.5 s).
func start(use_mock: bool) -> void:
	if enabled:
		return
	mock = use_mock
	enabled = true
	_start_tried = false
	var port := int(Settings.get_v("ics", "game_port"))
	if _rx.bind(port, "127.0.0.1") != OK:
		state_text = "UDP port %d busy (another game running?)" % port
		enabled = false
		return
	_tx.set_dest_address("127.0.0.1", int(Settings.get_v("ics", "udp_port")))
	_t0 = _now()
	state_text = "waiting for the helper"
	_hello()


## Stop our helper (if we started it) and the link; the game keeps running without intercom.
func stop() -> void:
	if not enabled:
		return
	_send({"cmd": "quit"})
	if helper_pid > 0:
		OS.kill(helper_pid)
		helper_pid = -1
	_rx.close()
	enabled = false
	status = {}
	_last_rx = -100.0
	_route_audio()
	state_text = "stopped"


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func config_values() -> Dictionary:
	var out := {}
	for k in Settings.DEFAULTS["ics"]:
		if k in ["udp_port", "game_port"]:
			continue
		out[k] = Settings.get_v("ics", k)
	return out


func _send(obj: Dictionary) -> void:
	if not enabled:
		return
	_tx.put_packet(JSON.stringify(obj).to_utf8_buffer())


func _hello() -> void:
	_send({"cmd": "hello", "pid": OS.get_process_id(), "values": config_values()})


## run.sh normally starts the helper; this is the fallback when the game is launched directly.
func _start_helper() -> void:
	_start_tried = true
	var script := ProjectSettings.globalize_path("res://tools/falcon_ics.py")
	if not FileAccess.file_exists(script):
		state_text = "helper script missing"
		return
	if OS.execute("sh", ["-c", "command -v python3"]) != 0:
		state_text = "python3 not found (intercom off)"
		return
	var logf := ProjectSettings.globalize_path("user://ics.log")
	var args := [script, "--parent-pid", str(OS.get_process_id()), "--port", str(Settings.get_v("ics", "udp_port")),
		"--game-port", str(Settings.get_v("ics", "game_port")), "--log", logf]
	if mock:
		args.append("--mock")
	helper_pid = OS.create_process("python3", args)
	state_text = "helper started (pid %d)" % helper_pid if helper_pid > 0 else "helper failed to start"


func connected() -> bool:
	return _demo or (enabled and _now() - _last_rx < 1.5)


func ok() -> bool:
	return connected() and bool(status.get("ok", false))


func seat(s: String) -> Dictionary:
	var seats: Dictionary = status.get("seats", {})
	return seats.get(s, {})


func keyed(s: String) -> bool:
	return bool(seat(s).get("open", false))


func ptt_down(s: String) -> bool:
	return bool(touch_ptt.get(s, false)) or InputHub.on(PTT_ACTION[s])


func allcall_down() -> bool:
	return touch_allcall or InputHub.on("all_call")


## Sink the voice callouts should go to ("" = default output): the MISSION CONTROL channel.
func mc_sink() -> String:
	return str(status.get("mc_sink", "")) if ok() and not _demo else ""


func set_cfg(key: String, value: Variant) -> void:
	Settings.set_v("ics", key, value)


func identify(device_id: String) -> void:
	_send({"cmd": "ident", "device": device_id})
	Sfx.click()


func rescan() -> void:
	_send({"cmd": "rescan"})


func toggle_mute(s: String) -> void:
	mute[s] = not bool(mute.get(s, false))
	Voice.say("%s microphone %s" % [SEAT_NAMES[s], "muted" if mute[s] else "on"])


## SETUP: step a seat through the detected headsets (and "none").
func cycle_headset(s: String, d: int) -> void:
	var ids: Array = [""]
	for dv in devices:
		ids.append(str(dv["id"]))
	var cur := str(Settings.get_v("ics", s + "_headset"))
	var i := ids.find(cur)
	if i < 0:
		i = 0
	var nxt: String = ids[posmod(i + d, ids.size())]
	# one headset per seat: take it away from the seat that had it
	for o in SEATS:
		if o != s and nxt != "" and str(Settings.get_v("ics", o + "_headset")) == nxt:
			Settings.set_v("ics", o + "_headset", "", false)
	set_cfg(s + "_headset", nxt)


func device_label(id: String) -> String:
	for dv in devices:
		if str(dv["id"]) == id:
			return str(dv["label"])
	if id == "":
		return "(none)"
	return id.get_slice("|", 0) + "  (not plugged in)"


func _process(dt: float) -> void:
	if not enabled:
		return
	while _rx.get_available_packet_count() > 0:
		var d: Variant = JSON.parse_string(_rx.get_packet().get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		_last_rx = _now()
		match str(d.get("type", "")):
			"status":
				status = d
				state_text = str(d.get("msg", ""))
				status_changed.emit()
			"devices":
				devices = d.get("list", [])
				assign = d.get("assign", {})
				devices_changed.emit()
	_hello_t += dt
	if _hello_t > 1.0:
		_hello_t = 0.0
		_hello()
	if not connected() and not _start_tried and _now() - _t0 > 1.5:
		_start_helper()
	elif not connected() and helper_pid > 0 and not OS.is_process_running(helper_pid):
		helper_pid = -1
		state_text = "helper stopped: see ~/.local/share/filament-falcon/ics.log"
	# PTT / ALL-CALL / mutes: on change, and every 0.5 s (UDP may drop a packet)
	var ptt := {}
	for s in SEATS:
		ptt[s] = ptt_down(s)
	var st := {"cmd": "state", "ptt": ptt, "allcall": allcall_down(), "mute": mute}
	var js := JSON.stringify(st)
	_state_t += dt
	if js != _sent_state or _state_t > 0.5:
		_state_t = 0.0
		_sent_state = js
		_send(st)
	_route_audio()


## Move Godot's own audio into the helper's falcon_game sink while the helper runs; back to the
## default output if the helper goes away (so the game never goes silent).
func _route_audio() -> void:
	if Settings.is_headless() or mock or _demo:
		return
	var want := ok() and str(status.get("game_sink", "")) != ""
	if want == _routed:
		return
	if want:
		var target := ""
		for dv in AudioServer.get_output_device_list():
			var n := str(dv).to_lower()
			if n.contains("falcon_game") or n.contains("falcon-game"):
				target = dv
				break
		if target == "":
			return
		_prev_device = AudioServer.output_device
		AudioServer.output_device = target
		_routed = true
		print("[ICS] game audio -> ", target)
	else:
		AudioServer.output_device = _prev_device if _prev_device != "" else "Default"
		_routed = false
		print("[ICS] game audio -> ", AudioServer.output_device)


## Screenshots / UI tests: plausible status without a helper.
func inject_demo() -> void:
	_demo = true
	devices = [
		{"id": "USB Audio Device|C-Media_Electronics_Inc._USB_Audio_Device|pci-0000:0e:00.3-usb-0:3:1.0", "label": "USB Audio Device  (USB 0:3:1.0)"},
		{"id": "USB Audio Device|C-Media_Electronics_Inc._USB_Audio_Device|pci-0000:0e:00.3-usb-0:4:1.0", "label": "USB Audio Device  (USB 0:4:1.0)"},
		{"id": "Logitech USB Headset|Logitech_Logitech_USB_Headset|pci-0000:0e:00.3-usb-0:2:1.0", "label": "Logitech USB Headset  (USB 0:2:1.0)"}]
	assign = {"pilot": devices[0]["id"], "ops": devices[1]["id"], "commander": devices[2]["id"]}
	for i in 3:
		Settings.set_v("ics", SEATS[i] + "_headset", devices[i]["id"], false)
	Settings.set_v("ics", "enabled", true, false)
	status = {"ok": true, "msg": "running on PulseAudio (on PipeWire 1.0.5)", "server": "PulseAudio (on PipeWire 1.0.5)", "xruns": 0, "latency_ms": 35,
		"game_sink": "falcon_game", "mc_sink": "falcon_mc",
		"allcall": false, "seats": {
			"pilot": {"level": -24.0, "peak": -19.0, "open": true, "mode": "vox", "device": devices[0]["label"], "connected": true},
			"ops": {"level": -52.0, "peak": -47.0, "open": false, "mode": "vox", "device": devices[1]["label"], "connected": true},
			"commander": {"level": -61.0, "peak": -58.0, "open": false, "mode": "ptt", "device": devices[2]["label"], "connected": true}}}
	state_text = str(status["msg"])
	devices_changed.emit()
	status_changed.emit()


func _exit_tree() -> void:
	if _routed:
		AudioServer.output_device = _prev_device
	stop()
