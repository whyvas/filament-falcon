class_name EvaSim
extends RefCounted
## The spacewalker: body, hands, handrails, tether, SAFER jetpack, arm ride, suit consumables,
## task steps and gestures. Pure logic (no nodes), so it runs headless in tests, inside the
## cockpit process (flat EVA) or inside the VR client (`--eva-client`), whichever "drives" it.
##
## Everything is in the SHIP frame ("S"): the Falcon's own axes, metres, ship centre = origin
## (+X right, +Y roof, -Z nose). The astronaut rig (XR origin: the floor point under the player)
## is `rig`; head and hands are rig-local transforms from the headset / controllers (or from
## FlatControl). A rig-local -Z is "the way the rig faces".
##
## Locomotion:
##  - VR: grab a handrail with GRIP and pull (the body moves so the hand stays put); let go
##    with some speed to glide. Grab the arm tip to ride the robotic arm.
##  - Flat (keyboard / pad / bot): attach to the rail network and slide along it (move_rail),
##    or detach and use the jetpack.
##  - SAFER jetpack: gentle (0.12 m/s²), speed-capped, STOP kills drift.
##  - Moon: gravity 1.62 m/s², ground plane, walk + hop; the ladder is a rail.

const REACH_VR := 0.16        # hand to rail / item distance for a grab
const FLAT_REACH := 1.35      # flat mode: interact with things this far from the head
const JET_ACCEL := 0.12
const JET_MAX_V := 0.8
const THROW_MAX := 1.2
const RAIL_SPEED := 0.75      # flat hand-over-hand speed
const WALK_SPEED := 1.3       # moon lope
const HOP_V := 1.4
const CANOPY_C := Vector3(0.0, 1.05, -4.6)   # crew-deck window glass (ellipsoid), cut into the hull
const CANOPY_R := Vector3(1.1, 0.62, 1.9)

# ---- scenario (built by EvaScenarios, sent to the driver process)
var scen := {}
var steps: Array = []
var step := 0
var progress := 0.0           # seconds held on a "use" step
var collected := 0
var rails_a := PackedVector3Array()
var rails_b := PackedVector3Array()
var nodes := PackedVector3Array()         # rail graph (flat mode + bots)
var edges: Array[Vector2i] = []
var items: Array = []                     # [{id, kind, pos, basis, held(-1|0|1), placed, gone}]
var props: Array = []                     # [{id, kind, pos, basis, state}]
var surface := false
var up := Vector3.UP
var ground_h := -1.0e9
var gravity := 0.0
var tether_on := true
var tether_anchor := Vector3.ZERO
var tether_len := 20.0
var hatch := Vector3.ZERO

# ---- body
var rig := Transform3D.IDENTITY
var vel := Vector3.ZERO
var head := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))      # rig-local
var hands: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.0, -0.3)), Transform3D(Basis.IDENTITY, Vector3(0.3, 1.0, -0.3))]
var hand_curl: Array[Vector3] = [Vector3(-1, 0, 0), Vector3(-1, 0, 0)]   # (grip, trigger, thumb) 0..1; x<0 = no analog data
var hand_pose: Array[String] = ["open", "open"]   # open | fist | point (avatar fingers)
var grip_prev: Array[bool] = [false, false]
var grab_kind: Array[String] = ["", ""]           # "" | rail | arm | item
var grab_anchor: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_prev_s: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var hand_vel: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var att_edge := -1            # flat: attached rail edge
var att_u := 0.0
var att_dir := 1              # flat: direction last moved along the edge
var perch := false            # flat: holding the canopy frame at a window (no drift)
var riding := false           # on the arm's foot restraint
var ride_off := Vector3.ZERO
var on_ground := false
var lamp := false
var jet_on := 0.0             # 0..1 thrust this frame (vignette, sound, avatar plume)
var flat := false

# ---- suit
var o2 := 100.0               # %
var batt := 100.0             # %
var co2 := 1.5                # mmHg
var suit_temp := 21.0         # °C
var heart := 78.0             # bpm
var gas := 100.0              # SAFER nitrogen %
var exertion := 0.0
var time_out := 0.0
var tether_used := 0.0
var taut := false
var done := false
var failed := ""
var score := 0

# ---- world inputs (set each frame by the owner)
var arm_tip := Vector3(0, 1.75, 1.0)
var arm_ok := false
var ship_w := Vector3.ZERO        # ship angular velocity, ship frame (rad/s)
var ship_acc := Vector3.ZERO      # ship proper acceleration, ship frame (m/s²)
var in_sun := true
var cargo_door := 1.0

# ---- events (the driver fills; owners drain with take_events, the net layer forwards)
var events: Array = []            # [[id, kind, data]]
var _ev_id := 0
var _wave: Array = [[], []]       # per hand: [[t, x]] recent lateral positions
var _wave_cd := 0.0
var _contact_t: Array[float] = [0.0, 0.0]
var _knock_cd := 0.0
var _palm_cd := 0.0
var _t := 0.0
var _o2_warned := 0


func setup(s: Dictionary) -> void:
	scen = s
	steps = s.get("steps", [])
	step = 0
	progress = 0.0
	collected = 0
	surface = bool(s.get("surface", false))
	up = s.get("up", Vector3.UP)
	ground_h = float(s.get("ground_h", -1.0e9))
	gravity = float(s.get("gravity", 0.0))
	tether_on = bool(s.get("tether", true))
	tether_anchor = s.get("tether_anchor", Vector3.ZERO)
	tether_len = float(s.get("tether_len", 20.0))
	hatch = s.get("hatch", Vector3.ZERO)
	items = []
	for it: Dictionary in s.get("items", []):
		var d := it.duplicate()
		d["held"] = -1
		d["placed"] = false
		d["gone"] = false
		items.append(d)
	props = []
	for p: Dictionary in s.get("props", []):
		props.append(p.duplicate())
	_build_rails(s.get("rails", []))
	var st: Transform3D = s.get("start", Transform3D(Basis.IDENTITY, hatch))
	rig = st
	vel = Vector3.ZERO
	gas = float(s.get("gas", 100.0))
	riding = false
	att_edge = -1
	done = false
	failed = ""
	time_out = 0.0
	score = 0
	lamp = not in_sun


func _build_rails(polys: Array) -> void:
	rails_a = PackedVector3Array()
	rails_b = PackedVector3Array()
	nodes = PackedVector3Array()
	edges.clear()
	for poly: PackedVector3Array in polys:
		var prev := -1
		for p in poly:
			var ni := _node_at(p)
			if prev >= 0 and prev != ni:
				edges.append(Vector2i(prev, ni))
				rails_a.append(nodes[prev])
				rails_b.append(nodes[ni])
			prev = ni


func _node_at(p: Vector3) -> int:
	for i in nodes.size():
		if nodes[i].distance_to(p) < 0.3:
			return i
	nodes.append(p)
	return nodes.size() - 1


# ======================================================================== frames
func head_s() -> Transform3D:
	return rig * head


func hand_s(i: int) -> Transform3D:
	return rig * hands[i]


## Waist (tether clip, flat-mode pivot): a bit below the head along rig up.
func waist_s() -> Vector3:
	return head_s().origin - rig.basis.y * 0.62


func body_up() -> Vector3:
	return rig.basis.y.normalized()


static func closest_on_seg(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-8:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


func nearest_rail(p: Vector3) -> Array:
	var best := -1
	var bd := 1e9
	var bp := Vector3.ZERO
	for i in rails_a.size():
		var c := closest_on_seg(p, rails_a[i], rails_b[i])
		var d := c.distance_to(p)
		if d < bd:
			bd = d
			best = i
			bp = c
	return [best, bd, bp]


func nearest_node(p: Vector3) -> int:
	var best := -1
	var bd := 1e9
	for i in nodes.size():
		var d := nodes[i].distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Shortest node path (BFS on segment lengths, tiny graphs) from a to b, inclusive.
func route(a: int, b: int) -> PackedInt32Array:
	var n := nodes.size()
	var dist := PackedFloat32Array()
	var prev := PackedInt32Array()
	var open := []
	dist.resize(n)
	prev.resize(n)
	for i in n:
		dist[i] = 1e9
		prev[i] = -1
	if a < 0 or b < 0:
		return PackedInt32Array()
	dist[a] = 0.0
	open.append(a)
	while not open.is_empty():
		var bi := 0
		for k in open.size():
			if dist[int(open[k])] < dist[int(open[bi])]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		for e in edges:
			var v := -1
			if e.x == u:
				v = e.y
			elif e.y == u:
				v = e.x
			if v < 0:
				continue
			var nd := dist[u] + nodes[u].distance_to(nodes[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				if not open.has(v):
					open.append(v)
	var out := PackedInt32Array()
	if dist[b] >= 1e8:
		return out
	var c := b
	while c >= 0:
		out.insert(0, c)
		c = prev[c]
	return out


# ======================================================================== step
## One simulation step. `inp` keys (all optional):
##  head: Transform3D, hands: [Transform3D, Transform3D] (rig-local, from XR or FlatControl)
##  grip: [bool, bool], use: [bool, bool], point: [bool, bool]
##  move: Vector3 (rig-local, -1..1: jetpack / moon walk), stop, hop, lamp_toggle: bool
##  turn: float (rad, snap turn about rig up)
##  flat: bool, rail_toggle: bool, rail_move: float (-1..1 along the look direction),
##  rail_target: int (bots: node to slide to), look: Vector3 (S frame), ptt: bool
func step_sim(dt: float, inp: Dictionary) -> void:
	if done:
		return
	_t += dt
	time_out += dt
	flat = bool(inp.get("flat", false))
	if inp.has("head"):
		head = inp["head"]
	if inp.has("hands"):
		var hs: Array = inp["hands"]
		hands[0] = hs[0]
		hands[1] = hs[1]
	var hc: Array = inp.get("curl", [])
	if hc.size() == 2:
		hand_curl[0] = hc[0]
		hand_curl[1] = hc[1]
	var grip: Array = inp.get("grip", [false, false])
	var use: Array = inp.get("use", [false, false])
	var pnt: Array = inp.get("point", [false, false])
	if bool(inp.get("lamp_toggle", false)):
		lamp = not lamp
		_event("lamp", {"on": lamp})
	var turn := float(inp.get("turn", 0.0))
	if turn != 0.0:
		_rotate_rig(turn)
	# free-floating: the ship turns / accelerates under us
	var holding := grab_kind[0] in ["rail", "arm"] or grab_kind[1] in ["rail", "arm"] or att_edge >= 0 or riding or perch
	if not holding and not surface:
		if ship_w.length_squared() > 1e-10:
			var r := Basis(ship_w.normalized(), -ship_w.length() * dt)
			rig = Transform3D(r * rig.basis, r * rig.origin)
			vel = r * vel
		vel -= ship_acc * dt
	# hands: velocities, grabs, items
	for i in 2:
		var hp := hand_s(i).origin
		hand_vel[i] = hand_vel[i].lerp((hp - hand_prev_s[i]) / maxf(dt, 1e-4), 0.35)
		hand_prev_s[i] = hp
		var g := bool(grip[i])
		if g and not grip_prev[i]:
			_try_grab(i)
		elif not g and grip_prev[i]:
			_release(i)
		grip_prev[i] = g
		hand_pose[i] = "fist" if grab_kind[i] != "" else ("point" if bool(pnt[i]) else ("fist" if g else "open"))
	# locomotion
	var moved_hand := false
	var pull := Vector3.ZERO
	var nh := 0
	for i in 2:
		if grab_kind[i] == "rail":
			pull += grab_anchor[i] - hand_s(i).origin
			nh += 1
	if nh > 0:
		var d := pull / float(nh)
		rig.origin += d
		vel = Vector3.ZERO
		moved_hand = true
	if riding:
		var target := arm_tip + ride_off
		vel = (target - rig.origin) / maxf(dt, 1e-4)
		rig.origin = target
		if not arm_ok:
			riding = false
	elif flat and att_edge >= 0 and not inp.has("glide_pose"):
		_flat_rail(dt, inp)
	elif flat and inp.has("glide_pose"):
		# flat: pull along the canopy frame into a "look in at the window" pose
		var goal: Transform3D = inp["glide_pose"]
		att_edge = -1
		perch = true
		var dpos := goal.origin - rig.origin
		var stepl := minf(dpos.length(), 0.6 * dt)
		var f := stepl / maxf(dpos.length(), 1e-4) if dpos.length() > 1e-4 else 1.0
		rig = Transform3D(rig.basis.slerp(goal.basis, clampf(maxf(f, dt * 1.5), 0.0, 1.0)).orthonormalized(), rig.origin + dpos * f)
		vel = Vector3.ZERO
		exertion = maxf(exertion, 0.4)
	elif perch and (inp.get("move", Vector3.ZERO) as Vector3).length() < 0.05:
		vel = Vector3.ZERO
	elif not moved_hand:
		perch = false
		_free_motion(dt, inp)
	if bool(inp.get("rail_toggle", false)):
		_flat_toggle()
	_tether(dt)
	# held items follow the hand
	for it: Dictionary in items:
		var h: int = it["held"]
		if h >= 0:
			var hx := hand_s(h)
			it["pos"] = hx.origin + hx.basis.z * -0.12
			it["basis"] = hx.basis
	_gestures(dt)
	_steps(dt, use)
	_suit(dt, inp)


func _rotate_rig(a: float) -> void:
	# about the head, so the view does not swing around the room centre
	var hp := head_s().origin
	var r := Basis(body_up(), a)
	rig.basis = (r * rig.basis).orthonormalized()
	rig.origin = hp + r * (rig.origin - hp)


func _try_grab(i: int) -> void:
	if flat and i == 0:
		return      # flat mode: the left hand just holds the rail; USE (right hand) picks things up
	var hp := hand_s(i).origin
	var reach := FLAT_REACH if flat else REACH_VR
	var src := head_s().origin if flat else hp
	# 1. items (not placed)
	var best: Dictionary = {}
	var bd := reach + 0.1
	for it: Dictionary in items:
		if bool(it["placed"]) or bool(it["gone"]) or int(it["held"]) >= 0:
			continue
		var d := (it["pos"] as Vector3).distance_to(src)
		if d < bd:
			bd = d
			best = it
	if not best.is_empty():
		if str(best.get("kind", "")) == "antenna" and cargo_door < 0.9 and bool(best.get("in_bay", false)):
			_event("need_doors", {})
			return
		best["held"] = i
		grab_kind[i] = "item"
		_event("pick", {"id": best["id"], "kind": best["kind"]})
		return
	# 2. holding an item in flat mode: E again = place / let it go
	# 3. the arm tip's foot restraint
	if arm_ok and arm_tip.distance_to(src if flat else hp) < (FLAT_REACH + 0.4 if flat else 0.35):
		riding = true
		att_edge = -1
		ride_off = rig.origin - arm_tip
		grab_kind[i] = "arm"
		_event("arm_on", {})
		return
	if flat:
		return
	# 4. rails
	var nr := nearest_rail(hp)
	if int(nr[0]) >= 0 and float(nr[1]) < reach:
		grab_kind[i] = "rail"
		grab_anchor[i] = hp
		vel = Vector3.ZERO
		if surface:
			on_ground = false


func _release(i: int) -> void:
	var k := grab_kind[i]
	grab_kind[i] = ""
	if k == "rail":
		if grab_kind[1 - i] != "rail":
			# push off: the body keeps the opposite of the hand's motion
			var v := -hand_vel[i]
			vel = v.limit_length(THROW_MAX)
	elif k == "arm":
		riding = false
		vel = Vector3.ZERO
		_event("arm_off", {})
	elif k == "item":
		_drop_item(i)


func _drop_item(i: int) -> void:
	for it: Dictionary in items:
		if int(it["held"]) != i:
			continue
		it["held"] = -1
		# snap into a matching place target of the current step
		var s := cur_step()
		var tgt: Vector3 = s.get("at", Vector3(1e9, 0, 0))
		var kinds: Array = s.get("kinds", [s.get("item_kind", "")])
		if str(s.get("do", "")) in ["place", "collect"] and str(it["kind"]) in kinds and (it["pos"] as Vector3).distance_to(tgt) < float(s.get("r", 0.6)) + (0.8 if flat else 0.0):
			if str(s.get("do", "")) == "collect":
				it["gone"] = true
				collected += 1
				_event("collected", {"n": collected, "of": int(s.get("count", 1))})
			else:
				it["placed"] = true
				it["pos"] = tgt
				it["basis"] = s.get("basis", Basis.IDENTITY)
				_event("placed", {"id": it["id"]})
		else:
			_event("drop", {"id": it["id"]})


## Flat-mode helper: E with an item in hand = put it down here (if it fits the step).
func flat_place() -> void:
	for i in 2:
		if grab_kind[i] == "item":
			grab_kind[i] = ""
			# move the item to the target if it is within flat reach
			var s := cur_step()
			for it: Dictionary in items:
				if int(it["held"]) == i and s.has("at") and (s["at"] as Vector3).distance_to(head_s().origin) < FLAT_REACH + 0.6:
					it["pos"] = s["at"]
			_drop_item(i)
			return


func holding_item() -> bool:
	return grab_kind[0] == "item" or grab_kind[1] == "item"


func _flat_toggle() -> void:
	if att_edge >= 0:
		att_edge = -1
		return
	perch = false
	if riding:
		riding = false
		grab_kind[0] = ""
		grab_kind[1] = ""
		_event("arm_off", {})
		return
	var nr := nearest_rail(waist_s())
	if int(nr[0]) >= 0 and float(nr[1]) < FLAT_REACH + 0.3:
		att_edge = int(nr[0])
		var e := edges[att_edge]
		var a := nodes[e.x]
		var b := nodes[e.y]
		att_u = clampf((nr[2] as Vector3 - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
		vel = Vector3.ZERO
		if not surface:
			# back upright (ship "up") along the rail, facing the same way (eased in _flat_rail)
			var fw := (-rig.basis.z).slide(Vector3.UP)
			_upright = Basis.looking_at(fw.normalized() if fw.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
		else:
			_upright = rig.basis


func attach_nearest() -> bool:
	if att_edge < 0:
		_flat_toggle()
	return att_edge >= 0


func rail_point() -> Vector3:
	if att_edge < 0:
		return waist_s()
	var e := edges[att_edge]
	return nodes[e.x].lerp(nodes[e.y], att_u)


var _upright := Basis.IDENTITY


func _snap_to_rail(rate: float = 1.0) -> void:
	# body hangs a little off the rail (hand on it, waist 0.45 m away from the hull centre)
	var rp := rail_point()
	var out := Vector3(rp.x, rp.y, 0.0)
	if surface:
		out = (rp - hatch).slide(up)
		out = Vector3.RIGHT if out.length() < 0.01 else out
	out = out.normalized() if out.length() > 0.01 else Vector3.UP
	var waist_target := rp + out * 0.45
	rig.origin += (waist_target - waist_s()) * rate


func _flat_rail(dt: float, inp: Dictionary) -> void:
	var e := edges[att_edge]
	var a := nodes[e.x]
	var b := nodes[e.y]
	var seg := b - a
	var L := maxf(seg.length(), 0.01)
	var speed := 0.0
	var tgt := int(inp.get("rail_target", -1))
	if tgt >= 0:
		# bot / click-to-go: walk the graph toward node tgt
		var here_node := e.x if att_u < 0.5 else e.y
		var path := route(here_node, tgt)
		var goal := tgt
		if path.size() >= 2:
			goal = path[1] if (path[1] == e.x or path[1] == e.y) else path[0]
		elif path.size() == 1:
			goal = path[0]
		if goal == e.x or goal == e.y:
			var to_u := 0.0 if goal == e.x else 1.0
			var du := to_u - att_u
			att_u += clampf(du, -RAIL_SPEED * dt / L, RAIL_SPEED * dt / L)
			if absf(to_u - att_u) < 1e-4 and goal != tgt:
				_switch_edge(goal, tgt)
		else:
			_switch_edge(e.x if att_u < 0.5 else e.y, goal)
	else:
		var mv := float(inp.get("rail_move", 0.0))
		var look: Vector3 = inp.get("look", -rig.basis.z)
		var dir_sign := 1.0 if seg.dot(look) >= 0.0 else -1.0
		speed = mv * dir_sign * RAIL_SPEED
		att_u += speed * dt / L
		if att_u > 1.0 or att_u < 0.0:
			var at_node := e.y if att_u > 1.0 else e.x
			att_u = clampf(att_u, 0.0, 1.0)
			# continue on the edge best aligned with the look direction
			var bestk := -1
			var bestd := 0.2
			for k in edges.size():
				if k == att_edge:
					continue
				var ek := edges[k]
				if ek.x != at_node and ek.y != at_node:
					continue
				var other := ek.y if ek.x == at_node else ek.x
				var dd := (nodes[other] - nodes[at_node]).normalized().dot(look * signf(mv))
				if dd > bestd:
					bestd = dd
					bestk = k
			if bestk >= 0:
				att_edge = bestk
				att_u = 0.0 if edges[bestk].x == at_node else 1.0
	exertion = maxf(exertion, absf(speed) * 0.8)
	# ease onto the rail / back upright (no visible snap in the windows and camera feeds)
	if not rig.basis.is_equal_approx(_upright):
		var hp := head_s().origin
		rig.basis = rig.basis.slerp(_upright, clampf(dt * 3.0, 0.0, 1.0)).orthonormalized()
		rig.origin += hp - head_s().origin
	_snap_to_rail(clampf(dt * 4.0, 0.0, 1.0))
	vel = Vector3.ZERO


func _switch_edge(at_node: int, toward: int) -> void:
	var path := route(at_node, toward)
	if path.size() < 2:
		return
	var nxt := path[1]
	for k in edges.size():
		var ek := edges[k]
		if (ek.x == at_node and ek.y == nxt) or (ek.y == at_node and ek.x == nxt):
			att_edge = k
			att_u = 0.0 if ek.x == at_node else 1.0
			return


func _free_motion(dt: float, inp: Dictionary) -> void:
	var mv: Vector3 = inp.get("move", Vector3.ZERO)
	jet_on = 0.0
	if surface:
		vel += -up * gravity * dt
		var h := rig.origin.dot(up)
		on_ground = h <= ground_h + 0.02
		if on_ground:
			rig.origin += up * (ground_h - h)
			var vn := vel.dot(up)
			if vn < 0.0:
				vel -= up * vn
			var want := (rig.basis * Vector3(mv.x, 0.0, mv.z)).slide(up)
			want = want.limit_length(1.0) * WALK_SPEED
			var hv := vel.slide(up)
			hv = hv.move_toward(want, dt * (4.0 if want.length() > 0.05 else 6.0))
			vel = hv + up * vel.dot(up)
			if bool(inp.get("hop", false)):
				vel += up * HOP_V
				on_ground = false
			exertion = maxf(exertion, hv.length() * 0.9)
	else:
		if mv.length() > 0.05 and gas > 0.0:
			var a := (rig.basis * mv).limit_length(1.0) * JET_ACCEL
			vel += a * dt
			if vel.length() > JET_MAX_V:
				vel = vel.normalized() * JET_MAX_V
			gas = maxf(0.0, gas - mv.length() * dt * 0.35)
			jet_on = clampf(mv.length(), 0.0, 1.0)
			if gas <= 0.0:
				_event("gas_empty", {})
		if bool(inp.get("stop", false)) and gas > 0.0:
			var before := vel.length()
			vel = vel.move_toward(Vector3.ZERO, JET_ACCEL * 2.0 * dt)
			if before > 0.01:
				jet_on = maxf(jet_on, 0.6)
				gas = maxf(0.0, gas - dt * 0.2)
	rig.origin += vel * dt
	if not surface:
		_hull_collide()


## Solid hull: the suit (feet, waist, chest, helmet spheres) can't pass through the fuselage.
## Analytic shape = the same lathe profile the model is built from (EvaScenarios.hull_r / YS),
## so it matches the mesh exactly and costs nothing. Low-speed contact: a soft bump that
## cancels the inward velocity and leaves a gentle push-off (restitution 0.15) plus friction.
const SUIT_R := 0.28
func _hull_collide() -> void:
	var up := rig.basis.y
	for h: float in [0.8, 1.25, 1.6]:   # waist, chest, helmet (legs may brush the skin)
		var p := rig.origin + up * h
		var r := EvaScenarios.hull_r(p.z)
		if r <= 0.0:
			continue
		# open-top cargo bay (doors on the roof): you can reach in; its floor is the limit
		if absf(p.x) < 1.5 and p.z > -1.4 and p.z < 4.4 and p.y > 0.5:
			if p.y < 0.85 + SUIT_R * 0.5:
				rig.origin.y += 0.85 + SUIT_R * 0.5 - p.y
				vel.y = maxf(vel.y, 0.0)
			continue
		var q := Vector2(p.x, p.y / EvaScenarios.YS)
		var d := q.length()
		var lim := r + SUIT_R
		if d >= lim or d < 1e-4:
			continue
		var n := Vector3(q.x / d * EvaScenarios.YS, q.y / d, 0.0).normalized()
		rig.origin += n * (lim - d)
		var vn := vel.dot(n)
		if vn < 0.0:
			vel -= n * vn * 1.15
			vel = vel.lerp(n * vel.dot(n), 0.25)   # scuff: friction along the hull
			if vn < -0.4:
				_event("knock", {"pos": p - n * SUIT_R, "n": n, "hand": 1})


func _tether(_dt: float) -> void:
	if not tether_on:
		tether_used = 0.0
		taut = false
		return
	var w := waist_s()
	var d := w - tether_anchor
	tether_used = d.length()
	var was := taut
	taut = tether_used > tether_len - 0.05
	if tether_used > tether_len:
		var n := d / tether_used
		rig.origin -= n * (tether_used - tether_len)
		var vn := vel.dot(n)
		if vn > 0.0:
			vel -= n * vn * 1.3    # a little bounce back
		if riding:
			riding = false
			grab_kind[0] = ""
			grab_kind[1] = ""
	if taut and not was:
		_event("tether_taut", {"len": tether_len})


# ======================================================================== gestures
func _gestures(dt: float) -> void:
	_wave_cd = maxf(0.0, _wave_cd - dt)
	_knock_cd = maxf(0.0, _knock_cd - dt)
	_palm_cd = maxf(0.0, _palm_cd - dt)
	var hs := head_s()
	var right := hs.basis.x.normalized()
	for i in 2:
		var hp := hand_s(i).origin
		# WAVE: hand above the shoulders, swinging side to side
		var above := (hp - hs.origin).dot(body_up()) > -0.12
		var hist: Array = _wave[i]
		if above and grab_kind[i] == "":
			hist.append([_t, hp.dot(right)])
		while hist.size() > 0 and _t - float(hist[0][0]) > 1.6:
			hist.pop_front()
		if hist.size() > 6 and _wave_cd <= 0.0:
			var rev := 0
			var last_s := 0.0
			var lo := 1e9
			var hi := -1e9
			for k in range(1, hist.size()):
				var dx := float(hist[k][1]) - float(hist[k - 1][1])
				lo = minf(lo, float(hist[k][1]))
				hi = maxf(hi, float(hist[k][1]))
				if absf(dx) > 0.004:
					var sg := signf(dx)
					if last_s != 0.0 and sg != last_s:
						rev += 1
					last_s = sg
			if rev >= 3 and hi - lo > 0.12:
				_wave_cd = 4.0
				hist.clear()
				_event("wave", {"hand": i})
		# KNOCK / HAND ON THE WINDOW: contact with the canopy glass
		var f := ((hp - CANOPY_C) / CANOPY_R).length()
		var on_glass := f < 1.07 and hp.y > CANOPY_C.y + 0.05
		if on_glass:
			_contact_t[i] += dt
			var n := ((hp - CANOPY_C) / (CANOPY_R * CANOPY_R)).normalized()
			var into := -hand_vel[i].dot(n)
			if into > 0.3 and _knock_cd <= 0.0 and _contact_t[i] < 0.12:
				_knock_cd = 0.35
				_event("knock", {"pos": hp, "n": n, "hand": i})
			if _contact_t[i] > 0.7 and _palm_cd <= 0.0:
				_palm_cd = 6.0
				_event("palm", {"pos": hp, "n": n, "hand": i})
		else:
			_contact_t[i] = 0.0


## Nearest point on the canopy glass (for flat-mode knock animation and screenshots).
static func canopy_point(from: Vector3) -> Array:
	# coarse search over the upper glass, then refine (only used for flat knocks / tests)
	var best := Vector3.UP
	var bd := 1e9
	for i in 24:
		for j in 9:
			var az := TAU * i / 24.0
			var el := 0.15 + (PI * 0.5 - 0.15) * j / 8.0
			var u := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
			var d := (CANOPY_C + u * CANOPY_R).distance_to(from)
			if d < bd:
				bd = d
				best = u
	var stp := 0.12
	for k in 30:
		var improved := false
		for dv: Vector3 in [Vector3(stp, 0, 0), Vector3(-stp, 0, 0), Vector3(0, stp, 0), Vector3(0, -stp, 0), Vector3(0, 0, stp), Vector3(0, 0, -stp)]:
			var u2 := (best + dv).normalized()
			if u2.y < 0.15:
				continue
			var d2 := (CANOPY_C + u2 * CANOPY_R).distance_to(from)
			if d2 < bd:
				bd = d2
				best = u2
				improved = true
		if not improved:
			stp *= 0.5
	var p := CANOPY_C + best * CANOPY_R
	var n := (best / CANOPY_R).normalized()
	return [p, n]


# ======================================================================== tasks
func cur_step() -> Dictionary:
	return steps[step] if step < steps.size() else {}


func step_text() -> String:
	var s := cur_step()
	return str(s.get("text", "EVA complete")) if not s.is_empty() else "EVA complete"


func _hand_near(p: Vector3, r: float) -> bool:
	if flat:
		return head_s().origin.distance_to(p) < r + FLAT_REACH
	for i in 2:
		if hand_s(i).origin.distance_to(p) < r:
			return true
	return false


func _steps(dt: float, use: Array) -> void:
	var s := cur_step()
	if s.is_empty():
		return
	var kind := str(s.get("do", ""))
	var at: Vector3 = s.get("at", Vector3.ZERO)
	var r := float(s.get("r", 0.6))
	var ok := false
	match kind:
		"go":
			if flat and s.has("pose"):
				ok = head_s().origin.distance_to(at) < 0.06 and perch
			else:
				ok = head_s().origin.distance_to(at) < r + (0.4 if flat else 0.0) or waist_s().distance_to(at) < r
		"use":
			var near := _hand_near(at, r)
			var pressing := bool(use[0]) or bool(use[1])
			if near and pressing:
				progress += dt
				if fmod(progress, 0.5) < dt:
					_event("tool", {})
			if progress >= float(s.get("hold", 1.5)):
				ok = true
		"pick":
			for it: Dictionary in items:
				if str(it["id"]) == str(s.get("item", "")) and int(it["held"]) >= 0:
					ok = true
		"place":
			for it: Dictionary in items:
				if str(it["id"]) == str(s.get("item", "")) and bool(it["placed"]):
					ok = true
		"collect":
			ok = collected >= int(s.get("count", 1))
		"ride":
			ok = riding and waist_s().distance_to(at) < r
		"grab_arm":
			ok = riding
		"gesture":
			ok = _seen.has(str(s.get("gesture", "")))
		"inside":
			var near2 := waist_s().distance_to(hatch) < r or head_s().origin.distance_to(hatch) < r + (0.5 if flat else 0.0)
			if near2 and (bool(use[0]) or bool(use[1]) or s.get("auto", false)):
				ok = true
	if ok:
		var pts := int(s.get("score", 100))
		score += pts
		for pid: String in (s.get("set", {}) as Dictionary):
			for p: Dictionary in props:
				if str(p.get("id", "")) == pid:
					p["state"] = (s["set"] as Dictionary)[pid]
		_event("step_done", {"step": step, "text": str(s.get("text", "")), "score": pts})
		step += 1
		progress = 0.0
		_seen.clear()
		if step >= steps.size():
			done = true
			score += 300
			_event("eva_done", {"score": score})
		else:
			_event("step", {"step": step, "text": step_text()})


var _seen := {}


func _event(kind: String, data: Dictionary) -> void:
	_ev_id += 1
	events.append([_ev_id, kind, data])
	if kind in ["wave", "knock", "palm"]:
		_seen[kind] = true
	if events.size() > 64:
		events.pop_front()


## Events newer than `after` (the net layer resends the last few until acknowledged).
func events_after(after: int) -> Array:
	var out := []
	for e: Array in events:
		if int(e[0]) > after:
			out.append(e)
	return out


# ======================================================================== suit
func _suit(dt: float, inp: Dictionary) -> void:
	var handwork := (hand_vel[0].length() + hand_vel[1].length()) * 0.5
	exertion = lerpf(exertion, clampf(handwork * 0.8 + vel.length() * 0.5 + jet_on * 0.2, 0.0, 1.5), clampf(dt * 0.8, 0.0, 1.0))
	var hr_target := 76.0 + exertion * 55.0 + (8.0 if taut else 0.0) + sin(_t * 0.37) * 2.5
	heart = lerpf(heart, hr_target, clampf(dt * 0.25, 0.0, 1.0))
	# ~22 min of O2 at rest (game-scaled), more when working hard
	o2 = maxf(0.0, o2 - dt * (0.07 + exertion * 0.05))
	batt = maxf(0.0, batt - dt * (0.035 + (0.03 if lamp else 0.0) + jet_on * 0.02))
	var co2_target := 1.2 + exertion * 2.4
	co2 = lerpf(co2, co2_target, clampf(dt * 0.05, 0.0, 1.0))
	var t_target := (23.5 if in_sun else 18.0) + exertion * 2.0
	suit_temp = lerpf(suit_temp, t_target, clampf(dt * 0.02, 0.0, 1.0))
	if o2 < 25.0 and _o2_warned < 1:
		_o2_warned = 1
		_event("o2_low", {"o2": o2})
	if o2 < 10.0 and _o2_warned < 2:
		_o2_warned = 2
		_event("o2_critical", {"o2": o2})
	if o2 <= 0.0 and failed == "":
		failed = "o2"
		_event("o2_out", {})
	if bool(inp.get("ptt", false)):
		pass


# ======================================================================== network
## Compact state for the other process (Godot binary var encoding over UDP).
func to_net() -> Dictionary:
	var its := []
	for it: Dictionary in items:
		its.append([it["id"], it["pos"], it["basis"], it["held"], it["placed"], it["gone"]])
	var ps := []
	for p: Dictionary in props:
		ps.append([p.get("id", ""), p.get("state", "")])
	return {"rig": rig, "vel": vel, "head": head, "hands": [hands[0], hands[1]], "hp": [hand_pose[0], hand_pose[1]], "hc": [hand_curl[0], hand_curl[1]],
		"step": step, "prog": progress, "col": collected, "riding": riding, "lamp": lamp, "jet": jet_on,
		"suit": [o2, batt, co2, suit_temp, heart, gas, tether_used, exertion], "taut": taut, "done": done,
		"failed": failed, "score": score, "time": time_out, "items": its, "props": ps, "ground": on_ground, "perch": perch}


func from_net(d: Dictionary) -> void:
	rig = d.get("rig", rig)
	vel = d.get("vel", vel)
	head = d.get("head", head)
	var hs: Array = d.get("hands", [])
	if hs.size() == 2:
		hands[0] = hs[0]
		hands[1] = hs[1]
	var hc: Array = d.get("hc", [])
	if hc.size() == 2:
		hand_curl[0] = hc[0]
		hand_curl[1] = hc[1]
	var hp: Array = d.get("hp", [])
	if hp.size() == 2:
		hand_pose[0] = str(hp[0])
		hand_pose[1] = str(hp[1])
	step = int(d.get("step", step))
	perch = bool(d.get("perch", perch))
	progress = float(d.get("prog", progress))
	collected = int(d.get("col", collected))
	riding = bool(d.get("riding", riding))
	lamp = bool(d.get("lamp", lamp))
	jet_on = float(d.get("jet", 0.0))
	var su: Array = d.get("suit", [])
	if su.size() >= 8:
		o2 = su[0]
		batt = su[1]
		co2 = su[2]
		suit_temp = su[3]
		heart = su[4]
		gas = su[5]
		tether_used = su[6]
		exertion = su[7]
	taut = bool(d.get("taut", false))
	done = bool(d.get("done", false))
	failed = str(d.get("failed", ""))
	score = int(d.get("score", 0))
	time_out = float(d.get("time", time_out))
	on_ground = bool(d.get("ground", false))
	var its: Array = d.get("items", [])
	for k in mini(its.size(), items.size()):
		var a: Array = its[k]
		var it: Dictionary = items[k]
		it["pos"] = a[1]
		it["basis"] = a[2]
		it["held"] = a[3]
		it["placed"] = a[4]
		it["gone"] = a[5]
	var ps: Array = d.get("props", [])
	for k in mini(ps.size(), props.size()):
		(props[k] as Dictionary)["state"] = (ps[k] as Array)[1]


## Pose snapshot for the avatar (and its interpolation buffer).
func pose() -> Dictionary:
	return {"head": head_s(), "l": hand_s(0), "r": hand_s(1), "hp": [hand_pose[0], hand_pose[1]], "hc": [hand_curl[0], hand_curl[1]],
		"up": body_up(), "vel": vel, "lamp": lamp, "jet": jet_on, "riding": riding, "ground": on_ground}
