class_name EvaBot
extends RefCounted
## Autopilot spacewalker for tests and demos: follows the scenario steps in flat mode
## (handrail traverse along the shortest rail path, jetpack / walking for the last metre,
## picks, places, uses, waves, knocks, goes back inside). Returns FlatControl commands.

var _wait := 0.0
var _phase := ""            # "" | "jet" (final approach off the rails)
var _phase_step := -1
var log_lines: Array[String] = []


func decide(dt: float, sim: EvaSim) -> Dictionary:
	var c := {"move": Vector3.ZERO, "rail_move": 0.0}
	if sim.done:
		return c
	_wait = maxf(0.0, _wait - dt)
	if sim.step != _phase_step:
		_phase_step = sim.step
		_phase = ""
	var s := sim.cur_step()
	var kind := str(s.get("do", ""))
	var target: Vector3 = s.get("at", Vector3.ZERO)
	match kind:
		"pick":
			for it: Dictionary in sim.items:
				if str(it["id"]) == str(s.get("item", "")):
					target = it["pos"]
		"gesture":
			target = sim.scen.get("window_head", EvaScenarios.window_spot())
		"collect":
			if sim.holding_item():
				target = s["at"]
			else:
				target = _nearest_item(sim, (s.get("kinds", ["rock"]) as Array))
		"grab_arm", "ride":
			target = sim.arm_tip
	var head := sim.head_s().origin
	var dist := head.distance_to(target)
	c["look_at"] = target
	var reach := EvaSim.FLAT_REACH * 0.8
	if kind in ["go", "inside"] and not s.has("pose"):
		reach = maxf(reach, float(s.get("r", 0.6)) + 0.3)
	if kind in ["grab_arm", "ride"]:
		# the test harness flies the arm (Ops); we just grab it when it is close, then ride
		if not sim.riding and sim.arm_ok and dist < EvaSim.FLAT_REACH + 0.3:
			c["use"] = _wait <= 0.0
			_wait = 0.3 if c["use"] else _wait
		return c
	if s.has("pose") and dist < 2.6:
		c["glide"] = true      # pull over to the window along the canopy frame
		return c
	if kind == "gesture" and sim.perch:
		dist = 0.0
	if kind == "inside" and sim.riding:
		c["grab"] = true       # let go of the arm, onto the rails
		return c
	if dist > reach:
		_travel(sim, target, c, dt)
		return c
	if _phase == "jet" and sim.vel.length() > 0.03:
		c["stop"] = true
		return c
	# at the worksite
	match kind:
		"pick", "place":
			if _wait <= 0.0:
				c["use"] = true
				_wait = 0.6
		"collect":
			if _wait <= 0.0:
				c["use"] = true
				_wait = 0.6
		"use":
			c["use"] = true
		"gesture":
			var g := str(s.get("gesture", ""))
			if _wait <= 0.0:
				c["wave" if g == "wave" else "knock"] = true
				_wait = 2.5
		"inside":
			c["use"] = true
		"go":
			pass
	return c


func _nearest_item(sim: EvaSim, kinds: Array) -> Vector3:
	var best := Vector3.ZERO
	var bd := 1e9
	for it: Dictionary in sim.items:
		if str(it["kind"]) in kinds and not bool(it["gone"]) and not bool(it["placed"]):
			var d := (it["pos"] as Vector3).distance_to(sim.head_s().origin)
			if d < bd:
				bd = d
				best = it["pos"]
	return best


## Get within reach of `target`: rails when the rail network passes close by, else the
## jetpack (space) or walking (Moon).
func _travel(sim: EvaSim, target: Vector3, c: Dictionary, _dt: float) -> void:
	var tn := sim.nearest_node(target)
	var node_ok := tn >= 0 and sim.nodes[tn].distance_to(target) < EvaSim.FLAT_REACH + 0.3
	var on_rail := sim.att_edge >= 0
	if sim.surface:
		# Moon: ladder rail between hatch and ground, walk everywhere else
		var head := sim.head_s().origin
		var tgt_h := target.dot(sim.up)
		var gnd_h := sim.ground_h
		var high := head.dot(sim.up) - gnd_h > 2.4
		var want_high := tgt_h - gnd_h > 2.4
		if high != want_high and node_ok == false:
			# use the ladder: top node (near hatch) / bottom node
			var top := sim.nearest_node(sim.hatch)
			var bot := 0
			var lo := 1e9
			for i in sim.nodes.size():
				var hh := sim.nodes[i].dot(sim.up)
				if hh < lo:
					lo = hh
					bot = i
			var dest := top if want_high else bot
			if not on_rail:
				c["grab"] = _wait <= 0.0
				_wait = 0.4 if c["grab"] else _wait
			elif sim.nodes[dest].distance_to(sim.rail_point()) < 0.05:
				c["grab"] = true            # step off the ladder
			else:
				c["rail_target"] = dest
			return
		if on_rail and not want_high:
			c["grab"] = true
			return
		if on_rail and want_high:
			c["rail_target"] = sim.nearest_node(target)
			return
		var d := (target - sim.waist_s()).slide(sim.up)
		var loc := sim.rig.basis.inverse() * d.normalized()
		c["move"] = Vector3(loc.x, 0, loc.z).normalized()
		return
	if _phase == "jet":
		_jet(sim, target - (sim.head_s().origin - sim.waist_s()), c)
		return
	if node_ok and on_rail and sim.gas > 5.0 and sim.rail_point().distance_to(sim.nodes[tn]) < 0.05 and sim.head_s().origin.distance_to(target) > EvaSim.FLAT_REACH * 0.8:
		# the rails end short of the worksite: let go and jet the last metre or two
		c["grab"] = true
		_phase = "jet"
		return
	if node_ok:
		if not on_rail:
			if sim.nearest_rail(sim.waist_s())[1] < EvaSim.FLAT_REACH + 0.2:
				c["grab"] = _wait <= 0.0
				_wait = 0.3 if c["grab"] else _wait
			else:
				_jet(sim, sim.nodes[sim.nearest_node(sim.waist_s())], c)
			return
		c["rail_target"] = tn
		return
	# off the rail network: jet from the closest rail point
	if on_rail:
		var here := sim.rail_point()
		if here.distance_to(sim.nodes[tn]) > 0.05:
			c["rail_target"] = tn
			return
		c["grab"] = true      # let go, then jet
		return
	_jet(sim, target, c)


func _jet(sim: EvaSim, target: Vector3, c: Dictionary) -> void:
	var d := target - sim.waist_s()
	var want := d.normalized() * minf(0.5, d.length() * 0.4)
	var dv := want - sim.vel
	if dv.length() > 0.03:
		c["move"] = sim.rig.basis.inverse() * dv.normalized()
	else:
		c["stop"] = d.length() < 0.6
