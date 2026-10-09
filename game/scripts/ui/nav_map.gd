class_name NavMap
extends Control
## Top-down orbit map for the NAV page. Draws the dominant body, its atmosphere, the
## ship's current conic (from OrbitMath), Ap/Pe markers, the target and the Moon.

var zoom := 1.0          # multiplier on the auto scale
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	clip_contents = true


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


## Map the orbital plane (world XZ, seen from +Y / north) to screen.
func _to_screen(rel: Vector3, center: Vector2, k: float) -> Vector2:
	return center + Vector2(rel.x, rel.z) * k


func _draw() -> void:
	var sim: ShipSim = Game.sim
	var dom: CelestialBody = sim.dominant
	if dom == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.05))
	for i in 12:
		var gx := size.x * i / 12.0
		draw_line(Vector2(gx, 0), Vector2(gx, size.y), Color(0.2, 0.5, 0.8, 0.08))
	for i in 8:
		var gy := size.y * i / 8.0
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.2, 0.5, 0.8, 0.08))
	var r := sim.pos.rel(dom.pos)
	var v := sim.vel - dom.vel
	var el := OrbitMath.elements(r, v, dom.gm, dom.radius)
	var extent := maxf(r.length(), dom.radius * 1.6)
	if not el["escaping"]:
		extent = maxf(extent, float(el["a"]) * (1.0 + float(el["e"])))
	extent = minf(extent, dom.soi if dom.soi > 0.0 else extent)
	var k := minf(size.x, size.y) * 0.46 / extent * zoom
	var c := size * 0.5
	# Body + atmosphere
	if dom.atmo_top > 0.0:
		draw_circle(c, (dom.radius + dom.atmo_top) * k, Color(0.3, 0.6, 1.0, 0.18))
	draw_circle(c, dom.radius * k, Color(0.15, 0.35, 0.7) if dom.id == "earth" else Color(0.45, 0.45, 0.48))
	draw_string(font, c + Vector2(-60, 8), dom.display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 1, 1, 0.8))
	# Orbit
	var pts: PackedVector3Array = OrbitMath.sample_conic(el, 256)
	var line := PackedVector2Array()
	for p in pts:
		if p.length() < dom.radius * 0.999 and line.size() > 1:
			draw_polyline(line, Color(0.3, 1.0, 0.5), 3.0)
			line = PackedVector2Array()
			continue
		line.append(_to_screen(p, c, k))
	if line.size() > 1:
		draw_polyline(line, Color(0.3, 1.0, 0.5), 3.0)
	# Ap / Pe
	var ev: Vector3 = el["ecc_vec"]
	if ev.length() > 0.001:
		var e_dir := ev.normalized()
		var p_r: float = el["p"] / (1.0 + float(el["e"]))
		var pe := _to_screen(e_dir * p_r, c, k)
		draw_circle(pe, 9.0, Color(1, 0.8, 0.2))
		draw_string(font, pe + Vector2(12, -8), "Pe %s" % Hud._fmt_dist(float(el["pe_alt"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.8, 0.2))
		if not el["escaping"]:
			var a_r: float = el["p"] / (1.0 - float(el["e"]))
			var ap := _to_screen(-e_dir * a_r, c, k)
			draw_circle(ap, 9.0, Color(0.4, 0.8, 1.0))
			draw_string(font, ap + Vector2(12, -8), "Ap %s" % Hud._fmt_dist(float(el["ap_alt"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.4, 0.8, 1.0))
	# Other body (moon from earth / earth from moon)
	for b in Game.bodies:
		var bb: CelestialBody = b
		if bb == dom:
			continue
		var br := bb.pos.rel(dom.pos)
		var bp := _to_screen(br, c, k)
		var dir_clamped := bp
		var inside := Rect2(Vector2.ZERO, size).grow(-20).has_point(bp)
		if not inside:
			dir_clamped = c + (bp - c).limit_length(minf(size.x, size.y) * 0.48)
		draw_circle(dir_clamped, maxf(bb.radius * k, 6.0), Color(0.6, 0.6, 0.62))
		draw_string(font, dir_clamped + Vector2(12, 6), bb.display_name + ("" if inside else " >"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.8, 0.8))
	# Target
	var ts: Array = Game.target_state()
	if not ts.is_empty():
		var tp := _to_screen((ts[0] as BigVec).rel(dom.pos), c, k)
		draw_polyline(PackedVector2Array([tp + Vector2(0, -12), tp + Vector2(12, 0), tp + Vector2(0, 12), tp + Vector2(-12, 0), tp + Vector2(0, -12)]), Color(0.75, 0.5, 1.0), 3.0)
		draw_string(font, tp + Vector2(14, 20), str(Game.current_target().get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.5, 1.0))
	# Ship
	var sp := _to_screen(r, c, k)
	var vd := Vector2(v.x, v.z).normalized()
	var perp := Vector2(-vd.y, vd.x)
	draw_colored_polygon(PackedVector2Array([sp + vd * 18.0, sp - vd * 10.0 + perp * 10.0, sp - vd * 10.0 - perp * 10.0]), Color(1, 1, 1))
	draw_string(font, Vector2(16, 30), "MAP: top view  (zoom x%.1f)" % zoom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.5, 0.8, 1.0, 0.8))
