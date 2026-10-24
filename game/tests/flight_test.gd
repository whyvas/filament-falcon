extends Node
## Flight test: robot crews genuinely fly every mission with the SAME controls the kids use
## (stick/throttle axes, switches, buttons, assist modes, nav vector): no cheat_advance.
## This proves each mission is physically completable with the real 6-DOF sim.
## Usage: godot --headless --path game --audio-driver Dummy -- --flight-test [--only=lunar] [--trace]

const DT := 1.0 / 30.0
var results: Array = []
var trace := false
var _last_trace := -999.0
var _pulse_t := {}


func _ready() -> void:
	Game.external_clock = true
	trace = Settings.cli.has("trace")
	_run.call_deferred()


func _run() -> void:
	var only: String = str(Settings.cli.get("only", ""))
	for id in Game.MISSION_ORDER:
		if (only != "" and not only.split(",").has(id)) or not has_method("_fly_" + id):
			continue   # newer missions (MISSIONS page extras) are covered by the smoke test only
		var t0 := Time.get_ticks_msec()
		await call("_fly_" + id)
		var ok := Game.state == Game.State.COMPLETE
		var m: Mission = Game.mission
		var line := "%s %-10s state=%s step=%d/%d score=%d stars=%d mission_time=%ds hull=%d%% maxG=%.1f (%d ms)" % [
			"PASS" if ok else "FAIL", id, Game.STATE_NAMES[Game.state], m.step, m.objectives.size(), Game.score_total, Game.stars,
			int(Game.mission_time), int(Game.hull), Game.sim.max_g, Time.get_ticks_msec() - t0]
		if not ok:
			line += " result='%s' objective='%s'" % [Game.result_text, str(m.current_objective().get("text", ""))]
		else:
			for it in Game.score_items:
				line += "\n      %-28s %+d" % [str(it[0]), int(it[1])]
		print(line)
		results.append([ok, line.split("\n")[0]])
		_reset_inputs()
	print("")
	print("==== FLIGHT TEST SUMMARY ====")
	var failed := 0
	for r in results:
		print(r[1])
		if not r[0]:
			failed += 1
	print("RESULT: %d/%d missions flown to completion" % [results.size() - failed, results.size()])
	get_tree().quit(1 if failed > 0 else 0)


# ======================================================================== crew helpers
func _reset_inputs() -> void:
	for a in ["pitch", "yaw", "roll", "tx", "ty", "tz", "throttle"]:
		InputHub.set_axis_override(a, 0.0)
	for s in ["engine_arm", "gear", "airbrake", "cargo_doors", "dock_clamp", "jump_arm", "pwr_shields", "pilot_trigger", "ops_trigger"]:
		InputHub.set_switch(s, false)
	InputHub.set_switch("pwr_sensors", false)
	InputHub.set_group("fa", 1)
	InputHub.set_group("ops", 0)
	Game.set_warp(1.0)


func _start(id: String) -> void:
	_reset_inputs()
	Game.load_mission(id)
	await get_tree().process_frame
	# The crew flips the overhead switches in order, one per half second
	for sid in Game.CHECKLIST:
		InputHub.set_switch(sid, true)
		_ticks(0.5)
	if not Game.try_start():
		push_error("could not start " + id)
	_ticks(0.5)


func _ticks(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		InputHub._process(DT)
		Game.tick(DT)


## Run the sim until done.call() is true, calling ctl.call() before every tick.
func _fly(ctl: Callable, done: Callable, timeout_s: float) -> bool:
	var t := 0.0
	var n := 0
	while t < timeout_s:
		if Game.state != Game.State.ACTIVE or done.call():
			return true
		ctl.call()
		InputHub._process(DT)
		Game.tick(DT * minf(Game.warp, 1.0) if false else DT)
		t += DT
		n += 1
		if trace and Game.mission_time - _last_trace >= float(Settings.cli.get("trace_dt", "10")):
			_last_trace = Game.mission_time
			_print_trace()
		if n % 600 == 0:
			await get_tree().process_frame
	print("  timeout after %ds" % int(timeout_s))
	return false


func _print_trace() -> void:
	var s: ShipSim = Game.sim
	if Game.mission.id == "reentry":
		var loc: Vector3 = Game.mission.call("runway_local")
		print("  runway local x=%.0f z=%.0f aoa=%.1f gs=%s" % [loc.x, loc.z, rad_to_deg(Game.sim.aoa), str(Game.sim.gear_down)])
	print("  t=%5.0f step=%d alt=%7.0f agl=%7.0f vs=%7.1f hs=%7.1f thr=%.2f fuel=%5.0f bfuel=%5.0f T=%4.0fK hull=%3.0f fa=%s nav=%s warp=%d" % [
		Game.mission_time, Game.mission.step, s.altitude, s.agl, s.vspeed, s.hspeed, s.throttle, s.fuel, s.booster_fuel, s.hull_temp, Game.hull,
		ShipSim.FA_NAMES[s.fa_mode], Game.nav_vector, int(Game.warp)])


func sw(id: String, on: bool) -> void:
	InputHub.set_switch(id, on)


## Press a button, at most once every `every` seconds of mission time.
func press(id: String, every: float = 0.6) -> void:
	var last: float = _pulse_t.get(id, -999.0)
	if Game.mission_time - last >= every or Game.mission_time < last:
		_pulse_t[id] = Game.mission_time
		InputHub.pulse(id, 2)


func throttle(v: float) -> void:
	InputHub.set_axis_override("throttle", clampf(v, 0.0, 1.0))


func assist(mode: int) -> void:
	InputHub.set_group("fa", mode)


func stick_zero() -> void:
	for a in ["pitch", "yaw", "roll"]:
		InputHub.set_axis_override(a, 0.0)


## Pilot: fly the stick (STAB assist = rate command) to point the nose along fwd with the
## roof toward up_ref.
func stick_point(fwd: Vector3, up_ref: Vector3, k: float = 1.4) -> float:
	var sim: ShipSim = Game.sim
	if fwd.length() < 1e-4:
		stick_zero()
		return 0.0
	var f := fwd.normalized()
	var u := up_ref.slide(f)
	if u.length() < 0.05:
		u = sim.basis.y.slide(f)
	var tb := Basis.looking_at(f, u.normalized())
	var err := sim.attitude_error(tb)
	var w := err * k
	var mr := sim.max_rate
	InputHub.set_axis_override("pitch", clampf(w.x / mr.x, -1.0, 1.0))
	InputHub.set_axis_override("yaw", clampf(-w.y / mr.y, -1.0, 1.0))
	InputHub.set_axis_override("roll", clampf(-w.z / mr.z, -1.0, 1.0))
	return rad_to_deg(sim.forward().angle_to(f))


## Ops: RCS translation to produce a world-frame push (each component -1..1 = full thrust).
func rcs_world(push: Vector3) -> void:
	var b := Game.sim.basis.transposed() * push
	InputHub.set_axis_override("tx", clampf(b.x, -1.0, 1.0))
	InputHub.set_axis_override("ty", clampf(b.y, -1.0, 1.0))
	InputHub.set_axis_override("tz", clampf(-b.z, -1.0, 1.0))


func rcs_zero() -> void:
	for a in ["tx", "ty", "tz"]:
		InputHub.set_axis_override(a, 0.0)


func target_until(name_: String) -> void:
	if str(Game.current_target().get("name", "")) != name_:
		press("nav_target", 0.4)


# ======================================================================== (a) launch
func _fly_launch() -> void:
	await _start("launch")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	sw("pwr_sensors", true)
	assist(ShipSim.FA.NAV)
	var ctl := func() -> void:
		var cd: float = m.get("countdown")
		if m.get("counting"):
			if cd < 5.5:
				sw("engine_arm", true)
				throttle(1.0)
				if not sim.engine_on:
					press("ignition", 1.0)
			return
		var el := m.orbit_elements()
		match m.step:
			1, 2:
				Game.nav_vector = "GUIDANCE"
				throttle(1.0)
				if m.step == 2:
					press("ops_trigger", 1.0)        # STAGE!
			3:
				Game.nav_vector = "GUIDANCE"
				throttle(0.0 if float(el["ap_alt"]) >= 198500.0 and float(el["pe_alt"]) > -295000.0 else 1.0)
			4:
				throttle(0.0)
				Game.nav_vector = "PROGRADE"
				if sim.density_now <= 0.0 and Game.warp < 10.0 and float(el["time_to_ap"]) > 60.0:
					Game.set_warp(10.0)
			5:
				Game.nav_vector = "PROGRADE"
				var aligned := sim.forward().angle_to(sim.surface_vel.normalized()) < deg_to_rad(5.0)
				throttle(1.0 if aligned else 0.0)
			6:
				throttle(0.0)
				sw("engine_arm", false)
				sw("cargo_doors", true)
				InputHub.set_group("ops", 1)
				if Game.arm_extend > 0.97:
					press("ops_trigger", 3.0)
	await _fly(ctl, func() -> bool: return false, 1500.0)


# ======================================================================== (b) docking
func _fly_docking() -> void:
	await _start("docking")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	var st: Dictionary = Game.station
	assist(ShipSim.FA.STAB)
	var ctl := func() -> void:
		sw("pwr_sensors", true)
		var sb: Basis = st["basis"]
		var n: Vector3 = (sb * Vector3(0, 0, 1)).normalized()
		stick_point(-n, sb.y, 1.2)
		if m.step == 0:
			target_until("STATION PORT")
			return
		if m.step == 3:
			rcs_zero()
			sw("dock_clamp", true)
			return
		var info: Dictionary = m.call("docking_info")
		var rng: float = info["range"]
		var lat: Vector2 = info["lat"]
		var lat_w: Vector3 = sb.x * lat.x + sb.y * lat.y
		var rv: Vector3 = info["rel_vel"]
		var lat_v_d := (-lat_w * 0.12).limit_length(0.8)
		var closing_d := 0.0
		if m.step >= 2:
			if lat.length() < maxf(0.25, rng * 0.05) or rng > 30.0:
				closing_d = clampf(rng * 0.025, 0.12, 2.5)
			if rng < 6.0 and lat.length() > 0.3:
				closing_d = 0.0
		var v_d := lat_v_d - n * closing_d
		rcs_world((v_d - rv) * 3.0)
	await _fly(ctl, func() -> bool: return false, 900.0)


# ======================================================================== (c) lunar landing
func _fly_lunar() -> void:
	await _start("lunar")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	var pad: Dictionary = Game.entities_of("lunar_pad")[0]
	var moon: CelestialBody = Game.moon
	var ctl := func() -> void:
		sw("pwr_sensors", true)
		if m.step == 0:
			press("scanner_ping", 1.0)
			return
		sw("engine_arm", true)
		if m.step == 1:
			assist(ShipSim.FA.NAV)              # mission set NAV vector = RETROGRADE
			var aligned := sim.forward().angle_to(-sim.surface_vel.normalized()) < deg_to_rad(10.0)
			throttle(1.0 if aligned else 0.0)
			if not sim.engine_on and aligned:
				press("ignition", 1.0)
			return
		assist(ShipSim.FA.STAB)
		if sim.landed or (sim.touching and sim.agl < 3.0):
			throttle(0.0)
			stick_zero()
			return
		var up := sim.up_dir
		var r := sim.pos.rel(moon.pos).length()
		var g := moon.gm / (r * r)
		var rel: Vector3 = m.rel_to_entity(pad)
		var h_off := rel - up * rel.dot(up)
		var hv := sim.surface_vel - up * sim.vspeed
		var dist := h_off.length()
		var vmax := 60.0 if dist > 1500.0 else (25.0 if dist > 300.0 else 8.0)
		var v_h_d := h_off.normalized() * minf(dist * 0.05, vmax) if dist > 0.5 else Vector3.ZERO
		var a_h := ((v_h_d - hv) * 0.35).limit_length(g * 0.6)
		var vs_d := -maxf(2.0, sim.agl / 14.0)
		if dist > 250.0:
			vs_d = clampf((450.0 - sim.agl) * 0.08, -40.0, 15.0)   # cruise at ~450 m to the beacon
		elif dist > 25.0 and sim.agl < 120.0:
			vs_d = maxf(vs_d, 0.0)            # hover until over the pad
		if sim.agl < 30.0 and dist < 40.0:
			vs_d = -1.4
		var a_v := g + (vs_d - sim.vspeed) * 0.9
		var a := up * maxf(a_v, 0.0) + a_h
		var tilt := rad_to_deg(a.angle_to(up))
		if tilt > 35.0:
			a = up * a.dot(up) + (a - up * a.dot(up)).limit_length(a.dot(up) * tan(deg_to_rad(35.0)))
		var ang := stick_point(a, CelestialBody.east_at(up), 1.6)
		var thrust_avail := sim.main_thrust
		var thr := a.length() * sim.total_mass() / thrust_avail
		if ang > 25.0:
			thr *= 0.3
		throttle(thr)
		sw("gear", sim.agl < 900.0)
		if not sim.engine_on:
			press("ignition", 1.0)
	await _fly(ctl, func() -> bool: return false, 900.0)


# ======================================================================== (d) asteroids
func _goto(rel: Vector3, tgt_vel: Vector3, stop_dist: float, vmax: float) -> float:
	var sim: ShipSim = Game.sim
	var d := rel.length()
	var dir := rel / maxf(d, 0.001)
	var a_rcs := sim.rcs_force / sim.total_mass()
	var sp := minf(vmax, sqrt(maxf(2.0 * a_rcs * 0.5 * (d - stop_dist), 0.0)))
	var v_d := tgt_vel + dir * sp
	var err := v_d - sim.vel
	if err.length() < 0.4:
		rcs_zero()   # deadband: save monoprop
	else:
		rcs_world(err / maxf(a_rcs, 0.01) * 0.8)
	return d


## Orient the ship so `dir` sits 40 deg above the nose (where the cargo arm can reach).
func _point_for_arm(dir: Vector3) -> void:
	var sim: ShipSim = Game.sim
	var d := dir.normalized()
	var roof := sim.basis.y.slide(d)
	if roof.length() < 0.1:
		roof = sim.basis.x.cross(d)
	roof = roof.normalized()
	var a := deg_to_rad(40.0)
	stick_point(d * cos(a) - roof * sin(a), d * sin(a) + roof * cos(a), 1.2)


## Ops: steer the arm (ARM mode axes) toward a target and hold the beam trigger.
func _aim_arm(target_rel: Vector3) -> float:
	var sim: ShipSim = Game.sim
	var tip: Vector3 = Game.arm_tip_rel()
	var d := sim.basis.transposed() * (target_rel - tip).normalized()
	var p_d := asin(clampf(d.y, -1.0, 1.0))
	var y_d := atan2(-d.x, -d.z)
	InputHub.set_axis_override("tx", clampf(-(y_d - Game.arm_yaw) * 3.0, -1.0, 1.0))
	InputHub.set_axis_override("ty", clampf((p_d - Game.arm_pitch) * 3.0, -1.0, 1.0))
	InputHub.set_axis_override("tz", 0.0)
	return rad_to_deg((target_rel - tip).angle_to(Game.arm_dir_world()))


func _fly_asteroids() -> void:
	await _start("asteroids")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	var fld: Dictionary = Game.field
	assist(ShipSim.FA.STAB)
	sw("pwr_shields", true)
	sw("pwr_sensors", true)
	var ctl := func() -> void:
		var fv: Vector3 = fld["vel"]
		match m.step:
			0:
				press("scanner_ping", 1.0)
			1:
				InputHub.set_group("ops", 0)
				var pod: Dictionary = m.get("pod")
				var rel: Vector3 = m.rel_to_entity(pod)
				stick_point(rel, sim.basis.y)
				_goto(rel, fv, 25.0, 12.0)
			2:
				var pod2: Dictionary = m.get("pod")
				var rel2: Vector3 = m.rel_to_entity(pod2)
				_point_for_arm(rel2)
				sw("cargo_doors", true)
				InputHub.set_group("ops", 1)
				if Game.arm_extend > 0.97:
					var off := _aim_arm(rel2)
					sw("ops_trigger", off < 8.0 or not (m.get("towed") as Array).is_empty())
				else:
					rcs_zero()
			3:
				var rocks: Array = m.get("rocks_c")
				var crystals := Game.entities_of("crystal").filter(func(e: Dictionary) -> bool: return e["mode"] == "field")
				var towed: Array = m.get("towed")
				if not crystals.is_empty() or not towed.is_empty():
					# Ops beams the nearest crystal in
					Game.laser_on = false
					sw("pilot_trigger", false)
					var c: Dictionary = towed[0] if not towed.is_empty() else crystals[0]
					var rel3: Vector3 = m.rel_to_entity(c)
					_point_for_arm(rel3)
					if rel3.length() > 60.0 and towed.is_empty():
						InputHub.set_group("ops", 0)
						_goto(rel3, fv, 35.0, 10.0)
					else:
						InputHub.set_group("ops", 1)
						var off2 := _aim_arm(rel3)
						sw("ops_trigger", off2 < 8.0 or not towed.is_empty())
				elif not rocks.is_empty():
					# Pilot flies near a crystal rock and lasers it
					sw("ops_trigger", false)
					var rk: Dictionary = rocks[0]
					var rel4: Vector3 = m.rel_to_entity(rk)
					var ang := stick_point(rel4, sim.basis.y)
					InputHub.set_group("ops", 0)
					_goto(rel4, fv, 80.0, 12.0)
					sw("pilot_trigger", ang < 2.0 and rel4.length() < 400.0)
			4:
				sw("pilot_trigger", false)
				sw("ops_trigger", false)
				InputHub.set_group("ops", 0)
				rcs_world((fv - sim.vel) * 2.0)
				sw("jump_arm", true)
				var ang2 := stick_point(m.call("jump_dir"), sim.basis.y)
				if Game.jump_charge >= 100.0 and ang2 < 8.0 and Game.jump_phase == 0.0:
					press("jump_engage", 5.0)
	await _fly(ctl, func() -> bool: return Game.jump_phase > 0.0, 1500.0)
	# The jump itself is a real-time tween (about 4 s); let it play out.
	while Game.jump_phase > 0.0 and Game.state == Game.State.ACTIVE:
		await get_tree().process_frame
		InputHub._process(DT)
		Game.tick(DT)
	await _fly(func() -> void: pass, func() -> bool: return false, 5.0)


# ======================================================================== (e) reentry + runway
func _fly_reentry() -> void:
	await _start("reentry")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	var rw: Dictionary = Game.entities_of("runway")[0]
	var ctl := func() -> void:
		# --warp4: the crew uses time warp x4 during the high glide (allowed in the air above 1.5 km)
		if Settings.cli.has("warp4") and Game.warp < 4.0 and sim.agl > 5000.0 and m.step >= 1:
			Game.set_warp(4.0)
		elif Settings.cli.has("warp4") and sim.agl <= 5000.0 and Game.warp > 1.0:
			Game.set_warp(1.0)
		sw("pwr_sensors", true)
		sw("pwr_shields", true)
		var bl: bool = m.get("blackout")
		match m.step:
			0, 1:
				assist(ShipSim.FA.NAV)
				Game.nav_vector = "GUIDANCE"
				return
			2:
				assist(ShipSim.FA.NAV)
				if not bl:
					target_until("RUNWAY")
					if str(Game.current_target().get("name", "")) == "RUNWAY":
						press("scanner_ping", 1.0)
				return
		var b: Basis = rw["basis"]
		var loc: Vector3 = m.call("runway_local")
		if m.step == 3 and (-1450.0 - loc.x) > 12500.0 and sim.agl > 4000.0:
			assist(ShipSim.FA.NAV)            # keep following the NAV GUIDANCE glide
			Game.nav_vector = "GUIDANCE"
			stick_zero()
			return
		assist(ShipSim.FA.STAB)
		var vl := b.transposed() * sim.surface_vel
		var spd := vl.length()
		if sim.touching or m.step >= 4:
			# rollout: nose level, airbrake (= wheel brakes), keep straight
			sw("airbrake", true)
			stick_point(b.x.slide(sim.up_dir), sim.up_dir, 1.0)
			return
		var tan_gs := tan(deg_to_rad(18.0))
		var aim_x := -1450.0
		var h := sim.agl
		var h_d := maxf((aim_x - loc.x) * tan_gs, 0.0) + 12.0
		var gamma_d := -deg_to_rad(18.0) + clampf((h_d - h) * 0.003, -0.15, 0.15)
		if h < 160.0:
			var vs_d := -(1.2 + h * 0.2)
			gamma_d = maxf(gamma_d, asin(clampf(vs_d / maxf(spd, 1.0), -0.6, 0.0)))
		var gamma := asin(clampf(vl.y / maxf(spd, 1.0), -1.0, 1.0))
		var psi := atan2(vl.z, vl.x)
		var vz_d := clampf(-loc.z * 0.05, -25.0, 25.0)
		var psi_d := atan2(vz_d, maxf(vl.x, 30.0))
		var pitch := gamma_d + sim.aoa + 1.2 * (gamma_d - gamma)
		var yaw := psi_d + 1.0 * (psi_d - psi)
		var fwd_l := Vector3(cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw))
		stick_point(b * fwd_l, sim.up_dir, 1.5)
		sw("gear", h < 1500.0)
		sw("flaps_down", h < 900.0)
		sw("airbrake", spd > 125.0 and h < 4000.0 and h > 40.0)
	await _fly(ctl, func() -> bool: return false, 1200.0)


# ======================================================================== (f) sandbox
func _fly_sandbox() -> void:
	await _start("sandbox")
	var m: Mission = Game.mission
	var sim: ShipSim = Game.sim
	assist(ShipSim.FA.STAB)
	var hops := 0
	while hops < 3 and Game.state == Game.State.ACTIVE:
		sw("jump_arm", true)
		await _fly(func() -> void: stick_zero(), func() -> bool: return Game.jump_charge >= 100.0, 30.0)
		InputHub.pulse("jump_engage", 2)
		_ticks(0.2)
		while Game.jump_phase > 0.0:
			await get_tree().process_frame
			InputHub._process(DT)
			Game.tick(DT)
		hops += 1
		print("  sandbox hop %d -> %s (alt %d km)" % [hops, str(m.get("DESTS")[int(m.get("dest_index"))]), int(sim.altitude / 1000.0)])
	await _fly(func() -> void: pass, func() -> bool: return false, 20.0)
	m.call("end_flight")           # Commander: END FREE FLIGHT button
	_ticks(0.5)
