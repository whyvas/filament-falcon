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
	print("")
	print("==== SMOKE TEST SUMMARY ====")
	var failed := 0
	for r in results:
		print(r[1])
		if not r[0]:
			failed += 1
	print("RESULT: %d/%d missions passed" % [results.size() - failed, results.size()])
	get_tree().quit(1 if failed > 0 else 0)


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
