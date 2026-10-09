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
	draw_string_outline(font, pos, s, align, width, sz, maxi(3, sz / 7), Color(0, 0, 0, 0.55 * c.a))
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
		# Horizon: faint curve across both windows, with a gap around the boresight
		var hcol := Color(GREEN, 0.4)
		var hpts := PackedVector2Array()
		var ctr := Vector2(size.x * 0.5, size.y * 0.5)
		for i in 97:
			var az := lerpf(-PI, PI, float(i) / 96.0)
			var hp := project_dir(hf * cos(az) + hr * sin(az))
			var ok := hp.z > 0.0 and absf(hp.x - ctr.x) > 160.0
			if ok:
				hpts.append(Vector2(hp.x, hp.y))
			elif hpts.size() >= 2:
				draw_polyline(hpts, hcol, 1.5, true)
				hpts = PackedVector2Array()
			else:
				hpts = PackedVector2Array()
		if hpts.size() >= 2:
			draw_polyline(hpts, hcol, 1.5, true)
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
				var col := Color(GREEN, 0.4) if pd > 0 else Color(AMBER, 0.4)
				var tick := nrm * (10.0 if pd > 0 else -10.0)
				for sgn: float in [-1.0, 1.0]:
					var a := c + along * sgn * 30.0
					var b := c + along * sgn * 110.0
					if pd < 0:
						# dashed below the horizon
						draw_line(a, a.lerp(b, 0.4), col, 1.5)
						draw_line(a.lerp(b, 0.6), b, col, 1.5)
					else:
						draw_line(a, b, col, 1.5)
					draw_line(b, b + tick, col, 1.5)
				_txt(c + along * 120.0 + Vector2(4, 8), str(absi(pd)), 18, col)
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


## Thin, background-free bar (window HUD). Vertical when `vert`.
func _bar(pos: Vector2, sz: Vector2, frac: float, col: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(pos, sz), Color(col, 0.35), false, 1.5)
	if sz.y > sz.x:
		draw_rect(Rect2(pos + Vector2(0, sz.y * (1.0 - frac)), Vector2(sz.x, sz.y * frac)), Color(col, 0.7))
	else:
		draw_rect(Rect2(pos, Vector2(sz.x * frac, sz.y)), Color(col, 0.7))


## Orbit readout shared by the HUD and the touchscreen: [state, apoapsis, periapsis].
static func orbit_strings(sim: ShipSim) -> Array:
	var dom: CelestialBody = sim.dominant
	if dom == null:
		return ["", "---", "---"]
	if sim.touching or (sim.agl < 200.0 and sim.surface_vel.length() < 15.0):
		return ["ON THE GROUND", "---", "---"]
	var el := OrbitMath.elements(sim.pos.rel(dom.pos), sim.vel - dom.vel, dom.gm, dom.radius)
	if el["escaping"]:
		return ["ESCAPING " + dom.display_name, "ESCAPE", _fmt_dist(maxf(float(el["pe_alt"]), 0.0))]
	var ap := _fmt_dist(float(el["ap_alt"]))
	if float(el["pe_alt"]) < (dom.atmo_top if dom.atmo_top > 0.0 else 0.0):
		var pe := "below surface" if float(el["pe_alt"]) < 0.0 else _fmt_dist(float(el["pe_alt"])) + " (in air)"
		return ["SUBORBITAL", ap, pe]
	return ["IN ORBIT", ap, _fmt_dist(float(el["pe_alt"]))]


const HUD_A := 0.85   # overall HUD opacity on the windows


## Minimal pilot HUD: speed / altitude / vertical speed by the lower-left corner,
## slim throttle + fuel bars, and the flight cues that matter right now. Everything
## else lives on the touchscreen (top telemetry strip, NAV, SYSTEMS).
func _draw_pilot_panel(g: Node, sim: ShipSim) -> void:
	var x := 70.0
	var y := size.y - 250.0
	var c := Color(GREEN, HUD_A)
	var dim := Color(CYAN, 0.65)
	var radar_ok: bool = sim.agl < 5000.0 and g.powered.get("sensors", false)
	var rows := [
		["SPD", "%d" % int(sim.surface_vel.length()), "m/s"],
		["ALT", _fmt_dist(sim.agl if radar_ok else sim.altitude), "R" if radar_ok else ""],
		["V/S", "%+.1f" % sim.vspeed, "m/s"],
	]
	for i in rows.size():
		_txt(Vector2(x, y + i * 46), rows[i][0], 20, dim)
		_txt(Vector2(x + 60, y + i * 46), rows[i][1], 34, c)
		_txt(Vector2(x + 220, y + i * 46), rows[i][2], 18, dim)
	# throttle + fuel: two slim vertical bars at the window edge
	var bx := 24.0
	var by := size.y - 300.0
	_bar(Vector2(bx, by), Vector2(10, 180), sim.throttle, GREEN if sim.engine_on else AMBER)
	var ff := sim.booster_fuel / sim.booster_fuel_max if sim.booster_attached else sim.fuel / sim.fuel_max
	_bar(Vector2(bx + 18, by), Vector2(10, 180), ff, AMBER if sim.booster_attached else (GREEN if sim.fuel > 600.0 else RED))
	_txt(Vector2(bx - 4, by + 204), "T  F", 16, dim)
	if sim.g_load > 2.5:
		_txt(Vector2(x, y - 40), "%.1f g" % sim.g_load, 28, AMBER if sim.g_load < 5.0 else RED)
	# Mission cues
	var gd: Dictionary = g.mission.guidance if g.mission else {}
	var cue_y := y + 3 * 46 + 10
	if gd.has("countdown") and g.mission.counting:
		var cd: float = gd["countdown"]
		_txt(Vector2(0, size.y * 0.42), "T-%d" % ceili(cd) if cd > 0.0 else "HOLD", 140, Color(AMBER if cd > 0.0 else RED, 0.9), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if gd.has("pitch_target") and g.state == Game.State.ACTIVE:
		_txt(Vector2(x, cue_y), "PITCH %d°" % int(gd["pitch_target"]), 22, c)
	if gd.has("sink_target"):
		var ok: bool = sim.vspeed > float(gd["sink_target"]) - 2.0 and sim.vspeed < 1.0
		_txt(Vector2(x, cue_y), "SINK %.0f" % float(gd["sink_target"]), 22, GREEN if ok else AMBER)
	if gd.has("flash") and fmod(_t, 0.8) < 0.5:
		_txt(Vector2(0, size.y * 0.3), str(gd["flash"]), 64, RED, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if gd.has("entry_aoa") and sim.density_now > 0.0:
		_txt(Vector2(x + 200, cue_y), "AoA %d° / %d°" % [int(rad_to_deg(sim.aoa)), int(gd["entry_aoa"])], 22, GREEN if absf(rad_to_deg(sim.aoa) - float(gd["entry_aoa"])) < 6.0 else AMBER)
	if sim.hull_temp > 900.0:
		_txt(Vector2(x, y - 76), "HULL %d K" % int(sim.hull_temp), 26, RED if sim.hull_temp > 1450.0 else AMBER)


## Minimal ops HUD: mode + target in the lower-right corner, RCS fuel bar, and the
## docking reticle when it matters. Power / systems detail is on the SYSTEMS page.
func _draw_ops_panel(g: Node, sim: ShipSim) -> void:
	var x := size.x - 420.0
	var y := size.y - 250.0
	var dim := Color(CYAN, 0.65)
	_txt(Vector2(x, y), "MODE " + Game.OPS_MODES[g.ops_mode], 26, Color(CYAN, HUD_A))
	var tgt: Dictionary = g.current_target()
	if not tgt.is_empty():
		var ts: Array = g.target_state()
		var rel: Vector3 = (ts[0] as BigVec).rel(sim.pos)
		var rv: Vector3 = sim.vel - (ts[1] as Vector3)
		var closing := -rv.dot(rel.normalized())
		_txt(Vector2(x, y + 40), str(tgt["name"]), 22, Color(PURPLE, HUD_A))
		_txt(Vector2(x, y + 78), "%s  %+.1f m/s" % [_fmt_dist(rel.length()), closing], 28, Color(WHITE, HUD_A))
	if g.ops_mode == 1:
		_txt(Vector2(x, y + 114), "ARM %s  BEAM %s" % ["OUT" if g.arm_extend > 0.95 else ("MOVING" if g.arm_extend > 0.0 else ("DOORS!" if g.cargo_door < 0.95 else "STOWED")), "ON" if g.beam_on else "OFF"], 20, dim)
	if InputHub.on("jump_arm") or g.jump_charge > 0.0:
		_txt(Vector2(x, y + 146), "JUMP " + ("READY" if g.jump_charge >= 100.0 else "%d%%" % int(g.jump_charge)), 22, Color(PURPLE, HUD_A))
	var bx := size.x - 34.0
	var by := size.y - 300.0
	_bar(Vector2(bx, by), Vector2(10, 180), sim.mono / sim.mono_max, CYAN)
	_txt(Vector2(bx - 6, by + 204), "RCS", 16, dim)
	if not g.power_ok and fmod(_t, 1.0) < 0.6:
		_txt(Vector2(x, y - 40), "POWER LOW", 26, RED)
	var gd: Dictionary = g.mission.guidance if g.mission else {}
	if gd.has("docking"):
		var info: Dictionary = gd["docking"]
		var cc := Vector2(size.x * 0.3, size.y * 0.62)
		var lat: Vector2 = info["lat"]
		var r := 120.0
		draw_arc(cc, r, 0, TAU, 64, Color(CYAN, 0.45), 1.5)
		draw_arc(cc, r * 0.2, 0, TAU, 32, Color(GREEN, 0.6), 1.5)
		draw_line(cc - Vector2(r, 0), cc + Vector2(r, 0), Color(CYAN, 0.25), 1.0)
		draw_line(cc - Vector2(0, r), cc + Vector2(0, r), Color(CYAN, 0.25), 1.0)
		var scale_m := 10.0 if float(info["range"]) > 30.0 else 2.0
		var dot := cc + Vector2(lat.x, -lat.y) / scale_m * r
		dot = cc + (dot - cc).limit_length(r)
		var ok := lat.length() < 0.4 and float(info["angle"]) < 3.0
		draw_circle(dot, 10.0, Color(GREEN if ok else AMBER, 0.85))
		var lv: Vector2 = info["lat_vel"]
		draw_line(dot, dot + Vector2(lv.x, -lv.y) * 120.0, Color(WHITE, 0.8), 2.0)
		var cl: float = info["closing"]
		_txt(cc + Vector2(-r, r + 36), "%.1f m   %.2f m/s" % [float(info["range"]), cl], 24, GREEN if cl < 0.3 else (AMBER if cl < 0.6 else RED))
	if gd.has("pad_dist"):
		_txt(Vector2(x, y + 178), "BEACON %s" % _fmt_dist(float(gd["pad_dist"])), 22, Color(GREEN, HUD_A))
	if gd.has("blackout") and gd["blackout"] and fmod(_t, 1.0) < 0.6:
		_txt(Vector2(0, size.y * 0.25), "COMMS BLACKOUT", 40, Color(AMBER, 0.85), HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw_banner(g: Node) -> void:
	if g.mission == null:
		return
	var o: Dictionary = g.mission.current_objective()
	var role: String = str(o.get("role", "ALL"))
	var mine := role == "BOTH" or role == "ALL" or (side < 0 and role == "PILOT") or (side > 0 and role == "OPS")
	if g.state == Game.State.ACTIVE and mine:
		_txt(Vector2(0, 46), str(o.get("text", "")), 26, Color(GREEN, HUD_A), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if _callout_t > 0.0 and _callout != "":
		var a := clampf(_callout_t, 0.0, 1.0) * 0.9
		var cc := RED if _callout_pri >= 2 else (AMBER if _callout_pri == 1 else WHITE)
		cc.a = a
		_txt(Vector2(0, size.y - 60), _callout, 28, cc, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw_caution(g: Node) -> void:
	if g.warnings.is_empty():
		return
	var blink: bool = g.caution_active and not g.caution_silenced and fmod(_t, 0.6) < 0.3
	var y := 76.0
	var x := size.x * 0.5 - 200.0
	draw_rect(Rect2(x, y, 400, 36), Color(1, 0.15, 0.1, 0.75) if blink else Color(0.4, 0.05, 0.05, 0.45))
	_txt(Vector2(x, y + 27), "MASTER CAUTION", 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 400)
	var i := 0
	for k in g.warnings:
		_txt(Vector2(x - 100, y + 66 + i * 28), str(g.warnings[k]), 22, Color(AMBER, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 600)
		i += 1
		if i >= 3:
			break


func _draw_state_overlay(g: Node) -> void:
	match g.state:
		Game.State.BRIEFING:
			draw_rect(Rect2(0, size.y * 0.66, size.x, 150), Color(0, 0, 0, 0.3))
			_txt(Vector2(0, size.y * 0.66 + 62), g.mission.title + " - " + g.mission.tagline, 48, CYAN, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			var need: bool = g.mission.requires_checklist and g.checklist_progress < Game.CHECKLIST.size()
			var msg: String = ("Overhead checklist: flip %s next" % Game.CHECKLIST_NAMES[g.checklist_progress]) if need else "Commander: press START!"
			_txt(Vector2(0, size.y * 0.66 + 116), msg, 30, AMBER if need else GREEN, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Game.State.PAUSED:
			_txt(Vector2(0, size.y * 0.5), "PAUSED", 90, AMBER, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Game.State.COMPLETE:
			draw_rect(Rect2(0, size.y * 0.3, size.x, 330), Color(0, 0.05, 0.02, 0.4))
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
