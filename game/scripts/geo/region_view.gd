class_name RegionView
extends Node3D
## Low-altitude detail region (OSM + DEM) built by tools/build_region.py, turned into meshes at
## runtime and streamed by distance: terrain with landuse colours, buildings (walls, gable /
## hipped / flat roofs, steeples, window atlas lit at night), instanced trees, water, roads
## with markings + bridges, railways. Sits on the game Earth at its real lat/lon (Geo), bent
## to the planet's curvature. Missing region = no-op.

const LOAD_R := 3500.0
const DROP_R := 5200.0
const LU_COL := [Color(0.27, 0.36, 0.17), Color(0.32, 0.45, 0.2), Color(0.52, 0.5, 0.3), Color(0.16, 0.26, 0.12),
	Color(0.42, 0.42, 0.36), Color(0.46, 0.44, 0.42), Color(0.44, 0.42, 0.4), Color(0.12, 0.2, 0.26),
	Color(0.24, 0.3, 0.2), Color(0.7, 0.65, 0.5), Color(0.3, 0.3, 0.3)]
const ROAD_COL := {"motorway": Color(0.2, 0.2, 0.21), "trunk": Color(0.21, 0.21, 0.22), "primary": Color(0.23, 0.23, 0.24),
	"footway": Color(0.55, 0.5, 0.45), "path": Color(0.5, 0.45, 0.35), "cycleway": Color(0.4, 0.2, 0.18), "track": Color(0.45, 0.38, 0.28), "stream": Color(0.12, 0.2, 0.26)}

var dir := ""
var man: Dictionary = {}
var up := Vector3.UP
var flat_h := 0.0
var chunks := {}        # key -> Node3D
var grids := {}         # key -> {o, n, h: PackedFloat32Array}
var _queue: Array = []
var _water: Node3D
var mats := {}
var active := false


func _ready() -> void:
	var name_ := str(Settings.cli.get("region", "fredericton"))
	dir = str(Settings.cli.get("region-dir", Geo.asset_dir() + "/regions/" + name_))
	var mf := dir + "/manifest.json"
	if not FileAccess.file_exists(mf):
		return
	man = JSON.parse_string(FileAccess.get_file_as_string(mf))
	if typeof(man) != TYPE_DICTIONARY:
		man = {}
		return
	up = Geo.game_dir(float(man["lat0"]), float(man["lon0"])).normalized()
	var east := CelestialBody.east_at(up)
	basis = Basis(east, up, east.cross(up))
	_make_mats()
	_register()
	Game.mission_loaded.connect(_register)
	print("Region '%s': %d chunks %s" % [man["name"], (man["chunks"] as Array).size(), str(man.get("counts", {}))])


## Flatten the game planet under the region and let the ground follow the DEM (collision).
func _register() -> void:
	var e: CelestialBody = Game.earth
	e.add_site(up, 6000.0)
	flat_h = e.terrain_amp * 0.25
	e.height_hook = height_at


func height_at(d: Vector3) -> float:
	var ang := up.angle_to(d)
	if ang * Game.earth.radius > 7000.0:
		return NAN
	var lp := basis.inverse() * (d.normalized() * Game.earth.radius - up * Game.earth.radius)
	return flat_h + ground(lp.x, lp.z)


## Terrain height (m above the region base) at local x/z, from loaded chunk grids.
func ground(x: float, z: float) -> float:
	var cs := float(man.get("chunk", 1000.0))
	var g: Dictionary = grids.get("%d_%d" % [floori(x / cs), floori(z / cs)], {})
	if g.is_empty():
		return 0.0
	var n: int = g["n"]
	var o: Vector2 = g["o"]
	var fx := clampf((x - o.x) / cs * (n - 1), 0.0, n - 1.001)
	var fz := clampf((z - o.y) / cs * (n - 1), 0.0, n - 1.001)
	var i := int(fx)
	var j := int(fz)
	var h: PackedFloat32Array = g["h"]
	var a := lerpf(h[j * n + i], h[j * n + i + 1], fx - i)
	var b := lerpf(h[(j + 1) * n + i], h[(j + 1) * n + i + 1], fx - i)
	return lerpf(a, b, fz - j)


func _bend(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y - (x * x + z * z) / (2.0 * Game.earth.radius), z)


## Called by WorldView every frame with the floating origin.
func place(origin: BigVec) -> void:
	if man.is_empty():
		return
	var e: CelestialBody = Game.earth
	var c := e.pos.copy()
	var r := e.radius + flat_h
	c.add_xyz(up.x * r, up.y * r, up.z * r)
	position = c.rel(origin)
	var cam := basis.inverse() * -position          # ship (world origin) in region coords
	var ext: Array = man["extent"]
	var near := cam.y < 25000.0 and cam.x > float(ext[0]) - 15000.0 and cam.x < float(ext[2]) + 15000.0 \
		and cam.z > float(ext[1]) - 15000.0 and cam.z < float(ext[3]) + 15000.0
	visible = near
	if near != active:
		active = near
		if near and _water == null:
			_build_water()
	if not near:
		return
	var cs := float(man["chunk"])
	var reach := LOAD_R + maxf(cam.y - 500.0, 0.0) * 0.6
	for k: String in man["chunks"]:
		var ix := int(k.get_slice("_", 0))
		var iz := int(k.get_slice("_", 1))
		var d := Vector2(cam.x, cam.z).distance_to(Vector2((ix + 0.5) * cs, (iz + 0.5) * cs))
		if d < reach and not chunks.has(k) and not _queue.has(k):
			_queue.append(k)
		elif d > reach + DROP_R - LOAD_R and chunks.has(k):
			(chunks[k] as Node).queue_free()
			chunks.erase(k)
			grids.erase(k)
	if not _queue.is_empty():          # one chunk per frame keeps the frame time smooth
		_queue.sort_custom(func(a: String, b: String) -> bool:
			return Vector2(cam.x, cam.z).distance_to(_cc(a, cs)) < Vector2(cam.x, cam.z).distance_to(_cc(b, cs)))
		_build_chunk(_queue.pop_front())


func _cc(k: String, cs: float) -> Vector2:
	return Vector2((int(k.get_slice("_", 0)) + 0.5) * cs, (int(k.get_slice("_", 1)) + 0.5) * cs)


# ------------------------------------------------------------------ materials
func _make_mats() -> void:
	var vc := func(rough: float, metal: float = 0.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = rough
		m.metallic = metal
		return m
	mats["terrain"] = vc.call(0.95)
	mats["road"] = vc.call(0.85)
	mats["roof"] = vc.call(0.8)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.06, 0.12, 0.16)
	water.roughness = 0.08
	water.metallic = 0.3
	mats["water"] = water
	# window atlas: rows of windows on a wall texture (u = metres / 3, v = storeys)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var lit := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1))
	lit.fill(Color(0, 0, 0))
	for y in range(18, 46):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(0.18, 0.22, 0.27))
			lit.set_pixel(x, y, Color(1.0, 0.78, 0.45))
	var wm := StandardMaterial3D.new()
	wm.vertex_color_use_as_albedo = true
	wm.albedo_texture = ImageTexture.create_from_image(img)
	wm.emission_enabled = true
	wm.emission_texture = ImageTexture.create_from_image(lit)
	wm.emission_energy_multiplier = 0.0
	wm.roughness = 0.85
	wm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mats["wall"] = wm
	mats["tree_c"] = _flat(Color(0.1, 0.2, 0.1))
	mats["tree_d"] = _flat(Color(0.2, 0.32, 0.12))
	mats["mark"] = _flat(Color(0.85, 0.75, 0.3))
	mats["rail"] = _flat(Color(0.25, 0.2, 0.18))


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _process(_dt: float) -> void:
	if active:   # windows light up at dusk
		var night := 1.0 - smoothstep(-0.05, 0.15, Game.sun_dir.normalized().dot(up))
		(mats["wall"] as StandardMaterial3D).emission_energy_multiplier = night * 1.6


# ------------------------------------------------------------------ building the meshes
func _build_water() -> void:
	_water = Node3D.new()
	add_child(_water)
	var p := dir + "/water.json"
	if FileAccess.file_exists(p):
		var polys: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(polys) == TYPE_ARRAY:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for poly: Array in polys:
				_poly_fill(st, poly, func(_x: float, _z: float) -> float: return 0.3, 40.0)
			_add_mesh(_water, st, mats["water"])


func _build_chunk(k: String) -> void:
	var p := dir + "/c_%s.json" % k
	if not FileAccess.file_exists(p):
		chunks[k] = Node3D.new()
		return
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
	var node := Node3D.new()
	node.name = "C_" + k
	add_child(node)
	chunks[k] = node
	var n := int(c["n"])
	var hs := PackedFloat32Array()
	for v in c["h"]:
		hs.append(float(v) * 0.1)
	var o := Vector2(float(c["o"][0]), float(c["o"][1]))
	grids[k] = {"n": n, "o": o, "h": hs}
	var gh := func(x: float, z: float) -> float: return ground(x, z)
	_terrain(node, c, n, o, hs)
	_buildings(node, c.get("b", []), gh)
	_roads(node, c.get("r", []), c.get("rl", []), gh)
	_trees(node, c.get("t", []), gh)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for poly: Array in c.get("w", []):
		any = true
		_poly_fill(st, poly, func(x: float, z: float) -> float: return ground(x, z) + 0.2, 0.0)
	if any:
		_add_mesh(node, st, mats["water"])


func _terrain(node: Node3D, c: Dictionary, n: int, o: Vector2, hs: PackedFloat32Array) -> void:
	var cs := float(man["chunk"])
	var lus: Array = c.get("lu", [])
	var polys: Array = []
	for l: Array in lus:
		var pp := PackedVector2Array()
		for q: Array in l[1]:
			pp.append(Vector2(q[0], q[1]))
		polys.append([int(l[0]), pp])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var x := o.x + i * cs / (n - 1)
			var z := o.y + j * cs / (n - 1)
			var cls := 0
			for pl: Array in polys:
				if Geometry2D.is_point_in_polygon(Vector2(x, z), pl[1]):
					cls = pl[0]
			var col: Color = LU_COL[cls % LU_COL.size()]
			var nz := sin(x * 0.013 + z * 0.007) * 0.04 + sin(x * 0.051 - z * 0.043) * 0.03
			st.set_color(col.lightened(nz) if nz > 0.0 else col.darkened(-nz))
			st.add_vertex(_bend(x, hs[j * n + i], z))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + n)
	st.generate_normals()
	_add_mesh(node, st, mats["terrain"])


func _wall_col(b: Dictionary) -> Color:
	var h := hash(b["p"][0]) % 1000 / 1000.0
	match str(b["mat"]):
		"brick":
			return Color(0.5, 0.24, 0.18).lerp(Color(0.62, 0.34, 0.25), h)
		"metal", "steel":
			return Color(0.6, 0.62, 0.64)
		"stone", "concrete":
			return Color(0.66, 0.64, 0.6)
	# Atlantic Canada clapboard: whites, greys, soft blues / yellows / reds
	var pal := [Color(0.92, 0.92, 0.9), Color(0.75, 0.78, 0.8), Color(0.6, 0.7, 0.8), Color(0.9, 0.84, 0.6), Color(0.68, 0.3, 0.25), Color(0.5, 0.6, 0.55)]
	return pal[int(h * pal.size()) % pal.size()]


func _buildings(node: Node3D, bs: Array, gh: Callable) -> void:
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roofs := SurfaceTool.new()
	roofs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in bs:
		var pts := PackedVector2Array()
		for q: Array in b["p"]:
			pts.append(Vector2(q[0], q[1]))
		if pts.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(pts):
			pts.reverse()
		var cen := Vector2.ZERO
		for q in pts:
			cen += q
		cen /= pts.size()
		var g0: float = gh.call(cen.x, cen.y) - 0.3
		var h := float(b["h"])
		var wc := _wall_col(b)
		walls.set_color(wc)
		var run := 0.0
		for i in pts.size():
			var a := pts[i]
			var c := pts[(i + 1) % pts.size()]
			var ln := a.distance_to(c)
			var u0 := run / 3.2
			var u1 := (run + ln) / 3.2
			run += ln
			var v1 := h / 3.0
			var p00 := _bend(a.x, g0, a.y)
			var p10 := _bend(c.x, g0, c.y)
			var p01 := _bend(a.x, g0 + h, a.y)
			var p11 := _bend(c.x, g0 + h, c.y)
			for tri: Array in [[p00, Vector2(u0, v1)], [p11, Vector2(u1, 0)], [p10, Vector2(u1, v1)], [p00, Vector2(u0, v1)], [p01, Vector2(u0, 0)], [p11, Vector2(u1, 0)]]:
				walls.set_uv(tri[1])
				walls.add_vertex(tri[0])
		var roof := str(b["roof"])
		var rc := Color(0.22, 0.22, 0.24) if str(b["mat"]) != "wood" else Color(0.25, 0.22, 0.2).lerp(Color(0.35, 0.18, 0.15), hash(b["p"][0]) % 3 / 3.0)
		roofs.set_color(rc)
		var top := g0 + h
		if roof in ["gabled", "hipped", "pyramidal"] and pts.size() >= 4:
			# ridge along the long axis of the oriented bounding box
			var ax := (pts[1] - pts[0]).normalized()
			if pts[1].distance_to(pts[0]) < pts[2].distance_to(pts[1]):
				ax = (pts[2] - pts[1]).normalized()
			var ay := Vector2(-ax.y, ax.x)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q in pts:
				var l := Vector2((q - cen).dot(ax), (q - cen).dot(ay))
				lo = lo.min(l)
				hi = hi.max(l)
			var half_w := (hi.y - lo.y) * 0.5
			var rise := clampf(half_w * 0.75, 1.0, 6.0)
			var inset := half_w if roof != "gabled" else 0.0
			var mid := cen + ay * (lo.y + hi.y) * 0.5
			var r0 := mid + ax * (lo.x + minf(inset, (hi.x - lo.x) * 0.5))
			var r1 := mid + ax * (hi.x - minf(inset, (hi.x - lo.x) * 0.5))
			# each wall edge rises to its projection on the ridge: long sides become roof planes,
			# short sides gable ends (gabled) or hips (hipped / pyramidal)
			var proj := func(q: Vector2) -> Vector3:
				var t := clampf((q - r0).dot(ax) / maxf((r1 - r0).dot(ax), 0.01), 0.0, 1.0) if r0 != r1 else 0.0
				var rp := r0.lerp(r1, t)
				return _bend(rp.x, top + rise, rp.y)
			for i in pts.size():
				var a := pts[i]
				var c := pts[(i + 1) % pts.size()]
				var A := _bend(a.x, top, a.y)
				var C := _bend(c.x, top, c.y)
				var RA: Vector3 = proj.call(a)
				var RC: Vector3 = proj.call(c)
				roofs.add_vertex(A)
				roofs.add_vertex(RA)
				roofs.add_vertex(C)
				if RA.distance_to(RC) > 0.05:
					roofs.add_vertex(RA)
					roofs.add_vertex(RC)
					roofs.add_vertex(C)
		else:
			var idx := Geometry2D.triangulate_polygon(pts)
			for i in range(0, idx.size(), 3):
				for t in [0, 2, 1]:
					var q := pts[idx[i + t]]
					roofs.add_vertex(_bend(q.x, top, q.y))
		if b.get("steeple", false):
			var sh := maxf(h * 1.6, 18.0)
			var sp := ProcGen.mesh_node(ProcGen.cyl(0.0, 2.2, sh, 8), _flat(Color(0.85, 0.85, 0.82)))
			sp.position = _bend(cen.x, top + sh * 0.5, cen.y)
			node.add_child(sp)
	walls.generate_normals()
	roofs.generate_normals()
	_add_mesh(node, walls, mats["wall"])
	_add_mesh(node, roofs, mats["roof"], true)


func _strip(st: SurfaceTool, pts: Array, w: float, yf: Callable) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x) * w * 0.5
		var ya: float = yf.call(a.x, a.y, i)
		var yb: float = yf.call(b.x, b.y, i + 1)
		var q := [_bend(a.x - nrm.x, ya, a.y - nrm.y), _bend(a.x + nrm.x, ya, a.y + nrm.y), _bend(b.x + nrm.x, yb, b.y + nrm.y), _bend(b.x - nrm.x, yb, b.y - nrm.y)]
		for t in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(q[t])


func _roads(node: Node3D, rs: Array, rails: Array, gh: Callable) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mk := SurfaceTool.new()
	mk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any_mk := false
	for r: Dictionary in rs:
		var pts: Array = r["p"]
		var br := int(r.get("br", 0))
		var lift := 0.15 + br * 7.0
		var ends := [float(gh.call(pts[0][0], pts[0][1])), float(gh.call(pts[-1][0], pts[-1][1]))]
		var yf := func(x: float, z: float, _i: int) -> float:
			return (maxf(ends[0], ends[1]) + lift) if br > 0 else float(gh.call(x, z)) + lift
		st.set_color(ROAD_COL.get(str(r.get("c", "")), Color(0.26, 0.26, 0.27)))
		_strip(st, pts, float(r["w"]), yf)
		if str(r.get("c", "")) in ["motorway", "trunk", "primary", "secondary", "tertiary"]:
			any_mk = true
			_strip(mk, pts, 0.18, func(x: float, z: float, i: int) -> float: return yf.call(x, z, i) + 0.03)
	for r: Dictionary in rails:
		st.set_color(Color(0.3, 0.27, 0.24))
		_strip(st, r["p"], 3.0, func(x: float, z: float, _i: int) -> float: return float(gh.call(x, z)) + 0.25)
	st.generate_normals()
	_add_mesh(node, st, mats["road"])
	if any_mk:
		_add_mesh(node, mk, mats["mark"])


func _trees(node: Node3D, ts: Array, gh: Callable) -> void:
	for kind in [0, 1]:
		var sel := ts.filter(func(t: Array) -> bool: return int(t[2]) == kind)
		if sel.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ProcGen.cyl(0.0, 2.6, 11.0, 7) if kind == 1 else ProcGen.sphere(3.4, 8, 5)
		mm.instance_count = sel.size()
		for i in sel.size():
			var t: Array = sel[i]
			var s := 0.7 + fmod(absf(float(t[0]) * 13.1 + float(t[1]) * 7.7), 0.6)
			var y: float = gh.call(float(t[0]), float(t[1])) + (5.5 if kind == 1 else 5.0) * s
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * (1.0 if kind == 1 else 1.25), s)), _bend(float(t[0]), y, float(t[1]))))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mats["tree_c" if kind == 1 else "tree_d"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)


func _poly_fill(st: SurfaceTool, poly: Array, yf: Callable, step: float) -> void:
	var pts := PackedVector2Array()
	for q: Array in poly:
		pts.append(Vector2(q[0], q[1]))
	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		for t in [0, 2, 1]:
			var q := pts[idx[i + t]]
			st.add_vertex(_bend(q.x, yf.call(q.x, q.y), q.y))


func _add_mesh(node: Node3D, st: SurfaceTool, m: Material, two_sided := false) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	if two_sided:
		var m2 := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m2
	mi.extra_cull_margin = 50.0
	node.add_child(mi)
