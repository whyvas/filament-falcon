extends Node
## Headless EVA frame-of-reference test (`-- --eva-frame-test`, ~10 s): the spacewalker is a
## separate body from the ship.
##  1. ship burns (RCS) while the spacewalker free-floats: they keep their own inertial path
##     (world-frame position relative to the ship's centre = their own drift minus the ship's
##     burn) and so drift in the ship frame; nothing drags them along
##  2. ship turns while they free-float: world-frame position stays put, ship frame rotates
##  3. on a handrail they move rigidly with the hull under thrust and rotation
##  4. letting go of the rail inherits the hull's velocity at that point (w x r)
##  5. every view draws the avatar at the same world position as the ship model (the frame the
##     VR client uses), also after a floating-origin shift (debug free camera)
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


## Free-floating, nothing attached, no tether, out of reach of the hull.
func _float_at(sim: EvaSim, p: Vector3) -> void:
	sim.grab_kind[0] = ""
	sim.grab_kind[1] = ""
	sim.grip_prev[0] = false
	sim.grip_prev[1] = false
	sim.att_edge = -1
	sim.perch = false
	sim.riding = false
	sim.tether_on = false
	sim.rig = Transform3D(Basis.IDENTITY, p)
	sim.vel = Vector3.ZERO
	sim._was_holding = false


func _run() -> void:
	print("EVA frame test")
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

	# 1. RCS burn (forward translation) while free-floating 6 m above the roof
	_float_at(sim, Vector3(0, 6, 0))
	s.ang_vel = Vector3.ZERO
	var p_w := s.basis * sim.rig.origin    # independent ghost: inertial, relative to ship centre
	var u_w := Vector3.ZERO
	var b0 := s.basis
	InputHub.set_axis_override("tz", 1.0)
	var burn_dv := 0.0
	for i in 240:
		_tick()
		var a: Vector3 = Eva.ship_motion()[1]
		burn_dv += a.length() * DT
		u_w -= a * DT
		p_w += u_w * DT
	InputHub.set_axis_override("tz", 0.0)
	var drift_s := sim.rig.origin.distance_to(Vector3(0, 6, 0))
	var err := (s.basis * sim.rig.origin).distance_to(p_w)
	_check("burn: free-floater not dragged (stays on inertial path)", burn_dv > 0.05 and drift_s > 0.05 and err < 0.01,
		"ship dv %.2f m/s, drift in ship frame %.2f m, world error %.4f m, ship turned %.1f deg" % [burn_dv, drift_s, err, rad_to_deg(b0.get_rotation_quaternion().angle_to(s.basis.get_rotation_quaternion()))])

	# 2. ship turning (8 deg/s yaw) while free-floating: world position fixed
	for i in 30:
		_tick()
	_float_at(sim, Vector3(0, 6, -3))
	var w := s.basis * Vector3(0, deg_to_rad(8.0), 0)
	var pw0 := s.basis * sim.rig.origin
	var turned := 0.0
	for i in 300:
		s.ang_vel = w
		_tick()
		var wm: Vector3 = Eva.ship_motion()[0]
		turned += wm.length() * DT
	var rot_err := (s.basis * sim.rig.origin).distance_to(pw0)
	var ship_move := sim.rig.origin.distance_to(Vector3(0, 6, -3))
	_check("turn: free-floater keeps its world position", turned > 0.5 and rot_err < 0.05 and ship_move > 1.0,
		"ship turned %.0f deg, moved %.2f m in ship frame, world error %.3f m" % [rad_to_deg(turned), ship_move, rot_err])

	# 3. handrail: rigid with the hull under rotation + thrust
	_float_at(sim, Vector3(0, 2.6, -1.0))
	var anchor := sim.hand_s(0).origin
	sim.grab_kind[0] = "rail"
	sim.grab_anchor[0] = anchor
	sim._was_holding = true
	s.ang_vel = w
	_tick()
	var rig0 := sim.rig.origin
	InputHub.set_axis_override("tz", 1.0)
	var worst := 0.0
	for i in 180:
		s.ang_vel = w
		_tick()
		worst = maxf(worst, sim.rig.origin.distance_to(rig0))
	InputHub.set_axis_override("tz", 0.0)
	_check("handrail: follows the ship (turn + burn)", worst < 0.02 and sim.is_holding(), "max slip in ship frame %.4f m" % worst)

	# 4. release: inherits w x r, then flies straight in the inertial frame
	var r_s := sim.rig.origin
	var expect_v := w.cross(s.basis * r_s)
	sim.grab_kind[0] = ""
	sim.grip_prev[0] = false
	sim.hand_vel[0] = Vector3.ZERO
	s.ang_vel = w
	var pw_rel := s.basis * sim.rig.origin
	_tick()
	var v_w := s.basis * sim.vel
	var v_err := v_w.distance_to(expect_v)
	var t := DT
	for i in 119:
		s.ang_vel = w
		_tick()
		t += DT
	var line_err := (s.basis * sim.rig.origin).distance_to(pw_rel + expect_v * t)
	_check("release: inherits hull velocity (w x r), flies straight", expect_v.length() > 0.1 and v_err < 0.02 and line_err < 0.05,
		"|w x r| %.3f m/s, vel error %.4f, path error after %.1f s %.3f m" % [expect_v.length(), v_err, t, line_err])
	s.ang_vel = Vector3.ZERO
	for i in 10:
		_tick()

	# 5. views: avatar at the ship model's world position, also after a floating-origin shift
	var wv: WorldView = get_parent().get_node("World")
	var dm: DisplayManager = get_parent().get_node("Display")
	await _frames(2)
	var wname: String = "front" if dm.cams.has("front") else str(dm.cams.keys()[0])
	var wcam: Camera3D = dm.cams[wname]
	# float 6 m out in front of that cockpit window
	var aim := wcam.global_position - wcam.global_basis.z * 6.0
	for k in 81:     # off-axis window frustum: find a direction it actually covers
		var d := wcam.global_basis * Vector3(float(k % 9) / 4.0 - 1.0, float(k / 9) / 4.0 - 1.0, -1.0).normalized()
		if wcam.is_position_in_frustum(wcam.global_position + d * 6.0):
			aim = wcam.global_position + d * 6.0
			break
	var target_s := wv.ship.global_transform.affine_inverse() * aim
	_float_at(sim, Vector3.ZERO)
	_float_at(sim, target_s - sim.head_s().origin)
	_tick()
	await _frames(3)
	var helm: Node3D = wv.eva_view.avatar.parts["helmet"]
	var local0 := wv.ship.global_transform.affine_inverse() * helm.global_position
	var head := sim.head_s().origin
	var vr_head := EvaView.ship_xform() * head      # where the VR client puts its own head
	var px := wcam.unproject_position(helm.global_position).distance_to(wcam.unproject_position(vr_head))
	_check("views: window camera sees the avatar where the VR head is", wcam.is_position_in_frustum(helm.global_position) and local0.distance_to(head) < 0.4,
		"%s window, helmet vs VR head %.3f m (%.1f px)" % [wname, local0.distance_to(head), px])
	var slew := Game.slew
	slew.cam_pos = s.pos.copy()
	slew.cam_pos.add(Vector3(40, -12, 25))
	slew.mode = "cam"
	slew.active = true
	await _frames(3)
	var local1 := wv.ship.global_transform.affine_inverse() * helm.global_position
	var ship_off := wv.ship.global_position.length()
	var vr_pose := EvaView.ship_xform() * sim.head_s().origin    # how the VR client frames its head
	var model_pose := wv.ship.global_transform * sim.head_s().origin
	slew.active = false
	slew.mode = "ship"
	_check("origin shift: avatar stays with the ship / VR frame", ship_off > 40.0 and local1.distance_to(local0) < 0.002 and vr_pose.distance_to(model_pose) < 0.002,
		"origin moved %.1f m, avatar shift in ship frame %.4f m, VR vs model %.4f m" % [ship_off, local1.distance_to(local0), vr_pose.distance_to(model_pose)])

	Eva.abort("EVA frame test done")
	print("EVA frame test: %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
