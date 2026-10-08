class_name OrbitMath
extends RefCounted
## Keplerian elements from a state vector (relative to a dominant body).

## Returns {a, e, ap_alt, pe_alt, period, energy, h, ecc_vec, nu, time_to_ap, time_to_pe, escaping}
static func elements(r: Vector3, v: Vector3, gm: float, body_radius: float) -> Dictionary:
	var rl := float(r.length())
	var vl2 := float(v.length_squared())
	var out := {}
	if rl < 1.0 or gm <= 0.0:
		return {"a": 0.0, "e": 0.0, "ap_alt": 0.0, "pe_alt": 0.0, "period": 0.0, "escaping": false,
			"time_to_ap": 0.0, "time_to_pe": 0.0, "nu": 0.0, "ecc_vec": Vector3.ZERO, "h": Vector3.ZERO}
	var energy := vl2 * 0.5 - gm / rl
	var h := r.cross(v)
	var ecc_vec := (v.cross(h) / gm) - r / rl
	var e := float(ecc_vec.length())
	var a := -gm / (2.0 * energy) if absf(energy) > 1e-9 else 1e18
	var pe := a * (1.0 - e) if e < 1.0 else float(h.length_squared()) / gm / (1.0 + e)
	var ap := a * (1.0 + e) if e < 1.0 else INF
	out["a"] = a
	out["e"] = e
	out["energy"] = energy
	out["h"] = h
	out["p"] = float(h.length_squared()) / gm
	out["ecc_vec"] = ecc_vec
	out["pe_alt"] = pe - body_radius
	out["ap_alt"] = ap - body_radius if e < 1.0 else INF
	out["escaping"] = e >= 1.0
	out["period"] = TAU * sqrt(pow(a, 3.0) / gm) if e < 1.0 and a > 0.0 else INF
	# True anomaly
	var nu := 0.0
	if e > 1e-6:
		var cosnu := clampf(ecc_vec.dot(r) / (e * rl), -1.0, 1.0)
		nu = acos(cosnu)
		if r.dot(v) < 0.0:
			nu = TAU - nu
	out["nu"] = nu
	out["time_to_ap"] = 0.0
	out["time_to_pe"] = 0.0
	if e < 1.0 and e > 1e-6 and a > 0.0:
		var E := 2.0 * atan(sqrt((1.0 - e) / (1.0 + e)) * tan(nu * 0.5))
		var M := E - e * sin(E)
		if M < 0.0:
			M += TAU
		var n := sqrt(gm / pow(a, 3.0))
		var t_pe := (TAU - M) / n
		var t_ap := (PI - M) / n
		if t_ap < 0.0:
			t_ap += TAU / n
		out["time_to_pe"] = fmod(t_pe, TAU / n)
		out["time_to_ap"] = t_ap
	return out


## Samples the conic as points (relative to the body centre) for drawing on the nav map.
static func sample_conic(el: Dictionary, n: int = 128) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var e: float = el["e"]
	var h: Vector3 = el["h"]
	if h.length_squared() < 1e-6:
		return pts
	var ev: Vector3 = el["ecc_vec"]
	var pdir := ev.normalized() if e > 1e-6 else Vector3(1, 0, 0).slide(h.normalized()).normalized()
	var qdir := h.normalized().cross(pdir)
	var p: float = float(el.get("p", 0.0))
	if p <= 0.0:
		return pts
	var nu_max := PI if e < 1.0 else acos(-1.0 / e) * 0.97
	for i in range(n + 1):
		var nu := lerpf(-nu_max, nu_max, float(i) / n)
		var rr := p / (1.0 + e * cos(nu))
		if rr < 0.0 or rr > 1e9:
			continue
		pts.append((pdir * cos(nu) + qdir * sin(nu)) * rr)
	return pts
