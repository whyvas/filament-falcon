class_name EvaScenarios
extends RefCounted
## EVA scenarios: handrail network on the Falcon's hull, worksite props, items and task steps,
## all in the SHIP frame (see EvaSim). Built by the cockpit process from the live game state
## (station pose, Moon ground) and sent to whichever process drives the spacewalker.

const TITLES := {
	"window": "WINDOW VISIT",
	"antenna": "ANTENNA SWAP",
	"sample": "ROCK SAMPLE + BEACON",
	"rescue": "CANADARM RESCUE",
	"moonwalk": "MOONWALK",
}
const BRIEFS := {
	"window": "Climb along the handrails to the nose, wave at the crew through the window and knock on the glass. Then come back in.",
	"antenna": "The station's radio antenna is broken. Take the new antenna from the cargo bay, climb to the station port, unbolt the old one, fit the new one, bolt it. Ops can carry you on the robotic arm!",
	"sample": "A boulder floats right in front of the nose. Take a radio beacon from the hatch toolbox, stick it on the boulder, chip off a rock sample and bring it home.",
	"rescue": "Oh no! The jetpack is out of gas and the spacewalker is drifting above the cargo bay. Ops: catch them with the robotic arm and bring them to the hatch. Pilot: HOLD attitude so the arm does not swing!",
	"moonwalk": "One small step! Climb down the ladder, plant the flag, collect three moon rocks into the sample box and climb back up.",
}
## Missions weave an EVA in when the Commander turns on "EVA IN MISSIONS":
## mission id -> [scenario, insert before objective index (-1 = at the end)]
const MISSION_EVA := {
	"launch": ["window", -1],
	"docking": ["antenna", -1],
	"asteroids": ["sample", 4],
	"lunar": ["moonwalk", -1],
	"sandbox": ["rescue", -1],
}

## Starship-style hull: ogive nose, long straight barrel, flat aft dome (the model AND the
## EVA collision both use this profile).
const PROFILE := [Vector2(-7.7, 0.0), Vector2(-7.6, 0.35), Vector2(-7.3, 0.75), Vector2(-6.8, 1.12), Vector2(-6.0, 1.48),
	Vector2(-5.0, 1.74), Vector2(-4.0, 1.88), Vector2(-3.0, 1.95), Vector2(6.9, 1.95), Vector2(7.2, 1.8), Vector2(7.3, 1.2), Vector2(7.32, 0.0)]
const YS := 0.82
const HATCH_Z := -1.5


static func hull_r(z: float) -> float:
	for i in range(PROFILE.size() - 1):
		var a: Vector2 = PROFILE[i]
		var b: Vector2 = PROFILE[i + 1]
		if z >= a.x and z <= b.x:
			return lerpf(a.y, b.y, (z - a.x) / maxf(b.x - a.x, 1e-4))
	return 0.0


## Point on (or `off` metres above) the hull: t = angle round the fuselage, PI/2 = roof, PI = port.
static func hull_pt(z: float, t: float, off: float = 0.14) -> Vector3:
	var r := hull_r(z)
	var p := Vector3(cos(t) * r, sin(t) * r * YS, z)
	var n := Vector3(cos(t) * YS, sin(t), 0.0).normalized()
	return p + n * off


static func hatch_point() -> Vector3:
	return hull_pt(HATCH_Z, PI - 0.32, 0.0)


static func hatch_normal() -> Vector3:
	return Vector3(-YS * cos(0.32), sin(0.32), 0.0).normalized()


## The Falcon's handrails (same for every scenario): hatch arc, roof spine, port bay sill,
## both canopy side rails, the nose arch in front of the windows and a stub to the nose ring.
static func hull_rails() -> Array:
	var rails := []
	var arc := PackedVector3Array()
	for k in 6:
		arc.append(hull_pt(-0.9, PI - 0.12 - k * (PI * 0.5 - 0.12) / 5.0))
	rails.append(arc)
	rails.append(PackedVector3Array([hull_pt(-0.9, PI * 0.5), hull_pt(-1.6, PI * 0.5), hull_pt(-2.3, PI * 0.5)]))
	# port bay sill (runs aft beside the cargo doors)
	var sill := PackedVector3Array()
	for z: float in [-0.9, 0.6, 2.1, 3.6]:
		sill.append(hull_pt(z, PI - 0.98))
	rails.append(sill)
	rails.append(PackedVector3Array([arc[2], sill[0]]))
	# canopy side rails, both sides, down to the nose arch
	for sgn: float in [-1.0, 1.0]:
		var side := PackedVector3Array()
		side.append(hull_pt(-2.3, PI * 0.5))
		for z: float in [-2.9, -4.0, -5.2, -6.2]:
			var t := PI * 0.5 + sgn * -0.62 if sgn > 0.0 else PI * 0.5 + 0.62
			side.append(hull_pt(z, t))
		side.append(hull_pt(-6.9, PI * 0.5 + (0.75 if sgn < 0.0 else -0.75)))
		rails.append(side)
	# nose arch (port -> roof -> starboard), just ahead of the windows
	var arch := PackedVector3Array()
	for k in 7:
		var t2 := PI * 0.5 + 0.75 - k * 0.25
		arch.append(hull_pt(-6.9, t2, 0.22 + 0.12 * sin(k / 6.0 * PI)))
	rails.append(arch)
	rails.append(PackedVector3Array([arch[3], hull_pt(-7.45, PI * 0.5, 0.25)]))
	return rails


static func nose_arch_top() -> Vector3:
	return hull_pt(-6.9, PI * 0.5, 0.34)


static func window_spot() -> Vector3:
	return window_face()["head"]


const EYE := Vector3(0, 1.05, -5.3)   # cockpit eye point (WorldView.EYE)


## Where a spacewalker floats to look in through the LEFT window: head ~0.36 m outside the
## glass on the crew's line of sight 35 deg left of straight ahead at eye level, body lying off
## the port side (feet out to the left, clear of the hull), visor turned to the crew. Returns {head, n, glass, rig}.
static func window_face(side: float = -1.0) -> Dictionary:
	var d := Vector3(sin(deg_to_rad(35.0)) * side, 0.03, -cos(deg_to_rad(35.0))).normalized()
	# march out from the eye to the canopy glass (ellipsoid EvaSim.CANOPY_*)
	var t := 0.0
	while t < 3.0 and ((EYE + d * t - EvaSim.CANOPY_C) / EvaSim.CANOPY_R).length() < 1.0:
		t += 0.005
	var glass := EYE + d * t
	var n := ((glass - EvaSim.CANOPY_C) / (EvaSim.CANOPY_R * EvaSim.CANOPY_R)).normalized()
	# on the crew's line of sight (centred in the left window), visor turned to the eye point
	var head := glass + d * 0.36
	var z := (head - EYE).normalized()
	var up := (Vector3(-side, 0.0, 0.0).slide(z)).normalized()
	var x := up.cross(z).normalized()
	var b := Basis(x, up, x.cross(up).normalized())
	return {"head": head, "n": n, "glass": glass, "rig": Transform3D(b, head - b.y * 1.6)}


static func ship_from_world(game: Node, world_rel: Vector3) -> Vector3:
	var sim: ShipSim = game.sim
	return sim.basis.inverse() * world_rel


static func in_space(game: Node) -> bool:
	var sim: ShipSim = game.sim
	if sim.dominant == null:
		return false
	return sim.density_now <= 0.0 and sim.thrust_now <= 0.0 and (sim.altitude > 70000.0 or sim.dominant != game.earth)


static func on_moon(game: Node) -> bool:
	var sim: ShipSim = game.sim
	return sim.dominant == game.moon and (sim.landed or (sim.agl < 30.0 and sim.vel.distance_to(game.moon.vel) < 0.5))


static func docked(game: Node) -> bool:
	var m: Mission = game.mission
	return m != null and m.id == "docking" and (bool(m.get("hard_docked")) or bool(m.get("soft_captured")))


## Scenario ids that make sense right now (first = suggested).
static func available(game: Node) -> Array[String]:
	var out: Array[String] = []
	if on_moon(game):
		out.append("moonwalk")
		return out
	if not in_space(game):
		return out
	if docked(game):
		out.append("antenna")
	var mid: String = game.mission_id
	if mid == "asteroids":
		out.append("sample")
	out.append("window")
	if not docked(game):
		out.append("rescue")
	if mid != "asteroids":
		out.append("sample")
	return out


static func build(id: String, game: Node, tether_len: float = 20.0) -> Dictionary:
	var hatch := hatch_point()
	var hn := hatch_normal()
	var s := {"id": id, "title": TITLES.get(id, id), "brief": BRIEFS.get(id, ""), "hatch": hatch,
		"tether": true, "tether_anchor": hatch + Vector3(0, 0.45, 0.35), "tether_len": tether_len,
		"rails": hull_rails(), "items": [], "props": [], "steps": [], "surface": false, "arm": true}
	var head0 := hatch + hn * 0.75 + Vector3(0, 0.25, 0)
	s["start"] = Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), head0 - Vector3(0, 1.6, 0))
	var props: Array = s["props"]
	var items: Array = s["items"]
	var steps: Array = s["steps"]
	props.append({"id": "toolbox", "kind": "toolbox", "pos": hatch + hn * 0.25 + Vector3(0, -0.45, 0.45), "basis": Basis.IDENTITY, "state": ""})
	var inside := {"do": "inside", "at": hatch + hn * 0.4, "r": 0.9, "text": "Back to the hatch and press USE to go inside", "score": 150}
	match id:
		"window":
			var wf := window_face()
			s["window_head"] = wf["head"]
			steps.append({"do": "go", "at": hull_pt(-6.2, PI * 0.5 + 0.62), "r": 0.9, "text": "Climb the handrails forward along the canopy", "score": 150})
			steps.append({"do": "go", "at": wf["head"], "r": 0.3, "pose": wf["rig"], "text": "Pull yourself over to the LEFT window and look in at the crew", "score": 100})
			steps.append({"do": "gesture", "gesture": "wave", "text": "Wave at the crew through the window!", "score": 100})
			steps.append({"do": "gesture", "gesture": "knock", "text": "Knock on the cockpit window", "score": 100})
			steps.append(inside)
		"sample":
			var c := Vector3(0.25, 1.7, -8.95)
			var rad := 0.85
			props.append({"id": "boulder", "kind": "boulder", "pos": c, "basis": Basis.IDENTITY, "state": "", "r": rad})
			items.append({"id": "beacon", "kind": "beacon", "pos": hatch + hn * 0.3 + Vector3(0, -0.3, 0.3), "basis": Basis.IDENTITY})
			var nose := hull_pt(-7.45, PI * 0.5, 0.25)
			var face := c + (nose - c).normalized() * (rad + 0.05)
			var chip := c + ((nose - c).normalized() + Vector3(-0.6, 0.3, 0)).normalized() * (rad + 0.05)
			steps.append({"do": "pick", "item": "beacon", "text": "Take a radio BEACON from the toolbox at the hatch", "score": 80})
			steps.append({"do": "go", "at": nose, "r": 1.0, "text": "Climb to the nose ring, next to the boulder", "score": 150})
			steps.append({"do": "place", "item": "beacon", "item_kind": "beacon", "at": face, "r": 0.5, "basis": Basis.looking_at(face - c, Vector3.UP),
				"text": "Stick the beacon on the boulder", "score": 150, "set": {"boulder": "tagged"}})
			steps.append({"do": "use", "at": chip, "r": 0.45, "hold": 2.0, "text": "Hold USE on the boulder to chip off a sample", "score": 150, "set": {"boulder": "sampled"}})
			steps.append(inside)
		"antenna":
			var st: Dictionary = game.station
			var sim: ShipSim = game.sim
			var to_s := func(p_st: Vector3) -> Vector3:
				return sim.basis.inverse() * ((st["basis"] as Basis) * p_st + (st["pos"] as BigVec).rel(sim.pos))
			var sb_s: Basis = sim.basis.inverse() * (st["basis"] as Basis)
			var r1: Vector3 = to_s.call(Vector3(0.35, 1.45, 20.6))
			var r2: Vector3 = to_s.call(Vector3(0.35, 1.45, 18.8))
			var r3: Vector3 = to_s.call(Vector3(0.35, 1.45, 17.2))
			(s["rails"] as Array).append(PackedVector3Array([hull_pt(-7.45, PI * 0.5, 0.25), r1, r2, r3]))
			var mount: Vector3 = to_s.call(Vector3(-0.35, 1.32, 18.4))
			props.append({"id": "mount", "kind": "antenna_mount", "pos": mount, "basis": sb_s, "state": "broken"})
			items.append({"id": "antenna", "kind": "antenna", "pos": hull_pt(2.2, PI * 0.5, -0.65) + Vector3(-0.55, 0, 0), "basis": Basis.IDENTITY, "in_bay": true})
			s["worksite"] = mount
			s["tether_len"] = maxf(tether_len, 30.0)    # the station antenna is ~21 m from the hatch
			steps.append({"do": "pick", "item": "antenna", "text": "Take the new ANTENNA from the cargo bay (Ops: CARGO DOORS open)", "score": 120})
			steps.append({"do": "go", "at": r2, "r": 1.3, "text": "Climb to the station antenna (or ride the arm: Ops brings the arm tip)", "score": 150})
			steps.append({"do": "use", "at": mount, "r": 0.5, "hold": 2.0, "text": "Hold USE to unbolt the broken antenna", "score": 120, "set": {"mount": "empty"}})
			steps.append({"do": "place", "item": "antenna", "item_kind": "antenna", "at": mount + sb_s.y * 0.05, "basis": sb_s, "r": 0.5, "text": "Put the new antenna on the mount", "score": 120})
			steps.append({"do": "use", "at": mount, "r": 0.5, "hold": 2.0, "text": "Hold USE to bolt it down", "score": 150, "set": {"mount": "fixed"}})
			steps.append(inside)
		"rescue":
			var drift := hull_pt(1.2, PI * 0.5, 0.0) + Vector3(0.0, 6.5, -1.0)
			s["start"] = Transform3D(Basis.looking_at(Vector3(0, -0.3, -1).normalized(), Vector3.UP), drift - Vector3(0, 1.6, 0))
			s["gas"] = 0.0
			s["tether_len"] = 30.0
			steps.append({"do": "grab_arm", "text": "Ops: fly the arm tip to the spacewalker. Spacewalker: GRAB the arm tip!", "score": 200})
			steps.append({"do": "ride", "at": hatch + hn * 1.2 + Vector3(0, 0.5, 0), "r": 2.2, "text": "Ops: carry the spacewalker to the hatch. Pilot: HOLD attitude!", "score": 250})
			steps.append({"do": "inside", "at": hatch + hn * 0.4, "r": 2.2, "text": "Let go of the arm, grab a handrail and press USE at the hatch", "score": 150})
		"moonwalk":
			var sim2: ShipSim = game.sim
			var up: Vector3 = (sim2.basis.inverse() * sim2.up_dir).normalized()
			var gh := -sim2.agl
			s["surface"] = true
			s["up"] = up
			s["ground_h"] = gh
			s["gravity"] = 1.62
			s["tether"] = false
			s["arm"] = false
			var foot := hatch + hn * 0.35
			foot = foot - up * (foot.dot(up) - gh)
			(s["rails"] as Array).append(PackedVector3Array([hatch + hn * 0.35, foot + up * 0.25]))
			var fwd := hn.slide(up).normalized() if hn.slide(up).length() > 0.1 else up.cross(Vector3.RIGHT).normalized()
			var side := up.cross(fwd).normalized()
			var gp := func(p: Vector3) -> Vector3:
				return p - up * (p.dot(up) - gh)
			var box: Vector3 = gp.call(foot + fwd * 1.2 + side * 0.8)
			props.append({"id": "box", "kind": "sample_box", "pos": box, "basis": Basis.IDENTITY, "state": ""})
			items.append({"id": "flag", "kind": "flag", "pos": foot + fwd * 0.8 - side * 0.5 + up * 0.9, "basis": Basis.IDENTITY})
			for k in 3:
				var a := -0.9 + k * 0.9
				var rp: Vector3 = gp.call(foot + (fwd * cos(a) + side * sin(a)) * (4.5 + k * 1.2)) + up * 0.08
				items.append({"id": "rock%d" % k, "kind": "rock", "pos": rp, "basis": Basis.IDENTITY})
			var flag_at: Vector3 = gp.call(foot + fwd * 6.5 - side * 2.0) + up * 0.6
			s["start"] = Transform3D(Basis.looking_at(-fwd, up), hatch + hn * 0.6 - up * 1.2)
			steps.append({"do": "go", "at": foot + up * 1.0, "r": 1.2, "text": "Climb down the ladder to the surface", "score": 150})
			steps.append({"do": "pick", "item": "flag", "text": "Pick up the FLAG next to the ladder", "score": 80})
			steps.append({"do": "place", "item": "flag", "item_kind": "flag", "at": flag_at, "basis": Basis.looking_at(fwd, up).rotated(up, 0.0), "r": 1.0, "text": "Walk out and plant the flag!", "score": 200})
			steps.append({"do": "collect", "kinds": ["rock"], "count": 3, "at": box + up * 0.4, "r": 0.9, "text": "Collect 3 moon rocks into the sample box", "score": 250})
			steps.append({"do": "inside", "at": hatch + hn * 0.4, "r": 1.2, "text": "Climb up the ladder and press USE at the hatch", "score": 150})
	return s
