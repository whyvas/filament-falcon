extends Node
## Headless smoke test: for every mission, load it, do the checklist, START, run the sim,
## inject + fix every failure type once, then cheat-advance each objective with simulated
## time in between and check that the mission reaches COMPLETE with a score.
## Exit code 0 = all passed. Usage: godot --headless --path game -- --smoke-test [--only=id]

var results: Array = []
var errors := 0


func _ready() -> void:
	Game.external_clock = true
	_run.call_deferred()


func _ticks(seconds: float, dt: float = 1.0 / 60.0) -> void:
	var n := int(seconds / dt)
	for i in n:
		InputHub._process(dt)
		Game.tick(dt)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var only: String = str(Settings.cli.get("only", ""))
	for id in Game.MISSION_ORDER:
		if only != "" and id != only:
			continue
		await _run_mission(id)
	if only == "eva":
		var eva_ok := await _check_eva()
		print("RESULT: EVA %s" % ("PASS" if eva_ok else "FAIL"))
		get_tree().quit(0 if eva_ok else 1)
		return
	var ui_ok := await _check_ui()
	print("")
	print("==== SMOKE TEST SUMMARY ====")
	var failed := 0
	for r in results:
		print(r[1])
		if not r[0]:
			failed += 1
	print("RESULT: %d/%d missions passed" % [results.size() - failed, results.size()])
	print("DISPLAY/UI CHECKS: %s" % ("PASS" if ui_ok else "FAIL"))
	get_tree().quit(1 if failed > 0 or not ui_ok else 0)


## Screen-role resolver against real rigs (no real monitors needed) and every console /
## Commander page, including the three-screen "Commander as a console tab" fallback.
func _check_ui() -> bool:
	var ok := true
	var dm: DisplayManager = get_parent().get_node("Display")
	# Yves's rig, verbatim from `xrandr --listmonitors`
	var xr := DisplayManager.parse_xrandr("""Monitors: 4
 0: +*HDMI-A-0 1920/698x1080/393+0+0  HDMI-A-0
 1: +DisplayPort-2 1920/598x1080/336+1920+0  DisplayPort-2
 2: +DisplayPort-0 1080/480x1920/270+3271+1080  DisplayPort-0
 3: +DisplayPort-1 1920/600x1080/330+3840+0  DisplayPort-1""")
	var saved := dm.monitors.duplicate(true)
	var cases := [
		["4 screens, console by name", xr, "DisplayPort-0", {"left": 1, "right": 3, "console": 2, "commander": 0}],
		["4 screens, console by size", xr, "", {"left": 1, "right": 3, "console": 2, "commander": 0}],
		["3 screens (no HDMI)", xr.slice(1), "DisplayPort-0", {"left": 1, "right": 3, "console": 2, "commander": -1}],
	]
	var keep := str(Settings.get_v("display", "console_output"))
	for c: Array in cases:
		dm.monitors.clear()
		var src: Array = c[1]
		for x: Dictionary in src:
			var i := xr.find(x)
			dm.monitors.append({"i": i, "name": x["name"], "pos": x["pos"], "size": x["size"], "mm": x["mm"], "diag": (x["mm"] as Vector2).length() / 25.4, "hz": 60.0})
		Settings.cfg.set_value("display", "console_output", c[2])
		dm.resolve_roles()
		var want: Dictionary = c[3]
		var good := true
		for r in want:
			if dm.screen_of(r) != int(want[r]):
				good = false
		print("  display roles [%s]: %s  %s" % [c[0], "ok" if good else "WRONG", str(dm.assign)])
		ok = ok and good
	Settings.cfg.set_value("display", "console_output", keep)
	dm.monitors = saved
	dm.resolve_roles()
	# every page of both UIs refreshes without errors
	for p in ConsoleUI.PAGES:
		dm.console.show_page(p)
		await _frames(2)
	for p in CommanderUI.PAGES:
		dm.commander.show_page(p)
		await _frames(2)
	var cc: Control = dm.cont["commander"]
	var parent := cc.get_parent()
	dm.console.embed_commander(cc)
	dm.console.toggle_commander()
	await _frames(2)
	ok = ok and dm.console.current == "COMMANDER"
	dm.console.release_commander()
	if parent:
		parent.add_child(cc)
	ok = ok and not dm.console.has_commander_tab()
	print("  console + commander pages, commander tab fallback: %s" % ("ok" if ok else "FAIL"))
	ok = (await _check_virtual(dm)) and ok
	ok = _check_pod() and ok
	ok = (await _check_ics()) and ok
	ok = (await _check_eva()) and ok
	ok = (await _check_ground()) and ok
	ok = (await _check_slew()) and ok
	return ok


## REFUEL + debug slew while paused (ship move, free cam, resume with zeroed velocity) in orbit,
## at the station, around the Moon and over Fredericton.
func _check_slew() -> bool:
	var ok := true
	for dest: String in ["STATION", "MOON ORBIT", "FREDERICTON", "LAUNCH PAD"]:
		Game.load_mission("sandbox")
		await _frames(2)
		Game.auto_checklist()
		_ticks(0.3)
		Game.try_start()
		Game.mission.call("go_to_name", dest)
		_ticks(0.5)
		var sim: ShipSim = Game.sim
		sim.fuel = 100.0
		sim.mono = 10.0
		Game.o2 = 40.0
		Game.refuel(0.25)
		var part := absf(sim.fuel - (100.0 + sim.fuel_max * 0.25)) < 1.0 and absf(Game.o2 - 65.0) < 0.5
		Game.refuel(1.0)
		var full: bool = sim.fuel == sim.fuel_max and sim.mono == sim.mono_max and Game.o2 == 100.0 and Game.commander_log.back().contains("REFUEL FULL")
		Game.start_pause()
		var paused := Game.state == Game.State.PAUSED
		var p0 := sim.pos.copy()
		var b0: Basis = sim.basis
		var sl: DebugSlew = Game.slew
		sl.start(Game, "ship")
		sl.speed_i = 3                                  # 100 m/s
		sl.rot_i = 2                                    # 20 deg/s
		for i in 60:
			sl.apply(Game, Vector3(0, 0, 1), Vector3(0, 1, 0), 1.0 / 60.0)
		var d := sim.pos.rel(p0)
		var ang := rad_to_deg((b0.z).angle_to(sim.basis.z))
		var ship_ok := absf(d.length() - 100.0) < 1.0 and absf(ang - 20.0) < 0.5
		sl.set_mode(Game, "cam")
		var p1 := sim.pos.copy()
		for i in 30:
			sl.apply(Game, Vector3(1, 0, 0), Vector3.ZERO, 1.0 / 60.0)
		await _frames(2)                                # render path with the free camera
		var cam_ok := sim.pos.rel(p1).length() < 0.001 and absf(sl.view_pos(Game).rel(p1).length() - 50.0) < 0.5
		sl.set_mode(Game, "ship")
		sl.apply(Game, Vector3(0, 1, 0), Vector3.ZERO, 0.1)
		sl.zero_vel = true
		sim.vel = sim.vel + Vector3(50, 0, 0)
		Game.start_pause()                               # resume: slew off, velocity matched to the body
		var vrel := (sim.vel - sim.dominant.vel).length()
		var res_ok := Game.state == Game.State.ACTIVE and not sl.active and vrel < 0.01
		var good: bool = part and full and paused and ship_ok and cam_ok and res_ok
		print("  refuel + debug slew [%s]: refuel +25%%=%s full=%s, ship moved %.1f m / turned %.1f°, free cam=%s, resume v_rel=%.2f m/s: %s" % [
			dest, part, full, d.length(), ang, cam_ok, vrel, "ok" if good else "FAIL"])
		ok = ok and good
	return ok


## GROUND CREW phone page: the built-in HTTP server answers the page, status and a button.
func _check_ground() -> bool:
	var gl := GroundLink.get_link()
	await _frames(2)
	var got := {}
	for path: String in ["/", "/s", "/c?x=hello"]:
		var c := HTTPClient.new()
		c.connect_to_host("127.0.0.1", gl.port)
		var body := PackedByteArray()
		for i in 300:
			c.poll()
			var st := c.get_status()
			if st == HTTPClient.STATUS_CONNECTED:
				c.request(HTTPClient.METHOD_GET, path, [])
			elif st == HTTPClient.STATUS_BODY:
				body.append_array(c.read_response_body_chunk())
			elif st == HTTPClient.STATUS_DISCONNECTED and body.size() > 0:
				break
			await _frames(1)
		got[path] = body.get_string_from_utf8()
	var ok: bool = str(got["/"]).contains("MISSION CONTROL") and str(got["/s"]).contains("objective") and str(got["/c?x=hello"]).contains("ok") and gl.presses >= 1
	print("  ground crew web page (port %d, %s): %s" % [gl.port, " ".join(gl.urls()), "ok" if ok else "FAIL " + str(got.keys().map(func(k: String) -> int: return str(got[k]).length()))])
	return ok


# ======================================================================== spacewalks
var _eva_seen := {}
var _eva_vis := {}


## Spacewalks in flat mode (no headset): an autopilot spacewalker climbs the handrails, does
## the task and comes back inside; the avatar must be in view of the cockpit windows when it
## waves / knocks. Also: XR is never initialised in the cockpit process.
func _check_eva() -> bool:
	var ok := true
	var xr_if := XRServer.find_interface("OpenXR")
	var xr_clean := (xr_if == null or not xr_if.is_initialized()) and XRServer.primary_interface == null and not get_viewport().use_xr
	print("  XR off in the cockpit process (no runtime needed): %s  [%s]" % ["ok" if xr_clean else "FAIL", Eva.status_text().replace("\n", " | ")])
	ok = ok and xr_clean
	if not Eva.eva_event.is_connected(_on_eva_event):
		Eva.eva_event.connect(_on_eva_event)
	Game.load_mission("docking")
	await _frames(3)
	Game.auto_checklist()
	_ticks(0.5)
	Game.try_start()
	_ticks(2.0)
	for id: String in str(Settings.cli.get("eva-only", "window,rescue")).split(",", false):
		ok = (await _eva_run(id, 900.0)) and ok
	# dock (cheat) for the station antenna job; Ops opens the cargo doors
	var m: Mission = Game.mission
	var guard := 0
	while not EvaScenarios.docked(Game) and guard < 12 and Game.state == Game.State.ACTIVE:
		m.cheat_advance()
		_ticks(1.0)
		guard += 1
	if EvaScenarios.docked(Game):
		ok = (await _eva_run("antenna", 1200.0)) and ok
	else:
		print("  EVA antenna: could not dock (step %d) FAIL" % m.step)
		ok = false
	InputHub.set_switch("cargo_doors", false)
	InputHub.set_group("ops", 0)
	ok = (await _check_eva_link()) and ok
	return ok


## The VR client path without a headset: spawn the client process (headless, XR unavailable,
## autopilot), start a "VR" spacewalk, and check the cockpit receives the pose stream at
## >= 60 Hz and draws the avatar smoothly (interpolated, no jumps).
func _check_eva_link() -> bool:
	if Eva.client_connected():
		Eva.stop_client()
	var launched := Eva.launch_client(true, ["--eva-bot"])
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and not Eva.client_connected():
		Game.tick(get_process_delta_time())
		await _frames(1)
	var connected := Eva.client_connected()
	var xr_reported := bool(Eva.client_info.get("xr", true))
	var started := connected and Eva.start("window", false, "vr")
	var wv: WorldView = get_parent().get_node("World")
	var prev := Vector3.INF
	var max_jump := 0.0
	var frames := 0
	var moved := 0.0
	var hz_samples: Array[float] = []
	t0 = Time.get_ticks_msec()
	var first_step := Eva.sim.step if Eva.sim else 0
	while started and Eva.active and Time.get_ticks_msec() - t0 < 40000:
		Game.tick(minf(get_process_delta_time(), 0.05))
		await _frames(1)
		frames += 1
		var p := wv.eva_view.current_pose()
		if not p.is_empty():
			var hp: Vector3 = (p["head"] as Transform3D).origin
			if prev != Vector3.INF:
				var j := hp.distance_to(prev)
				if j > 0.2 and Settings.cli.has("eva-debug"):
					print("    jump %.2f m at frame %d step %d edge %d riding %s perch %s" % [j, frames, Eva.sim.step, Eva.sim.att_edge, Eva.sim.riding, Eva.sim.perch])
				max_jump = maxf(max_jump, j)
				moved += j
			prev = hp
		if frames % 30 == 0 and Eva.rx_hz > 0.0:
			hz_samples.append(Eva.rx_hz)
		if Eva.sim and Eva.sim.step >= 3:
			break        # traverse + pull to the window + wave done: enough for the link check
	var steps_done := (Eva.sim.step - first_step) if Eva.sim else 0
	if Eva.active:
		Eva.abort("link test done")
	var moon_ok := await _check_moon_sync() if connected else false
	Eva.stop_client()
	var hz := 0.0
	for h in hz_samples.slice(1):
		hz += h
	hz /= maxf(hz_samples.size() - 1, 1)
	var ok := launched and connected and not xr_reported and started and hz >= 60.0 and moved > 2.0 and max_jump < 0.25 and steps_done >= 2 and moon_ok
	print("  EVA VR-client link (headless client, XR unavailable -> autopilot): connected=%s xr=%s stream %.0f Hz, avatar moved %.1f m, max frame jump %.3f m, steps %d: %s" % [connected, xr_reported, hz, moved, max_jump, steps_done, "ok" if ok else "FAIL"])
	return ok


## Moonwalk sync (the "rocks jitter in the headset" bug): parked on the Moon (which orbits at
## ~540 m/s in game scale), the VR client must keep the landing site / its rocks steady
## relative to the ship between world snapshots. The client reports its worst frame jump.
func _check_moon_sync() -> bool:
	Game.load_mission("lunar")
	await _frames(3)
	Game.auto_checklist()
	_ticks(0.5)
	Game.try_start()
	_ticks(1.0)
	var sim: ShipSim = Game.sim
	var pad: Dictionary = Game.entities_of("lunar_pad")[0]
	var moon: CelestialBody = Game.moon
	var up: Vector3 = (pad["pos"] as BigVec).rel(moon.pos).normalized()
	sim.gear_down = true
	sim.gear_pos = 1.0
	var p: BigVec = (pad["pos"] as BigVec).copy()
	p.add(up * 3.5 + up.cross(Vector3.UP).normalized() * 20.0)
	sim.pos.set_from(p)
	sim.vel = moon.vel
	_ticks(4.0)
	var landed := EvaScenarios.on_moon(Game)
	var started := landed and Eva.start("moonwalk", false, "vr")
	var worst := 0.0
	var t0 := Time.get_ticks_msec()
	var n := 0
	while started and Eva.active and Time.get_ticks_msec() - t0 < 6000:
		Game.tick(minf(get_process_delta_time(), 0.05))
		await _frames(1)
		n += 1
		if Time.get_ticks_msec() - t0 > 2500:      # after the client has settled on the stream
			worst = maxf(worst, float(Eva.client_info.get("ent_jit", 99.0)))
	if Eva.active:
		Eva.abort("moon sync test done")
	var ok := started and worst < 0.05
	print("  EVA VR-client moon sync (landed=%s, lunar site vs ship, worst client frame jump %.3f m over %d frames): %s" % [landed, worst, n, "ok" if ok else "FAIL"])
	return ok


func _on_eva_event(kind: String, _d: Dictionary) -> void:
	_eva_seen[kind] = int(_eva_seen.get(kind, 0)) + 1


func _eva_run(id: String, max_s: float) -> bool:
	_eva_seen.clear()
	_eva_vis.clear()
	if id == "antenna" or id == "rescue":
		InputHub.set_switch("cargo_doors", true)
		InputHub.set_group("ops", 1)
		_ticks(4.0)
	Eva.bot = EvaBot.new()
	if not Eva.start(id, false, "flat"):
		print("  EVA %s: refused to start (available %s) FAIL" % [id, Eva.available()])
		Eva.bot = null
		return false
	var sim: EvaSim = Eva.sim
	var dm: DisplayManager = get_parent().get_node("Display")
	var wv: WorldView = get_parent().get_node("World")
	var dt := 1.0 / 30.0
	var t := 0.0
	var path := 0.0
	var far := 0.0
	var prev := sim.head_s().origin
	var n := 0
	var hold_bad := 0
	while Eva.active and t < max_s:
		if id in ["rescue", "antenna"]:
			_fly_arm(sim, dt)
		_ticks(dt, dt)
		t += dt
		n += 1
		var h := sim.head_s().origin
		path += h.distance_to(prev)
		prev = h
		far = maxf(far, h.distance_to(sim.hatch))
		if Settings.cli.has("eva-debug") and n % 30 == 0:
			var c2 := Eva.last_cmd.duplicate()
			c2.erase("look_at")
			print("    t=%.0f step=%d %s head=%s edge=%d u=%.2f vel=%s cmd=%s" % [t, sim.step, sim.cur_step().get("do", ""), sim.head_s().origin.snapped(Vector3.ONE * 0.01), sim.att_edge, sim.att_u, sim.vel.snapped(Vector3.ONE * 0.01), c2])
		if sim.riding and Game.sim.ang_vel.length() > deg_to_rad(1.5):
			hold_bad += 1
		var gest := str(sim.cur_step().get("do", "")) == "gesture"
		if n % 90 == 0 or (gest and n % 6 == 0):
			await _frames(1)
			if str(sim.cur_step().get("do", "")) == "gesture" and wv.eva_view.avatar.visible:
				var hp: Vector3 = (wv.eva_view.avatar.parts["helmet"] as Node3D).global_position
				for v: String in dm.out_views:
					var cam: Camera3D = dm.cams[v]
					if cam.is_position_in_frustum(hp):
						_eva_vis[v] = true
					if Settings.cli.has("eva-debug"):
						print("    vis %s head=%s cam=%s near=%.2f in=%s vp=%s" % [v, hp, cam.global_transform.origin, cam.near, cam.is_position_in_frustum(hp), cam.get_viewport().get_visible_rect().size])
	Eva.bot = null
	var done := not Eva.active and sim.done
	if Eva.active:
		Eva.abort("test timeout")
	var line := "  EVA %-8s %s  steps %d/%d  score %d  path %.1f m (max %.1f m from hatch)  %.0f s sim  events %s" % [id,
		"ok" if done else "FAIL", sim.step, sim.steps.size(), sim.score, path, far, t, str(_eva_seen.keys())]
	var good := done and path > 3.0
	if id == "window":
		var vis := _eva_vis.size() > 0
		good = good and vis and _eva_seen.has("knock") and _eva_seen.has("wave")
		line += "  in window view: %s" % str(_eva_vis.keys())
	if id == "rescue":
		good = good and _eva_seen.has("arm_on") and hold_bad == 0
	if not good and done:
		line = line.replace(" ok ", " FAIL ")
	print(line)
	if not good:
		for l in Eva.log_lines.slice(-12):
			print("      log: " + l)
	return good


## "Ops" flies the arm tip to the spacewalker (grab), then to the hatch (ride) with the real
## arm axes (tx/ty/tz in arm mode), gently.
func _fly_arm(sim: EvaSim, _dt: float) -> void:
	var step := str(sim.cur_step().get("do", ""))
	var target := Vector3.ZERO
	if step == "grab_arm" and not sim.riding:
		target = sim.waist_s() + (sim.head_s().basis.z * 0.0) - Vector3(0, 0.0, 0)
	elif sim.riding:
		target = sim.cur_step().get("at", sim.hatch)
	else:
		for a in ["tx", "ty", "tz"]:
			InputHub.set_axis_override(a, 0.0)
		return
	var base := Game.arm_base_body()
	var d := target - base
	var L := clampf(d.length(), 3.0, 12.0)
	var pitch := asin(clampf(d.y / maxf(d.length(), 0.01), -1.0, 1.0))
	var yaw := atan2(-d.x, -d.z)
	var gain := 1.5
	InputHub.set_axis_override("tx", clampf(-(yaw - Game.arm_yaw) * gain, -0.5, 0.5))
	InputHub.set_axis_override("ty", clampf((pitch - Game.arm_pitch) * gain, -0.5, 0.5))
	InputHub.set_axis_override("tz", clampf((L - Game.arm_len) * 0.6, -0.5, 0.5))


## Virtual panels: hot-plug show/hide, the guarded two-tap, held buttons, the encoder.
func _check_virtual(dm: DisplayManager) -> bool:
	var con: ConsoleUI = dm.console
	var ok := true
	for d: String in InputHub.BOARDS:
		InputHub.fake_device(d, true)
	await _frames(2)
	var hidden_ok: bool = not (con.tabs["PANELS"] as Button).visible
	InputHub.fake_device(InputHub.DEV_PILOT, false)
	await _frames(2)
	var pilot_ok: bool = (con.tabs["PANELS"] as Button).visible and (con._virt[InputHub.DEV_PILOT][0] as Control).visible and not (con._virt[InputHub.DEV_OPS][0] as Control).visible
	InputHub.fake_device(InputHub.DEV_CMD, false)
	await _frames(2)
	var cmd_ok: bool = (con._virt[InputHub.DEV_CMD][0] as Control).visible
	InputHub.fake_device(InputHub.DEV_PILOT, true)
	InputHub.fake_device(InputHub.DEV_CMD, true)
	Settings.set_v("input", "force_virtual_panels", true, false)
	await _frames(2)
	var force_ok: bool = (con.tabs["PANELS"] as Button).visible
	Settings.set_v("input", "force_virtual_panels", false, false)
	InputHub.clear_fakes()
	await _frames(2)
	ok = hidden_ok and pilot_ok and cmd_ok and force_ok
	print("  virtual panels hot-plug: all plugged=%s, pilot missing=%s, cmd missing=%s, forced=%s" % [hidden_ok, pilot_ok, cmd_ok, force_ok])
	# interaction on a real layout (no hardware here, so latches decide)
	var vp := VirtualPanel.make("PILOT_DASH_A")
	vp.size = Vector2(600, 480)
	add_child(vp)
	vp._layout()
	var pos := {}
	for c: Dictionary in vp.controls():
		pos[str(c.get("action", c.get("id", "")))] = vp.to_px(float(c["x"]), float(c["y"]))
	InputHub.set_switch("engine_arm", false)
	vp._pointer_down(0, pos["engine_arm"])
	vp._pointer_up(0)
	_ticks(0.05)
	var guard1 := not InputHub.on("engine_arm")       # first tap only lifts the cover
	vp._pointer_down(0, pos["engine_arm"])
	vp._pointer_up(0)
	_ticks(0.05)
	var guard2 := InputHub.on("engine_arm")
	vp._pointer_down(3, pos["horn"])
	_ticks(0.05)
	var held := InputHub.on("horn")
	vp._pointer_up(3)
	_ticks(0.05)
	var rel := not InputHub.on("horn")
	InputHub.set_switch("engine_arm", false)
	vp.queue_free()
	var vb := VirtualPanel.make("PILOT_DASH_B")
	vb.size = Vector2(600, 480)
	add_child(vb)
	vb._layout()
	var enc: Dictionary = vb.controls()[0]
	var fa0 := InputHub.group("fa")
	vb._pointer_down(0, vb.to_px(float(enc["x"]) + 12.0, float(enc["y"])))
	vb._pointer_up(0)
	_ticks(0.05)
	var enc_ok := InputHub.group("fa") == (fa0 + 1) % InputHub.FA_COUNT
	InputHub.set_group("fa", fa0)
	vb.queue_free()
	var vok := guard1 and guard2 and held and rel and enc_ok
	print("  virtual panel touch: guard needs 2 taps=%s, button held/released=%s/%s, encoder=%s" % [guard1 and guard2, held, rel, enc_ok])
	return ok and vok


## Crew-position monitor: pod/seat states and callouts from the read-only contacts.
func _check_pod() -> bool:
	var p := PodMonitor.new()
	p.travel_s = 10.0
	var ev: Array[String] = []
	ev += p.update(0.1, false, false, false)
	var s0 := p.pod == PodMonitor.Pod.UP and p.seats == PodMonitor.Seats.UPRIGHT
	ev += p.update(0.1, true, false, false)
	var s1 := ev.has("pod_coming_down") and p.seats == PodMonitor.Seats.RECLINED
	ev += p.update(0.1, true, true, false)
	var s2 := p.pod == PodMonitor.Pod.DOWN_LOCKED and ev.has("pod_down")
	ev += p.update(0.1, true, false, false)
	var s3 := p.pod == PodMonitor.Pod.MOVING and ev.has("pod_going_up")
	for i in 120:
		p.update(0.1, true, false, false)
	var s4 := p.pod == PodMonitor.Pod.UNKNOWN_UP_OR_MOVING
	ev += p.update(0.1, false, false, false)
	var s5 := p.pod == PodMonitor.Pod.UP and p.seats == PodMonitor.Seats.MOVING and ev.has("seats_coming_up")
	# with the optional UP contact fitted
	var q := PodMonitor.new()
	q.update(0.1, false, false, true)
	q.update(0.1, true, false, true)
	var u1 := q.pod == PodMonitor.Pod.UP and q.has_up_sense()
	var e2 := q.update(0.1, true, false, false)
	var u2 := q.pod == PodMonitor.Pod.MOVING and e2.has("pod_coming_down")
	var ok := s0 and s1 and s2 and s3 and s4 and s5 and u1 and u2
	print("  pod monitor (no up sense: %s %s %s %s %s %s, with up sense: %s %s): %s" % [s0, s1, s2, s3, s4, s5, u1, u2, "ok" if ok else "FAIL"])
	return ok


## Intercom end-to-end with the helper in --mock mode (fake headsets, no audio devices):
## hello -> device list, touch PTT opens the Ops mic. Skipped when python3 + numpy are missing.
func _check_ics() -> bool:
	if OS.execute("python3", ["-c", "import numpy"]) != 0:
		print("  intercom mock: skipped (python3-numpy not installed)")
		return true
	var was := Ics.enabled
	var was_set: Variant = Settings.get_v("ics", "enabled")
	Ics.stop()
	Settings.cfg.set_value("ics", "enabled", true)   # else a runtime "ics" change switches it off again
	Ics.start(true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and (not Ics.ok() or Ics.devices.size() < 3):
		await _frames(1)
	var up := Ics.ok() and Ics.devices.size() >= 3
	Settings.set_v("ics", "ops_mode", "ptt", false)
	Ics.touch_ptt["ops"] = true
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and not Ics.keyed("ops"):
		await _frames(1)
	var keyed := Ics.keyed("ops")
	Ics.touch_ptt["ops"] = false
	# IDENTIFY a station: the chime must come out of THAT station's output (meter)
	Ics.identify_seat("pilot")
	var ident_lvl := -90.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and ident_lvl < -30.0:
		ident_lvl = maxf(ident_lvl, float(Ics.seat("pilot").get("out_level", -90.0)))
		await _frames(1)
	keyed = keyed and ident_lvl > -30.0
	Settings.set_v("ics", "ops_mode", "vox", false)
	Ics.stop()
	Settings.cfg.set_value("ics", "enabled", was_set)
	if was:
		Ics.start(Ics.mock)
	var ok := up and keyed
	print("  intercom mock helper: link+devices=%s, touch PTT keys ops=%s: %s" % [up, keyed, "ok" if ok else "FAIL (%s)" % Ics.state_text])
	return ok


func _run_mission(id: String) -> void:
	var t0 := Time.get_ticks_msec()
	Game.load_mission(id)
	await _frames(3)
	Game.auto_checklist()
	_ticks(0.5)
	if not Game.try_start():
		results.append([false, "FAIL %-10s could not START (checklist %d)" % [id, Game.checklist_progress]])
		return
	_ticks(3.0)
	await _frames(2)
	# Failures: inject and fix through the real crew actions where possible
	InputHub.set_switch("pwr_sensors", true)
	_ticks(0.5)
	for k in ["fire", "leak", "power", "sensor"]:
		Game.inject_failure(k)
		print("    inject %s  reactor=%s sensors=%s" % [k, InputHub.on("pwr_reactor"), InputHub.on("pwr_sensors")])
		_ticks(0.5)
		match k:
			"fire":
				var armed := InputHub.on("engine_arm")
				InputHub.set_switch("engine_arm", false)
				_ticks(0.2)
				InputHub.pulse("fire_suppress", 3)
				_ticks(0.2)
				InputHub.set_switch("engine_arm", armed)
			"leak":
				Game.leak_sealed = true
			"power":
				InputHub.set_switch("pwr_reactor", false)
				_ticks(2.5)
				InputHub.set_switch("pwr_reactor", true)
			"sensor":
				InputHub.set_switch("pwr_sensors", false)
				_ticks(1.0)
				InputHub.set_switch("pwr_sensors", true)
		_ticks(1.5)
		if Game.failures[k]:
			Game.fix_failure(k)
			print("  note: %s failure fixed by fallback" % k)
	Game.reset_caution()
	var m: Mission = Game.mission
	var guard := 0
	while Game.state == Game.State.ACTIVE and guard < 40:
		guard += 1
		m.cheat_advance()
		_ticks(1.0)
		await _frames(1)
	await _frames(3)
	var ok := Game.state == Game.State.COMPLETE and Game.score_total > 0
	var line := "%s %-10s state=%s steps=%d/%d score=%d stars=%d hull=%d%% (%d ms)" % ["PASS" if ok else "FAIL", id,
		Game.STATE_NAMES[Game.state], m.step, m.objectives.size(), Game.score_total, Game.stars, int(Game.hull), Time.get_ticks_msec() - t0]
	if not ok:
		line += " result='%s'" % Game.result_text
	print(line)
	results.append([ok, line])
