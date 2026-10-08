class_name BigVec
extends RefCounted
## Large-coordinate position stored as hi (snapped to a 1024 m grid, exact in float32)
## plus lo (small offset). Lets a single-precision engine handle planet-scale worlds:
## differences between two BigVecs are exact near each other and accurate far away.

const CELL := 1024.0

var hi := Vector3.ZERO
var lo := Vector3.ZERO


static func from_xyz(x: float, y: float, z: float) -> BigVec:
	var b := BigVec.new()
	b.set_xyz(x, y, z)
	return b


static func from_vec(v: Vector3) -> BigVec:
	return from_xyz(v.x, v.y, v.z)


func set_xyz(x: float, y: float, z: float) -> void:
	var hx := snappedf(x, CELL)
	var hy := snappedf(y, CELL)
	var hz := snappedf(z, CELL)
	hi = Vector3(hx, hy, hz)
	lo = Vector3(x - hx, y - hy, z - hz)


func set_from(o: BigVec) -> void:
	hi = o.hi
	lo = o.lo


func copy() -> BigVec:
	var b := BigVec.new()
	b.hi = hi
	b.lo = lo
	return b


func x() -> float:
	return float(hi.x) + float(lo.x)


func y() -> float:
	return float(hi.y) + float(lo.y)


func z() -> float:
	return float(hi.z) + float(lo.z)


## Adds a small displacement (metres) and renormalises.
func add(v: Vector3) -> void:
	lo += v
	if absf(lo.x) > CELL or absf(lo.y) > CELL or absf(lo.z) > CELL:
		var s := Vector3(snappedf(lo.x, CELL), snappedf(lo.y, CELL), snappedf(lo.z, CELL))
		hi += s
		lo -= s


## Adds a large displacement given as doubles.
func add_xyz(dx: float, dy: float, dz: float) -> void:
	set_xyz(x() + dx, y() + dy, z() + dz)


## Vector from `origin` to this point, float32 (precise when close, ~cm when 1000 km away).
func rel(origin: BigVec) -> Vector3:
	return (hi - origin.hi) + (lo - origin.lo)


## Same as rel() but returned as three doubles [x, y, z] for high-precision maths.
func rel_d(origin: BigVec) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(3)
	out[0] = (float(hi.x) - float(origin.hi.x)) + (float(lo.x) - float(origin.lo.x))
	out[1] = (float(hi.y) - float(origin.hi.y)) + (float(lo.y) - float(origin.lo.y))
	out[2] = (float(hi.z) - float(origin.hi.z)) + (float(lo.z) - float(origin.lo.z))
	return out


func dist_to(o: BigVec) -> float:
	var d := rel_d(o)
	return sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])


func _to_string() -> String:
	return "BigVec(%.2f, %.2f, %.2f)" % [x(), y(), z()]
