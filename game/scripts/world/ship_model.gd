class_name ShipModel
extends Node3D
## The Falcon, built from procedural parts: lifting-body fuselage with heat-shield belly,
## delta wings, tail fin, canopy, main engine with exhaust plume and light, RCS quads with
## puff particles, opening cargo-bay doors, robotic arm with tractor beam, landing gear
## (belly wheels + tail legs), docking port, nav/strobe/beacon lights, laser, plasma sheath.

var hull_mat: ShaderMaterial
var plume_mat: ShaderMaterial
var plume: MeshInstance3D
var engine_light: OmniLight3D
var door_l: Node3D
var door_r: Node3D
var arm_root: Node3D
var arm_seg: MeshInstance3D
var arm_tip: Node3D
var beam: MeshInstance3D
var beam_mat: ShaderMaterial
var laser: MeshInstance3D
var laser_mat: ShaderMaterial
var plasma: MeshInstance3D
var plasma_mat: ShaderMaterial
var wheels: Array[Node3D] = []
var legs: Array[Node3D] = []
var nav_red: OmniLight3D
var nav_green: OmniLight3D
var strobe: OmniLight3D
var beacon: OmniLight3D
var strobe_mesh: MeshInstance3D
var beacon_mesh: MeshInstance3D
var rcs_emitters: Array[GPUParticles3D] = []
var smoke: GPUParticles3D
var cargo_root: Node3D
var _t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	hull_mat = ProcGen.shader_mat("res://shaders/hull.gdshader")
	var profile := [Vector2(-7.7, 0.0), Vector2(-7.5, 0.55), Vector2(-7.0, 1.05), Vector2(-6.0, 1.5), Vector2(-4.5, 1.8),
		Vector2(-2.0, 1.95), Vector2(3.0, 1.95), Vector2(6.0, 1.8), Vector2(7.2, 1.55), Vector2(7.25, 0.0)]
	var body := ProcGen.mesh_node(ProcGen.lathe(profile, 48, 0.82), hull_mat)
	add_child(body)
	# Canopy (dark glass)
	var glass := ProcGen.mat(Color(0.03, 0.05, 0.08), 0.9, 0.05)
	glass.rim_enabled = true
	glass.rim = 0.4
	add_child(ProcGen.mesh_node(ProcGen.sphere(1.0, 32, 16), glass, Vector3(0, 0.95, -4.4), Vector3.ZERO, Vector3(1.05, 0.55, 2.0)))
	# Wings
	var wing_poly := PackedVector2Array([Vector2(1.5, -2.5), Vector2(6.6, 4.6), Vector2(6.6, 5.8), Vector2(1.5, 6.4)])
	var wing_mesh := ProcGen.extrude(wing_poly, 0.32)
	add_child(ProcGen.mesh_node(wing_mesh, hull_mat, Vector3(0, -0.75, 0)))
	var wing_poly_l := PackedVector2Array([Vector2(-1.5, 6.4), Vector2(-6.6, 5.8), Vector2(-6.6, 4.6), Vector2(-1.5, -2.5)])
	add_child(ProcGen.mesh_node(ProcGen.extrude(wing_poly_l, 0.32), hull_mat, Vector3(0, -0.75, 0)))
	# Wingtip fins
	var tipfin := ProcGen.extrude(PackedVector2Array([Vector2(-0.12, 4.4), Vector2(0.12, 4.4), Vector2(0.12, 5.9), Vector2(-0.12, 5.9)]), 1.2)
	add_child(ProcGen.mesh_node(tipfin, hull_mat, Vector3(6.6, -0.2, 0)))
	add_child(ProcGen.mesh_node(tipfin, hull_mat, Vector3(-6.6, -0.2, 0)))
	# Tail fin (YZ plane): extrude in X
	var fin_poly := PackedVector2Array([Vector2(0.0, 3.2), Vector2(3.2, 6.6), Vector2(3.2, 7.4), Vector2(0.0, 7.3)])
	var fin := ProcGen.mesh_node(ProcGen.extrude(fin_poly, 0.28), hull_mat, Vector3(0, 1.3, 0))
	fin.basis = Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
	add_child(fin)
	# Engine bell + glow
	var metal := ProcGen.mat(Color(0.25, 0.24, 0.23), 0.9, 0.35)
	var bell := ProcGen.mesh_node(ProcGen.cyl(0.65, 1.25, 2.0, 32), metal, Vector3(0, 0, 8.2), Vector3(PI * 0.5, 0, 0))
	add_child(bell)
	var hot := ProcGen.glow_mat(Color(1.0, 0.5, 0.2), 2.0)
	add_child(ProcGen.mesh_node(ProcGen.cyl(0.6, 0.6, 0.05, 24), hot, Vector3(0, 0, 7.3), Vector3(PI * 0.5, 0, 0)))
	plume_mat = ProcGen.shader_mat("res://shaders/plume.gdshader")
	var pm := CylinderMesh.new()
	pm.top_radius = 1.0
	pm.bottom_radius = 1.0
	pm.height = 1.0
	pm.radial_segments = 24
	pm.rings = 8
	plume = ProcGen.mesh_node(pm, plume_mat)
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plume_pivot := Node3D.new()
	plume_pivot.position = Vector3(0, 0, 9.1)
	plume_pivot.rotation = Vector3(-PI * 0.5, 0, 0)
	add_child(plume_pivot)
	plume.position = Vector3(0, -0.5, 0)
	plume_pivot.add_child(plume)
	plume_pivot.name = "PlumePivot"
	engine_light = OmniLight3D.new()
	engine_light.position = Vector3(0, 0, 11.0)
	engine_light.light_color = Color(1.0, 0.65, 0.35)
	engine_light.omni_range = 120.0
	engine_light.light_energy = 0.0
	engine_light.shadow_enabled = false
	add_child(engine_light)
	# Exhaust smoke (only in air)
	smoke = GPUParticles3D.new()
	smoke.amount = 160
	smoke.lifetime = 4.0
	smoke.local_coords = false
	smoke.position = Vector3(0, 0, 12.0)
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(0, 0, 1)
	spm.spread = 8.0
	spm.initial_velocity_min = 30.0
	spm.initial_velocity_max = 50.0
	spm.gravity = Vector3.ZERO
	spm.scale_min = 4.0
	spm.scale_max = 9.0
	spm.damping_min = 2.0
	spm.damping_max = 4.0
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(1.0, 0.8, 0.6, 0.5))
	sgrad.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sgrad
	spm.color_ramp = sgt
	smoke.process_material = spm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_texture = _soft_dot()
	quad.material = smat
	smoke.draw_pass_1 = quad
	smoke.emitting = false
	add_child(smoke)
	# RCS quads and puff emitters
	var rcs_pos := [Vector3(1.75, 0.6, -5.5), Vector3(-1.75, 0.6, -5.5), Vector3(1.6, 0.6, 6.2), Vector3(-1.6, 0.6, 6.2)]
	for p in rcs_pos:
		add_child(ProcGen.mesh_node(ProcGen.box(Vector3(0.35, 0.35, 0.35)), metal, p))
		var em := GPUParticles3D.new()
		em.amount = 24
		em.lifetime = 0.35
		em.one_shot = false
		em.explosiveness = 0.0
		em.position = p
		var ppm := ParticleProcessMaterial.new()
		ppm.direction = Vector3(signf(p.x), 0.3, 0)
		ppm.spread = 25.0
		ppm.initial_velocity_min = 8.0
		ppm.initial_velocity_max = 14.0
		ppm.gravity = Vector3.ZERO
		ppm.scale_min = 0.3
		ppm.scale_max = 0.9
		ppm.color_ramp = sgt
		em.process_material = ppm
		em.draw_pass_1 = quad
		em.emitting = false
		add_child(em)
		rcs_emitters.append(em)
	# Cargo bay doors (hinged along the top edges)
	var door_mesh := ProcGen.box(Vector3(1.3, 0.12, 6.0))
	door_l = Node3D.new()
	door_l.position = Vector3(-1.45, 1.42, 1.5)
	add_child(door_l)
	door_l.add_child(ProcGen.mesh_node(door_mesh, hull_mat, Vector3(0.65, 0, 0)))
	door_r = Node3D.new()
	door_r.position = Vector3(1.45, 1.42, 1.5)
	add_child(door_r)
	door_r.add_child(ProcGen.mesh_node(door_mesh, hull_mat, Vector3(-0.65, 0, 0)))
	var bay_mat := ProcGen.mat(Color(0.75, 0.6, 0.25), 0.85, 0.35)
	add_child(ProcGen.mesh_node(ProcGen.box(Vector3(2.5, 0.1, 5.8)), bay_mat, Vector3(0, 0.85, 1.5)))
	cargo_root = Node3D.new()
	add_child(cargo_root)
	# Robotic arm
	arm_root = Node3D.new()
	arm_root.position = Vector3(0, 1.75, 1.0)
	add_child(arm_root)
	var arm_mat := ProcGen.mat(Color(0.92, 0.92, 0.9), 0.3, 0.4)
	arm_root.add_child(ProcGen.mesh_node(ProcGen.sphere(0.35), arm_mat))
	arm_seg = ProcGen.mesh_node(ProcGen.cyl(0.14, 0.18, 1.0, 12), arm_mat)
	arm_root.add_child(arm_seg)
	arm_tip = Node3D.new()
	arm_root.add_child(arm_tip)
	arm_tip.add_child(ProcGen.mesh_node(ProcGen.cyl(0.25, 0.1, 0.5, 12), metal, Vector3.ZERO, Vector3(PI * 0.5, 0, 0)))
	beam_mat = ProcGen.shader_mat("res://shaders/glow_fx.gdshader", {"color": Color(0.3, 0.75, 1.0), "mode": 0, "intensity": 1.2})
	beam = ProcGen.mesh_node(ProcGen.cyl(4.0, 0.3, 1.0, 24), beam_mat)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	arm_tip.add_child(beam)
	# Laser (nose)
	laser_mat = ProcGen.shader_mat("res://shaders/glow_fx.gdshader", {"color": Color(1.0, 0.2, 0.15), "mode": 1, "intensity": 2.5})
	laser = ProcGen.mesh_node(ProcGen.cyl(0.12, 0.12, 1.0, 8), laser_mat)
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.visible = false
	add_child(laser)
	# Docking port ring at the nose
	add_child(ProcGen.mesh_node(ProcGen.torus(0.45, 0.7, 32), metal, Vector3(0, 0, -7.75), Vector3(PI * 0.5, 0, 0)))
	# Landing gear: belly wheels
	var tire := ProcGen.mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	for wp in [Vector3(0, -1.25, -4.6), Vector3(2.3, -1.25, 2.6), Vector3(-2.3, -1.25, 2.6)]:
		var g := Node3D.new()
		g.position = wp
		add_child(g)
		g.add_child(ProcGen.mesh_node(ProcGen.cyl(0.1, 0.1, 0.9, 8), metal, Vector3(0, -0.45, 0)))
		g.add_child(ProcGen.mesh_node(ProcGen.cyl(0.42, 0.42, 0.3, 16), tire, Vector3(0, -0.95, 0), Vector3(0, 0, PI * 0.5)))
		wheels.append(g)
	# Tail legs for vertical landings
	for lp in [Vector3(2.0, 0, 7.0), Vector3(-2.0, 0, 7.0), Vector3(0, 2.0, 7.0), Vector3(0, -2.0, 7.0)]:
		var lg := Node3D.new()
		lg.position = lp
		add_child(lg)
		var outward := Vector3(lp.x, lp.y, 0).normalized()
		lg.add_child(ProcGen.mesh_node(ProcGen.cyl(0.09, 0.09, 1.0, 8), metal, Vector3.ZERO, Vector3.ZERO))
		lg.add_child(ProcGen.mesh_node(ProcGen.cyl(0.35, 0.35, 0.1, 12), metal, Vector3.ZERO))
		lg.set_meta("out", outward)
		legs.append(lg)
	# Lights
	nav_red = _light(Vector3(-6.7, -0.3, 5.0), Color(1, 0.1, 0.1), 0.6)
	nav_green = _light(Vector3(6.7, -0.3, 5.0), Color(0.1, 1, 0.2), 0.6)
	strobe = _light(Vector3(0, 4.5, 7.3), Color(1, 1, 1), 0.0)
	beacon = _light(Vector3(0, 1.75, -1.5), Color(1, 0.2, 0.1), 0.0)
	add_child(ProcGen.mesh_node(ProcGen.sphere(0.12), ProcGen.glow_mat(Color(1, 0.1, 0.1), 6.0), Vector3(-6.7, -0.3, 5.0)))
	add_child(ProcGen.mesh_node(ProcGen.sphere(0.12), ProcGen.glow_mat(Color(0.1, 1, 0.2), 6.0), Vector3(6.7, -0.3, 5.0)))
	strobe_mesh = ProcGen.mesh_node(ProcGen.sphere(0.14), ProcGen.glow_mat(Color(1, 1, 1), 12.0), Vector3(0, 4.5, 7.3))
	add_child(strobe_mesh)
	beacon_mesh = ProcGen.mesh_node(ProcGen.sphere(0.16), ProcGen.glow_mat(Color(1, 0.15, 0.05), 10.0), Vector3(0, 1.75, -1.5))
	add_child(beacon_mesh)
	# Plasma sheath (re-entry glow)
	plasma_mat = ProcGen.shader_mat("res://shaders/glow_fx.gdshader", {"color": Color(1.0, 0.45, 0.15), "mode": 2, "intensity": 0.0})
	plasma = ProcGen.mesh_node(ProcGen.sphere(1.0, 32, 16), plasma_mat, Vector3.ZERO, Vector3.ZERO, Vector3(9, 6, 13))
	plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plasma.visible = false
	add_child(plasma)


func _light(p: Vector3, c: Color, e: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.light_energy = e
	l.omni_range = 8.0
	add_child(l)
	return l


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


## Animate from game state (called every frame by the World).
func animate(g: Node, dt: float) -> void:
	_t += dt
	var sim: ShipSim = g.sim
	var thr_frac := sim.thrust_now / maxf(sim.main_thrust, 1.0)
	if sim.booster_attached:
		thr_frac = 0.0
	var vac := 1.0 - clampf(sim.density_now / 0.4, 0.0, 1.0)
	plume.visible = thr_frac > 0.01
	plume.scale = Vector3(1.0 + vac * 2.5, 9.0 + thr_frac * 14.0 + vac * 10.0, 1.0 + vac * 2.5)
	plume_mat.set_shader_parameter("throttle", thr_frac * (1.3 if sim.boost else 1.0))
	plume_mat.set_shader_parameter("vacuum", vac)
	plume_mat.set_shader_parameter("time", _t)
	engine_light.light_energy = thr_frac * 6.0 * (0.85 + 0.15 * sin(_t * 40.0))
	smoke.emitting = thr_frac > 0.05 and sim.density_now > 0.05
	if smoke.emitting:
		var spm: ParticleProcessMaterial = smoke.process_material
		var air := sim.basis.transposed() * (-sim.surface_vel)
		spm.direction = (Vector3(0, 0, 1) * 40.0 + air).normalized()
		spm.initial_velocity_min = 30.0 + air.length() * 0.9
		spm.initial_velocity_max = 50.0 + air.length()
	# RCS puffs
	var tr := sim.rcs_trans_activity
	var rr := sim.rcs_rot_activity
	var act := [tr.x < -0.1 or rr.y > 0.3, tr.x > 0.1 or rr.y < -0.3, tr.x < -0.1 or rr.y < -0.3, tr.x > 0.1 or rr.y > 0.3]
	var any_v := absf(tr.y) > 0.1 or absf(tr.z) > 0.1 or absf(rr.x) > 0.3 or absf(rr.z) > 0.3
	for i in rcs_emitters.size():
		rcs_emitters[i].emitting = act[i] or any_v
	# Doors and arm
	door_l.rotation.z = -g.cargo_door * deg_to_rad(150.0)
	door_r.rotation.z = g.cargo_door * deg_to_rad(150.0)
	var ext: float = g.arm_extend
	arm_root.visible = ext > 0.01
	var dir_b: Vector3 = g.arm_dir_body()
	var length: float = g.arm_len * ext
	if arm_root.visible:
		var b := Basis.looking_at(dir_b, Vector3.UP if absf(dir_b.y) < 0.95 else Vector3.BACK)
		arm_seg.basis = b * Basis(Vector3.RIGHT, PI * 0.5)
		arm_seg.position = dir_b * length * 0.5
		arm_seg.scale = Vector3(1, maxf(length, 0.05), 1)
		arm_tip.position = dir_b * length
		arm_tip.basis = b
	beam.visible = g.beam_on
	if beam.visible:
		beam.basis = Basis(Vector3.RIGHT, -PI * 0.5)
		beam.scale = Vector3(1, 60.0, 1)
		beam.position = Vector3(0, 0, -30.0)
		beam_mat.set_shader_parameter("time", _t)
	# Laser
	laser.visible = g.laser_on
	if laser.visible:
		var dist := float(g.mission.guidance.get("laser_dist", 900.0)) if g.mission else 900.0
		laser.basis = Basis(Vector3.RIGHT, PI * 0.5)
		laser.scale = Vector3(1, dist, 1)
		laser.position = Vector3(0, -0.6, -7.8 - dist * 0.5)
	# Gear
	var gp: float = sim.gear_pos
	for w in wheels:
		w.visible = gp > 0.02
		w.scale = Vector3(1, maxf(gp, 0.05), 1)
	for lg in legs:
		lg.visible = gp > 0.02
		var out: Vector3 = lg.get_meta("out")
		var foot := out * 0.6 + Vector3(0, 0, 1.6 * gp)
		var leg_mesh: MeshInstance3D = lg.get_child(0)
		var foot_mesh: MeshInstance3D = lg.get_child(1)
		leg_mesh.position = foot * 0.5
		leg_mesh.basis = Basis.looking_at(foot.normalized(), Vector3.UP if absf(foot.normalized().y) < 0.9 else Vector3.RIGHT) * Basis(Vector3.RIGHT, PI * 0.5)
		leg_mesh.scale = Vector3(1, foot.length(), 1)
		foot_mesh.position = foot
		foot_mesh.basis = Basis(Vector3.RIGHT, PI * 0.5)
	# Lights
	nav_red.visible = InputHub.on("nav_lights")
	nav_green.visible = nav_red.visible
	var strobe_on := InputHub.on("strobe") and fmod(_t, 1.2) < 0.08
	strobe.light_energy = 6.0 if strobe_on else 0.0
	strobe_mesh.visible = strobe_on
	var beacon_on := InputHub.on("beacon") and fmod(_t, 1.0) < 0.5
	beacon.light_energy = 2.0 if beacon_on else 0.0
	beacon_mesh.visible = beacon_on
	# Heat
	var heat := clampf((sim.hull_temp - 700.0) / 900.0, 0.0, 1.2)
	hull_mat.set_shader_parameter("heat_glow", heat)
	var pl := clampf(sim.heat_flux / 120000.0, 0.0, 1.5)
	plasma.visible = pl > 0.02
	if plasma.visible:
		plasma_mat.set_shader_parameter("intensity", pl * 1.6)
		plasma_mat.set_shader_parameter("time", _t)
		plasma_mat.set_shader_parameter("flow_dir", sim.basis.transposed() * sim.surface_vel.normalized())
