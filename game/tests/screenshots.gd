extends Node
## Captures the README hero shots. Run under xvfb + lavapipe (see tests/run_screenshots.sh):
##   godot --path game --audio-driver Dummy --resolution 1920x1080 -- --dev --screenshots=../docs/game/screenshots
## Every shot sets up a scene with the real mission code, steps the simulation, waits for the
## renderer, and saves the window as PNG.

var out_dir := ""
var display: DisplayManager
var settle := 6


func _ready() -> void:
	out_dir = str(Settings.cli.get("screenshots", "user://screenshots"))
	if out_dir.is_relative_path() and not out_dir.begins_with("user://") and not out_dir.begins_with("res://"):
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	settle = int(Settings.cli.get("settle", 6))
	Game.external_clock = true
	display = get_parent().get_node("Display")
	_run.call_deferred()


func _ticks(seconds: float, dt: float = 1.0 / 60.0) -> void:
	for i in int(seconds / dt):
		InputHub._process(dt)
		Game.tick(dt)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _start(id: String) -> void:
	Game.load_mission(id)
	Game.auto_checklist()
	InputHub.set_switch("pwr_sensors", true)
	_ticks(0.3)
	Game.try_start()
	_ticks(0.2)


func _shot(file_name: String, solo: String = "") -> void:
	display.solo(solo)
	await _frames(settle)
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(file_name + ".png")
	var err := img.save_png(path)
	print("SCREENSHOT %s %s (%dx%d)" % [path, "ok" if err == OK else "ERROR %d" % err, img.get_width(), img.get_height()])
	display.solo("")


func _run() -> void:
	var only: String = str(Settings.cli.get("only", ""))
	var shots := ["launch_pad", "launch_ascent", "orbit_station", "docking", "lunar", "asteroids", "reentry", "runway", "celebration", "console_pages", "commander"]
	for s in shots:
		if only != "" and not only.split(",").has(s):
			continue
		var t0 := Time.get_ticks_msec()
		await call("_shot_" + s)
		print("  %s took %d ms" % [s, Time.get_ticks_msec() - t0])
	print("SCREENSHOTS DONE")
	get_tree().quit(0)


func _shot_launch_pad() -> void:
	Game.load_mission("launch")
	Game.auto_checklist()
	_ticks(0.5)
	Game.view_mode = 1
	await _shot("01_launch_pad_chase", "left")
	Game.view_mode = 0
	await _shot("02_cockpit_tiled_briefing")


func _shot_launch_ascent() -> void:
	_start("launch")
	var m: Mission = Game.mission
	InputHub.set_switch("engine_arm", true)
	InputHub.set_axis_override("throttle", 1.0)
	_ticks(0.3)
	Game.sim.engine_on = true
	_ticks(10.5)
	InputHub.set_group("fa", 2)   # PROGRADE assist following GUIDANCE
	_ticks(22.0)
	Game.view_mode = 1
	await _shot("03_launch_ascent_chase", "left")
	Game.view_mode = 0
	await _shot("04_launch_ascent_cockpit", "right")
	InputHub.set_axis_override("throttle", 0.0)
	InputHub.set_switch("engine_arm", false)
	m.step = m.step


func _shot_orbit_station() -> void:
	_start("docking")
	_ticks(1.0)
	await _shot("05_orbit_station_tiled")
	await _shot("06_orbit_station_left", "left")


func _shot_docking() -> void:
	_start("docking")
	var m: Mission = Game.mission
	# put the ship 18 m from the port, aligned
	var st: Dictionary = Game.station
	var n: Vector3 = (st["basis"] as Basis) * Vector3(0, 0, 1)
	var p: BigVec = (st["pos"] as BigVec).copy()
	p.add((st["basis"] as Basis) * Vector3(0, 0, 21) + n * 25.8 + Vector3(0.3, 0.2, 0))
	Game.sim.pos.set_from(p)
	Game.sim.vel = m.call("frame_vel", Game.sim.pos.rel(st["pos"]))
	Game.sim.basis = m.ship_basis(-n, (st["basis"] as Basis).y)
	Game.sim.ang_vel = Vector3.ZERO
	m.step = 2
	_ticks(0.5)
	await _shot("07_docking_ops", "right")
	Game.view_mode = 1
	await _shot("08_docking_chase", "left")
	Game.view_mode = 0


func _shot_lunar() -> void:
	_start("lunar")
	Game.scanner_ping()
	_ticks(20.0)
	# look down the descent path: retrograde, nose ~40 deg below the horizon
	InputHub.set_group("fa", ShipSim.FA.STAB)
	var sim: ShipSim = Game.sim
	var retro := -(sim.surface_vel - sim.up_dir * sim.surface_vel.dot(sim.up_dir)).normalized()
	sim.basis = Mission.ship_basis(retro - sim.up_dir * 0.85, sim.up_dir)
	sim.ang_vel = Vector3.ZERO
	_ticks(0.3)
	await _shot("09_lunar_descent", "left")
	Game.view_mode = 1
	await _shot("10_lunar_chase", "right")
	Game.view_mode = 0


func _shot_asteroids() -> void:
	_start("asteroids")
	_ticks(1.0)
	Game.view_mode = 0
	await _shot("11_asteroid_field", "left")
	Game.laser_on = true
	Game.view_mode = 1
	await _shot("12_asteroid_chase", "right")
	Game.view_mode = 0
	Game.laser_on = false


func _shot_reentry() -> void:
	_start("reentry")
	InputHub.set_switch("pwr_shields", true)
	InputHub.set_group("fa", 1)
	var sim: ShipSim = Game.sim
	var t := 0.0
	while t < 400.0 and sim.heat_flux < 150000.0:
		_ticks(2.0)
		t += 2.0
	print("  reentry: t=%d alt=%d heat=%d kW/m2 T=%d K" % [int(t), int(sim.altitude), int(sim.heat_flux / 1000.0), int(sim.hull_temp)])
	Game.view_mode = 1
	await _shot("13_reentry_plasma_chase", "left")
	Game.view_mode = 0
	await _shot("14_reentry_plasma_cockpit", "right")


func _shot_runway() -> void:
	Game.load_mission("sandbox")
	Game.auto_checklist()
	_ticks(0.3)
	Game.try_start()
	Game.mission.call("go_to", 3)
	InputHub.set_switch("gear", true)
	_ticks(3.0)
	await _shot("15_runway_approach", "left")
	Game.view_mode = 1
	await _shot("16_runway_chase", "right")
	Game.view_mode = 0


func _shot_celebration() -> void:
	_start("docking")
	var m: Mission = Game.mission
	while Game.state == Game.State.ACTIVE:
		m.cheat_advance()
		_ticks(0.5)
	Game.view_mode = 1
	await _frames(20)
	await _shot("17_mission_complete")
	Game.view_mode = 0


func _shot_console_pages() -> void:
	# the kids' console mid-docking: camera on the port, Ops in RCS mode
	_start("docking")
	InputHub.set_group("ops", 0)
	_ticks(3.0)
	var con: ConsoleUI = display.console
	var i := 18
	for p in ["FLIGHT", "NAV", "SYSTEMS", "CAMERAS"]:
		con.show_page(p)
		if p == "SYSTEMS":
			Game.inject_failure("leak")
			_ticks(0.5)
		await _frames(3)
		await _shot("%02d_console_%s" % [i, p.to_lower()], "console")
		i += 1
	# checklist before launch, half done
	Game.load_mission("launch")
	for id in Game.CHECKLIST:
		InputHub.set_switch(id, false)
	_ticks(0.2)
	for k in 3:
		InputHub.set_switch(Game.CHECKLIST[k], true)
		_ticks(0.2)
	con.show_page("CHECKLIST")
	await _frames(3)
	await _shot("%02d_console_checklist" % i, "console")
	con.show_page("FLIGHT")


func _shot_commander() -> void:
	_start("docking")
	_ticks(4.0)
	Game.inject_failure("power")
	_ticks(1.0)
	var cmd: CommanderUI = display.commander
	var i := 23
	for p in ["MISSION CONTROL", "BRIEFING", "TRAINING", "CONTROLS", "SETUP"]:
		cmd.show_page(p)
		await _frames(3)
		await _shot("%02d_commander_%s" % [i, p.to_lower().replace(" ", "_")], "commander")
		i += 1
	cmd.show_page("MISSION CONTROL")
	# three-screen fallback: the Commander UI as a tab on the console
	var c: Control = display.cont["commander"]
	display.console.embed_commander(c)
	display.console.show_page("COMMANDER")
	await _frames(4)
	await _shot("%02d_console_commander_tab" % i, "console")
	display.console.release_commander()
	display.dev_root.add_child(c)
	display._layout_tiles()
	await _frames(2)
