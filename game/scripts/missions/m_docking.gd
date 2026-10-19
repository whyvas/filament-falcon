extends Mission
## (b) Rendezvous and docking. Ops flies RCS translation; Pilot holds attitude.

const PORT := Vector3(0, 0, 21.0)       # docking port in station frame (faces +Z)
const SHIP_PORT := Vector3(0, 0, -7.8)  # ship docking port (nose)

var st: Dictionary
var soft_captured := false
var hard_docked := false
var _align_t := 0.0
var _contact_speed := 0.0
var _contact_offset := 0.0
var _bounces := 0
var _capture_offset := Vector3.ZERO
var start_range := 205.0                # subclasses (REAL ISS) start further out


func setup() -> void:
	id = "docking"
	title = "SPACE HUG"
	tagline = "Rendezvous & docking"
	briefing = "The space station needs supplies. The Falcon is parked just in front of it. Line up perfectly and glide in slower than a snail to dock."
	pilot_job = "Keep the Falcon pointed straight at the docking port. Use HOLD assist to lock the nose, and fix small drifts with the stick."
	ops_job = "Lock the target, then fly the Falcon sideways, up, down and forward with the RCS stick. Centre the crosshair on the port and creep in. Flip DOCK CLAMP when we touch."
	start_callout = "Docking mission start. Station is 200 metres ahead."
	star_thresholds = [1100, 1500]
	objectives = [
		{"text": "SENSORS on, then NAV TARGET until it says STATION PORT", "role": "OPS"},
		{"text": "Line up the nose on the port (HOLD assist helps)", "role": "PILOT"},
		{"text": "Fly RCS to the port: centre the cross, slower than 0.3 m/s at the end", "role": "OPS"},
		{"text": "Flip DOCK CLAMP to lock on!", "role": "OPS"},
	]
	game.sun_dir = Vector3(0.75, 0.55, -0.35).normalized()   # high sun: lit station, daylit Earth below
	st = game.station
	# Station at phase 0 moves along -Z; its port faces world -Z (ahead of it along the orbit).
	st["phase0"] = float(st.get("phase_set", 0.0))
	game._place_entity(st)
	var port_w := port_world()
	var normal := port_normal()
	var p: BigVec = port_w.copy()
	var lateral := Vector3(6.0, -3.5, 0.0)
	p.add(normal * start_range + lateral)
	sim.pos.set_from(p)
	sim.vel = frame_vel(sim.pos.rel(st["pos"]))   # co-moving with the station's rotating LVLH frame
	var aim := Basis(Vector3.UP, deg_to_rad(5.0)) * Basis(Vector3.RIGHT, deg_to_rad(-3.0))
	sim.basis = aim * ship_basis(-normal, (st["basis"] as Basis).y)
	sim.fuel = 2000.0
	game.nav_targets = [{"name": "STATION", "entity": st}, {"name": "STATION PORT", "entity": st, "port": PORT}, {"name": "MOON", "body": moon()}]
	game.nav_vector = "TARGET"


func port_world() -> BigVec:
	var p: BigVec = (st["pos"] as BigVec).copy()
	p.add((st["basis"] as Basis) * PORT)
	return p


## Velocity of a point fixed in the station's LVLH frame (the frame turns once per orbit), at
## offset `rel` from the station centre. On the R-bar this matters: 205 m out it's ~0.8 m/s.
func frame_vel(rel: Vector3) -> Vector3:
	var r := (st["pos"] as BigVec).rel(earth().pos)
	var v: Vector3 = st["vel"]
	var w := r.cross(v) / maxf(r.length_squared(), 1.0)
	return v + w.cross(rel)


func port_normal() -> Vector3:
	return ((st["basis"] as Basis) * Vector3(0, 0, 1)).normalized()


## Docking geometry for the HUD: {range, lateral (Vector2 m), closing (m/s), angle (deg), rel_vel}
func docking_info() -> Dictionary:
	var n := port_normal()
	var ship_port: BigVec = sim.pos.copy()
	ship_port.add(sim.basis * SHIP_PORT)
	var d := ship_port.rel(port_world())       # port -> ship port
	var along := d.dot(n)
	var lat := d - n * along
	var sb: Basis = st["basis"]
	var rv: Vector3 = sim.vel - frame_vel(sim.pos.rel(st["pos"]))
	var ang := rad_to_deg(sim.forward().angle_to(-n))
	return {"range": along, "lat": Vector2(lat.dot(sb.x), lat.dot(sb.y)), "closing": -rv.dot(n), "angle": ang, "rel_vel": rv,
		"lat_vel": Vector2((rv - n * rv.dot(n)).dot(sb.x), (rv - n * rv.dot(n)).dot(sb.y))}


func update(dt: float) -> void:
	var info := docking_info()
	guidance["docking"] = info
	match step:
		0:
			var tgt: Dictionary = game.current_target()
			if tgt.get("name", "") == "STATION PORT" and game.powered.get("sensors", false):
				advance("Target locked: station port.")
		1:
			if objective_done_after(2.0, dt, float(info["angle"]) < 3.0):
				advance("Aligned! Ops, take us in.")
		2:
			pass
		3:
			pass


func physics(_h: float) -> void:
	if hard_docked or soft_captured:
		_hold_to_port()
		return
	var info := docking_info()
	var rng: float = info["range"]
	var lat: Vector2 = info["lat"]
	if rng < 0.35 and rng > -3.0 and lat.length() < 2.5:
		var closing: float = info["closing"]
		var ang: float = info["angle"]
		if lat.length() < 0.4 and ang < 6.0 and closing < 0.35:
			_soft_capture(closing, lat.length())
		elif closing > 0.0:
			_bounce(closing)
	# Keep-out sphere around the station core (except the approach corridor)
	var rel := rel_to_entity(st)
	if rel.length() < 24.0 and (rng > 2.0 or lat.length() > 3.0):
		var outward := -rel.normalized()
		var rv: Vector3 = sim.vel - frame_vel(-rel)
		if rv.dot(outward) < 0.0:
			_bounce(-rv.dot(outward))


func _bounce(speed: float) -> void:
	var n := port_normal()
	var fv := frame_vel(sim.pos.rel(st["pos"]))
	var rv: Vector3 = sim.vel - fv
	sim.vel = fv + rv - n * rv.dot(n) * 1.4 + n * 0.05
	_bounces += 1
	Sfx.clunk()
	game.camera_shake = 0.4
	if speed > 0.6:
		game._damage(speed * 6.0)
	Voice.say("Bounced off! Too fast or not lined up. Back up and try again.", 1)


func _soft_capture(closing: float, offset: float) -> void:
	soft_captured = true
	_contact_speed = closing
	_contact_offset = offset
	Sfx.clunk()
	game.camera_shake = 0.3
	sim.clamped = true
	_hold_to_port()
	if step == 2:
		advance("Contact! Soft capture! Ops, DOCK CLAMP now!")
	else:
		step = 3
		game.objective_changed.emit()
		Voice.say("Contact! Ops, DOCK CLAMP now!", 1)


func _hold_to_port() -> void:
	var n := port_normal()
	var a := port_world().copy()
	a.add(n * 7.8)
	sim.anchor_pos = a
	sim.anchor_vel = frame_vel(a.rel(st["pos"]))
	sim.basis = sim.basis.slerp(ship_basis(-n, sim.basis.y), 0.05).orthonormalized()


func on_dock_clamp() -> void:
	if not soft_captured:
		Voice.say("Not touching yet. Clamp after contact.")
		return
	if hard_docked:
		return
	hard_docked = true
	Sfx.clunk()
	Voice.say("Hard dock! Welcome aboard the station!", 1)
	if step == 3:
		advance()


func cheat_advance() -> void:
	match step:
		0:
			game.set_nav_target_by_name("STATION PORT")
			advance()
		1:
			advance()
		2:
			_soft_capture(0.1, 0.05)
		3:
			on_dock_clamp()


func final_score() -> void:
	super.final_score()
	game.add_score("Contact speed %.2f m/s" % _contact_speed, clampi(int(400.0 - _contact_speed * 1000.0), 50, 400))
	game.add_score("Centre offset %.2f m" % _contact_offset, clampi(int(300.0 - _contact_offset * 700.0), 30, 300))
	if _bounces > 0:
		game.add_score("Bounces x%d" % _bounces, -60 * _bounces)
	game.add_score("RCS left %d%%" % int(sim.mono / sim.mono_max * 100.0), int(sim.mono / sim.mono_max * 200.0))
