extends Node
## EVA director (autoload "Eva"), cockpit side.
##
## The spacewalker is simulated by EvaSim in whichever process "drives" it:
##  - FLAT: right here (Commander > EVA view, keyboard / gamepad, or the test bot);
##  - VR:   the EVA client (`godot --xr-mode on -- --eva-client`, a second process of this same
##          project that owns the OpenXR session and the Quest 3). It runs EvaSim locally (hands
##          must feel instant) and streams the state at headset rate (72-120 Hz) over localhost
##          UDP; we keep a mirror EvaSim and interpolate the avatar pose ~45 ms behind, so the
##          astronaut moves smoothly in the cockpit windows and camera feeds.
## This process never touches OpenXR, so the cockpit runs exactly the same with no headset,
## no runtime, or a crashed VR client.
##
## Protocol (Godot var_to_bytes over UDP on 127.0.0.1, port eva/port = 47820):
##   client -> us: {t: "hello", info} | {t: "st", s: EvaSim.to_net(), ev: [[id, kind, data]], cack, info, ptt}
##   us -> client: {t: "w", ...world snapshot..., cmds: [[id, kind, data]], ack}  (every frame
##   while a client is connected; cmds/events are resent until acknowledged)

signal changed
signal eva_event(kind: String, data: Dictionary)

const EVA_HEAD_LAYER := 1 << 11    # helmet: hidden from the helmet cam / the wearer's own eyes
const EVA_BODY_LAYER := 1 << 12    # torso + legs: hidden from the wearer (VR / first person)

var role := "server"
var active := false
var scen_id := ""
var scen := {}
var sim: EvaSim = null
var driver := "flat"              # flat | vr
var flat := FlatControl.new()
var bot: EvaBot = null
var keyboard := false             # the flat EVA view owns the keyboard
var for_mission := false
var result_text := ""
var last_score := 0
var penalties := 0
var log_lines: Array[String] = []

# ---- network
var _udp := PacketPeerUDP.new()
var _bound := false
var _client_ip := ""
var _client_port := 0
var _client_seen := -100.0
var client_info := {}
var _cmds: Array = []             # [[id, kind, data]]
var _cmd_id := 0
var _client_cack := 0
var _ev_seen := 0
var _pose_buf: Array = []         # [[time, pose]]
var rx_hz := 0.0
var _rx_count := 0
var _rx_t := 0.0
var client_pid := -1
var _seq := 0
var _hold_warn_t := 0.0
var _state_t := 0.0
var ptt := false
var last_cmd := {}


func _ready() -> void:
	if Settings.cli.has("eva-client"):
		role = "client"
		return
	var port := int(Settings.get_v("eva", "port"))
	_bound = _udp.bind(port, "127.0.0.1") == OK
	if not _bound:
		push_warning("EVA: UDP port %d busy (another game running?) - VR client link off" % port)
	if Settings.cli.has("eva-vr"):
		launch_client.call_deferred()


func _exit_tree() -> void:
	stop_client()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func client_connected() -> bool:
	return _now() - _client_seen < 1.5


func client_has_xr() -> bool:
	return client_connected() and bool(client_info.get("xr", false))


# ======================================================================== control
func available() -> Array[String]:
	return EvaScenarios.available(Game)


func can_start(id: String) -> bool:
	return not active and id in available()


## Start a spacewalk. mode: "" = setting eva/mode (auto = VR when the client is connected
## with a headset, else flat).
func start(id: String, mission_eva: bool = false, mode: String = "") -> bool:
	if active or role != "server":
		return false
	if not id in available():
		Voice.say("No spacewalk here right now. The ship must be in space with the engine off, or landed on the Moon.", 1)
		return false
	scen_id = id
	scen = EvaScenarios.build(id, Game, float(Settings.get_v("eva", "tether_m")))
	sim = EvaSim.new()
	_update_world_inputs()
	sim.setup(scen)
	if mode == "":
		mode = str(Settings.get_v("eva", "mode"))
	driver = "vr" if (mode == "vr" or (mode == "auto" and client_has_xr())) and client_connected() else "flat"
	if mode == "vr" and not client_connected():
		Voice.say("The VR headset is not connected. Starting the spacewalk on screen instead.", 1)
	for_mission = mission_eva
	if Game.warp > 1.0:
		Game.set_warp(1.0)
	active = true
	_ev_seen = 0
	_pose_buf.clear()
	penalties = 0
	result_text = ""
	if driver == "vr":
		_send_cmd("start", {"scen": scen})
	flat = FlatControl.new()
	Voice.say("Hatch open. Spacewalker is outside! %s. %s" % [scen["title"], sim.step_text()], 1)
	Sfx.tone(300.0, 0.8, 0.25, "noise", 120.0)
	Game.game_event.emit("eva_start", {"id": id})
	changed.emit()
	return true


func abort(reason: String = "Spacewalk ended by the Commander.") -> void:
	if not active:
		return
	if driver == "vr":
		_send_cmd("abort", {"reason": reason})
	_finish(false, reason)


func _finish(ok: bool, text: String) -> void:
	active = false
	last_score = sim.score if sim else 0
	result_text = text
	var m: Mission = Game.mission
	if ok:
		Voice.say("Spacewalker is back inside. Hatch closed. Great EVA! %d points." % last_score, 1)
		Sfx.chime()
	else:
		Voice.say(text + " Hatch closed.", 1)
	if Game.state == Game.State.ACTIVE and last_score > 0:
		Game.add_score("Spacewalk: %s" % str(scen.get("title", "")), last_score - penalties * 40)
	if for_mission and m and m.eva_inserted and not m.eva_done:
		m.eva_done = true
		m.advance("Spacewalk complete!" if ok else "")
	for_mission = false
	keyboard = false
	InputHub.keyboard_grab = null
	Game.game_event.emit("eva_end", {"ok": ok})
	changed.emit()


## Mission weaving (Commander > EVA > EVA IN MISSIONS). Called by Mission.advance() after the
## step counter moved: when this is the planned point, a SPACEWALK objective becomes current
## (Mission.eva_obj; the mission's own logic pauses) and the spacewalk starts.
func mission_hook(m: Mission) -> bool:
	if role != "server" or Game.test_mode or m.eva_inserted or not EvaScenarios.MISSION_EVA.has(m.id):
		return false
	if not bool(Settings.get_v("eva", "in_missions")) and Game.force_eva != str(EvaScenarios.MISSION_EVA[m.id][0]):
		return false
	var plan: Array = EvaScenarios.MISSION_EVA[m.id]
	var at := int(plan[1])
	if at < 0:
		at = m.objectives.size()
	if m.step != at or active:
		return false
	var id := str(plan[0])
	if not id in available():
		return false
	m.eva_obj = {"text": "SPACEWALK: " + str(EvaScenarios.TITLES[id]) + " (watch the HELMET CAM on the EVA page)", "role": "EVA",
		"say": "Time for a spacewalk! " + str(EvaScenarios.BRIEFS[id])}
	m.eva_inserted = true
	Game._update_objective_text()
	Game.objective_changed.emit()
	_start_for_mission.call_deferred(id, m)
	return true


func _start_for_mission(id: String, m: Mission) -> void:
	if not start(id, true):
		m.eva_done = true
		m.advance()


func blocks_engine() -> bool:
	return active


# ======================================================================== frame
func _process(_dt: float) -> void:
	if role != "server":
		return
	_net_rx()
	_net_tx()


func tick(dt: float) -> void:
	if not active or sim == null:
		return
	_update_world_inputs()
	if driver == "flat":
		var cmd: Dictionary = bot.decide(dt, sim) if bot else flat.read_devices(keyboard)
		last_cmd = cmd
		var inp := flat.apply(dt, sim, cmd)
		sim.step_sim(dt, inp)
	elif not client_connected() and _now() - _client_seen > 4.0:
		# VR client gone (headset off / crash): the spacewalker is recalled, cockpit carries on
		_finish(false, "Lost the VR headset link. Spacewalker recalled.")
		return
	_handle_events(sim.events_after(_ev_seen))
	# Pilot must hold attitude while the arm carries the spacewalker
	_hold_warn_t = maxf(0.0, _hold_warn_t - dt)
	if sim.riding and Game.sim.ang_vel.length() > deg_to_rad(1.5) and _hold_warn_t <= 0.0:
		_hold_warn_t = 6.0
		penalties += 1
		Voice.say("Pilot, hold attitude! The spacewalker is on the arm.", 2)
	if sim.done and active:
		_finish(true, "EVA complete")
	elif sim.failed == "o2" and active:
		_finish(false, "Suit oxygen empty! Spacewalker recalled.")


func _update_world_inputs() -> void:
	if sim == null:
		return
	var s: ShipSim = Game.sim
	sim.arm_ok = Game.arm_extend > 0.9 and bool(Game.powered.get("arm", false))
	sim.arm_tip = Game.arm_base_body() + Game.arm_dir_body() * Game.arm_len * Game.arm_extend + Vector3(0, -0.15, 0)
	sim.ship_w = s.basis.inverse() * s.ang_vel
	sim.ship_acc = s.basis.inverse() * s.accel_proper if s.thrust_now > 0.0 or s.in_trans.length() > 0.01 else Vector3.ZERO
	var w: WorldView = get_tree().get_first_node_in_group("world")
	sim.in_sun = w == null or not w.in_shadow
	sim.cargo_door = Game.cargo_door


func _handle_events(evs: Array) -> void:
	for e: Array in evs:
		var id := int(e[0])
		if id <= _ev_seen:
			continue
		_ev_seen = id
		var kind := str(e[1])
		var data: Dictionary = e[2]
		_log("%s %s" % [kind, data])
		match kind:
			"step":
				Voice.say("Spacewalker: " + str(data.get("text", "")))
			"step_done":
				Sfx.chime()
			"tether_taut":
				Voice.say("Tether is tight! Come back toward the hatch.")
				Sfx.tone(180.0, 0.25, 0.25, "saw")
			"knock":
				Sfx.tone(140.0, 0.07, 0.6, "sine", 90.0)
				Sfx.tone(160.0, 0.06, 0.4, "noise", -1.0, 0.01)
				if not _said_knock:
					_said_knock = true
					Voice.say("Knock knock! Someone is at the window!", 1)
			"palm":
				Voice.say("The spacewalker has a hand on your window. High five through the glass!")
			"wave":
				Voice.say("The spacewalker is waving at you! Wave back!")
			"o2_low":
				Voice.say("Spacewalker, oxygen at twenty five percent. Start heading back to the hatch.", 2)
			"o2_critical":
				Voice.say("Spacewalker, oxygen critical! Go inside now!", 2)
				Sfx.caution_chime()
			"gas_empty":
				Voice.say("Jetpack gas empty. Use the handrails.")
			"need_doors":
				Voice.say("Ops, open the cargo doors so the spacewalker can reach the antenna.", 1)
			"arm_on":
				Voice.say("Spacewalker is on the arm. Ops, fly them gently. Pilot, hold attitude.")
				Sfx.clunk()
			"arm_off":
				Sfx.clunk()
			"pick":
				Sfx.click()
			"placed":
				Sfx.clunk()
			"collected":
				Voice.say("Moon rock %d of %d!" % [int(data.get("n", 0)), int(data.get("of", 3))])
		eva_event.emit(kind, data)


var _said_knock := false


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 200:
		log_lines.pop_front()


# ======================================================================== avatar
## Where to draw the spacewalker this frame: the local sim in flat mode, else the VR client's
## stream, interpolated 45 ms in the past between the two bracketing packets.
func avatar_pose() -> Dictionary:
	if sim == null or not active:
		return {}
	if driver == "flat" or _pose_buf.is_empty():
		return sim.pose()
	var tr := _now() - 0.045
	var n := _pose_buf.size()
	if n == 1 or tr >= float(_pose_buf[n - 1][0]):
		return _pose_buf[n - 1][1]
	for k in range(n - 1, 0, -1):
		var t0 := float(_pose_buf[k - 1][0])
		var t1 := float(_pose_buf[k][0])
		if tr >= t0:
			return lerp_pose(_pose_buf[k - 1][1], _pose_buf[k][1], clampf((tr - t0) / maxf(t1 - t0, 1e-4), 0.0, 1.0))
	return _pose_buf[0][1]


static func lerp_xf(a: Transform3D, b: Transform3D, f: float) -> Transform3D:
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, f)), a.origin.lerp(b.origin, f))


static func lerp_pose(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var o := b.duplicate()
	for k: String in ["head", "l", "r"]:
		o[k] = lerp_xf(a[k], b[k], f)
	o["up"] = (a["up"] as Vector3).lerp(b["up"], f).normalized()
	o["vel"] = (a["vel"] as Vector3).lerp(b["vel"], f)
	o["jet"] = lerpf(float(a["jet"]), float(b["jet"]), f)
	return o


func telemetry() -> Dictionary:
	if sim == null:
		return {}
	return {"o2": sim.o2, "batt": sim.batt, "co2": sim.co2, "temp": sim.suit_temp, "hr": sim.heart, "gas": sim.gas,
		"tether": sim.tether_used, "tether_len": sim.tether_len, "tether_on": sim.tether_on, "step": sim.step, "steps": sim.steps.size(),
		"text": sim.step_text(), "time": sim.time_out, "score": sim.score, "riding": sim.riding, "lamp": sim.lamp,
		"progress": sim.progress, "hold": float(sim.cur_step().get("hold", 0.0))}


# ======================================================================== VR client
func launch_client(headless: bool = false, extra: Array = []) -> bool:
	if role != "server":
		return false
	if client_pid > 0 and OS.is_process_running(client_pid):
		return true
	if not headless and not _wivrn_busy:
		# start WiVRn first (off the main thread: it can take up to ~20 s), then launch
		_wivrn_busy = true
		status_msg = "Starting WiVRn server..."
		_log(status_msg)
		var th := Thread.new()
		th.start(func() -> void:
			var out: Array = []
			OS.execute(ProjectSettings.globalize_path("res://tools/wivrn_up.sh"), ["start"], out, true)
			_after_wivrn.call_deferred(th, "\n".join(out), extra))
		return true
	return _spawn_client(headless, extra, "")


var _wivrn_busy := false
var _wivrn_started := false
var status_msg := ""


func _after_wivrn(th: Thread, out: String, extra: Array) -> void:
	th.wait_to_finish()
	_wivrn_busy = false
	_wivrn_started = true
	var rt := ""
	for line in out.split("\n"):
		if line.begins_with("XR_RUNTIME_JSON="):
			rt = line.substr(16).strip_edges()
		elif line.begins_with("[WiVRn]"):
			status_msg = line
			_log(line)
	_spawn_client(false, extra, rt)


func _spawn_client(headless: bool, extra: Array, wivrn_rt: String) -> bool:
	var rt := str(Settings.get_v("eva", "xr_runtime_json"))
	if rt == "":
		rt = wivrn_rt
	if rt != "" and OS.get_environment("XR_RUNTIME_JSON") == "":
		OS.set_environment("XR_RUNTIME_JSON", rt)
	var args: Array[String] = []
	if headless:
		args.append_array(["--headless", "--audio-driver", "Dummy"])
	args.append_array(["--path", ProjectSettings.globalize_path("res://"), "--xr-mode", "on", "--",
		"--eva-client", "--eva-port=%d" % int(Settings.get_v("eva", "port")),
		"--quality=%s" % str(Settings.get_v("eva", "vr_quality"))])
	for a in extra:
		args.append(str(a))
	client_pid = OS.create_process(OS.get_executable_path(), args)
	_log("launched EVA client pid %d" % client_pid)
	return client_pid > 0


## Ask the VR client to quit and give it time to end its OpenXR session cleanly (it stops XR
## rendering, uninitializes the interface, then exits); kill it only if it hangs. WiVRn is
## stopped after the client is gone, never under a live session.
func stop_client() -> void:
	if client_pid > 0 and OS.is_process_running(client_pid):
		_send_cmd("quit", {})
		var t0 := Time.get_ticks_msec()
		while OS.is_process_running(client_pid) and Time.get_ticks_msec() - t0 < 4000:
			_net_tx()          # resent until acked / gone (UDP)
			OS.delay_msec(50)
		if OS.is_process_running(client_pid):
			_log("EVA client did not exit in 4 s: killing pid %d" % client_pid)
			OS.kill(client_pid)
	client_pid = -1
	_stop_wivrn()


## Only stops a server tools/wivrn_up.sh started (it keeps a pid file); never one Yves started.
func _stop_wivrn() -> void:
	if _wivrn_started:
		_wivrn_started = false
		OS.execute(ProjectSettings.globalize_path("res://tools/wivrn_up.sh"), ["stop"])


func _send_cmd(kind: String, data: Dictionary) -> void:
	_cmd_id += 1
	_cmds.append([_cmd_id, kind, data])


func _net_rx() -> void:
	if not _bound:
		return
	var now := _now()
	while _udp.get_available_packet_count() > 0:
		var raw := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		var v: Variant = bytes_to_var(raw)
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = v
		_client_ip = ip
		_client_port = port
		_client_seen = now
		if d.has("info"):
			client_info = d["info"]
		_client_cack = maxi(_client_cack, int(d.get("cack", 0)))
		ptt = bool(d.get("ptt", false))
		if str(d.get("t", "")) == "st" and active and driver == "vr" and sim != null and d.has("s"):
			sim.from_net(d["s"])
			_pose_buf.append([now, sim.pose()])
			while _pose_buf.size() > 24:
				_pose_buf.pop_front()
			_handle_events(d.get("ev", []))
			_rx_count += 1
	_rx_t += get_process_delta_time()
	if _rx_t >= 1.0:
		rx_hz = _rx_count / _rx_t
		_rx_count = 0
		_rx_t = 0.0
	while _cmds.size() > 0 and int(_cmds[0][0]) <= _client_cack:
		_cmds.pop_front()
	if Ics:
		Ics.touch_ptt["eva"] = ptt and client_connected()


func _net_tx() -> void:
	if not _bound or not client_connected() or _client_port == 0:
		return
	var s: ShipSim = Game.sim
	var ents := []
	for e: Dictionary in Game.entities:
		var rel := (e["pos"] as BigVec).rel(s.pos)
		if rel.length() < 5000.0:
			var p: BigVec = e["pos"]
			ents.append([e["id"], p.x(), p.y(), p.z(), e["basis"], e.get("visible", true), e["vel"]])
	_seq += 1
	var w := {"t": "w", "seq": _seq, "mid": Game.mission_id, "gt": Game.t, "px": s.pos.x(), "py": s.pos.y(), "pz": s.pos.z(),
		"vel": s.vel, "basis": s.basis, "w": s.ang_vel, "sun": Game.sun_dir, "door": Game.cargo_door,
		"arm": [Game.arm_yaw, Game.arm_pitch, Game.arm_len, Game.arm_extend, bool(Game.powered.get("arm", false))],
		"thr": s.thrust_now, "eng": s.engine_on, "dens": s.density_now, "ents": ents, "cmds": _cmds.slice(0, 4),
		"ack": _ev_seen, "state": Game.state, "eva": active, "wave": Game.crew_wave, "acc": s.accel_proper if s.thrust_now > 0.0 or s.in_trans.length() > 0.01 else Vector3.ZERO,
		"cfg": {"snap": float(Settings.get_v("eva", "snap_deg")), "vignette": float(Settings.get_v("eva", "vignette")),
			"seated": str(Settings.get_v("eva", "play_height")) == "seated"}}
	_udp.set_dest_address(_client_ip, _client_port)
	_udp.put_packet(var_to_bytes(w))


# ======================================================================== status (Commander)
## OpenXR runtime detection without loading OpenXR here: the loader's active_runtime.json,
## XR_RUNTIME_JSON, the WiVRn Flatpak, adb.
static func runtime_report() -> Dictionary:
	var home := OS.get_environment("HOME")
	var cfg_home := OS.get_environment("XDG_CONFIG_HOME")
	if cfg_home == "":
		cfg_home = home + "/.config"
	var out := {"runtime": "", "source": "", "wivrn_flatpak": false, "adb": false}
	var env := OS.get_environment("XR_RUNTIME_JSON")
	var set_rt := str(Settings.get_v("eva", "xr_runtime_json"))
	for cand: Array in [[set_rt, "setting eva/xr_runtime_json"], [env, "XR_RUNTIME_JSON"],
			[cfg_home + "/openxr/1/active_runtime.json", "~/.config/openxr/1/active_runtime.json"],
			["/etc/xdg/openxr/1/active_runtime.json", "/etc/xdg/openxr/1/active_runtime.json"]]:
		var p := str(cand[0])
		if p != "" and FileAccess.file_exists(p):
			var txt := FileAccess.get_file_as_string(p)
			var j: Variant = JSON.parse_string(txt)
			var nm := p.get_file()
			if typeof(j) == TYPE_DICTIONARY:
				var r: Dictionary = (j as Dictionary).get("runtime", {})
				nm = str(r.get("name", r.get("library_path", nm)))
			out["runtime"] = nm
			out["source"] = str(cand[1])
			break
	for fp: String in ["/var/lib/flatpak/app/io.github.wivrn.wivrn", home + "/.local/share/flatpak/app/io.github.wivrn.wivrn"]:
		if DirAccess.dir_exists_absolute(fp):
			out["wivrn_flatpak"] = true
	for ap: String in ["/usr/bin/adb", "/usr/local/bin/adb", home + "/platform-tools/adb"]:
		if FileAccess.file_exists(ap):
			out["adb"] = true
	return out


func status_text() -> String:
	var t := ""
	if client_connected():
		if client_has_xr():
			t = "VR client connected · %s · %s · %d Hz" % [str(client_info.get("runtime", "?")), str(client_info.get("system", "?")), int(client_info.get("fps", 0))]
		else:
			t = "EVA client connected (no headset: %s)" % str(client_info.get("xr_error", "flat window"))
	elif client_pid > 0 and OS.is_process_running(client_pid):
		t = "VR client starting... (pid %d)" % client_pid
	else:
		var r := runtime_report()
		if str(r["runtime"]) != "":
			t = "VR client not running · OpenXR runtime: %s" % r["runtime"]
		elif bool(r["wivrn_flatpak"]):
			t = "VR client not running · WiVRn installed, connect the Quest to make it the active runtime"
		else:
			t = "No OpenXR runtime (VR off) · flat EVA works · see docs/game/VR_SETUP.md"
	if not _bound:
		t += " · UDP port busy"
	return t
