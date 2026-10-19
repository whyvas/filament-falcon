extends Mission
## CITY LIGHTS: a night flight over Fredericton (the OSM detail region, its lit windows and the
## NASA night lights). Fly to the glow, ping the scanner to find HOME, circle and wave.

var city: Dictionary
var home: Dictionary
var found := false


func setup() -> void:
	id = "night_pass"
	title = "CITY LIGHTS"
	tagline = "Night flight over Fredericton"
	briefing = "It is night-time and the whole city is sparkling. We fly low over Fredericton and the river, find our very own house and wave hello!"
	pilot_job = "Fly toward the city lights (NAV TARGET: FREDERICTON). Keep the throttle up and stay above 600 m."
	ops_job = "Ping the SCANNER near town to find HOME, then tap WAVE on the card."
	start_callout = "Night pass over Fredericton. Look at all the lights!"
	requires_checklist = false
	star_thresholds = [900, 1300]
	objectives = [
		{"text": "Fly to the city lights (NAV TARGET: FREDERICTON)", "role": "PILOT"},
		{"text": "SCANNER PING to find our HOME!", "role": "OPS"},
		{"text": "Circle over home and WAVE (stay close for 20 s)", "role": "BOTH"},
	]
	var e := earth()
	var cd := Geo.game_dir(45.962, -66.643)
	var hd := Geo.game_dir(float(Settings.get_v("game", "home_lat")), float(Settings.get_v("game", "home_lon")))
	city = game.add_entity("marker", {"mode": "surface", "body": e, "dir": cd, "radius": 1500.0, "name": "FREDERICTON"})
	home = game.add_entity("marker", {"mode": "surface", "body": e, "dir": hd, "radius": 40.0, "name": "HOME", "revealed": false})
	var east := CelestialBody.east_at(cd)
	var d := (cd * cos(9000.0 / e.radius) - east * sin(9000.0 / e.radius)).normalized()
	var r := e.radius + e.terrain_height(cd) + (2200.0 if game.difficulty() != "hard" else 3500.0)
	sim.pos.set_xyz(d.x * r, d.y * r, d.z * r)
	var e2 := CelestialBody.east_at(d)
	sim.vel = e2 * 110.0
	sim.basis = ship_basis(e2 - d * 0.1, d)
	sim.fuel = sim.fuel_max
	game.sun_dir = (-cd * 0.9 + east * 0.3).normalized()     # local midnight-ish
	game.nav_targets = [{"name": "FREDERICTON", "entity": city}, {"name": "HOME", "entity": home}]
	game.nav_index = 0
	InputHub.set_group("fa", ShipSim.FA.STAB)


func _horiz(e: Dictionary) -> float:
	var rel := rel_to_entity(e)
	return (rel - sim.up_dir * rel.dot(sim.up_dir)).length()


func update(dt: float) -> void:
	guidance["home_dist"] = _horiz(home)
	match step:
		0:
			if _horiz(city) < 3000.0:
				advance("Here is the city! Ops, ping the scanner to find our house.")
		2:
			if objective_done_after(20.0, dt, _horiz(home) < 1500.0):
				advance("Good night, house! We will be home soon.")


func on_scanner_ping() -> void:
	if step == 1 and _horiz(home) < 6000.0 and not found:
		found = true
		home["revealed"] = true
		game.set_nav_target_by_name("HOME")
		set_card("WE FOUND HOME! 🏠", "Our house is right down there. Wave hello!", [["👋 WAVE", "wave", Color(1, 0.8, 0.3)]])
		advance("Found it! That's our house! Pilot, fly over it.")
	elif step == 1:
		Voice.say("Too far away. Fly closer to town and ping again.", 1)


func on_card(cid: String) -> void:
	if cid == "wave":
		game.wave(0)
		game.wave(1)
		Voice.say("Hello house!", 1)
		Sfx.chime()


func commander_actions() -> Array:
	return [["JUMP OVER TOWN", "town"], ["TURN THE LIGHTS ON (day)", "day"], ["BACK TO NIGHT", "night"]]


func on_commander(cid: String) -> void:
	var cd: Vector3 = city["dir"]
	match cid:
		"town":
			var e := earth()
			var r := e.radius + e.terrain_height(cd) + 1200.0
			sim.pos.set_xyz(cd.x * r, cd.y * r, cd.z * r)
		"day":
			game.sun_dir = (cd + Vector3(0.1, 0.2, 0.0)).normalized()
		"night":
			game.sun_dir = (-cd).normalized()


func cheat_advance() -> void:
	if step == 1:
		found = true
	advance()
