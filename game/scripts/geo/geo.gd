class_name Geo
## Real-world <-> game-planet mapping. The game Earth is a 600 km planet; the NASA textures
## and the OSM regions are placed on it with one fixed rotation chosen so the game's launch pad
## sits on Cape Canaveral (so the textures show Florida under the pad). Directions are unit
## vectors in the planet's object space. Geo convention: lat/lon in degrees,
## dir = (cos lat sin lon, sin lat, -cos lat cos lon)  <=>  equirect u = (lon + 180) / 360.

const KSC := Vector2(28.573, -80.649)          # lat, lon of the game's launch pad
const ASSET_DIR := "filament-falcon/assets"    # under ~/.local/share

static var _r: Basis
static var _have := false


static func geo_dir(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), -cos(la) * cos(lo))


## game direction = game_from_geo() * real-world direction
static func game_from_geo() -> Basis:
	if not _have:
		var a := geo_dir(KSC.x, KSC.y)
		var b: Vector3 = Game.pad_dir.normalized()
		var axis := a.cross(b)
		_r = Basis.IDENTITY if axis.length() < 1e-6 else Basis(axis.normalized(), a.angle_to(b))
		_have = true
	return _r


static func game_dir(lat: float, lon: float) -> Vector3:
	return game_from_geo() * geo_dir(lat, lon)


## Folder with the downloaded NASA textures + built regions (tools/fetch_assets.sh).
static func asset_dir() -> String:
	var base := OS.get_environment("XDG_DATA_HOME")
	if base == "":
		base = OS.get_environment("HOME") + "/.local/share"
	return base + "/" + ASSET_DIR


## Load an image from the asset cache as a mipmapped texture, or null when missing.
static func tex(name: String) -> Texture2D:
	var p := asset_dir() + "/" + name
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ======================================================================== ISS
## Built-in ISS elements, used when tools/fetch_assets.sh (run.sh refreshes it daily) could not
## fetch a fresh TLE from CelesTrak into assets/iss.tle.
const ISS_TLE_FALLBACK := ["1 25544U 98067A   26292.43498098  .00007189  00000+0  13878-3 0  9990",
	"2 25544  51.6326  45.2419 0006754 282.9887  77.0347 15.48939196591015"]


static func iss_tle() -> Array:
	var p := asset_dir() + "/iss.tle"
	if FileAccess.file_exists(p):
		var l1 := ""
		for ln in FileAccess.get_file_as_string(p).split("\n"):
			if ln.begins_with("1 "):
				l1 = ln.strip_edges()
			elif ln.begins_with("2 ") and l1 != "":
				return [l1, ln.strip_edges(), "fresh"]
	return [ISS_TLE_FALLBACK[0], ISS_TLE_FALLBACK[1], "built-in"]


## ISS ground position now (two-body + J2 from the TLE; a few tens of km off after a day, fine
## for a 600 km game planet). {lat, lon, pos, vel_dir (geo frame, Earth-fixed), age_h, src}
static func iss_now(unix: float = -1.0) -> Dictionary:
	if unix < 0.0:
		unix = Time.get_unix_time_from_system()
	var tle := iss_tle()
	var l1: String = tle[0]
	var l2: String = tle[1]
	var ep := l1.substr(18, 14)
	var yr := 2000 + int(ep.substr(0, 2))
	var t_ep := Time.get_unix_time_from_datetime_dict({"year": yr, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}) + (float(ep.substr(2)) - 1.0) * 86400.0
	var inc := deg_to_rad(float(l2.substr(8, 8)))
	var raan0 := deg_to_rad(float(l2.substr(17, 8)))
	var ecc := float("0." + l2.substr(26, 7).strip_edges())
	var argp0 := deg_to_rad(float(l2.substr(34, 8)))
	var m0 := deg_to_rad(float(l2.substr(43, 8)))
	var n := float(l2.substr(52, 11)) * TAU / 86400.0
	var a := pow(3.986004418e14 / (n * n), 1.0 / 3.0)
	var k := 1.5 * n * 1.08263e-3 * pow(6378137.0 / a, 2.0) / pow(1.0 - ecc * ecc, 2.0)
	var ecef := func(tt: float) -> Vector3:
		var dt := tt - t_ep
		var raan := raan0 - k * cos(inc) * dt
		var argp := argp0 + 0.5 * k * (5.0 * cos(inc) * cos(inc) - 1.0) * dt
		var mm := fmod(m0 + n * dt, TAU)
		var ea := mm
		for i in 8:
			ea -= (ea - ecc * sin(ea) - mm) / (1.0 - ecc * cos(ea))
		var nu := 2.0 * atan2(sqrt(1.0 + ecc) * sin(ea * 0.5), sqrt(1.0 - ecc) * cos(ea * 0.5))
		var r := a * (1.0 - ecc * cos(ea))
		var u := argp + nu
		var x := r * (cos(raan) * cos(u) - sin(raan) * sin(u) * cos(inc))
		var y := r * (sin(raan) * cos(u) + cos(raan) * sin(u) * cos(inc))
		var z := r * sin(u) * sin(inc)
		var th := deg_to_rad(fmod(280.46061837 + 360.98564736629 * (tt / 86400.0 + 2440587.5 - 2451545.0), 360.0))
		var xe := x * cos(th) + y * sin(th)
		var ye := -x * sin(th) + y * cos(th)
		return Vector3(ye, z, -xe)          # ECEF -> geo frame (see geo_dir)
	var p0: Vector3 = ecef.call(unix)
	var p1: Vector3 = ecef.call(unix + 10.0)
	var d := p0.normalized()
	return {"lat": rad_to_deg(asin(d.y)), "lon": rad_to_deg(atan2(d.x, -d.z)), "pos": d,
		"vel_dir": (p1 - p0).normalized(), "alt_km": (p0.length() - 6371000.0) / 1000.0,
		"age_h": (unix - t_ep) / 3600.0, "src": tle[2]}
