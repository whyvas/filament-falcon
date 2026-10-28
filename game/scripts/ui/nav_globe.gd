class_name NavGlobe
extends SubViewport
## A planet picture for the nav map (NavMap): a 2D SubViewport holding one full-size ColorRect
## with shaders/nav_globe.gdshader (lit globe) or shaders/nav_ground.gdshader (ground-track
## close-up). It renders only when asked (UPDATE_ONCE, a few times a second at most), so the map
## costs one small quad most frames. Textures come from the 3D world's planet materials (the
## NASA Blue Marble / Black Marble / clouds / land mask and LROC / LOLA sets that
## tools/fetch_assets.sh downloads, HD when streamed in); without them the shaders draw a
## procedural planet.

const GLOBE_SHADER := preload("res://shaders/nav_globe.gdshader")
const GROUND_SHADER := preload("res://shaders/nav_ground.gdshader")

var mat: ShaderMaterial
var rect: ColorRect
var ground := false
var min_interval := 0.25        # seconds between renders (at most 4 Hz)
var max_age := 5.0              # re-render at least this often while shown (sun / clouds / HD swap)
var _since := 1e9
var _key: Array = []
var _tex_key: Array = []


func _init(ground_mode := false) -> void:
	ground = ground_mode
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(64, 64)
	mat = ShaderMaterial.new()
	mat.shader = GROUND_SHADER if ground else GLOBE_SHADER
	rect = ColorRect.new()
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(size)
	add_child(rect)


func tick(dt: float) -> void:
	_since += dt


## Render if `key` (whatever describes the picture: geometry, sun, body) changed, throttled; or
## when the picture is older than max_age. force skips the throttle (zoom, resize, body change).
func request(vp_size: Vector2i, key: Array, force := false) -> bool:
	vp_size = vp_size.clamp(Vector2i(8, 8), Vector2i(2048, 2048))
	if vp_size != size:
		size = vp_size
		force = true
	rect.size = Vector2(size)
	var changed := key != _key
	if not ((changed and (force or _since >= min_interval)) or _since >= max_age):
		return false
	_key = key
	_since = 0.0
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return true


func set_p(n: String, v: Variant) -> void:
	mat.set_shader_parameter(n, v)


# ------------------------------------------------------------------ textures
## The world's planet material for this body (WorldView.earth_mat / moon_mat), or null.
static func world_mat(body_id: String) -> ShaderMaterial:
	var w := world()
	if w == null or (body_id != "earth" and body_id != "moon"):
		return null
	var m: Variant = w.get("earth_mat" if body_id == "earth" else "moon_mat")
	return m as ShaderMaterial


## The running WorldView (main.gd's `world`), or null (tests, menus).
static func world() -> Object:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or (ml as SceneTree).current_scene == null:
		return null
	var w: Variant = (ml as SceneTree).current_scene.get("world")
	return w if w is Object and is_instance_valid(w) else null


## Borrow the body's textures from the world (no second copy in memory). Returns true when the
## real textures are bound (false = procedural fallback).
func bind_body(body_id: String) -> bool:
	var wm := world_mat(body_id)
	var real: bool = wm != null and wm.get_shader_parameter("use_tex") == true
	var tk: Array = [body_id, real]
	if real:
		if body_id == "earth":
			for n in ["day_tex", "night_tex", "cloud_tex", "mask_tex"]:
				tk.append(wm.get_shader_parameter(n))
			tk.append(wm.get_shader_parameter("use_normal") == true)
		else:
			tk.append(wm.get_shader_parameter("color_tex"))
			tk.append(wm.get_shader_parameter("height_tex"))
	if tk == _tex_key:
		return real
	_tex_key = tk
	_key = []          # new textures -> re-render
	set_p("kind", 0 if body_id == "earth" else (1 if body_id == "moon" else 2))
	set_p("use_tex", real)
	set_p("geo_from_game", Geo.game_from_geo().inverse() if body_id == "earth" else Basis.IDENTITY)
	if not real:
		set_p("use_mask", false)
		return false
	if body_id == "earth":
		set_p("day_tex", tk[2])
		set_p("night_tex", tk[3])
		set_p("cloud_tex", tk[4])
		set_p("mask_tex", tk[5])
		set_p("use_mask", bool(tk[6]) and tk[5] != null)
	else:
		set_p("day_tex", tk[2])
		if not ground:
			set_p("height_tex", tk[3])
		set_p("use_mask", false)
	return true
