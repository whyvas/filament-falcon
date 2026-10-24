class_name CelestialBody
extends RefCounted
## A gravitating body (point mass) on simple circular rails around its parent.
## Real size: Earth R = 6371 km, Moon R = 1737 km at 384,400 km (Newtonian point masses).

var id := ""
var display_name := ""
var gm := 0.0                 # m^3/s^2
var radius := 1.0             # m
var soi := INF                # sphere of influence radius (m)
var has_atmo := false
var rho0 := 0.0               # sea-level density kg/m^3
var scale_h := 1.0            # density scale height m
var atmo_top := 0.0           # m above surface
var parent: CelestialBody = null
var orbit_r := 0.0
var orbit_phase := 0.0
var color := Color.WHITE

# Cached state at the current sim time.
var pos := BigVec.new()
var vel := Vector3.ZERO

# Terrain: noise hills, flattened around "sites" (launch pad, runway, landing pad).
var terrain_amp := 0.0
var terrain_noise := FastNoiseLite.new()
var crater_noise := FastNoiseLite.new()
var cratered := false
var relief_amp := 0.0          # broad low-frequency relief (Moon highlands / basins), m
var relief_noise := FastNoiseLite.new()
var sites: Array = []          # [{dir: Vector3, flat_r: float, h: float}]
## Real-Earth heights (global DEM + land mask + downloaded area packs), see EarthTerrain.
## null = procedural noise terrain (the Moon, or Earth with no assets installed).
var terrain: EarthTerrain = null


func _init() -> void:
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	terrain_noise.fractal_octaves = 5
	terrain_noise.frequency = 0.00035
	terrain_noise.seed = 7
	crater_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	crater_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	crater_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	crater_noise.frequency = 0.0012
	crater_noise.seed = 11
	relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	relief_noise.fractal_octaves = 6
	relief_noise.frequency = 1.0 / 90000.0
	relief_noise.seed = 3


func update(t: float) -> void:
	if parent == null:
		pos.set_xyz(0.0, 0.0, 0.0)
		vel = Vector3.ZERO
		return
	var n := sqrt(parent.gm / pow(orbit_r, 3.0))
	var th := orbit_phase + n * t
	# Prograde = counter-clockwise seen from +Y (north): east is UP x radial.
	pos.set_xyz(parent.pos.x() + orbit_r * cos(th), parent.pos.y(), parent.pos.z() - orbit_r * sin(th))
	vel = parent.vel + Vector3(-sin(th), 0.0, -cos(th)) * (n * orbit_r)


func surface_gravity() -> float:
	return gm / (radius * radius)


func density(alt: float) -> float:
	if not has_atmo or alt > atmo_top:
		return 0.0
	return rho0 * exp(-maxf(alt, -500.0) / scale_h)


## Terrain height (m above `radius`) for a unit direction from the body centre.
var height_hook: Callable   # a loaded detail region (RegionView.height_at): NAN = outside it
var render_hook: Callable   # same, for the planet LOD mesh (sits just under the region's own mesh)


func terrain_height(dir: Vector3) -> float:
	if height_hook.is_valid():
		var rh: float = height_hook.call(dir)
		if not is_nan(rh):
			return rh
	if terrain != null:
		return terrain.height(dir)
	return natural_height(dir, true)


## Procedural terrain: noise hills (+ craters, + broad relief), flattened around the sites.
## Thread-safe (the LOD terrain meshes call it from worker threads).
func natural_height(dir: Vector3, flatten: bool) -> float:
	if terrain_amp <= 0.0 and relief_amp <= 0.0:
		return 0.0
	var p := dir * radius
	var h := (terrain_noise.get_noise_3dv(p) * 0.5 + 0.5) * terrain_amp
	if cratered:
		var c := crater_noise.get_noise_3dv(p) * 0.5 + 0.5   # ~0 at crater centre
		var bowl := clampf(1.0 - c / 0.45, 0.0, 1.0)
		var rim := exp(-pow((c - 0.45) / 0.08, 2.0))
		h += (-bowl * bowl * 0.8 + rim * 0.3) * terrain_amp
		h = maxf(h, 0.0)
	if relief_amp > 0.0:
		h += relief_noise.get_noise_3dv(p) * relief_amp
	if flatten:
		h = flatten_sites(dir, h)
	return h


## Blend a height toward each site's flat pad height (flat inside flat_r, natural beyond 4x).
func flatten_sites(dir: Vector3, h: float) -> float:
	for s in sites:
		var sd: Vector3 = s["dir"]
		var flat_r: float = s["flat_r"]
		var d := sd.angle_to(dir) * radius
		if d < flat_r * 4.0:
			h = lerpf(float(s["h"]), h, smoothstep(flat_r, flat_r * 4.0, d))
	return h


## A flat site (launch pad, runway, landing pad). height NAN = the natural height there.
func add_site(dir: Vector3, flat_r: float, height: float = NAN) -> void:
	var d := dir.normalized()
	var h := height
	if is_nan(h):
		h = natural_height(d, false) if relief_amp > 0.0 else terrain_amp * 0.25
	sites.append({"dir": d, "flat_r": flat_r, "h": h})


func clear_sites() -> void:
	sites.clear()


## Unit "east" vector at a surface direction.
static func east_at(dir: Vector3) -> Vector3:
	var e := Vector3.UP.cross(dir)
	if e.length_squared() < 1e-8:
		return Vector3(0, 0, -1)
	return e.normalized()
