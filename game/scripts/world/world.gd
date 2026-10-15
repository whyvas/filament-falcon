class_name WorldView
extends Node3D
## Renders the universe around the Falcon with a floating origin: the ship's centre is
## always (0,0,0) and everything else is placed at its BigVec offset each frame. Inertial
## axes are kept, so the star sky never moves.

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var earthshine: DirectionalLight3D
var ship: ShipModel
var earth_node: Node3D
var earth_mat: ShaderMaterial
var cloud_mat: ShaderMaterial
var atmo_mat: ShaderMaterial
var moon_node: Node3D
var moon_mat: ShaderMaterial
var patches: Array = []        # [{node, body, center}]
var ent_nodes := {}            # entity id -> Node3D
var tunnel: MeshInstance3D
var tunnel_mat: ShaderMaterial
var fx_nodes: Array = []       # [{node, pos: BigVec, t}]
var rig_xform := Transform3D.IDENTITY
var day_factor := 0.0
var in_shadow := false
var _t := 0.0
var _blinkers: Array = []
var _last_mission_obj: Object = null

const EYE := Vector3(0, 1.05, -5.3)
## Cameras use far = 1e6 m (larger ratios break Godot's frustum culling). Bodies whose visible
## disc would reach past that are drawn in "scaled space": shrunk about the camera by s and
## moved to s * distance, which keeps exactly the same angular size and shading.
## The VR client lowers these (XR combined-frustum culling breaks at huge far/near ratios).
var FAR_SAFE := 9.0e5
var ATMO_PROXY_R := 8.0e5
var atmo_node: MeshInstance3D
var earth_scale := 1.0
var eva_view: EvaView


func _ready() -> void:
	add_to_group("world")
	_build_environment()
	_build_bodies()
	_build_patches()
	ship = ShipModel.new()
	ship.name = "Falcon"
	add_child(ship)
	# The Falcon's own model lives on render layer 11 so the cockpit windows can hide it
	# (the eye point sits inside the hull); chase / console cameras still see it.
	get_tree().node_added.connect(func(n: Node) -> void:
		if ship and ship.is_ancestor_of(n):
			_tag_one(n))
	_tag_ship.call_deferred(ship)
	# the spacewalk (rails, props, astronaut) is NOT under the ship so the windows still see it
	eva_view = EvaView.new()
	add_child(eva_view)
	tunnel_mat = ProcGen.shader_mat("res://shaders/glow_fx.gdshader", {"color": Color(0.45, 0.35, 1.0), "mode": 3, "intensity": 0.0})
	tunnel = ProcGen.mesh_node(ProcGen.cyl(40.0, 40.0, 6000.0, 48), tunnel_mat)
	tunnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tunnel.visible = false
	add_child(tunnel)
	Game.mission_loaded.connect(_on_mission_loaded)
	Game.game_event.connect(_on_game_event)
	Settings.changed.connect(func(_s: String) -> void: apply_quality())
	_on_mission_loaded()
	apply_quality()


const SHIP_LAYER := 1 << 10


func _tag_one(n: Node) -> void:
	# hull meshes only: effects you should see out of the window (plume, laser, beam,
	# plasma sheath), lights and particles stay on the default layer
	if n is MeshInstance3D and n != ship.plume and n != ship.laser and n != ship.beam and n != ship.plasma:
		(n as MeshInstance3D).layers = SHIP_LAYER


func _tag_ship(n: Node) -> void:
	_tag_one(n)
	for c in n.get_children():
		_tag_ship(c)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/space_sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(6, 0.5)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 900.0
	sun.shadow_bias = 0.05
	sun.shadow_blur = 1.5
	add_child(sun)
	earthshine = DirectionalLight3D.new()
	earthshine.light_energy = 0.0
	earthshine.light_color = Color(0.45, 0.6, 1.0)
	earthshine.shadow_enabled = false
	earthshine.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(earthshine)


func _quality_segments() -> int:
	return [192, 320, 448, 640][Settings.quality_index()]


func _build_bodies() -> void:
	var e: CelestialBody = Game.earth
	earth_node = Node3D.new()
	earth_node.name = "Earth"
	add_child(earth_node)
	var seg := _quality_segments()
	earth_mat = ProcGen.shader_mat("res://shaders/planet.gdshader", {"site_a": Game.pad_dir, "site_b": Game.runway_dir})
	var surf := ProcGen.mesh_node(ProcGen.sphere(e.radius - 20.0, seg, seg / 2), earth_mat)
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surf.extra_cull_margin = 16384.0
	earth_node.add_child(surf)
	cloud_mat = ProcGen.shader_mat("res://shaders/clouds.gdshader", {"site_a": Game.pad_dir, "site_b": Game.runway_dir})
	var cl := ProcGen.mesh_node(ProcGen.sphere(e.radius + 4500.0, seg, seg / 2), cloud_mat)
	cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cl.extra_cull_margin = 16384.0
	earth_node.add_child(cl)
	atmo_mat = ProcGen.shader_mat("res://shaders/atmosphere.gdshader", {"planet_r_km": e.radius / 1000.0, "atmo_r_km": e.radius / 1000.0 + 90.0})
	# The atmosphere is ray-marched analytically, so its proxy mesh is just a big sphere around
	# the camera (inside the far plane); the planet centre comes in as a uniform.
	atmo_node = ProcGen.mesh_node(ProcGen.sphere(1.0, 48, 24), atmo_mat)
	atmo_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	atmo_node.extra_cull_margin = 16384.0
	atmo_node.scale = Vector3.ONE * ATMO_PROXY_R
	add_child(atmo_node)
	var m: CelestialBody = Game.moon
	moon_node = Node3D.new()
	moon_node.name = "Moon"
	add_child(moon_node)
	moon_mat = ProcGen.shader_mat("res://shaders/moon.gdshader")
	var ms := ProcGen.mesh_node(ProcGen.sphere(m.radius - 20.0, seg, seg / 2), moon_mat)
	ms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ms.extra_cull_margin = 16384.0
	moon_node.add_child(ms)


func _build_patches() -> void:
	var n: int = [96, 160, 224, 256][Settings.quality_index()]
	var earth_mat_t := ProcGen.shader_mat("res://shaders/terrain.gdshader", {"lunar": false, "tint_a": Color(0.16, 0.24, 0.08), "tint_b": Color(0.32, 0.3, 0.18)})
	var moon_mat_t := ProcGen.shader_mat("res://shaders/terrain.gdshader", {"lunar": true})
	_add_patch(Game.earth, Game.pad_dir, 16000.0, n, earth_mat_t)
	_add_patch(Game.earth, Game.runway_dir, 30000.0, n, earth_mat_t)
	_add_patch(Game.moon, Game.lunar_site_dir, 22000.0, n, moon_mat_t)


func _add_patch(body: CelestialBody, center: Vector3, half: float, n: int, mat: Material) -> void:
	var mi := ProcGen.mesh_node(ProcGen.terrain_patch(body, center, half, n), mat)
	var up := center.normalized()
	var east := CelestialBody.east_at(up)
	mi.basis = Basis(east, up, east.cross(up))
	mi.extra_cull_margin = 2000.0
	add_child(mi)
	patches.append({"node": mi, "body": body, "center": up})


func apply_quality() -> void:
	var q := Settings.quality_index()
	env.ssao_enabled = q >= 2
	env.ssil_enabled = q >= 3
	env.ssr_enabled = q >= 3
	env.glow_enabled = true
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	atmo_mat.set_shader_parameter("steps", [8, 12, 16, 24][q])
	atmo_mat.set_shader_parameter("light_steps", [4, 5, 6, 8][q])
	earth_mat.set_shader_parameter("detail", 0.5 if q == 0 else 1.0)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192, 8192][q], true)


# ------------------------------------------------------------------ entities
func _on_mission_loaded() -> void:
	for id in ent_nodes:
		(ent_nodes[id] as Node).queue_free()
	ent_nodes.clear()
	for f in fx_nodes:
		(f["node"] as Node).queue_free()
	fx_nodes.clear()
	_sync_entities()


func _make_entity_node(e: Dictionary) -> Node3D:
	match e["kind"]:
		"station":
			return Models.station()
		"booster":
			return Models.booster()
		"satellite":
			return Models.satellite()
		"pod":
			return Models.pod()
		"crystal":
			return Models.crystal(false)
		"crystal_rock":
			return Models.crystal_rock()
		"pad":
			return Models.pad()
		"runway":
			return Models.runway()
		"lunar_pad":
			return Models.lunar_pad()
		"field":
			return _make_field(e)
	return Node3D.new()


func _make_field(e: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pos: PackedVector3Array = e.get("rock_pos", PackedVector3Array())
	var rad: PackedFloat32Array = e.get("rock_r", PackedFloat32Array())
	var variants := 4
	var rmat := Models.rock_material()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for v in variants:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ProcGen.rock_mesh(100 + v, 0.38)
		var idxs := []
		for i in pos.size():
			if i % variants == v:
				idxs.append(i)
		mm.instance_count = idxs.size()
		for k in idxs.size():
			var i: int = idxs[k]
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * rad[i])
			mm.set_instance_transform(k, Transform3D(b, pos[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = rmat
		root.add_child(mmi)
	# a little dust glitter
	return root


func _sync_entities() -> void:
	var live := {}
	for e in Game.entities:
		var id: String = e["id"]
		live[id] = true
		if not ent_nodes.has(id):
			var n := _make_entity_node(e)
			n.name = id
			add_child(n)
			ent_nodes[id] = n
	for id in ent_nodes.keys():
		if not live.has(id):
			(ent_nodes[id] as Node).queue_free()
			ent_nodes.erase(id)


func _on_game_event(kind: String, data: Dictionary) -> void:
	if kind == "explosion":
		_spawn_explosion(data["pos"], float(data.get("radius", 10.0)), data.get("color", Color(1, 0.6, 0.3)))
	elif kind == "staged":
		_spawn_explosion(Game.sim.pos.copy(), 8.0, Color(1, 0.8, 0.6))


func _spawn_explosion(p: BigVec, radius: float, c: Color) -> void:
	var em := GPUParticles3D.new()
	em.amount = 220
	em.lifetime = 2.5
	em.one_shot = true
	em.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = radius * 0.5
	pm.initial_velocity_max = radius * 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.3
	pm.scale_max = 1.5
	pm.color = c
	em.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.4
	sm.height = 0.8
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = ProcGen.glow_mat(c, 5.0)
	em.draw_pass_1 = sm
	add_child(em)
	em.emitting = true
	fx_nodes.append({"node": em, "pos": p, "t": 0.0})


# ------------------------------------------------------------------ per frame
func _place_scaled(node: Node3D, rel: Vector3, radius: float) -> float:
	var d := rel.length()
	var need := sqrt(maxf(d * d - radius * radius, 0.0)) + radius * 0.3
	var s := minf(1.0, FAR_SAFE / maxf(need, 1.0))
	node.position = rel * s
	node.scale = Vector3.ONE * s
	return s


func _process(dt: float) -> void:
	_t += dt
	var g := Game
	var sim: ShipSim = g.sim
	var origin: BigVec = sim.pos
	_sync_entities()
	# Sun + eclipse test against the planet and moon
	var sd: Vector3 = g.sun_dir.normalized()
	sun.basis = Basis.looking_at(-sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.RIGHT)
	in_shadow = false
	for b in [g.earth, g.moon]:
		var body: CelestialBody = b
		var c := body.pos.rel(origin)
		var tca := c.dot(sd)
		if tca > 0.0 and (c - sd * tca).length() < body.radius * 0.995:
			in_shadow = true
	sun.light_energy = lerpf(sun.light_energy, 0.0 if in_shadow else 2.2, clampf(dt * 4.0, 0.0, 1.0))
	# Bodies
	var ep := g.earth.pos.rel(origin)
	earth_scale = _place_scaled(earth_node, ep, g.earth.radius)
	var mp := g.moon.pos.rel(origin)
	_place_scaled(moon_node, mp, g.moon.radius)
	atmo_node.position = rig_xform.origin
	atmo_mat.set_shader_parameter("planet_center", ep)
	atmo_mat.set_shader_parameter("space_scale", earth_scale)
	for m in [earth_mat, cloud_mat, atmo_mat, moon_mat]:
		(m as ShaderMaterial).set_shader_parameter("sun_dir", sd)
	earth_mat.set_shader_parameter("time", g.t)
	earth_mat.set_shader_parameter("cloud_rot", g.t * 0.00002)
	cloud_mat.set_shader_parameter("time", g.t)
	cloud_mat.set_shader_parameter("cloud_rot", g.t * 0.00002)
	# Earthshine: light reflected from the big blue planet
	var to_e := ep.normalized()
	var phase := clampf((-to_e).dot(sd) * 0.5 + 0.5, 0.0, 1.0)
	var size := clampf(g.earth.radius / maxf(ep.length(), 1.0), 0.0, 1.0)
	earthshine.light_energy = 0.35 * phase * size
	earthshine.basis = Basis.looking_at(to_e, Vector3.UP if absf(to_e.y) < 0.99 else Vector3.RIGHT)
	# Daylight inside the atmosphere dims the stars and adds blue ambient
	var dom: CelestialBody = sim.dominant
	day_factor = 0.0
	var elev := sim.up_dir.dot(sd)
	var in_air := dom != null and dom.has_atmo and sim.altitude < dom.atmo_top
	if in_air:
		day_factor = smoothstep(-0.12, 0.2, elev) * (1.0 - clampf(sim.altitude / 45000.0, 0.0, 1.0))
	sky_mat.set_shader_parameter("star_intensity", lerpf(1.0, 0.0, smoothstep(0.0, 0.25, day_factor)))
	sky_mat.set_shader_parameter("milky_intensity", lerpf(1.0, 0.0, day_factor))
	env.ambient_light_color = Color(0.05, 0.06, 0.08).lerp(Color(0.35, 0.45, 0.6), day_factor)
	# Scripted "physically based" exposure (deterministic, so screenshots and bots match): bright
	# daytime sky stops down, sunlit space a little less, night in the atmosphere opens up.
	var night := (1.0 - clampf(sim.altitude / 45000.0, 0.0, 1.0)) * (1.0 - smoothstep(-0.12, 0.05, elev)) if in_air else 0.0
	var exp_target := lerpf(0.92, 0.78, day_factor) + night * 0.35
	env.tonemap_exposure = lerpf(env.tonemap_exposure, exp_target, clampf(dt * 1.5, 0.0, 1.0)) if dt < 0.5 else exp_target
	# Terrain patches: visible only when near
	for p in patches:
		var body2: CelestialBody = p["body"]
		var center: Vector3 = p["center"]
		var bc := body2.pos.copy()
		bc.add_xyz(center.x * body2.radius, center.y * body2.radius, center.z * body2.radius)
		var rel := bc.rel(origin)
		var node: Node3D = p["node"]
		node.position = rel
		# Earth patches sit under the cloud deck: from high up the planet shader takes over
		node.visible = rel.length() < 400000.0 and (body2 != g.earth or sim.altitude < 60000.0)
	# Entities
	for e in g.entities:
		var n: Node3D = ent_nodes.get(e["id"])
		if n == null:
			continue
		var rel2 := (e["pos"] as BigVec).rel(origin)
		n.position = rel2
		n.basis = e["basis"]
		var far := 250000.0 if e["kind"] in ["pad", "runway", "lunar_pad"] else (60000.0 if e["kind"] != "field" else 500000.0)
		n.visible = bool(e.get("visible", true)) and rel2.length() < far
		_animate_entity(e, n, dt)
	# FX
	for f in fx_nodes.duplicate():
		f["t"] = float(f["t"]) + dt
		var fn: Node3D = f["node"]
		fn.position = (f["pos"] as BigVec).rel(origin)
		if float(f["t"]) > 4.0:
			fn.queue_free()
			fx_nodes.erase(f)
	# Ship + camera rig
	ship.basis = sim.basis
	ship.visible = true
	ship.animate(g, dt)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * g.camera_shake * 0.04
	shake += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * clampf(sim.dyn_pressure / 40000.0, 0.0, 0.03)
	if sim.thrust_now > 0.0 and sim.booster_attached:
		shake += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.02
	if g.view_mode == 0:
		rig_xform = Transform3D(sim.basis, sim.basis * (EYE + shake))
	else:
		rig_xform = chase_xform(sim, 34.0 if not sim.booster_attached else 75.0)
		rig_xform.origin += sim.basis * shake * 20.0
	# Hyperspace tunnel
	tunnel.visible = g.jump_phase > 0.0
	if tunnel.visible:
		tunnel.basis = sim.basis * Basis(Vector3.RIGHT, PI * 0.5)
		tunnel_mat.set_shader_parameter("intensity", sin(clampf(g.jump_phase, 0.0, 1.0) * PI) * 1.5 + g.jump_phase * 0.3)
		tunnel_mat.set_shader_parameter("time", _t)


func _animate_entity(e: Dictionary, n: Node3D, dt: float) -> void:
	match e["kind"]:
		"station":
			for c in n.get_children():
				if c.has_meta("spin"):
					(c as Node3D).rotate_object_local(Vector3(0, 0, 1), float(c.get_meta("spin")) * dt)
				if c.has_meta("blink"):
					(c as Node3D).visible = fmod(_t + c.position.x * 0.1, 1.5) < 0.2
				if c.has_meta("solar"):
					# arrays track the sun around their mast (local X)
					var ls: Vector3 = (e["basis"] as Basis).inverse() * Game.sun_dir
					var want := atan2(-ls.y, ls.z)
					(c as Node3D).rotation.x = lerp_angle((c as Node3D).rotation.x, want, clampf(dt * 2.0, 0.0, 1.0)) if dt < 0.5 else want
		"booster":
			var pl: Node3D = n.get_node_or_null("Plume")
			var on: bool = e["mode"] == "attached" and Game.sim.booster_attached and Game.sim.thrust_now > 0.0
			if pl:
				pl.visible = on
				var thr := Game.sim.thrust_now / Game.sim.booster_thrust
				var vac := 1.0 - clampf(Game.sim.density_now / 0.4, 0.0, 1.0)
				pl.scale = Vector3(2.2 + vac * 3.0, 30.0 + vac * 25.0, 2.2 + vac * 3.0)
				var pm: ShaderMaterial = pl.get_meta("mat")
				pm.set_shader_parameter("throttle", thr)
				pm.set_shader_parameter("vacuum", vac)
				pm.set_shader_parameter("time", _t)
				var hz: ShaderMaterial = pl.get_meta("haze")
				hz.set_shader_parameter("strength", thr * (1.0 - 0.8 * vac))
				hz.set_shader_parameter("time", _t)
			var l: OmniLight3D = n.get_node_or_null("Light")
			if l:
				l.light_energy = 10.0 * (Game.sim.thrust_now / Game.sim.booster_thrust) if on else 0.0
		"satellite":
			if e.get("deployed", false):
				for c in n.get_children():
					if c.has_meta("side"):
						var target := 0.0
						(c as Node3D).rotation.z = move_toward((c as Node3D).rotation.z, target, dt)
			else:
				for c in n.get_children():
					if c.has_meta("side"):
						(c as Node3D).rotation.z = float(c.get_meta("side")) * 1.4
		"crystal", "pod", "lunar_pad", "pad":
			if e["kind"] == "pad":
				var smk: GPUParticles3D = n.get_node_or_null("PadSmoke")
				if smk:
					var near_pad: bool = Game.sim.thrust_now > 0.0 and Game.sim.agl < 400.0 and Game.sim.pos.rel(e["pos"]).length() < 600.0
					if near_pad and not smk.emitting:
						smk.emitting = true
					elif not near_pad and smk.emitting and Game.sim.agl > 400.0:
						smk.emitting = false
			for c in n.get_children():
				if c.has_meta("blink"):
					(c as Node3D).visible = fmod(_t, 1.2) < 0.4
			if e["kind"] == "crystal":
				n.rotate_y(dt * 0.8)
		"crystal_rock":
			n.rotate_y(dt * 0.05)


## Docking camera (nose) and arm camera transforms, relative to the floating origin.
## Chase camera behind and above the ship; near the ground it swings to the side so it
## never ends up underground (e.g. the rocket standing on the pad).
func chase_xform(sim: ShipSim, dist: float) -> Transform3D:
	var fwd := sim.forward()
	var up := sim.up_dir if sim.up_dir.length() > 0.5 else sim.basis.y
	var off := -fwd * dist + sim.basis.y * dist * 0.26
	if sim.agl < 2000.0 and off.dot(up) < 6.0 - minf(sim.agl, 1000.0) * 0.5:
		var side := sim.basis.x.slide(up).normalized()
		if side.length() < 0.5:
			side = up.cross(fwd).normalized()
		off = side * dist * 0.9 + up * (dist * 0.15) - fwd.slide(up) * dist * 0.3
	var target := fwd * (dist * 0.1)
	var t := Transform3D(Basis.IDENTITY, off)
	var look_up := up if absf((target - off).normalized().dot(up)) < 0.98 else sim.basis.y
	return t.looking_at(target, look_up)


func docking_cam_xform() -> Transform3D:
	var s: ShipSim = Game.sim
	return Transform3D(s.basis, s.basis * Vector3(0, 0, -8.2))


func arm_cam_xform() -> Transform3D:
	var s: ShipSim = Game.sim
	var tip: Vector3 = Game.arm_tip_rel()
	var d: Vector3 = Game.arm_dir_world()
	var up := s.basis.y if absf(d.dot(s.basis.y)) < 0.95 else -s.basis.z
	return Transform3D(Basis.looking_at(d, up), tip + d * 0.6)
