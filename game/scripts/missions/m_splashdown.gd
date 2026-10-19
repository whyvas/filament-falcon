extends "res://scripts/missions/m_reentry.gd"
## SPLASHDOWN: capsule-style return. Plasma glow and radio blackout (from the reentry sim),
## cabin rumble on the camera + audio only (the seats' motion is hardwired, never software),
## then the DROGUE and MAIN parachutes on big card buttons and a gentle splash.

var drogue := false
var mains := false
var _rumble := 0.0
var _splash_v := 0.0
var _main_called := false


func setup() -> void:
	super.setup()
	id = "splashdown"
	title = "SPLASHDOWN"
	tagline = "Fire, parachutes and a splash"
	briefing = "We come home like Apollo: through the fire, the radio goes quiet, then pop pop go the parachutes and we land in the sea with a big SPLASH!"
	pilot_job = "Hold the nose up through the fire (PROGRADE assist + NAV GUIDANCE does it). After the chutes, just enjoy the ride."
	ops_job = "SHIELDS on! Then press the big DROGUE button, and later the big MAIN CHUTES button."
	start_callout = "Entry interface. Shields, crew!"
	star_thresholds = [1000, 1400]
	objectives = [
		{"text": "SHIELDS on before the heat!", "role": "OPS"},
		{"text": "Hold the nose up through the fire (radio blackout!)", "role": "PILOT"},
		{"text": "Press DROGUE CHUTE on the card", "role": "OPS"},
		{"text": "Press MAIN CHUTES on the card", "role": "OPS"},
		{"text": "Splashdown! Wait for the splash", "role": "ALL"},
	]
	game.nav_targets = [{"name": "EARTH", "body": earth()}]
	set_card("COMING HOME", "Shields on, hold on tight!")


func update(dt: float) -> void:
	blackout = sim.heat_flux > 60000.0
	guidance["blackout"] = blackout
	guidance["entry_aoa"] = entry_aoa(sim.airspeed)
	# cabin rumble: camera + audio only
	var q := clampf(sim.dyn_pressure / 30000.0, 0.0, 1.0)
	game.camera_shake = maxf(game.camera_shake, q * 0.7)
	_rumble -= dt
	if q > 0.1 and _rumble <= 0.0:
		_rumble = 0.9
		Sfx.tone(55.0 + q * 30.0, 1.0, 0.12 * q, "noise", 40.0)
	match step:
		0:
			if game.powered.get("shields", false):
				advance("Shields up. Here comes the fire!")
		1:
			if blackout:
				guidance["flash"] = "RADIO BLACKOUT"
			if sim.airspeed < 320.0 and not blackout:
				guidance.erase("flash")
				set_card("PARACHUTE TIME", "Press the big button!", [["🪂 DROGUE CHUTE", "drogue", Color(1, 0.6, 0.2)]])
				advance("Blackout over! Houston, we hear you! Ops, drogue chute!")
		3:
			if sim.agl < 3500.0 and not _main_called:
				_main_called = true
				Voice.say("Three kilometres. Ops, MAIN CHUTES now!", 1)
		4:
			if sim.touching:
				_splash_v = absf(sim.vspeed)
				Sfx.tone(180.0, 1.6, 0.4, "noise", 60.0)
				game.camera_shake = 1.0
				set_card("SPLASH! 🌊", "We are home! The boat is coming to pick us up.")
				advance("Splashdown! Welcome home, crew!")


func physics(h: float) -> void:
	if not drogue:
		return
	var tgt := 2.2 if mains else 60.0
	var sv := sim.surface_vel
	if sv.length() > tgt:
		sim.vel -= sv * (1.0 - tgt / sv.length()) * minf(1.0, h * (0.6 if mains else 0.35))
	sim.engine_on = false


func on_card(cid: String) -> void:
	match cid:
		"drogue":
			if step == 2:
				drogue = true
				game.camera_shake = 1.0
				Sfx.clunk()
				set_card("DROGUE OUT", "Wait... then press MAIN CHUTES!", [["🪂🪂🪂 MAIN CHUTES", "mains", Color(1, 0.85, 0.3)]])
				advance("Drogue chute out! Next, the big ones.")
		"mains":
			if step == 3:
				mains = true
				game.camera_shake = 1.0
				Sfx.clunk()
				set_card("THREE BIG CHUTES", "Floating down gently. Get ready for the splash!")
				advance("Main chutes! Three good chutes!")


func on_scanner_ping() -> void:
	pass


func commander_actions() -> Array:
	return [["SKIP TO CHUTES", "chutes"], ["BIG BUMP", "bump"]]


func on_commander(cid: String) -> void:
	match cid:
		"chutes":
			while step < 2:
				advance()
			on_card("drogue")
		"bump":
			game.camera_shake = 1.0
			Sfx.tone(70.0, 0.8, 0.35, "noise", 30.0)


func cheat_advance() -> void:
	match step:
		0:
			InputHub.set_switch("pwr_shields", true)
			advance()
		2:
			on_card("drogue")
		3:
			on_card("mains")
		_:
			advance()


func final_score() -> void:
	game.add_score("Mission complete", 600)
	game.add_score("Chutes", 200 if mains else 0)
	game.add_score("Splash %.1f m/s" % _splash_v, clampi(int(300.0 - _splash_v * 40.0), 0, 300))
