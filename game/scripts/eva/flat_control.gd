class_name FlatControl
extends RefCounted
## Flat (no headset) EVA control: turns keyboard / gamepad / bot commands into the same input
## dictionary the VR rig produces (head + two hand transforms, grip/use buttons), animating
## the hands so the avatar still waves, knocks on the window and reaches for things.
##
## Keyboard (when the EVA view has the keyboard: click it on Commander > EVA):
##   W/S  move along the handrail (toward / away from where you look), or jetpack fwd/back
##   A/D  jetpack left/right · R/F jetpack up/down · X stop drift · Q/E look left/right
##   SPACE grab / let go of the nearest handrail (or the arm tip; hop on the Moon)
##   ENTER (hold) USE: pick up / put down / bolt / chip / go inside
##   G wave · K knock on the window · P point · L helmet lamps · C camera (helmet / drone)
##   T (hold) pull yourself in along the tether, hand over hand · V (hold) REEL IN
##   Mouse: right-drag to look around.
## Gamepad: left stick move, right stick look, A grab, X use, Y wave, B stop, LB knock, RB lamp,
##   triggers up/down, BACK camera, D-pad up: tether pull, D-pad down: REEL IN.

var yaw := 0.0
var pitch := 0.0
var third_person := false
var _wave_t := 0.0
var _knock_t := 0.0
var _knock_target := Vector3.ZERO
var _knock_n := Vector3.UP
var _use_was := false
var _grab_was := false
var _keys_prev := {}
var _mouse_look := Vector2.ZERO
var _t := 0.0
var hint := ""
var _pull_t := -1.0       # hand-over-hand cycle time (-1 idle)
var _pull_hand := 1
const PULL_REACH := 0.25  # s reaching out (open hand)
const PULL_STROKE := 0.55 # s pulling the line to the chest (gripped)
const PULL_LEN := 0.38    # m of line per pull


func add_mouse_look(rel: Vector2) -> void:
	_mouse_look += rel


func _edge(id: String, down: bool) -> bool:
	var was: bool = _keys_prev.get(id, false)
	_keys_prev[id] = down
	return down and not was


func _pad() -> int:
	for id in Input.get_connected_joypads():
		var nm := Input.get_joy_name(id).to_lower()
		if Input.is_joy_known(id) and not nm.contains("falcon"):
			return id
	return -1


## Read keyboard + gamepad into a command dictionary (see apply()).
func read_devices(keyboard: bool) -> Dictionary:
	var c := {"move": Vector3.ZERO, "rail_move": 0.0}
	var k := func(key: Key) -> bool: return keyboard and Input.is_physical_key_pressed(key)
	var mv := Vector3.ZERO
	mv.z = (1.0 if k.call(KEY_S) else 0.0) - (1.0 if k.call(KEY_W) else 0.0)
	mv.x = (1.0 if k.call(KEY_D) else 0.0) - (1.0 if k.call(KEY_A) else 0.0)
	mv.y = (1.0 if k.call(KEY_R) else 0.0) - (1.0 if k.call(KEY_F) else 0.0)
	var look := Vector2.ZERO
	look.x = (1.0 if k.call(KEY_E) else 0.0) - (1.0 if k.call(KEY_Q) else 0.0)
	var grab: bool = k.call(KEY_SPACE)
	var use: bool = k.call(KEY_ENTER) or k.call(KEY_KP_ENTER)
	var wave: bool = k.call(KEY_G)
	var knock: bool = k.call(KEY_K)
	var point: bool = k.call(KEY_P)
	var lamp: bool = k.call(KEY_L)
	var stop: bool = k.call(KEY_X)
	var cam: bool = k.call(KEY_C)
	var tpull: bool = k.call(KEY_T)
	var reel: bool = k.call(KEY_V)
	var p := _pad()
	if p >= 0:
		var lx := Input.get_joy_axis(p, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(p, JOY_AXIS_LEFT_Y)
		mv.x += lx if absf(lx) > 0.15 else 0.0
		mv.z += ly if absf(ly) > 0.15 else 0.0
		mv.y += Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(p, JOY_AXIS_TRIGGER_LEFT)
		var rx := Input.get_joy_axis(p, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(p, JOY_AXIS_RIGHT_Y)
		look += Vector2(rx if absf(rx) > 0.15 else 0.0, ry if absf(ry) > 0.15 else 0.0)
		grab = grab or Input.is_joy_button_pressed(p, JOY_BUTTON_A)
		use = use or Input.is_joy_button_pressed(p, JOY_BUTTON_X)
		wave = wave or Input.is_joy_button_pressed(p, JOY_BUTTON_Y)
		stop = stop or Input.is_joy_button_pressed(p, JOY_BUTTON_B)
		knock = knock or Input.is_joy_button_pressed(p, JOY_BUTTON_LEFT_SHOULDER)
		lamp = lamp or Input.is_joy_button_pressed(p, JOY_BUTTON_RIGHT_SHOULDER)
		cam = cam or Input.is_joy_button_pressed(p, JOY_BUTTON_BACK)
		tpull = tpull or Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_UP)
		reel = reel or Input.is_joy_button_pressed(p, JOY_BUTTON_DPAD_DOWN)
	c["move"] = mv
	c["rail_move"] = -mv.z
	c["look"] = look
	c["grab"] = _edge("grab", grab)
	c["use"] = use
	c["wave"] = _edge("wave", wave)
	c["knock"] = _edge("knock", knock)
	c["point"] = point
	c["lamp"] = _edge("lamp", lamp)
	c["stop"] = stop
	c["tether_pull"] = tpull
	c["reel"] = reel
	if _edge("cam", cam):
		third_person = not third_person
	return c


## Turn commands into an EvaSim input. cmd keys: move (Vector3, rig-local: x right, y up,
## z back), rail_move, look (Vector2 rate), look_at (Vector3 S frame, bots), grab (edge),
## use (held), wave/knock (edge), point, lamp (edge), stop, rail_target (int),
## tether_pull (held: hand-over-hand along the tether), reel (held: REEL IN).
func apply(dt: float, sim: EvaSim, cmd: Dictionary) -> Dictionary:
	_t += dt
	var look: Vector2 = cmd.get("look", Vector2.ZERO)
	yaw -= look.x * dt * 1.8 + _mouse_look.x * 0.004
	pitch = clampf(pitch - look.y * dt * 1.4 - _mouse_look.y * 0.004, -1.3, 1.3)
	_mouse_look = Vector2.ZERO
	var turn := 0.0
	if bool(cmd.get("tether_pull", false)) and sim.tether_on and not cmd.has("look_at") and look.length() < 0.1:
		cmd["look_at"] = sim.tether_anchor + sim.rig.basis.y * 1.4   # face the hatch while pulling
	if cmd.has("look_at"):
		var lp: Vector3 = sim.rig.affine_inverse() * (cmd["look_at"] as Vector3)
		var d := lp - Vector3(0, 1.6, 0)
		var want := atan2(-d.x, -d.z)
		turn = clampf(wrapf(want, -PI, PI), -dt * 2.0, dt * 2.0)
		pitch = lerpf(pitch, clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.0, 1.0), clampf(dt * 3.0, 0.0, 1.0))
	else:
		turn = yaw
		yaw = 0.0
	var hb := Basis(Vector3.UP, 0.0) * Basis(Vector3.RIGHT, pitch)
	var head := Transform3D(hb, Vector3(0, 1.6, 0))
	var look_s := (sim.rig.basis * hb) * Vector3(0, 0, -1)
	# hands: rest pose, plus animations
	var lh := Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(-0.27, 1.02, -0.32))
	var rh := Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0.27, 1.02, -0.32))
	var holding := sim.att_edge >= 0 or sim.riding or sim.perch
	if holding:
		# one hand on the rail / arm, the other ready
		var anchor: Vector3 = sim.rail_point() if sim.att_edge >= 0 else (sim.arm_tip if sim.riding else EvaSim.canopy_point(sim.head_s().origin)[0])
		var al := sim.rig.affine_inverse() * anchor
		lh.origin = Vector3(-0.15, 1.0, -0.2).lerp(al, 0.85)
		lh.origin = Vector3(0, 1.35, 0) + (lh.origin - Vector3(0, 1.35, 0)).limit_length(0.62)
	if bool(cmd.get("wave", false)):
		_wave_t = 2.2
	if bool(cmd.get("knock", false)):
		var cp := EvaSim.canopy_point(sim.head_s().origin)
		var p: Vector3 = cp[0]
		if p.distance_to(sim.head_s().origin) < 1.25:
			_knock_t = 1.4
			_knock_target = p
			_knock_n = cp[1]
			hint = ""
		else:
			hint = "Get closer to the window to knock"
	if _wave_t > 0.0:
		_wave_t -= dt
		var ph := _t * 9.0
		rh.origin = Vector3(0.36 + 0.16 * sin(ph), 1.86, -0.18)
		rh.basis = Basis(Vector3.FORWARD, -0.35 * sin(ph))
	elif _knock_t > 0.0:
		_knock_t -= dt
		var k := absf(sin(_knock_t * PI * 2.5))
		var tp := _knock_target + _knock_n * (0.03 + 0.14 * k)
		rh.origin = sim.rig.affine_inverse() * tp
		rh.basis = Basis.looking_at(-(sim.rig.basis.inverse() * _knock_n), Vector3.UP)
	elif bool(cmd.get("use", false)) or sim.holding_item():
		var s := sim.cur_step()
		var tgt: Vector3 = s.get("at", Vector3.ZERO)
		var tl := sim.rig.affine_inverse() * tgt
		var sh := Vector3(0.2, 1.4, 0)
		var reachv := (tl - sh)
		if s.has("at") and reachv.length() < 1.6:
			rh.origin = sh + reachv.limit_length(0.62)
		else:
			rh.origin = Vector3(0.25, 1.15, -0.55)
	# hand-over-hand along the tether: reach toward the anchor, grip, pull to the chest, let go
	var tgrip := [false, false]
	var can_pull := sim.tether_on and not holding and sim.tether_used > EvaSim.REEL_MIN + 0.3
	if _pull_t < 0.0 and bool(cmd.get("tether_pull", false)) and can_pull:
		_pull_t = 0.0
		_pull_hand = 1 - _pull_hand
	if _pull_t >= 0.0:
		if not can_pull:
			_pull_t = -1.0
		else:
			var sh := Vector3(0.2 if _pull_hand == 1 else -0.2, 1.3, -0.1)
			var dl := (sim.rig.affine_inverse() * sim.tether_anchor - sh).normalized()
			var far := sh + dl * (0.12 + PULL_LEN)
			var near := sh + dl * 0.12
			var hx := Transform3D(Basis.looking_at(dl, Vector3.UP) if absf(dl.y) < 0.98 else Basis.IDENTITY, far)
			if _pull_t < PULL_REACH:
				hx.origin = near.lerp(far, _pull_t / PULL_REACH)
			else:
				hx.origin = far.lerp(near, clampf((_pull_t - PULL_REACH) / PULL_STROKE, 0.0, 1.0))
				tgrip[_pull_hand] = _pull_t < PULL_REACH + PULL_STROKE
			if _pull_hand == 0:
				lh = hx
			else:
				rh = hx
			_pull_t += dt
			if _pull_t >= PULL_REACH + PULL_STROKE + 0.04:
				_pull_t = -1.0
	var grab_edge := bool(cmd.get("grab", false))
	var use := bool(cmd.get("use", false))
	var use_edge := use and not _use_was
	_use_was = use
	var inp := {"flat": true, "head": head, "hands": [lh, rh], "turn": turn, "look": look_s,
		"move": cmd.get("move", Vector3.ZERO), "rail_move": cmd.get("rail_move", 0.0),
		"stop": cmd.get("stop", false), "lamp_toggle": cmd.get("lamp", false),
		"point": [false, bool(cmd.get("point", false))], "use": [false, use],
		"grip": [holding, not sim.grab_kind[1] in ["", "tether"]], "rail_target": cmd.get("rail_target", -1),
		"tether_grip": tgrip, "reel": bool(cmd.get("reel", false))}
	var st := sim.cur_step()
	if st.has("pose") and (st["at"] as Vector3).distance_to(sim.head_s().origin) < 2.6:
		if bool(cmd.get("glide", false)) or use:
			inp["glide_pose"] = st["pose"]
			use_edge = false
		else:
			hint = "Press USE to pull yourself over to the window"
	if sim.surface and grab_edge and sim.att_edge < 0 and sim.on_ground and sim.nearest_rail(sim.waist_s())[1] > 1.6:
		inp["hop"] = true
	elif grab_edge:
		inp["rail_toggle"] = true
	if use_edge:
		if sim.holding_item():
			sim.flat_place()
		else:
			# pick up an item / grab the arm tip within reach (the right hand)
			var near_item := false
			for it: Dictionary in sim.items:
				if not bool(it["placed"]) and not bool(it["gone"]) and int(it["held"]) < 0 and (it["pos"] as Vector3).distance_to(sim.head_s().origin) < EvaSim.FLAT_REACH + 0.1:
					near_item = true
			var busy := str(sim.cur_step().get("do", "")) in ["inside", "use", "place", "pick", "collect"]
			var near_arm := sim.arm_ok and not busy and sim.arm_tip.distance_to(sim.head_s().origin) < EvaSim.FLAT_REACH + 0.4 and not sim.riding
			if near_item or near_arm:
				(inp["grip"] as Array)[1] = true
				sim.grip_prev[1] = false
	return inp
