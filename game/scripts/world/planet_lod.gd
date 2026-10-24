class_name PlanetLOD
extends Node3D
## Real-size planet surface: a chunked cube-sphere quadtree (6 faces, up to ~15 levels, 32x32
## cells per chunk + skirts). Chunks are meshed on worker threads from the SAME height function
## the physics uses (EarthTerrain / CelestialBody), with every vertex stored relative to its
## chunk centre (double-precision maths, so there is no float32 jitter on a 6371 km planet).
## Each frame the chunk nodes are placed camera-relative (floating origin) and, far away, in
## "scaled space" (shrunk about the camera by s; same angular size, inside the far plane).
## A parent stays on screen until all 4 children are ready (no holes while streaming); chunks
## behind the horizon are culled; unused chunks are evicted (LRU).

const N := 32                  # cells per chunk edge
const MAX_TASKS := 6
const KEEP := 1400             # cached chunk meshes before LRU eviction
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)]]

var body: CelestialBody
var mat: Material
var sampler: Callable           # dir -> Vector3(height m, water 0..1, pack coverage 0..1); thread-safe
var max_level := 15
var split_k := 2.0              # split while camera distance < split_k * chunk edge
var hmax := 9000.0              # highest terrain (horizon culling)
var chunks := {}                # key -> {node, mesh, c: [x, y, z] (planet space, doubles), r, edge, hc, used}
var visible_count := 0
var built_count := 0
var _pending := {}              # key -> task id
var _done: Array = []
var _mx := Mutex.new()
var _frame := 0
var _shown: Array = []


func setup(b: CelestialBody, m: Material, fn: Callable, levels: int) -> void:
	body = b
	mat = m
	sampler = fn
	max_level = levels
	hmax = 9000.0 if b.has_atmo else 11000.0
	# the 6 faces + their 24 children are built up front: there is always a planet on screen
	for f in 6:
		_attach(_key(f, 0, 0, 0), _build(_key(f, 0, 0, 0)))
		for c in 4:
			var k := _key(f, 1, c % 2, c / 2)
			_attach(k, _build(k))


static func _key(face: int, level: int, x: int, y: int) -> int:
	return ((face * 32 + level) << 40) | (x << 20) | y


static func _kface(k: int) -> int:
	return (k >> 40) / 32


static func _klevel(k: int) -> int:
	return (k >> 40) % 32


static func _kx(k: int) -> int:
	return (k >> 20) & 0xFFFFF


static func _ky(k: int) -> int:
	return k & 0xFFFFF


## Unit direction (as 3 doubles) of face coords (u, v) in [-1, 1] (tangent warp: even cells).
static func _dir(face: int, u: float, v: float) -> Array:
	var f: Array = FACES[face]
	var a := tan(u * PI * 0.25)
	var b := tan(v * PI * 0.25)
	var n: Vector3 = f[0]
	var r: Vector3 = f[1]
	var up: Vector3 = f[2]
	var x := n.x + a * r.x + b * up.x
	var y := n.y + a * r.y + b * up.y
	var z := n.z + a * r.z + b * up.z
	var l := sqrt(x * x + y * y + z * z)
	return [x / l, y / l, z / l]


## Mesh one chunk (worker thread). Returns {mesh, c, r, edge, hc}.
func _build(k: int) -> Dictionary:
	var face := _kface(k)
	var lv := _klevel(k)
	var cx := _kx(k)
	var cy := _ky(k)
	var tiles := float(1 << lv)
	var R := body.radius
	var M := N + 3                       # samples incl. a border ring (normals)
	var px := PackedFloat64Array()
	px.resize(M * M * 3)
	var hs := PackedFloat32Array()
	hs.resize(M * M)
	var wat := PackedFloat32Array()
	wat.resize(M * M)
	var cov := PackedFloat32Array()
	cov.resize(M * M)
	var dirs := PackedFloat32Array()
	dirs.resize(M * M * 3)
	for j in M:
		for i in M:
			var u := (cx + float(i - 1) / N) / tiles * 2.0 - 1.0
			var v := (cy + float(j - 1) / N) / tiles * 2.0 - 1.0
			var d := _dir(face, u, v)
			var dv := Vector3(d[0], d[1], d[2])
			var s: Vector3 = sampler.call(dv)
			var rr: float = R + s.x
			var q := j * M + i
			px[q * 3] = d[0] * rr
			px[q * 3 + 1] = d[1] * rr
			px[q * 3 + 2] = d[2] * rr
			hs[q] = s.x
			wat[q] = s.y
			cov[q] = s.z
			dirs[q * 3] = d[0]
			dirs[q * 3 + 1] = d[1]
			dirs[q * 3 + 2] = d[2]
	# chunk centre (planet space, doubles) = the middle sample
	var mid := (M / 2) * M + M / 2
	var c := [px[mid * 3], px[mid * 3 + 1], px[mid * 3 + 2]]
	var edge := R * PI * 0.5 / tiles
	var skirt := edge * 0.03 + 5.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cust := PackedFloat32Array()
	var uv2 := PackedVector2Array()
	var rad := 0.0
	var hc: float = hs[mid]
	for pass_ in 2:            # 0 = surface grid, 1 = skirt ring (same order as the edge walk)
		var idxs: Array = []
		if pass_ == 0:
			for j in range(1, N + 2):
				for i in range(1, N + 2):
					idxs.append(j * M + i)
		else:
			for t in N:
				idxs.append(1 * M + 1 + t)               # top edge, left -> right
			for t in N:
				idxs.append((1 + t) * M + N + 1)         # right edge, top -> bottom
			for t in N:
				idxs.append((N + 1) * M + N + 1 - t)     # bottom edge, right -> left
			for t in N:
				idxs.append((N + 1 - t) * M + 1)         # left edge, bottom -> top
		for q: int in idxs:
			var drop := skirt if pass_ == 1 else 0.0
			var dx: float = dirs[q * 3]
			var dy: float = dirs[q * 3 + 1]
			var dz: float = dirs[q * 3 + 2]
			var p := Vector3(px[q * 3] - dx * drop - c[0], px[q * 3 + 1] - dy * drop - c[1], px[q * 3 + 2] - dz * drop - c[2])
			verts.append(p)
			rad = maxf(rad, p.length())
			var ql := q - 1
			var qr := q + 1
			var qu := q - M
			var qd := q + M
			var ex := Vector3(px[qr * 3] - px[ql * 3], px[qr * 3 + 1] - px[ql * 3 + 1], px[qr * 3 + 2] - px[ql * 3 + 2])
			var ey := Vector3(px[qd * 3] - px[qu * 3], px[qd * 3 + 1] - px[qu * 3 + 1], px[qd * 3 + 2] - px[qu * 3 + 2])
			var nn := ey.cross(ex).normalized()
			if nn.dot(Vector3(dx, dy, dz)) < 0.0:
				nn = -nn
			norms.append(nn)
			cust.append(dx)
			cust.append(dy)
			cust.append(dz)
			cust.append(hs[q] - drop)
			uv2.append(Vector2(wat[q], cov[q]))
	var W := N + 1
	var ind := PackedInt32Array()
	for j in N:
		for i in N:
			var a := j * W + i
			ind.append_array([a, a + 1, a + W, a + 1, a + W + 1, a + W])
	# skirts: quads between each edge vertex and its dropped copy
	var base := W * W
	var ring: Array = []
	for t in N:
		ring.append(t)
	for t in N:
		ring.append(t * W + N)
	for t in N:
		ring.append(N * W + N - t)
	for t in N:
		ring.append((N - t) * W)
	var rn := ring.size()
	for t in rn:
		var a0: int = ring[t]
		var a1: int = ring[(t + 1) % rn]
		var b0 := base + t
		var b1 := base + (t + 1) % rn
		ind.append_array([a0, b0, a1, a1, b0, b1, a0, a1, b0, a1, b1, b0])   # both windings (cheap, never seen from inside)
	# winding: make the front face point outward
	var tri_n := (verts[ind[1]] - verts[ind[0]]).cross(verts[ind[2]] - verts[ind[0]])
	if tri_n.dot(Vector3(dirs[mid * 3], dirs[mid * 3 + 1], dirs[mid * 3 + 2])) > 0.0:
		for t in range(0, N * N * 6, 3):
			var tmp := ind[t + 1]
			ind[t + 1] = ind[t + 2]
			ind[t + 2] = tmp
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = cust
	arr[Mesh.ARRAY_INDEX] = ind
	# (the ArrayMesh itself is made on the main thread in _attach: RID allocation isn't thread-safe
	# on every rendering backend)
	return {"arr": arr, "c": c, "r": rad, "edge": edge, "hc": hc}


func _attach(k: int, r: Dictionary) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r["arr"], [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	r.erase("arr")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	r["node"] = mi
	r["used"] = _frame
	chunks[k] = r
	built_count += 1


## Per frame: body centre relative to the camera (doubles) and the scaled-space factor s.
func update(brel: PackedFloat64Array, s: float) -> void:
	_frame += 1
	# finished worker meshes -> scene (a few per frame)
	_mx.lock()
	var done := _done.slice(0, 12)      # a dozen uploads per frame at most (no hitches)
	_done = _done.slice(12)
	_mx.unlock()
	for it: Array in done:
		var k: int = it[0]
		WorkerThreadPool.wait_for_task_completion(_pending[k])
		_pending.erase(k)
		if not chunks.has(k):
			_attach(k, it[1])
	var cam := [-brel[0], -brel[1], -brel[2]]
	var D := sqrt(cam[0] * cam[0] + cam[1] * cam[1] + cam[2] * cam[2])
	var R := body.radius
	var cdir := Vector3(cam[0] / D, cam[1] / D, cam[2] / D)
	var hor := acos(clampf(R / D, -1.0, 1.0)) + acos(R / (R + hmax)) if D > R else PI
	var show: Array = []
	var want: Array = []        # [priority, key]
	var stack: Array = []
	for f in 6:
		stack.append(_key(f, 0, 0, 0))
	while not stack.is_empty():
		var k: int = stack.pop_back()
		var ch: Dictionary = chunks.get(k, {})
		if ch.is_empty():
			continue
		ch["used"] = _frame
		var c: Array = ch["c"]
		var cl := sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2])
		var edge: float = ch["edge"]
		var ang_r := float(ch["r"]) / R
		if cdir.angle_to(Vector3(c[0] / cl, c[1] / cl, c[2] / cl)) > hor + ang_r:
			continue                      # behind the horizon
		var dx: float = cam[0] - c[0]
		var dy: float = cam[1] - c[1]
		var dz: float = cam[2] - c[2]
		var dist := maxf(sqrt(dx * dx + dy * dy + dz * dz) - float(ch["r"]) * 0.5, 0.0)
		var lv := _klevel(k)
		if lv < max_level and dist < split_k * edge:
			var kids: Array = []
			var ready := true
			var f := _kface(k)
			for q in 4:
				var kk := _key(f, lv + 1, _kx(k) * 2 + q % 2, _ky(k) * 2 + q / 2)
				kids.append(kk)
				if not chunks.has(kk):
					ready = false
					if not _pending.has(kk):
						want.append([lv * 1.0e9 + dist, kk])
			if ready:
				stack.append_array(kids)
				continue
		show.append(k)
	# hide last frame's set, show this one, placed camera-relative (scaled space far away)
	for k: int in _shown:
		var o: Dictionary = chunks.get(k, {})
		if not o.is_empty():
			(o["node"] as Node3D).visible = false
	for k: int in show:
		var ch2: Dictionary = chunks[k]
		var n: MeshInstance3D = ch2["node"]
		var c2: Array = ch2["c"]
		n.position = Vector3((brel[0] + c2[0]) * s, (brel[1] + c2[1]) * s, (brel[2] + c2[2]) * s)
		n.scale = Vector3.ONE * s
		n.visible = true
	_shown = show
	visible_count = show.size()
	# queue new chunk builds: coarse levels first, then nearest
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for w: Array in want:
		if _pending.size() >= MAX_TASKS:
			break
		var kk: int = w[1]
		if _pending.has(kk):
			continue
		_pending[kk] = WorkerThreadPool.add_task(func() -> void:
			var r := _build(kk)
			_mx.lock()
			_done.append([kk, r])
			_mx.unlock(), false, "planet chunk")
	if chunks.size() > KEEP and _frame % 30 == 0:
		_evict()


func _evict() -> void:
	var ks: Array = chunks.keys().filter(func(k: int) -> bool: return _klevel(k) > 1 and int(chunks[k]["used"]) < _frame - 2)
	ks.sort_custom(func(a: int, b: int) -> bool: return int(chunks[a]["used"]) < int(chunks[b]["used"]))
	for i in mini(ks.size(), chunks.size() - KEEP + 100):
		var k: int = ks[i]
		(chunks[k]["node"] as Node).queue_free()
		chunks.erase(k)


## Block until nothing is streaming (tests).
func busy() -> bool:
	return not _pending.is_empty()


## Drop every chunk above the base levels (terrain data changed: new area pack / region).
func rebuild() -> void:
	for tid: int in _pending.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_pending.clear()
	_done.clear()
	for k: int in chunks.keys():
		(chunks[k]["node"] as Node).queue_free()
	chunks.clear()
	_shown.clear()
	setup(body, mat, sampler, max_level)


func _exit_tree() -> void:
	for tid: int in _pending.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_pending.clear()
