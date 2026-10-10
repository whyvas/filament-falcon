class_name AdiGauge
extends Control
## Attitude director indicator ("the ball") for the kids' console: sky/ground split that
## rolls and slides with the ship's pitch and roll relative to the local horizon of the nearest
## body, a pitch ladder, roll scale and pointer, a heading strip, and the fixed ship symbol.
## Works in space too (the horizon is always the one of the planet or Moon below).

var font: Font
const SKY := Color(0.16, 0.45, 0.85)
const GROUND := Color(0.45, 0.28, 0.12)
const LINE := Color(1, 1, 1, 0.9)
const SHIP := Color(1.0, 0.85, 0.1)


func _ready() -> void:
	font = ThemeDB.fallback_font
	clip_contents = true


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## [pitch_deg, roll_deg, heading_deg] of the ship relative to the local horizon.
static func attitude(sim: ShipSim) -> Vector3:
	var up := sim.up_dir.normalized()
	var fwd := sim.forward().normalized()
	var right := (sim.basis * Vector3.RIGHT).normalized()
	var pitch := rad_to_deg(asin(clampf(fwd.dot(up), -1.0, 1.0)))
	# roll: angle of the ship's right wing below/above the horizon, measured around the nose
	var h_right := fwd.cross(up)
	var roll := 0.0
	if h_right.length() > 0.05:
		h_right = h_right.normalized()
		var ship_up := (sim.basis * Vector3.UP).normalized()
		roll = rad_to_deg(atan2(-right.dot(up), ship_up.dot(up)))
	var east := CelestialBody.east_at(up)
	var north := up.cross(east).normalized()
	var hf := fwd - up * fwd.dot(up)
	if hf.length() < 0.02:
		hf = (sim.basis * Vector3.UP) * (-1.0 if fwd.dot(up) > 0.0 else 1.0)
		hf -= up * hf.dot(up)
	var hdg := fposmod(rad_to_deg(atan2(hf.dot(east), hf.dot(north))), 360.0)
	return Vector3(pitch, roll, hdg)


func _draw() -> void:
	var sim: ShipSim = Game.sim
	if sim == null:
		return
	var att := attitude(sim)
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 6.0
	var px_per_deg := r / 40.0                  # +-40 deg visible
	var roll := deg_to_rad(att.y)
	var dir := Vector2(cos(-roll), sin(-roll))  # horizon direction on screen
	var nrm := Vector2(-dir.y, dir.x)           # points "down" toward the ground
	var hc := c + nrm * (att.x * px_per_deg)    # nose up -> horizon slides down
	# ball: sky disc, then the ground half-plane clipped to the disc
	draw_circle(c, r, SKY)
	var big := 4.0 * r
	var g_poly := PackedVector2Array([hc - dir * big, hc + dir * big, hc + dir * big + nrm * big, hc - dir * big + nrm * big])
	var circ := PackedVector2Array()
	for i in 96:
		var a := TAU * i / 96.0
		circ.append(c + Vector2(cos(a), sin(a)) * r)
	var clipped := Geometry2D.intersect_polygons(g_poly, circ)
	for poly in clipped:
		draw_colored_polygon(poly, GROUND)
	draw_line(hc - dir * r * 1.2, hc + dir * r * 1.2, LINE, 3.0)
	# pitch ladder every 10 deg (clipped to the inner circle)
	for k in range(-9, 10):
		if k == 0:
			continue
		var deg := float(k * 10)
		var pc := hc - nrm * (deg * px_per_deg)
		if pc.distance_to(c) > r * 0.8:
			continue
		var half := r * (0.22 if k % 3 == 0 else 0.13)
		draw_line(pc - dir * half, pc + dir * half, LINE, 2.0)
		draw_string(font, pc + dir * (half + 6.0) + Vector2(0, 8), str(absi(k * 10)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, LINE)
	# roll scale on the rim
	for dg: int in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(float(dg) - 90.0)
		var u := Vector2(cos(a), sin(a))
		var l := 18.0 if dg % 30 == 0 else 10.0
		draw_line(c + u * (r - l), c + u * r, Color.WHITE, 3.0)
	var pa := -roll - PI * 0.5
	var pu := Vector2(cos(pa), sin(pa))
	var pp := c + pu * (r - 22.0)
	var pt := PackedVector2Array([pp, pp + pu.rotated(2.6) * 22.0, pp + pu.rotated(-2.6) * 22.0])
	draw_colored_polygon(pt, SHIP)
	draw_arc(c, r, 0, TAU, 96, Color(0.2, 0.75, 1.0), 4.0)
	# fixed ship symbol
	draw_line(c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.12, 0), SHIP, 7.0)
	draw_line(c + Vector2(r * 0.12, 0), c + Vector2(r * 0.45, 0), SHIP, 7.0)
	draw_line(c + Vector2(-r * 0.12, 0), c + Vector2(0, r * 0.08), SHIP, 7.0)
	draw_line(c + Vector2(r * 0.12, 0), c + Vector2(0, r * 0.08), SHIP, 7.0)
	draw_circle(c, 5.0, SHIP)
	# readouts
	var tx := "PITCH %+d°   ROLL %+d°   HDG %03d°" % [int(round(att.x)), int(round(att.y)), int(round(att.z)) % 360]
	draw_string(font, Vector2(0, size.y - 8), tx, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
