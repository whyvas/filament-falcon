extends Mission
## (e) Reentry and runway landing: hold entry attitude through the plasma, find the runway
## beacon after blackout, glide through the approach boxes, land and brake to a stop.

const START_ALT := 40000.0    # just after the deorbit burn: straight into the plasma
const START_SPEED := 1200.0
const START_GAMMA := -8.0
const GLIDE_DEG := 18.0       # steep outer glideslope (like the Space Shuttle), flare at the end
const GLIDE_AOA := 6.0
const AIM_X := -1450.0

var rw: Dictionary
var blackout := false
var _blackout_seen := false
var beacon_locked := false
var _touch_v := 0.0
var _touch_lat := 0.0
var _touch_x := 0.0
var _peak_temp := 0.0
var _touched := false


func setup() -> void:
	id = "reentry"
	title = "HOMECOMING"
	tagline = "Reentry & runway landing"
	briefing = "Time to come home! We hit the air at over a kilometre per second. The air squeezes and glows like fire around us. Hold the nose up, survive the heat, then glide like a giant paper plane onto the runway."
	pilot_job = "Hold the nose up on the ENTRY bracket (PROGRADE assist with NAV GUIDANCE does it for you). When we slow down, fly through the green boxes to the runway, GEAR DOWN, land, and AIRBRAKE to stop."
	ops_job = "SHIELDS on before the heat! After the radio blackout, lock NAV TARGET: RUNWAY and ping the SCANNER to find the landing beacon. Call out the speed and height for the pilot."
	start_callout = "Deorbit burn complete. Forty kilometres. Here comes the heat!"
	star_thresholds = [1200, 1700]
	objectives = [
		{"text": "SHIELDS on before the heat!", "role": "OPS"},
		{"text": "Hold the nose up on the ENTRY bracket until below 650 m/s", "role": "PILOT"},
		{"text": "NAV TARGET: RUNWAY, then SCANNER PING to lock the beacon", "role": "OPS"},
		{"text": "Glide through the boxes, GEAR DOWN, touch down on the runway", "role": "PILOT"},
		{"text": "AIRBRAKE on and roll to a stop", "role": "PILOT"},
	]
	rw = game.entities_of("runway")[0]
	rw["revealed"] = true          # selectable as NAV TARGET; the SCANNER PING locks its beacon
	game.sun_dir = Vector3(-0.2, 0.55, -0.81).normalized()
	_place_start()
	game.nav_targets = [{"name": "RUNWAY", "entity": rw}, {"name": "STATION", "entity": game.station}]
	game.nav_vector = "GUIDANCE"
	sim.fuel = 900.0


## Entry attitude schedule: belly-first (40 deg) through the heat, a high-drag 25 deg phase to
## bleed speed quickly, then a 9 deg glide for the approach.
static func entry_aoa(airspeed: float) -> float:
	if airspeed > 400.0:
		return 40.0
	if airspeed > 150.0:
		return 30.0
	return GLIDE_AOA


static func nominal_dir(s: ShipSim) -> Vector3:
	var sv := s.surface_vel
	if sv.length() < 1.0:
		return Vector3.ZERO
	var vd := sv.normalized()
	var upp := s.up_dir.slide(vd).normalized()
	var a := deg_to_rad(entry_aoa(s.airspeed))
	return vd * cos(a) + upp * sin(a)


func guidance_dir() -> Vector3:
	if step >= 3 and beacon_locked and (approach_points()[0] as Vector3).length() < 16000.0:
		# close in: point down the glide path toward the next approach box
		var pts := approach_points()
		for p in pts:
			var v: Vector3 = p
			if v.dot(sim.surface_vel.normalized()) > 600.0:
				return v.normalized().slerp(nominal_dir(sim), 0.3)
	return nominal_dir(sim)


func _place_start() -> void:
	var e := earth()
	var up0 := Vector3(1, 0, 0)
	var east0 := CelestialBody.east_at(up0)
	var gm := deg_to_rad(START_GAMMA)
	var p := up0 * (e.radius + START_ALT)
	var v := (east0 * cos(gm) + up0 * sin(gm)) * START_SPEED
	var s := ShipSim.new()
	s.bodies = game.bodies
	s.pos.set_xyz(p.x, p.y, p.z)
	s.vel = v
	s.fuel = 900.0
	s.fa_mode = ShipSim.FA.NAV
	s.pick_dominant()
	s.basis = ship_basis(v, up0)
	var steps := 0
	while steps < 20000:
		s.nav_dir = nominal_dir(s)
		s.step(0.1)
		steps += 1
		if s.altitude < 5000.0:
			break
	var end_dir := s.up_dir
	var lam_e := atan2(-end_dir.z, end_dir.x)
	var rd: Vector3 = game.runway_dir
	var lam_r := atan2(-rd.z, rd.x)
	var delta := lam_r - lam_e - 14000.0 / e.radius
	var rot := Basis(Vector3.UP, delta)
	var p2 := rot * p
	sim.pos.set_xyz(p2.x, p2.y, p2.z)
	sim.vel = rot * v
	var up := p2.normalized()
	sim.basis = ship_basis(rot * v, up)
	sim.basis = Basis(sim.basis.x, deg_to_rad(40.0)) * sim.basis
	guidance["predicted_steps"] = steps


## Approach boxes relative to the ship (runway frame: x = along runway (east), y = up).
func approach_points() -> Array:
	var out := []
	var base: Vector3 = rel_to_entity(rw)
	var b: Basis = rw["basis"]
	var R: float = earth().radius
	for i in range(13):
		var d := 12000.0 - i * 1000.0
		var x := AIM_X - d
		var hgt := d * tan(deg_to_rad(GLIDE_DEG)) + 12.0 - (x * x) / (2.0 * R)
		out.append(base + b * Vector3(x, hgt, 0.0))
	return out


func runway_local() -> Vector3:
	var b: Basis = rw["basis"]
	return b.transposed() * (-rel_to_entity(rw))


func update(dt: float) -> void:
	_peak_temp = maxf(_peak_temp, sim.hull_temp)
	blackout = sim.heat_flux > 60000.0
	if blackout:
		_blackout_seen = true
	guidance["blackout"] = blackout
	guidance["entry_aoa"] = entry_aoa(sim.airspeed)
	match step:
		0:
			if game.powered.get("shields", false):
				advance("Shields up. Hold on tight!")
			elif sim.heat_flux > 30000.0:
				guidance["flash"] = "SHIELDS!"
		1:
			if sim.airspeed < 650.0:
				advance("Blackout over! Ops, find the runway!")
		2:
			pass
		3:
			if sim.touching and not _touched:
				_touched = true
				var loc := runway_local()
				_touch_v = absf(sim.vspeed)
				_touch_lat = absf(loc.z)
				_touch_x = loc.x
				var on_rw := absf(loc.z) < 30.0 and absf(loc.x) < 1800.0
				if not sim.gear_down:
					Voice.say("Belly landing! Ouch!", 2)
				advance("Touchdown! " + ("Right on the runway!" if on_rw else "We landed in the field!") + " Airbrake!")
		4:
			if sim.touching and sim.surface_vel.length() < 2.0:
				advance("Wheels stopped. Welcome home!")
	if step >= 3 and sim.agl < 1500.0 and not sim.gear_down:
		guidance["flash"] = "GEAR DOWN!"
	elif step >= 3:
		guidance.erase("flash")


func on_scanner_ping() -> void:
	var tgt: Dictionary = game.current_target()
	if blackout:
		Voice.say("No signal in the blackout. Wait for it to end.", 1)
		return
	if tgt.get("name", "") != "RUNWAY":
		Voice.say("Ops: select NAV TARGET RUNWAY first, then ping.", 1)
		rw["revealed"] = true
		return
	rw["revealed"] = true
	if not beacon_locked:
		beacon_locked = true
		if step == 2:
			advance("Runway beacon locked! Pilot, follow the green boxes.")
		else:
			Voice.say("Runway beacon locked.", 1)


func cheat_advance() -> void:
	match step:
		0:
			InputHub.set_switch("pwr_shields", true)
			advance()
		1:
			advance()
		2:
			game.set_nav_target_by_name("RUNWAY")
			beacon_locked = true
			rw["revealed"] = true
			advance()
		3:
			_touched = true
			advance()
		4:
			advance()


func final_score() -> void:
	super.final_score()
	var on_rw := _touch_lat < 30.0 and absf(_touch_x) < 1800.0
	game.add_score("Landed on the runway" if on_rw else "Field landing", 400 if on_rw else 100)
	game.add_score("Sink rate %.1f m/s" % _touch_v, clampi(int(300.0 - _touch_v * 60.0), 0, 300))
	game.add_score("Centreline %d m" % int(_touch_lat), clampi(int(200.0 - _touch_lat * 6.0), 0, 200))
	game.add_score("Peak hull %d K" % int(_peak_temp), 200 if _peak_temp < 1450.0 else 50)
