class_name RegionView
extends Node3D
## Low-altitude detail region (OSM + DEM) built by tools/build_region.py, turned into meshes at
## runtime and streamed by distance: terrain with landuse colours, buildings (walls, gable /
## hipped / flat roofs, steeples, window atlas lit at night), instanced trees, water, roads
## with markings + bridges, railways. Placed on the real-size Earth at its true lat/lon and
## true elevation: every vertex goes local metres -> lat/lon -> planet (double precision), so
## it lines up with the LOD terrain, the imagery and the physics. Missing region = no-op.
## Chunks are parsed and meshed on worker threads (WorkerThreadPool, up to MAX_TASKS at once,
## nearest first) and attached on the main thread, one per frame.
## Physics: height_at() reads the builder's dem.bin (ground or water surface, immutable, so
## it's safe from the LOD worker threads) and blends into the global terrain over 500 m.

const LOAD_R := 3500.0
const DROP_R := 5200.0
const MAX_TASKS := 3
const EDGE_BLEND := 500.0
const NEED_VER := 3
const LU_COL := [Color(0.27, 0.36, 0.17), Color(0.32, 0.45, 0.2), Color(0.52, 0.5, 0.3), Color(0.16, 0.26, 0.12),
	Color(0.42, 0.42, 0.36), Color(0.46, 0.44, 0.42), Color(0.44, 0.42, 0.4), Color(0.2, 0.24, 0.2),
	Color(0.24, 0.3, 0.2), Color(0.7, 0.65, 0.5), Color(0.3, 0.3, 0.3)]
const ROAD_COL := {"motorway": Color(0.2, 0.2, 0.21), "trunk": Color(0.21, 0.21, 0.22), "primary": Color(0.23, 0.23, 0.24),
	"footway": Color(0.55, 0.5, 0.45), "path": Color(0.5, 0.45, 0.35), "cycleway": Color(0.4, 0.2, 0.18), "track": Color(0.45, 0.38, 0.28), "stream": Color(0.1, 0.22, 0.34)}

var dir := ""
var man: Dictionary = {}
var up := Vector3.UP
var base := 0.0                 # region base elevation (m): chunk heights are relative to it
var lat0 := 0.0
var lon0 := 0.0
var kx := 1.0                   # builder projection (tools/build_region.py Proj)
var kz := 110540.0
var _enu: PackedFloat64Array    # geo-space east, up, north at (lat0, lon0)
var _gfg: Basis                 # game -> geo
var _r0 := 0.0                  # planet radius + base
var dem := PackedByteArray()    # int16 LE, 0.5 m, absolute (ground or water surface)
var dem_o := Vector2.ZERO
var dem_step := 30.0
var dem_nx := 0
var dem_nz := 0
var chunks := {}        # key -> Node3D
var grids := {}         # key -> {o, n, h: PackedFloat32Array}
var _queue: Array = []
var _water: Node3D
var mats := {}
var active := false
var _pending := {}      # key -> WorkerThreadPool task id
var _done: Array = []   # [key, [node, grid]] finished by workers
var _mx := Mutex.new()


func _ready() -> void:
	var name_ := str(Settings.cli.get("region", "fredericton"))
	if dir == "":       # World sets dir when it picks the region nearest the camera
		dir = str(Settings.cli.get("region-dir", Geo.asset_dir() + "/regions/" + name_))
	var mf := dir + "/manifest.json"
	if not FileAccess.file_exists(mf):
		return
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(mf))
	if typeof(m) != TYPE_DICTIONARY:
		return
	if int((m as Dictionary).get("version", 0)) < NEED_VER or not (m as Dictionary).has("dem"):
		push_warning("Region '%s' is an old build (v%d): rebuild it (tools/area_manager.py build %s, or tools/fetch_assets.sh)" % [
			str(m.get("name", name_)), int(m.get("version", 0)), str(m.get("name", name_))])
		return
	man = m
	lat0 = float(man["lat0"])
	lon0 = float(man["lon0"])
	kx = 111320.0 * cos(deg_to_rad(lat0))
	base = float(man.get("base_elev", 0.0))
	var la := deg_to_rad(lat0)
	var lo := deg_to_rad(lon0)
	_enu = PackedFloat64Array([cos(lo), 0.0, sin(lo),
		cos(la) * sin(lo), sin(la), -cos(la) * cos(lo),
		-sin(la) * sin(lo), cos(la), sin(la) * cos(lo)])
	var gfg := Geo.game_from_geo()
	_gfg = gfg.inverse()
	up = Geo.game_dir(lat0, lon0).normalized()
	var east := (gfg * Vector3(_enu[0], _enu[1], _enu[2])).normalized()
	var north := (gfg * Vector3(_enu[6], _enu[7], _enu[8])).normalized()
	basis = Basis(east, up, -north)       # local x = east, y = up, z = south (like the builder)
	var dm: Dictionary = man["dem"]
	dem = FileAccess.get_file_as_bytes(dir + "/" + str(dm["file"]))
	dem_o = Vector2(float(dm["o"][0]), float(dm["o"][1]))
	dem_step = float(dm["step"])
	dem_nx = int(dm["nx"])
	dem_nz = int(dm["nz"])
	if dem.size() != dem_nx * dem_nz * 2:
		push_warning("Region dem.bin size mismatch: physics uses the global terrain")
		dem = PackedByteArray()
	_r0 = Game.earth.radius + base
	_make_mats()
	_register()
	Game.mission_loaded.connect(_register)
	print("Region '%s': %d chunks %s" % [man["name"], (man["chunks"] as Array).size(), str(man.get("counts", {}))])


## The ground follows the region's DEM (physics + the planet LOD mesh). Idempotent.
func _register() -> void:
	if not dem.is_empty():
		Game.earth.height_hook = height_at
		Game.earth.render_hook = lod_height


## Height for the planet LOD mesh: the region's own terrain mesh covers it, so the LOD surface
## sinks 2.5 m under it inside the region (no z-fighting), rising back over the edge blend.
func lod_height(d: Vector3) -> float:
	var h := height_at(d)
	if is_nan(h):
		return h
	var g := _gfg * d
	var x := (rad_to_deg(atan2(g.x, -g.z)) - lon0) * kx
	var z := -(rad_to_deg(asin(clampf(g.y, -1.0, 1.0))) - lat0) * kz
	var fx := (x - dem_o.x) / dem_step
	var fz := (z - dem_o.y) / dem_step
	var edge := minf(minf(fx, dem_nx - 1 - fx), minf(fz, dem_nz - 1 - fz)) * dem_step
	return h - 2.5 * smoothstep(EDGE_BLEND, EDGE_BLEND * 2.0, edge)


## Local metres (x east, y up above the base, z south) -> lat / lon.
func local_ll(x: float, z: float) -> Vector2:
	return Vector2(lat0 - z / kz, lon0 + x / kx)


## Local metres -> this node's space, exactly (true lat/lon on the sphere, double maths).
func _local(x: float, y: float, z: float) -> Vector3:
	var la := deg_to_rad(lat0 - z / kz)
	var lo := deg_to_rad(lon0 + x / kx)
	var gx := cos(la) * sin(lo)
	var gy := sin(la)
	var gz := -cos(la) * cos(lo)
	var r := _r0 + y
	var e := _enu
	return Vector3((e[0] * gx + e[1] * gy + e[2] * gz) * r,
		(e[3] * gx + e[4] * gy + e[5] * gz) * r - _r0,
		-(e[6] * gx + e[7] * gy + e[8] * gz) * r)


## Absolute height (m above the sphere) at a game direction; NAN outside the region. Blends
## into the global terrain over the last EDGE_BLEND m. Thread-safe (immutable data only).
func height_at(d: Vector3) -> float:
	if dem.is_empty():
		return NAN
	var g := _gfg * d
	var lat := rad_to_deg(asin(clampf(g.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(g.x, -g.z))
	var x := (lon - lon0) * kx
	var z := -(lat - lat0) * kz
	var fx := (x - dem_o.x) / dem_step
	var fz := (z - dem_o.y) / dem_step
	if fx < 0.0 or fz < 0.0 or fx > dem_nx - 1 or fz > dem_nz - 1:
		return NAN
	var i := mini(int(fx), dem_nx - 2)
	var j := mini(int(fz), dem_nz - 2)
	var tx := fx - i
	var tz := fz - j
	var k := (j * dem_nx + i) * 2
	var row := dem_nx * 2
	var a := lerpf(dem.decode_s16(k), dem.decode_s16(k + 2), tx)
	var b := lerpf(dem.decode_s16(k + row), dem.decode_s16(k + row + 2), tx)
	var h := lerpf(a, b, tz) * 0.5
	var edge := minf(minf(fx, dem_nx - 1 - fx), minf(fz, dem_nz - 1 - fz)) * dem_step
	if edge < EDGE_BLEND:
		var e: CelestialBody = Game.earth
		var gh := e.terrain.sample(d).x if e.terrain != null else e.natural_height(d, true)
		h = lerpf(gh, h, smoothstep(0.0, EDGE_BLEND, edge))
	return h


## Terrain height (m above the region base) at local x/z, from loaded chunk grids.
func ground(x: float, z: float) -> float:
	var cs := float(man.get("chunk", 1000.0))
	return _grid_h(grids.get("%d_%d" % [floori(x / cs), floori(z / cs)], {}), x, z, cs)


static func _grid_h(g: Dictionary, x: float, z: float, cs: float) -> float:
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


## Called by WorldView every frame with the floating origin.
func place(origin: BigVec) -> void:
	if man.is_empty():
		return
	var e: CelestialBody = Game.earth
	var c := e.pos.copy()
	c.add_xyz(up.x * _r0, up.y * _r0, up.z * _r0)
	position = c.rel(origin)
	var cam := basis.inverse() * -position          # ship (world origin) in region coords
	var ext: Array = man["extent"]
	var near := cam.y < 25000.0 and cam.x > float(ext[0]) - 15000.0 and cam.x < float(ext[2]) + 15000.0 \
		and cam.z > float(ext[1]) - 15000.0 and cam.z < float(ext[3]) + 15000.0
	visible = near
	active = near
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
	if not _queue.is_empty():
		_queue.sort_custom(func(a: String, b: String) -> bool:
			return Vector2(cam.x, cam.z).distance_to(_cc(a, cs)) < Vector2(cam.x, cam.z).distance_to(_cc(b, cs)))
	pump()


## Start worker builds (nearest first) and attach at most one finished chunk per frame.
func pump() -> void:
	while not _queue.is_empty() and _pending.size() < MAX_TASKS:
		var k: String = _queue.pop_front()
		if chunks.has(k) or _pending.has(k):
			continue
		_pending[k] = WorkerThreadPool.add_task(func() -> void:
			var r := _make_chunk(k)
			_mx.lock()
			_done.append([k, r])
			_mx.unlock(), false, "region chunk " + k)
	_mx.lock()
	var item: Array = _done.pop_front() if not _done.is_empty() else []
	_mx.unlock()
	if item.is_empty():
		return
	var k2: String = item[0]
	WorkerThreadPool.wait_for_task_completion(_pending[k2])
	_pending.erase(k2)
	_attach(k2, item[1])


func busy() -> bool:
	return not (_queue.is_empty() and _pending.is_empty())


func _exit_tree() -> void:
	for tid: int in _pending.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_pending.clear()
	if Game.earth and Game.earth.height_hook == Callable(self, "height_at"):
		Game.earth.height_hook = Callable()
		Game.earth.render_hook = Callable()


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
	# water: deep blue body + Fresnel sky reflection + sun glint + small waves (water.gdshader)
	mats["water"] = ProcGen.shader_mat("res://shaders/water.gdshader", {})
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
	if active:   # windows light up at dusk; the water reflects the sky's colour
		var el := Game.sun_dir.normalized().dot(up)
		var night := 1.0 - smoothstep(-0.05, 0.15, el)
		(mats["wall"] as StandardMaterial3D).emission_energy_multiplier = night * 1.6
		var day := Color(0.42, 0.6, 0.85).lerp(Color(0.75, 0.55, 0.45), 1.0 - smoothstep(0.0, 0.25, el))
		var sky := Color(0.01, 0.015, 0.03).lerp(day, smoothstep(-0.12, 0.05, el))
		(mats["water"] as ShaderMaterial).set_shader_parameter("sky_col", sky)


# ------------------------------------------------------------------ building the meshes
func _build_water() -> void:
	pass   # BUILD_VER 3: water is per chunk (levels on the terrain grid), see _water_mesh


## Synchronous build (tests); streaming uses _make_chunk on worker threads + _attach.
func _build_chunk(k: String) -> void:
	_attach(k, _make_chunk(k))


func _attach(k: String, r: Array) -> void:
	if chunks.has(k):
		(r[0] as Node).queue_free()
		return
	chunks[k] = r[0]
	add_child(r[0])
	if not (r[1] as Dictionary).is_empty():
		grids[k] = r[1]


## Parse + mesh one chunk into an off-tree node. Thread-safe: touches no shared state except
## the read-only manifest / materials. Returns [node, height grid].
func _make_chunk(k: String) -> Array:
	var p := dir + "/c_%s.json" % k
	var node := Node3D.new()
	node.name = "C_" + k
	if not FileAccess.file_exists(p):
		return [node, {}]
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
	var n := int(c["n"])
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var hl: Array = c["h"]
	for i in hl.size():
		hs[i] = float(hl[i]) * 0.1
	var o := Vector2(float(c["o"][0]), float(c["o"][1]))
	var grid := {"n": n, "o": o, "h": hs}
	var cs := float(man.get("chunk", 1000.0))
	var gh := func(x: float, z: float) -> float: return _grid_h(grid, x, z, cs)
	_terrain(node, c, n, o, hs)
	_buildings(node, c.get("b", []), gh)
	_roads(node, c.get("r", []), c.get("rl", []), gh)
	_trees(node, c.get("t", []), gh)
	if c.get("wl") is Array:
		_water_mesh(node, c["wl"], n, o)
	return [node, grid]


## Flat water surface over every grid cell that touches water, at the builder's water level
## (the bed is carved below it and the banks lifted above it, so the terrain cuts a clean,
## smooth shoreline through it).
func _water_mesh(node: Node3D, wl: Array, n: int, o: Vector2) -> void:
	var cs := float(man["chunk"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var stp := cs / (n - 1)
	for j in n - 1:
		for i in n - 1:
			var ids: Array[int] = [j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i]
			var sum := 0.0
			var cnt := 0
			for q: int in ids:
				if int(wl[q]) > -32768:
					sum += float(wl[q]) * 0.1
					cnt += 1
			if cnt == 0:
				continue
			any = true
			var avg := sum / cnt
			var pts: Array = []
			var offs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for t in 4:
				var q: int = ids[t]
				var y := float(wl[q]) * 0.1 if int(wl[q]) > -32768 else avg
				var x := o.x + (i + offs[t].x) * stp
				var z := o.y + (j + offs[t].y) * stp
				pts.append([_local(x, y, z), Vector2(x, z)])
			for t: int in [0, 1, 3, 1, 2, 3]:
				var uv: Vector2 = pts[t][1]
				st.set_uv(uv)
				st.set_normal((_local(uv.x, 1.0, uv.y) - _local(uv.x, 0.0, uv.y)).normalized())
				st.add_vertex(pts[t][0])
	if any:
		_add_mesh(node, st, mats["water"])


func _terrain(node: Node3D, c: Dictionary, n: int, o: Vector2, hs: PackedFloat32Array) -> void:
	var cs := float(man["chunk"])
	var lg: Array = c.get("lg", [])      # v2: per-vertex landuse class, precomputed by the builder
	var lus: Array = c.get("lu", []) if lg.is_empty() else []
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
			var cls := int(lg[j * n + i]) if lg.size() == n * n else 0
			for pl: Array in polys:
				if Geometry2D.is_point_in_polygon(Vector2(x, z), pl[1]):
					cls = pl[0]
			var col: Color = LU_COL[cls % LU_COL.size()]
			var nz := sin(x * 0.013 + z * 0.007) * 0.04 + sin(x * 0.051 - z * 0.043) * 0.03
			st.set_color(col.lightened(nz) if nz > 0.0 else col.darkened(-nz))
			st.add_vertex(_local(x, hs[j * n + i], z))
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
		var g0 := INF                 # sit on the lowest corner (no floating downhill walls)
		for q in pts:
			g0 = minf(g0, float(gh.call(q.x, q.y)))
		g0 -= 0.3
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
			var p00 := _local(a.x, g0, a.y)
			var p10 := _local(c.x, g0, c.y)
			var p01 := _local(a.x, g0 + h, a.y)
			var p11 := _local(c.x, g0 + h, c.y)
			for tri: Array in [[p00, Vector2(u0, v1)], [p11, Vector2(u1, 0)], [p10, Vector2(u1, v1)], [p00, Vector2(u0, v1)], [p01, Vector2(u0, 0)], [p11, Vector2(u1, 0)]]:
				walls.set_uv(tri[1])
				walls.add_vertex(tri[0])
		var roof := str(b["roof"])
		var rc := Color(0.22, 0.22, 0.24) if str(b["mat"]) != "wood" else Color(0.25, 0.22, 0.2).lerp(Color(0.35, 0.18, 0.15), hash(b["p"][0]) % 3 / 3.0)
		roofs.set_color(rc)
		var top := g0 + h
		if roof in ["gabled", "hipped", "pyramidal"] and pts.size() >= 4:
			# ridge along the longest wall (the long axis of the footprint)
			var ax := Vector2.RIGHT
			var best := -1.0
			for i in pts.size():
				var e2 := pts[(i + 1) % pts.size()] - pts[i]
				if e2.length() > best:
					best = e2.length()
					ax = e2.normalized()
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
				return _local(rp.x, top + rise, rp.y)
			for i in pts.size():
				var a := pts[i]
				var c := pts[(i + 1) % pts.size()]
				var A := _local(a.x, top, a.y)
				var C := _local(c.x, top, c.y)
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
					roofs.add_vertex(_local(q.x, top, q.y))
		if b.get("steeple", false):
			var sh := maxf(h * 1.6, 18.0)
			var sp := ProcGen.mesh_node(ProcGen.cyl(0.0, 2.2, sh, 8), _flat(Color(0.85, 0.85, 0.82)))
			sp.position = _local(cen.x, top + sh * 0.5, cen.y)
			node.add_child(sp)
	walls.generate_normals()
	roofs.generate_normals()
	_add_mesh(node, walls, mats["wall"])
	_add_mesh(node, roofs, mats["roof"], true)


## Split polyline segments to <= max_len so the ribbon follows the ground between OSM nodes.
static func _subdiv(pts: Array, max_len: float) -> Array:
	var out: Array = [pts[0]]
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1][0], pts[i - 1][1])
		var b := Vector2(pts[i][0], pts[i][1])
		var k := maxi(1, ceili(a.distance_to(b) / max_len))
		for t in range(1, k + 1):
			var p := a.lerp(b, float(t) / k)
			out.append([p.x, p.y])
	return out


func _strip(st: SurfaceTool, pts0: Array, w: float, yf: Callable) -> void:
	var pts := _subdiv(pts0, 15.0)
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x) * w * 0.5
		var ya: float = yf.call(a.x, a.y, i)
		var yb: float = yf.call(b.x, b.y, i + 1)
		var q := [_local(a.x - nrm.x, ya, a.y - nrm.y), _local(a.x + nrm.x, ya, a.y + nrm.y), _local(b.x + nrm.x, yb, b.y + nrm.y), _local(b.x - nrm.x, yb, b.y - nrm.y)]
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
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * (1.0 if kind == 1 else 1.25), s)), _local(float(t[0]), y, float(t[1]))))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mats["tree_c" if kind == 1 else "tree_d"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)


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
