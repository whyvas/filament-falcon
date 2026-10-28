extends Node
## Headless nav map test (`-- --nav-map-test`, a few seconds): the NavMap globe / ground-track
## inset with no NASA assets (procedural fallback) plus a fake area and OSM overlay. ONLY runs with
## XDG_DATA_HOME pointing at a throw-away folder:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path game -- --nav-map-test
## Exit code 0 = pass.

var _ok := true


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_ok = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _place(body: CelestialBody, dir: Vector3, alt: float, speed: float) -> void:
	var sim: ShipSim = Game.sim
	sim.pos = body.pos.copy()
	sim.pos.add(dir.normalized() * (body.radius + alt))
	var t := dir.cross(Vector3.UP)
	t = Vector3(1, 0, 0) if t.length() < 1e-3 else t.normalized()
	sim.vel = body.vel + t * speed
	sim.dominant = body


func _run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if xdg == "" or xdg.begins_with(OS.get_environment("HOME") + "/.local"):
		print("NAV MAP TEST: refusing to run without a throw-away XDG_DATA_HOME")
		get_tree().quit(2)
		return
	# fake area pack registry entry + OSM overlay around Fredericton
	var ad := EarthTerrain.areas_dir() + "/fredericton"
	DirAccess.make_dir_recursive_absolute(ad)
	var fa := FileAccess.open(ad + "/area.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"name": "Fredericton", "bbox": [45.85, -66.8, 46.05, -66.5]}))
	fa.close()
	var od := Geo.asset_dir() + "/overlays"
	DirAccess.make_dir_recursive_absolute(od)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.9, 0.6))
	img.save_png(od + "/fredericton.png")
	var fo := FileAccess.open(od + "/fredericton.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify({"name": "fredericton", "bbox": [45.85, -66.8, 46.05, -66.5], "image": "fredericton.png",
		"places": [{"name": "Fredericton", "lat": 45.96, "lon": -66.64, "kind": "city"}]}))
	fo.close()
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child(vp)
	var nm := NavMap.new()
	vp.add_child(nm)
	nm.position = Vector2.ZERO
	nm.size = Vector2(900, 600)
	NavMap.scan_ground_data(true)
	await _frames(6)
	_check(NavMap.areas.size() == 1 and NavMap.overlays.size() == 1, "area + overlay scanned (%d, %d)" % [NavMap.areas.size(), NavMap.overlays.size()])
	_check(nm._g_drawn.has(nm._globe), "globe rendered (on the pad)")
	_check(nm._globe.mat.get_shader_parameter("use_tex") == false, "no assets -> procedural globe")
	var home := Geo.game_dir(45.96, -66.64)
	_place(Game.earth, home, 300000.0, 7700.0)
	for i in 60:
		await _frames(1)
		if nm._ground.mat.get_shader_parameter("use_osm") == true:
			break
		nm._ground._since = 1e9    # skip the throttle while waiting for the overlay decode
	_check(nm._ground_rect().size.x > 0.0, "ground inset shown in low orbit")
	_check(nm._ground.mat.get_shader_parameter("use_osm") == true, "OSM overlay bound over Fredericton")
	var f := nm._ground_frame()
	_check(absf(float(f["lat"]) - 45.96) < 0.5 and absf(float(f["lon"]) + 66.64) < 0.5, "sub-point %.2f, %.2f" % [f["lat"], f["lon"]])
	for z in [40.0, 0.2, 1.0]:
		nm.zoom = z
		await _frames(3)
	_check(nm._others.has("moon") and nm._g_drawn.has(nm._others["moon"]), "moon globe rendered")
	_place(Game.earth, Vector3(1, 0.2, 0.3), Game.earth.radius * 2.0, 4000.0)
	await _frames(3)
	_check(nm._ground_rect().size.x == 0.0, "no inset in high orbit")
	_place(Game.moon, Vector3(0.3, 0.4, 1), 200000.0, 1500.0)
	await _frames(4)
	_check(nm._globe.mat.get_shader_parameter("kind") == 1, "moon dominant -> moon globe")
	_check(nm._ground_rect().size.x > 0.0, "moon ground inset")
	nm.size = Vector2(300, 200)
	await _frames(3)
	_check(nm._ground_rect().size.x == 0.0, "no inset on a tiny map")
	vp.queue_free()
	await _frames(2)
	NavMap.wait_overlay_loads()
	print("NAV MAP TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)
