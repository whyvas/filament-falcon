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
	return ok


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
