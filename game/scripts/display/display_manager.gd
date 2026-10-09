class_name DisplayManager
extends Node
## Owns the three views and maps them to physical screens.
## - LEFT / RIGHT: forward windows. Both cameras share the ship eye point and use
##   asymmetric (off-axis) frusta computed from the real monitor geometry, so the two
##   monitors read as one continuous windscreen (the bezel gap is a real "window post").
## - CONSOLE: the centre touchscreen UI.
## Cockpit mode: one OS window per screen (fullscreen). Dev mode: all three tiled in one window.
##
## The out-the-window outputs are generic: `out_views` (from settings display/views) lists
## them, and each is described by a physical screen rectangle in eye space
## (`screen_rect_for`), from which a generic off-axis frustum is built (`off_axis`).
## Adding more outputs (e.g. three projectors on a dome) means: add names to display/views,
## teach `screen_rect_for` their geometry, and set display/<name>_warp to a canvas_item
## shader that pre-distorts that output for the dome (the hook is already wired below).

var NEAR := 1.0     # far/near must stay <= ~1e6 (float32 frustum planes)
var FAR := 1.0e6

var world: WorldView
var vp := {}            # name -> SubViewport
var cont := {}          # name -> SubViewportContainer
var cams := {}          # "left"/"right" -> Camera3D
var huds := {}
var console: Control
var windows: Array[Window] = []
var mode := "dev"
var dev_root: Control
var out_views: Array[String] = []   # out-the-window outputs, e.g. ["left", "right"]
var solo_view := ""                 # screenshot helper: this view gets a centred, forward frustum


func setup(w: WorldView) -> void:
	world = w
	if Settings.cli.has("far"):
		FAR = float(Settings.cli["far"])
	if Settings.cli.has("near"):
		NEAR = float(Settings.cli["near"])
	out_views.clear()
	for n0 in str(Settings.get_v("display", "views")).split(",", false):
		var nn: String = n0.strip_edges()
		if nn != "" and nn != "console" and not out_views.has(nn):
			out_views.append(nn)
	if out_views.is_empty():
		out_views = ["left", "right"]
	Engine.max_fps = int(Settings.get_v("display", "max_fps"))
	var all_views: Array[String] = out_views.duplicate()
	all_views.append("console")
	for n: String in all_views:
		var c := SubViewportContainer.new()
		c.name = n.capitalize() + "View"
		c.stretch = true
		var v := SubViewport.new()
		v.name = n.capitalize() + "Viewport"
		v.size_2d_override = Vector2i(1920, 1080)
		v.size_2d_override_stretch = true
		v.handle_input_locally = false
		v.audio_listener_enable_3d = false
		c.add_child(v)
		vp[n] = v
		cont[n] = c
		if n != "console":
			var cam := Camera3D.new()
			cam.name = "Camera"
			cam.projection = Camera3D.PROJECTION_FRUSTUM
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.near = NEAR
			cam.far = FAR
			cam.cull_mask = 0xFFFFF
			v.add_child(cam)
			cam.current = true
			cams[n] = cam
			var hud := Hud.new()
			hud.name = "Hud"
			hud.side = -1 if n == "left" else 1
			_apply_warp(n)
			hud.cam = cam
			hud.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.add_child(hud)
			huds[n] = hud
		else:
			v.transparent_bg = false
			console = ConsoleUI.new()
			console.name = "Console"
			console.display = self
			console.set_anchors_preset(Control.PRESET_FULL_RECT)
			v.add_child(console)
	apply_quality()
	apply_layout()
	Settings.changed.connect(func(section: String) -> void:
		if section == "graphics":
			apply_quality()
		elif section == "display":
			Engine.max_fps = int(Settings.get_v("display", "max_fps")))


func resolved_mode() -> String:
	var m: String = str(Settings.get_v("display", "mode"))
	if m == "auto":
		m = "cockpit" if DisplayServer.get_screen_count() >= 3 and not Settings.is_headless() and not Settings.is_test_run() else "dev"
	return m


func apply_layout() -> void:
	mode = resolved_mode()
	for c in cont.values():
		var cc: Control = c
		if cc.get_parent():
			cc.get_parent().remove_child(cc)
	for w in windows:
		w.queue_free()
	windows.clear()
	if dev_root:
		dev_root.queue_free()
		dev_root = null
	var root_win := get_window()
	if mode == "cockpit":
		var fs := bool(Settings.get_v("display", "fullscreen"))
		_place_window(root_win, int(Settings.get_v("display", "console_screen")), fs)
		var host := Control.new()
		host.set_anchors_preset(Control.PRESET_FULL_RECT)
		get_parent().add_child.call_deferred(host)
		dev_root = host
		host.add_child(cont["console"])
		cont["console"].set_anchors_preset(Control.PRESET_FULL_RECT)
		for n: String in out_views:
			var w := Window.new()
			w.title = "Filament Falcon - " + n.to_upper() + " WINDOW"
			w.borderless = true
			w.unresizable = false
			w.close_requested.connect(func() -> void: pass)
			get_parent().add_child.call_deferred(w)
			w.add_child(cont[n])
			cont[n].set_anchors_preset(Control.PRESET_FULL_RECT)
			windows.append(w)
			var scr: Variant = Settings.get_v("display", n + "_screen")
			_place_window.call_deferred(w, int(scr) if scr != null else 0, fs)
	else:
		if root_win.mode == Window.MODE_FULLSCREEN or root_win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			root_win.mode = Window.MODE_WINDOWED
		_apply_vsync(root_win)
		dev_root = Control.new()
		dev_root.name = "DevTiles"
		dev_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.03, 0.05)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		dev_root.add_child(bg)
		for n: String in cont:
			dev_root.add_child(cont[n])
		get_parent().add_child.call_deferred(dev_root)
		dev_root.resized.connect(_layout_tiles)
		_layout_tiles.call_deferred()


func _place_window(w: Window, screen: int, fullscreen: bool) -> void:
	screen = clampi(screen, 0, DisplayServer.get_screen_count() - 1)
	var pos := DisplayServer.screen_get_position(screen)
	var size := DisplayServer.screen_get_size(screen)
	w.mode = Window.MODE_WINDOWED
	w.position = pos
	w.size = size
	w.current_screen = screen
	if fullscreen:
		w.mode = Window.MODE_FULLSCREEN
	w.show()
	_apply_vsync(w)


## Per-window vsync. MAILBOX = no tearing and no blocking, so a 144 Hz, a 75 Hz and a 60 Hz
## screen can all be fed from one loop (capped by Engine.max_fps) without stutter.
func _apply_vsync(w: Window) -> void:
	if Settings.is_headless():
		return
	var m := DisplayServer.VSYNC_MAILBOX
	match str(Settings.get_v("display", "vsync")):
		"fifo":
			m = DisplayServer.VSYNC_ENABLED
		"off":
			m = DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(m, w.get_window_id())


func apply_vsync_all() -> void:
	_apply_vsync(get_window())
	for w in windows:
		_apply_vsync(w)


## Optional per-output post-warp (projector dome later). Empty setting = none.
func _apply_warp(n: String) -> void:
	var path := str(Settings.get_v("display", n + "_warp")) if Settings.get_v("display", n + "_warp") != null else ""
	var c: SubViewportContainer = cont[n]
	c.material = null
	if path == "" or path == "<null>":
		return
	var sh: Shader = load(path) if ResourceLoader.exists(path) else null
	if sh == null:
		push_warning("warp shader not found for %s: %s" % [n, path])
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	c.material = mat


func _layout_tiles() -> void:
	if dev_root == null:
		return
	var s := dev_root.size
	if s.x < 10:
		s = Vector2(get_window().size)
	var nv := out_views.size()
	var tile_w := floorf(s.x / nv)
	var top_h := minf(floorf(tile_w * 9.0 / 16.0), floorf(s.y * 0.55))
	for i in nv:
		var c: Control = cont[out_views[i]]
		c.position = Vector2(i * tile_w + 2, 0)
		c.size = Vector2(tile_w - 4, top_h)
	var ch := s.y - top_h - 4
	var cw := minf(ch * 16.0 / 9.0, s.x)
	(cont["console"] as Control).position = Vector2((s.x - cw) * 0.5, top_h + 4)
	(cont["console"] as Control).size = Vector2(cw, ch)


func apply_quality() -> void:
	var q := Settings.quality_index()
	for n: String in out_views:
		var v: SubViewport = vp[n]
		v.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][q]
		v.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
		v.use_taa = q >= 3
		v.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
		v.scaling_3d_scale = 0.67 if q == 0 else 1.0
		v.use_debanding = true
		v.mesh_lod_threshold = [4.0, 2.0, 1.0, 0.5][q]
		v.positional_shadow_atlas_size = [1024, 2048, 4096, 4096][q]
	if world:
		world.apply_quality()


## Physical screen rectangle for one output, in eye space (metres; eye at origin,
## looking down -Z, +Y up): {"center": Vector3, "basis": Basis (rect's own axes;
## -Z = its normal toward the scene), "w": width, "h": height}.
## The two flat side monitors are built from the display settings; a projector dome
## would return one rectangle per projector's virtual image plane here.
func screen_rect_for(n: String) -> Dictionary:
	var W := float(Settings.get_v("display", "monitor_width_m"))
	var H := float(Settings.get_v("display", "monitor_height_m"))
	var gap := float(Settings.get_v("display", "monitor_gap_m"))
	var D := float(Settings.get_v("display", "eye_distance_m"))
	var eh := float(Settings.get_v("display", "eye_height_m"))
	var toe := deg_to_rad(float(Settings.get_v("display", "toe_in_deg")))
	var side := -1.0 if n == "left" else (1.0 if n == "right" else 0.0)
	var center := Vector3(side * (gap * 0.5 + W * 0.5 * cos(toe)) if side != 0.0 else 0.0, -eh, -D + (W * 0.5 * sin(toe) if side != 0.0 else 0.0))
	return {"center": center, "basis": Basis(Vector3.UP, -side * toe), "w": W, "h": H}


## Generic off-axis frustum through a screen rectangle.
## Returns [camera basis, size, offset] at the near plane (for Camera3D.set_frustum).
func off_axis(r: Dictionary) -> Array:
	var s := maxf(float(Settings.get_v("display", "view_scale")), 0.2)
	var yb: Basis = r["basis"]
	var cl: Vector3 = yb.inverse() * (r["center"] as Vector3)
	var dist := maxf(-cl.z, 0.05)
	var k := s * NEAR / dist
	return [yb, float(r["h"]) * k, Vector2(cl.x, cl.y) * k]


## Back-compat helper: side = -1 (left) / +1 (right).
func frustum_for(side: int) -> Array:
	return off_axis(screen_rect_for("left" if side < 0 else "right"))


func _process(_dt: float) -> void:
	if world == null:
		return
	for n: String in out_views:
		var cam: Camera3D = cams[n]
		var f := off_axis(screen_rect_for(n))
		if n == solo_view:
			# single-view screenshot: same field of view, but centred straight ahead
			f = [Basis.IDENTITY, f[1], Vector2.ZERO]
		cam.global_transform = world.rig_xform * Transform3D(f[0], Vector3.ZERO)
		if Settings.cli.has("persp"):
			cam.set_perspective(70.0, NEAR, FAR)
		else:
			cam.set_frustum(f[1], f[2], NEAR, FAR)
		# Hide the Falcon's own hull from the cockpit eye point
		cam.cull_mask = 0xFFFFF if Game.view_mode == 1 else (0xFFFFF & ~WorldView.SHIP_LAYER)


## Screenshot / demo helper (dev mode only): show one view full-window, or "" for the tiles.
func solo(which: String) -> void:
	if mode != "dev":
		return
	solo_view = which
	if which == "":
		for n in cont:
			(cont[n] as Control).visible = true
		_layout_tiles()
		return
	for n in cont:
		var c: Control = cont[n]
		c.visible = (n == which)
		if n == which:
			c.position = Vector2.ZERO
			c.size = dev_root.size
