extends Node
## Headless tether + takeoff-during-EVA test (`-- --eva-tether-test`, ~10 s).
##  1. REEL IN (crew assist) winds a spacewalker 12 m out back to the hatch and stops there
##  2. hand-over-hand (flat T): pulls move the body toward the hatch and it keeps the momentum
##  3. no engine gating: ignition with a spacewalker outside asks the Commander GO / NO-GO;
##     after GO the engine lights
##  4. thrusting with the spacewalker tethered at full length tows them along (distance bounded,
##     tension below the snap limit); a hard yank on slack line warns and snaps it
##  5. Moon liftoff (EvaSim alone): a walker standing on the ground is left behind, one on the
##     ladder rail is carried, a tethered one is lifted off the ground within the limits
## Exit code 0 = pass.

const DT := 1.0 / 60.0
var _ok := true


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, good: bool, info: String) -> void:
	print("  %-58s %s  %s" % [name, "ok" if good else "FAIL", info])
	_ok = _ok and good


func _tick(dt: float = DT) -> void:
	InputHub._process(dt)
	Game.tick(dt)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _float_at(sim: EvaSim, p: Vector3) -> void:
	for i in 2:
		sim.grab_kind[i] = ""
		sim.grip_prev[i] = false
	sim.att_edge = -1
	sim.perch = false
	sim.riding = false
	sim.tether_on = true
	sim.snapped = false
	sim.tension_peak = 0.0
	sim.reel_assist = false
	sim.rig = Transform3D(Basis.IDENTITY, p)
	sim.vel = Vector3.ZERO
	sim._was_holding = false


func _run() -> void:
	print("EVA tether test")
	Game.external_clock = true
	Game.load_mission("docking")
	await _frames(3)
	Game.auto_checklist()
	for i in 30:
		_tick()
	Game.try_start()
	for i in 60:
		_tick()
	if not Eva.start("window", false, "flat"):
		_check("EVA starts", false, str(Eva.available()))
		get_tree().quit(1)
		return
	var sim: EvaSim = Eva.sim
	var s: ShipSim = Game.sim
	Game.ops_mode = 0
	var hn := EvaScenarios.hatch_normal()
	var anc := sim.tether_anchor
	sim.tether_len = 20.0

	# 1. REEL IN assist from 12 m
	_float_at(sim, anc + hn * 12.0 - Vector3(0, 1.0, 0))
	s.ang_vel = Vector3.ZERO
	Eva.set_reel(true)
	var t := 0.0
	var peak := 0.0
	while t < 120.0 and sim.reel_assist:
		s.ang_vel = Vector3.ZERO
		_tick()
		t += DT
		peak = maxf(peak, sim.tension)
	var rv := sim._vel_rel_hull(sim.waist_s()).length()
	_check("reel in: back at the hatch, stopped, assist off", sim.tether_used < EvaSim.REEL_MIN + 0.5 and rv < 0.1 and not sim.reel_assist and Eva.active,
		"%.0f s, at %.2f m, %.2f m/s, peak %d N" % [t, sim.tether_used, rv, int(peak)])

	# 2. hand-over-hand (flat T key) from 10 m
	_float_at(sim, anc + hn * 10.0 - Vector3(0, 1.0, 0))
	var d0 := sim.waist_s().distance_to(anc)
	Eva.cmd_override = {"tether_pull": true}
	for i in 240:
		s.ang_vel = Vector3.ZERO
		_tick()
	Eva.cmd_override = {}
	for i in 30:
		_tick()
	var d1 := sim.tether_used
	var vin := -sim._vel_rel_hull(sim.waist_s()).dot((sim.waist_s() - anc).normalized())
	for i in 120:
		_tick()
	var d2 := sim.tether_used
	_check("hand over hand: pulls toward the hatch, keeps momentum", d1 < d0 - 1.0 and vin > 0.1 and d2 < d1 - 0.1,
		"%.2f -> %.2f m after 4 s of pulls, coasting in at %.2f m/s -> %.2f m" % [d0, d1, vin, d2])

	# 2b. VR: grab the line with a hand, pull it to the chest (EvaSim alone)
	var vr := _vr_pull()
	_check("VR hand over hand: grip the line, pull, glide in", bool(vr[0]) and float(vr[1]) > 0.3 and float(vr[2]) > 0.4 and float(vr[3]) > float(vr[1]) + 0.2,
		"gripped %s, body moved %.2f m in the pull, %.2f m/s, %.2f m after 1 s coast" % [vr[0], float(vr[1]), float(vr[2]), float(vr[3])])

	# 3. ignition with the spacewalker outside: GO / NO-GO, no hard block
	_float_at(sim, anc + hn * 2.0)
	InputHub.set_switch("engine_arm", true)
	InputHub.set_axis_override("throttle", 0.0)
	_tick()
	InputHub.pulse("ignition", 2)
	for i in 3:
		_tick()
	var asked := Eva.go_pending and not s.engine_on
	Eva.burn_decision(true)
	InputHub.pulse("ignition", 2)
	for i in 3:
		_tick()
	_check("ignition during EVA: Commander GO, then the engine lights", asked and s.engine_on and Eva.active,
		"asked %s, engine %s" % [asked, s.engine_on])
	s.engine_on = false
	InputHub.set_switch("engine_arm", false)
	for i in 3:
		_tick()

	# 4a. gentle RCS burn away from the walker at full tether length: towed within limits
	s.ang_vel = Vector3.ZERO
	_float_at(sim, anc + Vector3(0, 0, 19.6))   # 19.6 m aft of the hatch clip
	InputHub.set_axis_override("tz", 1.0)
	var worst := 0.0
	var tpk := 0.0
	var dv := 0.0
	for i in 900:
		_tick()
		dv += (Eva.ship_motion()[1] as Vector3).length() * DT
		worst = maxf(worst, sim.tether_used)
		tpk = maxf(tpk, sim.tension)
	InputHub.set_axis_override("tz", 0.0)
	var rel := sim._vel_rel_hull(sim.waist_s()).length()
	_check("RCS burn, tethered: towed along within the limits", dv > 1.0 and sim.tether_on and worst < 20.0 + EvaSim.TETHER_MAX_STRETCH + 0.01 and tpk < EvaSim.TENSION_SNAP and rel < 0.6,
		"ship dv %.1f m/s, max %.2f m, peak %d N, rel speed %.2f m/s" % [dv, worst, int(tpk), rel])

	# 4b. hard yank (main engine, full throttle, 4 m of slack): warning, then the line snaps
	for i in 60:
		_tick()
	s.ang_vel = Vector3.ZERO
	_float_at(sim, anc + Vector3(0, 0, 16.0))
	var pen0 := Eva.penalties
	InputHub.set_switch("engine_arm", true)
	InputHub.set_axis_override("throttle", 1.0)
	_tick()
	InputHub.pulse("ignition", 2)
	var tpk2 := 0.0
	for i in 240:
		_tick()
		tpk2 = maxf(tpk2, sim.tension)
		if sim.snapped:
			break
	_check("hard burn on a slack tether: warns, snaps above the limit", s.engine_on and sim.snapped and not sim.tether_on and Eva.penalties > pen0,
		"engine %s, peak %d N, snapped %s, warnings %d" % [s.engine_on, int(tpk2), sim.snapped, Eva.penalties - pen0])
	InputHub.set_axis_override("throttle", 0.0)
	s.engine_on = false
	InputHub.set_switch("engine_arm", false)
	Eva.abort("test")
	_tick()

	# 5. Moon liftoff, EvaSim alone (ship frame, ground falls away)
	var res := []
	for mode: String in ["ground", "ladder", "tether"]:
		res.append(_moon_case(mode))
	_check("moon liftoff: walker on the ground is left behind", float(res[0][0]) < 0.15 and float(res[0][1]) > 60.0,
		"above ground %.2f m, %.0f m from the ship" % [float(res[0][0]), float(res[0][1])])
	_check("moon liftoff: walker on the ladder is carried", float(res[1][2]) < 0.15,
		"moved %.2f m in the ship frame" % float(res[1][2]))
	_check("moon liftoff: tethered walker lifted along, no snap", float(res[2][0]) > 10.0 and float(res[2][1]) < 21.1 and not bool(res[2][3]),
		"above ground %.1f m, %.1f m from the clip, peak %d N" % [float(res[2][0]), float(res[2][1]), int(res[2][4])])

	print("EVA TETHER TEST: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)


## Ship lifts off at 0.5 m/s² (relative to the Moon) for 20 s. Returns [height above ground,
## distance from the ship / tether clip, ship-frame drift, snapped, peak tension].
func _moon_case(mode: String) -> Array:
	var es := EvaSim.new()
	var gh := -3.0
	var scen := {"surface": true, "up": Vector3.UP, "ground_h": gh, "gravity": 1.62, "tether": mode == "tether",
		"tether_anchor": Vector3(1.2, 0.0, 0.0), "tether_len": 20.0, "hatch": Vector3(1.2, 0.0, 0.0),
		"rails": [PackedVector3Array([Vector3(1.6, 0.5, 0.0), Vector3(1.6, -2.7, 0.0)])],
		"start": Transform3D(Basis.IDENTITY, Vector3(4.0 if mode != "ladder" else 1.9, gh, 0.0))}
	es.setup(scen)
	var head := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var lh := Transform3D(Basis.IDENTITY, Vector3(-0.27, 1.02, -0.32))
	var rh := Transform3D(Basis.IDENTITY, Vector3(0.27, 1.02, -0.32))
	if mode == "ladder":
		lh.origin = Vector3(1.6, -1.2, 0.0) - es.rig.origin   # hand on the ladder
	var vz := 0.0
	var z := 0.0
	for i in 120:   # settle on the ground
		es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [mode == "ladder", false]})
	var start := es.rig.origin
	for i in int(20.0 / DT):
		vz += 0.5 * DT
		z += vz * DT
		es.ship_acc = Vector3(0, 0.5, 0)
		es.ground_h = gh - z
		es.ground_vel = Vector3(0, -vz, 0)
		es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [mode == "ladder", false]})
	var above := es.rig.origin.y - (es.ground_h + es.ground_vel.y * DT)   # where the ground is now
	var dist := es.waist_s().distance_to(es.tether_anchor) if mode == "tether" else es.rig.origin.length()
	return [above, dist, es.rig.origin.distance_to(start), es.snapped, es.tension_peak]


## VR-style input: hand on the line 0.6 m in front of the waist, grip, pull it back to the
## chest in 0.5 s, let go. Returns [gripped, moved in the pull, inward speed, moved after 1 s].
func _vr_pull() -> Array:
	var es := EvaSim.new()
	es.setup({"tether": true, "tether_anchor": Vector3.ZERO, "tether_len": 20.0,
		"start": Transform3D(Basis.IDENTITY, Vector3(0, -0.98, 8.0))})
	es._was_holding = false
	var head := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var rh := Transform3D(Basis.IDENTITY, Vector3(0.27, 1.02, -0.32))
	var w := es.waist_s()
	var dir := (es.tether_anchor - w).normalized()
	var far := (w + dir * 0.6) - es.rig.origin
	var near := (w + dir * 0.1) - es.rig.origin
	var lh := Transform3D(Basis.IDENTITY, far)
	es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [false, false]})
	var d0 := es.waist_s().distance_to(Vector3.ZERO)
	es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [true, false]})
	var gripped := es.grab_kind[0] == "tether"
	for i in 30:
		lh.origin = far.lerp(near, (i + 1) / 30.0)
		es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [true, false]})
	var d1 := es.waist_s().distance_to(Vector3.ZERO)
	var v := -es.vel.dot(es.waist_s().normalized())
	for i in 60:
		es.step_sim(DT, {"head": head, "hands": [lh, rh], "grip": [false, false]})
	var d2 := es.waist_s().distance_to(Vector3.ZERO)
	return [gripped, d0 - d1, v, d0 - d2]
