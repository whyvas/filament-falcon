extends Node
## Headless AREAS job-runner test (`-- --area-runner-test`, ~15 s, downloads at most one ~12 KB
## DEM tile). ONLY runs with XDG_DATA_HOME pointing at a throw-away folder (never your real areas):
##   XDG_DATA_HOME=$(mktemp -d) godot --headless --path game -- --area-runner-test
##  1. a job queued with no runner (the old "QUEUED 0% / runner idle" state) and a job left
##     'running' by a dead runner (stale runner.pid): the AREAS page auto-starts the runner, both finish
##  2. a runner that dies at start (simulated with a sitecustomize.py that exits): the page shows
##     "RUNNER FAILED TO START" with the log, not a silent "runner idle"
## Exit code 0 = pass.

var _ok := true


func _ready() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_ok = false


func _cli(args: Array) -> Dictionary:
	var c := CommanderUI._area_cli(args)
	var out: Array = []
	OS.execute(str(c[0]), c[1], out, true)
	var lines := "".join(out).strip_edges().split("\n")
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with("{"):
			var js: Variant = JSON.parse_string(lines[i])
			return js if js is Dictionary else {}
	return {}


func _state(js: Dictionary, id: String) -> String:
	for a: Dictionary in js.get("areas", []):
		if str(a["id"]) == id:
			return str(a["state"])
	return "?"


func _run() -> void:
	var xdg := OS.get_environment("XDG_DATA_HOME")
	if xdg == "" or not (xdg.begins_with("/tmp/") or xdg.contains("test")):
		print("area-runner-test: set XDG_DATA_HOME to a throw-away folder (e.g. $(mktemp -d)); refusing to touch real data")
		get_tree().quit(2)
		return
	var areas := xdg.path_join("filament-falcon/areas")
	print("area-runner-test in ", areas)
	var c := CommanderUI.new()
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	add_child(vp)
	vp.add_child(c)
	c.size = Vector2(1920, 1080)
	await get_tree().process_frame
	# --- 1. queued + stale 'running' job, no runner
	_cli(["add", "--id", "tiny_a", "--bbox=45.962,-66.645,45.965,-66.640", "--steps", "dem"])
	_cli(["add", "--id", "tiny_b", "--bbox=45.962,-66.645,45.965,-66.640", "--steps", "dem"])
	var f := FileAccess.open(areas.path_join("runner.pid"), FileAccess.WRITE)   # dead pid
	f.store_string("999999")
	f.close()
	var sp := areas.path_join("tiny_b/status.json")
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sp))
	st["state"] = "running"
	st["step"] = "dem"
	f = FileAccess.open(sp, FileAccess.WRITE)
	f.store_string(JSON.stringify(st))
	f.close()
	for q: String in DirAccess.get_files_at(areas.path_join("queue")):
		if q.ends_with("_tiny_b.json"):
			DirAccess.remove_absolute(areas.path_join("queue").path_join(q))
	var js := _cli(["status", "--json"])
	_check(int(js.get("runner", -1)) == 0, "stale runner.pid is not taken for a live runner")
	_check(_state(js, "tiny_a") == "queued" and _state(js, "tiny_b") == "stalled", "status: tiny_a queued, tiny_b stalled (got %s / %s)" % [_state(js, "tiny_a"), _state(js, "tiny_b")])
	c.show_page("AREAS")
	var done := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().create_timer(0.5).timeout
		js = _cli(["status", "--json"])
		if _state(js, "tiny_a") == "done" and _state(js, "tiny_b") == "done":
			done = true
			break
	_check(done, "AREAS page auto-started the runner; both jobs done (%s / %s)" % [_state(js, "tiny_a"), _state(js, "tiny_b")])
	_check(FileAccess.get_file_as_string(areas.path_join("runner.log")).contains("re-queued first"), "runner.log: the stale 'running' job was resumed")
	# --- 2. a runner that dies at once
	var fake := xdg.path_join("fake_crash")
	DirAccess.make_dir_recursive_absolute(fake)
	f = FileAccess.open(fake.path_join("sitecustomize.py"), FileAccess.WRITE)
	f.store_string("import sys\nif '--wait' in sys.argv:\n    print('simulated runner crash at start'); sys.exit(3)\n")
	f.close()
	OS.set_environment("PYTHONPATH", fake)
	_cli(["add", "tiny_a"])
	c._ar["last_start"] = -1000.0
	c._ar["runner_err"] = ""
	c._area_run(true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and str(c._ar.get("runner_err", "")) == "":
		await get_tree().create_timer(0.3).timeout
	c._ar["next_poll"] = 0.0
	await get_tree().create_timer(2.5).timeout
	var err := str(c._ar.get("runner_err", ""))
	_check(err.contains("exited at once"), "failed start reported: " + err.get_slice("\n", 0))
	var rl := (c._ar["runner_lbl"] as Label).text
	_check(rl.begins_with("RUNNER FAILED TO START"), "AREAS page shows it: " + rl.get_slice("\n", 0).left(90))
	_check((c._ar["log_lbl"] as Label).text.contains("simulated runner crash"), "AREAS page shows the runner log tail")
	OS.set_environment("PYTHONPATH", "")
	print("AREA RUNNER TEST ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)
