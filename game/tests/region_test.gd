extends Node
## Headless: build every chunk of a region (godot --headless --path game -- --region-test --region-dir=DIR)
func _ready() -> void:
	await get_tree().process_frame
	var rv := RegionView.new()
	add_child(rv)
	await get_tree().process_frame
	if rv.man.is_empty():
		print("REGION TEST: no manifest")
		get_tree().quit(1)
		return
	rv._build_water()
	for k: String in rv.man["chunks"]:
		rv._build_chunk(k)
	var meshes := 0
	var mm := 0
	for n in rv.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	for n in rv.find_children("*", "MultiMeshInstance3D", true, false):
		mm += (n as MultiMeshInstance3D).multimesh.instance_count
	var h := Game.earth.terrain_height(rv.up)
	print("REGION TEST: chunks %d  meshes %d  trees %d  ground@centre %.1f m  OK" % [rv.chunks.size(), meshes, mm, h])
	# async streaming: same chunks built on worker threads, attached one per frame
	var rv2 := RegionView.new()
	add_child(rv2)
	await get_tree().process_frame
	rv2._queue = (rv2.man["chunks"] as Array).duplicate()
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var worst := 0
	while (rv2.busy() or rv2.chunks.size() < rv.chunks.size()) and Time.get_ticks_msec() - t0 < 60000:
		var f0 := Time.get_ticks_usec()
		rv2.pump()
		worst = maxi(worst, Time.get_ticks_usec() - f0)
		frames += 1
		await get_tree().process_frame
	var meshes2 := rv2.find_children("*", "MeshInstance3D", true, false).size()
	var ok := rv2.chunks.size() == rv.chunks.size() and meshes2 > 0
	print("REGION TEST: async %d chunks, %d meshes in %d frames, worst main-thread pump %.1f ms: %s" % [rv2.chunks.size(), meshes2, frames, worst / 1000.0, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
