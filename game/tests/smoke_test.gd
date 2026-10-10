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
