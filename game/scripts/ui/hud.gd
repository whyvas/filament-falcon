class_name Hud
extends Control
## Forward-window HUD. World markers (horizon, pitch ladder, prograde, target, guidance,
## approach boxes, sun flare) are projected through each window's own off-axis camera, so
## they flow continuously across both monitors. Text panels are role-specific:
## left = PILOT flight data, right = OPS systems / docking / arm data.

const CYAN := Color(0.35, 0.95, 1.0)
const GREEN := Color(0.35, 1.0, 0.45)
const AMBER := Color(1.0, 0.7, 0.15)
const RED := Color(1.0, 0.25, 0.2)
const WHITE := Color(1, 1, 1)
const PURPLE := Color(0.75, 0.5, 1.0)

var side := -1
var cam: Camera3D
var font: Font
var _callout := ""
var _callout_t := 0.0
var _callout_pri := 0
var _t := 0.0
var _confetti: Array = []
var _proj := Projection()
var _view := Transform3D()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	Voice.callout.connect(func(text: String, pri: int) -> void:
		_callout = text
		_callout_t = 4.5
		_callout_pri = pri)
	Game.mission_finished.connect(func(ok: bool) -> void:
		if ok:
			_spawn_confetti())


func _process(dt: float) -> void:
	_t += dt
	_callout_t -= dt
	for c in _confetti:
		c["v"] += Vector2(0, 260.0) * dt
		c["p"] += c["v"] * dt
		c["r"] += c["w"] * dt
	_confetti = _confetti.filter(func(c: Dictionary) -> bool: return c["p"].y < size.y + 50.0)
	queue_redraw()


func _spawn_confetti() -> void:
	for i in 260:
		_confetti.append({"p": Vector2(randf() * size.x, -randf() * 600.0), "v": Vector2(randf_range(-80, 80), randf_range(0, 200)),
			"r": randf() * TAU, "w": randf_range(-6, 6), "c": Color.from_hsv(randf(), 0.8, 1.0)})


## World point (floating-origin coordinates) -> HUD pixel; z < 0 means behind the camera.
func project(p: Vector3) -> Vector3:
	var v := _view * p
	var clip := _proj * Vector4(v.x, v.y, v.z, 1.0)
	if clip.w <= 0.0001:
		return Vector3(0, 0, -1)
	var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
	return Vector3((ndc.x * 0.5 + 0.5) * size.x, (0.5 - ndc.y * 0.5) * size.y, 1.0)


func project_dir(d: Vector3) -> Vector3:
	return project(cam.global_position + d.normalized() * 1000.0)


func _txt(pos: Vector2, s: String, sz: int = 26, c: Color = CYAN, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(font, pos + Vector2(2, 2), s, align, width, sz, Color(0, 0, 0, 0.6 * c.a))
	draw_string(font, pos, s, align, width, sz, c)


func _on_screen(p: Vector3, margin: float = 0.0) -> bool:
	return p.z > 0.0 and p.x > -margin and p.x < size.x + margin and p.y > -margin and p.y < size.y + margin


func _draw() -> void:
	if cam == null or not is_inside_tree():
		return
	_view = cam.global_transform.affine_inverse()
	_proj = cam.get_camera_projection()
	var g := Game
	var sim: ShipSim = g.sim
	var glitch: bool = g.failures["sensor"]
	var hud_on: bool = g.powered.get("avionics", false) or g.state != Game.State.ACTIVE
	_draw_flare()
	if not g.master_power:
		_txt(Vector2(0, size.y * 0.5), "MASTER POWER OFF", 54, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		return
	if hud_on:
		if glitch:
			draw_set_transform(Vector2(randf_range(-14, 14), randf_range(-8, 8)))
		_draw_world_markers(g, sim)
		draw_set_transform(Vector2.ZERO)
		if side < 0:
			_draw_pilot_panel(g, sim)
		else:
			_draw_ops_panel(g, sim)
		if glitch:
			for i in 30:
				var y := randf() * size.y
				draw_line(Vector2(0, y), Vector2(size.x, y + randf_range(-3, 3)), Color(1, 1, 1, randf() * 0.25), randf_range(1, 4))
	else:
		_txt(Vector2(0, 80), "AVIONICS OFF", 36, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_banner(g)
	_draw_caution(g)
	_draw_state_overlay(g)
	if g.o2 < 50.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, clampf((50.0 - g.o2) / 60.0, 0.0, 0.7)))
	for c in _confetti:
		draw_set_transform(c["p"], c["r"])
		draw_rect(Rect2(-6, -3, 12, 6), c["c"])
	draw_set_transform(Vector2.ZERO)


func _draw_flare() -> void:
	if Game.jump_phase > 0.0:
		return
	var w: WorldView = get_tree().get_first_node_in_group("world")
	if w == null or w.in_shadow:
		return
	var sp := project_dir(Game.sun_dir)
	if not _on_screen(sp, 400.0):
		return
	var center := size * 0.5
	var p := Vector2(sp.x, sp.y)
	var dvec := center - p
	var fade := 1.0 - clampf(dvec.length() / (size.length() * 0.9), 0.0, 1.0)
	var atm := 1.0 - w.day_factor * 0.6
	var cols := [Color(1, 0.9, 0.7), Color(0.6, 0.8, 1.0), Color(1.0, 0.5, 0.3), Color(0.5, 1.0, 0.7), Color(0.8, 0.6, 1.0)]
	var rad := [90.0, 30.0, 55.0, 18.0, 120.0]
	var pos_k := [0.0, 0.45, 0.8, 1.15, 1.5]
	for i in 5:
		var c: Color = cols[i]
		c.a = (0.18 if i > 0 else 0.35) * fade * atm
		draw_circle(p + dvec * pos_k[i], rad[i], c)
	var streak := Color(1, 0.95, 0.85, 0.25 * fade * atm)
	draw_line(p - Vector2(400, 0), p + Vector2(400, 0), streak, 3.0)


func _draw_world_markers(g: Node, sim: ShipSim) -> void:
	var up := sim.up_dir
	var dom: CelestialBody = sim.dominant
	var near_body := sim.altitude < dom.radius * 2.0
	# Horizon + pitch ladder
	if near_body:
		var fwd := sim.forward()
		var hf := fwd.slide(up)
		if hf.length() < 0.05:
			hf = (-sim.basis.y).slide(up)
		hf = hf.normalized()
		var hr := hf.cross(up)
		# Horizon: long curve across both windows
		var hpts := PackedVector2Array()
		for i in 49:
			var az := lerpf(-PI, PI, float(i) / 48.0)
			var hp := project_dir(hf * cos(az) + hr * sin(az))
			if hp.z > 0.0:
				hpts.append(Vector2(hp.x, hp.y))
			elif hpts.size() >= 2:
				draw_polyline(hpts, GREEN, 3.0)
				hpts = PackedVector2Array()
			else:
				hpts = PackedVector2Array()
		if hpts.size() >= 2:
			draw_polyline(hpts, GREEN, 3.0)
		# Pitch ladder rungs at two headings (one per window), oriented along the local horizon
		for az0: float in [-0.42, 0.42]:
			for pd in range(-80, 90, 10):
				if pd == 0:
					continue
				var pr := deg_to_rad(pd)
				var dir_c := (hf * cos(az0) + hr * sin(az0)) * cos(pr) + up * sin(pr)
				var dir_r := (hf * cos(az0 + 0.01) + hr * sin(az0 + 0.01)) * cos(pr) + up * sin(pr)
				var pc := project_dir(dir_c)
				var prr := project_dir(dir_r)
				if not _on_screen(pc) or prr.z <= 0.0:
					continue
				var c := Vector2(pc.x, pc.y)
				var along := (Vector2(prr.x, prr.y) - c).normalized()
				var nrm := Vector2(-along.y, along.x)
				var col := Color(GREEN, 0.6) if pd > 0 else Color(AMBER, 0.6)
				var tick := nrm * (10.0 if pd > 0 else -10.0)
				for sgn: float in [-1.0, 1.0]:
					var a := c + along * sgn * 30.0
					var b := c + along * sgn * 110.0
					if pd < 0:
						# dashed below the horizon
						draw_line(a, a.lerp(b, 0.4), col, 2.0)
						draw_line(a.lerp(b, 0.6), b, col, 2.0)
					else:
						draw_line(a, b, col, 2.0)
					draw_line(b, b + tick, col, 2.0)
				_txt(c + along * 120.0 + Vector2(4, 8), str(absi(pd)), 20, col)
	# Prograde / retrograde
	var sv := sim.surface_vel
	if sv.length() > 1.0:
		var pg := project_dir(sv)
		if _on_screen(pg):
			_marker_prograde(Vector2(pg.x, pg.y), GREEN)
		var rg := project_dir(-sv)
		if _on_screen(rg):
			_marker_retro(Vector2(rg.x, rg.y), AMBER)
	# Nav vector (what PROGRADE assist steers to)
	if g.nav_dir.length() > 0.5:
		var nv := project_dir(g.nav_dir)
		if _on_screen(nv):
			var c := Vector2(nv.x, nv.y)
			var s := 26.0 + 4.0 * sin(_t * 6.0)
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.6), c, c + Vector2(s, s * 0.6)]), CYAN, 4.0)
			_txt(c + Vector2(-60, 46), g.nav_vector, 20, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 120)
	# Target
	var ts: Array = g.target_state()
	if not ts.is_empty() and g.powered.get("sensors", false):
		var rel: Vector3 = (ts[0] as BigVec).rel(sim.pos)
		var tp := project(rel) if rel.length() < 5.0e6 else project_dir(rel)
		var tname: String = g.current_target().get("name", "")
		if _on_screen(tp):
			var c2 := Vector2(tp.x, tp.y)
			draw_polyline(PackedVector2Array([c2 + Vector2(0, -22), c2 + Vector2(22, 0), c2 + Vector2(0, 22), c2 + Vector2(-22, 0), c2 + Vector2(0, -22)]), PURPLE, 3.0)
			_txt(c2 + Vector2(28, -8), tname, 22, PURPLE)
			_txt(c2 + Vector2(28, 18), _fmt_dist(rel.length()), 22, PURPLE)
	# Mission guidance
	var gd: Dictionary = g.mission.guidance if g.mission else {}
	if gd.has("docking") and side > 0:
		pass
	if g.mission and g.mission.id == "reentry" and g.mission.beacon_locked:
		var pts2: Array = g.mission.approach_points()
		for i in pts2.size():
			var bp := project(pts2[i])
			if bp.z > 0.0:
				var d := (pts2[i] as Vector3).length()
				var half := clampf(60.0 * cam.get_camera_projection().y.y * 540.0 / maxf(d, 1.0), 4.0, 400.0)
				var bc := Vector2(bp.x, bp.y)
				draw_rect(Rect2(bc - Vector2(half * 1.6, half), Vector2(half * 3.2, half * 2.0)), Color(GREEN, 0.8), false, 3.0)
	if g.mission and g.mission.id == "asteroids" and gd.has("jump_dir"):
		var jp := project_dir(gd["jump_dir"])
		if _on_screen(jp):
			var jc := Vector2(jp.x, jp.y)
			draw_arc(jc, 40.0 + 6.0 * sin(_t * 5.0), 0, TAU, 40, PURPLE, 4.0)
			_txt(jc + Vector2(-80, 70), "JUMP HOME", 24, PURPLE, HORIZONTAL_ALIGNMENT_CENTER, 160)
	# Laser crosshair / ship boresight
	var bore := project_dir(sim.forward())
	if _on_screen(bore):
		var b := Vector2(bore.x, bore.y)
		var col := RED if g.laser_on else Color(WHITE, 0.6)
		draw_line(b + Vector2(-30, 0), b + Vector2(-10, 0), col, 2.0)
		draw_line(b + Vector2(10, 0), b + Vector2(30, 0), col, 2.0)
		draw_line(b + Vector2(0, -30), b + Vector2(0, -10), col, 2.0)
	# Tractor beam aim point
	if g.ops_mode == 1 and g.arm_extend > 0.5 and side > 0:
		var ap := project(g.arm_tip_rel() + g.arm_dir_world() * 40.0)
		if _on_screen(ap):
			draw_arc(Vector2(ap.x, ap.y), 30.0, 0, TAU, 32, Color(0.3, 0.75, 1.0), 3.0)
	# Revealed objects worth pointing at
	for e in g.entities:
		if e["kind"] in ["pod", "crystal", "crystal_rock", "lunar_pad"] and e["revealed"] and e["mode"] != "attached":
			var rp := project((e["pos"] as BigVec).rel(sim.pos))
			if _on_screen(rp):
				draw_arc(Vector2(rp.x, rp.y), 16.0, 0, TAU, 20, Color(0.3, 1.0, 0.9, 0.8), 2.0)
	# Scanner ping ring
	if g.scanner_age < 2.0:
		var r: float = g.scanner_age * size.x * 0.5
		draw_arc(size * 0.5, r, 0, TAU, 96, Color(0.3, 0.8, 1.0, 1.0 - g.scanner_age / 2.0), 6.0)


func _marker_prograde(c: Vector2, col: Color) -> void:
	draw_arc(c, 16.0, 0, TAU, 24, col, 3.0)
	draw_line(c + Vector2(-34, 0), c + Vector2(-16, 0), col, 3.0)
	draw_line(c + Vector2(16, 0), c + Vector2(34, 0), col, 3.0)
	draw_line(c + Vector2(0, -16), c + Vector2(0, -30), col, 3.0)


func _marker_retro(c: Vector2, col: Color) -> void:
	draw_arc(c, 16.0, 0, TAU, 24, col, 3.0)
	draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), col, 3.0)
	draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), col, 3.0)


static func _fmt_dist(m: float) -> String:
	if m < 1000.0:
		return "%d m" % int(m)
	if m < 100000.0:
		return "%.1f km" % (m / 1000.0)
	return "%d km" % int(m / 1000.0)


func _gauge(pos: Vector2, label: String, frac: float, col: Color, text: String) -> void:
	draw_rect(Rect2(pos, Vector2(260, 22)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(pos, Vector2(260 * clampf(frac, 0.0, 1.0), 22)), col)
	draw_rect(Rect2(pos, Vector2(260, 22)), Color(col, 0.8), false, 2.0)
	_txt(pos + Vector2(0, -6), label, 20, col)
	_txt(pos + Vector2(270, 19), text, 22, WHITE)


func _draw_pilot_panel(g: Node, sim: ShipSim) -> void:
	var x := 40.0
	var y := 170.0
	draw_rect(Rect2(x - 16, y - 40, 470, 520), Color(0, 0.05, 0.1, 0.35))
	var rows := [
		["ALT", _fmt_dist(sim.altitude)],
		["RADAR", _fmt_dist(sim.agl) if sim.agl < 20000.0 and g.powered.get("sensors", false) else "---"],
		["SPEED", "%d m/s" % int(sim.surface_vel.length())],
		["V/S", "%+.1f m/s" % sim.vspeed],
		["G", "%.1f g" % sim.g_load],
		["ASSIST", ShipSim.FA_NAMES[sim.fa_mode]],
	]
	for i in rows.size():
		_txt(Vector2(x, y + i * 44), rows[i][0], 24, Color(CYAN, 0.7))
		_txt(Vector2(x + 140, y + i * 44), rows[i][1], 32, WHITE)
	var gy := y + rows.size() * 44 + 20
	_gauge(Vector2(x, gy), "THROTTLE", sim.throttle, GREEN if sim.engine_on else AMBER, "%d%%%s" % [int(sim.throttle * 100.0), " BOOST" if sim.boost else ""])
	if sim.booster_attached:
		_gauge(Vector2(x, gy + 60), "BOOSTER FUEL", sim.booster_fuel / sim.booster_fuel_max, AMBER, "%d%%" % int(sim.booster_fuel / sim.booster_fuel_max * 100.0))
	else:
		_gauge(Vector2(x, gy + 60), "FUEL", sim.fuel / sim.fuel_max, GREEN if sim.fuel > 600.0 else RED, "%d kg" % int(sim.fuel))
	var eng := "ENGINE RUNNING" if sim.engine_on else ("ENGINE ARMED" if InputHub.on("engine_arm") else "ENGINE SAFE")
	_txt(Vector2(x, gy + 130), eng, 26, GREEN if sim.engine_on else (AMBER if InputHub.on("engine_arm") else Color(WHITE, 0.6)))
	_txt(Vector2(x, gy + 164), "GEAR %s   FLAPS %s%s" % ["DOWN" if sim.gear_down else "UP", ["UP", "HALF", "DOWN"][int(sim.flaps * 2.0)], "   AIRBRAKE" if sim.airbrake else ""], 22, WHITE)
	# Orbit summary
	var dom: CelestialBody = sim.dominant
	var el := OrbitMath.elements(sim.pos.rel(dom.pos), sim.vel - dom.vel, dom.gm, dom.radius)
	var ap: float = el["ap_alt"]
	_txt(Vector2(x, gy + 205), "AP %s   PE %s" % ["ESC" if el["escaping"] else _fmt_dist(ap), _fmt_dist(float(el["pe_alt"]))], 24, CYAN)
	# Mission specific pilot cues
	var gd: Dictionary = g.mission.guidance if g.mission else {}
	if gd.has("countdown") and g.mission.counting:
		var cd: float = gd["countdown"]
		_txt(Vector2(0, size.y * 0.42), "T-%d" % ceili(cd) if cd > 0.0 else "HOLD", 140, AMBER if cd > 0.0 else RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if gd.has("pitch_target") and g.state == Game.State.ACTIVE:
		_txt(Vector2(x, gy + 245), "PITCH TARGET %d°" % int(gd["pitch_target"]), 24, GREEN)
	if gd.has("sink_target"):
		var ok: bool = sim.vspeed > float(gd["sink_target"]) - 2.0 and sim.vspeed < 1.0
		_txt(Vector2(x, gy + 245), "SINK TARGET %.0f m/s" % float(gd["sink_target"]), 24, GREEN if ok else AMBER)
	if gd.has("flash") and fmod(_t, 0.8) < 0.5:
		_txt(Vector2(0, size.y * 0.3), str(gd["flash"]), 72, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if gd.has("entry_aoa") and sim.density_now > 0.0:
		_txt(Vector2(x, gy + 280), "AoA %d°  (target %d°)" % [int(rad_to_deg(sim.aoa)), int(gd["entry_aoa"])], 24, GREEN if absf(rad_to_deg(sim.aoa) - float(gd["entry_aoa"])) < 6.0 else AMBER)
	if sim.hull_temp > 900.0:
		_txt(Vector2(x, gy + 315), "HULL %d K" % int(sim.hull_temp), 26, RED if sim.hull_temp > 1450.0 else AMBER)


func _draw_ops_panel(g: Node, sim: ShipSim) -> void:
	var x := size.x - 520.0
	var y := 170.0
	draw_rect(Rect2(x - 16, y - 40, 500, 560), Color(0, 0.05, 0.1, 0.35))
	_txt(Vector2(x, y), "MODE  " + Game.OPS_MODES[g.ops_mode], 34, CYAN)
	# RCS translation bars
	var tr := sim.in_trans
	var labels := ["L/R", "D/U", "B/F"]
	for i in 3:
		var v: float = [tr.x, tr.y, tr.z][i]
		var by := y + 40 + i * 34
		_txt(Vector2(x, by + 18), labels[i], 20, Color(CYAN, 0.7))
		draw_rect(Rect2(Vector2(x + 70, by), Vector2(300, 20)), Color(0, 0, 0, 0.5))
		var mid := x + 220.0
		draw_rect(Rect2(Vector2(minf(mid, mid + v * 150.0), by), Vector2(absf(v) * 150.0, 20)), GREEN)
		draw_line(Vector2(mid, by - 3), Vector2(mid, by + 23), WHITE, 2.0)
	_gauge(Vector2(x, y + 180), "RCS FUEL", sim.mono / sim.mono_max, CYAN, "%d%%" % int(sim.mono / sim.mono_max * 100.0))
	var pw_col := GREEN if g.power_ok else RED
	_gauge(Vector2(x, y + 240), "POWER USE", g.power_draw / maxf(g.power_avail, 1.0), pw_col, "%d / %d" % [int(g.power_draw), int(g.power_avail)])
	var sys_line := ""
	for pair in [["REA", g.reactor_out > 90.0], ["LIFE", g.powered.get("life", false)], ["SHLD", g.powered.get("shields", false)], ["COMM", g.powered.get("comms", false)], ["SENS", g.powered.get("sensors", false)]]:
		sys_line += ("■" if pair[1] else "□") + pair[0] + "  "
	_txt(Vector2(x, y + 300), sys_line, 22, WHITE)
	var tgt: Dictionary = g.current_target()
	if not tgt.is_empty():
		var ts: Array = g.target_state()
		var rel: Vector3 = (ts[0] as BigVec).rel(sim.pos)
		var rv: Vector3 = sim.vel - (ts[1] as Vector3)
		var closing := -rv.dot(rel.normalized())
		_txt(Vector2(x, y + 340), "TGT " + str(tgt["name"]), 26, PURPLE)
		_txt(Vector2(x, y + 372), "%s   %+.1f m/s" % [_fmt_dist(rel.length()), closing], 26, WHITE)
	if InputHub.on("jump_arm") or g.jump_charge > 0.0:
		_gauge(Vector2(x, y + 420), "JUMP DRIVE", g.jump_charge / 100.0, PURPLE, "READY" if g.jump_charge >= 100.0 else "%d%%" % int(g.jump_charge))
	if g.ops_mode == 1:
		_txt(Vector2(x, y + 470), "ARM %s  BEAM %s" % ["OUT" if g.arm_extend > 0.95 else ("MOVING" if g.arm_extend > 0.0 else ("DOORS!" if g.cargo_door < 0.95 else "STOWED")), "ON" if g.beam_on else "OFF"], 24, CYAN)
	# Docking display
	var gd: Dictionary = g.mission.guidance if g.mission else {}
	if gd.has("docking"):
		var info: Dictionary = gd["docking"]
		var c := Vector2(size.x * 0.5, size.y * 0.55) if side > 0 else Vector2.ZERO
		c = Vector2(size.x * 0.32, size.y * 0.6)
		var lat: Vector2 = info["lat"]
		var r := 150.0
		draw_arc(c, r, 0, TAU, 64, Color(CYAN, 0.6), 2.0)
		draw_arc(c, r * 0.2, 0, TAU, 32, Color(GREEN, 0.8), 2.0)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(CYAN, 0.4), 1.0)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(CYAN, 0.4), 1.0)
		var scale_m := 10.0 if float(info["range"]) > 30.0 else 2.0
		var dot := c + Vector2(lat.x, -lat.y) / scale_m * r
		dot = c + (dot - c).limit_length(r)
		var ok := lat.length() < 0.4 and float(info["angle"]) < 3.0
		draw_circle(dot, 14.0, GREEN if ok else AMBER)
		var lv: Vector2 = info["lat_vel"]
		draw_line(dot, dot + Vector2(lv.x, -lv.y) * 120.0, WHITE, 3.0)
		_txt(c + Vector2(-r, r + 40), "RANGE %.1f m" % float(info["range"]), 28, WHITE)
		var cl: float = info["closing"]
		_txt(c + Vector2(-r, r + 76), "CLOSING %.2f m/s" % cl, 28, GREEN if cl < 0.3 else (AMBER if cl < 0.6 else RED))
		_txt(c + Vector2(-r, r + 112), "ALIGN %.1f°  OFFSET %.2f m" % [float(info["angle"]), lat.length()], 24, GREEN if ok else AMBER)
		_txt(c + Vector2(-r, -r - 16), "DOCKING  (scale %d m)" % int(scale_m), 22, CYAN)
	if gd.has("pad_dist"):
		_txt(Vector2(x, y + 520), "BEACON %s" % _fmt_dist(float(gd["pad_dist"])), 26, GREEN)
	if gd.has("blackout") and gd["blackout"] and fmod(_t, 1.0) < 0.6:
		_txt(Vector2(0, size.y * 0.25), "COMMS BLACKOUT - PLASMA", 48, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw_banner(g: Node) -> void:
	if g.mission == null:
		return
	var o: Dictionary = g.mission.current_objective()
	var role: String = str(o.get("role", "ALL"))
	var mine := role == "BOTH" or role == "ALL" or (side < 0 and role == "PILOT") or (side > 0 and role == "OPS")
	var col := GREEN if mine else Color(WHITE, 0.55)
	draw_rect(Rect2(0, 0, size.x, 92), Color(0, 0.04, 0.08, 0.55))
	var who := "YOUR JOB" if mine else role
	_txt(Vector2(30, 40), ("PILOT" if side < 0 else "OPS") + "  |  " + g.mission.title, 24, Color(CYAN, 0.8))
	_txt(Vector2(30, 78), "%s: %s" % [who, str(o.get("text", ""))], 32 if mine else 26, col)
	if _callout_t > 0.0 and _callout != "":
		var a := clampf(_callout_t, 0.0, 1.0)
		var cc := RED if _callout_pri >= 2 else (AMBER if _callout_pri == 1 else WHITE)
		cc.a = a
		draw_rect(Rect2(size.x * 0.15, size.y - 170, size.x * 0.7, 70), Color(0, 0, 0, 0.5 * a))
		_txt(Vector2(size.x * 0.15, size.y - 122), _callout, 34, cc, HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.7)


func _draw_caution(g: Node) -> void:
	if g.warnings.is_empty():
		return
	var blink: bool = g.caution_active and not g.caution_silenced and fmod(_t, 0.6) < 0.3
	var y := 110.0
	var x := size.x * 0.5 - 300.0
	draw_rect(Rect2(x, y, 600, 46), RED if blink else Color(0.4, 0.05, 0.05, 0.8))
	_txt(Vector2(x, y + 34), "MASTER CAUTION", 32, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 600)
	var i := 0
	for k in g.warnings:
		_txt(Vector2(x, y + 82 + i * 32), str(g.warnings[k]), 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 600)
		i += 1
		if i >= 4:
			break


func _draw_state_overlay(g: Node) -> void:
	match g.state:
		Game.State.BRIEFING:
			draw_rect(Rect2(0, size.y * 0.62, size.x, 170), Color(0, 0, 0, 0.55))
			_txt(Vector2(0, size.y * 0.62 + 70), g.mission.title + " - " + g.mission.tagline, 54, CYAN, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			var need: bool = g.mission.requires_checklist and g.checklist_progress < Game.CHECKLIST.size()
			var msg: String = ("Overhead checklist: flip %s next" % Game.CHECKLIST_NAMES[g.checklist_progress]) if need else "Commander: press START!"
			_txt(Vector2(0, size.y * 0.62 + 130), msg, 34, AMBER if need else GREEN, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Game.State.PAUSED:
			_txt(Vector2(0, size.y * 0.5), "PAUSED", 90, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Game.State.COMPLETE:
			draw_rect(Rect2(0, size.y * 0.3, size.x, 330), Color(0, 0.05, 0.02, 0.6))
			_txt(Vector2(0, size.y * 0.3 + 110), "MISSION COMPLETE!", 96, GREEN, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			var stars := ""
			for i in 3:
				stars += "★ " if i < g.stars else "☆ "
			_txt(Vector2(0, size.y * 0.3 + 220), stars, 90, Color(1, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER, size.x)
			_txt(Vector2(0, size.y * 0.3 + 300), "SCORE %d" % g.score_total, 48, WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Game.State.FAILED:
			draw_rect(Rect2(0, size.y * 0.35, size.x, 220), Color(0.1, 0, 0, 0.6))
			_txt(Vector2(0, size.y * 0.35 + 100), g.result_text, 52, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			_txt(Vector2(0, size.y * 0.35 + 170), "Press START to try again", 40, WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
