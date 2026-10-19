extends Mission
## GROUND CREW: a 4th person is MISSION CONTROL on a phone / tablet (GroundLink web page).
## Mission Control gives the GO, the Pilot burns, Ops sends a photo down, Mission Control
## confirms it and says well done.

var burn_t := 0.0
var link: GroundLink


func setup() -> void:
	id = "ground_crew"
	title = "GROUND CREW"
	tagline = "Mission Control joins on a phone"
	briefing = "Today someone is MISSION CONTROL on the ground, with a phone! They watch our ship and tell us when we are GO. Listen to Mission Control!"
	pilot_job = "Wait for Mission Control's GO, then burn the engine for 10 seconds."
	ops_job = "SCANNER PING to take a photo of Earth and send it to Mission Control."
	start_callout = "Mission Control, Falcon. Radio check!"
	requires_checklist = false
	star_thresholds = [900, 1300]
	objectives = [
		{"text": "Mission Control (phone): press GO!", "role": "MC"},
		{"text": "Engine burn: ENGINE ARM, IGNITION, 10 seconds", "role": "PILOT"},
		{"text": "SCANNER PING: send a photo to Mission Control", "role": "OPS"},
		{"text": "Mission Control: press PHOTO RECEIVED", "role": "MC"},
	]
	set_circular_orbit(earth(), 150000.0, deg_to_rad(100.0))
	sim.basis = ship_basis(sim.vel, sim.pos.rel(earth().pos))
	game.nav_targets = [{"name": "EARTH", "body": earth()}, {"name": "MOON", "body": moon()}]
	link = GroundLink.get_link()
	set_card("WAITING FOR MISSION CONTROL", "Ask the grown-up on the phone to press GO!\n" + " · ".join(link.urls()))


func update(dt: float) -> void:
	if step == 1:
		if sim.engine_on and sim.throttle > 0.05:
			burn_t += dt
		guidance["flash"] = "BURN %d / 10 s" % int(burn_t)
		if burn_t >= 10.0:
			guidance.erase("flash")
			set_card("BURN COMPLETE", "Ops: press SCANNER PING to take a photo!")
			advance("Burn complete. Ops, take a photo for Mission Control!")


func on_ground(cmd: String) -> bool:
	if cmd == "go" and step == 0 and game.state == game.State.ACTIVE:
		set_card("WE ARE GO! ✅", "Pilot: ENGINE ARM, IGNITION and burn for 10 seconds.")
		advance("Mission Control says: you are GO! Pilot, light the engine!")
		return true
	if cmd == "photo" and step == 3:
		set_card("PHOTO RECEIVED 📷", "Mission Control loves our photo! Mission complete!")
		advance("Mission Control: photo received. Beautiful! Well done, crew!")
		return true
	return false


func on_scanner_ping() -> void:
	if step == 2:
		Sfx.tone(1800.0, 0.4, 0.2, "sine", 600.0)
		set_card("PHOTO SENT 📡", "Waiting for Mission Control to say PHOTO RECEIVED...")
		advance("Photo sent to Mission Control!")


func commander_actions() -> Array:
	return [["PRETEND: MC SAYS GO", "go"], ["PRETEND: PHOTO RECEIVED", "photo"]]


func on_commander(cid: String) -> void:
	on_ground(cid)


func cheat_advance() -> void:
	match step:
		0:
			on_ground("go")
		1:
			burn_t = 10.0
			update(0.0)
		2:
			on_scanner_ping()
		3:
			on_ground("photo")


func final_score() -> void:
	super.final_score()
	game.add_score("Mission Control presses x%d" % link.presses, mini(link.presses * 40, 300))
