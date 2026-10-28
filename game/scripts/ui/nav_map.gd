class_name NavMap
extends Control
## Top-down orbit map for the NAV page (console) and the Commander ORBIT MAP. Draws the dominant
## body as a lit globe (NavGlobe: NASA day / night lights / clouds / terminator / atmosphere for
## Earth, LROC colour + LOLA relief for the Moon, procedural when the assets aren't fetched),
## the ship's current conic (OrbitMath), Ap/Pe, the target, the other bodies, the ground areas
## (Fredericton / the selected region, the area manager's areas, the pad) and, when the ship is
## low or landed, a north-up GROUND TRACK close-up with the area imagery and the OSM overlay
## from tools/nav_overlay.py.

var zoom := 1.0          # multiplier on the auto scale
var font: Font
var show_ground := true  # the low-altitude ground-track inset

const MAX_VP := 640.0            # globe render resolution cap (longest side, px)
const GROUND_ALT := 0.35         # inset below this altitude, in body radii
const C_AREA := Color(1.0, 0.75, 0.25)
const C_AREA_READY := Color(0.35, 1.0, 0.6)
const C_HOME := Color(1.0, 0.45, 0.85)

var _globe: NavGlobe
var _ground: NavGlobe
var _others := {}                # body id -> NavGlobe
var _g_drawn := {}               # globe -> {"c": centre px, "r": radius px, "rect": Rect2} at render
var _lay := {}
var _last_force: Array = []
var _scan_t := 1e9

# ground areas + OSM overlays (shared by every NavMap; rescanned every few seconds)
static var areas: Array = []     # [{id, name, s, w, n, e, ready}]
static var overlays: Array = []  # [{id, s, w, n, e, png, places}]
static var _ov_tex := {}         # overlay id -> Texture2D (null while loading)
static var _ov_tasks := {}       # overlay id -> WorkerThreadPool task
static var _scanned_ms := -1e9
static var _live := 0            # NavMaps in the tree (the last one out frees the textures)


func _ready() -> void:
	_live += 1
	font = ThemeDB.fallback_font
	clip_contents = true
	_globe = NavGlobe.new()
	add_child(_globe)
	_ground = NavGlobe.new(true)
	_ground.min_interval = 0.2
	add_child(_ground)


func _exit_tree() -> void:
	_live -= 1
	wait_overlay_loads()
	if _live <= 0:
		_ov_tex.clear()          # static textures alive at engine teardown crash the exit


static func wait_overlay_loads() -> void:
	for id: String in _ov_tasks.keys():
		WorkerThreadPool.wait_for_task_completion(int(_ov_tasks[id]))
	_ov_tasks.clear()


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	for g: NavGlobe in [_globe, _ground] + _others.values():
		g.tick(dt)
	_scan_t += dt
	if _scan_t > 5.0:
		_scan_t = 0.0
		scan_ground_data()
	_layout()
	_update_globes()
	queue_redraw()


## Map the orbital plane (world XZ, seen from +Y / north) to screen.
func _to_screen(rel: Vector3, center: Vector2, k: float) -> Vector2:
	return center + Vector2(rel.x, rel.z) * k


func _layout() -> void:
	_lay = {}
	var sim: ShipSim = Game.sim
	if sim == null or sim.dominant == null or size.x < 8.0 or size.y < 8.0:
		return
	var dom: CelestialBody = sim.dominant
	var r := sim.pos.rel(dom.pos)
	var v := sim.vel - dom.vel
	var el := OrbitMath.elements(r, v, dom.gm, dom.radius)
	var extent := maxf(r.length(), dom.radius * 1.6)
	if not el["escaping"]:
		extent = maxf(extent, float(el["a"]) * (1.0 + float(el["e"])))
	extent = minf(extent, dom.soi if dom.soi > 0.0 else extent)
	_lay = {"dom": dom, "r": r, "v": v, "el": el, "k": minf(size.x, size.y) * 0.46 / extent * zoom, "c": size * 0.5,
		"grounded": Hud.orbit_strings(sim)[0] == "ON THE GROUND"}


static func _glow_px(b: CelestialBody, r_px: float) -> float:
	if b.atmo_top <= 0.0:
		return 0.0
	return clampf(r_px * maxf(b.atmo_top / b.radius, 0.02) * 2.2, 3.0, 60.0)


static func _sun_key() -> Array:
	var s: Vector3 = Game.sun_dir.normalized()
	return [snappedf(s.x, 0.002), snappedf(s.y, 0.002), snappedf(s.z, 0.002)]


func _update_globes() -> void:
	if _lay.is_empty():
		return
	var dom: CelestialBody = _lay["dom"]
	var k: float = _lay["k"]
	var c: Vector2 = _lay["c"]
	var sd: Vector3 = Game.sun_dir.normalized()
	# --- dominant body: a viewport the size of the map (capped), aligned with it
	var s := minf(1.0, MAX_VP / maxf(size.x, size.y))
	var vs := Vector2i(ceili(size.x * s), ceili(size.y * s))
	var rpx := dom.radius * k * s
	_globe.bind_body(dom.id)
	var force_key: Array = [dom.id, zoom, size]
	var key: Array = force_key + [snappedf(rpx, maxf(0.5, rpx * 0.01)), _sun_key()]
	if _globe.request(vs, key, force_key != _last_force):
		_globe.set_p("vp_size", Vector2(vs))
		_globe.set_p("center_px", c * s)
		_globe.set_p("radius_px", rpx)
		_globe.set_p("glow_px", _glow_px(dom, rpx))
		_globe.set_p("sun_dir", sd)
		_globe.set_p("base_color", Color(0.6, 0.55, 0.5))
		_g_drawn[_globe] = {"c": c, "r": dom.radius * k, "size": Vector2(vs) / s}
	_last_force = force_key
	# --- the other bodies: small square globes
	for b: CelestialBody in Game.bodies:
		if b == dom:
			continue
		var g: NavGlobe = _others.get(b.id)
		if g == null:
			g = NavGlobe.new()
			g.min_interval = 1.0
			add_child(g)
			_others[b.id] = g
		var rr := maxf(b.radius * k, 7.0)
		var n := clampi(nearest_po2(int(rr * 2.6)), 32, 256)
		var glow := _glow_px(b, n * 0.4)
		var rad := n * 0.5 - glow - 1.0
		g.bind_body(b.id)
		if g.request(Vector2i(n, n), [b.id, n, _sun_key()]):
			g.set_p("vp_size", Vector2(n, n))
			g.set_p("center_px", Vector2(n, n) * 0.5)
			g.set_p("radius_px", rad)
			g.set_p("glow_px", glow)
			g.set_p("sun_dir", sd)
			g.set_p("base_color", Color(0.6, 0.6, 0.62))
			_g_drawn[g] = {"n": n, "rad": rad}
	# --- ground track inset
	var gr := _ground_rect()
	if gr.size.x > 0.0:
		_update_ground(dom, gr, sd)


## Inset rectangle (bottom right), or empty when not shown.
func _ground_rect() -> Rect2:
	if _lay.is_empty() or not show_ground:
		return Rect2()
	var dom: CelestialBody = _lay["dom"]
	if dom.id != "earth" and dom.id != "moon":
		return Rect2()
	var alt: float = (_lay["r"] as Vector3).length() - dom.radius
	if not (_lay["grounded"] or alt < dom.radius * GROUND_ALT) or minf(size.x, size.y) < 240.0:
		return Rect2()
	var side := roundf(minf(size.x * 0.42, size.y * 0.5))
	return Rect2(size - Vector2(side, side) - Vector2(10, 10), Vector2(side, side))


## Geo direction (real-world frame) of a body-relative game vector; the Moon has no remap.
static func geo_of(dom: CelestialBody, v: Vector3) -> Vector3:
	return Geo.game_from_geo().inverse() * v if dom.id == "earth" else v


static func ground_half(dom: CelestialBody, alt: float, grounded: bool) -> float:
	return 25000.0 if grounded else clampf(alt * 0.9, 25000.0, dom.radius * 0.3)


func _ground_frame() -> Dictionary:
	var dom: CelestialBody = _lay["dom"]
	var r: Vector3 = _lay["r"]
	var up := geo_of(dom, r.normalized()).normalized()
	var east := up.cross(Vector3.UP)
	east = Vector3(1, 0, 0) if east.length() < 1e-6 else east.normalized()
	var north := east.cross(up).normalized()
	var half := ground_half(dom, r.length() - dom.radius, bool(_lay["grounded"]))
	return {"up": up, "east": east, "north": north, "half": half, "hr": half / dom.radius,
		"lat": rad_to_deg(asin(clampf(up.y, -1.0, 1.0))), "lon": rad_to_deg(atan2(up.x, -up.z))}


func _update_ground(dom: CelestialBody, gr: Rect2, sd: Vector3) -> void:
	var f := _ground_frame()
	var n := clampi(int(gr.size.x), 64, 384)
	_ground.bind_body(dom.id)
	var hr: float = f["hr"]
	var up: Vector3 = f["up"]
	var key: Array = [dom.id, n, snappedf(hr, hr * 0.02), snappedf(up.x, hr * 0.004), snappedf(up.y, hr * 0.004), snappedf(up.z, hr * 0.004), _sun_key(), _ov_tex.size()]
	if not _ground.request(Vector2i(n, n), key, false):
		return
	_ground.set_p("up_geo", up)
	_ground.set_p("east_geo", f["east"])
	_ground.set_p("north_geo", f["north"])
	_ground.set_p("half_r", hr)
	_ground.set_p("sun_dir", sd)
	# nearest area imagery (loaded by the world near the camera) + nearest OSM overlay
	var lat: float = f["lat"]
	var lon: float = f["lon"]
	var span := rad_to_deg(hr) * 1.5
	var pk := {}
	var ptex: Texture2D = null
	if dom.id == "earth" and dom.terrain != null:
		var wv := NavGlobe.world()
		var pv: Variant = wv.get("_pack_tex") if wv else null
		var pt: Dictionary = pv if pv is Dictionary else {}
		pk = _nearest(dom.terrain.packs.filter(func(p: Dictionary) -> bool: return pt.get(p["id"]) is Texture2D), lat, lon, span)
		if not pk.is_empty():
			ptex = pt[pk["id"]]
	_ground.set_p("use_pack", ptex != null)
	if ptex:
		_ground.set_p("pack_box", Vector4(pk["s"], pk["w"], pk["n"], pk["e"]))
		_ground.set_p("pack_tex", ptex)
	var ov := _nearest(overlays, lat, lon, span) if dom.id == "earth" else {}
	var otex: Texture2D = overlay_texture(ov) if not ov.is_empty() else null
	_ground.set_p("use_osm", otex != null)
	if otex:
		_ground.set_p("osm_box", Vector4(ov["s"], ov["w"], ov["n"], ov["e"]))
		_ground.set_p("osm_tex", otex)
	_g_drawn[_ground] = {"f": f}


## The box (dict with s, w, n, e) nearest (lat, lon) that comes within `span` degrees of it.
static func _nearest(list: Array, lat: float, lon: float, span: float) -> Dictionary:
	var best := {}
	var bd := 1e9
	var cl := maxf(cos(deg_to_rad(lat)), 0.05)
	for b: Dictionary in list:
		var dy := maxf(0.0, maxf(float(b["s"]) - lat, lat - float(b["n"])))
		var dx := maxf(0.0, maxf(float(b["w"]) - lon, lon - float(b["e"]))) * cl
		var d := Vector2(dx, dy).length()
		if d <= span and d < bd:
			bd = d
			best = b
	return best


# ------------------------------------------------------------------ ground data
## Areas (tools/area_manager.py: areas/<id>/area.json) + OSM overlays (assets/overlays/*.json).
static func scan_ground_data(force := false) -> void:
	if not force and Time.get_ticks_msec() - _scanned_ms < 4000.0:
		return
	_scanned_ms = Time.get_ticks_msec()
	var out: Array = []
	var base := EarthTerrain.areas_dir()
	if DirAccess.dir_exists_absolute(base):
		for id in DirAccess.get_directories_at(base):
			var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "/" + id + "/area.json")) if FileAccess.file_exists(base + "/" + id + "/area.json") else null
			if typeof(m) == TYPE_DICTIONARY and (m as Dictionary).get("bbox") is Array and ((m as Dictionary)["bbox"] as Array).size() == 4:
				var bb: Array = m["bbox"]
				out.append({"id": id, "name": str(m.get("name", id)), "s": float(bb[0]), "w": float(bb[1]), "n": float(bb[2]), "e": float(bb[3]),
					"ready": not ((m as Dictionary).get("pack", {}) as Dictionary).is_empty()})
	areas = out
	var ovs: Array = []
	var od := Geo.asset_dir() + "/overlays"
	if DirAccess.dir_exists_absolute(od):
		for f in DirAccess.get_files_at(od):
			if not f.ends_with(".json"):
				continue
			var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(od + "/" + f))
			if typeof(m) != TYPE_DICTIONARY or not ((m as Dictionary).get("bbox") is Array):
				continue
			var bb: Array = m["bbox"]
			var png := od + "/" + str(m.get("image", f.get_basename() + ".png"))
			if bb.size() == 4 and FileAccess.file_exists(png):
				ovs.append({"id": f.get_basename() + ":" + str(FileAccess.get_modified_time(png)), "name": str(m.get("name", f.get_basename())),
					"s": float(bb[0]), "w": float(bb[1]), "n": float(bb[2]), "e": float(bb[3]), "png": png, "places": m.get("places", [])})
	overlays = ovs


## The overlay's texture; first use decodes the PNG on a worker thread (null until ready).
static func overlay_texture(ov: Dictionary) -> Texture2D:
	var id: String = ov["id"]
	if _ov_tex.has(id):
		return _ov_tex[id]
	_ov_tex[id] = null
	var path: String = ov["png"]
	_ov_tasks[id] = WorkerThreadPool.add_task(func() -> void:
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			img.generate_mipmaps()
		(func() -> void:
			if _ov_tasks.has(id):     # every task must be waited for once, or the exit aborts
				WorkerThreadPool.wait_for_task_completion(int(_ov_tasks[id]))
				_ov_tasks.erase(id)
			if img and not img.is_empty():
				_ov_tex[id] = ImageTexture.create_from_image(img)).call_deferred(), false, "nav overlay")
	return null


# ------------------------------------------------------------------ drawing
func _draw_globe_tex(g: NavGlobe, c: Vector2, r_now: float) -> void:
	var d: Dictionary = _g_drawn.get(g, {})
	if d.is_empty() or float(d["r"]) <= 0.0:
		return
	var f := r_now / float(d["r"])
	var c0: Vector2 = d["c"]
	draw_texture_rect(g.get_texture(), Rect2(c - c0 * f, (d["size"] as Vector2) * f), false)


func _draw() -> void:
	if _lay.is_empty():
		_layout()
	if _lay.is_empty():
		return
	var dom: CelestialBody = _lay["dom"]
	var r: Vector3 = _lay["r"]
	var v: Vector3 = _lay["v"]
	var el: Dictionary = _lay["el"]
	var k: float = _lay["k"]
	var c: Vector2 = _lay["c"]
	var grounded: bool = _lay["grounded"]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.05))
	for i in 12:
		var gx := size.x * i / 12.0
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(0.2, 0.5, 0.8, 0.08))
	for i in 8:
		var gy := size.y * i / 8.0
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.2, 0.5, 0.8, 0.08))
	# Body: the rendered globe (flat disc until the first render lands)
	var rk := dom.radius * k
	if _g_drawn.has(_globe):
		_draw_globe_tex(_globe, c, rk)
	else:
		if dom.atmo_top > 0.0:
			draw_circle(c, (dom.radius + dom.atmo_top) * k, Color(0.3, 0.6, 1.0, 0.18))
		draw_circle(c, rk, Color(0.15, 0.35, 0.7) if dom.id == "earth" else Color(0.45, 0.45, 0.48))
	if dom.id == "earth" and rk > 30.0:
		_draw_globe_sites(c, rk)
	draw_string(font, c + Vector2(-60, 8) if rk < 60.0 else c + Vector2(-60, -rk - 12.0), dom.display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 1, 1, 0.8))
	# Orbit
	if grounded:
		draw_string(font, _to_screen(r, c, k) + Vector2(14, -10), "ON THE GROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.3, 1.0, 0.5))
	var pts: PackedVector3Array = PackedVector3Array() if grounded else OrbitMath.sample_conic(el, 256)
	var line := PackedVector2Array()
	for p in pts:
		if p.length() < dom.radius * 0.999 and line.size() > 1:
			draw_polyline(line, Color(0.3, 1.0, 0.5), 3.0)
			line = PackedVector2Array()
			continue
		line.append(_to_screen(p, c, k))
	if line.size() > 1:
		draw_polyline(line, Color(0.3, 1.0, 0.5), 3.0)
	# Ap / Pe (none while sitting on the ground: the "orbit" would be a sliver inside the planet)
	var ev: Vector3 = el["ecc_vec"]
	if ev.length() > 0.001 and not grounded:
		var e_dir := ev.normalized()
		var p_r: float = el["p"] / (1.0 + float(el["e"]))
		var pe := _to_screen(e_dir * p_r, c, k)
		draw_circle(pe, 9.0, Color(1, 0.8, 0.2))
		draw_string(font, pe + Vector2(12, -8), "Pe %s" % Hud._fmt_dist(float(el["pe_alt"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.8, 0.2))
		if not el["escaping"]:
			var a_r: float = el["p"] / (1.0 - float(el["e"]))
			var ap := _to_screen(-e_dir * a_r, c, k)
			draw_circle(ap, 9.0, Color(0.4, 0.8, 1.0))
			draw_string(font, ap + Vector2(12, -8), "Ap %s" % Hud._fmt_dist(float(el["ap_alt"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.4, 0.8, 1.0))
	# Other bodies (moon from earth / earth from moon): small lit globes, clamped to the edge
	for b in Game.bodies:
		var bb: CelestialBody = b
		if bb == dom:
			continue
		var br := bb.pos.rel(dom.pos)
		var bp := _to_screen(br, c, k)
		var dir_clamped := bp
		var inside := Rect2(Vector2.ZERO, size).grow(-20).has_point(bp)
		if not inside:
			dir_clamped = c + (bp - c).limit_length(minf(size.x, size.y) * 0.48)
		var rr := maxf(bb.radius * k, 7.0)
		var g: NavGlobe = _others.get(bb.id)
		var d: Dictionary = _g_drawn.get(g, {}) if g else {}
		if d.is_empty():
			draw_circle(dir_clamped, rr, Color(0.6, 0.6, 0.62))
		else:
			var half: float = float(d["n"]) * 0.5 * rr / float(d["rad"])
			draw_texture_rect(g.get_texture(), Rect2(dir_clamped - Vector2(half, half), Vector2(half, half) * 2.0), false)
		draw_string(font, dir_clamped + Vector2(rr + 6.0, 6), bb.display_name + ("" if inside else " >"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.8, 0.8))
	# Target
	var ts: Array = Game.target_state()
	if not ts.is_empty():
		var tp := _to_screen((ts[0] as BigVec).rel(dom.pos), c, k)
		draw_polyline(PackedVector2Array([tp + Vector2(0, -12), tp + Vector2(12, 0), tp + Vector2(0, 12), tp + Vector2(-12, 0), tp + Vector2(0, -12)]), Color(0.75, 0.5, 1.0), 3.0)
		draw_string(font, tp + Vector2(14, 20), str(Game.current_target().get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.5, 1.0))
	# Ship
	var sp := _to_screen(r, c, k)
	var vd := Vector2(v.x, v.z).normalized()
	var perp := Vector2(-vd.y, vd.x)
	draw_colored_polygon(PackedVector2Array([sp + vd * 18.0, sp - vd * 10.0 + perp * 10.0, sp - vd * 10.0 - perp * 10.0]), Color(1, 1, 1))
	draw_string(font, Vector2(16, 30), "MAP: top view  (zoom x%.1f)" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.5, 0.8, 1.0, 0.8))
	var gr := _ground_rect()
	if gr.size.x > 0.0 and _g_drawn.has(_ground):
		_draw_ground(gr, dom, r, v, el, grounded)


## Home region (Fredericton by default), the pad and the area manager's areas on the globe's
## visible (+Y) hemisphere.
func _draw_globe_sites(c: Vector2, rk: float) -> void:
	var labels := rk > 110.0
	var sites: Array = [[Geo.KSC, "PAD", Color(0.6, 0.9, 1.0)], [Geo.region_center(), _home_name(), C_HOME]]
	for a: Dictionary in areas:
		var col: Color = C_AREA_READY if a["ready"] else C_AREA
		var d0 := Geo.game_dir(float(a["s"]), float(a["w"]))
		var d1 := Geo.game_dir(float(a["n"]), float(a["e"]))
		if d0.y <= 0.0 or d1.y <= 0.0:
			continue
		var p0 := c + Vector2(d0.x, d0.z) * rk
		var p1 := c + Vector2(d1.x, d1.z) * rk
		if p0.distance_to(p1) > 5.0:
			var corners := PackedVector2Array()
			for ll: Vector2 in [Vector2(a["s"], a["w"]), Vector2(a["s"], a["e"]), Vector2(a["n"], a["e"]), Vector2(a["n"], a["w"]), Vector2(a["s"], a["w"])]:
				var dd := Geo.game_dir(ll.x, ll.y)
				corners.append(c + Vector2(dd.x, dd.z) * rk)
			draw_polyline(corners, col, 1.5)
		else:
			draw_rect(Rect2((p0 + p1) * 0.5 - Vector2(2.5, 2.5), Vector2(5, 5)), col)
	for st: Array in sites:
		var ll: Vector2 = st[0]
		var dg := Geo.game_dir(ll.x, ll.y)
		if dg.y <= 0.02:
			continue
		var p := c + Vector2(dg.x, dg.z) * rk
		draw_circle(p, 4.0, st[2])
		draw_circle(p, 6.5, Color(0, 0, 0, 0.6), false, 1.5)
		if labels:
			draw_string(font, p + Vector2(8, -6), st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, st[2])


static func _home_name() -> String:
	return str(Settings.cli.get("region", "fredericton")).capitalize()


## The ground-track close-up: picture + track, ship, areas, home, OSM places, scale.
func _draw_ground(gr: Rect2, dom: CelestialBody, r: Vector3, v: Vector3, el: Dictionary, grounded: bool) -> void:
	var f := _ground_frame()     # current frame (the picture can lag a fraction of a second)
	var up: Vector3 = f["up"]
	var east: Vector3 = f["east"]
	var north: Vector3 = f["north"]
	var hr: float = f["hr"]
	draw_rect(gr.grow(2.0), Color(0, 0, 0, 0.8))
	draw_texture_rect(_ground.get_texture(), gr, false)
	var proj := func(g: Vector3) -> Vector2:
		var z := g.dot(up)
		if z <= 0.0:
			return Vector2(INF, INF)
		var p := Vector2(g.dot(east), -g.dot(north)) / (z * hr)
		return gr.position + (p + Vector2.ONE) * 0.5 * gr.size
	var inner := gr.grow(-1.0)
	# ground track (the game Earth doesn't spin, so it is the orbit itself, projected)
	if not grounded:
		var line := PackedVector2Array()
		for p in OrbitMath.sample_conic(el, 720):
			var q: Vector2 = proj.call(geo_of(dom, p.normalized()))
			if inner.has_point(q):
				line.append(q)
			elif line.size() > 0:
				if line.size() > 1:
					draw_polyline(line, Color(0.3, 1.0, 0.5, 0.9), 2.0)
				line = PackedVector2Array()
		if line.size() > 1:
			draw_polyline(line, Color(0.3, 1.0, 0.5, 0.9), 2.0)
	if dom.id == "earth":
		for a: Dictionary in areas:
			var col: Color = C_AREA_READY if a["ready"] else C_AREA
			var poly := PackedVector2Array()
			var ok := true
			for ll: Vector2 in [Vector2(a["s"], a["w"]), Vector2(a["s"], a["e"]), Vector2(a["n"], a["e"]), Vector2(a["n"], a["w"]), Vector2(a["s"], a["w"])]:
				var q: Vector2 = proj.call(Geo.geo_dir(ll.x, ll.y))
				ok = ok and q.x != INF
				poly.append(q)
			if not ok:
				continue
			var bb := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				bb = bb.expand(q)
			if not bb.intersects(gr):
				continue
			draw_polyline(_clip_poly(poly, inner), col, 1.5)
			if bb.size.x > 30.0 and inner.has_point(bb.position + Vector2(3, 14)):
				draw_string(font, bb.position + Vector2(3, 14), str(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		var half_km: float = float(f["half"]) / 1000.0
		if half_km < 200.0:
			for ov: Dictionary in overlays:
				for pl: Variant in ov["places"]:
					if not (pl is Dictionary):
						continue
					var big: bool = str(pl.get("kind", "")) in ["city", "town"]
					if not big and half_km > 60.0:
						continue
					var q: Vector2 = proj.call(Geo.geo_dir(float(pl.get("lat", 0)), float(pl.get("lon", 0))))
					if inner.has_point(q):
						draw_circle(q, 3.0 if big else 2.0, Color(1, 1, 1, 0.9))
						draw_string(font, q + Vector2(5, -3), str(pl.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if big else 12, Color(1, 1, 1, 0.85))
		for st: Array in [[Geo.KSC, "PAD", Color(0.6, 0.9, 1.0)], [Geo.region_center(), _home_name(), C_HOME]]:
			var q: Vector2 = proj.call(Geo.geo_dir((st[0] as Vector2).x, (st[0] as Vector2).y))
			if inner.has_point(q):
				draw_circle(q, 4.5, st[2])
				draw_circle(q, 7.0, Color(0, 0, 0, 0.7), false, 1.5)
				draw_string(font, q + Vector2(9, -5), st[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, st[2])
	# the ship at the centre, nose along the ground velocity
	var vg := geo_of(dom, v)
	var hd := Vector2(vg.dot(east), -vg.dot(north))
	hd = Vector2.UP if hd.length() < 1e-3 else hd.normalized()
	var sp := gr.get_center()
	var pp := Vector2(-hd.y, hd.x)
	draw_colored_polygon(PackedVector2Array([sp + hd * 13.0, sp - hd * 7.0 + pp * 7.0, sp - hd * 7.0 - pp * 7.0]), Color(1, 1, 1))
	draw_rect(gr, Color(0.4, 0.8, 1.0, 0.7), false, 1.5)
	draw_string(font, gr.position + Vector2(6, 18), "GROUND  %.2f%s %.2f%s   ±%s" % [absf(float(f["lat"])), "N" if float(f["lat"]) >= 0.0 else "S",
		absf(float(f["lon"])), "E" if float(f["lon"]) >= 0.0 else "W", Hud._fmt_dist(float(f["half"]))], HORIZONTAL_ALIGNMENT_LEFT, gr.size.x - 10.0, 15, Color(0.7, 0.9, 1.0))


## Keep the polyline points inside rect (good enough for box outlines on a small inset).
static func _clip_poly(poly: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in poly:
		out.append(q.clamp(rect.position, rect.end))
	return out
