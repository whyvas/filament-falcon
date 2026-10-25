extends Node
## Headless (godot --headless --path game -- --hand-test): optical hand tracking -> glove.
## Synthetic skeletons (open hand + fist, both hands, an arbitrary tracking-space pose) are fed
## through a real XRHandTracker (joint bases in Godot's humanoid convention, as the OpenXR
## module stores them) and HandPose; checks the glove frame (fingers -Z, palm -Y, thumb side),
## the curls (open ~0, fist ~1) and that the posed AstronautModel fingertips curl toward the palm.

const HUMANOID := Basis(Quaternion(0.0, -0.70710678, 0.70710678, 0.0))

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("  %s: %s" % [what, "ok" if ok else "FAIL"])


func _tip(n: Node3D) -> Vector3:
	# the tip segment's box is centred at -0.4 * len along -Z: take its far end
	var mi := n.get_child(0) as Node3D
	return n.global_transform * (mi.position * 2.0)


func _ready() -> void:
	await get_tree().process_frame
	var model := AstronautModel.new()
	add_child(model)
	var xf := Transform3D(Basis.from_euler(Vector3(0.4, 1.1, -0.7)), Vector3(0.2, 1.3, -0.4))
	for left: bool in [true, false]:
		var s := "l" if left else "r"
		var tip_n := {}
		for flex: float in [0.0, 1.3]:
			var tag := "%s %s" % ["left" if left else "right", "fist" if flex > 0.0 else "open"]
			var raw := HandPose.synthetic(left, flex, xf)
			var ht := XRHandTracker.new()
			for k in HandPose.JOINTS:
				# what Godot's OpenXR module stores: the OpenXR joint basis (-Z to the fingertip,
				# +Y back of the hand = our glove frame here) times its humanoid bone adjustment
				ht.set_hand_joint_transform(k as XRHandTracker.HandJoint, Transform3D(xf.basis * HUMANOID, raw[k]))
			var j := HandPose.joints_of(ht)
			# the old mapping (palm joint basis straight onto the glove) points the glove's
			# fingers out of the back of the hand: that was the bug
			var old := ht.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).basis
			_check(old.z.dot(xf.basis.z) < 0.5, tag + ": raw palm joint basis is NOT the glove frame (regression guard)")
			var fr := HandPose.hand_frame(j, left)
			_check(fr.basis.z.dot(xf.basis.z) > 0.97, tag + ": fingers along glove -Z")
			_check(fr.basis.y.dot(xf.basis.y) > 0.97, tag + ": palm on glove -Y")
			_check((j[5] - fr.origin).dot(fr.basis.x) * (1.0 if left else -1.0) > 0.0, tag + ": thumb on the glove's thumb side (+X left, -X right)")
			var cu := HandPose.curls(j, left)
			print("    curls ", cu)
			var okc := true
			for k in 5:
				okc = okc and (cu[k] < 0.15 if flex == 0.0 else cu[k] > 0.7)
			_check(okc, tag + ": curls " + ("~0" if flex == 0.0 else "~1"))
			(model.parts["glove_" + s] as Node3D).global_transform = fr
			model.pose_fingers(s, cu)
			var n := -fr.basis.y
			var acc := 0.0
			for k in 4:
				acc += (_tip(model.fingers[s]["f"][k][1]) - fr.origin).dot(n)
			tip_n[flex] = acc / 4.0
		_check(tip_n[1.3] > tip_n[0.0] + 0.03 and tip_n[1.3] > 0.03, "%s: glove fingertips curl toward the palm (%.3f -> %.3f m)" % [s, tip_n[0.0], tip_n[1.3]])
	print("HAND TEST: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
