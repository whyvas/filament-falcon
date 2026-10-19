extends Mission
## HOUSTON, A PROBLEM: Apollo-13 style. The Commander (or a timer) fires a chain of faults; each
## one shows a big checklist card on the kids' touchscreen. Fix them all and get home safe.

const HELP := {
	"leak": ["OXYGEN TANK LEAK!", "1. Ops: tap SEAL LEAK below.\n2. Watch the cabin air go back to green.", [["🔧 SEAL LEAK", "seal", Color(0.4, 0.8, 1)]]],
	"power": ["POWER FAULT!", "1. Ops: REACTOR switch OFF.\n2. Count to two.\n3. REACTOR switch ON.", []],
	"fire": ["ENGINE FIRE!", "1. Pilot: ENGINE ARM OFF.\n2. Ops: tap FIRE OUT below!", [["🧯 FIRE OUT", "fire", Color(1, 0.35, 0.25)]]],
	"sensor": ["SENSORS GLITCH!", "1. Ops: SENSORS switch OFF.\n2. SENSORS switch ON again.", []],
}
var chain: Array = []
var armed := false
var _t := 0.0
var delay := 25.0


func setup() -> void:
	id = "emergency"
	title = "HOUSTON, A PROBLEM"
	tagline = "Apollo-style emergencies"
	briefing = "Bang! Something went wrong on our spaceship, just like Apollo 13. Stay calm, follow the big checklist cards and fix every problem. Real astronauts train for this!"
	pilot_job = "Hold the ship steady and do the PILOT steps on the cards (ENGINE ARM off for a fire)."
	ops_job = "Read the big card and press its buttons and switches in order."
	start_callout = "All systems normal... for now."
	star_thresholds = [1000, 1500]
	match game.difficulty():
		"easy":
			chain = ["leak", "fire"]
			delay = 30.0
		"hard":
			chain = ["leak", "power", "fire", "sensor"]
			delay = 15.0
		_:
			chain = ["leak", "power", "fire"]
	for k: String in chain:
		objectives.append({"text": "Fix the %s (follow the card)" % HELP[k][0].to_lower().trim_suffix("!"), "role": "BOTH"})
	set_circular_orbit(earth(), 140000.0, deg_to_rad(30.0))
	sim.basis = ship_basis(sim.vel, sim.pos.rel(earth().pos))
	game.nav_targets = [{"name": "EARTH", "body": earth()}, {"name": "MOON", "body": moon()}]
	set_card("ALL CALM", "Everything is fine. Look out of the window!\nIf an alarm rings, a card will tell you what to do.")


func _inject() -> void:
	var k: String = chain[step]
	armed = true
	game.inject_failure(k)
	var h: Array = HELP[k]
	set_card("⚠ " + h[0], h[1], h[2])


func update(dt: float) -> void:
	if step >= chain.size():
		return
	var k: String = chain[step]
	if not armed:
		_t += dt
		if _t > delay:
			_inject()
	elif not game.failures[k]:
		armed = false
		_t = 0.0
		set_card("FIXED! ✓", "Great job, crew! Houston says: well done." if step + 1 < chain.size() else "Every problem fixed. You saved the ship!")
		advance("Problem fixed! Great work.")


func on_card(cid: String) -> void:
	match cid:
		"seal":
			game.leak_sealed = true
		"fire":
			InputHub.pulse("fire_suppress", 3)


func commander_actions() -> Array:
	return [["▶ NEXT PROBLEM NOW", "next"], ["EXTRA: SENSOR GLITCH", "sensor"], ["CALM DOWN (fix all)", "fix"]]


func on_commander(cid: String) -> void:
	match cid:
		"next":
			if not armed and step < chain.size():
				_inject()
		"sensor":
			game.inject_failure("sensor")
		"fix":
			for k: String in game.failures:
				game.fix_failure(k)


func cheat_advance() -> void:
	if step >= chain.size():
		advance()
		return
	if not armed:
		_inject()
	game.fix_failure(chain[step])
	update(0.0)


func final_score() -> void:
	super.final_score()
	game.add_score("Problems solved x%d" % chain.size(), chain.size() * 150)
