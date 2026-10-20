extends Node
## Headless (godot --headless --path game -- --asset-test): every shader compiles (the dummy
## renderer still parses them) and the HD texture cache round-trips (decode -> mipmaps -> BC
## compression -> cache/tex/*.res -> reload) on tiny synthetic images in a temp data dir.
func _ready() -> void:
	await get_tree().process_frame
	var ok := true
	for f in DirAccess.get_files_at("res://shaders"):
		if not f.ends_with(".gdshader"):
			continue
		var sh: Shader = load("res://shaders/" + f)
		var good := sh != null and (not sh.code.contains("uniform ") or sh.get_shader_uniform_list().size() > 0)
		ok = ok and good
		if not good:
			print("  shader %s: FAIL" % f)
	print("ASSET TEST: shaders compile: %s" % ("ok" if ok else "FAIL"))
	var dir := Geo.asset_dir()
	if not dir.begins_with("/tmp/"):
		print("ASSET TEST: run with XDG_DATA_HOME=/tmp/... for the cache check (skipped)")
	else:
		DirAccess.make_dir_recursive_absolute(dir)
		var im := Image.create(256, 128, false, Image.FORMAT_RGB8)
		im.fill(Color(0.2, 0.4, 0.8))
		im.save_jpg(dir + "/earth_day_07_hd.jpg")
		im.fill(Color(0.5, 0.5, 1.0))
		im.save_png(dir + "/earth_normal.png")
		var g := Image.create(256, 128, false, Image.FORMAT_L8)
		g.fill(Color(1, 1, 1))
		g.save_png(dir + "/earth_mask.png")
		var fmts := []
		for pass_i in 2:
			var t0 := Time.get_ticks_usec()
			var a := Geo.hd_image("earth_day_07_hd.jpg", "color")
			var b := Geo.hd_image("earth_normal.png", "normal")
			var c := Geo.hd_image("earth_mask.png", "gray")
			var good2 := a != null and b != null and c != null and a.is_compressed() and b.is_compressed() and c.is_compressed() and a.has_mipmaps()
			fmts = [a.get_format() if a else -1, b.get_format() if b else -1, c.get_format() if c else -1]
			print("ASSET TEST: HD cache pass %d (%s): formats %s, %d us: %s" % [pass_i + 1, "build" if pass_i == 0 else "cached", str(fmts), Time.get_ticks_usec() - t0, "ok" if good2 else "FAIL"])
			ok = ok and good2
		var cached := DirAccess.get_files_at(Geo.cache_dir() + "/tex")
		ok = ok and cached.size() == 3 and fmts == [Image.FORMAT_DXT1, Image.FORMAT_RGTC_RG, Image.FORMAT_RGTC_R]
		print("ASSET TEST: cache files %s" % str(cached))
	print("ASSET TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
