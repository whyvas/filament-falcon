extends Node
## Headless AREAS map layer test (`-- --map-layer-test`, a few seconds): the AreaMap without a
## layer (BUILD MAP LAYER button shown), then a small synthetic maps/test.ffml (roads of every
## tier, a river, a lake, a city / town / village / hamlet) loaded in the background, drawn at
## several zooms (tiers and names appear as you zoom in) and culled when out of view. ONLY runs
## with XDG_DATA_HOME pointing at a throw-away folder:
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path game -- --map-layer-test
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


func _line(b: PackedByteArray, kind: int, tier: int, levels: Array) -> void:
	b.append_array(PackedByteArray([kind, tier, 0, 0]))
	for pts: Array in levels:
		var h := PackedByteArray()
		h.resize(4)
		h.encode_u32(0, pts.size())
		b.append_array(h)
		var ints := PackedInt32Array()
		for p: Vector2 in pts:      # (lon, lat)
			ints.append(int(p.x * 1e6))
			ints.append(int(p.y * 1e6))
		b.append_array(ints.to_byte_array())


func _write_layer(path: String) -> void:
	var meta := {"src": "test", "bbox": [45.5, -67.2, 46.4, -66.0], "counts": {},
		"places": [["Bigcity", "city", 60000, 45.96, -66.64], ["Smalltown", "town", 5000, 45.6, -66.1],
			["Littlevillage", "village", 300, 46.1, -66.8], ["Tinyhamlet", "hamlet", 20, 45.93, -66.58]]}
	var js := JSON.stringify(meta).to_utf8_buffer()
	var b := "FFML".to_ascii_buffer()
	var h := PackedByteArray()
	h.resize(8)
	h.encode_u32(0, 1)
	h.encode_u32(4, js.size())
	b.append_array(h)
	b.append_array(js)
	var mw := [Vector2(-67.1, 45.6), Vector2(-66.64, 45.96), Vector2(-66.1, 46.3)]
	_line(b, 0, 0, [mw, mw, mw])                                  # motorway: all levels
	var pr := [Vector2(-66.9, 45.96), Vector2(-66.3, 45.95)]
	_line(b, 0, 1, [[], pr, pr])                                  # primary: levels 1 + 2
	var te := [Vector2(-66.66, 45.95), Vector2(-66.62, 45.97)]
	_line(b, 0, 3, [[], [], te])                                  # tertiary: level 2 only
	var rv := [Vector2(-67.0, 45.9), Vector2(-66.7, 45.94), Vector2(-66.3, 45.92)]
	_line(b, 1, 0, [rv, rv, rv])
	var lk := [Vector2(-66.5, 46.1), Vector2(-66.3, 46.1), Vector2(-66.3, 46.2), Vector2(-66.5, 46.2)]
	_line(b, 2, 0, [lk, lk, lk])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _view(am: AreaMap, c: Vector2, dpp: float) -> void:
	am.center = c
	am.deg_per_px = dpp
	am.queue_redraw()
	await _frames(3)


func _run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if xdg == "" or xdg.begins_with(OS.get_environment("HOME") + "/.local"):
		print("MAP LAYER TEST: refusing to run without a throw-away XDG_DATA_HOME")
		get_tree().quit(2)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child(vp)
	var am := AreaMap.new()
	am.size = Vector2(900, 600)
	vp.add_child(am)
	await _frames(4)
	_check(MapLayer.layers.is_empty() and am.build_btn.visible, "no layer: map draws, BUILD MAP LAYER button shown")
	var pressed := [false]
	am.build_layer.connect(func() -> void: pressed[0] = true)
	am.build_btn.pressed.emit()
	_check(pressed[0] and am.build_btn.disabled, "button emits build_layer and disables while building")
	DirAccess.make_dir_recursive_absolute(MapLayer.maps_dir())
	_write_layer(MapLayer.maps_dir() + "/test.ffml")
	MapLayer.poll(true)
	var t0 := Time.get_ticks_msec()
	while MapLayer.layers.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		await _frames(1)
	await _frames(3)
	_check(MapLayer.layers.size() == 1, "layer loaded in the background")
	_check(not am.build_btn.visible, "button hidden once a layer exists")
	var c := Vector2(-66.64, 45.96)
	await _view(am, c, 0.3)
	_check(MapLayer.drawn.x == 3 and MapLayer.drawn.y == 0, "world zoom: motorway + river + lake, no names (%s)" % MapLayer.drawn)
	await _view(am, c, 0.04)
	_check(MapLayer.drawn.x == 3 and MapLayer.drawn.y == 1, "region zoom: still level 0, the city name (%s)" % MapLayer.drawn)
	await _view(am, c, 0.01)
	_check(MapLayer.drawn.x == 4 and MapLayer.drawn.y == 2, "county zoom: + primary, city + town (%s)" % MapLayer.drawn)
	await _view(am, c, 0.0008)
	_check(MapLayer.drawn.x == 5 and MapLayer.drawn.y == 3, "street zoom: + tertiary, city + village + hamlet (%s)" % MapLayer.drawn)
	await _view(am, Vector2(20.0, -30.0), 0.01)
	_check(MapLayer.drawn == Vector2i.ZERO, "culled when out of view (%s)" % MapLayer.drawn)
	var lay: Dictionary = MapLayer.layers.values()[0]
	var lakes := 0
	for e: Dictionary in lay["levels"][2]:
		if int(e["kind"]) == 2 and e.has("mesh"):
			lakes += 1
	_check(lakes == 1, "lake triangulated into a mesh")
	am.queue_free()
	await _frames(2)
	_check(MapLayer.layers.is_empty() and not MapLayer.loading(), "released when the last map leaves")
	print("MAP LAYER TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)
