extends "res://scripts/missions/m_docking.gd"
## REAL ISS: the station flies where the real ISS is right now (CelesTrak TLE fetched on this
## PC by tools/fetch_assets.sh / run.sh, built-in elements as the fallback): same ground point,
## same 51.6 deg orbit plane and direction over the textured Earth. Then rendezvous + docking.

var iss := {}


func setup() -> void:
	iss = Geo.iss_now()
	var p: Vector3 = Geo.game_from_geo() * (iss["pos"] as Vector3)
	var v: Vector3 = (Geo.game_from_geo() * (iss["vel_dir"] as Vector3)).slide(p).normalized()
	var st0: Dictionary = game.station
	st0["plane"] = Basis(p, p.cross(v).normalized(), -v)     # rails phase 0 = the ISS ground point
	st0["name"] = "ISS"
	start_range = 420.0 if game.difficulty() != "easy" else 260.0
	super.setup()
	id = "iss"
	title = "REAL ISS"
	tagline = "Dock with the real space station"
	briefing = "Look down: the space station is flying over %s right now, for real! We catch up with it and dock, just like the astronauts. Slow and gentle wins." % _where()
	start_callout = "Rendezvous with the International Space Station. Range %d metres." % int(start_range)
	game.nav_targets[0]["name"] = "ISS"
	star_thresholds = [1100, 1500]


func _where() -> String:
	var la := float(iss["lat"])
	var lo := float(iss["lon"])
	return "%.0f°%s %.0f°%s" % [absf(la), "N" if la >= 0.0 else "S", absf(lo), "E" if lo >= 0.0 else "W"]


func commander_actions() -> Array:
	return [["SAY WHERE THE ISS IS", "where"], ["THRUSTER GLITCH (drift)", "drift"]]


func on_commander(cid: String) -> void:
	match cid:
		"where":
			Voice.say("The space station is over %s, %d kilometres up. Elements %s, %d hours old." % [_where(), int(iss["alt_km"]), iss["src"], int(iss["age_h"])], 1)
		"drift":
			sim.vel += sim.basis * Vector3(0.15, -0.1, 0.0)
			Voice.say("Thruster glitch! Ops, steady us with the RCS.", 2)
