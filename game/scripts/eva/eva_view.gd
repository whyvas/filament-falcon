class_name EvaView
extends Node3D
## Draws the spacewalk in the shared 3D world (cockpit windows, docking / arm / chase cameras,
## helmet cam, the VR client): handrails, worksite props, items, the tether cable, frosty
## handprints / knock ripples on the canopy, and the astronaut avatar. Everything is in the
## ship frame: this node carries the Falcon's attitude (the ship sits at the world origin).
## NOT a child of the ship model, so the cockpit windows (which hide the hull) still see it.

var avatar: AstronautModel
var client_sim: EvaSim = null       # VR client: draw our own local sim (no interpolation)
var _scen_key := ""
var _built: Node3D
var _prop_nodes := {}
var _item_nodes := {}
var _tether: MeshInstance3D
var _tether_mesh: ImmediateMesh
var _tether_mat: StandardMaterial3D
var _prints: Array = []             # [{node, t, mat}]
var _t := 0.0
var _pose := {}


## The avatar pose drawn this frame (ship frame), {} when nobody is outside.
func current_pose() -> Dictionary:
	return _pose if avatar.visible else {}


func _ready() -> void:
	name = "Eva"
	avatar = AstronautModel.new()
	avatar.visible = false
	add_child(avatar)
	_tether_mesh = ImmediateMesh.new()
	_tether = MeshInstance3D.new()
	_tether.mesh = _tether_mesh
	_tether_mat = ProcGen.mat(Color(0.95, 0.95, 0.9), 0.0, 0.7)
	_tether.material_override = _tether_mat
	_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tether)
	if Eva.role == "server":
		Eva.eva_event.connect(_on_event)


func _src() -> EvaSim:
	if client_sim != null:
		return client_sim
	return Eva.sim if Eva.active else null


func _process(dt: float) -> void:
	_t += dt
	transform = Transform3D(Game.sim.basis, Vector3.ZERO)
	var sim := _src()
	if sim == null:
		_pose = {}
		avatar.visible = false
		_tether.visible = false
		if _built:
			_built.queue_free()
			_built = null
			_scen_key = ""
		_fade_prints(dt)
		return
	var key := str(sim.scen.get("id", "")) + str(sim.scen.get("hatch", ""))
	if key != _scen_key:
		_build(sim)
		_scen_key = key
	var pose: Dictionary = sim.pose() if client_sim != null else Eva.avatar_pose()
	_pose = pose
	avatar.apply_pose(pose, dt)
	_update_items(sim)
	_update_tether(sim, pose)
	_fade_prints(dt)


# ======================================================================== build
func _build(sim: EvaSim) -> void:
	if _built:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Scenario"
	add_child(_built)
	_prop_nodes.clear()
	_item_nodes.clear()
	var rail_mat := ProcGen.mat(Color(0.95, 0.72, 0.15), 0.4, 0.45)
	for i in sim.rails_a.size():
		var a := sim.rails_a[i]
		var b := sim.rails_b[i]
		var mi := ProcGen.mesh_node(ProcGen.cyl(0.022, 0.022, 1.0, 8), rail_mat)
		_place_seg(mi, a, b)
		_built.add_child(mi)
		# standoff feet toward the hull every ~0.7 m
		var n := int(a.distance_to(b) / 0.7) + 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(maxi(n, 1)))
			var toward := Vector3(-p.x, -p.y, 0.0).normalized() * 0.1
			var sf := ProcGen.mesh_node(ProcGen.cyl(0.012, 0.012, 1.0, 6), rail_mat)
			_place_seg(sf, p, p + toward)
			_built.add_child(sf)
	for p: Dictionary in sim.props:
		var node := _make_prop(p)
		node.transform = Transform3D(p.get("basis", Basis.IDENTITY), p["pos"])
		_built.add_child(node)
		_prop_nodes[str(p["id"])] = node
	for it: Dictionary in sim.items:
		var inode := _make_item(str(it["kind"]))
		_built.add_child(inode)
		_item_nodes[str(it["id"])] = inode


static func _place_seg(mi: Node3D, a: Vector3, b: Vector3) -> void:
	var y := b - a
	var L := y.length()
	if L < 1e-4:
		return
	var yn := y / L
	var x := yn.cross(Vector3.FORWARD if absf(yn.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, yn, x.cross(yn)).scaled_local(Vector3(1, L, 1)), (a + b) * 0.5)


func _make_prop(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var grey := ProcGen.mat(Color(0.55, 0.56, 0.58), 0.6, 0.4)
	match str(p["kind"]):
		"toolbox":
			root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.36, 0.22, 0.28)), ProcGen.mat(Color(0.95, 0.5, 0.1), 0.1, 0.6)))
			root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.2, 0.03, 0.03)), grey, Vector3(0, 0.13, 0)))
		"boulder":
			var r := float(p.get("r", 0.85))
			var rock := ProcGen.mesh_node(ProcGen.rock_mesh(42, 0.42), Models.rock_material())
			rock.scale = Vector3.ONE * r
			root.add_child(rock)
			var scar := ProcGen.mesh_node(ProcGen.sphere(0.12, 10, 5), ProcGen.glow_mat(Color(0.75, 0.95, 1.0), 1.5), Vector3(-0.45, 0.25, 0.7) * r)
			scar.name = "Scar"
			scar.visible = false
			root.add_child(scar)
		"antenna_mount":
			root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.34, 0.08, 0.34)), grey))
			var broken := Node3D.new()
			broken.name = "Broken"
			var mast := ProcGen.mesh_node(ProcGen.cyl(0.03, 0.03, 0.8, 8), grey, Vector3(0.12, 0.38, 0), Vector3(0, 0, -0.55))
			broken.add_child(mast)
			broken.add_child(ProcGen.mesh_node(ProcGen.cyl(0.22, 0.04, 0.12, 16), ProcGen.mat(Color(0.5, 0.5, 0.5), 0.2, 0.7), Vector3(0.36, 0.66, 0.05), Vector3(0.8, 0, -1.6)))
			root.add_child(broken)
			var ok := ProcGen.mesh_node(ProcGen.sphere(0.05, 8, 4), ProcGen.glow_mat(Color(0.2, 1.0, 0.35), 6.0), Vector3(0, 0.1, 0.2))
			ok.name = "Ok"
			ok.visible = false
			root.add_child(ok)
		"sample_box":
			root.add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.5, 0.35, 0.4)), ProcGen.mat(Color(0.75, 0.75, 0.78), 0.8, 0.3), Vector3(0, 0.175, 0)))
	return root


func _make_item(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"antenna":
			var m := ProcGen.mat(Color(0.9, 0.9, 0.92), 0.5, 0.35)
			root.add_child(ProcGen.mesh_node(ProcGen.cyl(0.03, 0.035, 0.9, 10), m, Vector3(0, 0.45, 0)))
			root.add_child(ProcGen.mesh_node(ProcGen.cyl(0.26, 0.05, 0.14, 20), ProcGen.mat(Color(0.97, 0.97, 0.95), 0.1, 0.5), Vector3(0, 0.85, 0), Vector3(0.5, 0, 0)))
			var tip := ProcGen.mesh_node(ProcGen.sphere(0.035, 8, 4), ProcGen.glow_mat(Color(1.0, 0.25, 0.2), 6.0), Vector3(0, 0.95, 0))
			tip.set_meta("blink", true)
			root.add_child(tip)
		"beacon":
			root.add_child(ProcGen.mesh_node(ProcGen.cyl(0.06, 0.07, 0.22, 12), ProcGen.mat(Color(0.95, 0.85, 0.1), 0.3, 0.5)))
			var bl := ProcGen.mesh_node(ProcGen.sphere(0.045, 8, 4), ProcGen.glow_mat(Color(1.0, 0.15, 0.1), 8.0), Vector3(0, 0.14, 0))
			bl.set_meta("blink", true)
			root.add_child(bl)
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.2, 0.1)
			ol.omni_range = 3.0
			ol.light_energy = 0.0
			ol.position = Vector3(0, 0.2, 0)
			ol.set_meta("blink_light", true)
			root.add_child(ol)
		"flag":
			root.add_child(ProcGen.mesh_node(ProcGen.cyl(0.015, 0.015, 1.9, 8), ProcGen.mat(Color(0.85, 0.85, 0.85), 0.8, 0.3), Vector3(0, 0.35, 0)))
			root.add_child(ProcGen.mesh_node(ProcGen.cyl(0.008, 0.008, 0.8, 6), ProcGen.mat(Color(0.85, 0.85, 0.85), 0.8, 0.3), Vector3(0.4, 1.28, 0), Vector3(0, 0, PI * 0.5)))
			var q := QuadMesh.new()
			q.size = Vector2(0.8, 0.4)
			var fm := StandardMaterial3D.new()
			fm.albedo_texture = flag_texture()
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED
			fm.roughness = 0.9
			root.add_child(ProcGen.mesh_node(q, fm, Vector3(0.41, 1.07, 0)))
		"rock":
			var rk := ProcGen.mesh_node(ProcGen.rock_mesh(9, 0.45), Models.rock_material())
			rk.scale = Vector3.ONE * 0.13
			root.add_child(rk)
	return root


## Canadian flag (red-white-red, 1:2:1, with a simple 11-point maple leaf), procedural.
static func flag_texture() -> ImageTexture:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var red := Color(0.84, 0.09, 0.12)
	img.fill(Color(1, 1, 1))
	for y in h:
		for x in w:
			if x < w / 4 or x >= w * 3 / 4:
				img.set_pixel(x, y, red)
	# maple leaf as a star-ish polar shape + stem
	var cx := w * 0.5
	var cy := h * 0.47
	for y in h:
		for x in range(w / 4, w * 3 / 4):
			var dx := (x - cx) / 14.0
			var dy := (y - cy) / 14.0
			var a := atan2(dx, -dy)
			var r := sqrt(dx * dx + dy * dy)
			var lobes := 0.62 + 0.3 * absf(cos(a * 2.5)) + 0.12 * absf(cos(a * 5.5))
			if r < lobes and dy < 0.75:
				img.set_pixel(x, y, red)
			if absf(dx) < 0.07 and dy > 0.3 and dy < 1.25:
				img.set_pixel(x, y, red)
	return ImageTexture.create_from_image(img)


# ======================================================================== per frame
func _update_items(sim: EvaSim) -> void:
	for it: Dictionary in sim.items:
		var n: Node3D = _item_nodes.get(str(it["id"]))
		if n == null:
			continue
		n.visible = not bool(it["gone"])
		var b: Basis = it.get("basis", Basis.IDENTITY)
		if str(it["kind"]) == "flag" and bool(it["placed"]):
			b = Basis.looking_at(Vector3(1, 0, 0).slide(sim.up), sim.up) if sim.surface else b
		n.transform = Transform3D(b.orthonormalized(), it["pos"])
		for c in n.get_children():
			if c.has_meta("blink"):
				(c as Node3D).visible = fmod(_t, 1.0) < 0.35
			if c.has_meta("blink_light"):
				(c as OmniLight3D).light_energy = 1.5 if fmod(_t, 1.0) < 0.35 else 0.0
	for p: Dictionary in sim.props:
		var pn: Node3D = _prop_nodes.get(str(p["id"]))
		if pn == null:
			continue
		var st := str(p.get("state", ""))
		var br := pn.get_node_or_null("Broken")
		if br:
			(br as Node3D).visible = st == "broken"
		var ok := pn.get_node_or_null("Ok")
		if ok:
			(ok as Node3D).visible = st == "fixed" and fmod(_t, 1.2) < 0.6
		var scar := pn.get_node_or_null("Scar")
		if scar:
			(scar as Node3D).visible = st == "sampled"


func _update_tether(sim: EvaSim, pose: Dictionary) -> void:
	_tether.visible = sim.tether_on and not pose.is_empty()
	if not _tether.visible:
		return
	var a := sim.tether_anchor
	var H: Transform3D = pose["head"]
	var up_b: Vector3 = pose.get("up", Vector3.UP)
	var clip := H.origin - up_b * 0.7 - H.basis.x * 0.15
	var d := clip - a
	var L := d.length()
	var slack := sqrt(maxf((L * 1.15 + 0.6) * (L * 1.15 + 0.6) - L * L, 0.0)) * 0.22 * (0.0 if sim.taut else 1.0)
	var side := d.cross(Vector3.UP)
	side = side.normalized() if side.length() > 1e-3 else Vector3.RIGHT
	var bow := (side * 0.6 + Vector3(a.x, a.y, 0).normalized() * 0.8).normalized() * slack
	_tether_mesh.clear_surfaces()
	_tether_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 24
	var sides := 5
	var r := 0.012
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var u := float(i) / segs
		var w := sin(u * PI) + 0.15 * sin(u * PI * 3.0 + _t * 0.6)
		pts.append(a.lerp(clip, u) + bow * w)
	for i in segs:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var ax := (p1 - p0).normalized()
		var n0 := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var n1 := ax.cross(n0)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var o0 := (n0 * cos(a0) + n1 * sin(a0)) * r
			var o1 := (n0 * cos(a1) + n1 * sin(a1)) * r
			for v: Vector3 in [p0 + o0, p1 + o0, p1 + o1, p0 + o0, p1 + o1, p0 + o1]:
				_tether_mesh.surface_set_normal((v - p0).normalized())
				_tether_mesh.surface_add_vertex(v)
	_tether_mesh.surface_end()


# ======================================================================== window FX
func _on_event(kind: String, data: Dictionary) -> void:
	if kind in ["knock", "palm"]:
		add_print(data.get("pos", Vector3.ZERO), data.get("n", Vector3.UP), kind == "palm")


## Frosty glove print on the canopy (+ a ring for a knock), fades in ~20 s.
func add_print(p: Vector3, n: Vector3, palm: bool) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.2) if palm else Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _print_tex(palm)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.85)
	var mi := ProcGen.mesh_node(q, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := Vector3.UP.slide(n)
	up = up.normalized() if up.length() > 0.05 else Vector3.FORWARD
	mi.transform = Transform3D(Basis.looking_at(-n, up), p + n * 0.012)
	add_child(mi)
	_prints.append({"node": mi, "t": 0.0, "mat": m})
	if _prints.size() > 12:
		(_prints[0]["node"] as Node).queue_free()
		_prints.pop_front()


func _fade_prints(dt: float) -> void:
	for pr: Dictionary in _prints.duplicate():
		pr["t"] = float(pr["t"]) + dt
		var a := clampf(1.0 - (float(pr["t"]) - 12.0) / 8.0, 0.0, 1.0) * 0.85
		(pr["mat"] as StandardMaterial3D).albedo_color.a = a
		if a <= 0.0:
			(pr["node"] as Node).queue_free()
			_prints.erase(pr)


static var _tex_cache := {}


static func _print_tex(palm: bool) -> ImageTexture:
	var key := "palm" if palm else "knock"
	if _tex_cache.has(key):
		return _tex_cache[key]
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in s:
		for x in s:
			var u := (x + 0.5) / s * 2.0 - 1.0
			var v := (y + 0.5) / s * 2.0 - 1.0
			var a := 0.0
			if palm:
				var pv := Vector2(u / 0.55, (v - 0.25) / 0.5)
				a = 1.0 - smoothstep(0.85, 1.0, pv.length())
				for k in 4:
					var fx := -0.42 + k * 0.28
					var fv := Vector2((u - fx) / 0.11, (v + 0.45 - absf(k - 1.5) * 0.08) / 0.33)
					a = maxf(a, 1.0 - smoothstep(0.8, 1.0, fv.length()))
				var tv := Vector2((u + 0.62) / 0.12, (v - 0.05) / 0.28)
				a = maxf(a, 1.0 - smoothstep(0.8, 1.0, tv.length()))
				a *= 0.55 + 0.45 * sin((u * 9.0 + v * 7.0) * 3.0) * 0.5 + 0.2
			else:
				var r := Vector2(u, v).length()
				a = maxf(1.0 - smoothstep(0.25, 0.4, r), (1.0 - smoothstep(0.03, 0.08, absf(r - 0.75))) * 0.8) * 0.8
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t
