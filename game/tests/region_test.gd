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
	get_tree().quit(0)
