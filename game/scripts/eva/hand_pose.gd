class_name HandPose
extends RefCounted
## Optical hand tracking (XR_EXT_hand_tracking) -> suit glove pose, from joint POSITIONS only.
##
## Godot's XRHandTracker does not hand out raw OpenXR joint orientations: it rotates every joint
## into the Godot Humanoid skeleton convention (+Y along the bone toward the fingertip, +Z out of
## the palm, X mirrored). The glove (AstronautModel) is built fingers along -Z with the palm pad
## at -Y, so feeding it the palm joint basis directly pointed the fingers out of the back of the
## hand and made them curl toward the wrist. Positions have no such convention, so the palm frame
## and the curls are both derived from them and come out the same on every runtime.
##
## Joint indices are the XRHandTracker.HandJoint values (same order as OpenXR).

const J_PALM := 0
const J_WRIST := 1
const THUMB := [2, 3, 4, 5]                 # metacarpal, proximal, distal, tip
const FINGERS := [[6, 7, 8, 9, 10], [11, 12, 13, 14, 15], [16, 17, 18, 19, 20], [21, 22, 23, 24, 25]]
const JOINTS := 26
const FINGER_FULL := deg_to_rad(230.0)     # MCP + PIP + DIP flexion of a tight fist
const THUMB_FULL := deg_to_rad(110.0)


static func joints_of(ht: XRHandTracker) -> PackedVector3Array:
	var j := PackedVector3Array()
	j.resize(JOINTS)
	for k in JOINTS:
		j[k] = ht.get_hand_joint_transform(k as XRHandTracker.HandJoint).origin
	return j


## Out-of-the-palm unit normal (world/tracking space).
static func palm_normal(j: PackedVector3Array, left: bool) -> Vector3:
	var across := j[7] - j[22]                  # pinky knuckle -> index knuckle
	var fwd := j[12] - j[J_WRIST]               # wrist -> middle knuckle
	var n := across.cross(fwd) * (-1.0 if left else 1.0)
	return n.normalized() if n.length_squared() > 1e-10 else Vector3.DOWN


## Glove frame: fingers along -Z, back of the hand +Y (palm -Y), thumb on +X for the left hand
## and -X for the right (the AstronautModel glove layout), origin at the palm centre.
static func hand_frame(j: PackedVector3Array, left: bool) -> Transform3D:
	var fwd := j[12] - j[J_WRIST]
	if fwd.length_squared() < 1e-10:
		return Transform3D(Basis.IDENTITY, j[J_PALM])
	var z := -fwd.normalized()
	var y := (-palm_normal(j, left)).slide(z)
	y = y.normalized() if y.length_squared() > 1e-10 else z.cross(Vector3.RIGHT).normalized()
	var x := y.cross(z).normalized()
	var o := j[J_PALM]
	if o.is_zero_approx():
		o = (j[J_WRIST] + j[12]) * 0.5
	return Transform3D(Basis(x, y, z), o)


## Signed flexion along a chain of joints: bends toward the palm count, hyperextension
## (bending toward the back of the hand) subtracts.
## `ax` = palm normal x hand forward: flexion turns each bone about -ax, whichever hand.
static func _chain_bend(j: PackedVector3Array, chain: Array, ax: Vector3, signed: bool) -> float:
	var tot := 0.0
	for k in chain.size() - 2:
		var b1: Vector3 = j[chain[k + 1]] - j[chain[k]]
		var b2: Vector3 = j[chain[k + 2]] - j[chain[k + 1]]
		if b1.length_squared() < 1e-10 or b2.length_squared() < 1e-10:
			continue
		var a := b1.angle_to(b2)
		if signed and b1.cross(b2).dot(ax) > 0.0:
			a = -a
		tot += a
	return tot


## Per-finger curl 0 (straight) .. 1 (fist): thumb, index, middle, ring, pinky.
static func curls(j: PackedVector3Array, left: bool) -> PackedFloat32Array:
	var ax := palm_normal(j, left).cross(j[12] - j[J_WRIST])
	var out := PackedFloat32Array([clampf(_chain_bend(j, THUMB, ax, false) / THUMB_FULL, 0.0, 1.0)])
	for f: Array in FINGERS:
		out.append(clampf(_chain_bend(j, f, ax, true) / FINGER_FULL, 0.0, 1.0))
	return out


## Synthetic skeleton for tests: a hand in its own glove frame (fingers -Z, back +Y), every
## finger joint flexed by `flex` radians toward the palm, then placed by `xf`.
static func synthetic(left: bool, flex: float, xf: Transform3D) -> PackedVector3Array:
	var sg := 1.0 if left else -1.0             # thumb side (+X left, -X right)
	var j := PackedVector3Array()
	j.resize(JOINTS)
	j[J_PALM] = Vector3(0, 0, 0)
	j[J_WRIST] = Vector3(0, 0, 0.05)
	var lens := [[0.045, 0.04, 0.025, 0.02], [0.045, 0.045, 0.028, 0.022], [0.045, 0.042, 0.026, 0.021], [0.045, 0.034, 0.02, 0.018]]
	for f in 4:
		var x := sg * (0.03 - f * 0.02)
		var p := Vector3(x * 0.6, 0, 0.05)
		j[FINGERS[f][0]] = p
		p = Vector3(x, 0, -0.045)                # knuckle
		j[FINGERS[f][1]] = p
		var d := Vector3(0, 0, -1)
		for s in 3:
			d = d.rotated(Vector3.RIGHT, -flex)    # toward -Y (palm)
			p += d * float(lens[f][s + 1])
			j[FINGERS[f][s + 2]] = p
	var tp := Vector3(sg * 0.02, -0.01, 0.04)
	j[THUMB[0]] = tp
	var td := Vector3(sg * 0.7, 0, -0.7).normalized()
	for s in 3:
		tp += td * 0.03
		j[THUMB[s + 1]] = tp
		td = td.rotated(Vector3.UP, sg * flex * 0.6)  # thumb folds across the palm
	for k in JOINTS:
		j[k] = xf * j[k]
	return j
