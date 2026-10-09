extends Mission
## (d) Asteroid field rescue & mining: scanner finds a stranded pod, Pilot threads the
## field, Ops captures it with the tractor beam; Pilot lasers crystal rocks, Ops collects
## the crystals; finally the jump drive takes everyone home.

const SHIP_R := 7.0
const CRYSTALS_NEEDED := 3

var fld: Dictionary
var pod: Dictionary
var rocks_c: Array = []
var towed: Array = []
var collected := 0
var hits := 0
var _near: Array = []
var _near_t := 0.0
var _laser_t := 0.0


func setup() -> void:
	id = "asteroids"
	title = "ROCK HOPPERS"
	tagline = "Asteroid rescue & mining"
	briefing = "A tiny escape pod is lost in the asteroid field! Find it, fly in carefully, and pull it aboard with the tractor beam. Then mine three glowing crystals and jump home."
	pilot_job = "Fly between the rocks to the pod without crashing (go slow!). Then point at the glowing crystal rocks and hold your TRIGGER to fire the mining laser."
	ops_job = "SHIELDS on! Ping the SCANNER to find the pod. Open the CARGO DOORS, choose ARM mode, aim with your stick and HOLD TRIGGER for the tractor beam. Last: arm and engage the JUMP drive."
	start_callout = "Entering the asteroid field. Shields up!"
	laser_enabled = true
	star_thresholds = [1200, 1700]
	objectives = [
		{"text": "SHIELDS + SENSORS on, then SCANNER PING to find the pod", "role": "OPS"},
		{"text": "Fly to the pod: stop within 40 m (slow near rocks!)", "role": "PILOT"},
		{"text": "CARGO DOORS open, mode ARM, HOLD TRIGGER to beam the pod in", "role": "OPS"},
		{"text": "Mine 3 crystals: Pilot lasers glowing rocks, Ops beams crystals in", "role": "BOTH"},
		{"text": "JUMP ARM, Pilot points at the JUMP marker, Ops ENGAGE!", "role": "BOTH"},
	]
	game.sun_dir = Vector3(-0.3, 0.35, 0.89).normalized()
	fld = game.field
	var start_off := Vector3(0, 40, 2300)
	pod = game.add_entity("pod", {"mode": "field", "parent": fld, "offset": Vector3(160, 25, 300), "radius": 2.5, "name": "ESCAPE POD", "revealed": false, "mass": 600.0})
	var cpos := [Vector3(-260, -30, 120), Vector3(320, 70, -80), Vector3(-60, 110, -320)]
	for i in cpos.size():
		rocks_c.append(game.add_entity("crystal_rock", {"mode": "field", "parent": fld, "offset": cpos[i], "radius": 13.0, "name": "CRYSTAL ROCK %d" % (i + 1), "heat": 0.0}))
	_clear_rocks_near([start_off, pod["offset"], cpos[0], cpos[1], cpos[2]], 90.0)
	var p: BigVec = (fld["pos"] as BigVec).copy()
	p.add(start_off)
	sim.pos.set_from(p)
	sim.vel = fld["vel"]
	sim.basis = ship_basis(Vector3(0.05, -0.02, -1), sim.pos.rel(earth().pos).normalized())
	sim.fuel = 4000.0
	sim.mono_max = 1500.0   # lots of small RCS hops in the field
	sim.mono = 1500.0
	game.nav_targets = [{"name": "ESCAPE POD", "entity": pod}, {"name": "CRYSTAL ROCK 1", "entity": rocks_c[0]}, {"name": "CRYSTAL ROCK 2", "entity": rocks_c[1]}, {"name": "CRYSTAL ROCK 3", "entity": rocks_c[2]}, {"name": "EARTH", "body": earth()}]
	game.nav_vector = "TGT RETRO"


func _clear_rocks_near(points: Array, dist: float) -> void:
	var pos: PackedVector3Array = fld["rock_pos"]
	var rad: PackedFloat32Array = fld["rock_r"]
	var np := PackedVector3Array()
	var nr := PackedFloat32Array()
	for i in pos.size():
		var ok := true
		for q in points:
			if pos[i].distance_to(q) < dist + rad[i]:
				ok = false
				break
		if ok:
			np.append(pos[i])
			nr.append(rad[i])
	fld["rock_pos"] = np
	fld["rock_r"] = nr


func jump_dir() -> Vector3:
	return earth().pos.rel(sim.pos).normalized()


func guidance_dir() -> Vector3:
	return jump_dir() if step == 4 else Vector3.ZERO


func update(dt: float) -> void:
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 0.25
		_near.clear()
		var frel: Vector3 = (fld["pos"] as BigVec).rel(sim.pos)
		var pos: PackedVector3Array = fld["rock_pos"]
		var rad: PackedFloat32Array = fld["rock_r"]
		for i in pos.size():
			if (frel + pos[i]).length() < 350.0 + rad[i]:
				_near.append(i)
	_update_laser(dt)
	_update_beam(dt)
	match step:
		1:
			var d := rel_to_entity(pod).length()
			var rv := rel_vel_entity(pod).length()
			guidance["pod_dist"] = d
			if d < 45.0 and rv < 2.0:
				advance("Pod in range! Ops, tractor beam!")
		3:
			if collected >= CRYSTALS_NEEDED:
				advance("Cargo full! Time to jump home!")
	if step == 4:
		guidance["jump_dir"] = jump_dir()


func physics(h: float) -> void:
	var frel: Vector3 = (fld["pos"] as BigVec).rel(sim.pos)
	var pos: PackedVector3Array = fld["rock_pos"]
	var rad: PackedFloat32Array = fld["rock_r"]
	for i in _near:
		if i >= pos.size():
			continue
		var rr: Vector3 = frel + pos[i]
		var d := rr.length()
		var lim: float = rad[i] * 0.85 + SHIP_R
		if d < lim and d > 0.01:
			var n := -rr / d
			var rv: Vector3 = sim.vel - (fld["vel"] as Vector3)
			var vn := rv.dot(n)
			sim.pos.add(n * (lim - d))
			if vn < 0.0:
				sim.vel -= n * vn * 1.5
				sim.ang_vel += sim.basis.x * randf_range(-0.2, 0.2)
				var dmg := absf(vn) * (1.2 if game.powered.get("shields", false) else 5.0)
				hits += 1
				Sfx.clunk()
				game.camera_shake = clampf(absf(vn) * 0.2, 0.2, 1.0)
				if absf(vn) > 0.7:
					game._damage(dmg)
	# towed objects follow the beam
	for e in towed.duplicate():
		var tip: Vector3 = game.arm_tip_rel()
		var tr: Vector3 = e["tow_rel"]
		tr = tr.move_toward(tip, h * 5.0)
		e["tow_rel"] = tr
		if tr.distance_to(tip) < 1.0:
			_capture(e)


func _update_laser(dt: float) -> void:
	guidance.erase("laser_dist")
	if not game.laser_on:
		return
	var fwd := sim.forward()
	var best := 900.0
	var hit: Dictionary = {}
	for e in rocks_c:
		if not game.entities.has(e):
			continue
		var rel := rel_to_entity(e)
		var tt := rel.dot(fwd)
		if tt <= 0.0 or tt > 900.0:
			continue
		if (rel - fwd * tt).length() < float(e["radius"]) and tt < best:
			best = tt
			hit = e
	guidance["laser_dist"] = best
	if hit.is_empty():
		return
	hit["heat"] = float(hit["heat"]) + dt
	if float(hit["heat"]) > 2.5:
		_shatter(hit)


func _shatter(rock: Dictionary) -> void:
	Sfx.explosion()
	game.camera_shake = 0.3
	game.game_event.emit("explosion", {"pos": (rock["pos"] as BigVec).copy(), "radius": 20.0, "color": Color(0.4, 1.0, 0.9)})
	var c: Dictionary = game.add_entity("crystal", {"mode": "field", "parent": fld, "offset": rock["offset"], "drift": Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)), "radius": 1.6, "name": "CRYSTAL", "mass": 150.0})
	c["ang_vel"] = Vector3(0.3, 0.5, 0.1)
	rocks_c.erase(rock)
	game.remove_entity(rock)
	game.nav_targets = game.nav_targets.filter(func(t: Dictionary) -> bool: return not (t.has("entity") and t["entity"] == rock))
	game.nav_targets.append({"name": "CRYSTAL", "entity": c})
	game.nav_index = game.nav_targets.size() - 1
	Voice.say("Rock cracked! Ops, grab the crystal!", 1)


func _update_beam(_dt: float) -> void:
	if not game.beam_on:
		# drop anything being towed
		for e in towed:
			e["mode"] = "field"
			e["offset"] = (e["pos"] as BigVec).rel(fld["pos"])
			e["drift"] = Vector3.ZERO
		towed.clear()
		return
	var tip: Vector3 = game.arm_tip_rel()
	var dir: Vector3 = game.arm_dir_world()
	for e in game.entities:
		if e["kind"] != "pod" and e["kind"] != "crystal":
			continue
		if e["mode"] != "field" or not e["revealed"]:
			continue
		var q := rel_to_entity(e) - tip
		if q.length() < 90.0 and rad_to_deg(q.angle_to(dir)) < 14.0:
			e["mode"] = "towed"
			e["tow_rel"] = rel_to_entity(e)
			towed.append(e)
			Voice.say("Tractor beam locked!")


func _capture(e: Dictionary) -> void:
	towed.erase(e)
	e["mode"] = "attached"
	e["offset"] = Vector3(randf_range(-0.6, 0.6), 0.4, 0.5 + collected * 0.9)
	e["visible"] = e["kind"] == "crystal"
	sim.cargo_mass += float(e.get("mass", 100.0))
	Sfx.clunk()
	game.nav_targets = game.nav_targets.filter(func(t: Dictionary) -> bool: return not (t.has("entity") and t["entity"] == e))
	game.nav_index = -1
	if e["kind"] == "pod":
		e["visible"] = false
		if step == 2:
			advance("Pod captured! The pilot is safe. Now let's go mining!")
	else:
		collected += 1
		Voice.say("Crystal %d collected!" % collected, 1)


func on_scanner_ping() -> void:
	if not pod["revealed"]:
		pod["revealed"] = true
		game.set_nav_target_by_name("ESCAPE POD")
		if step == 0:
			if not game.powered.get("shields", false):
				Voice.say("Pod found! Ops, don't forget the SHIELDS!", 1)
			advance("Escape pod found! Pilot, fly us there, slowly.")


func can_jump() -> bool:
	if step != 4:
		Voice.say("Finish the job before jumping home!", 1)
		return false
	var ang := rad_to_deg(sim.forward().angle_to(jump_dir()))
	if ang > 20.0:
		Voice.say("Pilot: point at the jump marker first. %d degrees off." % int(ang), 1)
		return false
	return true


func on_jump_complete() -> void:
	# Arrive near the space station back home
	var st: Dictionary = game.station
	var p: BigVec = (st["pos"] as BigVec).copy()
	p.add(Vector3(0, 60, -600))
	sim.pos.set_from(p)
	sim.vel = st["vel"]
	sim.ang_vel = Vector3.ZERO
	advance("Jump complete! Welcome home, heroes!")


func cheat_advance() -> void:
	match step:
		0:
			on_scanner_ping()
		1:
			advance()
		2:
			pod["mode"] = "towed"
			pod["tow_rel"] = game.arm_tip_rel()
			towed.append(pod)
			_capture(pod)
		3:
			collected = CRYSTALS_NEEDED
			update(0.0)
		4:
			on_jump_complete()


func final_score() -> void:
	super.final_score()
	game.add_score("Crystals x%d" % collected, collected * 100)
	game.add_score("Rock bumps x%d" % hits, -25 * hits)
	game.add_score("Pod rescued", 300)
