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
