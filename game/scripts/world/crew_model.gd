class_name CrewModel
extends Node3D
## The two kids in the crew-deck seats (Pilot left, Ops right), child-sized, in white flight
## suits with open-visor helmets. Seen through the windows from outside (VR spacewalker, EVA
## helmet cam, chase cams); hidden from the cockpit's own window views (ship layer).
## Idle: slow look-around + breathing. WAVE (kids' console button or board button
## wave_pilot / wave_ops): the outer arm waves for ~2.5 s. State: Game.crew_wave (seconds left).

const SEATS := [Vector3(-0.55, 0.3, -5.05), Vector3(0.55, 0.3, -5.05)]
var kids: Array = []   # {root, head, sh, el, phase}
var _t := 0.0


func _ready() -> void:
	var suit := ProcGen.mat(Color(0.95, 0.95, 0.93), 0.0, 0.7)
	var black := ProcGen.mat(Color(0.08, 0.08, 0.09), 0.2, 0.5)
	var seat_m := ProcGen.mat(Color(0.12, 0.12, 0.13), 0.1, 0.8)
	var skin := ProcGen.mat(Color(0.93, 0.76, 0.64), 0.0, 0.7)
	var accent := [ProcGen.mat(Color(0.15, 0.4, 0.95), 0.0, 0.6), ProcGen.mat(Color(0.95, 0.45, 0.1), 0.0, 0.6)]
	for i in 2:
		var root := Node3D.new()
		root.position = SEATS[i]
		add_child(root)
		# seat: pan + reclined back + headrest
		root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.5, 0.08, 0.5)), seat_m, Vector3(0, 0.1, 0)))
		root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.5, 0.8, 0.08)), seat_m, Vector3(0, 0.5, 0.28), Vector3(-0.25, 0, 0)))
		# body (child: ~1.3 m tall standing)
		root.add_child(ProcGen.mesh_node(_cap(0.13, 0.48), suit, Vector3(0, 0.42, 0.12), Vector3(-0.2, 0, 0)))
		root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.22, 0.06, 0.02)), accent[i], Vector3(0, 0.52, 0.0), Vector3(-0.2, 0, 0)))
		for sx: float in [-1.0, 1.0]:   # thighs + shins (seated)
			root.add_child(ProcGen.mesh_node(_cap(0.06, 0.34), suit, Vector3(sx * 0.08, 0.2, -0.12), Vector3(PI * 0.5, 0, 0)))
			root.add_child(ProcGen.mesh_node(_cap(0.055, 0.3), suit, Vector3(sx * 0.08, 0.05, -0.3)))
			root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.08, 0.06, 0.14)), black, Vector3(sx * 0.08, -0.1, -0.33)))
		var head := Node3D.new()
		head.position = Vector3(0, 0.74, 0.06)
		root.add_child(head)
		head.add_child(ProcGen.mesh_node(ProcGen.sphere(0.085, 16, 8), skin))
		head.add_child(ProcGen.mesh_node(ProcGen.sphere(0.075, 6, 4), black, Vector3(0, 0.03, 0.02), Vector3.ZERO, Vector3(1.15, 0.9, 1.1)))   # hair
		var helm := ProcGen.mat(Color(0.97, 0.97, 0.97), 0.1, 0.4)
		helm.cull_mode = BaseMaterial3D.CULL_DISABLED
		# helmet shell open at the front (visor up): a sphere pushed back
		head.add_child(ProcGen.mesh_node(ProcGen.sphere(0.13, 16, 8), helm, Vector3(0, 0.02, 0.05), Vector3.ZERO, Vector3(1.0, 1.0, 0.75)))
		head.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.2, 0.05, 0.08)), black, Vector3(0, 0.1, -0.06)))   # visor (raised)
		var arms: Array = []
		for sx: float in [-1.0, 1.0]:
			var sh := Node3D.new()
			sh.position = Vector3(sx * 0.17, 0.58, 0.08)
			root.add_child(sh)
			sh.add_child(ProcGen.mesh_node(_cap(0.045, 0.24), suit, Vector3(0, -0.1, 0)))
			var el := Node3D.new()
			el.position = Vector3(0, -0.2, 0)
			sh.add_child(el)
			el.add_child(ProcGen.mesh_node(_cap(0.04, 0.22), suit, Vector3(0, -0.1, 0)))
			el.add_child(ProcGen.mesh_node(ProcGen.sphere(0.04, 10, 6), black, Vector3(0, -0.22, 0)))   # glove
			arms.append([sh, el])
		# the window-side arm waves (Pilot: left arm, Ops: right arm)
		var outer: Array = arms[0] if i == 0 else arms[1]
		kids.append({"root": root, "head": head, "arms": arms, "outer": outer, "phase": i * 2.3, "w": 0.0})


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return c


func animate(waves: Array, dt: float) -> void:
	_t += dt
	for i in kids.size():
		var k: Dictionary = kids[i]
		var ph: float = k["phase"]
		var head: Node3D = k["head"]
		# idle look-around: slow, layered sines + occasional glance out of the side window
		var glance := smoothstep(0.7, 1.0, sin(_t * 0.13 + ph * 1.7)) * (-0.8 if i == 0 else 0.8)
		head.rotation = Vector3(0.12 * sin(_t * 0.31 + ph) - 0.05, 0.35 * sin(_t * 0.23 + ph) + glance, 0.05 * sin(_t * 0.17 + ph))
		(k["root"] as Node3D).scale = Vector3(1, 1.0 + 0.006 * sin(_t * 1.6 + ph), 1)
		var want := 1.0 if i < waves.size() and float(waves[i]) > 0.0 else 0.0
		k["w"] = move_toward(float(k["w"]), want, dt * 4.0)
		var w: float = k["w"]
		var sx := -1.0 if i == 0 else 1.0
		var arms: Array = k["arms"]
		for a in 2:
			var sh: Node3D = arms[a][0]
			var el: Node3D = arms[a][1]
			var rest := Vector3(-0.5, 0, 0)   # hands on lap
			if arms[a] == k["outer"] and w > 0.0:
				var up := Vector3(0.0, 0.0, sx * 2.5)
				sh.rotation = rest.lerp(up, w)
				el.rotation = Vector3(0, 0, sx * (0.3 + 0.45 * sin(_t * 9.0)) * w)
				head.rotation.y = lerpf(head.rotation.y, sx * 0.9, w)   # look out at the spacewalker
			else:
				sh.rotation = rest
				el.rotation = Vector3(-0.9, 0, 0)
