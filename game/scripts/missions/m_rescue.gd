extends Mission
## CATCH THE SPACEWALKER: a spacewalker's jetpack ran dry. Stop the spin, open the bay, put the
## arm out, then the EVA player (VR headset or the on-screen spacewalk) drifts and Ops catches
## them with the arm (the existing CANADARM RESCUE spacewalk).


func setup() -> void:
	id = "rescue"
	title = "CATCH THE SPACEWALKER"
	tagline = "Arm rescue"
	briefing = "Uh oh! Our friend outside ran out of jetpack gas and is floating away. Stop the ship from spinning, open the cargo doors, reach out with the robot arm and catch them!"
	pilot_job = "Turn HOLD assist on so the ship stops spinning, and keep it still."
	ops_job = "CARGO DOORS open, then ARM mode and push the arm out. Catch the spacewalker with the arm trigger."
	start_callout = "Spacewalker adrift! Let's go get them."
	requires_checklist = false
	star_thresholds = [900, 1300]
	objectives = [
		{"text": "HOLD assist: stop the spin", "role": "PILOT"},
		{"text": "CARGO DOORS open and ARM out", "role": "OPS"},
		{"text": "Catch the spacewalker with the arm!", "role": "OPS"},
	]
	set_circular_orbit(earth(), 150000.0, deg_to_rad(80.0))
	sim.basis = ship_basis(sim.vel, sim.pos.rel(earth().pos))
	sim.ang_vel = Vector3(0.02, 0.035, 0.0) * (1.5 if game.difficulty() == "hard" else 1.0)
	game.nav_targets = [{"name": "EARTH", "body": earth()}]


func update(dt: float) -> void:
	match step:
		0:
			if objective_done_after(2.0, dt, sim.ang_vel.length() < deg_to_rad(0.4)):
				advance("Spin stopped. Ops, open the doors!")
		1:
			if game.cargo_door > 0.95 and game.arm_extend > 0.9:
				advance("Arm is out. Here comes the spacewalker!")
		2:
			if not eva_inserted and not Eva.active and "rescue" in Eva.available():
				start_eva_step("rescue")
			elif not eva_inserted:
				guidance["flash"] = "ENGINE OFF"


func commander_actions() -> Array:
	return [["SPIN AGAIN", "spin"], ["START THE SPACEWALK NOW", "eva"]]


func on_commander(cid: String) -> void:
	match cid:
		"spin":
			sim.ang_vel += Vector3(0.0, 0.03, 0.02)
		"eva":
			if step == 2 and not Eva.active:
				start_eva_step("rescue")
