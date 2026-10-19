extends Mission
## (f) Free-flight sandbox. Everything works; the jump drive hops between destinations.
## The Commander ends the flight from the MISSION page.

const DESTS := ["STATION", "MOON ORBIT", "ASTEROID FIELD", "RUNWAY APPROACH", "LAUNCH PAD", "FREDERICTON"]
var dest_index := 0
var visited := {}


func setup() -> void:
	id = "sandbox"
	title = "FREE FLIGHT"
	tagline = "Sandbox"
	briefing = "No rules, just flying! Visit the station, skim the Moon, explore the asteroid field, glide to the runway, or hop off the launch pad. The jump drive takes you to the next place."
	pilot_job = "Fly anything you like. Try ASSIST OFF to feel real space physics: nothing slows you down!"
	ops_job = "Run the systems, play with the arm and scanner, and arm + engage the JUMP drive to travel to the next place."
	start_callout = "Free flight. Have fun, crew!"
	star_thresholds = [700, 1200]
	objectives = [
		{"text": "Free flight! Ops: JUMP to visit places. Commander: END FLIGHT on the MISSION page", "role": "ALL"},
	]
	laser_enabled = true
	go_to(0)


func go_to_name(nm: String) -> void:
	go_to(maxi(0, DESTS.find(nm)))


func go_to(i: int) -> void:
	dest_index = i % DESTS.size()
	var nm: String = DESTS[dest_index]
	visited[nm] = true
	sim.ang_vel = Vector3.ZERO
	sim.clamped = false
	sim.booster_attached = false
	match nm:
		"STATION":
			game.sun_dir = Vector3(0.5, 0.55, 0.65).normalized()
			var st: Dictionary = game.station
			var p: BigVec = (st["pos"] as BigVec).copy()
			var n: Vector3 = (st["basis"] as Basis) * Vector3(0, 0, 1)
			p.add(n * 400.0 + Vector3(30, 20, 0))
			sim.pos.set_from(p)
			sim.vel = st["vel"]
			sim.basis = ship_basis(-n, (st["basis"] as Basis).y)
			game.nav_targets = [{"name": "STATION", "entity": st}, {"name": "STATION PORT", "entity": st, "port": Vector3(0, 0, 21)}, {"name": "MOON", "body": moon()}]
		"MOON ORBIT":
			var m := moon()
			var site: Vector3 = game.lunar_site_dir
			var ph := atan2(-site.z, site.x) - 0.2
			set_circular_orbit(m, 15000.0, ph)
			var up := sim.pos.rel(m.pos).normalized()
			sim.basis = ship_basis(sim.vel - m.vel, up)
			game.nav_targets = [{"name": "LANDING SITE", "entity": game.entities_of("lunar_pad")[0]}, {"name": "EARTH", "body": earth()}]
			game.entities_of("lunar_pad")[0]["revealed"] = true
		"ASTEROID FIELD":
			var f: Dictionary = game.field
			var p2: BigVec = (f["pos"] as BigVec).copy()
			p2.add(Vector3(0, 300, 2600))
			sim.pos.set_from(p2)
			sim.vel = f["vel"]
			sim.basis = ship_basis(Vector3(0, -0.1, -1), sim.pos.rel(earth().pos).normalized())
			game.nav_targets = [{"name": "ASTEROID FIELD", "entity": f}, {"name": "EARTH", "body": earth()}]
		"RUNWAY APPROACH":
			var e := earth()
			var rd: Vector3 = game.runway_dir
			var east := CelestialBody.east_at(rd)
			var a := 45000.0 / e.radius
			var dir := (rd * cos(a) - east * sin(a)).normalized()
			var r := e.radius + 9000.0
			sim.pos.set_xyz(dir.x * r, dir.y * r, dir.z * r)
			var e2 := CelestialBody.east_at(dir)
			sim.vel = e2 * 260.0 - dir * 20.0
			sim.basis = ship_basis(e2 + dir * 0.05, dir)
			var rw: Dictionary = game.entities_of("runway")[0]
			rw["revealed"] = true
			game.nav_targets = [{"name": "RUNWAY", "entity": rw}]
		"FREDERICTON":
			# descent over downtown Fredericton NB and the Saint John River (OSM detail region,
			# tools/fetch_assets.sh); 8 km west, 4 km up, gliding east
			var e4 := earth()
			var fd := Geo.game_dir(45.962, -66.643)
			var east4 := CelestialBody.east_at(fd)
			var d4 := (fd * cos(8000.0 / e4.radius) - east4 * sin(8000.0 / e4.radius)).normalized()
			var r4 := e4.radius + e4.terrain_height(fd) + 4000.0
			sim.pos.set_xyz(d4.x * r4, d4.y * r4, d4.z * r4)
			var e5 := CelestialBody.east_at(d4)
			sim.vel = e5 * 120.0 - d4 * 15.0
			sim.basis = ship_basis(e5 - d4 * 0.15, d4)
			game.nav_targets = [{"name": "EARTH", "body": e4}]
		"LAUNCH PAD":
			var e3 := earth()
			var up2: Vector3 = game.pad_dir
			var east2 := CelestialBody.east_at(up2)
			var d2 := (up2 * cos(220.0 / e3.radius) + east2 * sin(220.0 / e3.radius)).normalized()
			var r2 := e3.radius + e3.terrain_height(d2) + 9.2
			sim.pos.set_xyz(d2.x * r2, d2.y * r2, d2.z * r2)
			sim.vel = Vector3.ZERO
			sim.basis = ship_basis(d2, -east2)
			sim.gear_down = true
			sim.gear_pos = 1.0
			InputHub.set_switch("gear", true)
			game.nav_targets = [{"name": "LAUNCH PAD", "entity": game.entities_of("pad")[0]}, {"name": "STATION", "entity": game.station}]
	sim.fuel = sim.fuel_max
	sim.mono = sim.mono_max
	game.nav_index = -1
	sim.pick_dominant()


func can_jump() -> bool:
	return true


func on_jump_complete() -> void:
	go_to(dest_index + 1)
	Voice.say("Arrived: " + DESTS[dest_index], 1)


func end_flight() -> void:
	advance()


func final_score() -> void:
	game.add_score("Flight time %d s" % int(game.mission_time), mini(int(game.mission_time), 600))
	game.add_score("Places visited x%d" % visited.size(), visited.size() * 150)
