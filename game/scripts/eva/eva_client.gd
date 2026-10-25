class_name EvaClient
extends Node
## The VR spacewalk client: a 2nd process of this same game started with
##   godot --path game --xr-mode on -- --eva-client [--eva-port=47820] [--quality=medium]
## (Commander > EVA > LAUNCH VR CLIENT, or run.sh --eva-vr). It renders the world from the
## spacewalker's helmet in the Quest 3 (OpenXR through WiVRn), runs the spacewalk simulation
## locally (so hands and grabs feel instant) and streams the result to the cockpit over UDP on
## localhost at the headset frame rate (72-90 Hz). The cockpit sends world snapshots back
## (ship position / attitude, arm, cargo doors, nearby objects) and START / ABORT commands.
## No headset / no OpenXR runtime: it opens a normal window (keyboard / mouse / gamepad) or,
## with --headless, runs the autopilot (--eva-bot) for tests.

const SEATED_OFFSET := 0.45

var world: WorldView
var sim: EvaSim = null
var has_xr := false
var xr_error := ""
var xr_if: XRInterface
var origin: XROrigin3D
var xr_cam: XRCamera3D
var ctrl: Array[XRController3D] = []
var cuff: Label3D
var vignette_mat: ShaderMaterial
var flat_cam: Camera3D
var hud: Label
var flat := FlatControl.new()
var bot: EvaBot = null
var flat_view := "HELMET CAM"

var _udp := PacketPeerUDP.new()
var _port := 47820
var _cack := 0
var _srv_ack := 0
var _last_rx := -100.0
var _info_t := 0.0
var _mid := ""
var _cfg := {"snap": 30.0, "vignette": 0.7, "seated": false}
var _snap_armed := true
var _btn_prev := {}
var _menu_t := 0.0
var _vig := 0.0
var _sent := 0
var _rx := 0
var _t := 0.0
const XR_NEAR := 0.03   # face right at the hull without clipping into it
const XR_FAR := 3.0e4   # keep far/near ~1e6 (XR combined-frustum culling breaks beyond)
var _ptt := false


func _ready() -> void:
	add_to_group("eva_client")
	Game.external_clock = true
	_port = int(Settings.cli.get("eva-port", Settings.get_v("eva", "port")))
	if Settings.cli.has("eva-bot"):
		bot = EvaBot.new()
	world = WorldView.new()
	world.name = "World"
	var xr_probe := XRServer.find_interface("OpenXR")
	if xr_probe and xr_probe.is_initialized():
		# XR: Godot culls with ONE combined frustum built from both eye projections; with
		# near 0.05 / far 1e6 (ratio 2e7) that frustum degenerates and culls every mesh,
		# leaving only the sky. Keep the ratio ~1e6 and pull scaled-space bodies inside it.
		world.FAR_SAFE = XR_FAR * 0.9
		world.ATMO_PROXY_R = XR_FAR * 0.8
	add_child(world)
	world.eva_view.client_sim = null
	_setup_xr()
	if not has_xr:
		_setup_flat()
	_setup_audio()
	_udp.connect_to_host("127.0.0.1", _port)
	print("EVA client: xr=%s %s · port %d%s" % [has_xr, xr_error if not has_xr else str(_system_info()), _port, " · bot" if bot else ""])
	if Settings.cli.has("eva-selftest"):
		_selftest.call_deferred()


# ======================================================================== XR / flat setup
func _setup_xr() -> void:
	xr_if = XRServer.find_interface("OpenXR")
	if xr_if == null:
		xr_error = "OpenXR module missing"
		return
	if not xr_if.is_initialized():
		xr_error = "no OpenXR runtime / headset (start WiVRn and connect the Quest)"
		_xlog("XR init FAILED: " + xr_error)
		return
	has_xr = true
	_xlog("XR init ok: %s · action map %s" % [str(_system_info()), ProjectSettings.get_setting("xr/openxr/default_action_map", "?")])
	var oxr := xr_if as OpenXRInterface
	if oxr:
		oxr.session_begun.connect(func() -> void: _xlog("session begun"))
		oxr.pose_recentered.connect(func() -> void: _xlog("pose recentered (runtime)"))
		oxr.session_focussed.connect(func() -> void: _xlog("session FOCUSED (input + poses live)"))
		oxr.session_visible.connect(func() -> void: _xlog("session visible only (system menu / proximity sensor: no input)"))
		_xlog("near=%.2f far=%.0f reference_space=%s" % [XR_NEAR, XR_FAR, ProjectSettings.get_setting("xr/openxr/reference_space", "?")])
		_xlog("hand tracking (XR_EXT_hand_tracking): %s · project setting %s" % ["AVAILABLE" if oxr.is_hand_tracking_supported() else "not offered by the runtime (WiVRn: enable hand tracking on the Quest)", ProjectSettings.get_setting("xr/openxr/extensions/hand_tracking", "?")])
		oxr.session_begun.connect(_match_refresh.bind(oxr))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # the runtime paces frames
	Engine.max_fps = 0
	get_viewport().use_xr = true
	origin = XROrigin3D.new()
	world.eva_view.add_child(origin)
	xr_cam = XRCamera3D.new()
	xr_cam.near = XR_NEAR
	xr_cam.far = XR_FAR
	xr_cam.cull_mask = 0xFFFFF & ~(Eva.EVA_HEAD_LAYER | Eva.EVA_BODY_LAYER)   # you see your arms + gloves, not your helmet
	origin.add_child(xr_cam)
	xr_cam.current = true
	for side: String in ["left_hand", "right_hand"]:
		var c := XRController3D.new()
		c.tracker = side
		c.pose = &"grip_pose"   # Godot's default action map names it grip_pose ("grip" never tracked)
		origin.add_child(c)
		ctrl.append(c)
		# simple glove so you always see your hands, even before the avatar exists
		var glove := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.05, 0.13)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.92, 0.92, 0.88)
		gm.roughness = 0.8
		bm.material = gm
		glove.mesh = bm
		glove.name = "Glove"
		c.add_child(glove)
		c.button_pressed.connect(func(b: String) -> void: _xlog("%s pressed %s" % [side, b]))
	# wrist cuff checklist (real EVA suits have one): a little screen on the left forearm
	cuff = Label3D.new()
	cuff.pixel_size = 0.00035
	cuff.font_size = 40
	cuff.outline_size = 8
	cuff.modulate = Color(1.0, 0.9, 0.55)
	cuff.position = Vector3(0.0, 0.045, 0.11)
	cuff.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cuff.no_depth_test = true
	cuff.width = 520
	cuff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl[0].add_child(cuff)
	# comfort vignette: head-locked quad, darkens the edges while thrusting / the ship turns
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform float strength = 0.0;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(smoothstep(0.35, 0.85, r) * strength, 0.0, 1.0);
}"""
	vignette_mat = ShaderMaterial.new()
	vignette_mat.shader = sh
	vignette_mat.render_priority = 127
	var vq := MeshInstance3D.new()
	vq.mesh = q
	vq.material_override = vignette_mat
	vq.position = Vector3(0, 0, -0.08)
	vq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	xr_cam.add_child(vq)
	# The runtime recenters on its own (Quest: hold Meta button). Do NOT call center_on_hmd
	# from pose_recentered: that fed back into repeated recenters.


## Run the headset at 90 Hz when offered (72 judders, 120 is costly) and tick physics at the
## same rate with interpolation on, so nothing is ever stepped at 60 Hz under a 90 Hz view.
## (The EVA sim itself steps in _process, once per rendered frame.)
func _match_refresh(oxr: OpenXRInterface) -> void:
	var rates: Array = oxr.get_available_display_refresh_rates()
	var pick: float = 90.0 if rates.has(90.0) else (float(rates.max()) if not rates.is_empty() else oxr.display_refresh_rate)
	if pick > 0.0 and rates.has(pick):
		oxr.display_refresh_rate = pick
	var hz := int(roundf(pick)) if pick > 0.0 else 90
	Engine.physics_ticks_per_second = hz
	get_tree().physics_interpolation = true
	_xlog("display refresh %s Hz (offered %s) · physics tick %d Hz, interpolated" % [pick, str(rates), hz])


func _setup_flat() -> void:
	flat_cam = Camera3D.new()
	flat_cam.near = 0.05
	flat_cam.far = 1.0e6
	flat_cam.fov = 75.0
	add_child(flat_cam)
	flat_cam.current = true
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	var cl := CanvasLayer.new()
	add_child(cl)
	cl.add_child(hud)
	if not Settings.is_headless():
		get_window().title = "Filament Falcon · SPACEWALK (no headset: keyboard / mouse / gamepad)"
		Engine.max_fps = 90
	else:
		Engine.max_fps = 90


## Play this process's sounds in the headset (WiVRn's virtual "WiVRn" sink) when it exists,
## never on the cockpit speakers (the cockpit already plays the game audio).
func _setup_audio() -> void:
	var found := ""
	for d in AudioServer.get_output_device_list():
		if str(d).to_lower().contains("wivrn"):
			found = d
	if found != "":
		AudioServer.output_device = found
	else:
		AudioServer.set_bus_mute(0, true)


func _system_info() -> Dictionary:
	if xr_if == null or not has_xr:
		return {}
	var si: Dictionary = xr_if.get_system_info()
	return {"runtime": str(si.get("XRRuntimeName", "OpenXR")) + " " + str(si.get("XRRuntimeVersion", "")), "system": str(si.get("XRSystemName", si.get("OpenXRSystemName", "headset")))}


## Orderly exit (cockpit "quit" command, window close via Game.quit_game): stop the sim and the
## world's worker threads, stop submitting XR frames, uninitialize OpenXR (ends + destroys the
## session and the hand / spatial-entity extensions while everything is still alive), then quit
## a frame later. Quitting with the session live let engine teardown race the OpenXR runtime
## (XR_ERROR_SESSION_NOT_STOPPING, leaked RIDs, SIGSEGV in pthread_mutex_lock). Safe to call twice.
var _quitting := false


func quit_clean(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	set_process(false)
	set_physics_process(false)
	sim = null
	if world:
		world.shutdown_workers()
	if has_xr and xr_if and xr_if.is_initialized():
		_xlog("quit: stopping XR rendering + session")
		get_viewport().use_xr = false
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		xr_if.uninitialize()
		has_xr = false
		_xlog("quit: OpenXR uninitialized")
	await get_tree().process_frame
	get_tree().quit(code)


func _selftest() -> void:
	# XR unavailable must be a clean fallback: report and quit
	await get_tree().process_frame
	await get_tree().process_frame
	print("EVA CLIENT SELFTEST: xr=%s fallback=%s reason='%s' OK" % [has_xr, "flat" if flat_cam != null else "xr", xr_error])
	get_tree().quit(0)


var _xlog_t := 0.0
var _xlog_last := ""         # last logged tracker state (positions excluded)
var _xlog_beat := 0.0        # seconds since the last status line
## XR diagnostics -> ~/.local/share/filament-falcon/eva_vr.log (user://eva_vr.log)
func _xlog(msg: String) -> void:
	var path := OS.get_environment("HOME") + "/.local/share/filament-falcon/eva_vr.log"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s  %s" % [Time.get_datetime_string_from_system(), msg])
	print("[EVA-VR] ", msg)


## Tracker / controller status: logged when it changes (positions left out of the compare)
## and otherwise only as a 60 s heartbeat, not every poll.
func _xr_status(dt: float) -> void:
	var s := ""
	for side: String in ["left_hand", "right_hand"]:
		var t := XRServer.get_tracker(side) as XRPositionalTracker
		s += "%s: %s profile=%s · " % [side, "present" if t else "MISSING", t.profile if t else "-"]
	s += "trackers=%s" % str(XRServer.get_trackers(0xFF).keys())
	for i in ctrl.size():
		var t := XRServer.get_tracker(ctrl[i].tracker) as XRPositionalTracker
		var poses := ""
		if t:
			for pn: String in ["grip_pose", "aim_pose", "palm_pose", "default"]:
				var ps := t.get_pose(pn)
				if ps:
					poses += "%s(%s) " % [pn, ps.has_tracking_data]
		s += " · c%d tracked=%s pose=%s has=[%s]" % [i, ctrl[i].get_has_tracking_data(), ctrl[i].pose, poses.strip_edges()]
	_xlog_beat += dt
	if s == _xlog_last and _xlog_beat < 60.0:
		return
	_xlog_last = s
	_xlog_beat = 0.0
	_xlog(s + " · origin=%s head=%s" % [origin.global_position.snapped(Vector3.ONE * 0.1), xr_cam.global_position.snapped(Vector3.ONE * 0.1)])


# ======================================================================== frame
func _process(dt: float) -> void:
	_t += dt
	_net_rx()
	_dead_reckon(dt)
	_measure_jitter(dt)
	if sim != null and not sim.done:
		_world_inputs()
		var inp := _xr_input(dt) if has_xr else flat.apply(dt, sim, bot.decide(dt, sim) if bot else flat.read_devices(get_window().has_focus() if not Settings.is_headless() else false))
		sim.step_sim(dt, inp)
		_handle_local_events()
	world.eva_view.client_sim = sim
	if has_xr:
		for c in ctrl:   # placeholder gloves until the articulated suit gloves exist
			var gl := c.get_node_or_null("Glove")
			if gl:
				gl.visible = sim == null
		_place_origin()
		_update_comfort(dt)
		_xlog_t -= dt
		if _xlog_t <= 0.0:
			_xlog_t = 2.0
			_xr_status(2.0)
		cuff.text = _cuff_text()
	else:
		_place_flat_cam()
		hud.text = _cuff_text() + ("\n" + flat.hint if flat.hint != "" else "")
	_net_tx(dt)


func _place_origin() -> void:
	if sim == null:
		# waiting at the airlock handrail: head ~1 m out from the hull, facing the hatch
		# (the old spot put your eyes inside the hull, where back-face culling shows only stars)
		var n := EvaScenarios.hatch_normal()
		var head := EvaScenarios.hatch_point() + n * 1.0
		var fwd := Vector3(-n.x, 0.0, -n.z).normalized() if Vector3(n.x, 0, n.z).length() > 0.1 else Vector3.FORWARD
		origin.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), head - Vector3(0, 1.6, 0))
		return
	origin.transform = sim.rig * Transform3D(Basis.IDENTITY, Vector3(0, SEATED_OFFSET if bool(_cfg.get("seated", false)) else 0.0, 0))


func _place_flat_cam() -> void:
	if sim == null:
		var h := EvaScenarios.hatch_point()
		flat_cam.global_transform = world.eva_view.global_transform * Transform3D(Basis.looking_at(Vector3(0.3, -0.2, -1.0).normalized()), h + EvaScenarios.hatch_normal() * 1.6 + Vector3(0, 0.6, 0))
		flat_cam.cull_mask = 0xFFFFF
		return
	var p := sim.pose()
	if flat_view == "EVA DRONE":
		flat_cam.global_transform = CamFeedView.drone_xform(world.eva_view.global_transform, p, _t)
		flat_cam.cull_mask = 0xFFFFF
	else:
		var hd: Transform3D = p["head"]
		flat_cam.global_transform = world.eva_view.global_transform * hd
		flat_cam.cull_mask = 0xFFFFF & ~(Eva.EVA_HEAD_LAYER | Eva.EVA_BODY_LAYER)


func _cuff_text() -> String:
	if sim == null:
		return "SPACEWALK CLIENT · waiting for the Commander (START EVA)\n" + ("headset: " + str(_system_info().get("system", "")) if has_xr else xr_error)
	var s := "%s\n▶ %s\nO2 %d%%  BATT %d%%  HR %d\nGAS %d%%  TETHER %.1f/%d m%s" % [str(sim.scen.get("title", "")), sim.step_text(), int(sim.o2), int(sim.batt), int(sim.heart),
		int(sim.gas), sim.tether_used, int(sim.tether_len), "  TAUT!" if sim.taut else ""]
	if sim.cur_step().has("hold"):
		s += "\nHOLD %.1f / %.1f s" % [sim.progress, float(sim.cur_step()["hold"])]
	return s


# ======================================================================== VR input
func _xr_pressed(c: XRController3D, name: String) -> bool:
	return c.is_button_pressed(name)


func _edge(key: String, down: bool) -> bool:
	var was: bool = _btn_prev.get(key, false)
	_btn_prev[key] = down
	return down and not was


var _hand_mode := ["", ""]          # "controller" / "hand" / "none" per side (logged on change)
var _pinch_on := [false, false]     # hysteresis so a grab never flickers
var _fist_on := [false, false]
var _fingers := [PackedFloat32Array(), PackedFloat32Array()]   # thumb, index, middle, ring, pinky curl 0..1


func _set_hand_mode(i: int, m: String) -> void:
	if _hand_mode[i] != m:
		_hand_mode[i] = m
		_xlog("%s hand: %s" % ["left" if i == 0 else "right", {"controller": "Touch controller", "hand": "HAND TRACKING (pinch = grab, fist = grip)", "none": "not tracked"}[m]])


## Optical hand tracking (XR_EXT_hand_tracking) when it is live and NOT just emulated from a
## held controller. Quest/WiVRn switch automatically when you put the controllers down.
func _optical_hand(i: int) -> XRHandTracker:
	var ht := XRServer.get_tracker("/user/hand_tracker/" + ("left" if i == 0 else "right")) as XRHandTracker
	if ht and ht.has_tracking_data and ht.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		return ht
	return null


## Per-finger curl from the tracked skeleton (signed flexion toward the palm, from joint
## positions; see HandPose), so the articulated suit glove follows your real fingers.
static func hand_curls(ht: XRHandTracker, left: bool) -> PackedFloat32Array:
	return HandPose.curls(HandPose.joints_of(ht), left)


## Gesture state from curls + thumb-index gap, with hysteresis. Returns [pinch, fist, point].
static func hand_gestures(curls: PackedFloat32Array, pinch_gap: float, was_pinch: bool, was_fist: bool) -> Array:
	var pinch := pinch_gap < (0.035 if was_pinch else 0.02)
	var rest := (curls[2] + curls[3] + curls[4]) / 3.0
	var fist := rest > (0.45 if was_fist else 0.6)
	var point := fist and curls[1] < 0.3
	return [pinch and not fist, fist and not point, point]


func _hand_xform(i: int) -> Array:
	# [transform relative to the origin, grip, use, point, tracked]
	var c := ctrl[i]
	var ht := _optical_hand(i)
	var tracked := c.get_has_tracking_data() and ht == null
	if not tracked and ht == null:
		# fall back to any pose the runtime does report (aim/palm) instead of losing the hand
		var t := XRServer.get_tracker(c.tracker) as XRPositionalTracker
		if t:
			for pn: String in ["aim_pose", "palm_pose"]:
				var ps := t.get_pose(pn)
				if ps and ps.has_tracking_data:
					c.pose = pn
					_xlog("controller %d: grip_pose untracked, using %s" % [i, pn])
					tracked = true
					break
	_fingers[i] = PackedFloat32Array()
	if tracked:
		_set_hand_mode(i, "controller")
		var g := c.get_float("grip")
		var tr := c.get_float("trigger")
		var touch := c.is_button_pressed("trigger_touch")
		return [c.transform, g > 0.6, tr > 0.6, g > 0.6 and not touch, true]
	if ht:
		# hands (controllers down): pinch = grab, fist = grip (handrails / tools), fist with the
		# index out = point. Pinch held on a tool = use.
		_set_hand_mode(i, "hand")
		# palm frame from joint positions: the tracker's joint bases are in Godot's humanoid
		# convention (+Y along the bone, +Z out of the palm), not the glove's (-Z / -Y)
		var jp := HandPose.joints_of(ht)
		var palm := HandPose.hand_frame(jp, i == 0)
		var gap := jp[XRHandTracker.HAND_JOINT_THUMB_TIP].distance_to(jp[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP])
		var cu := HandPose.curls(jp, i == 0)
		_fingers[i] = cu
		var gs := hand_gestures(cu, gap, _pinch_on[i], _fist_on[i])
		_pinch_on[i] = gs[0]
		_fist_on[i] = gs[1]
		return [palm, gs[0] or gs[1], gs[0], gs[2], true]
	_set_hand_mode(i, "none")
	return [Transform3D(Basis.IDENTITY, Vector3(0.25 * (-1 if i == 0 else 1), 1.0, -0.3)), false, false, false, false]


## Touch controller analog values -> glove fingers: grip = middle/ring/pinky, trigger = index,
## thumb resting on A/B/stick = thumb down.
func _curl(c: XRController3D) -> Vector3:
	if not c.get_has_tracking_data():
		return Vector3(-1, 0, 0)
	var th := c.is_button_pressed("ax_touch") or c.is_button_pressed("by_touch") or c.is_button_pressed("primary_touch")
	var tr := c.get_float("trigger")
	if c.is_button_pressed("trigger_touch"):
		tr = maxf(tr, 0.25)
	return Vector3(clampf(c.get_float("grip"), 0, 1), clampf(tr, 0, 1), 1.0 if th else 0.0)


func _xr_input(dt: float) -> Dictionary:
	var off := Transform3D(Basis.IDENTITY, Vector3(0, SEATED_OFFSET if bool(_cfg.get("seated", false)) else 0.0, 0))
	var head := off * xr_cam.transform
	var L := _hand_xform(0)
	var R := _hand_xform(1)
	var inp := {"head": head, "hands": [off * (L[0] as Transform3D), off * (R[0] as Transform3D)],
		"grip": [L[1], R[1]], "use": [L[2], R[2]], "point": [L[3], R[3]],
		"curl": [_curl(ctrl[0]) if _fingers[0].is_empty() else Vector3(-1, 0, 0), _curl(ctrl[1]) if _fingers[1].is_empty() else Vector3(-1, 0, 0)],
		"fingers": [_fingers[0], _fingers[1]]}
	var lc := ctrl[0]
	var rc := ctrl[1]
	# left stick: jetpack / moon walk, relative to where you look; right stick Y: up / down
	var ls := lc.get_vector2("primary")
	var rs := rc.get_vector2("primary")
	var yaw := Basis(Vector3.UP, atan2(-head.basis.z.x, -head.basis.z.z))
	var mv := yaw * Vector3(ls.x, 0.0, -ls.y)
	mv.y = rs.y if absf(rs.y) > 0.25 else 0.0
	inp["move"] = mv if mv.length() > 0.15 else Vector3.ZERO
	# snap turn (no smooth turning: comfort)
	if absf(rs.x) > 0.7 and _snap_armed:
		_snap_armed = false
		inp["turn"] = -signf(rs.x) * deg_to_rad(float(_cfg.get("snap", 30.0)))
	elif absf(rs.x) < 0.3:
		_snap_armed = true
	inp["stop"] = _xr_pressed(lc, "by_button")
	inp["lamp_toggle"] = _edge("lamp", _xr_pressed(rc, "by_button"))
	inp["hop"] = _edge("hop", _xr_pressed(rc, "ax_button"))
	_ptt = _xr_pressed(lc, "ax_button")
	inp["ptt"] = _ptt
	# hold Menu ~1 s: recenter (the runtime's own recenter also works)
	if _xr_pressed(lc, "menu_button"):
		_menu_t += dt
		if _menu_t > 0.9:
			_menu_t = -1.0e9   # once per hold; reset only on release
			_xlog("menu hold: recenter")
			XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	else:
		_menu_t = 0.0
	return inp


func _update_comfort(dt: float) -> void:
	var strength := float(_cfg.get("vignette", 0.7))
	var want := 0.0
	if sim != null:
		want = maxf(want, sim.jet_on)
		want = maxf(want, clampf(sim.vel.length() / 0.8, 0.0, 1.0) * 0.6 if sim.att_edge < 0 and not sim.riding else 0.0)
		want = maxf(want, clampf(sim.ship_w.length() / deg_to_rad(4.0), 0.0, 1.0))
		if sim.riding:
			want = maxf(want, 0.5)
	_vig = move_toward(_vig, want * strength, dt * 2.5)
	vignette_mat.set_shader_parameter("strength", _vig)


# ======================================================================== local feedback
var _ev_local := 0


func _handle_local_events() -> void:
	for e: Array in sim.events_after(_ev_local):
		_ev_local = int(e[0])
		match str(e[1]):
			"knock":
				Sfx.tone(140.0, 0.07, 0.6, "sine", 90.0)
				world.eva_view.add_print(e[2].get("pos", Vector3.ZERO), e[2].get("n", Vector3.UP), false)
				_haptic(int(e[2].get("hand", 1)), 0.6)
			"palm":
				world.eva_view.add_print(e[2].get("pos", Vector3.ZERO), e[2].get("n", Vector3.UP), true)
			"pick", "placed", "arm_on":
				Sfx.clunk()
			"step_done":
				Sfx.chime()
			"tether_taut":
				_haptic(0, 0.8)
				_haptic(1, 0.8)


func _haptic(i: int, amp: float) -> void:
	if has_xr and i < ctrl.size():
		ctrl[i].trigger_haptic_pulse("haptic", 0.0, amp, 0.08, 0.0)


# ======================================================================== world mirror
func _world_inputs() -> void:
	sim.arm_ok = Game.arm_extend > 0.9 and bool(Game.powered.get("arm", false))
	sim.arm_tip = Game.arm_base_body() + Game.arm_dir_body() * Game.arm_len * Game.arm_extend + Vector3(0, -0.15, 0)
	sim.cargo_door = Game.cargo_door
	sim.in_sun = not world.in_shadow


## Smooth world clock. Snapshots arrive at the cockpit's frame rate (~75-87 Hz) with jitter,
## the headset renders at 72-120 Hz. Snapping the ship / entities to each snapshot (and
## leaving the entities frozen between them) made everything that moves with the Moon (it
## orbits at ~540 m/s in game scale) jump by metres every frame: the "rock jitter". Now one
## monotonic clock is slewed toward the snapshot time, the ship is extrapolated from the newest
## snapshot to that clock, and entities on rails / surfaces are recomputed locally from it.
var _snap := {}
var _clock := 0.0


func _dead_reckon(dt: float) -> void:
	if _mid == "" or _snap.is_empty():
		return
	var gt: float = _snap["gt"]
	var target := gt + (_t - float(_snap["rx"]))
	_clock += dt
	if absf(target - _clock) > 0.25:
		_clock = target
	else:
		_clock += (target - _clock) * minf(1.0, dt * 3.0)   # gentle slew, never a step
	Game.t = _clock
	for b in Game.bodies:
		(b as CelestialBody).update(Game.t)
	var s: ShipSim = Game.sim
	var h := _clock - gt
	var v: Vector3 = _snap["vel"]
	s.pos.set_xyz(float(_snap["px"]) + v.x * h, float(_snap["py"]) + v.y * h, float(_snap["pz"]) + v.z * h)
	var w: Vector3 = _snap["w"]
	s.basis = (Basis(w.normalized(), w.length() * h) * (_snap["basis"] as Basis)).orthonormalized() if w.length_squared() > 1e-12 else _snap["basis"]
	s.refresh_frame()
	for e: Dictionary in Game.entities:
		match str(e["mode"]):
			"surface", "rails", "field", "towed", "attached":
				Game._place_entity(e)
			_:
				if e.has("_snap"):
					var sn: Array = e["_snap"]
					var ev: Vector3 = sn[3]
					var eh := _clock - float(sn[4])
					(e["pos"] as BigVec).set_xyz(float(sn[0]) + ev.x * eh, float(sn[1]) + ev.y * eh, float(sn[2]) + ev.z * eh)


## Diagnostic sent to the cockpit (client info "ent_jit"): the worst frame-to-frame jump, over
## the last second, of a nearby entity relative to the ship, beyond its smooth relative motion.
var _jit_prev := {}
var _jit_max := 0.0


func _measure_jitter(dt: float) -> void:
	if Game.sim == null or dt <= 0.0:
		return
	var sp: BigVec = Game.sim.pos
	for e: Dictionary in Game.entities:
		var r := (e["pos"] as BigVec).rel(sp)
		if r.length() > 3000.0:
			continue
		var rv: Vector3 = (e.get("vel", Vector3.ZERO) as Vector3) - Game.sim.vel
		var id := str(e["id"])
		if _jit_prev.has(id):
			var pr: Array = _jit_prev[id]
			# compare against the relative velocity predicted from the previous frame
			_jit_max = maxf(_jit_max, (r - ((pr[0] as Vector3) + (pr[1] as Vector3) * dt)).length())
		_jit_prev[id] = [r, rv]


func _apply_world(w: Dictionary) -> void:
	var mid := str(w.get("mid", ""))
	if mid != "" and mid != Game.mission_id or _mid == "":
		Game.load_mission(mid)
	_mid = mid
	var s: ShipSim = Game.sim
	Game.t = float(w["gt"])
	var wv: Array = w.get("wave", [])
	if wv.size() == 2:
		Game.crew_wave = [maxf(float(Game.crew_wave[0]), float(wv[0])), maxf(float(Game.crew_wave[1]), float(wv[1]))]
	for b in Game.bodies:
		(b as CelestialBody).update(Game.t)
	s.pos.set_xyz(float(w["px"]), float(w["py"]), float(w["pz"]))
	s.vel = w["vel"]
	s.basis = w["basis"]
	s.ang_vel = w["w"]
	_snap = {"gt": float(w["gt"]), "rx": _t, "px": float(w["px"]), "py": float(w["py"]), "pz": float(w["pz"]), "vel": w["vel"], "basis": w["basis"], "w": w["w"]}
	s.thrust_now = float(w["thr"])
	s.engine_on = bool(w["eng"])
	s.density_now = float(w["dens"])
	Game.sun_dir = w["sun"]
	Game.cargo_door = float(w["door"])
	var arm: Array = w["arm"]
	Game.arm_yaw = float(arm[0])
	Game.arm_pitch = float(arm[1])
	Game.arm_len = float(arm[2])
	Game.arm_extend = float(arm[3])
	Game.powered["arm"] = bool(arm[4])
	Game.state = int(w["state"])
	s.pick_dominant()
	s.refresh_frame()
	var by_id := {}
	for e: Dictionary in Game.entities:
		by_id[str(e["id"])] = e
	for en: Array in w["ents"]:
		var e: Dictionary = by_id.get(str(en[0]), {})
		if not e.is_empty():
			(e["pos"] as BigVec).set_xyz(float(en[1]), float(en[2]), float(en[3]))
			e["basis"] = en[4]
			e["visible"] = en[5]
			if en.size() > 6:
				e["vel"] = en[6]
				e["_snap"] = [float(en[1]), float(en[2]), float(en[3]), en[6], float(w["gt"])]
	_dead_reckon(0.0)     # place everything on the smooth clock right away (no snap)
	_srv_ack = int(w["ack"])
	_cfg = w.get("cfg", _cfg)
	if sim != null:
		var b2: Basis = s.basis
		sim.ship_w = b2.inverse() * (w["w"] as Vector3)
		sim.ship_acc = b2.inverse() * (w["acc"] as Vector3)
	for c: Array in w["cmds"]:
		var id := int(c[0])
		if id <= _cack:
			continue
		_cack = id
		match str(c[1]):
			"start":
				sim = EvaSim.new()
				sim.setup((c[2] as Dictionary)["scen"])
				_ev_local = 0
				flat = FlatControl.new()
				if bot:
					bot = EvaBot.new()
			"abort":
				sim = null
			"quit":
				quit_clean()
	if not bool(w["eva"]) and sim != null and sim.done:
		sim = null


func _net_rx() -> void:
	while _udp.get_available_packet_count() > 0:
		var v: Variant = bytes_to_var(_udp.get_packet())
		if typeof(v) == TYPE_DICTIONARY and str((v as Dictionary).get("t", "")) == "w":
			_apply_world(v)
			_last_rx = _t
			_rx += 1


func _net_tx(dt: float) -> void:
	_info_t -= dt
	var d := {"t": "st" if sim != null else "hi", "cack": _cack, "ptt": _ptt}
	if _info_t <= 0.0:
		_info_t = 1.0
		var info := {"xr": has_xr, "xr_error": xr_error, "fps": Engine.get_frames_per_second(), "bot": bot != null, "ent_jit": _jit_max, "hands": _hand_mode}
		_jit_max = 0.0
		info.merge(_system_info())
		d["info"] = info
	if sim != null:
		d["s"] = sim.to_net()
		d["ev"] = sim.events_after(_srv_ack)
	_udp.put_packet(var_to_bytes(d))
	_sent += 1
