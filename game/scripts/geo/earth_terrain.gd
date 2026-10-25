class_name EarthTerrain
extends RefCounted
## Real-size Earth ground: the height (m above the 6371 km sphere) and water fraction at any
## direction, used by BOTH the physics (CelestialBody.terrain_height) and the LOD terrain meshes
## (PlanetLOD, on worker threads), so what you see is what you land on.
## Sources, best first:
##   1. a built OSM detail region (RegionView.height_at via CelestialBody.height_hook)
##   2. area packs from tools/area_manager.py: ~/.local/share/filament-falcon/areas/<id>/
##      (terrarium DEM ~20 m, water mask from OSM + DEM <= 0, Sentinel-2 imagery)
##   3. the global set from tools/fetch_assets.sh: GEBCO land heights (earth_height.png, ~10 km)
##      + land/water mask (earth_mask.png, ~5 km) + noise detail
##   4. nothing installed: gentle noise hills everywhere (tests / offline)
## The pad and the runway are flattened at their real 3 m elevation. Thread-safe after _init
## (all lookups read immutable packed arrays); reload_packs() swaps in a new pack list and is
## only called after World has stopped the LOD workers (PlanetLOD.quiesce), so no worker ever
## reads `packs` while it changes (no lock on the per-vertex path).

const GLOBAL_CACHE_VER := 1
const PACK_VER := 1
const EDGE_BLEND := 1000.0      # m: packs fade into the global terrain over their last km

var body: CelestialBody
var gfg := Basis.IDENTITY       # game -> real-world (geo) directions
var detail := FastNoiseLite.new()
var g_w := 0                    # global heights (L8, 6400 m / 255 per step), equirect
var g_h := 0
var g_px := PackedByteArray()
var m_w := 0                    # global land mask (L8, 255 = land), equirect
var m_h := 0
var m_px := PackedByteArray()
var packs: Array = []           # replaced whole, never edited in place: [{id, name, s, w, n, e, dw, dh, dem: PackedByteArray, wm: PackedByteArray, img_path, area}]


func _init(b: CelestialBody) -> void:
	body = b
	gfg = Geo.game_from_geo().inverse()
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 6
	detail.frequency = 1.0 / 2500.0
	detail.seed = 21
	_load_global()
	reload_packs()


func has_global() -> bool:
	return g_w > 0


# ------------------------------------------------------------------ queries
## Height of the ground (or the water surface) in metres above the sphere.
func height(d: Vector3) -> float:
	return sample(d).x


## (surface height m, water 0..1, pack coverage 0..1) at a unit game-space direction.
func sample(d: Vector3) -> Vector3:
	var g := gfg * d
	var lat := rad_to_deg(asin(clampf(g.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(g.x, -g.z))
	var r := base_sample(d, lat, lon)
	var cov := 0.0
	var pl: Array = packs
	for pk: Dictionary in pl:
		var w := _pack_weight(pk, lat, lon)
		if w <= 0.0:
			continue
		var ps := _pack_sample(pk, lat, lon)
		r = r.lerp(ps, w)
		cov = maxf(cov, w)
		if w >= 1.0:
			break
	return _sites(d, Vector3(r.x, r.y, cov))


## Global (no packs, no region) height + water at a direction / lat-lon.
func base_sample(d: Vector3, lat: float, lon: float) -> Vector3:
	if g_w == 0:
		return Vector3(body.natural_height(d, false), 0.0, 0.0)
	var u := (lon + 180.0) / 360.0
	var v := (90.0 - lat) / 180.0
	var hl := _bilin(g_px, g_w, g_h, u, v, true) * (6400.0 / 255.0)
	var m := _bilin(m_px, m_w, m_h, u, v, true) / 255.0 if m_w > 0 else (1.0 if hl > 0.5 else 0.0)
	var land := smoothstep(0.3, 0.7, m)
	var nz := detail.get_noise_3dv(d * body.radius)
	var h := hl + nz * (10.0 + 0.06 * hl) * land + land * 1.5
	return Vector3(h, 1.0 - land, 0.0)


func _sites(d: Vector3, r: Vector3) -> Vector3:
	for s: Dictionary in body.sites:
		var sd: Vector3 = s["dir"]
		var flat_r: float = s["flat_r"]
		var dist := sd.angle_to(d) * body.radius
		if dist < flat_r * 4.0:
			var k := smoothstep(flat_r, flat_r * 4.0, dist)
			r.x = lerpf(float(s["h"]), r.x, k)
			r.y *= k
	return r


static func _bilin(px: PackedByteArray, w: int, h: int, u: float, v: float, wrap: bool) -> float:
	var x := u * w - 0.5
	var y := clampf(v * h - 0.5, 0.0, h - 1.001)
	var x0 := floori(x)
	var fx := x - x0
	var y0 := int(y)
	var fy := y - y0
	var x1 := x0 + 1
	if wrap:
		x0 = posmod(x0, w)
		x1 = posmod(x1, w)
	else:
		x0 = clampi(x0, 0, w - 1)
		x1 = clampi(x1, 0, w - 1)
	var r0 := y0 * w
	var r1 := mini(y0 + 1, h - 1) * w
	var a := lerpf(px[r0 + x0], px[r0 + x1], fx)
	var b := lerpf(px[r1 + x0], px[r1 + x1], fx)
	return lerpf(a, b, fy)


# ------------------------------------------------------------------ area packs
func _pack_weight(pk: Dictionary, lat: float, lon: float) -> float:
	var s: float = pk["s"]
	var n: float = pk["n"]
	var w: float = pk["w"]
	var e: float = pk["e"]
	if lat <= s or lat >= n or lon <= w or lon >= e:
		return 0.0
	var kx := 111320.0 * cos(deg_to_rad(lat))
	var dm := minf(minf(lat - s, n - lat) * 110540.0, minf(lon - w, e - lon) * kx)
	return clampf(dm / EDGE_BLEND, 0.0, 1.0)


## Pack DEM (int16, 0.5 m units, rows north -> south, lat/lon-linear) + water mask (L8).
func _pack_sample(pk: Dictionary, lat: float, lon: float) -> Vector3:
	var dw: int = pk["dw"]
	var dh: int = pk["dh"]
	var fx := (lon - float(pk["w"])) / (float(pk["e"]) - float(pk["w"])) * (dw - 1)
	var fy := (float(pk["n"]) - lat) / (float(pk["n"]) - float(pk["s"])) * (dh - 1)
	fx = clampf(fx, 0.0, dw - 1.001)
	fy = clampf(fy, 0.0, dh - 1.001)
	var i := int(fx)
	var j := int(fy)
	var tx := fx - i
	var ty := fy - j
	var dem: PackedByteArray = pk["dem"]
	var o := (j * dw + i) * 2
	var o2 := o + dw * 2
	var h00 := dem.decode_s16(o) * 0.5
	var h10 := dem.decode_s16(o + 2) * 0.5
	var h01 := dem.decode_s16(o2) * 0.5
	var h11 := dem.decode_s16(o2 + 2) * 0.5
	var h := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)
	var wm: PackedByteArray = pk["wm"]
	var wat := 0.0
	if wm.size() == dw * dh:
		var k := j * dw + i
		wat = lerpf(lerpf(wm[k], wm[k + 1], tx), lerpf(wm[k + dw], wm[k + dw + 1], tx), ty) / 255.0
	# sea: the DEM holds bathymetry; the surface is sea level. Lakes: the DEM is the lake level.
	h = lerpf(h, maxf(h, 0.0), smoothstep(0.2, 0.6, wat))
	return Vector3(h, wat, 1.0)


static func areas_dir() -> String:
	return Geo.asset_dir().get_base_dir() + "/areas"


## (Re)scan ~/.local/share/filament-falcon/areas for finished packs (area.json "pack": true).
func reload_packs() -> void:
	var out: Array = []
	var base := areas_dir()
	if DirAccess.dir_exists_absolute(base):
		for id in DirAccess.get_directories_at(base):
			var pk := load_pack(base + "/" + id)
			if not pk.is_empty():
				out.append(pk)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) < float(b["area"]))
	packs = out
	if not out.is_empty():
		print("Earth: %d area pack(s): %s" % [out.size(), ", ".join(out.map(func(p: Dictionary) -> String: return str(p["id"])))])


static func load_pack(dir: String) -> Dictionary:
	var mf := dir + "/area.json"
	if not FileAccess.file_exists(mf):
		return {}
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(mf))
	if typeof(m) != TYPE_DICTIONARY:
		return {}
	var a: Dictionary = m
	var pk: Dictionary = a.get("pack", {})
	if pk.is_empty() or int(pk.get("version", 0)) != PACK_VER or not FileAccess.file_exists(dir + "/dem.bin"):
		return {}
	var bb: Array = a["bbox"]
	var dw := int(pk["dem_w"])
	var dh := int(pk["dem_h"])
	var dem := FileAccess.get_file_as_bytes(dir + "/dem.bin")
	if dem.size() != dw * dh * 2:
		return {}
	var wm := FileAccess.get_file_as_bytes(dir + "/water.bin") if FileAccess.file_exists(dir + "/water.bin") else PackedByteArray()
	var s := float(bb[0])
	var w := float(bb[1])
	var n := float(bb[2])
	var e := float(bb[3])
	return {"id": dir.get_file(), "name": str(a.get("name", dir.get_file())), "s": s, "w": w, "n": n, "e": e, "dw": dw, "dh": dh,
		"dem": dem, "wm": wm, "img": dir + "/" + str(pk.get("image", "image.jpg")), "dir": dir,
		"area": (n - s) * (e - w), "region": str(a.get("region", ""))}


# ------------------------------------------------------------------ global maps
## earth_height.png / earth_mask.png decoded once and cached raw (fast start next time).
func _load_global() -> void:
	var hp := _raw("earth_height.png", 4096)
	if hp.is_empty():
		return
	g_w = hp[0]
	g_h = hp[1]
	g_px = hp[2]
	var mp := _raw("earth_mask.png", 8192)
	if not mp.is_empty():
		m_w = mp[0]
		m_h = mp[1]
		m_px = mp[2]
	print("Earth terrain: global DEM %dx%d, mask %dx%d" % [g_w, g_h, m_w, m_h])


static func _raw(name: String, max_w: int) -> Array:
	var p := Geo.asset_dir() + "/" + name
	if not FileAccess.file_exists(p):
		return []
	var cp := "%s/terrain/%s.v%d.%d.raw" % [Geo.cache_dir(), name.get_basename(), GLOBAL_CACHE_VER, FileAccess.get_modified_time(p)]
	if FileAccess.file_exists(cp):
		var f := FileAccess.open(cp, FileAccess.READ)
		if f:
			var w := f.get_32()
			var h := f.get_32()
			var px := f.get_buffer(w * h)
			if px.size() == w * h:
				return [w, h, px]
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return []
	img.convert(Image.FORMAT_L8)
	if img.get_width() > max_w:
		img.resize(max_w, max_w / 2, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(cp.get_base_dir())
	var wf := FileAccess.open(cp, FileAccess.WRITE)
	if wf:
		wf.store_32(img.get_width())
		wf.store_32(img.get_height())
		wf.store_buffer(img.get_data())
	return [img.get_width(), img.get_height(), img.get_data()]
