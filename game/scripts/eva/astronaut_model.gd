class_name AstronautModel
extends Node3D
## Procedural spacewalker (white EMU-style suit, gold visor, helmet lamps, PLSS backpack with a
## SAFER jetpack, red commander stripes, a little Canadian flag patch), posed every frame from
## head + both hand transforms (headset + controllers, or FlatControl):
##  - torso hangs under the head, turning with it (smoothed), leaning with body "up";
##  - arms: two-bone IK from the shoulders to the gloves, elbows pointing down / out;
##  - gloves: open, fist (gripping) or pointing index finger;
##  - legs: relaxed zero-g bend, a walking stride on the Moon.
## Helmet meshes live on Eva.EVA_HEAD_LAYER and the torso / legs on Eva.EVA_BODY_LAYER so the
## wearer's own camera (VR / helmet cam) can hide them; everyone else sees the whole suit.

const UPPER := 0.30
const LOWER := 0.29

var suit_mat: StandardMaterial3D
var parts := {}            # name -> MeshInstance3D
var lamps: Array[SpotLight3D] = []
var lamp_glow: Array[MeshInstance3D] = []
var jet_glow: MeshInstance3D
var fingers := {}          # "l"/"r" -> {curl: Node3D, index: Node3D}
var _fwd := Vector3(0, 0, -1)
var _walk := 0.0
var _t := 0.0
var self_view := false     # true in the wearer's own process: hide helmet / body from them


func _ready() -> void:
	suit_mat = ProcGen.mat(Color(0.93, 0.93, 0.9), 0.0, 0.78)
	var soft := ProcGen.mat(Color(0.86, 0.86, 0.83), 0.0, 0.85)
	var grey := ProcGen.mat(Color(0.55, 0.56, 0.58), 0.3, 0.5)
	var dark := ProcGen.mat(Color(0.15, 0.15, 0.16), 0.4, 0.5)
	var red := ProcGen.mat(Color(0.75, 0.08, 0.08), 0.0, 0.6)
	var visor := ProcGen.mat(Color(0.95, 0.72, 0.3), 1.0, 0.06)
	visor.rim_enabled = true
	visor.rim = 0.6
	var glove := ProcGen.mat(Color(0.8, 0.8, 0.78), 0.0, 0.8)
	var b := Eva.EVA_BODY_LAYER
	var h := Eva.EVA_HEAD_LAYER
	_part("torso", _capsule(0.2, 0.62), suit_mat, b)
	_part("hut", ProcGen.box(Vector3(0.44, 0.22, 0.3)), soft, b)
	_part("plss", ProcGen.box(Vector3(0.48, 0.62, 0.22)), suit_mat, b)
	_part("safer", ProcGen.box(Vector3(0.5, 0.16, 0.26)), grey, b)
	_part("dcm", ProcGen.box(Vector3(0.26, 0.12, 0.1)), grey, b)
	_part("pelvis", ProcGen.box(Vector3(0.34, 0.2, 0.24)), soft, b)
	_part("patch", ProcGen.box(Vector3(0.09, 0.05, 0.005)), ProcGen.mat(Color(0.85, 0.1, 0.1), 0.0, 0.7), b)
	_part("patch_w", ProcGen.box(Vector3(0.045, 0.05, 0.006)), ProcGen.mat(Color(0.95, 0.95, 0.95), 0.0, 0.7), b)
	_part("helmet", ProcGen.sphere(0.17, 24, 12), suit_mat, h)
	_part("visor", ProcGen.sphere(0.158, 24, 12), visor, h)
	_part("neckring", ProcGen.torus(0.12, 0.165, 24), grey, h)
	for s: String in ["l", "r"]:
		_part("up_" + s, _capsule(0.068, UPPER + 0.08), suit_mat, 1)
		_part("lo_" + s, _capsule(0.062, LOWER + 0.06), suit_mat, 1)
		_part("elb_" + s, ProcGen.sphere(0.07, 12, 6), soft, 1)
		_part("sh_" + s, ProcGen.sphere(0.095, 12, 6), soft, b)
		_part("cuff_" + s, ProcGen.cyl(0.065, 0.065, 0.06, 12), grey, 1)
		_part("th_" + s, _capsule(0.09, 0.5), suit_mat, b)
		_part("sh2_" + s, _capsule(0.08, 0.48), suit_mat, b)
		_part("stripe_" + s, ProcGen.cyl(0.093, 0.093, 0.08, 12), red, b)
		_part("knee_" + s, ProcGen.sphere(0.085, 12, 6), soft, b)
		_part("boot_" + s, ProcGen.box(Vector3(0.13, 0.12, 0.27)), dark, b)
		# glove: palm + curled finger block + index finger + thumb
		var g := Node3D.new()
		g.name = "glove_" + s
		add_child(g)
		parts["glove_" + s] = g
		g.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.09, 0.035, 0.1)), glove))
		var curl := Node3D.new()
		curl.position = Vector3(0.012, 0, -0.05)
		g.add_child(curl)
		curl.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.06, 0.03, 0.08)), glove, Vector3(0, 0, -0.04)))
		var idx := Node3D.new()
		idx.position = Vector3(-0.03 if s == "r" else 0.03, 0.0, -0.05)
		g.add_child(idx)
		idx.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.022, 0.025, 0.085)), glove, Vector3(0, 0, -0.042)))
		var th := ProcGen.mesh_node(ProcGen.box(Vector3(0.024, 0.024, 0.06)), glove, Vector3(-0.05 if s == "r" else 0.05, 0.0, -0.02), Vector3(0, 0.6 if s == "r" else -0.6, 0))
		g.add_child(th)
		fingers[s] = {"curl": curl, "index": idx}
	# helmet lamps (EMU style, either side of the helmet)
	for sx: float in [-1.0, 1.0]:
		var lg := ProcGen.mesh_node(ProcGen.cyl(0.03, 0.03, 0.06, 10), ProcGen.glow_mat(Color(1.0, 0.95, 0.85), 4.0), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
		lg.layers = h
		add_child(lg)
		lamp_glow.append(lg)
		var sp := SpotLight3D.new()
		sp.spot_range = 14.0
		sp.spot_angle = 26.0
		sp.light_energy = 0.0
		sp.light_color = Color(1.0, 0.95, 0.85)
		sp.shadow_enabled = false
		add_child(sp)
		lamps.append(sp)
	jet_glow = ProcGen.mesh_node(ProcGen.cyl(0.01, 0.07, 0.25, 8), ProcGen.glow_mat(Color(0.7, 0.85, 1.0), 2.5))
	jet_glow.visible = false
	add_child(jet_glow)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 14
	c.rings = 4
	return c


func _part(nm: String, mesh: Mesh, m: Material, layer: int) -> MeshInstance3D:
	var mi := ProcGen.mesh_node(mesh, m)
	mi.name = nm
	mi.layers = layer
	add_child(mi)
	parts[nm] = mi
	return mi


func _mi(nm: String) -> Node3D:
	return parts[nm]


## Put a Y-aligned part between two points (capsules / cylinders are built along Y).
func _bone(nm: String, a: Vector3, b: Vector3, side_hint: Vector3 = Vector3.FORWARD) -> void:
	var n := _mi(nm)
	var y := b - a
	var L := y.length()
	if L < 1e-4:
		return
	y /= L
	var x := y.cross(side_hint)
	if x.length() < 1e-3:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	n.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


static func ik(shoulder: Vector3, target: Vector3, pole: Vector3, a: float, b: float) -> Vector3:
	var d := target - shoulder
	var L := clampf(d.length(), 0.05, a + b - 0.002)
	var dir := d.normalized() if d.length() > 1e-4 else Vector3.DOWN
	var ca := clampf((a * a + L * L - b * b) / (2.0 * a * L), -1.0, 1.0)
	var perp := (pole - shoulder).slide(dir)
	perp = perp.normalized() if perp.length() > 1e-4 else dir.cross(Vector3.RIGHT).normalized()
	return shoulder + dir * a * ca + perp * a * sqrt(1.0 - ca * ca)


## pose: {head, l, r: Transform3D (ship frame), hp: [l, r] hand poses, up, vel, lamp, jet, ground}
func apply_pose(p: Dictionary, dt: float) -> void:
	if p.is_empty():
		visible = false
		return
	visible = true
	_t += dt
	var H: Transform3D = p["head"]
	var up_b: Vector3 = p.get("up", Vector3.UP)
	var hup := H.basis.y.normalized()
	var tu := (up_b * 0.65 + hup * 0.35).normalized()
	var hf := (-H.basis.z).slide(tu)
	if hf.length() > 0.1:
		_fwd = _fwd.slerp(hf.normalized(), clampf(dt * 4.0, 0.0, 1.0)) if dt < 0.5 else hf.normalized()
	var fwd := _fwd.slide(tu).normalized()
	var right := fwd.cross(tu).normalized()
	var neck := H.origin - tu * 0.17 - fwd * 0.03
	var chest := neck - tu * 0.27
	var pelvis := neck - tu * 0.66
	var tb := Basis(right, tu, -fwd)
	_mi("torso").transform = Transform3D(tb, chest - tu * 0.05)
	_mi("hut").transform = Transform3D(tb, chest + tu * 0.08)
	_mi("plss").transform = Transform3D(tb, chest - fwd * 0.26 - tu * 0.02)
	_mi("safer").transform = Transform3D(tb, chest - fwd * 0.27 - tu * 0.39)
	_mi("dcm").transform = Transform3D(tb, chest + fwd * 0.22 + tu * 0.02)
	_mi("pelvis").transform = Transform3D(tb, pelvis)
	_mi("patch").transform = Transform3D(Basis(fwd, tu, right), neck - tu * 0.18 - right * 0.235)
	_mi("patch_w").transform = Transform3D(Basis(fwd, tu, right), neck - tu * 0.18 - right * 0.237)
	_mi("helmet").transform = Transform3D(H.basis, H.origin + hup * 0.01 - H.basis.z * -0.015)
	_mi("visor").transform = Transform3D(H.basis.scaled(Vector3(1.0, 0.82, 0.8)), H.origin - H.basis.z * 0.045 + hup * 0.005)
	_mi("neckring").transform = Transform3D(tb, neck + tu * 0.02)
	# lamps
	var lamp_on := bool(p.get("lamp", false))
	for k in 2:
		var sx := -1.0 if k == 0 else 1.0
		var lp := H.origin + H.basis.x * (0.17 * sx) + hup * 0.06 - H.basis.z * 0.02
		lamp_glow[k].transform = Transform3D(H.basis * Basis(Vector3.RIGHT, PI * 0.5), lp)
		lamp_glow[k].visible = true
		lamps[k].transform = Transform3D(H.basis, lp - H.basis.z * 0.04)
		lamps[k].light_energy = 2.2 if lamp_on else 0.0
		(lamp_glow[k] as MeshInstance3D).transparency = 0.0 if lamp_on else 0.7
	# arms
	for s: String in ["l", "r"]:
		var sx2 := -1.0 if s == "l" else 1.0
		var sh := neck - tu * 0.1 + right * (0.22 * sx2)
		var hand: Transform3D = p[s]
		var wrist := hand.origin + hand.basis.z * 0.06
		var pole := sh - tu * 0.5 + right * (0.25 * sx2) - fwd * 0.2
		var elbow := ik(sh, wrist, pole, UPPER, LOWER)
		_mi("sh_" + s).position = sh
		_bone("up_" + s, sh, elbow, fwd)
		_bone("lo_" + s, elbow, wrist, fwd)
		_mi("elb_" + s).position = elbow
		_bone("cuff_" + s, wrist - (wrist - elbow).normalized() * 0.03, wrist + (wrist - elbow).normalized() * 0.03, fwd)
		_mi("glove_" + s).transform = hand
		var hp: Array = p.get("hp", ["open", "open"])
		var st := str(hp[0 if s == "l" else 1])
		var f: Dictionary = fingers[s]
		(f["curl"] as Node3D).rotation.x = -1.4 if st != "open" else -0.15
		(f["index"] as Node3D).rotation.x = -1.4 if st == "fist" else (0.0 if st == "point" else -0.15)
	# legs
	var v: Vector3 = p.get("vel", Vector3.ZERO)
	var on_ground := bool(p.get("ground", false))
	var stride := 0.0
	if on_ground:
		_walk += v.length() * dt * 4.2
		stride = clampf(v.length() / 1.3, 0.0, 1.0)
	var trail := -v.slide(tu).limit_length(0.6) * 0.15
	for s: String in ["l", "r"]:
		var sx3 := -1.0 if s == "l" else 1.0
		var hip := pelvis + right * (0.11 * sx3) - tu * 0.06
		var ph := sin(_walk + (0.0 if s == "l" else PI)) * stride
		var knee := hip - tu * 0.45 + fwd * (0.12 + ph * 0.25) + trail + right * (0.03 * sx3)
		var foot := knee - tu * 0.44 - fwd * (0.06 - ph * 0.1) + trail * 1.5
		if not on_ground:
			knee += fwd * 0.05 * sin(_t * 0.7 + sx3)
		_bone("th_" + s, hip, knee, right)
		_bone("stripe_" + s, hip.lerp(knee, 0.45), hip.lerp(knee, 0.62), right)
		_mi("knee_" + s).position = knee
		_bone("sh2_" + s, knee, foot, right)
		_mi("boot_" + s).transform = Transform3D(tb, foot - tu * 0.05 + fwd * 0.05)
	# jetpack puff
	var jet := float(p.get("jet", 0.0))
	jet_glow.visible = jet > 0.05
	if jet_glow.visible:
		jet_glow.transform = Transform3D(Basis(right, -tu, fwd), chest - fwd * 0.3 - tu * 0.55)
		jet_glow.scale = Vector3.ONE * (0.6 + jet * 0.8 + 0.2 * sin(_t * 40.0))
