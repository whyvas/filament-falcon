extends Mission
## (c) Lunar landing: braking burn, scanner finds the beacon, powered descent, touchdown.

var pad: Dictionary
var _touch_v := 0.0
var _touch_dist := 0.0


func setup() -> void:
	id = "lunar"
	title = "EAGLE EYE"
	tagline = "Lunar landing"
	briefing = "We are skimming over the Moon at 9 km. Find the landing beacon, slow down, and land as gently as a feather. No air here, so only the engine can slow us down."
	pilot_job = "Use PROGRADE assist (the NAV vector is set to RETROGRADE) and burn to slow down. Then hover down with the throttle, GEAR DOWN, and touch down slower than 3 m/s."
	ops_job = "Ping the SCANNER to find the beacon and lock it as NAV TARGET. Near the ground, slide the Falcon over the beacon with the RCS stick."
	start_callout = "Lunar descent. Altitude 9 kilometres."
	star_thresholds = [1100, 1600]
	objectives = [
		{"text": "SENSORS on, SCANNER PING to find the landing beacon", "role": "OPS"},
		{"text": "Braking burn: PROGRADE assist (RETROGRADE), ENGINE ARM, IGNITION, slow below 60 m/s", "role": "PILOT"},
		{"text": "Descend: keep the sink rate in the green, below 300 m", "role": "PILOT"},
		{"text": "GEAR DOWN, hover down gently. Ops: RCS over the beacon", "role": "BOTH"},
	]
	var m := moon()
	pad = game.entities_of("lunar_pad")[0]
	pad["revealed"] = false
	var site: Vector3 = game.lunar_site_dir
	var east := CelestialBody.east_at(site)
	var a := 10000.0 / m.radius     # ~10 km uprange: braking ends near the beacon
	var dir := (site * cos(a) - east * sin(a)).normalized()
	var r := m.radius + 9000.0
	sim.pos.set_xyz(m.pos.x() + dir.x * r, m.pos.y() + dir.y * r, m.pos.z() + dir.z * r)
	var e2 := CelestialBody.east_at(dir)
	sim.vel = m.vel + e2 * 310.0 - dir * 12.0
	sim.basis = ship_basis(-e2 + dir * 0.15, dir)
	sim.fuel = 6500.0
	game.sun_dir = (east * 0.55 + site * 0.5 + Vector3.UP * 0.35).normalized()
	game.nav_targets = [{"name": "LANDING SITE", "entity": pad}, {"name": "EARTH", "body": earth()}]
	game.nav_vector = "RETROGRADE"
	InputHub.set_group("fa", ShipSim.FA.NAV)


func update(dt: float) -> void:
	var rel := rel_to_entity(pad)
	var horiz := rel - sim.up_dir * rel.dot(sim.up_dir)
	guidance["sink_target"] = -maxf(2.0, sim.agl / 14.0)
	guidance["pad_dist"] = horiz.length()
	match step:
		1:
			if sim.hspeed < 60.0:
				advance("Braking burn complete. Start the descent.")
		2:
			if sim.agl < 300.0:
				advance("300 metres. Gear down! Ops, line us up on the beacon.")
		3:
			if sim.landed and sim.contact_points > 0:
				_touch_dist = horiz.length()
				if not sim.gear_down:
					return
				advance("Touchdown! The Falcon has landed!")
	if sim.touching and _touch_v == 0.0:
		_touch_v = sim.last_impact


func on_scanner_ping() -> void:
	if not pad["revealed"]:
		pad["revealed"] = true
		game.set_nav_target_by_name("LANDING SITE")
		if step == 0:
			advance("Beacon found! Landing site locked.")


func cheat_advance() -> void:
	match step:
		0:
			on_scanner_ping()
		3:
			sim.gear_down = true
			_touch_v = 1.2
			advance()
		_:
			advance()


func final_score() -> void:
	super.final_score()
	game.add_score("Touchdown %.1f m/s" % _touch_v, clampi(int(400.0 - _touch_v * 100.0), 0, 400))
	game.add_score("Distance to beacon %d m" % int(_touch_dist), clampi(int(400.0 - _touch_dist * 2.0), 0, 400))
	game.add_score("Fuel left %d kg" % int(sim.fuel), int(sim.fuel / 15.0))
