class_name CamFeedView
extends SubViewportContainer
## A live camera picture for the console / Commander screen (docking, arm or chase camera).
## Only renders while it is actually visible, so hidden pages cost nothing.

var kind := "DOCKING CAMERA"     # DOCKING CAMERA | ARM CAMERA | CHASE CAMERA | AUTO (follows the Ops mode)
var vp: SubViewport
var cam: Camera3D
var overlay: CameraOverlay


func _ready() -> void:
	stretch = true
	vp = SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_2X
	vp.audio_listener_enable_3d = false
	add_child(vp)
	cam = Camera3D.new()
	cam.near = 0.3
	cam.far = 2.5e5
	vp.add_child(cam)
	cam.current = true
	overlay = CameraOverlay.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(overlay)


func current_kind() -> String:
	if kind != "AUTO":
		return kind
	match Game.ops_mode:
		1:
			return "ARM CAMERA"
		0:
			return "DOCKING CAMERA"
	return "CHASE CAMERA"


func _process(_dt: float) -> void:
	var on := is_visible_in_tree() and size.x > 8.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var w: WorldView = get_tree().get_first_node_in_group("world")
	if w == null or Game.sim == null:
		return
	var k := current_kind()
	overlay.kind = k
	cam.fov = 60.0 if k == "CHASE CAMERA" else 55.0
	match k:
		"DOCKING CAMERA":
			cam.global_transform = w.docking_cam_xform()
		"ARM CAMERA":
			cam.global_transform = w.arm_cam_xform()
		_:
			var sim: ShipSim = Game.sim
			var back := sim.basis * Vector3(0, 6, 34)
			cam.global_transform = Transform3D(Basis.IDENTITY, back).looking_at(Vector3.ZERO, sim.basis.y)
