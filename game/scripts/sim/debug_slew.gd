class_name DebugSlew
extends RefCounted
## Debug slew while the mission is PAUSED (Commander > MISSION CONTROL, or Ctrl+F).
##   "ship": move + turn the Falcon itself; RESUME continues from there with the velocities
##            ZEROED (matched to the nearest body: hover / park) or KEPT (selectable).
##   "cam":  free camera only; the ship stays where it is and the camera snaps back on resume.
## Inputs, all additive: keyboard (owned by the slew while it is on), the Commander screen
## buttons, and the kids' sticks (Pilot stick = rotate, Ops stick = translate).
## Keys: W/S fwd/back, A/D left/right, Q/E down/up · arrows pitch/yaw, Z/X roll ·
## +/- slew speed · [ ] turn speed · Tab ship/cam · V keep/zero velocity · Esc off · Pause resume.

const SPEEDS := [0.1, 1.0, 10.0, 100.0, 1000.0, 10000.0]   # m/s
const ROT_SPEEDS := [1.0, 5.0, 20.0, 90.0]                 # deg/s

var active := false
var mode := "ship"
var zero_vel := true
var speed_i := 2
var rot_i := 2
var cam_pos: BigVec = null
var cam_basis := Basis.IDENTITY
var btn_trans := Vector3.ZERO    # held Commander buttons: x right, y up, z forward
var btn_rot := Vector3.ZERO      # x pitch up, y yaw right, z roll right
var moved := 0.0                 # metres the SHIP was slewed since start (HUD / tests)
var _kprev := {}
var _hold_grab := false          # keep the keyboard until our keys are up (no stray presses after)
const KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Z, KEY_X,
	KEY_EQUAL, KEY_MINUS, KEY_KP_ADD, KEY_KP_SUBTRACT, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_TAB, KEY_V, KEY_ESCAPE,
	KEY_PAUSE, KEY_F9, KEY_F, KEY_CTRL]


func speed() -> float:
	return SPEEDS[speed_i]


func rot_speed() -> float:
	return ROT_SPEEDS[rot_i]


func step_speed(d: int) -> void:
	speed_i = clampi(speed_i + d, 0, SPEEDS.size() - 1)


func step_rot(d: int) -> void:
	rot_i = clampi(rot_i + d, 0, ROT_SPEEDS.size() - 1)


func start(g: Node, m: String = "") -> void:
	if g.state != g.State.PAUSED:
		return
	if m != "":
		mode = m
	if not active:
		moved = 0.0
	active = true
	_hold_grab = false
	_kprev.clear()
	for k in KEYS:
		_kprev[k] = Input.is_key_pressed(k)
	cam_pos = g.sim.pos.copy()
	cam_basis = g.sim.basis
	InputHub.keyboard_grab = self
	g.log_commander("Debug slew ON (%s)" % mode)


func set_mode(g: Node, m: String) -> void:
	mode = m
	cam_pos = g.sim.pos.copy()
	cam_basis = g.sim.basis


## Leaving the slew (resume, Esc, button). The ship keeps its new place in either case.
func stop(g: Node, apply_vel: bool = true) -> void:
	if not active:
		return
	active = false
	btn_trans = Vector3.ZERO
	btn_rot = Vector3.ZERO
	_hold_grab = InputHub.keyboard_grab == self
	if apply_vel and mode == "ship" and moved > 0.0 and zero_vel:
		var sim: ShipSim = g.sim
		sim.pick_dominant()
		sim.vel = sim.dominant.vel if sim.dominant else Vector3.ZERO
		sim.ang_vel = Vector3.ZERO
	g.log_commander("Debug slew OFF (%s, %.0f m, velocity %s)" % [mode, moved, "zeroed" if zero_vel else "kept"])


## Floating-origin anchor for the renderer: the free camera, else the ship.
func view_pos(g: Node) -> BigVec:
	return cam_pos if active and mode == "cam" and cam_pos != null else g.sim.pos


func status_text() -> String:
	return "SLEW %s · %s m/s · %s°/s · resume: velocity %s · moved %.0f m" % [
		"SHIP" if mode == "ship" else "FREE CAM", _num(speed()), _num(rot_speed()), "ZERO" if zero_vel else "KEEP", moved]


static func _num(v: float) -> String:
	return ("%.1f" % v) if v < 1.0 else str(int(v))


func _edge(k: Key) -> bool:
	var d := Input.is_key_pressed(k)
	var was: bool = _kprev.get(k, false)
	_kprev[k] = d
	return d and not was


func _k(k: Key) -> float:
	return 1.0 if Input.is_key_pressed(k) else 0.0


## Every game tick: Ctrl+F toggles the slew while paused, then the slew itself.
func poll(g: Node, dt: float) -> void:
	var cf := Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_F)
	var was: bool = _kprev.get("ctrl_f", false)
	_kprev["ctrl_f"] = cf
	if cf and not was:
		if active:
			stop(g)
		elif g.state == g.State.PAUSED:
			start(g)
	tick(g, dt)


func tick(g: Node, dt: float) -> void:
	if _hold_grab and not active:
		if KEYS.all(func(k: Key) -> bool: return not Input.is_key_pressed(k)):
			_hold_grab = false
			if InputHub.keyboard_grab == self:
				InputHub.keyboard_grab = null
	if not active:
		return
	if g.state != g.State.PAUSED:
		stop(g, false)       # mission reloaded / ended: nothing to carry over
		return
	if _edge(KEY_EQUAL) or _edge(KEY_KP_ADD):
		step_speed(1)
	if _edge(KEY_MINUS) or _edge(KEY_KP_SUBTRACT):
		step_speed(-1)
	if _edge(KEY_BRACKETRIGHT):
		step_rot(1)
	if _edge(KEY_BRACKETLEFT):
		step_rot(-1)
	if _edge(KEY_TAB):
		set_mode(g, "cam" if mode == "ship" else "ship")
	if _edge(KEY_V):
		zero_vel = not zero_vel
	if _edge(KEY_ESCAPE):
		stop(g)
		return
	if _edge(KEY_PAUSE) or _edge(KEY_F9):
		g.start_pause()      # resume (stop() runs from there)
		return
	var tr := Vector3(_k(KEY_D) - _k(KEY_A), _k(KEY_E) - _k(KEY_Q), _k(KEY_W) - _k(KEY_S))
	var rt := Vector3(_k(KEY_UP) - _k(KEY_DOWN), _k(KEY_RIGHT) - _k(KEY_LEFT), _k(KEY_X) - _k(KEY_Z))
	tr += btn_trans + Vector3(InputHub.axis("tx"), InputHub.axis("ty"), InputHub.axis("tz"))
	rt += btn_rot + Vector3(InputHub.axis("pitch"), InputHub.axis("yaw"), InputHub.axis("roll"))
	tr = tr.limit_length(1.0)
	rt = rt.clamp(-Vector3.ONE, Vector3.ONE)
	apply(g, tr, rt, dt)


## One slew step: tr (x right, y up, z forward) and rt (pitch up, yaw right, roll right), -1..1.
func apply(g: Node, tr: Vector3, rt: Vector3, dt: float) -> void:
	var sim: ShipSim = g.sim
	var b: Basis = sim.basis if mode == "ship" else cam_basis
	var dpos: Vector3 = b * Vector3(tr.x, tr.y, -tr.z) * speed() * dt
	var w := Vector3(rt.x, -rt.y, -rt.z) * deg_to_rad(rot_speed()) * dt      # same sense as the stick
	if w.length_squared() > 0.0:
		b = (b * Basis.from_euler(w)).orthonormalized()
	if mode == "ship":
		moved += dpos.length()
		sim.pos.add(dpos)
		sim.basis = b
		if dpos.length_squared() > 0.0:
			sim.landed = false
			sim.touching = false
	else:
		cam_pos.add(dpos)
		cam_basis = b
